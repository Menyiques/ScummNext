"""Ensamblador minimo de SCUMM v5, para escribir los scripts del juego de prueba.

    a = Asm()
    a.move(V(100), 3)
    a.if_eq(V(100), 3, "otro")      # si var100 == 3 sigue; si no, salta a "otro"
    ...
    a.label("otro")
    a.stop()
    code = a.finish()

Operandos: un entero es un valor directo; V(n) una variable global, L(n) una
local, B(n) una de bit; V(n, i) lleva indice (un numero o una variable). Las
condiciones saltan cuando NO se cumplen, como en SCUMM. Los textos pueden ser
str (latin1) o bytes (con escapes $FF).
"""
import struct


class V:
    def __init__(self, n, idx=None):
        self.n = n
        self.idx = idx

    def enc(self):
        if self.idx is None:
            return struct.pack("<H", self.n)
        i = self.idx
        iw = (i.n | 0x2000) if isinstance(i, V) else (i & 0xFFF)
        return struct.pack("<HH", self.n | 0x2000, iw)


def L(n):
    return V(0x4000 | n)


def B(n):
    return V(0x8000 | n)


class Asm:
    def __init__(self):
        self.out = bytearray()
        self.labels = {}
        self.fixups = []

    # --- piezas ---
    def b(self, *v):
        self.out += bytes(x & 0xFF for x in v)

    def w(self, v):
        self.out += struct.pack("<H", v & 0xFFFF)

    def label(self, name):
        self.labels[name] = len(self.out)

    def ref(self, name):
        self.fixups.append((len(self.out), name))
        self.w(0)

    def finish(self):
        for pos, name in self.fixups:
            off = self.labels[name] - (pos + 2)
            self.out[pos:pos + 2] = struct.pack("<h", off)
        return bytes(self.out)

    def emit(self, base, params, extra=b""):
        """params: [(valor, 'b'|'w')] con los bits de parametro en el codigo."""
        code = base
        body = bytearray()
        for i, (val, size) in enumerate(params):
            if isinstance(val, V):
                code |= (0x80, 0x40, 0x20)[i]
                body += val.enc()
            elif size == "b":
                body.append(val & 0xFF)
            else:
                body += struct.pack("<H", val & 0xFFFF)
        self.b(code)
        self.out += body + extra

    def sub(self, sub, params):
        """Subcodigo con sus propios bits de parametro."""
        self.emit(sub, params)

    def var(self, v):
        self.out += v.enc()

    def wv(self, x):
        """Una palabra directa o una variable."""
        if isinstance(x, V):
            self.out += x.enc()
        else:
            self.w(x)

    def string(self, text):
        self.out += (text.encode("latin1") if isinstance(text, str) else bytes(text)) + b"\0"

    def vararg(self, args):
        for a in args:
            self.emit(0x01, [(a, "w")])
        self.b(0xFF)

    # --- instrucciones ---
    def stop(self):
        self.b(0x00)

    def brk(self):
        self.b(0x80)

    def jump(self, label):
        self.b(0x18)
        self.ref(label)

    def _arith(self, base, var, val):
        code = base | (0x80 if isinstance(val, V) else 0)
        self.b(code)
        self.var(var)
        self.wv(val)

    def mov(self, var, val):
        self._arith(0x1A, var, val)

    def add(self, var, val):
        self._arith(0x5A, var, val)

    def subtract(self, var, val):
        self._arith(0x3A, var, val)

    def mul(self, var, val):
        self._arith(0x1B, var, val)

    def div(self, var, val):
        self._arith(0x5B, var, val)

    def band(self, var, val):
        self._arith(0x17, var, val)

    def bor(self, var, val):
        self._arith(0x57, var, val)

    def inc(self, var):
        self.b(0x46)
        self.var(var)

    def dec(self, var):
        self.b(0xC6)
        self.var(var)

    def _cmp(self, base, var, val, label):
        self.b(base | (0x80 if isinstance(val, V) else 0))
        self.var(var)
        self.wv(val)
        self.ref(label)

    def if_eq(self, var, val, label):       # sigue si val == var
        self._cmp(0x48, var, val, label)

    def if_ne(self, var, val, label):
        self._cmp(0x08, var, val, label)

    def if_lt(self, var, val, label):       # sigue si val < var
        self._cmp(0x44, var, val, label)

    def if_gt(self, var, val, label):       # sigue si val > var
        self._cmp(0x78, var, val, label)

    def if_zero(self, var, label):          # sigue si var == 0
        self.b(0x28)
        self.var(var)
        self.ref(label)

    def if_nonzero(self, var, label):
        self.b(0xA8)
        self.var(var)
        self.ref(label)

    def expr(self, var, items):
        """items: ('push', valor) | ('add'|'sub'|'mul'|'div',) | ('op', funcion que emite)."""
        self.b(0xAC)
        self.var(var)
        for it in items:
            if it[0] == "push":
                self.emit(0x01, [(it[1], "w")])
            elif it[0] == "op":
                self.b(0x06)
                it[1](self)
            else:
                self.b({"add": 2, "sub": 3, "mul": 4, "div": 5}[it[0]])
        self.b(0xFF)

    def set_var_range(self, var, vals):
        self.b(0xA6)
        self.var(var)
        self.b(len(vals))
        for v in vals:
            self.w(v)

    def random(self, var, mx):
        code = 0x16 | (0x80 if isinstance(mx, V) else 0)
        self.b(code)
        self.var(var)
        if isinstance(mx, V):
            self.var(mx)
        else:
            self.b(mx)

    def delay(self, jiffies):
        self.b(0x2E, jiffies, jiffies >> 8, jiffies >> 16)

    def delay_var(self, var):
        self.b(0x2B)
        self.var(var)

    def start_script(self, n, args=(), recursive=False, freeze_res=False):
        base = 0x0A | (0x40 if recursive else 0) | (0x20 if freeze_res else 0)
        if isinstance(n, V):
            self.b(base | 0x80)
            self.var(n)
        else:
            self.b(base, n)
        self.vararg(args)

    def chain_script(self, n, args=()):
        self.emit(0x42, [(n, "b")])
        self.vararg(args)

    def stop_script(self, n):
        self.emit(0x62, [(n, "b")])

    def is_running(self, var, n):
        self.b(0x68 | (0x80 if isinstance(n, V) else 0))
        self.var(var)
        if isinstance(n, V):
            self.var(n)
        else:
            self.b(n)

    def freeze(self, flag):
        self.emit(0x60, [(flag, "b")])

    def cutscene(self, args=()):
        self.b(0x40)
        self.vararg(args)

    def end_cutscene(self):
        self.b(0xC0)

    def override(self, skip_label):
        self.b(0x58, 1)
        self.jump(skip_label)

    def end_override(self):
        self.b(0x58, 0)

    def start_object(self, obj, verb, args=()):
        self.emit(0x37, [(obj, "w"), (verb, "b")])
        self.vararg(args)

    def set_state(self, obj, st):
        self.emit(0x07, [(obj, "w"), (st, "b")])

    def get_state(self, var, obj):
        self.b(0x0F | (0x80 if isinstance(obj, V) else 0))
        self.var(var)
        self.wv(obj)

    def if_state(self, obj, st, label):     # sigue si estado == st
        # 0x4F lleva el bit del segundo parametro: el estado es siempre una variable
        if not isinstance(st, V):
            raise ValueError("ifState: el estado tiene que ser una variable (usa if_not_state)")
        self.emit(0x4F, [(obj, "w"), (st, "b")])
        self.ref(label)

    def if_not_state(self, obj, st, label):
        self.emit(0x2F, [(obj, "w"), (st, "b")])
        self.ref(label)

    def draw_object_at(self, obj, x, y):
        """drawObject con setXY: el objeto a (x * 8, y * 8)."""
        self.emit(0x05, [(obj, "w")])
        self.sub(0x01, [(x, "w"), (y, "w")])

    def draw_object(self, obj, state=None):
        self.emit(0x05, [(obj, "w")])
        if state is None:
            self.b(0x1F)
        else:
            self.sub(0x02, [(state, "w")])

    def set_owner(self, obj, owner):
        self.emit(0x29, [(obj, "w"), (owner, "b")])

    def get_owner(self, var, obj):
        self.b(0x10 | (0x80 if isinstance(obj, V) else 0))
        self.var(var)
        self.wv(obj)

    def pickup(self, obj, room=0):
        self.emit(0x25, [(obj, "w"), (room, "b")])

    def set_class(self, obj, classes):
        self.emit(0x5D, [(obj, "w")])
        for c in classes:
            self.emit(0x01, [(c, "w")])
        self.b(0xFF)

    def if_class(self, obj, classes, label):
        self.emit(0x1D, [(obj, "w")])
        for c in classes:
            self.emit(0x01, [(c, "w")])
        self.b(0xFF)
        self.ref(label)

    def find_object(self, var, x, y):
        self.b(0x35 | (0x80 if isinstance(x, V) else 0) | (0x40 if isinstance(y, V) else 0))
        self.var(var)
        for v in (x, y):
            self.wv(v)

    def print_(self, act, text, at=None):
        self.emit(0x14, [(act, "b")])
        if at:
            self.sub(0x00, [(at[0], "w"), (at[1], "w")])
        self.b(0x0F)
        self.string(text)

    def print_ego(self, text):
        self.b(0xD8, 0x0F)
        self.string(text)

    def wait(self, kind, act=None):
        self.b(0xAE)
        if kind == 1:
            self.sub(0x01, [(act, "b")])
        else:
            self.b(kind)

    def put_actor(self, act, x, y):
        self.emit(0x01, [(act, "b"), (x, "w"), (y, "w")])

    def walk_actor(self, act, x, y):
        self.emit(0x1E, [(act, "b"), (x, "w"), (y, "w")])

    def walk_to_object(self, act, obj):
        self.emit(0x36, [(act, "b"), (obj, "w")])

    def put_in_room(self, act, room):
        self.emit(0x2D, [(act, "b"), (room, "b")])

    def actor_costume(self, act, cost):
        self.emit(0x13, [(act, "b")])
        self.sub(0x01, [(cost, "b")])
        self.b(0xFF)

    def get_actor_x(self, var, act):
        self.b(0x43 | (0x80 if isinstance(act, V) else 0))
        self.var(var)
        self.wv(act)

    def get_actor_y(self, var, act):
        self.b(0x23 | (0x80 if isinstance(act, V) else 0))
        self.var(var)
        self.wv(act)

    def get_actor_moving(self, var, act):
        self.b(0x56 | (0x80 if isinstance(act, V) else 0))
        self.var(var)
        if isinstance(act, V):
            self.var(act)
        else:
            self.b(act)

    def load_room(self, room):
        self.emit(0x72, [(room, "b")])

    def camera_at(self, x):
        self.emit(0x32, [(x, "w")])

    def camera_pan(self, x):
        self.emit(0x12, [(x, "w")])

    def camera_follow(self, act):
        self.emit(0x52, [(act, "b")])

    def lights(self, a, b, c):
        self.emit(0x70, [(a, "b")])
        self.b(b, c)

    def pseudo_room(self, room, pseudos):
        """pseudoRoom: las habitaciones pseudos (128 o mas) son room."""
        self.b(0xCC, room, *pseudos, 0)

    def room_scroll(self, x1, x2):
        self.b(0x33)
        self.sub(0x01, [(x1, "w"), (x2, "w")])

    def box_flags(self, box, flags):
        self.b(0x30)
        self.sub(0x01, [(box, "b"), (flags, "b")])

    def object_name(self, obj, text):
        self.emit(0x54, [(obj, "w")])
        self.string(text)

    def cursor(self, k):
        self.b(0x2C, k)

    def verb_ops(self, verb, name):
        self.emit(0x7A, [(verb, "b")])
        self.b(0x02)
        self.string(name)
        self.b(0x06, 0xFF)

    def sound(self, n):                             # startSound
        self.emit(0x1C, [(n, "b")])

    def start_music(self, n):
        self.emit(0x02, [(n, "b")])

    def stop_sound(self, n):
        self.emit(0x3C, [(n, "b")])

    def stop_music(self):
        self.b(0x20)

    def sound_running(self, var, n):                # isSoundRunning
        self._res_op(0x7C, var, [(n, "b")])

    def sound_kludge(self, args):
        self.b(0x4C)
        self.vararg(args)

    # --- textos, verbos, cursor, frases e inventario -----------------------------
    def print_items(self, items):
        """('at', x, y) ('color', c) ('clipped', r) ('center',) ('left',) ('overhead',) ('text', t)."""
        for it in items:
            k = it[0]
            if k == "at":
                self.sub(0x00, [(it[1], "w"), (it[2], "w")])
            elif k == "color":
                self.sub(0x01, [(it[1], "b")])
            elif k == "clipped":
                self.sub(0x02, [(it[1], "w")])
            elif k == "center":
                self.b(0x04)
            elif k == "left":
                self.b(0x06)
            elif k == "overhead":
                self.b(0x07)
            elif k == "text":
                self.b(0x0F)
                self.string(it[1])
                return
        self.b(0xFF)

    def say(self, act, items):
        self.emit(0x14, [(act, "b")])
        self.print_items(items)

    def say_ego(self, items):
        self.b(0xD8)
        self.print_items(items)

    def verb(self, verb, *subs):
        """('new',) ('name', t) ('color', c) ('hicolor', c) ('at', x, y) ('on',) ('off',) ('delete',)
        ('dimcolor', c) ('dim',) ('key', k) ('center',) ('namestr', n) ('image', obj, hab) ('bkcolor', c)."""
        self.emit(0x7A, [(verb, "b")])
        simple = {"new": 9, "on": 6, "off": 7, "delete": 8, "dim": 17, "center": 19}
        one_b = {"color": 3, "hicolor": 4, "dimcolor": 16, "key": 18, "bkcolor": 23}
        for sb in subs:
            k = sb[0]
            if k in simple:
                self.b(simple[k])
            elif k in one_b:
                self.sub(one_b[k], [(sb[1], "b")])
            elif k == "name":
                self.b(2)
                self.string(sb[1])
            elif k == "at":
                self.sub(5, [(sb[1], "w"), (sb[2], "w")])
            elif k == "namestr":
                self.sub(20, [(sb[1], "w")])
            elif k == "image":
                self.sub(22, [(sb[1], "w"), (sb[2], "b")])
        self.b(0xFF)

    def verbs_save(self, k, a, b, c):
        """saveRestoreVerbs: 1 guardar, 2 recuperar, 3 borrar."""
        self.b(0xAB)
        self.sub(k, [(a, "b"), (b, "b"), (c, "b")])

    def cursor_charset(self, n):
        self.b(0x2C)
        self.sub(13, [(n, "b")])

    def cursor_colors(self, cols):
        self.b(0x2C, 14)
        self.vararg(cols)

    def load_charset(self, n):
        self.b(0x0C)
        self.sub(18, [(n, "b")])

    def set_screen(self, b, h):
        self.b(0x33)
        self.sub(3, [(b, "w"), (h, "w")])

    def set_pal_color(self, idx, r, g, b):          # roomOps 4 (setPalColor)
        self.b(0x33)
        self.sub(4, [(r, "w"), (g, "w"), (b, "w")])
        self.sub(0, [(idx, "b")])

    def system_ops(self, k):                        # systemOps (1 reiniciar, 3 salir)
        self.b(0x98, k)

    def shake(self, on):                            # roomOps 5 / 6
        self.b(0x33, 5 if on else 6)

    def room_intensity(self, scale, start, end):    # roomOps 8
        self.b(0x33)
        self.sub(8, [(scale, "b"), (start, "b"), (end, "b")])

    def room_effect(self, a):                       # roomOps 10: transiciones
        self.b(0x33)
        self.sub(10, [(a, "w")])

    def rgb_intensity(self, r, g, b, start, end):   # roomOps 11 (rgbRoomIntensity)
        self.b(0x33)
        self.sub(11, [(r, "w"), (g, "w"), (b, "w")])
        self.sub(0, [(start, "b"), (end, "b")])

    def sentence(self, verb, a, b):
        self.emit(0x19, [(verb, "b"), (a, "w"), (b, "w")])

    def sentence_stop(self):
        self.b(0x19, 0xFE)

    def _res_op(self, base, var, params):
        """Instruccion con resultado: codigo, variable y despues los parametros."""
        code = base
        body = bytearray()
        for i, (val, size) in enumerate(params):
            if isinstance(val, V):
                code |= (0x80, 0x40, 0x20)[i]
                body += val.enc()
            elif size == "b":
                body.append(val & 0xFF)
            else:
                body += struct.pack("<H", val & 0xFFFF)
        self.b(code)
        self.var(var)
        self.out += body

    def verb_entry(self, var, obj, verb):
        self._res_op(0x0B, var, [(obj, "w"), (verb, "w")])

    def find_inventory(self, var, owner, idx):
        self._res_op(0x3D, var, [(owner, "b"), (idx, "b")])

    def inventory_count(self, var, owner):
        self._res_op(0x31, var, [(owner, "b")])

    def draw_box(self, x, y, x2, y2, c):
        self.emit(0x3F, [(x, "w"), (y, "w")])
        self.sub(0x00, [(x2, "w"), (y2, "w"), (c, "b")])

    def load_string(self, n, text):
        self.b(0x27)
        self.sub(1, [(n, "b")])
        self.string(text)

    def set_string_char(self, n, i, c):
        self.b(0x27)
        self.sub(3, [(n, "b"), (i, "b"), (c, "b")])

    def create_string(self, n, size):
        self.b(0x27)
        self.sub(5, [(n, "b"), (size, "b")])

    def get_string_char(self, var, n, i):
        self.b(0x27)
        self._res_op(4, var, [(n, "b"), (i, "b")])

    ACTOR_SUBS = {"costume": (1, "b"), "speed": (2, "bb"), "sound": (3, "b"), "walkframe": (4, "b"),
                  "talkframes": (5, "bb"), "standframe": (6, "b"), "init": (8, ""), "elevation": (9, "w"),
                  "defaultframes": (10, ""), "palette": (11, "bb"), "talkcolor": (12, "b"), "initframe": (14, "b"),
                  "width": (16, "b"), "scale": (17, "bb"), "neverzclip": (18, ""), "alwayszclip": (19, "b"),
                  "ignoreboxes": (20, ""), "followboxes": (21, ""), "animspeed": (22, "b")}

    def actor(self, act, *subs):
        """actorOps: ('costume', c) ('speed', x, y) ('sound', s) ('walkframe', f) ('talkframes', a, b)
        ('standframe', f) ('init',) ('elevation', e) ('defaultframes',) ('palette', i, c)
        ('talkcolor', c) ('name', t) ('initframe', f) ('width', w) ('scale', x, y)
        ('neverzclip',) ('alwayszclip', z) ('ignoreboxes',) ('followboxes',) ('animspeed', s)."""
        self.emit(0x13, [(act, "b")])
        for sb in subs:
            k = sb[0]
            if k == "name":
                self.b(13)
                self.string(sb[1])
                continue
            code, fmt = self.ACTOR_SUBS[k]
            self.sub(code, [(v, f) for v, f in zip(sb[1:], fmt)])
        self.b(0xFF)

    def animate_actor(self, act, anim):
        self.emit(0x11, [(act, "b"), (anim, "b")])

    def face_actor(self, act, obj):
        self.emit(0x09, [(act, "b"), (obj, "w")])

    def walk_to_actor(self, act, act2, dist):
        self.emit(0x0D, [(act, "b"), (act2, "b")], bytes((dist & 0xFF,)))

    def put_at_object(self, act, obj):
        self.emit(0x0E, [(act, "b"), (obj, "w")])

    def load_room_with_ego(self, obj, room, x=-1, y=-1):
        self.emit(0x24, [(obj, "w"), (room, "b")], struct.pack("<hh", x, y))

    def actor_query(self, var, what, act):
        """getActorRoom / Costume / Elevation / Facing / WalkBox / Width / Scale / AnimCounter."""
        code = {"room": 0x03, "elevation": 0x06, "animcounter": 0x22, "scale": 0x3B, "facing": 0x63,
                "width": 0x6C, "costume": 0x71, "walkbox": 0x7B, "moving": 0x56}[what]
        self._res_op(code, var, [(act, "b")])

    def actor_from_pos(self, var, x, y):
        self._res_op(0x15, var, [(x, "w"), (y, "w")])

    def get_dist(self, var, a, b):
        self._res_op(0x34, var, [(a, "w"), (b, "w")])

    def closest_actor(self, var, act):
        self._res_op(0x66, var, [(act, "w")])

    def if_actor_in_box(self, act, box, label):     # sigue si el actor esta en la caja
        self.emit(0x1F, [(act, "b"), (box, "b")])
        self.ref(label)

    def if_le(self, var, val, label):       # sigue si val <= var
        self._cmp(0x38, var, val, label)

    def if_ge(self, var, val, label):       # sigue si val >= var
        self._cmp(0x04, var, val, label)
