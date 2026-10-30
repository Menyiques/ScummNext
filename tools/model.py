"""Modelo de referencia del motor: lo mismo que hace el Z80, con la misma
aritmetica entera, para comparar byte a byte (tools/nexttest.py).

Reproduce el comportamiento de SCUMM v5 (como lo documenta ScummVM):

- cajas: punto mas cercano, ajustar un destino a una caja, siguiente caja
  (BOXM) y el paso de una caja a otra (findPathTowards);
- actor: andar (walkActor / actorWalkStep / calcMovementFactor), girar de
  90 en 90 grados, animaciones del costume (costumeDecodeData / increaseAnim);
- camara: seguir al actor en pasos de 8 pixeles (moveCamera);
- escala del actor segun su caja (directa o por una franja de SCAL) y dibujo
  escalado quitando filas y columnas;
- dibujo de los actores en tiles de 16x16 para los sprites del Next (de 4
  bits, o de 8 bits si el costume es de 32 colores), con el plano Z de su
  caja, en el orden de SCUMM (por y: los de delante, encima);
- objetos de la habitacion: se pintan sobre el fondo y sus planos Z segun su
  estado y el de su padre (drawRoomObjects).

La aritmetica imita a C: division que trunca hacia cero, enteros de 32 bits
que dan la vuelta y coordenadas de 16 bits.
"""
import copy

import numpy as np

import scumm as S

TICK = 4                # frames de 50 Hz por paso del motor (12,5 por segundo)
ROOM_Y0 = 44            # linea de Layer 2 donde empieza la habitacion
SCREEN_W = 320
BOXM_MAX = 0xF00         # createBoxMatrix: lo mas que el Z80 comprime (BXMAX, boxmat.asm)
CMAXW, CMAXH = 8, 8     # tiles de 16x16 como mucho por actor (128x128)
NSPR_ACTOR = 64         # sprites de los actores: 0..63 (el cursor es el 127)
SPR_BYTES = 8192        # patrones de los actores de 16 colores (SPRBUF): 64 de 4 bits (huecos 0-31)
SPR8_BYTES = 7936       # y los de 32 colores, en otra pagina: 31 de 8 bits (huecos 32-62; el 63
PAT8_SLOT = 32          # es del cursor y del medidor). Entre los dos, como mucho 64 sprites
ACTOR_BANK = 1          # banco de 16 colores del actor sin maquina virtual (el actor n: banco n)
PAL8 = 208              # costumes de 32 colores: colores de sprite 208..239
CAST_PAGE = 78          # la pagina de los actores; los costumes van antes (tras la habitacion)
COST_CACHE = 16         # costumes como mucho en la cache de una habitacion
INVALID = S.INVALID_BOX

MF_NEW_LEG, MF_IN_LEG, MF_TURN, MF_LAST_LEG = 1, 2, 4, 8
INIT_FRAME, WALK_FRAME, STAND_FRAME, TALK_START, TALK_STOP = 1, 2, 3, 4, 5


def i16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def i32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


cdiv = S.cdiv


def sqr_dist(a, b):
    dx = abs(a[0] - b[0])
    if dx >= 0x1000:
        return 0xFFFFFF
    dy = abs(a[1] - b[1])
    if dy >= 0x1000:
        return 0xFFFFFF
    return dx * dx + dy * dy


# ---------------------------------------------------------------------------
# Cajas
# ---------------------------------------------------------------------------
def closest_pt_on_line(st, en, p):
    lxdiff = en[0] - st[0]
    lydiff = en[1] - st[1]
    if en[0] == st[0]:
        rx, ry = st[0], p[1]
    elif en[1] == st[1]:
        rx, ry = p[0], st[1]
    else:
        dist = lxdiff * lxdiff + lydiff * lydiff
        if abs(lxdiff) > abs(lydiff):
            a = cdiv(st[0] * lydiff, lxdiff)
            b = cdiv(p[0] * lxdiff, lydiff)
            c = cdiv(i32(i32((a + b - st[1] + p[1]) * lydiff) * lxdiff), dist)
            rx = i16(c)
            ry = i16(cdiv(i32(c * lydiff), lxdiff) - a + st[1])
        else:
            a = cdiv(st[1] * lxdiff, lydiff)
            b = cdiv(p[1] * lydiff, lxdiff)
            c = cdiv(i32(i32((a + b - st[0] + p[0]) * lydiff) * lxdiff), dist)
            rx = i16(cdiv(i32(c * lxdiff), lydiff) - a + st[0])
            ry = i16(c)
    if abs(lydiff) < abs(lxdiff):
        if lxdiff > 0:
            if rx < st[0]:
                return st
            if rx > en[0]:
                return en
        else:
            if rx > st[0]:
                return st
            if rx < en[0]:
                return en
    else:
        if lydiff > 0:
            if ry < st[1]:
                return st
            if ry > en[1]:
                return en
        else:
            if ry > st[1]:
                return st
            if ry < en[1]:
                return en
    return (rx, ry)


def compare_slope(p1, p2, p3):
    return (p2[1] - p1[1]) * (p3[0] - p1[0]) <= (p3[1] - p1[1]) * (p2[0] - p1[0])


class Boxes:
    def __init__(self, boxes, matrix, slots=()):
        self.boxes = boxes
        self.matrix = matrix
        self.slots = list(slots)
        self.rebuilt = False            # (createBoxMatrix: la matriz ya no es la de BOXM)

    def get_scale(self, b, x, y):
        """getScale: la escala de la caja, directa o de una franja de SCAL."""
        if b == INVALID or b >= len(self.boxes):
            return 255
        sc = self.boxes[b].scale
        if not sc & 0x8000:
            return min(sc, 255)
        slot = sc & 0x7FFF
        if slot >= len(self.slots):
            return 255
        s1, y1, s2, y2 = self.slots[slot]
        if y1 == y2:
            return 255
        # la recta sigue fuera de [y1, y2] (y1 puede ser la de abajo): el original
        # hace una tabla de 200 filas (setScaleItem) y mira la y del actor en 0..199
        y = max(0, min(199, y))
        scale = s1 + cdiv((y - y1) * (s2 - s1), y2 - y1)
        return max(1, min(255, scale))

    def num(self):
        return len(self.boxes)

    def coords(self, b):
        bx = self.boxes[b]
        return [tuple(bx.ul), tuple(bx.ur), tuple(bx.lr), tuple(bx.ll)]

    def flags(self, b):
        return self.boxes[b].flags if b < len(self.boxes) else 0

    def mask(self, b):
        return self.boxes[b].mask if b < len(self.boxes) else 0

    def in_box(self, b, x, y):
        """checkXYInBoxBounds."""
        if b < 0 or b == INVALID or b >= len(self.boxes):
            return False
        ul, ur, lr, ll = self.coords(b)
        xs = (ul[0], ur[0], lr[0], ll[0])
        ys = (ul[1], ur[1], lr[1], ll[1])
        if x < min(xs) or x > max(xs) or y < min(ys) or y > max(ys):
            return False
        p = (x, y)
        if (ul == ur and lr == ll) or (ul == ll and ur == lr):
            if sqr_dist(p, closest_pt_on_line(ul, lr, p)) <= 4:
                return True
        return (compare_slope(ul, ur, p) and compare_slope(ur, lr, p) and
                compare_slope(lr, ll, p) and compare_slope(ll, ul, p))

    def closest_pt_on_box(self, b, x, y):
        ul, ur, lr, ll = self.coords(b)
        p = (x, y)
        best = 0xFFFFFF
        out = (0, 0)
        for s, e in ((ul, ur), (ur, lr), (lr, ll), (ll, ul)):
            t = closest_pt_on_line(s, e, p)
            d = sqr_dist(p, t)
            if d < best:
                best = d
                out = t
        return best, out

    def quick_reject(self, b, x, y, th):
        ul, ur, lr, ll = self.coords(b)
        xs = (ul[0], ur[0], lr[0], ll[0])
        ys = (ul[1], ur[1], lr[1], ll[1])
        return (x - th > max(xs) or x + th < min(xs) or
                y - th > max(ys) or y + th < min(ys))

    def box_scale(self, b):
        """getBoxScale (16 bits; 255 sin caja)."""
        if b == INVALID or b >= len(self.boxes):
            return 255
        return self.boxes[b].scale & 0xFFFF

    def adjust_xy(self, x, y, player=True):
        """adjustXYToBeInBox: (x, y, caja). Las cajas invisibles no valen, salvo las
        que son solo del jugador para quien no lo es."""
        rx, ry, rbox = x, y, INVALID
        n = len(self.boxes) - 1
        if n < 1:
            return rx, ry, rbox
        for th in (30, 80, 0):
            best = 0xFFFF
            best_box = INVALID
            for b in range(n, 0, -1):
                f = self.flags(b)
                if f & 0x80 and not (f & 0x20 and not player):
                    continue
                if th and self.quick_reject(b, x, y, th):
                    continue
                if self.in_box(b, x, y):
                    return x, y, b
                d, (tx, ty) = self.closest_pt_on_box(b, x, y)
                if d < best:
                    rx, ry = tx, ty
                    if d == 0:
                        return rx, ry, b
                    best = d
                    best_box = b
            if th == 0 or th * th >= best:
                return rx, ry, best_box
        return rx, ry, rbox

    def next_box(self, frm, to):
        if frm == to:
            return to
        if to == INVALID:
            return -1
        if frm == INVALID:
            return to
        m = self.matrix
        o = 0
        for _ in range(frm):
            while m[o] != 0xFF:
                o += 3
            o += 1
        dest = -1
        while m[o] != 0xFF:
            if m[o] <= to <= m[o + 1]:
                dest = m[o + 2] - 256 if m[o + 2] & 0x80 else m[o + 2]
            o += 3
        return dest


def _overlap(a1, a2, b1, b2):
    """Los tramos [a1, a2] y [b1, b2] se solapan (tocarse en un extremo no vale, salvo
    que alguno sea un punto)."""
    lo2, hi2 = min(a1, a2), max(a1, a2)
    lo, hi = min(b1, b2), max(b1, b2)
    return not (hi < lo2 or lo > hi2 or ((lo == hi2 or hi == lo2) and hi2 != lo2 and lo != hi))


def boxes_touch(c1, c2):
    """areBoxesNeighbors (boxes.cpp) sin los flags: algun lado de una caja y alguno de
    la otra en la misma recta vertical u horizontal, solapandose. c1, c2: las cuatro
    esquinas (ul, ur, lr, ll); se giran las dos, 16 parejas de lados."""
    box2 = [tuple(p) for p in c1]
    box = [tuple(p) for p in c2]
    for _ in range(4):
        for _ in range(4):
            (ax, ay), (bx, by) = box2[0], box2[1]
            (cx, cy), (dx, dy) = box[0], box[1]
            if bx == ax and cx == ax and dx == ax and _overlap(ay, by, cy, dy):
                return True
            if by == ay and cy == ay and dy == ay and _overlap(ax, bx, cx, dx):
                return True
            box2 = box2[1:] + box2[:1]
        box = box[1:] + box[:1]
    return False


def box_near_bits(coords):
    """La tabla de vecinas que lleva la habitacion para createBoxMatrix: un bit por
    pareja i < j (0-1, 0-2 ... 0-(n-1), 1-2 ...), el primero en el bit 0. Las cajas no
    se mueven, asi que basta con hacerla al convertir (y vale en los dos sentidos)."""
    n = len(coords)
    out = bytearray((n * (n - 1) // 2 + 7) // 8)
    k = 0
    for i in range(n - 1):
        for j in range(i + 1, n):
            if boxes_touch(coords[i], coords[j]):
                out[k >> 3] |= 1 << (k & 7)
            k += 1
    return bytes(out)


def box_matrix(near, flags):
    """createBoxMatrix (calcItineraryMatrix y la compresion de boxes.cpp): con la tabla
    de vecinas y los flags de ahora (una invisible, $80, no es vecina de nadie), el
    camino mas corto de cada caja a cada otra por Kleene, y la matriz como BOXM: por
    caja, tripletas (desde, hasta, por donde) y un $FF. (ScummVM pone el $FF delante de
    cada fila y otro al final, y getBoxMatrixBaseAddr se salta el primero: es lo mismo.)"""
    n = len(flags)
    dist = [[255] * n for _ in range(n)]
    it = [[255] * n for _ in range(n)]
    for i in range(n):
        dist[i][i], it[i][i] = 0, i
    k = 0
    for i in range(n - 1):
        for j in range(i + 1, n):
            if near[k >> 3] >> (k & 7) & 1 and not (flags[i] | flags[j]) & 0x80:
                dist[i][j] = dist[j][i] = 1
                it[i][j], it[j][i] = j, i
            k += 1
    for k in range(n):
        dk = dist[k]
        for i in range(n):
            dik = dist[i][k]
            if i == k or dik == 255:            # (no puede mejorar nada)
                continue
            di, ti, tk = dist[i], it[i], it[i][k]
            for j in range(n):
                if dk[j] != 255 and dik + dk[j] < di[j]:
                    di[j] = dik + dk[j]
                    ti[j] = tk
    out = bytearray()
    for i in range(n):
        j = 0
        while j < n:
            v = it[i][j]
            if v != 255:
                out.append(j)
                while j < n - 1 and it[i][j + 1] == v:
                    j += 1
                out += bytes((j, v))
            j += 1
        out.append(0xFF)
    return bytes(out)


def find_path_towards(boxes, actor, b1n, b2n, b3n):
    """findPathTowards: (True, None) si ya puede ir recto; (False, punto) si no."""
    box1 = boxes.coords(b1n)
    box2 = boxes.coords(b2n)
    px, py = actor.x, actor.y
    for _ in range(4):
        for _ in range(4):
            ul1, ur1, ul2, ur2 = list(box1[0]), list(box1[1]), list(box2[0]), list(box2[1])
            if ul1[0] == ur1[0] and ul1[0] == ul2[0] and ul1[0] == ur2[0]:
                if ul1[1] > ur1[1]:
                    ul1[1], ur1[1] = ur1[1], ul1[1]
                if ul2[1] > ur2[1]:
                    ul2[1], ur2[1] = ur2[1], ul2[1]
                if not (ul1[1] > ur2[1] or ul2[1] > ur1[1] or
                        ((ur1[1] == ul2[1] or ur2[1] == ul1[1]) and
                         ul1[1] != ur1[1] and ul2[1] != ur2[1])):
                    pos = py
                    if b2n == b3n:
                        dx = actor.dest_x - px
                        dy = actor.dest_y - py
                        bdx = ul1[0] - px
                        if dx != 0:
                            dy *= bdx
                            t = cdiv(dy, dx)
                            if t == 0 and (dy <= 0 or dx <= 0) and (dy >= 0 or dx >= 0):
                                t = -1
                            pos = py + t
                    q = max(pos, ul2[1])
                    q = min(q, ur2[1])
                    q = max(q, ul1[1])
                    q = min(q, ur1[1])
                    if q == pos and b2n == b3n:
                        return True, None
                    return False, (ul1[0], i16(q))
            if ul1[1] == ur1[1] and ul1[1] == ul2[1] and ul1[1] == ur2[1]:
                if ul1[0] > ur1[0]:
                    ul1[0], ur1[0] = ur1[0], ul1[0]
                if ul2[0] > ur2[0]:
                    ul2[0], ur2[0] = ur2[0], ul2[0]
                if not (ul1[0] > ur2[0] or ul2[0] > ur1[0] or
                        ((ur1[0] == ul2[0] or ur2[0] == ul1[0]) and
                         ul1[0] != ur1[0] and ul2[0] != ur2[0])):
                    pos = px
                    if b2n == b3n:
                        dx = actor.dest_x - px
                        dy = actor.dest_y - py
                        bdy = ul1[1] - py
                        if dy != 0:
                            pos += cdiv(dx * bdy, dy)
                    q = max(pos, ul2[0])
                    q = min(q, ur2[0])
                    q = max(q, ul1[0])
                    q = min(q, ur1[0])
                    if q == pos and b2n == b3n:
                        return True, None
                    return False, (i16(q), ul1[1])
            box1 = box1[1:] + box1[:1]
        box2 = box2[1:] + box2[:1]
    return False, (0, 0)


# ---------------------------------------------------------------------------
# Direcciones
# ---------------------------------------------------------------------------
def to_simple_dir(d):
    for i, (lo, hi) in enumerate(((71, 109), (109, 251), (251, 289))):
        if lo <= d <= hi:
            return i + 1
    return 0


def normalize_angle(a):
    return to_simple_dir((a + 360) % 360) * 90


def new_dir_to_old_dir(d):
    if 71 <= d <= 109:
        return 1
    if 109 <= d <= 251:
        return 2
    if 251 <= d <= 289:
        return 0
    return 3


def angle_from_pos(x, y):
    if abs(y) * 2 < abs(x):
        return 90 if x > 0 else 270
    return 180 if y > 0 else 0


# ---------------------------------------------------------------------------
# Actor
# ---------------------------------------------------------------------------
OLD_TO_NEW = (270, 90, 180, 0)
TURN_TABLE = (0, 2, 2, 3, 2, 1, 2, 3, 0, 1, 2, 1, 0, 1, 0, 3)     # updateActorDirection
CLASS_NEVER_CLIP, CLASS_YFLIP, CLASS_XFLIP, CLASS_PLAYER, CLASS_UNTOUCHABLE = 20, 29, 30, 31, 32
NO_STRIP = 0xFFFF
SPECIAL_FRAMES = {0x38: "init_frame", 0x39: "walk_frame", 0x3A: "stand_frame",
                  0x3B: "talk_start", 0x3C: "talk_stop"}
ACTOR_REC = 237         # bytes de un actor (la ficha del Z80: A_* y R_* en actor.asm)


def old_dir_to_new_dir(d):
    return OLD_TO_NEW[d & 3]


class Actor:
    """Un actor de SCUMM v5 (actor.cpp de ScummVM 2.8). Con world es uno de los 13
    de la maquina virtual (World): su habitacion, su costume (de la cache de la
    habitacion), sus fotogramas, su velocidad, su escala... Sin world es el actor
    solo del motor (las pruebas sin scripts): siempre en la habitacion y con el
    costume cost."""

    def __init__(self, cost=None, number=1, world=None):
        self.number = number
        self.w = world
        self.cost = cost
        self.boxes = None
        self.init_actor(-1)
        if cost is not None:
            self.costume = 1
            self.visible = True
            self.palette = [0xFF] * 32

    # --- los datos (initActor) ---
    def init_actor(self, mode):
        if mode == -1:
            self.top = self.bottom = 0
            self.strip0 = self.strip1 = NO_STRIP
            self.needs_init = False
            self.visible = False
            self.speedx, self.speedy = 8, 2
            self.frame = 0
            self.box = 0
            self.anim_progress = 0
            self.anim_counter = 0
            self.sound_counter = 0
            self.palette = [0] * 32
            self.reset_cost(0)
            self.dest_x = self.dest_y = 0
            self.dest_box = 0
            self.dest_dir = 0
            self.cur_box = 0
            self.cur_x = self.cur_y = self.next_x = self.next_y = 0
            self.dxf = self.dyf = 0
            self.xfrac = self.yfrac = 0
        if mode in (1, -1):
            self.costume = 0
            self.room = 0
            self.x = self.y = 0
            self.facing = 180
        elif mode == 2:
            self.facing = 180
        self.elevation = 0
        self.width = 24
        self.talk_color = 15
        self.boxscale = self.scalex = self.scaley = 255
        self.sound = 0
        self.target_facing = self.facing
        self.moving = 0
        self.set_walk_speed(8, 2)
        self.anim_speed = 0
        self.ignore_boxes = False
        self.force_clip = 0
        self.init_frame, self.walk_frame, self.stand_frame = 1, 2, 3
        self.talk_start, self.talk_stop = 4, 5
        if self.w is not None and mode != -1:
            vm = self.w.vm
            if self.number < len(vm.classes):
                vm.classes[self.number] = 0

    def reset_cost(self, v=0xFFFF):
        """CostumeData::reset (v = 0: como el memset del principio)."""
        self.stopped = 0
        self.curpos = [v] * 16
        self.start = [v] * 16
        self.end = [v] * 16
        self.cframe = [v] * 16

    def pack(self):
        """Los mismos bytes que la ficha del actor en el Z80 (A_* y R_* en actor.asm)."""
        import struct
        out = struct.pack("<hhHHBBB", self.x, self.y, self.facing, self.target_facing,
                          self.box, self.moving, self.frame)
        out += struct.pack("<hhBhB", self.dest_x, self.dest_y, self.dest_box, self.dest_dir, self.cur_box)
        out += struct.pack("<hhhh", self.cur_x, self.cur_y, self.next_x, self.next_y)
        out += struct.pack("<iiHH", self.dxf, self.dyf, self.xfrac, self.yfrac)
        out += struct.pack("<BBH", self.anim_progress, self.anim_speed, self.stopped)
        out += struct.pack("<16H", *self.curpos) + struct.pack("<16H", *self.start)
        out += struct.pack("<16H", *self.end) + struct.pack("<16H", *self.cframe)
        out += struct.pack("<BB", self.scalex, self.scaley)
        out += bytes((self.speedx & 0xFF, self.speedy & 0xFF))
        out += bytes((self.number, self.room, self.costume, int(self.visible), int(self.needs_init),
                      self.init_frame, self.walk_frame, self.stand_frame, self.talk_start, self.talk_stop))
        out += struct.pack("<hBBH", self.elevation, self.width & 0xFF, self.talk_color & 0xFF, self.boxscale & 0xFFFF)
        out += bytes((int(self.ignore_boxes), self.force_clip & 0xFF))
        out += struct.pack("<HhhHH", self.anim_counter & 0xFFFF, self.top, self.bottom, self.strip0, self.strip1)
        out += bytes(p & 0xFF for p in self.palette)
        out += bytes((self.sound & 0xFF, self.sound_counter & 0xFF))
        return out

    # --- donde esta ---
    def in_room(self):
        """isInCurrentRoom (aqui, nunca en la habitacion 0)."""
        if self.w is None:
            return True
        return self.w.room != 0 and self.room == self.w.room

    def in_class(self, c):
        return self.w is not None and self.w.vm.get_class(self.number, c)

    def is_player(self):
        return self.w is None or self.in_class(CLASS_PLAYER)

    def get_cost(self):
        """Los datos de su costume (None si no tiene o no esta)."""
        if self.w is None:
            return self.cost
        if not self.costume:
            return None
        return self.w.costume_for(self.costume)

    def set_walk_speed(self, sx, sy):
        if sx == self.speedx and sy == self.speedy:
            return
        self.speedx, self.speedy = sx, sy
        if self.moving and self.boxes is not None:
            self.calc_movement(self.boxes, self.next_x, self.next_y)

    # --- costume ---
    def decode_data(self, frame, usemask):
        """costumeDecodeData: en cframe va la animacion (direccion + 4 * frame)."""
        c = self.get_cost()
        if c is None:
            return
        anim = new_dir_to_old_dir(self.facing) + frame * 4
        if anim > c.num_anim:
            return
        off = S.le16(c.blk, c.anim_table + 2 * anim)
        if off == 0:
            return
        r = c.abs(off)
        mask = S.le16(c.blk, r)
        r += 2
        i = 0
        while mask & 0xFFFF:
            if mask & 0x8000:
                j = S.le16(c.blk, r)
                r += 2
                if usemask & 0x8000:
                    if j == 0xFFFF:
                        self.curpos[i] = 0xFFFF
                        self.start[i] = 0
                        self.cframe[i] = anim
                    else:
                        extra = c.blk[r]
                        r += 1
                        cmd = c.cmds[j]
                        if cmd == 0x7A:
                            self.stopped &= ~(1 << i)
                        elif cmd == 0x79:
                            self.stopped |= 1 << i
                        else:
                            self.curpos[i] = self.start[i] = j
                            self.end[i] = j + (extra & 0x7F)
                            if extra & 0x80:
                                self.curpos[i] |= 0x8000
                            self.cframe[i] = anim
                else:
                    if j != 0xFFFF:
                        r += 1
            i += 1
            usemask = (usemask << 1) & 0xFFFF
            mask = (mask << 1) & 0xFFFF

    def increase_anim(self, c, slot):
        cmds = c.cmds
        if self.curpos[slot] == 0xFFFF:
            return False
        high = self.curpos[slot] & 0x8000
        i = self.curpos[slot] & 0x7FFF
        end = self.end[slot]
        code = cmds[i] & 0x7F
        while True:
            if not high:
                if i >= end:
                    i = self.start[slot]
                else:
                    i += 1
            else:
                if i != end:
                    i += 1
            nc = cmds[i]
            if nc == 0x7C:
                self.anim_counter = (self.anim_counter + 1) & 0xFFFF
                if self.start[slot] != end:
                    continue
            elif nc == 0x78:                # sonido: playActorSounds al final del paso
                self.sound_counter = (self.sound_counter + 1) & 0xFF
                if self.start[slot] != end:
                    continue
            self.curpos[slot] = i | high
            return (cmds[i] & 0x7F) != code

    def animate(self):
        """animateCostume."""
        if not self.costume:
            return
        self.anim_progress = (self.anim_progress + 1) & 0xFF
        if self.anim_progress >= self.anim_speed:
            self.anim_progress = 0
            c = self.get_cost()
            if c is None:
                return
            for i in range(16):
                if self.curpos[i] != 0xFFFF:
                    self.increase_anim(c, i)

    def start_anim(self, f):
        """startAnimActor (0x38..0x3C: init, andar, quieto, hablar y callar)."""
        f &= 0xFF
        if f in SPECIAL_FRAMES:
            f = getattr(self, SPECIAL_FRAMES[f])
        if self.in_room() and self.costume:
            self.anim_progress = 0
            self.anim_counter = 0
            if f == self.init_frame:
                self.reset_cost()
            self.decode_data(f, 0xFFFF)
            self.frame = f

    def animate_actor(self, anim):
        """animateActor: 252-255 parar, 248-251 mirar ya, 244-247 girar; el resto, una animacion."""
        anim &= 0xFF
        chore = 0x3F - (anim >> 2) + 2
        d = old_dir_to_new_dir(anim)
        if chore == 2:
            if self.in_room():
                self.start_anim(self.stand_frame)
                self.moving = 0
        elif chore == 3:
            if self.in_room():
                self.moving &= ~MF_TURN
            self.set_direction(d)
        elif chore == 4:
            if self.in_room():
                self.turn_to(d)
        else:
            self.start_anim(anim)

    def set_direction(self, d):
        d = (d + 360) % 360
        if self.facing == d:
            return
        self.facing = d
        if not self.costume or not self.in_room():
            return
        mask = 0x8000
        for i in range(16):
            vald = self.cframe[i]
            if vald != 0xFFFF and (vald & 3) != new_dir_to_old_dir(d):
                self.decode_data(vald >> 2, mask)
            mask >>= 1

    def turn_to(self, d):
        if d == -1:
            return
        self.target_facing = d
        self.moving = MF_TURN

    def talk_anim(self, f):
        """runActorTalkScript."""
        ta = self.w.vm.vars[25] if self.w is not None else 0
        if not ta or not self.in_room() or self.frame == f:
            return
        self.start_anim(f)

    # --- andar ---
    def remap_direction(self, boxes, d, walking):
        if not self.ignore_boxes:
            flags = boxes.flags(self.box) if self.box != INVALID else 0
            flip_x = self.dxf > 0
            flip_y = self.dyf > 0
            if flags & 0x08 or self.in_class(CLASS_XFLIP):
                d = 360 - d
                flip_x = not flip_x
            if flags & 0x10 or self.in_class(CLASS_YFLIP):
                d = 180 - d
                flip_y = not flip_y
            k = flags & 7
            if k == 1:
                if walking:
                    return 90 if flip_x else 270
                return 90 if d == 90 else 270
            if k == 2:
                if walking:
                    return 180 if flip_y else 0
                return 0 if d == 0 else 180
            if k in (3, 4, 5, 6):
                return {3: 270, 4: 90, 5: 0, 6: 180}[k]
        return (d + 360) % 360 | 0x400

    def update_direction(self, boxes, walking):
        d = self.remap_direction(boxes, self.target_facing, walking)
        if d & 0x400:
            d = OLD_TO_NEW[TURN_TABLE[new_dir_to_old_dir(d & 0x3FF) | new_dir_to_old_dir(self.facing) << 2]]
        return d

    def set_box(self, b):
        self.box = b
        self.setup_scale()

    def setup_scale(self):
        """setupActorScale: la escala sale de la caja y de la posicion."""
        if self.ignore_boxes or self.boxes is None:
            return
        self.boxscale = self.boxes.box_scale(self.box)
        self.scalex = self.scaley = self.boxes.get_scale(self.box, self.x, self.y)

    def adjust_xy(self, boxes, x, y):
        """adjustXYToBeInBox."""
        if self.ignore_boxes:
            return x, y, INVALID
        return boxes.adjust_xy(x, y, self.is_player())

    def start_walk(self, boxes, x, y, d=-1):
        """startWalkActor."""
        ax, ay, ab = self.adjust_xy(boxes, x, y)
        if not self.in_room():
            self.x, self.y = ax, ay
            if d != -1:
                self.facing = d
            return
        if self.ignore_boxes:
            ab = INVALID
            self.box = INVALID
        else:
            if boxes.in_box(self.dest_box, ax, ay):
                ab = self.dest_box
            else:
                ax, ay, ab = self.adjust_xy(boxes, ax, ay)
            if self.moving and self.dest_dir == d and self.dest_x == ax and self.dest_y == ay:
                return
        if self.x == ax and self.y == ay:
            if d != self.facing:
                self.turn_to(d)
            return
        self.dest_x, self.dest_y, self.dest_box, self.dest_dir = ax, ay, ab, d
        self.cur_box = self.box
        self.moving = (self.moving & MF_IN_LEG) | MF_NEW_LEG

    def walk_step(self, boxes):
        """actorWalkStep: 1 si sigue en el tramo."""
        nf = self.update_direction(boxes, True)
        if not (self.moving & MF_IN_LEG) or self.facing != nf:
            if self.walk_frame != self.frame or self.facing != nf:
                self.set_direction(nf)
                self.start_anim(self.walk_frame)
            self.moving |= MF_IN_LEG
        if self.box != self.cur_box and boxes.in_box(self.cur_box, self.x, self.y):
            self.set_box(self.cur_box)
        dist_x = abs(self.next_x - self.cur_x)
        dist_y = abs(self.next_y - self.cur_y)
        if abs(self.x - self.cur_x) >= dist_x and abs(self.y - self.cur_y) >= dist_y:
            self.moving &= ~MF_IN_LEG
            return 0
        tx = i32((self.x << 16) + self.xfrac + (self.dxf >> 8) * self.scalex)
        self.xfrac = tx & 0xFFFF
        self.x = i16(tx >> 16)
        ty = i32((self.y << 16) + self.yfrac + (self.dyf >> 8) * self.scaley)
        self.yfrac = ty & 0xFFFF
        self.y = i16(ty >> 16)
        if abs(self.x - self.cur_x) > dist_x:
            self.x = self.next_x
        if abs(self.y - self.cur_y) > dist_y:
            self.y = self.next_y
        if self.x == self.next_x and self.y == self.next_y:
            self.moving &= ~MF_IN_LEG
            return 0
        return 1

    def calc_movement(self, boxes, nx, ny):
        """calcMovementFactor (ScummVM 2.8: la x se compara entera, sin decimales, y
        mira hacia donde mas avanza, con la y por 3)."""
        if self.x == nx and self.y == ny:
            return 0
        dx = nx - self.x
        dy = ny - self.y
        dyf = self.speedy << 16
        if dy < 0:
            dyf = -dyf
        dxf = i32(dyf * dx)
        if dy != 0:
            dxf = cdiv(dxf, dy)
        else:
            dyf = 0
        if abs(cdiv(dxf, 0x10000)) > self.speedx:
            dxf = self.speedx << 16
            if dx < 0:
                dxf = -dxf
            dyf = i32(dxf * dy)
            if dx != 0:
                dyf = cdiv(dyf, dx)
            else:
                dxf = 0
        self.xfrac = self.yfrac = 0
        self.cur_x, self.cur_y = self.x, self.y
        self.next_x, self.next_y = nx, ny
        self.dxf, self.dyf = dxf, dyf
        if abs(dy) * 3 > abs(dx):
            self.target_facing = 180 if dyf > 0 else 0
        else:
            self.target_facing = 90 if dxf > 0 else 270
        return self.walk_step(boxes)

    def walk(self, boxes):
        """walkActor."""
        if not self.moving:
            return
        if not (self.moving & MF_NEW_LEG):
            if self.moving & MF_IN_LEG and self.walk_step(boxes):
                return
            if self.moving & MF_LAST_LEG:
                self.moving = 0
                self.set_box(self.dest_box)
                self.start_anim(self.stand_frame)
                if self.target_facing != self.dest_dir:
                    self.turn_to(self.dest_dir)
                return
            if self.moving & MF_TURN:
                nd = self.update_direction(boxes, False)
                if self.facing != nd:
                    self.set_direction(nd)
                else:
                    self.moving = 0
                return
            self.set_box(self.cur_box)
            self.moving &= MF_IN_LEG
        self.moving &= ~MF_NEW_LEG
        while True:
            if self.box == INVALID:
                self.set_box(self.dest_box)
                self.cur_box = self.dest_box
                break
            if self.box == self.dest_box:
                break
            nb = boxes.next_box(self.box, self.dest_box)
            if nb < 0:
                self.dest_box = self.box
                self.moving |= MF_LAST_LEG
                return
            self.cur_box = nb
            done, pt = find_path_towards(boxes, self, self.box, nb, self.dest_box)
            if done:
                break
            if self.calc_movement(boxes, pt[0], pt[1]):
                return
            self.set_box(self.cur_box)
        self.moving |= MF_LAST_LEG
        self.calc_movement(boxes, self.dest_x, self.dest_y)

    # --- ponerlo, enseñarlo, quitarlo ---
    def adjust_pos(self):
        """adjustActorPos."""
        boxes = self.boxes
        ax, ay, ab = self.adjust_xy(boxes, self.x, self.y) if boxes is not None else (self.x, self.y, INVALID)
        self.x, self.y = ax, ay
        self.dest_box = ab
        self.set_box(ab)
        self.dest_x = -1
        self.moving = 0
        self.sound_counter = 0
        if self.box != INVALID and boxes is not None and boxes.flags(self.box) & 7:
            self.turn_to(self.facing)

    def put_actor(self, x, y, room):
        """putActor."""
        w = self.w
        if self.visible and w.room != room and w.ui.talking_actor() == self.number:
            w.ui.stop_talk()
        self.x, self.y, self.room = x, y, room
        if w.vm.vars[1] == self.number:
            w.ego_positioned = True
        if self.visible:
            if self.in_room():
                if self.moving:
                    self.moving = 0
                    self.start_anim(self.stand_frame)
                self.adjust_pos()
            else:
                self.hide()
        elif self.in_room():
            self.show()

    def show(self):
        """showActor."""
        if not self.w.room or self.visible:
            return
        self.adjust_pos()
        if self.needs_init:
            self.start_anim(self.init_frame)
            self.needs_init = False
        self.moving = 0
        self.visible = True

    def hide(self):
        """hideActor."""
        if not self.visible:
            return
        if self.moving:
            self.moving = 0
            self.start_anim(self.stand_frame)
        self.visible = False
        self.sound_counter = 0

    def set_costume(self, c):
        """setActorCostume."""
        self.needs_init = True
        if self.visible:
            self.hide()
            self.reset_cost()
            self.costume = c & 0xFF
            self.show()
        else:
            self.costume = c & 0xFF
            self.reset_cost()
        self.palette = [0xFF] * 32

    def face_to(self, obj):
        """faceToObject."""
        if not self.in_room():
            return
        xy = self.w.object_or_actor_xy(obj)
        if xy is None:
            return
        self.turn_to(90 if xy[0] > self.x else 270)

    def put(self, boxes, x, y):
        """El actor solo del motor: putActor + adjustActorPos y su animacion inicial."""
        self.boxes = boxes
        self.x, self.y = x, y
        ax, ay, ab = boxes.adjust_xy(x, y)
        self.x, self.y = ax, ay
        self.dest_box = ab
        self.set_box(ab)
        self.dest_x = -1
        self.moving = 0
        self.start_anim(self.init_frame)
        self.start_anim(self.stand_frame)


# ---------------------------------------------------------------------------
# Camara
# ---------------------------------------------------------------------------
CAM_FOLLOW, CAM_NORMAL, CAM_PAN = 1, 2, 3


class Camera:
    def __init__(self, room_w):
        self.w = room_w
        self.min_x = SCREEN_W // 2
        self.max_x = room_w - SCREEN_W // 2
        self.cur = self.dest = SCREEN_W // 2
        self.moving_to_actor = False
        self.start_strip = 0
        self.mode = CAM_FOLLOW
        self.follows = 1

    def moved(self):
        if self.cur < SCREEN_W // 2:
            self.cur = SCREEN_W // 2
        elif self.cur > self.w - SCREEN_W // 2:
            self.cur = self.w - SCREEN_W // 2
        self.start_strip = max(0, (self.cur >> 3) - 20)

    def left(self):
        return self.start_strip * 8

    def set_at(self, x):
        """Al entrar: la camara salta al actor."""
        self.cur = self.dest = x
        if self.cur < self.min_x:
            self.cur = self.min_x
        if self.cur > self.max_x:
            self.cur = self.max_x
        self.moving_to_actor = False
        self.moved()

    def move(self, ax):
        """moveCamera, siguiendo la x del actor que sigue (sin VAR_CAMERA_FAST_X)."""
        self.cur -= self.cur & 7            # &= 0xFFF8 de 16 bits con signo (sigue negativa)
        if self.cur < self.min_x:
            self.cur += 8
            self.moved()
            return
        if self.cur > self.max_x:
            self.cur -= 8
            self.moved()
            return
        if self.mode == CAM_FOLLOW:
            t = (ax >> 3) - self.start_strip
            if t < 10 or t > 30:
                self.moving_to_actor = True
        if self.moving_to_actor:
            self.dest = ax
        if self.dest < self.min_x:
            self.dest = self.min_x
        if self.dest > self.max_x:
            self.dest = self.max_x
        if self.cur < self.dest:
            self.cur += 8
        if self.cur > self.dest:
            self.cur -= 8
        if self.moving_to_actor and self.cur >> 3 == ax >> 3:
            self.moving_to_actor = False
        self.moved()

    def pack(self):
        import struct
        return struct.pack("<hhBBB", self.cur, self.dest, int(self.moving_to_actor),
                           self.start_strip & 0xFF, self.mode)

    def at(self, x):
        """setCameraAt: modo normal, salta a x."""
        self.mode = CAM_NORMAL
        self.cur = self.dest = x
        if self.cur < self.min_x:
            self.cur = self.min_x
        if self.cur > self.max_x:
            self.cur = self.max_x
        self.moving_to_actor = False
        self.moved()

    def pan(self, x):
        self.dest = x
        self.mode = CAM_PAN
        self.moving_to_actor = False


# ---------------------------------------------------------------------------
# Dibujo de los actores en tiles de sprite
# ---------------------------------------------------------------------------
HIDDEN = bytes((0, 0, 0, 0x40, 0))


class Frame:
    """Lo que el Z80 sube a los sprites en un paso: los patrones de los actores
    seguidos, los de 4 bits (SPRBUF[0:used]) y los de 8 (la otra pagina,
    [0:used8]), y los atributos de los sprites 0..63. Los actores se componen
    de delante atras: el primero se queda con los sprites de numero mas alto
    (los que se ven encima)."""

    def __init__(self):
        self.used = 0                   # bytes de patrones de 4 bits
        self.used8 = 0                  # y de 8 bits
        self.nspr = 0                   # sprites usados: el k-esimo es el 63 - k
        self.pats = bytearray()         # 4 bits (pixel izquierdo arriba, 128 bytes)
        self.pats8 = bytearray()        # 8 bits (256)
        self.attrs = bytearray(HIDDEN * NSPR_ACTOR)
        self.pals = []                  # (primer color de sprite, costume), en el orden en que se escriben
        self.canvas = []                # (bx, by, TW, TH) de cada actor, para depurar

    @property
    def patterns(self):
        """Los de 4 bits y detras los de 8 (como los lee la prueba del Z80)."""
        return bytes(self.pats) + bytes(self.pats8)

    @property
    def nbytes(self):
        return self.used + self.used8

    @property
    def ntiles(self):
        return self.nspr


def compose(actor, room_h, zplanes, boxes, left, bank=ACTOR_BANK, elev=0):
    """Un paso con un actor solo (el motor sin maquina virtual)."""
    fr = Frame()
    compose_into(fr, actor, room_h, zplanes, boxes, left, bank, elev)
    return fr


def compose_into(fr, actor, room_h, zplanes, boxes, left, bank=ACTOR_BANK, elev=0, shake=0, cost=None,
                 lights=11, text=None):
    """drawActorCostume en tiles de 16x16, detras de lo que ya tiene fr.
    zplanes: lista (h, w/8) uint8 (con los objetos ya puestos). text: (tmask, x0, y0,
    x1, y1), los pixeles del texto con mascara en [x0, x1) x [y0, y1) (x de habitacion,
    dentro de la vista): ahi el actor no se pinta, para que el texto (en Layer 2, debajo
    de los sprites) quede encima, como en SCUMM. Con escala < 255
    cada dibujo pierde filas y columnas: la k se queda si (k * escala) >> 8
    cambia, y va a ese sitio. El lienzo del actor (tw x th tiles) va donde
    acaban los patrones de los anteriores de su tipo (4 u 8 bits, cada uno en su
    pagina) y no puede pasar de su pagina ni de los 64 sprites: si no cabe, se le
    quitan filas de tiles (y si no cabe ninguna, no se dibuja)."""
    c = cost if cost is not None else actor.cost
    actor.setup_scale()
    sc = actor.scalex
    mode8 = c.num_colors == 32
    fr.pals.append((PAL8 if mode8 else 16 * bank, c, actor_colors(actor, c, lights)))
    room_w = zplanes[0].shape[1] * 8 if zplanes else 0
    mirror = new_dir_to_old_dir(actor.facing) != 0 or c.no_mirror
    if actor.force_clip:
        zbuf = actor.force_clip
    elif actor.in_class(CLASS_NEVER_CLIP):
        zbuf = 0
    else:
        zbuf = boxes.mask(actor.box) if actor.box != INVALID else 0
    if zbuf > len(zplanes):
        zbuf = len(zplanes)
    xmove = ymove = 0
    items = []
    for limb in range(16):
        cp = actor.curpos[limb]
        if cp == 0xFFFF or actor.stopped & (1 << limb):
            continue
        code = c.cmds[cp & 0x7FFF] & 0x7F
        if code == 0x7B:
            continue
        pic = c.limb_picture(limb, code)
        xmc = xmove + pic.rel_x
        ymc = ymove + pic.rel_y
        xmove += pic.move_x
        ymove -= pic.move_y
        if sc != 255:
            xmc = (xmc * sc) >> 8
            ymc = (ymc * sc) >> 8
        x0 = actor.x + xmc if mirror else actor.x - xmc
        items.append((pic, i16(x0), i16(actor.y - elev + ymc)))
    actor.strip0 = actor.strip1 = NO_STRIP
    if not items:
        return

    def last(n):
        return n - 1 if sc == 255 else ((n - 1) * sc) >> 8

    def keep(k):
        return sc == 255 or k == 0 or (k * sc) >> 8 != ((k - 1) * sc) >> 8

    def dest(k):
        return k if sc == 255 else (k * sc) >> 8

    step = 1 if mirror else -1
    xs = []
    ys = []
    for pic, x0, y0 in items:
        if not pic.width or not pic.height:
            continue
        xs += [x0, x0 + step * last(pic.width)]
        ys += [y0, y0 + last(pic.height)]
    if not xs:
        return
    bx, by = min(xs), min(ys)
    actor.top = max(0, by)                              # (drawTop / drawBottom y las tiras)
    actor.bottom = min(room_h, max(ys) + 1)
    actor.strip0 = max(0, bx) >> 3
    actor.strip1 = max(0, max(xs) + 1) >> 3
    if max(xs) < left or bx >= left + SCREEN_W:
        return                                          # (no se ve: no se pinta)
    tw = min(CMAXW, (max(xs) - bx + 16) // 16)
    th = min(CMAXH, (max(ys) - by + 16) // 16)
    ts = 256 if mode8 else 128
    # cada tipo en su pagina, detras de los suyos; y entre los dos no mas de 64 sprites
    # (used / 128 + used8 / 256 <= NSPR_ACTOR)
    if mode8:
        start = fr.used8
        maxt = (min(SPR8_BYTES, 2 * SPR_BYTES - 2 * fr.used) - start) // ts
    else:
        start = fr.used
        maxt = (SPR_BYTES - fr.used8 // 2 - start) // ts
    if tw * th > maxt:
        th = maxt // tw
    if th == 0:
        return
    can = np.zeros((th * 16, tw * 16), dtype=np.uint8)
    zp = zplanes[zbuf - 1] if zbuf else None
    if text is not None:
        tm, tx0, ty0, tx1, ty1 = text
    for pic, x0, y0 in items:
        px = c.decode_picture(pic)
        for k in range(pic.width):
            if not keep(k):
                continue
            x = x0 + step * dest(k)
            cx = x - bx
            if cx < 0 or cx >= tw * 16:
                continue
            for j in range(pic.height):
                if not keep(j):
                    continue
                col = px[j, k]
                if not col:
                    continue
                y = y0 + dest(j)
                if y < 0 or y >= room_h:
                    continue
                cy = y - by
                if cy >= th * 16:
                    continue
                if zp is not None and 0 <= x < room_w and (zp[y, x >> 3] << (x & 7)) & 0x80:
                    continue
                if text is not None and tx0 <= x < tx1 and ty0 <= y < ty1 and tm[y, x % 320]:
                    continue
                can[cy, cx] = col
    n = 0
    for ty in range(th):
        for tx in range(tw):
            t = can[ty * 16:ty * 16 + 16, tx * 16:tx * 16 + 16]
            if not t.any():
                continue
            sx = (bx + 16 * tx - left) & 0x1FF
            sy = (ROOM_Y0 + by + 16 * ty + shake) & 0x1FF
            p = start // ts + n
            if mode8:
                fr.pats8 += np.where(t > 0, t + PAL8, 0).astype(np.uint8).tobytes()
                a = (sx & 0xFF, sy & 0xFF, sx >> 8, 0xC0 | PAT8_SLOT + p, sy >> 8)
            else:
                fr.pats += (t[:, 0::2] << 4 | t[:, 1::2]).astype(np.uint8).tobytes()
                a = (sx & 0xFF, sy & 0xFF, bank << 4 | sx >> 8, 0xC0 | p >> 1, 0x80 | (p & 1) << 6 | sy >> 8)
            s_ = NSPR_ACTOR - 1 - fr.nspr
            fr.attrs[5 * s_:5 * s_ + 5] = bytes(a)
            fr.nspr += 1
            n += 1
    if mode8:
        fr.used8 = start + n * ts
    else:
        fr.used = start + n * ts
    fr.canvas.append((bx, by, tw, th))


def actor_colors(actor, c, lights):
    """setPalette: los colores del costume (indices de la paleta de la habitacion), con
    los que el actor cambia (los que no son 255); sin luz para actores, todo el 8."""
    n = c.num_colors
    if not lights & 8:
        out = [8] * n
        if n > 12:
            out[12] = 0
        return out
    pal = getattr(actor, "palette", None) or [0xFF] * 32
    return [c.palette[i] if pal[i] == 0xFF else pal[i] for i in range(n)]


def sort_actors(acts, ys):
    """processActors: los actores de la habitacion por y, de menor a mayor,
    con el mismo bucle que SCUMM (los empates salen como en el original)."""
    a = list(zip(ys, acts))
    n = len(a)
    for i in range(n):
        for j in range(n):
            if a[i][0] < a[j][0]:
                a[i], a[j] = a[j], a[i]
    return [x[1] for x in a]


# ---------------------------------------------------------------------------
# Objetos de la habitacion
# ---------------------------------------------------------------------------
def obj_visible(objs, k):
    """drawRoomObject: con estado, y cada padre en el estado que pide el hijo."""
    od = objs[k]
    if not od.state:
        return False
    for _ in range(16):
        a = od.parentstate
        if not od.parent:
            return True
        if od.parent > len(objs):
            return False
        od = objs[od.parent - 1]
        if (od.state & 0xF) != a:
            return False
    return False


def obj_image(o):
    if not o.state or o.state > len(o.images):
        return None
    return o.images[o.state - 1]


def recompose(rd, objs, top=()):
    """Fondo y planos Z con los objetos visibles, del ultimo al primero; los de top (los
    numeros de los que se han pintado con drawObject) despues de los demas, encima: en
    SCUMM van a la cola de dibujo, que se pinta al final, sin el orden de los indices."""
    bg = rd.bg.copy()
    zps = [z.copy() for z in rd.zplanes]
    H, W = bg.shape
    ns = W // 8
    order = list(reversed(range(len(objs))))
    if top:
        order = [k for k in order if objs[k].id not in top] + [k for k in order if objs[k].id in top]
    for k in order:
        o = objs[k]
        if not obj_visible(objs, k):
            continue
        im = obj_image(o)
        if im is None:
            continue
        w = min(o.w, ns - o.x) if o.x < ns else 0
        h = min(o.h, H - o.y) if o.y < H else 0
        if w <= 0 or h <= 0:
            continue
        region = bg[o.y:o.y + h, 8 * o.x:8 * (o.x + w)]
        m = im.opaque[:h, :8 * w]
        region[m] = im.pix[:h, :8 * w][m]
        for pl, zb in im.planes.items():
            if 1 <= pl <= len(zps):
                zps[pl - 1][o.y:o.y + h, o.x:o.x + w] = zb[:h, :w]
    return bg, zps


def obj_at(objs, x, y):
    """El objeto con imagen mas arriba (el de indice menor) en (x, y)."""
    for k, o in enumerate(objs):
        if any(i is not None for i in o.images) and \
                8 * o.x <= x < 8 * (o.x + o.w) and o.y <= y < o.y + o.h:
            return k
    return None


# ---------------------------------------------------------------------------
# El motor: una habitacion, un actor y la camara
# ---------------------------------------------------------------------------
class Engine:
    def __init__(self, room, cost, start=None, vm_mode=False):
        """room: RoomData (tools/convert.py); cost: scumm.Costume. Con vm_mode la
        camara empieza quieta en 160 y al actor lo coloca el mundo."""
        import copy
        self.room = room
        self.boxes = Boxes(copy.deepcopy(room.boxes), room.matrix, room.scale_slots)
        self.objs = copy.deepcopy(room.objects)
        self.top = set()                    # los que van encima (drawObject; ZOBTOP en el Z80)
        self.work_bg, self.work_zp = recompose(room, self.objs)
        self.cam = Camera(room.width)
        self.actor = None
        if vm_mode:                         # (los actores son los de la maquina virtual)
            self.cam.cur = self.cam.dest = SCREEN_W // 2
            self.cam.mode = CAM_NORMAL
            self.cam.moved()
        else:
            self.actor = Actor(cost)
            sx, sy = start if start else room.start
            self.actor.put(self.boxes, sx, sy)
            self.cam.set_at(self.actor.x)
        self.frame = None

    def tick(self, click=None):
        """Un paso del motor; click = (x, y) en coordenadas de la habitacion."""
        a = self.actor
        if click is not None:
            a.start_walk(self.boxes, click[0], click[1], -1)
        a.walk(self.boxes)
        self.cam.move(a.x)
        self.frame = compose(a, self.room.height, self.work_zp, self.boxes, self.cam.left())
        a.animate()
        return self.frame

    def set_state(self, k, v):
        """Cambia el estado del objeto k y vuelve a componer el fondo."""
        self.objs[k].state = v
        self.work_bg, self.work_zp = recompose(self.room, self.objs, getattr(self, "top", ()))

    def sync_states(self, table):
        """Estados de los objetos desde la tabla global (la de la maquina virtual)."""
        for o in self.objs:
            o.state = table[o.id] if 0 <= o.id < len(table) else 0
        self.work_bg, self.work_zp = recompose(self.room, self.objs, getattr(self, "top", ()))


# ---------------------------------------------------------------------------
# El mundo: la maquina virtual, la habitacion actual y el protagonista
# ---------------------------------------------------------------------------
def name_bytes(n):
    return n.encode("latin1") if isinstance(n, str) else bytes(n or b"")


L2_TRANSPARENT = 0xE3                       # NR $14 (como tools/convert.py)
SHAKE_POS = (0, 2, 4, 2, 0, 4, 6, 2)        # shake_positions de SCUMM (pixeles hacia abajo)
VAR_TIMER_NEXT = 19


def next_color9(r, g, b):
    """RGB de 8 bits -> los dos bytes de NR $44 (convert.next_color)."""
    r, g, b = [(int(v) * 7 + 127) // 255 for v in (r, g, b)]
    hi = r << 5 | g << 2 | b >> 1
    lo = b & 1
    if hi == L2_TRANSPARENT:
        hi, lo = hi - 1, 1
    return hi, lo


def palette9(pal):
    out = bytearray()
    for rgb in list(pal)[:256]:
        out += bytes(next_color9(*rgb))
    out += bytes(512 - len(out))
    return out


def s16v(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def ui_num_verbs():
    import ui as U
    return U.NUM_VERBS


def clamp8(v):
    """Una fila para DRAWSTRIPR: 0..255."""
    return max(0, min(255, v))


class L2Mem:
    """La memoria de Layer 2 tal como la deja el Z80: 256 filas x 320 columnas
    (la columna c tiene la columna de la habitacion que vale c modulo 320)."""

    def __init__(self):
        self.mem = np.zeros((256, 320), dtype=np.uint8)

    def view(self, scroll, main_h):
        """Lo que se ve: la habitacion con el scroll y los verbos sin el (cobre)."""
        out = self.mem.copy()
        split = ROOM_Y0 + main_h
        out[:split] = np.roll(self.mem[:split], -scroll, axis=1)
        return out


class World:
    """Une la maquina virtual (tools/vm.py) con la habitacion (Engine), la
    interfaz (tools/ui.py) y la memoria de Layer 2. rooms(n) da la RoomData;
    costumes(n) el costume n (o None si no esta) para los demas actores."""

    def __init__(self, rooms, scripts, objects, cost, first_room, nvars=800, nbits=2048,
                 charsets=None, verb_image=None, costumes=None, sounds=None):
        import vm as V
        self.V = V
        self._init = (rooms, scripts, objects, cost, nvars, nbits, charsets, verb_image, costumes, sounds)
        self.restart_req = False
        self.quit_req = False
        self.rooms = rooms
        self.cost = cost
        self.costumes = costumes
        self.ccache = []                # (numero, Costume o None) de esta habitacion
        self.cc_next = CAST_PAGE
        self.rstamp = 0                 # habitaciones cargadas (para la caja de los demas)
        self.vm = V.VM(scripts, objects, nvars, nbits, world=self, charsets=charsets, verb_image=verb_image,
                       sounds=sounds)
        self.vm.vars[V.VAR_EGO] = 1             # el protagonista es el actor 1
        self.ui = self.vm.ui
        self.room = 0
        self.eng = None
        self.l2 = L2Mem()
        self.tmask = np.zeros((200, SCREEN_W), bool)   # pixeles de texto (columna de Layer 2)
        self.room_w = 0                     # ancho de la ultima habitacion cargada (RW)
        self.l2ss = 0
        self.pstrip = None
        self.dirty = set()
        self.follows = 1
        self.ego_positioned = False
        self.ego_start = False
        self.frame = None
        self.pal9 = bytearray(512)              # la paleta de Layer 2 que se ve (NR $44)
        self.pal8 = [(0, 0, 0)] * 256           # la de la habitacion (darkenPalette parte de ella)
        self.cycles = [None] * 16               # [delay, contador, flags, primero, ultimo]
        self.shake_on = False
        self.shake_frame = 0
        self.shake_y = 0
        self.room_fx = (0, 0)                   # _switchRoomEffect, _switchRoomEffect2 (solo se ven)
        if first_room:
            self.enter_with_ego(first_room)

    # --- entrar en una habitacion -------------------------------------------------
    def enter_with_ego(self, room):
        """Para las pruebas: el protagonista en el punto de inicio de la habitacion y
        la camara siguiendole (como loadRoomWithEgo, sin objeto). El punto de inicio
        se le pone al cargar la habitacion (como en el Z80, que hasta entonces no lo
        sabe), despues del script de salida de la anterior."""
        V, vm = self.V, self.vm
        ego = vm.vars[V.VAR_EGO]
        if 0 < ego < V.NUM_ACTORS:
            a = vm.actors[ego]
            a.room, a.moving = room, 0
            self.ego_start = True
        self.start_scene(room)
        if self.room:
            self.camera_follows(ego)

    def ego(self):
        return self.vm.vars[self.V.VAR_EGO]

    def ego_actor(self):
        e = self.ego()
        return self.vm.actors[e] if 0 < e < self.V.NUM_ACTORS else None

    def ego_here(self):
        return self.room != 0 and self.eng is not None and self.vm.in_room(self.ego())

    def room_resource(self, room):
        """La habitacion de verdad: 128 o mas son pseudohabitaciones (pseudoRoom)."""
        return self.vm.res_map[room & 0x7F] if room >= 0x80 else room

    def start_scene(self, room, obj=0):
        """startScene (con obj: loadRoomWithEgo, el protagonista en el objeto)."""
        V, vm, ui = self.V, self.vm, self.ui
        ui.stop_talk()
        if self.room:
            vm.run_exit()
        vm.kill_room_scripts()
        self.cycles = [None] * 16           # stopCycle(0)
        for a in vm.actors[1:]:             # hideActor
            a.hide()
        if room == 0:                       # sin habitacion: se queda la imagen
            self.room = 0
            vm.room_code = {}
            vm.vars[V.VAR_ROOM] = 0
            vm.vars[V.VAR_ROOM_RESOURCE] = 0
            return
        res = self.room_resource(room)
        rd = self.rooms(res)
        vm.room_code = rd.code
        self.room = room
        vm.vars[V.VAR_ROOM] = room
        vm.vars[V.VAR_ROOM_RESOURCE] = res
        vm.vars[V.VAR_CAMERA_MIN_X] = SCREEN_W // 2
        vm.vars[V.VAR_CAMERA_MAX_X] = rd.width - SCREEN_W // 2
        self.room_w = rd.width              # (el ancho que usa roomOps 1, como _roomWidth)
        self.eng = Engine(rd, self.cost, vm_mode=True)
        self.eng.cam.follows = self.follows
        for a in vm.actors:
            a.boxes = self.eng.boxes
        self.pal8 = [tuple(int(v) & 0xFF for v in rgb) for rgb in list(rd.palette)[:256]]
        self.pal8 += [(0, 0, 0)] * (256 - len(self.pal8))
        self.pal9 = palette9(self.pal8)
        self.cycles = [[cy[0], 0, cy[1], cy[2], cy[3]] if cy else None for cy in rd.cycles]
        self.rstamp = (self.rstamp + 1) & 0xFF
        self.ccache = []                # los costumes van detras de la habitacion
        self.cc_next = 27 + rd.data_pages
        ego = self.ego_actor()
        if self.ego_start:                  # (enter_with_ego)
            self.ego_start = False
            vm.actors[vm.vars[V.VAR_EGO]].x, vm.actors[vm.vars[V.VAR_EGO]].y = rd.start
        if obj and ego is not None:
            xyd = self.object_walk_xyd(obj)
            if xyd is not None:
                ego.put_actor(xyd[0], xyd[1], room)
                ego.set_direction(xyd[2] + 180)
                ego.moving = 0
        for a in vm.actors[1:]:             # showActors
            if a.in_room():
                a.show()
        self.eng.sync_states(vm.state)
        self.dirty = set()
        self.load_draw()
        self.ego_positioned = False
        vm.run_entry()
        if obj and ego is not None and not self.ego_positioned:
            xyd = self.object_walk_xyd(obj)
            if xyd is not None:
                ego.put_actor(xyd[0], xyd[1], room)
                ego.moving = 0
        self.flush()

    def load_draw(self):
        """LOADROOM: la vista entera (y en negro lo que queda a la derecha)."""
        rd = self.eng.room
        h = self.ui.main_h
        ns = rd.width // 8
        if ns < 40:
            self.l2.mem[ROOM_Y0:ROOM_Y0 + h, ns * 8:] = 0
        self.l2ss = self.eng.cam.start_strip
        self.full_draw()
        self.pstrip = None
        self.ui.has_mask = False
        self.ui.mask_rect = None
        self.tmask[:] = False

    # --- Layer 2 -------------------------------------------------------------------
    def draw_strip(self, s_, y0=0, y1=255, keep_text=False):
        """La tira s_ en Layer 2, solo las filas [y0, y1) (DRAWSTRIP / DRAWSTRIPR).
        keep_text: los pixeles del texto (tmask) se quedan (FLUSHOBJ: TDRAWS)."""
        rd = self.eng.room
        h = self.ui.main_h
        rows = min(rd.height, h)
        c = (s_ % 40) * 8
        if keep_text and self.ui.mask_rect is not None:
            keep = self.l2.mem[ROOM_Y0:ROOM_Y0 + 200, c:c + 8].copy()
            m = self.tmask[:, c:c + 8].copy()
        else:
            keep = None
        a0, a1 = y0, min(y1, rows)
        if a1 > a0:
            self.l2.mem[ROOM_Y0 + a0:ROOM_Y0 + a1, c:c + 8] = self.eng.work_bg[a0:a1, 8 * s_:8 * s_ + 8]
        c0, c1 = max(y0, rows), min(y1, h)
        if c1 > c0:
            self.l2.mem[ROOM_Y0 + c0:ROOM_Y0 + c1, c:c + 8] = 0
        if keep is not None:
            col = self.l2.mem[ROOM_Y0:ROOM_Y0 + 200, c:c + 8]
            col[m] = keep[m]

    def tmask_clear(self, x0, y0, x1, y1):
        """Sin texto en las tiras de x de habitacion [x0, x1) y las filas [y0, y1) (TMCLR)."""
        r0, r1 = clamp8(y0), min(clamp8(y1), 200)
        if x1 <= x0 or r1 <= r0:
            return
        for s_ in range(max(x0, 0) // 8, (x1 - 1) // 8 + 1):
            c = (s_ % 40) * 8
            self.tmask[r0:r1, c:c + 8] = False

    def full_draw(self):
        ns = self.eng.room.width // 8
        ss = self.eng.cam.start_strip
        for s_ in range(ss, ss + 40):
            if s_ < ns:
                self.draw_strip(s_)

    def visible(self, s_):
        ss = self.eng.cam.start_strip
        return ss <= s_ < ss + 40 and s_ < self.eng.room.width // 8

    def flush(self):
        """FLUSHOBJ: las tiras de los objetos que han cambiado, si se ven."""
        if not self.room:
            self.dirty = set()
            return
        for s_ in sorted(self.dirty):
            if self.visible(s_):
                self.draw_strip(s_, keep_text=True)
        self.dirty = set()

    def cam_left(self):
        return self.eng.cam.left() if self.eng is not None else 0

    def cam_cur_dest(self):
        return self.eng.cam.cur, self.eng.cam.dest

    def surface_px(self, vs, x, y, c, text=False):
        """text: un pixel de texto con mascara (va tambien a tmask: TMSET)."""
        if vs == 0:
            if 0 <= x < SCREEN_W and 0 <= y < self.ui.main_h:
                self.l2.mem[ROOM_Y0 + y, (self.cam_left() + x) % 320] = c
                if text:
                    self.tmask[y, (self.cam_left() + x) % 320] = True
        else:
            if 0 <= x < SCREEN_W and 0 <= y < 200 - self.ui.main_h:
                self.l2.mem[ROOM_Y0 + self.ui.main_h + y, x] = c

    def surface_restore(self, vs, rect):
        """Borrar el texto: en la principal se vuelven a pintar sus filas de sus tiras."""
        x0, y0, x1, y1 = rect
        if vs == 0:
            if not self.room or x1 <= x0:
                return
            for s_ in range(max(x0, 0) // 8, (x1 - 1) // 8 + 1):
                if self.visible(s_):
                    self.draw_strip(s_, clamp8(y0), clamp8(y1))
        else:
            self.fill_vs(1, x0, y0 - self.ui.main_h, x1, y1 - self.ui.main_h, 0)

    def fill_vs(self, vs, x0, y0, x1, y1, c):
        h = self.ui.main_h if vs == 0 else 200 - self.ui.main_h
        x0, x1 = max(x0, 0), min(x1, SCREEN_W)
        y0, y1 = max(y0, 0), min(y1, h)
        if x0 >= x1 or y0 >= y1:
            return
        top = ROOM_Y0 + (0 if vs == 0 else self.ui.main_h)
        if vs == 0:
            for x in range(x0, x1):
                self.l2.mem[top + y0:top + y1, (self.cam_left() + x) % 320] = c
        else:
            self.l2.mem[top + y0:top + y1, x0:x1] = c

    def surface_fill(self, vs_hint, rect, c):
        """restoreBackground: rect en coordenadas de pantalla."""
        l, t, r, b = rect
        t = max(t, 0)
        if l >= r or t >= b:
            return
        vs = self.ui.find_vs(t)
        if vs is None:
            return
        top = self.ui.vs_top(vs)
        if vs == 0 and self.room:
            self.tmask_clear(l + self.cam_left(), t, r + self.cam_left(), b)
            for s_ in range(max(l + self.cam_left(), 0) // 8, (r - 1 + self.cam_left()) // 8 + 1):
                if self.visible(s_):
                    self.draw_strip(s_, clamp8(t), clamp8(b))
            return
        self.fill_vs(vs, l, t - top, r, b - top, c)

    def surface_image(self, vs, x, y, img):
        w, h, pix, opaque = img
        h8 = h // 8 * 8
        for yy in range(h8):
            for xx in range(w):
                if opaque[yy][xx]:
                    self.surface_px(vs, x + xx, y + yy, pix[yy][xx])

    def draw_box(self, x, y, x2, y2, c):
        vs = self.ui.find_vs(y)
        if vs is None:
            return
        if x > x2:
            x, x2 = x2, x
        if y > y2:
            y, y2 = y2, y
        x2 += 1
        y2 += 1
        top = self.ui.vs_top(vs)
        self.fill_vs(vs, x, y - top, x2, y2 - top, c)

    def set_screen(self, b, h):
        """setScreen(b, h): b siempre es 0 en Monkey Island."""
        self.ui.main_h = max(0, min(200, h))
        self.l2.mem[ROOM_Y0 + self.ui.main_h:ROOM_Y0 + 200] = 0
        self.ui.has_mask = False
        self.ui.mask_rect = None
        self.tmask[:] = False
        if self.room:
            self.full_draw()

    # --- lo que pregunta la maquina virtual ---
    def object_changed(self, obj):
        if not self.room:
            return
        objs = self.eng.objs
        k = next((i for i, o in enumerate(objs) if o.id == obj), None)
        if k is None:
            return
        for j, o in enumerate(objs):
            if o.w and self.descends(j, k):
                self.dirty.update(range(o.x, o.x + o.w))
        self.eng.sync_states(self.vm.state)

    def draw_top(self, obj, on):
        """drawObject: el objeto va encima de los demas al recomponer (como la cola de
        dibujo de SCUMM) hasta un setState o pickupObject, que lo vuelven a poner en el
        orden de los indices."""
        if not self.room or not any(o.id == obj for o in self.eng.objs):
            return
        top = self.eng.__dict__.setdefault("top", set())     # (los motores guardados de antes)
        if on:
            top.add(obj)
        else:
            top.discard(obj)

    def move_object(self, obj, xs, ys):
        """drawObject setXY: el objeto a (xs * 8, ys * 8) y su punto de llegada con el;
        se apuntan sus tiras de antes y las de ahora (DOSETXY)."""
        if not self.room:
            return
        o = next((o for o in self.eng.objs if o.id == obj), None)
        if o is None:
            return
        self.object_changed(obj)
        o.walk_x = s16v(o.walk_x + xs * 8 - o.x * 8)
        o.walk_y = s16v(o.walk_y + ys * 8 - o.y)
        o.x, o.y = xs & 0xFF, (ys * 8) & 0xFF
        self.object_changed(obj)

    def descends(self, j, k):
        objs = self.eng.objs
        for _ in range(16):
            if j == k:
                return True
            p = objs[j].parent
            if not p or p > len(objs):
                return False
            j = p - 1
        return False

    def object_in_room(self, obj):
        return self.room != 0 and any(o.id == obj for o in self.eng.objs)

    def object_name(self, obj):
        if not self.room:
            return None
        for o in self.eng.objs:
            if o.id == obj:
                return name_bytes(o.name)
        return None

    def object_data(self, obj):
        """Lo que se copia al inventario: verbos, codigo y nombre."""
        if not self.room:
            return None
        code = self.vm.room_code
        for o in self.eng.objs:
            if o.id == obj:
                return (list(code.get(("verbs", obj)) or []), bytes(code.get(("obj", obj)) or b""),
                        name_bytes(o.name))
        return None

    def object_walk_xy(self, obj):
        xyd = self.object_walk_xyd(obj)
        return None if xyd is None else xyd[:2]

    def object_walk_xyd(self, obj):
        """getObjectXYPos: a donde se anda y hacia donde se mira (o None si no esta)."""
        if not self.room:
            return None
        for o in self.eng.objs:
            if o.id == obj:
                return o.walk_x, o.walk_y, old_dir_to_new_dir(o.actor_dir)
        return None

    def object_or_actor_xy(self, obj):
        """getObjectOrActorXY: (x, y) o None."""
        V, vm = self.V, self.vm
        if obj < V.NUM_ACTORS:
            a = vm.actors[obj] if obj > 0 else None
            return (a.x, a.y) if a is not None and a.in_room() else None
        where = vm.where_is(obj)
        if where is None:
            return None
        if where == V.WIO_INVENTORY:
            own = vm.owner_of(obj)
            if 0 < own < V.NUM_ACTORS and vm.actors[own].in_room():
                return vm.actors[own].x, vm.actors[own].y
            return None
        return self.object_walk_xy(obj)

    def obj_act_dist(self, a, b):
        """getObjActToObjActDist."""
        V, vm = self.V, self.vm
        acta = vm.actors[a] if 0 < a < V.NUM_ACTORS else None
        actb = vm.actors[b] if 0 < b < V.NUM_ACTORS else None
        if acta and actb and acta.room == actb.room and acta.room and not acta.in_room():
            return 0
        p = self.object_or_actor_xy(a)
        if p is None:
            return 0xFF
        q = self.object_or_actor_xy(b)
        if q is None:
            return 0xFF
        x2, y2 = q
        if acta and not actb:
            x2, y2, _ = acta.adjust_xy(self.eng.boxes if self.eng else None, x2, y2) if self.eng else (x2, y2, 0)
        return max(abs(p[1] - y2), abs(p[0] - x2))

    def actor_from_pos(self, x, y):
        """getActorFromPos: el primer actor dibujado en esa tira y entre su arriba y abajo."""
        V, vm = self.V, self.vm
        s_ = x // 8
        for i in range(1, V.NUM_ACTORS):
            a = vm.actors[i]
            if a.strip0 == NO_STRIP or not a.strip0 <= s_ <= a.strip1:
                continue
            if vm.get_class(i, CLASS_UNTOUCHABLE):
                continue
            if a.top <= y <= a.bottom:
                return i
        return 0

    def same_rect(self, obj):
        if not self.room:
            return []
        objs = self.eng.objs
        me = [o for o in objs if o.id == obj]
        if not me:
            return []
        m = me[0]
        return [o.id for o in objs if o.id and (o.x, o.y, o.w, o.h) == (m.x, m.y, m.w, m.h)]

    def find_object(self, x, y):
        if not self.room:
            return 0
        objs = self.eng.objs
        for k, o in enumerate(objs):
            if not o.id or self.vm.get_class(o.id, self.V.CLASS_UNTOUCHABLE):
                continue
            b = k
            for _ in range(16):
                a = objs[b].parentstate
                p = objs[b].parent
                if not p:
                    if 8 * o.x <= x < 8 * (o.x + o.w) and o.y <= y < o.y + o.h:
                        return o.id
                    break
                if p > len(objs):
                    break
                b = p - 1
                if (self.vm.get_state(objs[b].id) & 0xF) != a:
                    break
        return 0

    def actor_talk_pos(self, act):
        """(x, y, elevacion, escala y) del actor que habla."""
        a = self.vm.actors[act]
        return a.x, a.y, a.elevation, a.scaley

    def camera_moving(self):
        c = self.eng.cam
        return c.cur >> 3 != c.dest >> 3

    def set_box_flags(self, b, f):
        if 0 <= b < len(self.eng.boxes.boxes):
            self.eng.boxes.boxes[b].flags = f & 0xFF

    def set_box_scale(self, b, sc):
        if 0 <= b < len(self.eng.boxes.boxes):
            self.eng.boxes.boxes[b].scale = sc & 0xFFFF

    def create_box_matrix(self):
        """matrixOps 4 (createBoxMatrix): la matriz de cajas otra vez, con los flags de
        ahora, si la habitacion trae la tabla de vecinas y la nueva cabe en su hueco
        (como el Z80, F_BOXMATRIX; si no, se queda la que habia). Al entrar en la
        habitacion vuelve la de la habitacion, como en SCUMM."""
        if not self.room or self.eng is None:
            return
        near, cap = self.eng.room.box_near
        bx = self.eng.boxes
        if near is None or not bx.boxes:
            return
        m = box_matrix(near, [bx.flags(b) for b in range(len(bx.boxes))])
        if len(m) > min(cap, BOXM_MAX):
            return
        bx.matrix = m
        bx.rebuilt = True

    # --- camara (camera.cpp) -------------------------------------------------------
    def set_camera_at(self, x):
        V, vm = self.V, self.vm
        cam = self.eng.cam
        if cam.mode != CAM_FOLLOW or abs(x - cam.cur) > SCREEN_W // 2:
            cam.cur = x
        cam.dest = x
        if cam.cur < vm.vars[V.VAR_CAMERA_MIN_X]:
            cam.cur = vm.vars[V.VAR_CAMERA_MIN_X]
        if cam.cur > vm.vars[V.VAR_CAMERA_MAX_X]:
            cam.cur = vm.vars[V.VAR_CAMERA_MAX_X]
        self.scroll_script()
        if cam.cur != self.ui.cam_last and self.ui.has_mask:
            self.ui.stop_talk()

    def scroll_script(self):
        V, vm = self.V, self.vm
        if vm.vars[V.VAR_SCROLL_SCRIPT]:
            vm.vars[V.VAR_CAMERA_POS_X] = self.eng.cam.cur
            vm.run_script(vm.vars[V.VAR_SCROLL_SCRIPT])

    def camera_at(self, x):
        """setCameraAt (setCameraAtEx): modo normal y salta a x."""
        if not self.room:
            return
        cam = self.eng.cam
        cam.mode = CAM_NORMAL
        cam.cur = x
        self.set_camera_at(x)
        cam.moving_to_actor = False

    def camera_pan(self, x):
        if self.room:
            self.eng.cam.pan(x)

    def cam_follows(self):
        return self.follows

    def actor_x(self, act):
        return self.vm.actor_xy(act)[0]

    def camera_follows(self, act):
        """actorFollowCamera / setCameraFollows: si el actor esta en otra habitacion, se va alli."""
        V, vm = self.V, self.vm
        self.follows = act
        if self.eng is not None:
            self.eng.cam.follows = act
            self.eng.cam.mode = CAM_FOLLOW
        if not vm.in_room(act):
            vm.change_room_from_script(vm.actors[act].room)
            if not self.room:
                return
            cam = self.eng.cam
            cam.mode = CAM_FOLLOW
            cam.cur = self.actor_x(act)
            self.set_camera_at(cam.cur)
        if not self.room:
            return
        cam = self.eng.cam
        t = (self.actor_x(act) >> 3) - cam.start_strip
        if t < 10 or t > 30:
            self.set_camera_at(self.actor_x(act))
        self.ui.run_inventory_script(0)
        cam.moving_to_actor = False

    # --- un paso -------------------------------------------------------------------------
    def tick(self, click=None, mouse=None, button=0, key=0):
        """click: andar directo a (x, y) de la habitacion (sin script de verbos);
        mouse: (x, y) de pantalla; button: 1 o 2; key: codigo de tecla."""
        if self.restart_req:                # systemOps 1 del paso anterior
            self.restart()
        V, vm, ui = self.V, self.vm, self.ui
        vm.timers()
        vm.decrease_delays()
        if mouse is not None:
            ui.mouse = mouse
        ui.set_mouse(*ui.mouse)
        if key:
            ui.key(key)
        if button:
            ui.click(button)
        vm.vars[V.VAR_HAVE_MSG] = ui.have_msg
        if self.room:
            vm.vars[V.VAR_CAMERA_POS_X] = self.eng.cam.cur
        vm.run_all()
        ui.check_exec_verbs()
        ui.check_sentence()
        self.frame = None
        if self.room:
            eng = self.eng
            if click is not None and not vm.vars[33 - 1] and self.ego_here():
                self.ego_actor().start_walk(eng.boxes, click[0], click[1], -1)
            vm.walk_actors()                # walkActors: todos los de la habitacion
            cam = eng.cam
            cam.min_x = vm.vars[V.VAR_CAMERA_MIN_X]
            cam.max_x = vm.vars[V.VAR_CAMERA_MAX_X]
            self.flush()
            old = cam.cur
            cam.move(self.actor_x(cam.follows))
            if cam.cur != old:
                self.scroll_script()
            if cam.cur != ui.cam_last and ui.has_mask:
                ui.stop_talk()              # (redrawBGAreas, v4-6: el texto se quita al moverse)
            ss = cam.start_strip
            if ss != self.l2ss:
                if abs(ss - self.l2ss) == 1:
                    new = ss if ss < self.l2ss else ss + 39
                    self.pstrip = new if new < eng.room.width // 8 else None
                else:
                    self.full_draw()
                    self.pstrip = None
                self.l2ss = ss
        ui.charset_1()
        if ui.cursor_state > 0:
            ui.verb_mouse(ui.find_verb_at(*ui.mouse))
        self.cycle_palette()                # (antes de los actores: sus colores salen de la paleta)
        self.update_shake()
        if self.room:
            eng = self.eng
            self.frame = self.draw_actors()
            eng.frame = self.frame
            if self.pstrip is not None:
                self.draw_strip(self.pstrip)
                self.pstrip = None
            ui.cam_last = eng.cam.cur
            vm.play_actor_sounds()          # (v5: despues de dibujar, solo en una habitacion)
        vm.process_sound()                  # scummLoop_handleSound, al final del paso
        return self.frame

    # --- los actores en sprites (processActors) ------------------------------------------
    def draw_actors(self):
        """processActors: los actores de la habitacion por y (como SCUMM), compuestos de
        delante atras, y despues animados. El actor n usa el banco de paleta n; de cada
        uno se apunta lo que ocupa (para actorFromPos)."""
        V, vm, eng = self.V, self.vm, self.eng
        fr = Frame()
        acts = [i for i in range(1, V.NUM_ACTORS) if vm.actors[i].in_room()]
        for i in range(1, V.NUM_ACTORS):
            if i not in acts:
                vm.actors[i].strip0 = vm.actors[i].strip1 = NO_STRIP
        ys = [vm.actors[i].y for i in acts]
        h, zp, bx, left = eng.room.height, eng.work_zp, eng.boxes, eng.cam.left()
        lights = vm.vars[V.VAR_CURRENT_LIGHTS]
        text = None                     # el texto con mascara, encima de los actores
        mr = self.ui.mask_rect
        if mr is not None:
            x0, x1 = max(mr[0], left), min(mr[2], left + SCREEN_W, eng.room.width)   # (KZCLIP)
            y0, y1 = max(mr[1], 0), min(mr[3], 200)
            if x0 < x1 and y0 < y1:
                text = (self.tmask, x0, y0, x1, y1)
        for i in reversed(sort_actors(acts, ys)):
            a = vm.actors[i]
            if not a.costume:
                continue
            c = a.get_cost()
            if c is not None:
                compose_into(fr, a, h, zp, bx, left, i, a.elevation, self.shake_y, cost=c, lights=lights,
                             text=text)
            else:
                a.strip0 = a.strip1 = NO_STRIP
            a.animate()
        return fr

    def costume_for(self, n):
        """El costume n: el del protagonista (paginas 80-82) o uno de la cache de
        la habitacion. Uno nuevo se carga detras del ultimo, si cabe antes de la
        pagina de los actores (y si no, o si no esta, se apunta que no hay)."""
        if n == self.cost.idx:
            return self.cost
        for num, c in self.ccache:
            if num == n:
                return c
        if len(self.ccache) >= COST_CACHE:
            return None
        c = self.costumes(n) if self.costumes else None
        if c is not None:
            pages = (len(c.blk) + 8191) >> 13
            if self.cc_next + pages > CAST_PAGE:
                c = None
            else:
                self.cc_next += pages
        self.ccache.append((n, c))
        return c

    def screen(self):
        """Indices de Layer 2 tal como se ven (256 x 320); con el temblor, todo baja
        shake_y filas (el desplazamiento Y de Layer 2 da la vuelta: arriba salen
        las filas negras de abajo)."""
        scroll = (self.l2ss % 40) * 8
        view = self.l2.view(scroll, self.ui.main_h)
        if self.shake_y:
            view = np.roll(view, self.shake_y, axis=0)
        return view

    # --- guardar, cargar y reiniciar ------------------------------------------------------
    def _memo(self):
        """Lo que no cambia, compartido en las copias (y el propio mundo)."""
        memo = {id(self.V): self.V, id(self): self}
        for o in (self.rooms, self.costumes, self.cost, self.vm.scripts, self.ui.charsets,
                  self.ui.verb_image, self.vm.room_code):
            memo[id(o)] = o
        if self.eng is not None:
            memo[id(self.eng.room)] = self.eng.room
            memo[id(self.eng.boxes)] = self.eng.boxes
        for _, c in self.ccache:
            if c is not None:
                memo[id(c)] = c
        return memo

    def snapshot(self):
        """Una partida guardada: lo mismo que la instantanea del Z80 (la maquina
        virtual, la interfaz, los actores, la paleta, los ciclos, el temblor, la
        camara, el protagonista y las cajas de la habitacion)."""
        memo = self._memo()
        snap = {"vmui": copy.deepcopy((self.vm, self.ui), memo), "room": self.room,
                "follows": self.follows, "ego_positioned": self.ego_positioned,
                "pal9": bytes(self.pal9), "cycles": copy.deepcopy(self.cycles),
                "shake": (self.shake_on, self.shake_frame, self.shake_y), "room_fx": self.room_fx}
        if self.eng is not None:
            snap["cam"] = copy.deepcopy(self.eng.cam)
            snap["boxes"] = copy.deepcopy(self.eng.boxes.boxes)
            snap["boxm"] = getattr(self.eng.boxes, "rebuilt", False)
        return snap

    def load_state(self, snap):
        """Cargar una partida (como el Z80): todo como estaba, la pantalla en negro,
        la habitacion otra vez (sin sus scripts) con su camara y su paleta, y los
        verbos pintados de nuevo. Los textos que habia en pantalla se pierden."""
        vm, ui = copy.deepcopy(snap["vmui"], self._memo())
        self.vm, self.ui = vm, ui
        vm.sound.after_load()
        self.room = snap["room"]
        self.follows = snap["follows"]
        self.ego_positioned = snap["ego_positioned"]
        self.pal9 = bytearray(snap["pal9"])
        self.cycles = copy.deepcopy(snap["cycles"])
        self.shake_on, self.shake_frame, self.shake_y = snap["shake"]
        self.room_fx = snap["room_fx"]
        self.l2 = L2Mem()
        self.tmask[:] = False
        self.pstrip = None
        self.dirty = set()
        self.frame = None
        self.ccache = []
        self.eng = None
        if self.room:
            rd = self.rooms(self.room_resource(self.room))
            vm.room_code = rd.code
            self.room_w = rd.width
            self.eng = Engine(rd, self.cost, vm_mode=True)
            self.eng.boxes.boxes = copy.deepcopy(snap["boxes"])
            if snap.get("boxm") or rd.box_matrix_own:   # (la matriz rehecha no se guarda:
                self.create_box_matrix()                # se rehace con los flags guardados)
            self.eng.cam = copy.deepcopy(snap["cam"])
            self.eng.cam.follows = self.follows
            self.pal8 = [tuple(int(v) & 0xFF for v in rgb) for rgb in list(rd.palette)[:256]]
            self.pal8 += [(0, 0, 0)] * (256 - len(self.pal8))
            self.rstamp = (self.rstamp + 1) & 0xFF
            self.cc_next = 27 + rd.data_pages
            self.eng.sync_states(vm.state)
            for a in vm.actors:
                a.boxes = self.eng.boxes
            self.load_draw()
        ui.has_mask = False
        ui.mask_rect = None
        ui.verb_rect = None
        self.fill_vs(1, 0, 0, SCREEN_W, 200 - ui.main_h, 0)
        for k in range(1, ui_num_verbs()):
            ui.draw_verb(k, 0)
        ui.verb_mouse_over = 0

    def restart(self):
        """systemOps 1: el juego desde el principio (VMINIT y el script 1)."""
        self._reinit()
        self.vm.run_script(1, args=[0])

    def _reinit(self):
        rooms, scripts, objects, cost, nvars, nbits, charsets, verb_image, costumes, sounds = self._init
        World.__init__(self, rooms, scripts, objects, cost, 0, nvars, nbits, charsets=charsets,
                       verb_image=verb_image, costumes=costumes, sounds=sounds)

    # --- paleta y pantalla (roomOps 4, 5, 6, 8, 10 y 11; ciclos de color) ---------------
    def set_pal_color(self, idx, r, g, b):
        """setPalColor: un color de la paleta que se ve."""
        i = idx & 0xFF
        self.pal9[2 * i:2 * i + 2] = bytes(next_color9(r & 0xFF, g & 0xFF, b & 0xFF))

    def darken(self, rs, gs, bs, start, end):
        """darkenPalette: los colores start..end de la habitacion por escala / 255
        (como mucho 255). Escalas de 16 bits sin signo (ScummVM las deja con signo;
        en los juegos son de 0 a 1000)."""
        if not self.room or start > end:
            return
        rs, gs, bs = rs & 0xFFFF, gs & 0xFFFF, bs & 0xFFFF
        for j in range(start, end + 1):
            r, g, b = self.pal8[j]
            self.pal9[2 * j:2 * j + 2] = bytes(next_color9(min(r * rs // 255, 255),
                                                           min(g * gs // 255, 255),
                                                           min(b * bs // 255, 255)))

    def cycle_palette(self):
        """cyclePalette: cada ciclo suma VAR_TIMER (o VAR_TIMER_NEXT si es mayor) y,
        al pasar de su delay, gira sus colores (hacia delante si no tiene el flag 2)."""
        vm = self.vm
        add = s16v(vm.vars[self.V.VAR_TIMER])
        nxt = s16v(vm.vars[VAR_TIMER_NEXT])
        if add < nxt:
            add = nxt
        for cy in self.cycles:
            if cy is None or not cy[0] or cy[3] > cy[4]:
                continue
            cy[1] = (cy[1] + add) & 0xFFFF
            if cy[1] >= cy[0]:
                cy[1] %= cy[0]
                a, b = cy[3], cy[4]
                if a == b:
                    continue
                ent = [bytes(self.pal9[2 * i:2 * i + 2]) for i in range(a, b + 1)]
                ent = ent[-1:] + ent[:-1] if not cy[2] & 2 else ent[1:] + ent[:1]
                self.pal9[2 * a:2 * b + 2] = b"".join(ent)

    def set_shake(self, on):
        self.shake_on = bool(on)
        self.shake_frame = 0
        self.shake_y = 0

    def update_shake(self):
        """drawDirtyScreenParts: con el temblor, la siguiente posicion; sin el, a 0."""
        if self.shake_on:
            self.shake_frame = (self.shake_frame + 1) % len(SHAKE_POS)
            self.shake_y = SHAKE_POS[self.shake_frame]
        elif self.shake_frame:
            self.shake_frame = 0
            self.shake_y = 0

    def room_effect(self, a):
        """roomOps 10: el efecto de las transiciones (solo se ve; 0: fadeIn ya)."""
        if a & 0xFFFF:
            self.room_fx = (a & 0xFF, (a >> 8) & 0xFF)


# ---------------------------------------------------------------------------
# Pantalla: Layer 2 (320x256) con la habitacion y los sprites del actor
# ---------------------------------------------------------------------------
def rgb9(hi, lo):
    """Los dos bytes de NR $44 -> RGB de 8 bits (como lo pintan los emuladores)."""
    r, g, b = hi >> 5, (hi >> 2) & 7, (hi & 3) << 1 | lo & 1
    return tuple(round(v * 255 / 7) for v in (r, g, b))


def palette_rgb(pal9):
    return np.array([rgb9(pal9[2 * i], pal9[2 * i + 1]) for i in range(len(pal9) // 2)],
                    dtype=np.uint8)


def sprite_bank(pal9, cost, cols=None):
    """Los colores (9 bits) del actor: la paleta de la habitacion vista a
    traves de la del costume (16, o 32 si es de 32 colores), o de cols."""
    out = bytearray()
    for i in range(cost.num_colors):
        c = cols[i] if cols is not None else (cost.palette[i] if i < len(cost.palette) else 0)
        out += pal9[2 * c:2 * c + 2]
    return bytes(out)


class Screen:
    def __init__(self, rd, pal9, cost):
        self.rd = rd
        self.pal9 = pal9
        self.rgb = palette_rgb(pal9)
        self.srgb = np.zeros((256, 3), dtype=np.uint8)
        first = PAL8 if cost.num_colors == 32 else 16 * ACTOR_BANK
        self.srgb[first:first + cost.num_colors] = palette_rgb(sprite_bank(pal9, cost))

    def set_palettes(self, frame):
        """Los colores que ha escrito el Z80 para los actores de este paso (en
        orden: si dos usan los mismos, se queda el ultimo)."""
        for first, cost, cols in frame.pals:
            self.srgb[first:first + cost.num_colors] = palette_rgb(sprite_bank(self.pal9, cost, cols))

    def layer2(self, left, bg=None):
        """Indices de Layer 2 tal como se ven (256 filas x 320 columnas)."""
        rd = self.rd
        bg = rd.bg if bg is None else bg
        out = np.zeros((256, 320), dtype=np.uint8)
        w = min(320, rd.width - left)
        out[ROOM_Y0:ROOM_Y0 + rd.height, :w] = bg[:, left:left + w]
        return out

    def render(self, left, frame, sprites=True, bg=None):
        img = self.rgb[self.layer2(left, bg)]
        if sprites and frame is not None:
            self.draw_sprites(img, frame)
        return img

    def draw_sprites(self, img, frame):
        self.set_palettes(frame)
        a = frame.attrs
        pats = bytes(frame.pats).ljust(SPR_BYTES, b"\0") + bytes(frame.pats8)   # (la memoria de patrones)
        for i in range(len(a) // 5):
            a0, a1, a2, a3, a4 = a[5 * i:5 * i + 5]
            if not a3 & 0x80:
                continue
            x = a0 | (a2 & 1) << 8
            y = a1 | (a4 & 1) << 8
            bank = a2 >> 4
            if a4 & 0x80:                   # 4 bits
                n = (a3 & 0x3F) << 1 | (a4 >> 6) & 1
                t = np.frombuffer(pats[128 * n:128 * n + 128], dtype=np.uint8).reshape(16, 8)
                px = np.zeros((16, 16), dtype=np.uint8)
                px[:, 0::2] = t >> 4
                px[:, 1::2] = t & 15
            else:                           # 8 bits: el indice ya es el color
                n = a3 & 0x3F
                px = np.frombuffer(pats[256 * n:256 * n + 256], dtype=np.uint8).reshape(16, 16)
                bank = 0
            for py in range(16):
                sy = (y + py) & 0x1FF
                if sy >= 256:
                    continue
                for qx in range(16):
                    sx = (x + qx) & 0x1FF
                    if px[py, qx] and sx < 320:
                        img[sy, sx] = self.srgb[(bank * 16 + px[py, qx]) & 255]
