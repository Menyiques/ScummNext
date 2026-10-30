"""La interfaz del juego de prueba: fuentes, iconos y scripts, todo propio.

- Dos fuentes de 5x7 dibujadas aqui: la 1 de un bit por pixel y la 2 de dos,
  con sombra (el color 2 del mapa).
- La habitacion 4, "iconos": los iconos del inventario (40x24) y las flechas
  (16x24), como la habitacion de verbos de los juegos de LucasArts.
- Scripts globales: 1 arranque, 20 entrada (clics y teclas), 21 frases, 22
  inventario, 23 verbos, 24 lo que hay bajo el cursor, 25 la linea de frase.
- Verbos de los objetos del patio: puerta, farol, sol y una moneda que se coge.
"""
import numpy as np

import charset as CH
import sasm as A
from sasm import L, V

# colores de la paleta del juego de prueba (tools/fixture.py)
DARK0, COL0, BOX0, ROBOT0 = 192, 160, 208, 240
WHITE, YELLOW, CYAN, ORANGE, GREY = ROBOT0 + 11, ROBOT0 + 9, ROBOT0 + 6, ROBOT0 + 8, ROBOT0 + 3

# verbos
OPEN, CLOSE, LOOK, TAKE, USE, TALK, WALK = 1, 2, 3, 4, 5, 6, 7
F_WALL_TOP = 127                        # fixture.WALL0 + 31: el color mas claro del muro
SENTENCE = 100
INV0, ARROW_UP, ARROW_DOWN = 200, 208, 209
ICON_VERB = 91
ICON_ROOM = 4
ICON_BLANK, ICON_ITEM, ICON_COIN, ARROW_UP_IMG, ARROW_DOWN_IMG, ARROW_DIM_IMG = 900, 901, 902, 908, 909, 910
COIN = 106

# variables
V_VERB, V_OVER, V_OBJA, V_INVOFF, V_INV0, V_ICON = 300, 301, 302, 303, 310, 320
V_NEWOVER, V_STRNUM, V_NAMEOBJ = 304, 305, 306

# --- fuente de 5x7 (filas de 5 bits, el bit 4 a la izquierda) ------------------------------
FONT5 = {
    "0": "0E 11 13 15 19 11 0E", "1": "04 0C 04 04 04 04 0E", "2": "0E 11 01 02 04 08 1F",
    "3": "1F 02 04 02 01 11 0E", "4": "02 06 0A 12 1F 02 02", "5": "1F 10 1E 01 01 11 0E",
    "6": "06 08 10 1E 11 11 0E", "7": "1F 01 02 04 08 08 08", "8": "0E 11 11 0E 11 11 0E",
    "9": "0E 11 11 0F 01 02 0C",
    "A": "0E 11 11 11 1F 11 11", "B": "1E 11 11 1E 11 11 1E", "C": "0E 11 10 10 10 11 0E",
    "D": "1C 12 11 11 11 12 1C", "E": "1F 10 10 1E 10 10 1F", "F": "1F 10 10 1E 10 10 10",
    "G": "0E 11 10 17 11 11 0F", "H": "11 11 11 1F 11 11 11", "I": "0E 04 04 04 04 04 0E",
    "J": "07 02 02 02 02 12 0C", "K": "11 12 14 18 14 12 11", "L": "10 10 10 10 10 10 1F",
    "M": "11 1B 15 15 11 11 11", "N": "11 11 19 15 13 11 11", "O": "0E 11 11 11 11 11 0E",
    "P": "1E 11 11 1E 10 10 10", "Q": "0E 11 11 11 15 12 0D", "R": "1E 11 11 1E 14 12 11",
    "S": "0F 10 10 0E 01 01 1E", "T": "1F 04 04 04 04 04 04", "U": "11 11 11 11 11 11 0E",
    "V": "11 11 11 11 11 0A 04", "W": "11 11 11 15 15 15 0A", "X": "11 11 0A 04 0A 11 11",
    "Y": "11 11 11 0A 04 04 04", "Z": "1F 01 02 04 08 10 1F",
    "a": "00 00 0E 01 0F 11 0F", "b": "10 10 16 19 11 11 1E", "c": "00 00 0E 10 10 11 0E",
    "d": "01 01 0D 13 11 11 0F", "e": "00 00 0E 11 1F 10 0E", "f": "06 09 08 1C 08 08 08",
    "g": "00 0F 11 11 0F 01 0E", "h": "10 10 16 19 11 11 11", "i": "04 00 0C 04 04 04 0E",
    "j": "02 00 06 02 02 12 0C", "k": "10 10 12 14 18 14 12", "l": "0C 04 04 04 04 04 0E",
    "m": "00 00 1A 15 15 11 11", "n": "00 00 16 19 11 11 11", "o": "00 00 0E 11 11 11 0E",
    "p": "00 00 1E 11 1E 10 10", "q": "00 00 0D 13 0F 01 01", "r": "00 00 16 19 10 10 10",
    "s": "00 00 0E 10 0E 01 1E", "t": "08 08 1C 08 08 09 06", "u": "00 00 11 11 11 13 0D",
    "v": "00 00 11 11 11 0A 04", "w": "00 00 11 11 15 15 0A", "x": "00 00 11 0A 04 0A 11",
    "y": "00 00 11 11 0F 01 0E", "z": "00 00 1F 02 04 08 1F",
    ".": "00 00 00 00 00 0C 0C", ",": "00 00 00 00 0C 04 08", "!": "04 04 04 04 04 00 04",
    "?": "0E 11 01 02 04 00 04", ":": "00 0C 0C 00 0C 0C 00", ";": "00 0C 0C 00 0C 04 08",
    "'": "0C 04 08 00 00 00 00", '"': "0A 0A 0A 00 00 00 00", "-": "00 00 00 1F 00 00 00",
    "(": "02 04 08 08 08 04 02", ")": "08 04 02 02 02 04 08", "/": "00 01 02 04 08 10 00",
    "=": "00 00 1F 00 1F 00 00", "+": "00 04 04 1F 04 04 00", ">": "08 04 02 01 02 04 08",
    "<": "02 04 08 10 08 04 02",
    "\xa1": "04 00 04 04 04 04 04", "\xbf": "04 00 04 08 10 11 0E",
    "\xe1": "02 04 0E 01 0F 11 0F", "\xe9": "02 04 0E 11 1F 10 0E", "\xed": "02 04 0C 04 04 04 0E",
    "\xf3": "02 04 0E 11 11 11 0E", "\xfa": "02 04 11 11 11 13 0D", "\xf1": "0E 00 16 19 11 11 11",
}


def glyph_rows(ch):
    """Filas de pixeles (0/1) recortadas a las columnas que se usan, con una de separacion."""
    rows = [int(x, 16) for x in FONT5[ch].split()]
    cols = [c for c in range(5) if any(r >> (4 - c) & 1 for r in rows)]
    c0, c1 = cols[0], cols[-1]
    return [[(r >> (4 - c)) & 1 for c in range(c0, c1 + 1)] + [0] for r in rows]


def charsets():
    """{1: fuente de 1 bit, 2: fuente de 2 bits con sombra} (bloques CHAR sin cabecera)."""
    g1 = {32: (0, 0, [[0, 0, 0]] * 7)}
    g2 = {32: (0, 0, [[0, 0, 0, 0]] * 8)}
    for ch in FONT5:
        rows = glyph_rows(ch)
        g1[ord(ch)] = (0, 0, rows)
        w = len(rows[0]) + 1
        sh = [[0] * w for _ in range(8)]
        for y, r in enumerate(rows):
            for x, p in enumerate(r):
                if p:
                    sh[y][x] = 1
        for y, r in enumerate(rows):
            for x, p in enumerate(r):
                if p and not sh[y + 1][x + 1]:
                    sh[y + 1][x + 1] = 2
        g2[ord(ch)] = (0, 0, sh)
    colors1 = [WHITE, 0] + list(range(3, 16))
    colors2 = [WHITE, 0] + list(range(3, 16))
    return {1: CH.encode(8, 1, g1, colors1), 2: CH.encode(9, 2, g2, colors2)}


# --- la habitacion de los iconos ------------------------------------------------------------
def icon(kind):
    w, h = (16, 24) if kind in ("up", "down", "dim") else (40, 24)
    ys, xs = np.mgrid[0:h, 0:w]
    pix = np.full((h, w), DARK0 + 3, dtype=np.uint8)
    frame = (xs == 0) | (ys == 0) | (xs == w - 1) | (ys == h - 1)
    pix[frame] = COL0 + 12
    opaque = np.ones((h, w), dtype=bool)
    if kind == "item":
        pix[(np.abs(xs - 19.5) < 7) & (np.abs(ys - 11.5) < 7) & ((xs + ys) % 3 == 0)] = GREY
    elif kind == "coin":
        d = (xs - 19.5) ** 2 + (ys - 11.5) ** 2
        pix[d < 64] = YELLOW
        pix[(d >= 40) & (d < 64)] = ORANGE
        pix[(np.abs(xs - 19.5) < 1) & (np.abs(ys - 11.5) < 4)] = ORANGE
        opaque[(xs < 3) & (ys < 3)] = False         # una esquina transparente: deja ver lo de debajo
    elif kind in ("up", "down"):
        t = (ys - 6) if kind == "up" else (17 - ys)
        arrow = (t >= 0) & (np.abs(xs - 7.5) <= t * 0.6) & (t < 12)
        pix[arrow] = CYAN
    return pix, opaque


def icon_room():
    """(imagen, planos z, cajas, objetos): 8x200 en negro y los iconos como objetos."""
    import scumm as S
    from fixture import FObj
    img = np.zeros((200, 8), dtype=np.uint8)
    boxes = [S.Box((0, 0), (0, 0), (0, 0), (0, 0), 0, 0x80, 255),
             S.Box((0, 150), (7, 150), (7, 199), (0, 199), 0, 0, 255)]
    objs = []
    for oid, kind, name in ((ICON_BLANK, "blank", "hueco"), (ICON_ITEM, "item", "cosa"),
                            (ICON_COIN, "coin", "moneda"), (ARROW_UP_IMG, "up", "arriba"),
                            (ARROW_DOWN_IMG, "down", "abajo"), (ARROW_DIM_IMG, "dim", "flecha")):
        pix, opq = icon(kind)
        h, w = pix.shape
        objs.append(FObj(oid, name, 0, 0, w // 8, h, 0, [(pix, opq, {})]))
    return img, [], boxes, objs


# --- verbos de los objetos del patio ----------------------------------------------------------------
def _code(build):
    a = A.Asm()
    build(a)
    return a.finish()


def door_verbs():
    def opn(a):
        a.if_not_state(100, 2, "already")   # sigue si no esta abierta (estado 2)
        a.set_state(100, 2)
        a.shake(True)                       # la pantalla tiembla un momento
        a.delay(20)
        a.shake(False)
        a.stop()
        a.label("already")
        a.say_ego([("text", "Ya est\xe1 abierta.")])
        a.stop()

    def close(a):
        a.set_state(100, 1)
        a.stop()

    def look(a):
        a.say_ego([("text", b"Una puerta con \xFF\x04" + bytes((110, 0)) + b" clavos.")])
        a.stop()
    return {OPEN: _code(opn), CLOSE: _code(close), LOOK: _code(look)}


def lamp_verbs():
    def use(a):
        a.set_pal_color(F_WALL_TOP, 255, 255, 170)  # mas luz: el color mas claro del muro
        a.say_ego([("text", "Ahora da m\xe1s luz.")])
        a.stop()

    def look(a):
        a.say_ego([("text", "Un farol. Parpadea a veces.\xff\x03Y da poca luz.")])
        a.delay(30)                         # parpadea con el texto encima (el texto se queda)
        a.set_state(101, 2)
        a.delay(12)
        a.set_state(101, 1)
        a.wait(2)
        a.say_ego([("text", "Mucho texto para un farol tan peque\xf1o, que no cabe en una sola l\xednea.")])
        a.stop()
    return {LOOK: _code(look), USE: _code(use)}


def sun_verbs():
    def talk(a):
        a.say(2, [("text", "\xa1Hola! Soy la tortuga.\xff\x02")])
        a.wait(2)
        a.say(2, [("text", " Y sigo hablando.")])
        a.stop()

    def look(a):
        a.say(254, [("at", 160, 8), ("center",), ("color", ORANGE), ("text", "EL SOL")])
        a.rgb_intensity(300, 220, 160, 1, 239)  # atardecer (sin los colores del robot)
        a.room_effect(0x8180)               # la proxima habitacion: de golpe y disolviendo
        a.stop()
    return {TALK: _code(talk), LOOK: _code(look)}


def coin_verbs():
    def take(a):
        # en un script global: pickupObject llama al script del inventario, que
        # arranca el verbo del icono de la moneda y eso para los scripts de la
        # moneda (startObject, como en SCUMM), este tambien
        a.start_script(26)
        a.stop()

    def look(a):
        a.mov(V(V_NAMEOBJ), COIN)
        a.say_ego([("text", b"Es una \xFF\x06" + bytes((V_NAMEOBJ & 0xFF, V_NAMEOBJ >> 8)) + b".")])
        a.stop()

    def icon_(a):
        a.mov(V(V_ICON), ICON_COIN)
        a.stop()
    return {TAKE: _code(take), LOOK: _code(look), ICON_VERB: _code(icon_)}


def coin_image():
    w, h = 16, 8
    ys, xs = np.mgrid[0:h, 0:w]
    d = ((xs - 7.5) / 7.5) ** 2 + ((ys - 3.5) / 3.5) ** 2
    pix = np.where(d < 0.5, YELLOW, ORANGE).astype(np.uint8)
    return [(pix, d < 1.0, {})]


# --- scripts globales -------------------------------------------------------------------------
VERB_LIST = ((OPEN, "Abrir", 8, 154, ord("a")), (CLOSE, "Cerrar", 8, 166, ord("c")),
             (LOOK, "Mirar", 56, 154, ord("m")), (TAKE, "Coger", 56, 166, ord("g")),
             (USE, "Usar", 104, 154, ord("u")), (TALK, "Hablar", 104, 166, ord("h")),
             (WALK, "Ir a", 8, 178, ord("i")))
INV_SLOTS = ((168, 152), (208, 152), (168, 176), (208, 176))


def boot():
    a = A.Asm()
    a.mov(V(32), 20)                        # VAR_VERB_SCRIPT
    a.mov(V(33), 21)                        # VAR_SENTENCE_SCRIPT
    a.mov(V(34), 22)                        # VAR_INVENTORY_SCRIPT
    a.mov(V(24), 27)                        # VAR_CUTSCENEEXIT_KEY (ESC)
    a.mov(V(57), 46)                        # VAR_TALKSTOP_KEY (.)
    a.mov(V(54), -70)                       # VAR_V5_TALK_STRING_Y
    a.mov(V(V_STRNUM), 1)
    a.mov(V(V_VERB), WALK)
    a.load_charset(1)
    a.load_charset(2)
    a.cursor_charset(2)
    a.set_screen(0, 144)
    a.pseudo_room(2, [201, 202])            # (la 201 y la 202 son el almacen: prueba pseudo)
    a.create_string(40, 200)                # cadena de bytes: escribir y leer uno (stringOps 5/3/4)
    a.set_string_char(40, 150, 77)
    a.get_string_char(V(160), 40, 150)
    a.room_effect(0x8181)                   # transiciones: a negro y de golpe (como el juego)
    a.say(255, [("overhead",), ("color", WHITE)])           # sin texto: por defecto
    a.actor(1, ("costume", 1), ("talkcolor", YELLOW), ("name", "Robi"))
    a.actor(2, ("talkcolor", CYAN), ("name", "tortuga"))
    a.start_script(23)
    a.put_in_room(1, 1)
    a.put_actor(1, 300, 125)
    a.camera_follow(1)
    a.cutscene([])
    a.override("skip")
    a.say(254, [("at", 160, 20), ("center",), ("color", ORANGE), ("text", "JUEGO DE PRUEBA")])
    a.delay(30)
    a.say_ego([("text", "Hola. Soy Robi.\xff\x03Pulsa ESC para saltar esto.")])
    a.wait(2)
    a.walk_actor(1, 380, 125)
    a.wait(1, 1)
    a.end_override()
    a.label("skip")
    a.end_cutscene()
    a.cursor(1)                             # cursor y control
    a.cursor(3)
    a.start_script(24)
    a.start_script(22)
    a.start_script(25)
    a.stop()
    return a.finish()


def verbs_setup():
    a = A.Asm()
    for vid, name, x, y, key in VERB_LIST:
        a.verb(vid, ("new",), ("name", name), ("at", x, y), ("color", CYAN), ("hicolor", YELLOW),
               ("dimcolor", GREY), ("key", key), ("on",))
    a.verb(SENTENCE, ("new",), ("name", ""), ("at", 160, 145), ("center",), ("color", WHITE), ("on",))
    for i, (x, y) in enumerate(INV_SLOTS):
        a.verb(INV0 + i, ("new",), ("at", x, y), ("image", ICON_BLANK, ICON_ROOM), ("on",))
    a.verb(ARROW_UP, ("new",), ("at", 252, 152), ("image", ARROW_DIM_IMG, ICON_ROOM), ("dim",))
    a.verb(ARROW_DOWN, ("new",), ("at", 252, 176), ("image", ARROW_DIM_IMG, ICON_ROOM), ("dim",))
    a.stop()
    return a.finish()


def input_script():
    """20: L0 zona (1 verbo, 2 escena, 4 tecla), L1 verbo o tecla, L2 boton."""
    a = A.Asm()
    a.if_eq(L(0), 4, "notkey")              # la tecla M: la prueba de sonido
    a.if_eq(L(1), ord("M"), "notm")
    a.start_script(27)
    a.stop()
    a.label("notm")
    a.if_eq(L(1), ord("R"), "nothing")      # la tecla R: el juego desde el principio
    a.system_ops(1)
    a.stop()
    a.label("notkey")
    a.if_eq(L(0), 1, "notverb")
    a.if_nonzero(L(1), "nothing")           # sigue si L1 != 0
    a.if_ge(L(1), 7, "notmain")             # sigue si 7 >= L1: verbos 1..7
    a.mov(V(V_VERB), L(1))
    a.mov(V(V_OBJA), 0)
    a.start_script(25)
    a.stop()
    a.label("notmain")
    a.if_eq(L(1), ARROW_UP, "notup")
    a.subtract(V(V_INVOFF), 2)
    a.chain_script(22)
    a.label("notup")
    a.if_eq(L(1), ARROW_DOWN, "notdown")
    a.add(V(V_INVOFF), 2)
    a.chain_script(22)
    a.label("notdown")
    a.if_le(L(1), INV0, "nothing")          # sigue si 200 <= L1
    a.if_ge(L(1), INV0 + 3, "nothing")      # sigue si 203 >= L1
    a.expr(L(3), [("push", L(1)), ("push", INV0), ("sub",)])
    a.mov(L(4), V(V_INV0, L(3)))
    a.jump("object")
    a.label("notverb")
    a.if_eq(L(0), 2, "nothing")
    a.find_object(L(4), V(20), V(21))
    a.if_nonzero(L(4), "walk")
    a.label("object")
    a.if_nonzero(L(4), "nothing")           # sigue si L4 != 0
    a.if_eq(V(V_VERB), USE, "plain")
    a.if_zero(V(V_OBJA), "plain")
    a.mov(V(V_OBJA), L(4))
    a.start_script(25)
    a.stop()
    a.label("plain")
    a.sentence(V(V_VERB), L(4), V(V_OBJA))
    a.mov(V(V_OBJA), 0)
    a.stop()
    a.label("walk")
    a.sentence_stop()
    a.walk_actor(1, V(20), V(21))
    a.label("nothing")
    a.stop()
    return a.finish()


def sentence_script():
    """21: L0 verbo, L1 objeto A, L2 objeto B."""
    a = A.Asm()
    a.get_owner(L(3), L(1))
    a.if_eq(L(3), 15, "here")
    a.walk_to_object(1, L(1))
    a.wait(1, 1)
    a.label("here")
    a.verb_entry(L(4), L(1), L(0))
    a.if_nonzero(L(4), "none")
    a.start_object(L(1), L(0), [L(2)])
    a.stop()
    a.label("none")
    a.if_eq(L(0), LOOK, "nolook")
    a.mov(V(V_OVER), L(1))
    a.say_ego([("text", b"Es \xFF\x06" + bytes((V_OVER & 0xFF, V_OVER >> 8)) + b".")])
    a.stop()
    a.label("nolook")
    a.if_eq(L(0), WALK, "cant")
    a.stop()
    a.label("cant")
    a.say_ego([("text", "No puedo hacer eso.")])
    a.stop()
    return a.finish()


def inventory_script():
    """22: los cuatro huecos del inventario y las flechas."""
    a = A.Asm()
    a.inventory_count(L(3), 1)
    a.if_gt(V(V_INVOFF), 0, "offok")        # sigue si 0 > offset
    a.mov(V(V_INVOFF), 0)
    a.label("offok")
    a.mov(L(5), 0)
    a.label("slot")
    a.expr(L(6), [("push", V(V_INVOFF)), ("push", L(5)), ("add",), ("push", 1), ("add",)])
    a.find_inventory(L(2), 1, L(6))
    a.mov(V(V_INV0, L(5)), L(2))
    a.mov(L(7), ICON_BLANK)
    a.if_nonzero(L(2), "set")               # sigue si hay objeto
    a.mov(L(7), ICON_ITEM)
    a.verb_entry(L(4), L(2), ICON_VERB)
    a.if_nonzero(L(4), "set")
    a.start_object(L(2), ICON_VERB, [])
    a.mov(L(7), V(V_ICON))
    a.label("set")
    a.expr(L(8), [("push", INV0), ("push", L(5)), ("add",)])
    a.verb(L(8), ("image", L(7), ICON_ROOM), ("on",))
    a.inc(L(5))
    a.if_eq(L(5), 4, "slot")
    a.if_lt(V(V_INVOFF), 0, "updim")        # sigue si 0 < offset
    a.verb(ARROW_UP, ("image", ARROW_UP_IMG, ICON_ROOM), ("on",))
    a.jump("down")
    a.label("updim")
    a.verb(ARROW_UP, ("image", ARROW_DIM_IMG, ICON_ROOM), ("dim",))
    a.label("down")
    a.expr(L(9), [("push", V(V_INVOFF)), ("push", 4), ("add",)])
    a.if_gt(L(9), L(3), "downdim")          # sigue si cuantos > offset + 4
    a.verb(ARROW_DOWN, ("image", ARROW_DOWN_IMG, ICON_ROOM), ("on",))
    a.stop()
    a.label("downdim")
    a.verb(ARROW_DOWN, ("image", ARROW_DIM_IMG, ICON_ROOM), ("dim",))
    a.stop()
    return a.finish()


def hover_script():
    """24: el objeto bajo el cursor; si cambia, se rehace la linea de frase."""
    a = A.Asm()
    a.label("top")
    a.if_lt(V(52), 0, "wait")               # sigue si 0 < VAR_CURSORSTATE
    a.find_object(V(V_NEWOVER), V(20), V(21))
    a.if_ne(V(V_NEWOVER), V(V_OVER), "wait")   # sigue si cambia
    a.mov(V(V_OVER), V(V_NEWOVER))
    a.start_script(25)
    a.label("wait")
    a.brk()
    a.jump("top")
    return a.finish()


def sentence_line():
    """25: la palabra del verbo en la cadena 1 y la linea en el verbo 100."""
    a = A.Asm()
    for vid, name, _, _, _ in VERB_LIST:
        a.if_eq(V(V_VERB), vid, "n%d" % vid)
        a.load_string(1, name)
        a.jump("done")
        a.label("n%d" % vid)
    a.label("done")
    sv = bytes((1, 0))                      # (el 7 lleva la cadena, no una variable)
    so = bytes((V_OVER & 0xFF, V_OVER >> 8))
    sa = bytes((V_OBJA & 0xFF, V_OBJA >> 8))
    a.if_zero(V(V_OBJA), "two")             # sigue si no hay objeto A
    a.verb(SENTENCE, ("name", b"\xFF\x07" + sv + b" \xFF\x06" + so), ("on",))
    a.stop()
    a.label("two")
    a.verb(SENTENCE, ("name", b"\xFF\x07" + sv + b" \xFF\x06" + sa + b" con \xFF\x06" + so), ("on",))
    a.stop()
    return a.finish()


def take_coin():
    """26: coger la moneda (fuera de los scripts de la moneda)."""
    a = A.Asm()
    a.pickup(COIN)
    a.set_state(COIN, 0)
    a.object_name(COIN, "moneda vieja")
    a.stop()
    return a.finish()


def sound_test():
    """27 (tecla M): los sonidos y lo que ven los scripts (isSoundRunning y
    VAR_MUSIC_TIMER), apuntado en las variables 230-246."""
    import fixture as F
    a = A.Asm()
    a.sound(F.SND_BELL)                     # en la cola
    a.sound_running(V(230), F.SND_BELL)     # 1: en la cola
    a.brk()
    a.sound_running(V(231), F.SND_BELL)     # 1: suena
    a.sound(F.SND_TRACK)                    # dos pistas en el mismo paso: la cola va del
    a.sound(F.SND_LOOP)                     # ultimo al primero y se queda SND_TRACK
    a.brk()
    a.sound_running(V(232), F.SND_TRACK)    # 1
    a.sound_running(V(233), F.SND_LOOP)     # 0
    a.mov(V(234), V(14))                    # VAR_MUSIC_TIMER
    a.delay(30)
    a.sound_running(V(235), F.SND_BELL)     # 0: ya ha acabado
    a.sound(F.SND_BUZZ)
    a.sound(F.SND_BUZZ)                     # dos a la vez
    a.brk()
    a.stop_sound(F.SND_BUZZ)
    a.sound_running(V(236), F.SND_BUZZ)     # 0
    a.label("wait")                         # hasta que acaba la pista
    a.brk()
    a.sound_running(V(237), F.SND_TRACK)
    a.if_zero(V(237), "wait")
    a.mov(V(238), V(14))                    # el reloj sigue
    a.sound(F.SND_LOOP)
    a.brk()
    a.sound_running(V(239), F.SND_LOOP)     # 1: da vueltas
    a.stop_music()
    a.sound_running(V(240), F.SND_LOOP)     # 0
    a.mov(V(241), V(14))
    a.sound(F.SND_BELL)
    a.sound_kludge([-1])                    # la cola, ahora mismo
    a.sound_running(V(242), F.SND_BELL)     # 1
    a.sound(F.SND_ADL)                      # AdLib (iMuse): da vueltas hasta que se para
    a.sound(F.SND_ADL2)                     # y otro que acaba (~1 s)
    a.brk()
    a.sound_running(V(243), F.SND_ADL)      # 1
    a.delay(90)
    a.sound_running(V(247), F.SND_ADL2)     # 0: ya ha acabado
    a.sound_running(V(248), F.SND_ADL)      # 1: sigue
    a.start_music(F.SND_BUZZ)
    a.sound_running(V(244), F.SND_BUZZ)     # 1: en la cola
    a.mov(V(245), V(23))                    # VAR_LAST_SOUND
    a.mov(V(246), 1)
    a.stop()
    return a.finish()


def global_scripts():
    return {1: boot(), 20: input_script(), 21: sentence_script(), 22: inventory_script(),
            23: verbs_setup(), 24: hover_script(), 25: sentence_line(), 26: take_coin(),
            27: sound_test()}
