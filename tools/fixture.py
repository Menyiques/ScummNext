"""Juego de prueba propio en formato SCUMM v5 (PRUEBA.000 / PRUEBA.001).

Sirve para probar el conversor y el motor sin datos de ningun juego comercial.
Todo esta dibujado aqui con codigo:

- habitacion 1, "patio": 640x144, un patio de piedra al atardecer con arcos,
  una puerta con escalones a la izquierda y dos columnas delante. Las columnas
  estan en el plano Z 1: el robot pasa por detras cuando anda por el fondo
  (cajas con mascara 1) y por delante en la parte de abajo (mascara 0).
  Objetos del patio: una puerta con dos estados (cerrada y abierta), un
  farol (encendido y apagado) con un resplandor que solo se ve si el farol
  esta encendido (objeto hijo), una barandilla con su propio plano Z que
  empieza escondida, y una zona sin imagen.
- habitacion 2, "almacen": 320x144, sin scroll, con una caja en diagonal.
- habitacion 3, "camino": 480x144, un camino que se aleja; las cajas usan una
  escala que va de 50 al fondo a 255 delante (y una caja con escala fija).
- costume 1: un robot pequeno con piernas, de perfil (este; el oeste es el
  mismo dibujo invertido), de frente y de espaldas, con ciclo de andar, quieto
  y hablando.
- costume 2: una tortuga grande (120 pixeles de ancho, 16 colores).
- costume 3: una medusa de 32 colores.
- scripts propios (tools/sasm.py): la entrada y la salida de cada habitacion,
  scripts locales, un cofre con scripts de verbo en el almacen y scripts
  globales que hacen parpadear el farol, cuentan, pasean a la tortuga y a la medusa,
  cambian de habitacion... para probar la maquina virtual.

    python tools/fixture.py [carpeta]      # por defecto build/prueba
"""
import math
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sasm as A  # noqa: E402
import scumm as S  # noqa: E402
from sasm import B, L, V  # noqa: E402

ROOT = os.path.dirname(HERE)

# --- paleta ------------------------------------------------------------------
SKY0, NSKY = 1, 48
SUN = 49
HILLF0 = 64             # colinas lejanas, 16 tonos
HILLN0 = 80             # colinas cercanas, 16
WALL0 = 96              # muro, 32
FLOOR0 = 128            # suelo, 32
COL0 = 160              # columnas, 32
DARK0 = 192             # sombras, 16
BOX0 = 208              # cajas del almacen, 16
ROBOT0 = 240            # colores del robot


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def ramp(pal, first, n, stops):
    """Rellena n colores interpolando entre varias paradas."""
    for i in range(n):
        t = i / max(1, n - 1) * (len(stops) - 1)
        k = min(int(t), len(stops) - 2)
        pal[first + i] = lerp(stops[k], stops[k + 1], t - k)


def make_palette():
    pal = [(0, 0, 0)] * 256
    ramp(pal, SKY0, NSKY, [(18, 22, 70), (70, 50, 120), (190, 90, 100), (245, 150, 80), (252, 210, 130)])
    pal[SUN] = (255, 240, 190)
    pal[SUN + 1] = (255, 220, 150)
    ramp(pal, HILLF0, 16, [(40, 45, 80), (110, 100, 130)])
    ramp(pal, HILLN0, 16, [(25, 45, 40), (70, 95, 70)])
    ramp(pal, WALL0, 32, [(60, 45, 45), (150, 110, 90), (225, 190, 150)])
    ramp(pal, FLOOR0, 32, [(55, 45, 50), (140, 115, 95), (200, 175, 140)])
    ramp(pal, COL0, 32, [(70, 65, 75), (170, 160, 150), (245, 238, 220)])
    ramp(pal, DARK0, 16, [(5, 5, 12), (45, 35, 45)])
    ramp(pal, BOX0, 16, [(60, 35, 20), (190, 130, 70)])
    robot = [(0, 0, 0), (18, 18, 28), (70, 80, 100), (125, 140, 165), (190, 205, 225),
             (30, 170, 200), (170, 250, 255), (200, 50, 40), (240, 150, 40), (250, 220, 80),
             (40, 40, 44), (255, 255, 255)]
    for i, c in enumerate(robot):
        pal[ROBOT0 + i] = c
    return pal


# --- dibujo de la habitacion 1 ----------------------------------------------
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def dith(v, x, y):
    """v en [0, n): indice con tramado ordenado entre dos tonos vecinos."""
    return np.floor(v + BAYER[y % 4, x % 4]).astype(int)


def patio():
    W, H = 640, 144
    ys, xs = np.mgrid[0:H, 0:W]
    img = np.zeros((H, W), dtype=np.uint8)
    # cielo
    sky = np.clip(ys / 74.0 * (NSKY - 1), 0, NSKY - 1)
    img[:] = SKY0 + np.clip(dith(sky, xs, ys), 0, NSKY - 1)
    sun = (xs - 470) ** 2 + (ys - 44) ** 2
    img[sun < 15 ** 2] = SUN + 1
    img[sun < 12 ** 2] = SUN
    # colinas
    far = 60 + 7 * np.sin(xs / 53.0) + 4 * np.sin(xs / 17.0 + 1.3)
    shade = np.clip((ys - far) / 2.5, 0, 15)
    m = ys >= far
    img[m] = (HILLF0 + 15 - np.clip(dith(shade, xs, ys), 0, 15))[m]
    near = 70 + 5 * np.sin(xs / 31.0 + 2.0) + 3 * np.sin(xs / 11.0)
    shade = np.clip((ys - near) / 2.0, 0, 15)
    m = ys >= near
    img[m] = (HILLN0 + 15 - np.clip(dith(shade, xs, ys), 0, 15))[m]
    # muro con arcos (los huecos dejan ver el paisaje)
    wall = (ys >= 52) & (ys < 101)
    ax = (xs - 64) % 128
    arch_hole = (np.abs(ax - 64) < 26) & (ys >= 66) & \
                ((ys >= 80) | ((ax - 64) ** 2 + (ys - 80) ** 2 < 26 ** 2))
    door = (xs >= 36) & (xs < 76) & (ys >= 68) & (ys < 101) & \
           ((ys >= 84) | ((xs - 56) ** 2 + (ys - 84) ** 2 < 20 ** 2))
    brick_row = (ys - 52) // 8
    bx = (xs + (brick_row % 2) * 12) % 24
    mortar = ((ys - 52) % 8 == 7) | (bx == 23)
    light = np.clip(20 - np.abs(((xs + 40) % 128) - 64) / 5.0 - (ys - 52) / 6.0, 0, 31)
    stone = WALL0 + np.clip(dith(light, xs, ys), 0, 31)
    stone = np.where(mortar, WALL0 + 3, stone)
    m = wall & ~arch_hole & ~door
    img[m] = stone[m]
    cornice = (ys >= 50) & (ys < 55)
    img[cornice] = (WALL0 + 26 - (ys - 50) * 3)[cornice]
    # sombra bajo los arcos y la puerta
    edge = arch_hole & (ys >= 97)
    img[edge] = DARK0 + 6
    inside = np.clip((ys - 68) / 3.0, 0, 9)
    img[door] = (DARK0 + np.clip(dith(inside, xs, ys), 0, 9))[door]
    # escalones de la puerta
    for k, (y0, x0, x1) in enumerate(((96, 40, 72), (99, 38, 74), (102, 36, 76))):
        img[y0:y0 + 3, x0:x1] = WALL0 + 22 - 4 * k
        img[y0 + 2, x0:x1] = WALL0 + 6
    # suelo en perspectiva
    fy = ys >= 101
    z = 900.0 / (ys - 70 + 0.001)
    u = (xs - 320) / (ys - 70 + 0.001) * 6
    tile = ((np.floor(z / 6) + np.floor(u / 1.0)) % 2).astype(int)
    fl = np.clip((ys - 101) / 43.0 * 20 + 6 + tile * 5, 0, 31)
    img[fy] = (FLOOR0 + np.clip(dith(fl, xs, ys), 0, 31))[fy]
    # columnas delante (plano Z 1)
    zp = np.zeros((H, W), dtype=bool)
    for cx in (184, 436):
        for y in range(8, 132):
            half = 13
            if y < 16:
                half = 18          # capitel
            elif y < 20:
                half = 15
            elif y >= 124:
                half = 17          # basa
            elif y >= 120:
                half = 15
            for x in range(cx - half, cx + half):
                t = (x - (cx - half)) / (2 * half)
                v = 31 * math.sin(math.pi * min(max(t * 1.15, 0), 1)) ** 0.7
                if y < 20 or y >= 120:
                    v = min(31, v + 3)
                img[y, x] = COL0 + int(np.clip(math.floor(v + BAYER[y % 4, x % 4]), 0, 31))
                zp[y, x] = True
        img[132:135, cx - 18:cx + 18] = DARK0 + 4          # sombra de la basa
    boxes = [
        S.Box((0, 0), (0, 0), (0, 0), (0, 0), 0, 0x80, 255),            # 0: no se usa
        S.Box((16, 104), (624, 104), (630, 116), (10, 116), 1, 0, 255),  # 1: fondo
        S.Box((10, 116), (630, 116), (639, 138), (0, 138), 0, 0, 255),   # 2: delante
        S.Box((44, 96), (68, 96), (72, 104), (40, 104), 1, 0, 255),      # 3: escalones
    ]
    return img, [zp], boxes


def almacen():
    W, H = 320, 144
    ys, xs = np.mgrid[0:H, 0:W]
    img = np.zeros((H, W), dtype=np.uint8)
    v = np.clip(ys / 144.0 * 12 + 2, 0, 15)
    img[:] = DARK0 + np.clip(dith(v, xs, ys), 0, 15)
    # suelo en diagonal y cajas apiladas
    fl = ys > 90 + (xs - 160) * 0.15
    img[fl] = (FLOOR0 + np.clip(dith(np.clip((ys - 90) / 54.0 * 22 + 4, 0, 31), xs, ys), 0, 31))[fl]
    zp = np.zeros((H, W), dtype=bool)
    for x0, y0, w, h in ((30, 40, 50, 56), (90, 60, 40, 36), (230, 30, 60, 70)):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                edge = x in (x0, x0 + w - 1) or y in (y0, y0 + h - 1) or (x - x0) == (y - y0) * w // h
                img[y, x] = BOX0 + (3 if edge else 10 + (x + y) % 3)
    for y in range(100, 136):                                # una caja delante (plano Z)
        for x in range(150, 186):
            edge = x in (150, 185) or y in (100, 135)
            img[y, x] = BOX0 + (2 if edge else 12)
            zp[y, x] = True
    boxes = [
        S.Box((0, 0), (0, 0), (0, 0), (0, 0), 0, 0x80, 255),
        S.Box((20, 100), (300, 120), (300, 132), (20, 112), 1, 0, 255),    # en diagonal
        S.Box((20, 112), (300, 132), (310, 140), (10, 140), 0, 0, 255),
    ]
    return img, [zp], boxes


# --- matriz de cajas -----------------------------------------------------------
def shares_edge(a, b):
    """Dos cajas se tocan si tienen un lado horizontal o vertical en comun."""
    ea = list(zip(a.corners(), a.corners()[1:] + a.corners()[:1]))
    eb = list(zip(b.corners(), b.corners()[1:] + b.corners()[:1]))
    for (p, q) in ea:
        for (r, s) in eb:
            if p[1] == q[1] == r[1] == s[1]:
                lo1, hi1 = sorted((p[0], q[0]))
                lo2, hi2 = sorted((r[0], s[0]))
                if min(hi1, hi2) > max(lo1, lo2):
                    return True
            if p[0] == q[0] == r[0] == s[0]:
                lo1, hi1 = sorted((p[1], q[1]))
                lo2, hi2 = sorted((r[1], s[1]))
                if min(hi1, hi2) > max(lo1, lo2):
                    return True
    return False


def box_matrix(boxes):
    n = len(boxes)
    adj = [[j for j in range(1, n) if j != i and shares_edge(boxes[i], boxes[j])] for i in range(n)]
    out = bytearray()
    for i in range(n):
        nxt = [255] * n
        if not i:
            nxt[0] = 0          # la caja 0 apunta a si misma, como en los juegos
        else:
            # BFS desde i: el primer paso hacia cada destino
            first = {i: i}
            q = [i]
            while q:
                c = q.pop(0)
                for j in adj[c]:
                    if j not in first:
                        first[j] = j if c == i else first[c]
                        q.append(j)
            for j, f in first.items():
                nxt[j] = f
        j = 0
        while j < n:
            if nxt[j] == 255:
                j += 1
                continue
            k = j
            while k + 1 < n and nxt[k + 1] == nxt[j]:
                k += 1
            out += bytes((j, k, nxt[j]))
            j = k + 1
        out.append(0xFF)
    return bytes(out)


# --- el robot --------------------------------------------------------------------
OUT, MDARK, MMID, MLIGHT, VISOR, GLOW, RED, ORANGE, YELLOW, RUBBER, WHITE = range(1, 12)


def canvas(w, h):
    return np.zeros((h, w), dtype=np.uint8)


def rect(c, x0, y0, x1, y1, col, outline=True):
    c[y0:y1, x0:x1] = col
    if outline:
        c[y0, x0:x1] = OUT
        c[y1 - 1, x0:x1] = OUT
        c[y0:y1, x0] = OUT
        c[y0:y1, x1 - 1] = OUT


def body_side(talk=0):
    c = canvas(20, 32)
    # antena
    c[0:2, 8:10] = RED if talk != 1 else YELLOW
    c[2:6, 8] = OUT
    # cabeza
    rect(c, 3, 5, 17, 17, MMID)
    c[6, 4:16] = MLIGHT
    c[8:13, 11:16] = VISOR                      # visera mirando al este
    c[9, 13:15] = GLOW
    c[13, 4:16] = MDARK
    # cuerpo
    rect(c, 2, 17, 18, 32, MMID)
    c[18:31, 3:6] = MLIGHT
    c[21:24, 10:15] = ORANGE
    c[25, 10:15] = MDARK
    c[27:30, 6:9] = MDARK                       # brazo
    return c


def body_front(talk=0):
    c = canvas(22, 32)
    c[0:2, 10:12] = RED if talk != 1 else YELLOW
    c[2:6, 10] = OUT
    rect(c, 3, 5, 19, 17, MMID)
    c[6, 4:18] = MLIGHT
    c[8:12, 6:16] = VISOR
    c[9, 8:10] = GLOW
    c[9, 12:14] = GLOW
    if talk == 2:
        c[13:15, 8:14] = OUT                    # boca abierta
    else:
        c[14, 8:14] = OUT
    rect(c, 2, 17, 20, 32, MMID)
    c[18:31, 3:5] = MLIGHT
    c[20:25, 8:14] = ORANGE
    c[22, 9:13] = YELLOW
    c[18:30, 0:2] = MDARK                       # brazos
    c[18:30, 20:22] = MDARK
    c[18, 0:2] = OUT
    c[18, 20:22] = OUT
    return c


def body_back():
    c = canvas(22, 32)
    c[0:2, 10:12] = RED
    c[2:6, 10] = OUT
    rect(c, 3, 5, 19, 17, MMID)
    c[6, 4:18] = MLIGHT
    c[9:13, 8:14] = MDARK
    rect(c, 2, 17, 20, 32, MMID)
    c[18:31, 17:19] = MLIGHT
    rect(c, 7, 20, 15, 28, MDARK)
    c[23, 9:13] = RED
    c[18:30, 0:2] = MDARK
    c[18:30, 20:22] = MDARK
    return c


def legs_side(phase):
    """phase 0 quieto, 1-4 ciclo de andar (de perfil)."""
    c = canvas(18, 14)
    offs = {0: (0, 0), 1: (-3, 3), 2: (0, 0), 3: (3, -3), 4: (0, 0)}[phase]
    lift = {0: (0, 0), 1: (0, 1), 2: (1, 0), 3: (1, 0), 4: (0, 1)}[phase]
    for k, (dx, up) in enumerate(zip(offs, lift)):
        x = 7 + dx + (k * 2 - 1)
        col = MDARK if k == 0 else MMID
        c[0:11 - up, x:x + 3] = col
        c[0:11 - up, x] = OUT
        c[11 - up:13 - up, x - 1:x + 5] = RUBBER
        c[13 - up, x - 1:x + 5] = OUT
    return c


def legs_front(phase):
    c = canvas(18, 14)
    lift = {0: (0, 0), 1: (2, 0), 2: (0, 0), 3: (0, 2), 4: (0, 0)}[phase]
    for k, x in enumerate((4, 10)):
        up = lift[k]
        c[0:11 - up, x:x + 4] = MMID
        c[0:11 - up, x] = OUT
        c[0:11 - up, x + 3] = OUT
        c[11 - up:13 - up, x - 1:x + 5] = RUBBER
        c[13 - up, x - 1:x + 5] = OUT
    return c


def pic(px, rel_x, rel_y):
    h, w = px.shape
    return S.Picture(w, h, rel_x, rel_y, 0, 0, px)


def robot():
    """Costume del robot. Miembro 0: piernas; miembro 1: cuerpo y cabeza."""
    legs = [pic(legs_side(p), -9, -14) for p in range(5)] + \
           [pic(legs_front(p), -9, -14) for p in range(5)]
    body = []
    for d in ("side", "front", "back"):
        for bob in (0, 1):
            px = {"side": body_side, "front": body_front}.get(d, lambda talk=0: body_back())()
            body.append(pic(px, -10 if d == "side" else -11, -45 + bob))
    body.append(pic(body_front(1), -11, -45))      # 6: hablando
    body.append(pic(body_front(2), -11, -45))      # 7
    body.append(pic(body_side(1), -10, -45))       # 8
    # codigos por direccion: (piernas quieto, piernas andando, cuerpo, cuerpo con salto)
    side = (0, [1, 2, 3, 4], 0, 1)
    front = (5, [6, 7, 8, 9], 2, 3)
    back = (5, [6, 7, 8, 9], 4, 5)
    per_dir = {0: side, 1: side, 2: front, 3: back}
    anims = []
    for frame in range(6):
        for d in range(4):
            stand_l, walk_l, b0, b1 = per_dir[d]
            if frame in (1, 3, 5):                     # inicio, quieto, fin de hablar
                anims.append([(0, [stand_l], True), (1, [b0], True)])
            elif frame == 2:                           # andar
                anims.append([(0, walk_l, False), (1, [b0, b1, b0, b1], False)])
            elif frame == 4:                           # hablar
                talk = [6, 7, 2, 7] if d in (2, 3) else [8, 0]
                anims.append([(1, talk, False)])
            else:
                anims.append(None)
    pal = [0] + [ROBOT0 + i for i in range(1, 12)] + [0] * 4
    return S.encode_costume(23, pal, anims, {0: legs, 1: body})


# --- objetos del patio ------------------------------------------------------------
class FObj:
    """Objeto del juego de prueba: x y ancho en tiras, y y alto en pixeles."""

    def __init__(self, oid, name, x, y, w, h, state, images, parent=0, parentstate=0, verbs=None, adir=0):
        self.oid, self.name, self.x, self.y, self.w, self.h = oid, name, x, y, w, h
        self.adir = adir                            # hacia donde se mira al llegar (0-3)
        self.state, self.images = state, images     # images: [(pix, opaco, {plano: mascara})]
        self.parent, self.parentstate = parent, parentstate
        self.verbs = verbs or {}                    # {verbo: codigo}


def door_images():
    w, h = 48, 40
    ys, xs = np.mgrid[0:h, 0:w]
    shape = (np.abs(xs - 23.5) < 20) & ((ys >= 20) | ((xs - 23.5) ** 2 + (ys - 20) ** 2 < 20 ** 2))
    closed = np.where((xs - 3) % 8 == 0, BOX0 + 2, BOX0 + 8 + (ys // 3) % 3).astype(np.uint8)
    closed[(ys == 22) | (ys == 23)] = BOX0 + 1
    closed[18:21, 34:37] = ROBOT0 + 9                      # tirador
    opened = np.clip(DARK0 + 10 - (np.abs(xs - 24) // 3), DARK0, DARK0 + 15).astype(np.uint8)
    opened[(xs - 24) ** 2 + (ys - 30) ** 2 < 36] = ROBOT0 + 9
    opened[(np.abs(xs - 24) < 2) & (ys > 6)] = ROBOT0 + 8
    return [(closed, shape, {}), (opened, shape, {})]


def lamp_images():
    w, h = 24, 24
    ys, xs = np.mgrid[0:h, 0:w]
    body = (np.abs(xs - 11.5) < 6) & (ys >= 6) & (ys < 20)
    hook = (np.abs(xs - 11.5) < 1) & (ys < 6)
    lit = np.where(body, ROBOT0 + 9, ROBOT0 + 1).astype(np.uint8)
    lit[(np.abs(xs - 11.5) < 3) & (ys >= 9) & (ys < 17)] = ROBOT0 + 11
    lit[body & ((ys == 6) | (ys == 19))] = ROBOT0 + 1
    off = np.where(body, ROBOT0 + 2, ROBOT0 + 1).astype(np.uint8)
    off[body & ((ys == 6) | (ys == 19))] = ROBOT0 + 1
    return [(lit, body | hook, {}), (off, body | hook, {})]


def glow_images():
    w, h = 32, 16
    ys, xs = np.mgrid[0:h, 0:w]
    d = ((xs - 15.5) / 15.0) ** 2 + (ys / 15.0) ** 2
    pix = np.where(d < 0.3, ROBOT0 + 9, ROBOT0 + 8).astype(np.uint8)
    opaque = (d < 1.0) & ((xs + ys) % 2 == 0)             # tramado: deja ver el fondo
    return [(pix, opaque, {})]


def fence_images():
    w, h = 64, 24
    ys, xs = np.mgrid[0:h, 0:w]
    rail = (ys < 4) | ((ys >= 20) & (ys < 24))
    bars = (xs % 8 < 3) & (ys >= 4) & (ys < 20)
    shape = rail | bars
    pix = np.where(rail, WALL0 + 24, WALL0 + 14).astype(np.uint8)
    return [(pix, shape, {1: shape})]


def patio_objects():
    import fixture_ui as U
    return [
        FObj(100, "puerta", 4, 64, 6, 40, 1, door_images(), verbs=U.door_verbs()),
        FObj(101, "farol", 56, 40, 3, 24, 1, lamp_images(), verbs=U.lamp_verbs()),
        FObj(102, "luz", 55, 64, 4, 16, 1, glow_images(), parent=2, parentstate=1),
        FObj(103, "barandilla", 32, 104, 8, 24, 0, fence_images()),
        FObj(104, "sol", 56, 24, 4, 32, 0, [], verbs=U.sun_verbs(), adir=3),
        FObj(106, "moneda", 40, 128, 2, 8, 1, U.coin_image(), verbs=U.coin_verbs(), adir=1),
    ]


def chest_images():
    w, h = 32, 24
    ys, xs = np.mgrid[0:h, 0:w]
    box = (ys >= 8)
    closed = np.where(box, BOX0 + 10, BOX0 + 6).astype(np.uint8)
    closed[(ys == 8) | (xs == 0) | (xs == w - 1) | (ys == h - 1)] = BOX0 + 2
    closed[12:15, 14:18] = ROBOT0 + 9
    opened = closed.copy()
    opened[0:8, 2:30] = BOX0 + 4
    opened[9:12, 3:29] = DARK0 + 2
    return [(closed, box, {}), (opened, box | ((ys < 8) & (xs >= 2) & (xs < 30)), {})]


def chest_verbs():
    a = A.Asm()                             # verbo 1: abrir
    a.set_state(105, 2)
    a.inc(V(125))
    a.stop()
    b = A.Asm()                             # cualquier otro verbo
    b.mov(V(126), 7)
    b.stop()
    return {1: a.finish(), 0xFF: b.finish()}


def almacen_objects():
    return [FObj(105, "cofre", 12, 104, 4, 24, 0, chest_images(), verbs=chest_verbs())]


# --- scripts de prueba -----------------------------------------------------------
def global_scripts():
    sc = {}
    a = A.Asm()                             # 10: el farol parpadea tres veces
    a.mov(L(0), 0)
    a.label("top")
    a.set_state(101, 2)
    a.delay(25)
    a.set_state(101, 1)
    a.delay(15)
    a.inc(L(0))
    a.if_eq(L(0), 3, "top")
    a.mov(V(111), 1)
    a.stop()
    sc[10] = a.finish()
    a = A.Asm()                             # 11: cuenta pasos hasta 30
    a.label("top")
    a.inc(V(112))
    a.if_eq(V(112), 30, "more")
    a.stop()
    a.label("more")
    a.brk()
    a.jump("top")
    sc[11] = a.finish()
    a = A.Asm()                             # 12: una escena con un texto
    a.cutscene([5])
    a.override("skip")
    a.print_(2, "Hola", at=(160, 30))
    a.wait(2)
    a.end_override()
    a.label("skip")
    a.end_cutscene()
    a.mov(V(122), 1)
    a.stop()
    sc[12] = a.finish()
    a = A.Asm()                             # 13: la tortuga pasea por el patio (delante
    a.put_in_room(2, 1)                     # de las columnas y despues detras)
    a.put_actor(2, 100, 120)
    a.actor_costume(2, 2)
    a.label("top")
    a.walk_actor(2, 300, 134)
    a.wait(1, 2)
    a.walk_actor(2, 100, 110)
    a.wait(1, 2)
    a.get_actor_x(V(127), 2)
    a.inc(V(113))
    a.if_eq(V(113), 2, "top")
    a.stop()
    sc[13] = a.finish()
    a = A.Asm()                             # 14: cambia de habitacion al rato
    a.delay(200)
    a.load_room(2)
    a.mov(V(123), 1)
    a.stop()
    sc[14] = a.finish()
    a = A.Asm()                             # 15: clases
    a.set_class(103, [0x85, 0x86, 7])
    a.if_class(103, [0x85, 0x86, 7], "no")
    a.set_state(103, 1)
    a.label("no")
    a.stop()
    sc[15] = a.finish()
    a = A.Asm()                             # 16: duenos
    a.set_owner(102, 2)
    a.get_owner(V(114), 102)
    a.pickup(103)
    a.get_owner(V(115), 103)
    a.get_state(V(124), 103)
    a.stop()
    sc[16] = a.finish()
    a = A.Asm()                             # 17: la medusa (32 colores) flota por el camino,
    a.put_in_room(3, 3)                     # con escala y elevacion
    a.actor(3, ("costume", 3), ("elevation", 12))
    a.put_actor(3, 300, 84)
    a.mov(V(131), 0)
    a.label("top")
    a.walk_actor(3, 260, 132)
    a.wait(1, 3)
    a.walk_actor(3, 300, 84)
    a.wait(1, 3)
    a.inc(V(131))
    a.if_eq(V(131), 3, "top")
    a.stop()
    sc[17] = a.finish()
    a = A.Asm()                             # 18: otra tortuga (actor 4) que lo hace todo:
    a.mov(V(15), 1)                         # actorOps, animar, girar, andar hasta otro actor
    a.mov(V(16), 12)                        # y hasta un objeto, sin cajas, preguntas...
    a.put_in_room(4, 1)
    a.actor(4, ("costume", 2), ("speed", 4, 1), ("animspeed", 2), ("palette", 3, 40),
            ("talkcolor", 9), ("width", 30), ("talkframes", 4, 5), ("walkframe", 2), ("standframe", 3))
    a.put_actor(4, 520, 130)
    a.animate_actor(4, 250)                 # mira al sur ya
    a.actor_query(V(132), "facing", 4)
    a.animate_actor(4, 245)                 # y gira hacia el este
    a.wait(1, 4)
    a.face_actor(4, 1)                      # hacia el protagonista
    a.wait(1, 4)
    a.walk_to_actor(4, 1, 255)
    a.wait(1, 4)
    for i, q in enumerate(("room", "costume", "facing", "walkbox", "width", "scale", "elevation",
                           "animcounter")):
        a.actor_query(V(133 + i), q, 4)
    a.get_actor_x(V(141), 104)              # donde se anda para un objeto
    a.get_actor_y(V(142), 104)
    a.get_dist(V(143), 1, 4)
    a.get_dist(V(144), 4, 104)
    a.closest_actor(V(145), 1)
    a.get_actor_x(V(147), 4)
    a.get_actor_y(V(148), 4)
    a.dec(V(148))
    a.actor_from_pos(V(146), V(147), V(148))
    a.mov(V(149), 0)
    a.if_actor_in_box(4, 2, "nobox")
    a.mov(V(149), 1)
    a.label("nobox")
    a.say(4, [("overhead",), ("text", b"Bah\xff\x09\x06\x01 bah")])
    a.walk_to_object(4, 104)                # al sol (y mira al norte)
    a.wait(1, 4)
    a.wait(2)
    a.actor(4, ("ignoreboxes",))            # por donde no hay cajas
    a.walk_actor(4, 420, 70)
    a.wait(1, 4)
    a.actor(4, ("followboxes",), ("scale", 180, 180), ("alwayszclip", 1))
    a.walk_actor(4, 200, 126)
    a.wait(1, 4)
    a.actor(4, ("neverzclip",), ("speed", 8, 2), ("elevation", 6), ("sound", SND_BELL))
    a.set_class(4, [0x80 | 20])             # nunca tapado
    a.mov(V(23), 0)                         # VAR_LAST_SOUND
    a.animate_actor(4, 6)                   # cabecea: cada vuelta pasa por un $78 (sonido)
    a.delay(50)
    a.mov(V(152), V(23))                    # SND_BELL: la ha puesto playActorSounds
    a.sound_running(V(153), SND_BELL)
    a.put_at_object(4, 106)                 # junto a la moneda
    a.animate_actor(4, 255)
    a.actor_query(V(150), "moving", 4)
    a.actor(4, ("init",), ("defaultframes",), ("initframe", 1), ("costume", 2))
    a.put_in_room(4, 0)
    a.mov(V(151), 1)
    a.stop()
    sc[18] = a.finish()
    return sc


def patio_scripts():
    e = A.Asm()                             # entrada
    e.inc(V(120))
    e.if_zero(B(101), "open")
    e.set_state(100, 1)
    e.jump("door")
    e.label("open")
    e.set_state(100, 2)
    e.label("door")
    e.expr(V(100), [("push", V(120)), ("push", 3), ("add",), ("push", 2), ("mul",), ("push", 1), ("sub",)])
    e.set_var_range(V(105), [7, 8, 9])
    e.random(V(110), 9)
    e.cursor(1)
    e.verb_ops(1, "Abrir")
    e.object_name(104, "sol")
    e.sound(3)
    for n in (10, 11, 15, 16, 200, 12, 13, 18):
        e.start_script(n)
    e.is_running(V(116), 10)
    e.start_script(201)
    e.stop()
    x = A.Asm()                             # salida
    x.mov(B(101), 1)
    x.inc(V(121))
    x.stop()
    l200 = A.Asm()                          # local 200: mira por la habitacion
    l200.label("top")
    l200.get_actor_x(V(117), 1)
    l200.find_object(V(118), 60, 80)
    l200.delay(10)
    l200.inc(V(119))
    l200.if_eq(V(119), 5, "top")
    l200.print_ego("Bip")
    l200.wait(2)
    l200.stop()
    l201 = A.Asm()                          # local 201: congela a los demas un rato
    l201.freeze(1)
    l201.delay(30)
    l201.freeze(0)
    l201.mov(V(128), 1)
    l201.stop()
    return {"encd": e.finish(), "excd": x.finish(), 200: l200.finish(), 201: l201.finish()}


def almacen_scripts():
    e = A.Asm()
    e.if_zero(V(121), "skip")
    e.set_state(105, 1)
    e.label("skip")
    e.start_object(105, 1)
    e.start_object(105, 9)
    e.draw_object(105)
    e.get_state(V(129), 105)
    e.draw_box(0, 197, 319, 199, 248)
    e.room_intensity(200, 1, 239)               # el almacen, algo mas oscuro (sin el robot)
    e.room_scroll(100, 900)                     # (fuera del ancho: se queda en 160, 160)
    e.if_eq(V(4), 201, "nopseudo")              # entrando como la 201 (prueba pseudo): el
    e.draw_object_at(105, 24, 13)               # cofre a (192, 104), con setXY
    e.label("nopseudo")
    e.room_effect(0x0101)                       # de aqui se sale y se entra con el iris
    e.stop()
    return {"encd": e.finish()}


def camino_scripts():
    e = A.Asm()
    e.camera_at(400)
    e.room_scroll(160, 300)
    e.walk_actor(1, 240, 75)
    e.start_script(14)
    e.lights(5, 0, 0)
    e.box_flags(4, 0x80)
    e.camera_pan(160)
    e.start_script(200)
    e.start_script(17)
    e.verbs_save(1, 1, 7, 1)
    e.room_effect(0x8080)                       # y del camino, disolviendo
    e.stop()
    x = A.Asm()
    x.verbs_save(2, 1, 7, 1)
    x.stop()
    l200 = A.Asm()
    l200.wait(3)
    l200.camera_follow(1)
    l200.mov(V(130), 1)
    l200.stop()
    return {"encd": e.finish(), "excd": x.finish(), 200: l200.finish()}


# --- habitacion 3: un camino que se aleja (escalado) -----------------------------
def camino():
    W, H = 480, 144
    ys, xs = np.mgrid[0:H, 0:W]
    img = np.zeros((H, W), dtype=np.uint8)
    sky = np.clip(ys / 60.0 * (NSKY - 1), 0, NSKY - 1)
    img[:] = SKY0 + np.clip(dith(sky, xs, ys), 0, NSKY - 1)
    far = 52 + 6 * np.sin(xs / 41.0) + 3 * np.sin(xs / 13.0 + 0.5)
    m = ys >= far
    img[m] = (HILLF0 + 15 - np.clip(dith(np.clip((ys - far) / 2.0, 0, 15), xs, ys), 0, 15))[m]
    grass = ys >= 66
    img[grass] = (HILLN0 + np.clip(dith(np.clip((ys - 66) / 78.0 * 14 + 1, 0, 15), xs, ys), 0, 15))[grass]
    # el camino: de 40 pixeles al fondo (y=66) a 300 delante (y=144)
    t = np.clip((ys - 66) / 78.0, 0, 1)
    half = 20 + t * 130
    road = grass & (np.abs(xs - 240) < half)
    img[road] = (FLOOR0 + np.clip(dith(t * 18 + 6, xs, ys), 0, 31))[road]
    stripe = road & (np.abs(xs - 240) < 1 + t * 3) & ((np.clip(ys - 66, 0, None) ** 1.3).astype(int) % 9 < 4)
    img[stripe] = ROBOT0 + 11
    zp = np.zeros((H, W), dtype=bool)
    boxes = [
        S.Box((0, 0), (0, 0), (0, 0), (0, 0), 0, 0x80, 255),
        S.Box((140, 120), (380, 120), (380, 140), (100, 140), 0, 0, 0x8000),   # delante
        S.Box((190, 90), (290, 90), (340, 120), (140, 120), 0, 0, 0x8000),     # en medio
        S.Box((220, 70), (260, 70), (290, 90), (190, 90), 0, 0, 0x8000),       # al fondo
        S.Box((380, 120), (470, 120), (470, 140), (380, 140), 0, 0, 160),      # escala fija
    ]
    scal = [(50, 70, 255, 140), (0, 0, 0, 0), (0, 0, 0, 0), (0, 0, 0, 0)]
    return img, [zp], boxes, scal


# --- costumes grandes -------------------------------------------------------------
def turtle():
    """Tortuga de 120 pixeles de ancho, 16 colores. Miembro 0: cuerpo; 1: cabeza."""
    def shell(squash):
        w, h = 120, 64 - squash
        ys, xs = np.mgrid[0:h, 0:w]
        e = ((xs - 59.5) / 58.0) ** 2 + ((ys - h + 0.5) / (h - 1.0)) ** 2
        c = np.zeros((h, w), dtype=np.uint8)
        inside = e < 1.0
        hexes = ((xs // 12 + (ys // 10) % 2) % 2 == 0)
        c[inside] = np.where(hexes, 6, 5)[inside]
        c[inside & (e > 0.8)] = 3
        c[inside & (ys < h * 0.35) & (e < 0.5)] = 8
        c[(e >= 0.9) & (e < 1.0)] = 1
        for fx in (14, 92):                                  # patas
            c[h - 6:h, fx:fx + 14] = 4
            c[h - 1, fx:fx + 14] = 1
        return c

    def head(blink):
        c = np.zeros((26, 28), dtype=np.uint8)
        ys, xs = np.mgrid[0:26, 0:28]
        e = ((xs - 13.5) / 13.0) ** 2 + ((ys - 12.5) / 12.0) ** 2
        c[e < 1] = 4
        c[(e >= 0.85) & (e < 1)] = 1
        if blink:
            c[9, 15:21] = 1
        else:
            c[7:12, 15:21] = 9
            c[8:11, 17:20] = 10
        c[17, 14:24] = 11
        return c

    body = [S.Picture(120, 64, -60, -64, 0, 0, shell(0)),
            S.Picture(120, 61, -60, -61, 0, 0, shell(3))]
    heads = [S.Picture(28, 26, 50, -50, 0, 0, head(0)),
             S.Picture(28, 26, 50, -48, 0, 0, head(1))]
    anims = []
    for frame in range(7):
        for d in range(4):
            if frame in (1, 3, 5):
                anims.append([(0, [0], True), (1, [0, 0, 0, 1], False)])
            elif frame == 2:
                anims.append([(0, [0, 1], False), (1, [0, 1], False)])
            elif frame == 4:
                anims.append([(1, [0, 1], False)])
            elif frame == 6:                # cabecea; $78: sonido en cada vuelta
                anims.append([(1, [0, 0x78, 1], False)])
            else:
                anims.append(None)
    pal = [0, ROBOT0 + 1, HILLN0 + 2, HILLN0 + 5, HILLN0 + 9, HILLN0 + 12, HILLN0 + 15,
           BOX0 + 6, BOX0 + 12, ROBOT0 + 11, ROBOT0 + 1, ROBOT0 + 7] + [0] * 4
    return S.encode_costume(27, pal, anims, {0: body, 1: heads}, no_mirror=False)


def jellyfish():
    """Medusa de 32 colores (formato 0x59): una campana con 31 tonos y tentaculos."""
    def bell(phase):
        w, h = 40, 56
        ys, xs = np.mgrid[0:h, 0:w]
        c = np.zeros((h, w), dtype=np.uint8)
        e = ((xs - 19.5) / 19.0) ** 2 + ((ys - 22) / 22.0) ** 2
        dome = (e < 1) & (ys < 23)
        c[dome] = np.clip(1 + (ys[dome] * 30) // 22, 1, 31)
        for k in range(6):                                   # tentaculos
            x0 = 4 + k * 6
            for y in range(23, h):
                x = int(x0 + 2 * np.sin((y + phase * 4 + k * 3) / 4.0))
                if 0 <= x < w:
                    c[y, x] = 31 - (y - 23) // 2 % 30
        return c
    pics = [S.Picture(40, 56, -20, -56, 0, 0, bell(p)) for p in range(2)]
    anims = []
    for frame in range(6):
        for d in range(4):
            if frame in (1, 3, 5):
                anims.append([(0, [0, 1], False)])
            elif frame == 2:
                anims.append([(0, [0, 1], False)])
            else:
                anims.append(None)
    pal = [0] + [SKY0 + i for i in range(31)]
    return S.encode_costume(23, pal, anims, {0: pics}, colors=32)


# --- ficheros ----------------------------------------------------------------
def object_blocks(objs):
    """OBIM y OBCD de cada objeto (en el mismo orden)."""
    out = b""
    for o in objs:
        ims = S.make_block("IMHD", struct.pack("<HHHBBHHHH", o.oid, len(o.images), 0, 0, 0, 0, 0,
                                                o.w * 8, o.h))
        for n, (pix, opaque, planes) in enumerate(o.images):
            img = np.where(opaque, pix, 0).astype(np.uint8)    # TRNS = 0
            body = S.encode_smap(img, "mix")
            for pl, m in planes.items():
                body += S.encode_zplane("ZP%02d" % pl, m)
            ims += S.make_block("IM%02d" % (n + 1), body)
        out += S.make_block("OBIM", ims)
    for o in objs:
        cd = S.encode_cdhd(o.oid, o.x, o.y, o.w, o.h, o.parent, o.parentstate, o.adir)
        out += S.make_block("OBCD", cd + verb_block(o.verbs) +
                            S.make_block("OBNA", o.name.encode() + b"\0"))
    return out


def verb_block(verbs):
    """VERB: (verbo, offset) por entrada y un 0; los offsets cuentan desde el
    principio del bloque, con su cabecera de 8 bytes."""
    table_len = 3 * len(verbs) + 1
    table = bytearray()
    code = bytearray()
    for v, c in verbs.items():
        table += struct.pack("<BH", v, 8 + table_len + len(code))
        code += c
    return S.make_block("VERB", bytes(table) + b"\0" + bytes(code))


def room_block(img, zps, boxes, pal, objs=(), scal=None, scripts=None, cycles=()):
    H, W = img.shape
    rmhd = S.make_block("RMHD", struct.pack("<3H", W, H, len(objs)))
    cycl = S.make_block("CYCL", S.encode_cycles(cycles))
    trns = S.make_block("TRNS", struct.pack("<H", 0))
    epal = S.make_block("EPAL", bytes(256))
    boxd = S.make_block("BOXD", struct.pack("<H", len(boxes)) + b"".join(b.pack() for b in boxes))
    boxm = S.make_block("BOXM", box_matrix(boxes))
    clut = S.make_block("CLUT", bytes(v for c in pal for v in c))
    scal = S.make_block("SCAL", b"".join(struct.pack("<4H", *sl) for sl in scal) if scal else bytes(32))
    im = S.encode_smap(img, "mix")
    for i, z in enumerate(zps):
        im += S.encode_zplane("ZP%02d" % (i + 1), z)
    rmim = S.make_block("RMIM", S.make_block("RMIH", struct.pack("<H", len(zps))) +
                        S.make_block("IM00", im))
    scripts = scripts or {}
    excd = S.make_block("EXCD", scripts.get("excd", b"\x00"))
    encd = S.make_block("ENCD", scripts.get("encd", b"\x00"))
    locs = [k for k in scripts if isinstance(k, int)]
    nlsc = S.make_block("NLSC", struct.pack("<H", len(locs)))
    lscr = b"".join(S.make_block("LSCR", bytes((k,)) + scripts[k]) for k in sorted(locs))
    return S.make_block("ROOM", rmhd + cycl + trns + epal + boxd + boxm + clut + scal +
                        rmim + object_blocks(objs) + excd + encd + nlsc + lscr)


# ---------------------------------------------------------------------------
# Sonido: dos efectos digitalizados, dos pistas de "CD" y dos de AdLib (musica de iMuse:
# 7 da vueltas, 8 acaba)
# ---------------------------------------------------------------------------
SND_BELL, SND_BUZZ, SND_TRACK, SND_LOOP, SND_ADL, SND_ADL2 = 3, 4, 5, 6, 7, 8


def _u8(wave):
    return bytes(int(max(0, min(255, round(128 + 100 * v)))) for v in wave)


def bell(rate=6849, secs=0.3):
    n = int(rate * secs)
    return _u8(math.sin(2 * math.pi * 880 * i / rate) * math.exp(-10 * i / rate) for i in range(n))


def buzz(rate=7092, secs=1.0):
    n = int(rate * secs)
    return _u8((1 if (i * 220 // rate) % 2 else -1) * 0.6 * (1 - i / n) for i in range(n))


def sbl_block(rate, data):
    """SOUN > SOU > SBL > AUhd + AUdt (un bloque VOC 1: tamano, frecuencia, sin comprimir)."""
    sr = 256 - 1000000 // rate
    voc = bytes((1,)) + struct.pack("<I", len(data) + 2)[:3] + bytes((sr, 0)) + data
    sbl = b"AUhd" + struct.pack(">I", 3) + b"\x00\x00\x80" + b"AUdt" + struct.pack(">I", len(voc)) + voc
    return S.make_block("SOUN", S.make_block("SOU ", S.make_block("SBL ", sbl)))


def cd_block(track, loops, start=(0, 0, 0), end=(0, 0, 0)):
    """Referencia a una pista del CD (32 bytes, como en la version CD)."""
    body = bytes((0x18, 0, 0, 0, 0, 0, 0, 4, 2, 0xC8, 0xC8, 0xFF, 0, 1, 0, 1))
    body += bytes((track, loops)) + bytes(start) + bytes(end)
    return S.make_block("SOUN", body)


def _vlq(v):
    out = [v & 0x7F]
    v >>= 7
    while v:
        out.insert(0, 0x80 | (v & 0x7F))
        v >>= 7
    return bytes(out)


def _nib(data):
    return bytes(x for b in data for x in (b >> 4, b & 15))


# un instrumento de AdLib (los 30 bytes de iMuse): una nota que se sostiene (EG
# sostenido), ataque rapido, algo de realimentacion
ADL_INSTR = bytes((0x21, 0x20, 0x0F, 0xF8, 0x00, 0x21, 0x3F, 0x0F, 0xF8, 0x00, 0x06)) + bytes(19)


def adl_block(loop):
    """SOUN > SOU > ADL (como Monkey Island: dentro de SOU el tamano no cuenta la
    cabecera): MDhd y un MIDI con los sysex de iMuse (parte, instrumento) y una nota; con
    loop, sostenida (pedal) y un salto al tiempo 2 que se repite para siempre."""
    ev = []

    def e(delta, data):
        ev.append(_vlq(delta) + data)

    def sysex(delta, data):
        e(delta, b"\xF0" + _vlq(len(data) + 1) + data + b"\xF7")
    e(0, b"\xFF\x51\x03\x07\xA1\x20")
    sysex(1, b"\x7D\x00\x00" + _nib(bytes((1, 0, 0x7F, 0, 0, 0, 2, 0))))
    sysex(1, b"\x7D\x10\x00\x01" + _nib(ADL_INSTR))
    if loop:
        e(1, b"\xB0\x40\x7F")
        e(1, b"\x90\x3C\x64")
        sysex(956, b"\x7D\x30\x00" + _nib(bytes((0, 0, 0, 0, 2, 0, 0))))
        e(940, b"\x80\x3C\x00")
        e(20, b"\xFF\x2F\x00")
    else:
        e(1, b"\x90\x48\x64")
        e(400, b"\x80\x48\x00")
        e(20, b"\xFF\x2F\x00")
    trk = b"".join(ev)
    smf = b"MThd" + struct.pack(">IHHH", 6, 2, 1, 480) + b"MTrk" + struct.pack(">I", len(trk)) + trk
    adl = b"MDhd" + struct.pack(">I", 8) + bytes((0, 0, 0x80, 0x7F, 0, 0, 0, 0x80)) + smf
    sou = b"ADL " + struct.pack(">I", len(adl)) + adl
    return S.make_block("SOUN", b"SOU " + struct.pack(">I", len(sou)) + sou)


def sound_blocks():
    return {SND_BELL: sbl_block(6849, bell()), SND_BUZZ: sbl_block(7092, buzz()),
            SND_TRACK: cd_block(1, 1), SND_LOOP: cd_block(2, 0xFF),
            SND_ADL: adl_block(True), SND_ADL2: adl_block(False)}


def write_track(path, secs, notes, rate=22050):
    """Una pista de 'CD' para el juego de prueba: WAV de 8 bits, mono."""
    n = int(rate * secs)
    per = n // len(notes)
    wave = [0.5 * math.sin(2 * math.pi * notes[min(i // per, len(notes) - 1)] * i / rate) for i in range(n)]
    data = _u8(wave)
    hdr = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE"
    hdr += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate, 1, 8)
    hdr += b"data" + struct.pack("<I", len(data))
    with open(path, "wb") as f:
        f.write(hdr + data)


def build(outdir):
    pal = make_palette()
    img, zps, boxes = patio()
    objs = patio_objects()
    import fixture_ui as U
    rooms = {1: ("patio", (img, zps, boxes, objs, None, patio_scripts())),
             2: ("almacen", almacen() + (almacen_objects(), None, almacen_scripts())),
             3: ("camino", camino()[:3] + ((), camino()[3], camino_scripts())),
             4: ("iconos", U.icon_room() + (None, None))}
    objs = objs + almacen_objects() + rooms[4][1][3]
    gscripts = global_scripts()
    gscripts.update(U.global_scripts())
    chars = U.charsets()
    char_offs = {}
    costumes = {1: (1, robot()), 2: (2, turtle()), 3: (3, jellyfish())}   # costume -> (habitacion, bloque)
    lflfs = []
    room_offs = {}
    cost_offs = {}
    script_offs = {}
    sound_offs = {}
    pos = 8 + 8 + 1 + 5 * len(rooms)        # LECF + LOFF
    # ciclos de color: el sol del patio parpadea; las cajas del almacen giran hacia atras
    cycles = {1: [(1, 1000, 0, SUN, SUN + 1)], 2: [(3, 2048, 2, BOX0, BOX0 + 15)]}
    for n in sorted(rooms):
        img, zps, boxes, robjs, scal, rscripts = rooms[n][1]
        room = room_block(img, zps, boxes, pal, robjs, scal, rscripts, cycles.get(n, ()))
        extra = b""
        for c, (r, blk) in costumes.items():
            if r == n:
                cost_offs[c] = (n, len(room) + len(extra))
                extra += blk
        if n == 1:                          # los scripts globales, las fuentes y los sonidos, con el patio
            for k, blk in sorted(sound_blocks().items()):
                sound_offs[k] = (n, len(room) + len(extra))
                extra += blk
            for k in sorted(gscripts):
                script_offs[k] = (n, len(room) + len(extra))
                extra += S.make_block("SCRP", gscripts[k])
            for k in sorted(chars):
                char_offs[k] = (n, len(room) + len(extra))
                extra += S.make_block("CHAR", chars[k])
        lflf = S.make_block("LFLF", room + extra)
        room_offs[n] = pos + 8
        pos += len(lflf)
        lflfs.append(lflf)
    loff = S.make_block("LOFF", bytes((len(rooms),)) + b"".join(
        struct.pack("<BI", n, room_offs[n]) for n in sorted(rooms)))
    data = S.make_block("LECF", loff + b"".join(lflfs))

    def directory(tag, n, entries):
        rooms_ = bytearray(n)
        offs = [0] * n
        for i, (r, o) in entries.items():
            rooms_[i] = r
            offs[i] = o
        return S.make_block(tag, struct.pack("<H", n) + bytes(rooms_) + struct.pack("<%dI" % n, *offs))

    rnam = b"".join(bytes((n,)) + bytes(c ^ 0xFF for c in name.encode().ljust(9, b"\0"))
                    for n, (name, _) in sorted(rooms.items())) + b"\0"
    index = (S.make_block("RNAM", rnam) +
             S.make_block("MAXS", struct.pack("<9H", 800, 16, 2048, 200, 50, 9, 100, 50, 80)) +
             directory("DROO", 5, {n: (1, 0) for n in rooms}) +
             directory("DSCR", 200, script_offs) +
             directory("DSOU", 10, sound_offs) +
             directory("DCOS", 4, cost_offs) +
             directory("DCHR", 3, char_offs) +
             S.make_block("DOBJ", dobj(objs)))
    os.makedirs(outdir, exist_ok=True)
    write_track(os.path.join(outdir, "Track1.wav"), 2.0, (262, 330, 392, 523))
    write_track(os.path.join(outdir, "Track2.wav"), 1.0, (131, 165))
    S.write_xor(os.path.join(outdir, "PRUEBA.000"), index)
    S.write_xor(os.path.join(outdir, "PRUEBA.001"), data)
    return rooms


def dobj(objs):
    """DOBJ: por numero de objeto, estado << 4 | dueno, y las clases."""
    n = max(o.oid for o in objs) + 1
    st = bytearray(n)
    for o in objs:
        st[o.oid] = o.state << 4 | 15         # dueno 15: en la habitacion
    return struct.pack("<H", n) + bytes(st) + bytes(4 * n)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "prueba")
    build(out)
    print("juego de prueba en", out)


if __name__ == "__main__":
    main()
