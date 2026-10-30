"""Pruebas en el emulador (ZEsarUX por ZRCP): el Z80 contra el modelo.

    python tools/nexttest.py unit 300      # aritmetica y cajas, con datos al azar
    python tools/nexttest.py walk          # paseo guionizado: actor, camara y sprites
                                           # == modelo, paso a paso, byte a byte
    python tools/nexttest.py random 400    # clics al azar en las dos habitaciones
    python tools/nexttest.py screen        # la pantalla de ZEsarUX == la del modelo
    python tools/nexttest.py objetos 40    # estados de objetos al azar: tiras de fondo y
                                           # planos Z, objeto bajo el cursor y actor == modelo
    python tools/nexttest.py escala        # el camino con escalado == modelo
    python tools/nexttest.py costumes      # la tortuga (120 px) y la medusa (32 colores)
    python tools/nexttest.py gif SALIDA.gif
    python tools/nexttest.py scripts       # la maquina virtual con los scripts del juego de
                                           # prueba: variables, ranuras, objetos == modelo
    python tools/nexttest.py juego [habitaciones]  # tu juego (build/sd, original/): paseos
                                                   # al azar == modelo, solo numeros
    python tools/nexttest.py saltos        # pasos sin pintar los actores (con retraso): maquina
                                           # virtual == modelo y los sprites de antes, movidos
    python tools/nexttest.py actores       # los demas actores en sprites: la tortuga y la medusa
                                           # con el protagonista (orden, planos Z, escala) == modelo
    python tools/nexttest.py pseudo        # pseudoRoom (la 201 es el almacen), roomScroll fuera
                                           # del ancho y drawObject con setXY (el cofre se mueve)
    python tools/nexttest.py interfaz      # el juego de prueba desde el arranque: verbos,
                                           # frases, textos, inventario == modelo
    python tools/nexttest.py teclas        # el juego de prueba en modo normal (sin TMODE):
                                           # teclas y clics de ZEsarUX llegan a los scripts
    python tools/nexttest.py juegos        # el menu de juegos (modo normal): una tarjeta con
                                           # el juego de prueba tres veces, elegir y cambiar
    python tools/nexttest.py arranque 600  # tu juego desde el arranque (ESC en la intro) y
                                           # luego clics al azar en verbos, objetos e
                                           # inventario: maquina virtual e interfaz ==
                                           # modelo, solo numeros (sin pantallas ni textos)
    python tools/nexttest.py arranque 300 todas [guardar5]  # y despues el protagonista a cada
                                           # habitacion (o a las que se digan), 60 pasos
    python tools/nexttest.py partida NOMBRE [CADA] [HASTA] [DESDE]  # una partida de partida.py
                                           # (build/partida/NOMBRE.pkl): sus entradas, paso a
                                           # paso, en el modelo desde el arranque y en el Z80;
                                           # cada CADA pasos (y al cambiar de habitacion) ==
                                           # modelo, solo numeros; al final, el modelo == la
                                           # partida guardada

Usan el juego de prueba (python tools/build.py prueba), salvo "juego". El programa tiene un
modo prueba (TMODE): espera a que TREQ valga 1 (un paso), 2 (cargar
habitacion) o 3 (llamar a una rutina) y pone TDONE a 1 al terminar.
"""
import os
import random
import struct
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import convert as C  # noqa: E402
import model as M  # noqa: E402
import preview as P  # noqa: E402
import sound as SN  # noqa: E402
import ui as U  # noqa: E402
from zrcp import Zrcp  # noqa: E402

SD = os.path.join(ROOT, "build", "prueba_sd")
SD_JUEGO = os.path.join(ROOT, "build", "sd")
OVS_PAGE = 107                  # (la capa del menu de juegos: sus variables)
ORIGINAL = os.path.join(ROOT, "original")
SYM = os.path.join(ROOT, "build", "scumm.sym")
SPRBUF = 0x6000


def symbols():
    sym = {}
    for line in open(SYM):
        if ":" in line and "EQU" in line:
            name, val = line.split(":", 1)
            sym[name.strip()] = int(val.split("EQU")[1].strip(), 16)
    return sym


class Next:
    def __init__(self, visible=False, sd=SD):
        self.s = symbols()
        self.z = Zrcp(visible=visible)
        self.z.cmd("hard-reset-cpu")
        time.sleep(0.5)
        self.z.load(os.path.join(sd, "scumm.nex"))
        for _ in range(30):                 # modo de prueba en cuanto esta cargado: si el
            time.sleep(0.05)                # modo normal llega a desplazar la pantalla, el
            self.w8("TMODE", 1)             # copper deja puesto su recorte de 4 pixeles
        time.sleep(1.0)
        self.w8("TMODE", 1)
        time.sleep(0.3)

    def w8(self, name, v):
        self.z.write(self.s[name], bytes((v & 0xFF,)))

    def w16(self, name, v):
        self.z.write(self.s[name], (v & 0xFFFF).to_bytes(2, "little"))

    def r8(self, name):
        return self.z.read(self.s[name], 1)[0]

    def read(self, name, n):
        return self.z.read(self.s[name], n)

    def request(self, req, timeout=10):
        self.w8("TDONE", 0)
        self.w8("TREQ", req)
        t0 = time.time()
        while time.time() - t0 < timeout:
            if self.r8("TDONE"):
                return
            time.sleep(0.005)
        raise RuntimeError("el Z80 no termina (TREQ=%d)" % req)

    def call(self, func, args):
        self.z.write(self.s["TARGS"], args)
        self.w8("TFUNC", func)
        self.request(3)
        return self.read("TRES", 8)

    def load_room(self, n):
        self.w8("TROOM", n)
        self.request(2, timeout=30)

    def step(self, click=None, mouse=None, button=0, key=0):
        """click: andar directo a (x, y) de la habitacion; mouse: (x, y) de pantalla.
        (TCLICK, TCX, TCY van seguidos, y TMX, TMY, TBUT, TKEY tambien: una orden cada
        uno; el Z80 solo pone TCLICK a 0, asi que un 0 ya escrito no se repite.)"""
        if click is None:
            if getattr(self, "_click", 1):
                self.w8("TCLICK", 0)
                self._click = 0
        else:
            self.z.write(self.s["TCLICK"], struct.pack("<BHH", 1, click[0] & 0xFFFF, click[1] & 0xFFFF))
            self._click = 1
        if mouse is not None:
            self.z.write(self.s["TMX"], struct.pack("<HHBB", mouse[0] & 0xFFFF, mouse[1] & 0xFFFF,
                                                    button, key))
        else:
            self.z.write(self.s["TBUT"], bytes((button, key)))
        self.request(1, timeout=60)         # (entrar en una habitacion grande tarda)

    def page(self, pg):
        """Una pagina de 8 KB entera (de la RAM fisica, sin tocar nada del Z80)."""
        return self.z.read_phys(pg * 0x2000, 0x2000)

    def actor(self):
        return self.read("ACTOR", M.ACTOR_REC)

    def actor_recs(self):
        """Las fichas de los actores 1-12 (CAST_PAGE; la de ACTOR si es la que esta alli)."""
        page = self.page(M.CAST_PAGE)
        n = M.ACTOR_REC
        recs = [bytes(page[n * i:n * i + n]) for i in range(12)]
        k = self.r8("ACTN")
        if 0 < k < 13:
            recs[k - 1] = self.actor()
        return recs

    def camera(self):
        return self.read("CAM_CUR", 7)

    def enter_room(self, room):
        """startScene(room) con scripts."""
        self.w8("TROOM", room)
        self.request(7, timeout=60)

    def enter_ego(self, room):
        """El protagonista a la habitacion (World.enter_with_ego)."""
        self.w8("TROOM", room)
        self.request(8, timeout=60)

    def boot(self):
        """La maquina virtual desde cero y el script 1."""
        self.request(9, timeout=120)

    def reset_vm(self, room):
        self.w8("TROOM", room)
        self.request(6, timeout=60)

    def vm_state(self):
        """La maquina virtual del Z80, como en el modelo (para compararlas)."""
        import struct as st
        d = {}
        d["room"] = self.r8("CURROOM")
        d["vars"] = list(st.unpack("<800h", self.read("VARS", 1600)))
        d["bits"] = self.read("BITS", 256)
        n = int.from_bytes(self.read("NOBJG", 2), "little")
        d["state"] = self.read("OBJST", n)
        d["owner"] = self.read("OBJOWN", n)
        cl = self.page(self.s.get("CLASS_PAGE", 13))[:4 * n] if n else b""    # (sin pasar por SPRBUF)
        d["classes"] = [int.from_bytes(cl[4 * i:4 * i + 4], "little") for i in range(n)]
        raw = self.read("SLOTS", 20 * 70)
        slots = []
        for i in range(20):
            b = raw[70 * i:70 * i + 70]
            dl = b[16] | b[17] << 8 | b[18] << 16
            if dl & 0x800000:
                dl -= 1 << 24
            slots.append(dict(status=b[0], where=b[1], number=b[2] | b[3] << 8, pc=b[8] | b[9] << 8,
                              fres=bool(b[12]), rec=bool(b[13]), fcount=b[14], cso=b[15], delay=dl,
                              locals=list(st.unpack("<25h", b[20:70]))))
        d["slots"] = slots
        d["actors"] = self.actor_recs()
        return d

    def frame(self):
        """(bytes de patrones, los de 4 bits seguidos de los de 8, atributos)."""
        n = int.from_bytes(self.read("SPRUSED", 2), "little")
        n8 = int.from_bytes(self.read("SPRUSD8", 2), "little") if "SPRUSD8" in self.s else 0
        pats = self.z.read(SPRBUF, n) if n else b""
        if n8:
            pats += self.z.read_phys(self.s.get("SPRB_PAGE", 223) * 0x2000, n8)
        return n + n8, pats, self.read("ATTRBUF", 5 * M.NSPR_ACTOR)

    def set_state(self, k, v):
        self.w8("TOBJ", k)
        self.w8("TSTATE", v)
        self.request(4, timeout=30)

    def load_costume(self, c):
        self.w8("TCOST", c)
        self.request(5, timeout=30)

    def strip(self, s_, rec):
        self.call(7, bytes((s_,)))
        return self.z.read(SPRBUF, rec)

    def save(self, slot):
        """Guardar la partida en el hueco slot (SAVEn.DAT): 0 si ha ido bien."""
        self.w8("TROOM", slot)
        self.request(10, timeout=60)
        return self.r8("TRES")

    def load(self, slot):
        """Cargar la del hueco slot: 0 si ha ido bien."""
        self.w8("TROOM", slot)
        self.request(11, timeout=60)
        return self.r8("TRES")

    def l2_palette(self):
        """La primera paleta de Layer 2: 256 colores de 9 bits."""
        txt = self.z.cmd("tbblue-get-palette layer2 first 0 256")
        return [int(v, 16) for v in txt.split()]

    def close(self):
        self.z.close()


def game():
    g, _ = C.find_game(os.path.join(ROOT, "build", "prueba"))
    return g


# ---------------------------------------------------------------------------
def cmd_unit(n):
    rng = random.Random(5)
    g = game()
    rd = C.RoomData(g.room(1), g.index)
    boxes = M.Boxes(rd.boxes, rd.matrix)
    nx = Next()
    nx.load_room(1)
    bad = 0

    def check(name, got, want, args):
        nonlocal bad
        if got != want:
            bad += 1
            if bad <= 12:
                print("%s%s: Z80 %s, modelo %s" % (name, args, got, want))

    for _ in range(n):
        a = rng.randint(-2**31, 2**31 - 1)
        b = rng.randint(-32768, 32767)
        r = nx.call(3, struct.pack("<ih", a, b))
        check("mul32x16", struct.unpack("<i", r[:4])[0], M.i32(a * b), (a, b))
        a = rng.randint(-2**31 + 1, 2**31 - 1)
        b = rng.choice((rng.randint(-2**24, 2**24), rng.randint(-300, 300))) or 7
        r = nx.call(4, struct.pack("<ii", a, b))
        check("div32", struct.unpack("<i", r[:4])[0], M.cdiv(a, b), (a, b))
        pts = [(rng.randint(-50, 700), rng.randint(-50, 200)) for _ in range(3)]
        if rng.random() < 0.3:
            pts[1] = (pts[0][0], pts[1][1]) if rng.random() < 0.5 else (pts[1][0], pts[0][1])
        r = nx.call(1, struct.pack("<6h", *pts[0], *pts[1], *pts[2]))
        check("closest", struct.unpack("<2h", r[:4]), M.closest_pt_on_line(*pts), pts)
        x, y = rng.randint(-100, 740), rng.randint(-60, 220)
        r = nx.call(2, struct.pack("<2h", x, y))
        got = struct.unpack("<2hB", r[:5])
        check("adjust", got, boxes.adjust_xy(x, y), (x, y))
        bx = rng.randrange(len(rd.boxes))
        r = nx.call(5, struct.pack("<2hB", x, y, bx))
        check("inbox", bool(r[0]), boxes.in_box(bx, x, y), (bx, x, y))
    for f in range(len(rd.boxes)):
        for t in list(range(len(rd.boxes))) + [255]:
            r = nx.call(6, bytes((f, t)))
            want = boxes.next_box(f, t) & 0xFF
            check("nextbox", r[0], want, (f, t))
    print("%d casos, %d diferencias" % (n, bad))
    nx.close()
    return bad == 0


def compare_tick(nx, eng, fr, t, quiet=False):
    errs = []
    if eng.actor is not None:               # (el actor solo del motor; con la maquina
        dif = actor_diff(nx.actor(), eng.actor.pack())     # virtual, compare_vm)
        if dif:
            errs.append("actor: " + dif)
    zc, mc = nx.camera(), eng.cam.pack()
    if zc != mc:
        errs.append("camara: Z80 %s / modelo %s" % (zc.hex(), mc.hex()))
    n, pats, attrs = nx.frame()
    if n != fr.nbytes:
        errs.append("patrones: Z80 %d bytes, modelo %d (%d de 4 bits y %d de 8)" % (
            n, fr.nbytes, fr.used, fr.used8))
    elif pats != fr.patterns:
        k = next(i for i in range(len(pats)) if pats[i] != fr.patterns[i])
        errs.append("patrones: byte %d (%s)" % (k, "tile de 4 bits %d" % (k // 128) if k < fr.used
                                                else "tile de 8 bits %d" % ((k - fr.used) // 256)))
    if attrs != fr.attrs:
        k = next(i for i in range(len(attrs)) if attrs[i] != fr.attrs[i])
        errs.append("atributos: sprite %d: Z80 %s / modelo %s" % (
            k // 5, attrs[k // 5 * 5:k // 5 * 5 + 5].hex(), fr.attrs[k // 5 * 5:k // 5 * 5 + 5].hex()))
    if errs and not quiet:
        print("paso %d:" % t)
        for e in errs:
            print("   ", e)
    return not errs


def run_script(nx, room, clicks, steps, g=None, costume=1, states=None):
    """clicks: [(paso, x, y)]; states: {paso: (objeto, estado)}."""
    g = g or game()
    rd = C.RoomData(g.room(room), g.index)
    eng = M.Engine(rd, g.costume(costume))
    nx.load_room(room)
    todo = dict((t, (x, y)) for t, x, y in clicks)
    states = states or {}
    bad = 0
    for t in range(steps):
        if t in states:
            k, v = states[t]
            eng.set_state(k, v)
            nx.set_state(k, v)
        click = todo.get(t)
        fr = eng.tick(click)
        nx.step(click)
        if not compare_tick(nx, eng, fr, t):
            bad += 1
            if bad > 3:
                break
    return bad


def expected_strip(eng, s_):
    rd = eng.room
    out = bytearray(eng.work_bg[:, 8 * s_:8 * s_ + 8].T.tobytes())
    for z in eng.work_zp:
        out += z[:, s_].tobytes()
    return bytes(out)


def compare_strips(nx, eng, label):
    """Las tiras de trabajo == modelo. Las que cambiaron fuera de la vista (STALE) se
    rehacen al entrar en la vista o cuando un actor que se ve las tapa, asi que ninguna
    puede estar a la vista."""
    rd = eng.room
    rec = (8 + len(rd.zplanes)) * rd.height
    pix = 8 * rd.height
    stale = nx.read("STALE", 16)
    ss = nx.r8("CAM_SS")
    bad = []
    for s_ in range(rd.width // 8):
        got, want = nx.strip(s_, rec), expected_strip(eng, s_)
        if stale[s_ >> 3] & (1 << (s_ & 7)):
            if ss <= s_ < ss + 40:
                bad.append(s_)
        elif got != want:
            bad.append(s_)
    if bad:
        print("%s: tiras distintas %s" % (label, bad[:10]))
    return not bad


def cmd_objetos(n):
    """Cambios de estado al azar en el patio: tiras de trabajo, objeto bajo el
    cursor y el actor (con la barandilla tapandolo) == modelo."""
    rng = random.Random(9)
    g = game()
    rd = C.RoomData(g.room(1), g.index)
    eng = M.Engine(rd, g.costume(1))
    nx = Next()
    nx.load_room(1)
    bad = 0 if compare_strips(nx, eng, "al entrar") else 1
    for i in range(n):
        k = rng.randrange(len(eng.objs))
        v = rng.randrange(len(eng.objs[k].images) + 1)
        eng.set_state(k, v)
        nx.set_state(k, v)
        if not compare_strips(nx, eng, "cambio %d (objeto %d, estado %d)" % (i, k, v)):
            bad += 1
            if bad > 3:
                break
    for _ in range(80):
        x, y = rng.randint(0, rd.width), rng.randint(0, rd.height)
        want = M.obj_at(eng.objs, x, y)
        got = nx.call(8, struct.pack("<2h", x, y))[0]
        if got != (0xFF if want is None else want):
            bad += 1
            print("objeto en (%d, %d): Z80 %d, modelo %s" % (x, y, got, want))
    # el robot detras de la barandilla visible (plano Z del objeto)
    bad += run_script(nx, 1, [(0, 290, 110), (30, 280, 125), (55, 300, 108)], 80,
                      states={0: (3, 1), 40: (1, 2), 60: (0, 2)})
    print("objetos: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


def cmd_escala():
    nx = Next()
    clicks = [(0, 240, 72), (40, 430, 130), (70, 250, 100), (100, 120, 138), (130, 240, 60)]
    bad = run_script(nx, 3, clicks, 170)
    print("escala: %s" % ("igual que el modelo" if not bad else "%d pasos distintos" % bad))
    nx.close()
    return bad == 0


def cmd_costumes():
    nx = Next()
    bad = 0
    for cost, room, clicks in ((2, 1, [(0, 500, 130), (40, 150, 120)]),
                               (3, 2, [(0, 60, 125), (30, 280, 135)]),
                               (2, 3, [(0, 240, 75), (30, 240, 135)])):
        nx.load_costume(cost)
        b = run_script(nx, room, clicks, 60, costume=cost)
        print("costume %d en la habitacion %d: %s" % (cost, room, "igual" if not b else "distinto"))
        bad += b
    nx.load_costume(1)
    nx.close()
    return bad == 0


def cmd_walk():
    nx = Next()
    bad = run_script(nx, 1, P.WALK, 200)
    print("paseo: %s" % ("igual que el modelo" if not bad else "%d pasos distintos" % bad))
    nx.close()
    return bad == 0


def cmd_random(n):
    rng = random.Random(11)
    nx = Next()
    bad = 0
    for room, w in ((1, 640), (2, 320)):
        clicks = []
        t = 0
        while t < n // 2:
            clicks.append((t, rng.randint(-20, w + 20), rng.randint(-10, 160)))
            t += rng.randint(1, 40)
        bad += run_script(nx, room, clicks, n // 2)
    print("clics al azar: %s" % ("igual que el modelo" if not bad else "%d pasos distintos" % bad))
    nx.close()
    return bad == 0


# --- pantalla ------------------------------------------------------------------
def grab(nx, path):
    root, ext = os.path.splitext(path)      # (con el puerto: puede haber otra prueba a la vez)
    img = np.array(nx.z.screenshot("%s_%d%s" % (root, nx.z.port, ext)))
    return img


def find_offset(img):
    """Donde empieza la zona de 320x256 en la captura (a 2x)."""
    return 32, 48


def screen_case(nx, room, costume, clicks, states=None, steps=60, every=12):
    """Compara capturas de ZEsarUX con la pantalla del modelo."""
    g = game()
    rd = C.RoomData(g.room(room), g.index)
    cost = g.costume(costume)
    eng = M.Engine(rd, cost)
    scr = M.Screen(rd, C.palette_bytes(rd.palette), cost)
    nx.load_costume(costume)
    nx.load_room(room)
    states = states or {}
    todo = dict((a, (b, c)) for a, b, c in clicks)
    bad = 0
    for t in range(steps):
        if t in states:
            k, v = states[t]
            eng.set_state(k, v)
            nx.set_state(k, v)
        fr = eng.tick(todo.get(t))
        nx.step(todo.get(t))
        if t % every:
            continue
        want = scr.render(eng.cam.left(), fr, bg=eng.work_bg)
        for _ in range(30):
            got = grab(nx, os.path.join(ROOT, "build", "_grab.png"))
            ox, oy = find_offset(got)
            g2 = got[oy:oy + 512:2, ox:ox + 640:2]
            diff = np.any(g2 != want, axis=2)
            diff[:, 319] = False        # ZEsarUX no pinta la ultima columna de Layer 2
            if not diff.any():
                break
            time.sleep(0.1)
        if diff.any():
            bad += 1
            ys, xs = np.nonzero(diff)
            print("hab %d costume %d paso %d: %d pixeles distintos (primero en x=%d y=%d)" % (
                room, costume, t, diff.sum(), xs[0], ys[0]))
            Image.fromarray(np.concatenate([g2, want], axis=1)).save(
                os.path.join(ROOT, "build", "diff_%d_%d_%02d.png" % (room, costume, t)))
    return bad


def cmd_screen():
    nx = Next()
    bad = screen_case(nx, 1, 1, P.WALK, states={5: (3, 1), 20: (1, 2), 30: (0, 2)})
    bad += screen_case(nx, 2, 3, [(0, 60, 125), (30, 280, 135)], steps=48)
    bad += screen_case(nx, 3, 2, [(0, 240, 75), (30, 240, 135)], steps=48)
    nx.load_costume(1)
    print("pantallas: %s" % ("iguales" if not bad else "%d distintas" % bad))
    nx.close()
    return bad == 0


def cmd_gif(out, steps=470, every=2):
    """GIF del juego de prueba con la interfaz (lo que hace la prueba interfaz, desde
    el arranque): capturas de ZEsarUX, cada una comprobada con el modelo."""
    g = game()
    w = boot_world(g, g.costume(1))
    nx = Next()
    nx.boot()
    plan = dict(IFACE_PLAN)
    mouse = (160, 100)
    imgs = []
    bad = 0
    for t in range(steps):
        button = key = 0
        if t in plan:
            m, button, key, room = resolve(w, plan[t])
            if room:
                w.enter_with_ego(room)
                nx.enter_ego(room)
            if m is not None:
                mouse = m
        fr = w.tick(mouse=mouse, button=button, key=key)
        nx.step(mouse=mouse, button=button, key=key)
        if t % every:
            continue
        rd = w.eng.room
        scr = M.Screen(rd, bytes(w.pal9), w.cost)
        want = scr.rgb[w.screen()]
        if fr is not None:
            scr.draw_sprites(want, fr)
        for _ in range(30):
            got = grab(nx, os.path.join(ROOT, "build", "_grab.png"))
            ox, oy = find_offset(got)
            g2 = got[oy:oy + 512:2, ox:ox + 640:2]
            diff = np.any(g2 != want, axis=2)
            diff[:, 319] = False
            if not diff.any():
                break
            time.sleep(0.05)
        bad += bool(diff.any())
        imgs.append(Image.fromarray(np.ascontiguousarray(g2[M.ROOM_Y0:M.ROOM_Y0 + 200])))
    imgs[0].save(out, save_all=True, append_images=imgs[1:], duration=80 * every, loop=0,
                 optimize=True)
    print("GIF:", out, len(imgs), "imagenes,", bad, "distintas del modelo")
    nx.close()
    return bad == 0


def model_vm_state(w):
    vm = w.vm
    d = {"room": w.room, "vars": list(vm.vars), "bits": bytes(vm.bits),
         "state": bytes(vm.state), "owner": bytes(vm.owner), "classes": list(vm.classes)}
    d["slots"] = [dict(status=s.status, where=s.where, number=s.number & 0xFFFF, pc=s.pc,
                       fres=bool(s.freeze_res), rec=bool(s.recursive), fcount=s.freeze_count & 0xFF,
                       cso=s.cs_override & 0xFF, delay=s.delay, locals=list(s.locals)) for s in vm.slots]
    d["actors"] = [a.pack() for a in vm.actors[1:13]]
    return d


# Los campos de la ficha de un actor (Actor.pack()), para decir cual es distinto
ACTOR_FIELDS = [("x", 2), ("y", 2), ("facing", 2), ("target_facing", 2), ("box", 1), ("moving", 1),
                ("frame", 1), ("dest_x", 2), ("dest_y", 2), ("dest_box", 1), ("dest_dir", 2),
                ("cur_box", 1), ("cur_x", 2), ("cur_y", 2), ("next_x", 2), ("next_y", 2), ("dxf", 4),
                ("dyf", 4), ("xfrac", 2), ("yfrac", 2), ("anim_progress", 1), ("anim_speed", 1),
                ("stopped", 2), ("curpos", 32), ("start", 32), ("end", 32), ("cframe", 32),
                ("scalex", 1), ("scaley", 1), ("speedx", 1), ("speedy", 1), ("number", 1), ("room", 1),
                ("costume", 1), ("visible", 1), ("needs_init", 1), ("init_frame", 1), ("walk_frame", 1),
                ("stand_frame", 1), ("talk_start", 1), ("talk_stop", 1), ("elevation", 2), ("width", 1),
                ("talk_color", 1), ("boxscale", 2), ("ignore_boxes", 1), ("force_clip", 1),
                ("anim_counter", 2), ("top", 2), ("bottom", 2), ("strip0", 2), ("strip1", 2),
                ("palette", 32), ("sound", 1), ("sound_counter", 1)]


def actor_field(k):
    o = 0
    for name, n in ACTOR_FIELDS:
        if o <= k < o + n:
            return name, o, n
        o += n
    return "?", k, 1


def actor_diff(za, ma):
    """El primer campo distinto de dos fichas (texto) o None."""
    if za == ma:
        return None
    k = next(i for i in range(min(len(za), len(ma))) if za[i] != ma[i])
    name, o, n = actor_field(k)
    return "%s: Z80 %s / modelo %s" % (name, za[o:o + n].hex(), ma[o:o + n].hex())


def compare_vm(nx, w, label):
    z = nx.vm_state()
    m = model_vm_state(w)
    errs = []
    if z["room"] != m["room"]:
        errs.append("habitacion: Z80 %d, modelo %d" % (z["room"], m["room"]))
    for key in ("vars", "bits", "state", "owner", "classes"):
        a, b = list(z[key]), list(m[key])
        if a != b:
            k = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
            errs.append("%s[%d]: Z80 %s, modelo %s" % (key, k, a[k] if k < len(a) else "-",
                                                      b[k] if k < len(b) else "-"))
    for i, (a, b) in enumerate(zip(z["slots"], m["slots"])):
        if a["status"] != b["status"]:
            errs.append("ranura %d: estado Z80 %d, modelo %d" % (i, a["status"], b["status"]))
        elif a["status"]:
            for f in ("number", "where", "pc", "fres", "rec", "fcount", "cso", "delay", "locals"):
                if a[f] != b[f]:
                    errs.append("ranura %d (script %d) %s: Z80 %s, modelo %s" % (i, b["number"], f, a[f], b[f]))
                    break
    for i in range(12):
        dif = actor_diff(z["actors"][i], m["actors"][i])
        if dif:
            errs.append("actor %d: %s" % (i + 1, dif))
    if "SNDST" in nx.s:                     # el sonido que ven los scripts (pagina UIP)
        zs = nx.z.read_phys(UIP * 0x2000 + nx.s["SNDST"] - 0xE000, len(w.vm.sound.pack()))
        ms = w.vm.sound.pack()
        if zs != ms:
            errs.append("sonido: Z80 %s, modelo %s" % (zs.hex(), ms.hex()))
    if getattr(w, "rstamp", 0):             # ya se ha cargado alguna habitacion
        zp = nx.l2_palette()
        mp = [w.pal9[2 * i] << 1 | w.pal9[2 * i + 1] & 1 for i in range(256)]
        if zp != mp:
            k = next(i for i in range(256) if zp[i] != mp[i])
            errs.append("paleta[%d]: Z80 %03x, modelo %03x" % (k, zp[k], mp[k]))
        zy = nx.z.nextreg(0x17)
        if zy != -w.shake_y & 0xFF:
            errs.append("temblor (NR $17): Z80 %d, modelo %d" % (zy, -w.shake_y & 0xFF))
    return errs


def world_screen(nx, w, fr, label, t):
    """La pantalla de ZEsarUX == la del modelo (solo el juego de prueba)."""
    rd = w.eng.room
    scr = M.Screen(rd, bytes(w.pal9), w.cost)
    want = scr.rgb[w.screen()]
    if fr is not None:
        scr.draw_sprites(want, fr)
    for _ in range(30):
        got = grab(nx, os.path.join(ROOT, "build", "_grab.png"))
        ox, oy = find_offset(got)
        g2 = got[oy:oy + 512:2, ox:ox + 640:2]
        diff = np.any(g2 != want, axis=2)
        diff[:, 319] = False            # ZEsarUX no pinta la ultima columna de Layer 2
        if not diff.any():
            return True
        time.sleep(0.1)
    ys, xs = np.nonzero(diff)
    print("%s, paso %d: pantalla con %d pixeles distintos (primero en x=%d y=%d)" % (
        label, t, diff.sum(), xs[0], ys[0]))
    Image.fromarray(np.concatenate([g2, want], axis=1)).save(
        os.path.join(ROOT, "build", "diff_%s_%02d.png" % (label, t)))
    return False


def run_world(nx, w, steps, label, clicks=None, room_changes=None, quiet=False, screens=(), events=None,
              ui=False, show_text=True):
    """Pasos de mundo comparando maquina virtual, motor e interfaz (y la pantalla en los
    pasos de screens). events: {paso: (raton, boton, tecla)}."""
    clicks = clicks or {}
    room_changes = room_changes or {}
    events = events or {}
    bad = 0
    mouse = (160, 100)
    for t in range(steps):
        if t in room_changes:
            w.enter_with_ego(room_changes[t])
            nx.enter_ego(room_changes[t])
        click = clicks.get(t)
        button, key = 0, 0
        if t in events:
            mouse, button, key = events[t]
        fr = w.tick(click=click, mouse=mouse, button=button, key=key)
        nx.step(click, mouse=mouse, button=button, key=key)
        errs = []
        if w.room:
            if not compare_tick(nx, w.eng, fr, t, quiet):
                errs.append("(motor)")
        if t in screens and not world_screen(nx, w, fr, label, t):
            errs.append("(pantalla)")
        if ui:
            errs += compare_ui(nx, w, full=(t in screens), show_text=show_text)
        errs += compare_vm(nx, w, label)    # (despues: las clases pasan por SPRBUF)
        if errs:
            print("%s, paso %d:" % (label, t))
            for e in errs[:6]:
                print("   ", e)
            bad += 1
            if bad > 2:
                break
    return bad


def make_world(g, cost, room):
    cache = {}

    def rooms(n):
        if n not in cache:
            cache[n] = C.RoomData(g.room(n), g.index)
        return cache[n]

    scripts = {}
    for i in range(len(g.index.dirs["DSCR"])):
        r = g.resource("DSCR", i)
        if r is not None:
            scripts[i] = bytes(g.data[r[1]:r[2]])
    costs = {}

    def costumes(n):
        """El costume n como lo carga el Z80 (Cnnn.DAT), o None si no hay."""
        if n not in costs:
            try:
                costs[n] = g.costume(n)
            except (ValueError, IndexError, KeyError):
                costs[n] = None
        return costs[n]

    sres = SN.sound_resources(g)
    return M.World(rooms, scripts, g.index.objects, cost, room, g.index.maxs[0], g.index.maxs[2],
                   charsets=C.game_charsets(g), verb_image=C.verb_images(g), costumes=costumes,
                   sounds=SN.sound_table(sres, g.folder))


# --- la interfaz: el estado del Z80 y el del modelo -----------------------------------
def cstr(b):
    """La cadena hasta su 0 (los escapes enteros, como resStrLen)."""
    b = bytes(b)
    return b[:U.res_str_len(b)]


UIP, HEAPP = 94, 95
VSZ = 36


def z80_ui(nx, full=False):
    import struct as st
    g = nx.read

    def w(name):
        return st.unpack("<h", g(name, 2))[0]

    def b(name):
        return g(name, 1)[0]
    d = {}
    d["have_msg"] = b("HAVEMSG")
    d["talk_delay"] = w("TALKD")
    d["keep_text"] = bool(b("TKEEP"))
    d["charset_color"] = b("CSCOL")
    d["buf_pos"] = b("BUFPOS")
    d["next"] = (w("NEXTL"), w("NEXTT"))
    buf = g("MSGBUF", 256)
    d["buf"] = bytes(buf[:buf.index(0)] if 0 in buf else buf)
    d["has_mask"] = bool(b("HASMASK"))
    d["mask_screen"] = b("MASKSCR")
    d["mask_rect"] = st.unpack("<4h", g("MASKR", 8)) if b("MASKV") else None
    d["verb_rect"] = st.unpack("<4h", g("VRECT", 8)) if b("VRECTV") else None
    tab = g("STAB", 6 * 22)
    d["strings"] = [(st.unpack("<hhhBBBBB", tab[22 * i:22 * i + 11]), st.unpack("<hhhBBBBB", tab[22 * i + 11:22 * i + 22]))
                    for i in range(6)]
    d["cmap"] = list(g("TCMAP", 16))
    d["chdata"] = bytes(g("CHDATA", 128))
    d["chload"] = [bool(x) for x in g("CHLOAD", 8)]
    d["cursor"] = w("CURSTATE")
    d["userput"] = w("USERPUT")
    d["main_h"] = b("MAINH")
    d["vmover"] = b("VMOVER")
    n = b("SENTN")
    sb = g("SENT", 42)
    d["sentence"] = [(sb[7 * i], st.unpack("<h", sb[7 * i + 1:7 * i + 3])[0], st.unpack("<h", sb[7 * i + 3:7 * i + 5])[0],
                      bool(sb[7 * i + 5]), sb[7 * i + 6]) for i in range(n)]
    d["follows"] = b("FOLLOWS")
    d["talk_colors"] = [r[188] for r in nx.actor_recs()]
    page = nx.page(UIP)
    sy = nx.s

    def off(name):
        return sy[name] - 0xE000
    verbs = []
    for k in range(100):
        v = page[VSZ * k:VSZ * k + VSZ]
        verbs.append((v[0], st.unpack("<hhhh", v[1:9]), st.unpack("<hhhh", v[9:17]) if v[17] else None,
                      tuple(v[18:22]), v[22], v[23], v[24], v[25], v[26], v[27], st.unpack("<h", v[28:30])[0],
                      (v[30], st.unpack("<H", v[31:33])[0]) if v[34] else None, bool(v[33])))
    d["verbs"] = verbs
    inv = st.unpack("<80H", page[off("INVOBJ"):off("INVOBJ") + 160])
    d["inventory"] = list(inv)
    nn = st.unpack("<150H", page[off("NNOBJ"):off("NNOBJ") + 300])
    d["new_names_obj"] = list(nn)
    if full:
        an = page[off("ANAMES"):off("ANAMES") + 416]
        d["actor_names"] = [cstr(an[32 * i:32 * i + 32]) for i in range(13)]
        heap = nx.page(HEAPP)

        def hp(table, i, size=None):
            o = st.unpack("<H", page[off(table) + 2 * i:off(table) + 2 * i + 2])[0]
            if not o:
                return None
            if size is None:
                size = st.unpack("<H", heap[o - 2:o])[0]
            return bytes(heap[o:o + size])
        d["verb_names"] = [cstr(hp("HP_VERB", k) or b"") if verbs[k][-1] else None
                           for k in range(100)]
        sz = g("STRSZ", 50)
        d["strings_res"] = {i: hp("HP_STR", i, sz[i]) or b"" for i in range(50) if sz[i]}
        d["new_names"] = [cstr(hp("HP_NN", i) or b"") if nn[i] else None for i in range(150)]
    return d


def model_ui(w, full=False):
    ui = w.ui
    d = {}
    d["have_msg"] = ui.have_msg
    d["talk_delay"] = ui.talk_delay
    d["keep_text"] = bool(ui.keep_text)
    d["charset_color"] = ui.charset_color & 0xFF
    d["buf_pos"] = ui.buf_pos & 0xFF
    d["next"] = (ui.next_left, ui.next_top)
    buf = bytes(ui.buf)
    d["buf"] = buf[:buf.index(0)] if 0 in buf else buf
    d["has_mask"] = bool(ui.has_mask)
    d["mask_screen"] = ui.mask_screen
    d["mask_rect"] = tuple(ui.mask_rect) if ui.mask_rect is not None else None
    d["verb_rect"] = tuple(ui.verb_rect) if ui.verb_rect is not None else None

    def slot(x):
        return (x.xpos, x.ypos, x.right, x.color & 0xFF, x.charset & 0xFF, int(bool(x.center)),
                int(bool(x.overhead)), int(bool(x.no_talk_anim)))
    d["strings"] = [(slot(t.cur), slot(t.default)) for t in ui.strings]
    d["cmap"] = [c & 0xFF for c in ui.cmap]
    d["chdata"] = bytes(c & 0xFF for row in ui.charset_data for c in row)
    d["chload"] = list(ui.charset_loaded)
    d["cursor"] = ui.cursor_state
    d["userput"] = ui.userput
    d["main_h"] = ui.main_h
    d["vmover"] = ui.verb_mouse_over
    d["sentence"] = [(v & 0xFF, a, b, bool(p), f) for v, a, b, p, f in ui.sentence]
    d["follows"] = w.follows
    d["talk_colors"] = [w.vm.actors[i].talk_color & 0xFF for i in range(1, 13)]
    verbs = []
    for v in ui.verbs:
        verbs.append((v.verbid & 0xFF, (v.left, v.top, v.right, v.bottom), tuple(v.old) if v.old is not None else None,
                      (v.color & 0xFF, v.hicolor & 0xFF, v.dimcolor & 0xFF, v.bkcolor & 0xFF), v.type,
                      v.charset & 0xFF, v.curmode, v.saveid & 0xFF, v.key & 0xFF, v.center, v.imgindex,
                      (v.image[0] & 0xFF, v.image[1] & 0xFFFF) if v.image is not None else None, v.name is not None))
    d["verbs"] = verbs
    d["inventory"] = list(ui.inventory)
    d["new_names_obj"] = list(ui.new_names)
    if full:
        d["actor_names"] = [cstr(bytes(ui.actor_names.get(i, b""))[:31]) for i in range(13)]
        d["verb_names"] = [cstr(v.name) if v.name is not None else None for v in ui.verbs]
        d["strings_res"] = {i: bytes(v) for i, v in ui.string_res.items() if i < 50}
        d["new_names"] = [cstr(ui.new_name_res[i]) if ui.new_names[i] else None
                          for i in range(150)]
    return d


def compare_ui(nx, w, full=False, show_text=True):
    """Diferencias de la interfaz (sin textos si show_text es False)."""
    z = z80_ui(nx, full)
    m = model_ui(w, full)
    errs = []
    for k in m:
        a, b = z[k], m[k]
        if a == b:
            continue
        if isinstance(b, list) and isinstance(a, list) and len(a) == len(b):
            i = next(i for i in range(len(b)) if a[i] != b[i])
            if k in ("verb_names", "new_names", "actor_names") and not show_text:
                errs.append("%s[%d] distinto" % (k, i))
            else:
                errs.append("%s[%d]: Z80 %s, modelo %s" % (k, i, a[i], b[i]))
        elif k in ("buf", "strings_res") and not show_text:
            errs.append("%s distinto" % k)
        else:
            errs.append("%s: Z80 %s, modelo %s" % (k, a, b))
    return errs


def boot_world(g, cost):
    """El modelo con el arranque: sin habitacion y el script 1."""
    w = make_world(g, cost, 0)
    w.vm.run_script(1, args=[0])
    return w


# Lo que se hace en la prueba de la interfaz: (paso, accion). Las posiciones salen
# del modelo en ese momento (el Z80 recibe lo mismo).
IFACE_PLAN = [
    (6, ("hover", 160, 100)),
    (20, ("key", 27)),                  # ESC: se salta la escena del principio
    (30, ("hover_obj", 101)),           # el farol: la linea de frase
    (34, ("verb", 3)),                  # Mirar
    (37, ("obj", 101)),                 # ... el farol: va hasta el, texto con espera y saltos de linea
    #                                     (y parpadea con el texto encima: paso 75)
    (110, ("key", 46)),                 # '.': corta el texto
    (120, ("xy", 10, 130)),             # andar hacia la izquierda (la camara le sigue)
    (150, ("xy", 10, 130)),
    (185, ("verb", 1)),                 # Abrir la puerta
    (188, ("obj", 100)),
    (225, ("xy", 300, 130)),            # andar hacia la derecha
    (260, ("key", ord("g"))),           # Coger (con su tecla)
    (263, ("obj", 106)),                # la moneda: al inventario, con su icono y nombre nuevo
    (300, ("hover_inv", 1)),            # el icono de la moneda
    (304, ("verb", 3)),
    (307, ("inv", 1)),                  # Mirar la moneda (en el inventario)
    (350, ("verb", 6)),                 # Hablar con el sol: habla la tortuga (sin borrar)
    (353, ("obj", 104)),
    (430, ("verb", 3)),                 # Mirar el sol: texto de sistema arriba
    (433, ("obj", 104)),
    (470, ("xy", 100, 130)),            # andar
    (500, ("verb", 5)),                 # Usar ... con
    (503, ("inv", 0)),
    (506, ("obj", 101)),
    (550, ("room", 2)),                 # el almacen: drawBox en los verbos
    (580, ("verb", 1)),
    (583, ("obj", 105)),
    (630, ("room", 3)),                 # el camino: guarda los verbos
    (690, ("room", 1)),                 # y al salir, vuelven
    (712, ("key", ord("R"))),           # R: el juego desde el principio (systemOps 1)
]
IFACE_SCREENS = (0, 10, 25, 40, 60, 75, 140, 175, 200, 204, 206, 230, 262, 320, 370, 440, 480, 520, 550,
                 560, 600, 630, 650, 671, 690, 710)
IFACE_STEPS = 730


def resolve(w, act):
    """(raton, boton, tecla, habitacion) de una accion del plan."""
    k = act[0]
    left = w.cam_left() if w.room else 0
    if k == "key":
        return None, 0, act[1], None
    if k == "room":
        return None, 0, 0, act[1]
    if k in ("hover", "xy"):
        return (act[1], act[2]), (1 if k == "xy" else 0), 0, None
    if k in ("hover_obj", "obj"):
        for o in w.eng.objs:
            if o.id == act[1]:
                # un punto que se vea y en el que findObject de este objeto (los de
                # delante tapan), lo mas cerca posible del centro de lo que se ve
                x0, x1 = max(o.x * 8, left), min((o.x + o.w) * 8, left + 320)
                y0, y1 = o.y, min(o.y + o.h, w.ui.main_h)
                cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
                pts = sorted(((x, y) for x in range(x0, x1) for y in range(y0, y1)),
                             key=lambda p: (abs(p[0] - cx) + abs(p[1] - cy), p))
                for x, y in pts:
                    if w.find_object(x, y) == o.id:
                        return (x - left, y), (1 if k == "obj" else 0), 0, None
                raise ValueError("%s: el objeto no se ve (camara en %d)" % (act, left))
        raise KeyError(act)
    if k == "verb":
        for v in w.ui.verbs:
            if v.verbid == act[1] and v.curmode == 1:
                return (v.left + 3, v.top + 3), 1, 0, None
        raise KeyError(act)
    if k in ("inv", "hover_inv"):
        v = next(v for v in w.ui.verbs if v.verbid == 200 + act[1])
        return (v.left + 8, v.top + 8), (1 if k == "inv" else 0), 0, None
    raise ValueError(act)


def cmd_interfaz(steps=IFACE_STEPS, screens=IFACE_SCREENS):
    """El juego de prueba desde el arranque: verbos, frases, textos, inventario,
    teclas y cambios de habitacion; cada paso == modelo y la pantalla en unos cuantos."""
    g = game()
    w = boot_world(g, g.costume(1))
    nx = Next()
    nx.boot()
    bad = 0
    errs = compare_vm(nx, w, "arranque") + compare_ui(nx, w, full=True)
    if errs:
        print("al arrancar:", errs[:6])
        bad += 1
    plan = dict(IFACE_PLAN)
    mouse = (160, 100)
    for t in range(steps):
        button = key = 0
        if t in plan:
            m, button, key, room = resolve(w, plan[t])
            if room:
                w.enter_with_ego(room)
                nx.enter_ego(room)
            if m is not None:
                mouse = m
        fr = w.tick(mouse=mouse, button=button, key=key)
        nx.step(mouse=mouse, button=button, key=key)
        e = []
        if w.room and not compare_tick(nx, w.eng, fr, t, quiet=True):
            e.append("(motor)")
        if t in screens and not world_screen(nx, w, fr, "interfaz", t):
            e.append("(pantalla)")
        e += compare_ui(nx, w, full=(t in screens))
        e += compare_vm(nx, w, "interfaz")
        if e:
            print("paso %d:" % t)
            for x in e[:6]:
                print("   ", x)
            bad += 1
            if bad > 3:
                break
    print("interfaz: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


def fixture_world(room):
    g = game()
    return make_world(g, g.costume(1), room)


def cmd_scripts():
    nx = Next()
    bad = 0
    w = fixture_world(1)
    nx.reset_vm(1)
    errs = compare_vm(nx, w, "al entrar")
    if errs:
        print("al entrar en el patio:", errs[:6])
        bad += 1
    bad += run_world(nx, w, 90, "patio", clicks={20: (500, 125), 60: (100, 130)},
                     screens=(0, 10, 30, 45, 89))
    bad += run_world(nx, w, 40, "almacen", room_changes={0: 2}, screens=(0, 39))
    bad += run_world(nx, w, 70, "camino", room_changes={0: 3}, screens=(0, 1, 5, 20, 41, 69))
    print("scripts: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


def cmd_pseudo():
    """pseudoRoom (el arranque del juego de prueba hace del almacen la 201) y
    roomScroll fuera del ancho: del patio a la 201 y vuelta; cada paso == modelo."""
    g = game()
    w = boot_world(g, g.costume(1))
    nx = Next()
    nx.boot()
    bad = 0
    for t in range(40):
        k = 27 if t == 20 else 0            # (ESC: la escena del principio)
        w.tick(mouse=(160, 100), key=k)
        nx.step(mouse=(160, 100), key=k)
    errs = compare_vm(nx, w, "pseudo") + compare_ui(nx, w, full=True)
    if errs:
        print("al arrancar:", errs[:6])
        bad += 1
    bad += run_world(nx, w, 40, "pseudo", room_changes={0: 201}, screens=(0, 39), ui=True)
    V = w.V
    got = (w.vm.vars[V.VAR_ROOM], w.vm.vars[V.VAR_ROOM_RESOURCE], w.vm.vars[V.VAR_CAMERA_MIN_X],
           w.vm.vars[V.VAR_CAMERA_MAX_X])
    if got != (201, 2, 160, 160):
        print("en la 201 (habitacion, la de verdad, camara min y max): %s" % (got,))
        bad += 1
    bad += run_world(nx, w, 30, "patio", room_changes={0: 1}, screens=(29,), ui=True)
    print("pseudo: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


def cmd_actores():
    """Todos los actores de la habitacion en sprites: la tortuga (actor 2, costume 2,
    que se carga en la cache detras del patio) pasa por delante del protagonista y
    despues por detras, tapada por las columnas; la medusa (actor 3, de 32 colores,
    con escala y elevacion) por el camino, con el protagonista al fondo, hasta que
    un script se va al almacen; y otra vez el patio (la cache de costumes se vacia
    al cambiar de habitacion y la tortuga se vuelve a cargar). En el patio, otra
    tortuga (actor 4, script 18) usa todo lo de los actores: actorOps, animateActor,
    faceActor, andar hasta otro actor y hasta un objeto, sin cajas, con escala y
    plano Z fijos, hablar, lo que preguntan los scripts (getActor*, getDist,
    actorFromPos...) y, hacia el paso 205, su sonido (actorOps 3): cabecea con una
    animacion que pasa por $78 y playActorSounds pone la campana tres veces.
    Cada paso == modelo y la pantalla cada pocos pasos."""
    nx = Next()
    bad = 0
    w = fixture_world(1)
    nx.reset_vm(1)
    errs = compare_vm(nx, w, "al entrar")
    if errs:
        print("al entrar en el patio:", errs[:6])
        bad += 1
    bad += run_world(nx, w, 230, "actores_patio", clicks={0: (230, 126), 70: (150, 130)},
                     screens=range(0, 230, 4))
    if (w.vm.vars[151], w.vm.vars[152]) != (1, 3):
        print("actores: el script 18 no ha acabado con la campana del actor 4 (vars 151, 152 = %d, %d)"
              % (w.vm.vars[151], w.vm.vars[152]))
        bad += 1
    bad += run_world(nx, w, 80, "actores_camino", room_changes={0: 3}, screens=range(0, 80, 3))
    bad += run_world(nx, w, 30, "actores_vuelta", room_changes={0: 1}, screens=range(0, 30, 3))
    n2 = sum(1 for a in range(1, 13) if w.vm.in_room(a))
    print("actores: %s (%d actores en el patio al final)" % ("igual que el modelo" if not bad else "con diferencias", n2))
    nx.close()
    return bad == 0


def shift_attrs(attrs, delta):
    """Los atributos de los sprites con la x movida delta (los que se ven)."""
    out = bytearray(attrs)
    for k in range(0, len(out), 5):
        if out[k + 3] & 0x80:
            x = ((out[k] | (out[k + 2] & 1) << 8) + delta) & 0x1FF
            out[k] = x & 0xFF
            out[k + 2] = (out[k + 2] & 0xFE) | x >> 8
    return bytes(out)


def cmd_saltos(steps=240):
    """Pasos sin pintar los actores (SKIPDRAW, lo que hace el bucle principal cuando va
    con retraso): en el patio, con la camara moviendose, se pinta uno de cada tres.
    Cada paso, la maquina virtual (con las fichas de los actores: escala, tiras y lo
    que ocupan) == modelo; en los que no se pinta, los sprites son los de antes
    movidos con la camara; en los que se pinta, == modelo."""
    nx = Next()
    w = fixture_world(1)
    nx.reset_vm(1)
    bad = 0
    prev = None                     # (atributos, left) del ultimo pintado
    clicks = {0: (600, 130), 60: (40, 126), 120: (560, 120), 180: (150, 130)}
    for t in range(steps):
        skip = t % 3 != 0 and prev is not None
        nx.w8("SKIPDRAW", int(skip))
        fr = w.tick(click=clicks.get(t), mouse=(160, 100))
        nx.step(clicks.get(t), mouse=(160, 100))
        errs = []
        left = w.cam_left()
        if skip:
            want = shift_attrs(prev[0], prev[1] - left)
            got = nx.frame()[2]
            if got != want:
                errs.append("sprites sin pintar: no son los de antes movidos %d" % (prev[1] - left))
            zc, mc = nx.camera(), w.eng.cam.pack()
            if zc != mc:
                errs.append("camara: Z80 %s / modelo %s" % (zc.hex(), mc.hex()))
            prev = (want, left)
        else:
            if not compare_tick(nx, w.eng, fr, t, quiet=True):
                errs.append("(motor)")
            prev = (bytes(fr.attrs), left)
        errs += compare_vm(nx, w, "saltos")     # (despues: las clases pasan por SPRBUF)
        if errs:
            print("paso %d%s:" % (t, " (sin pintar)" if skip else ""))
            for e in errs[:6]:
                print("   ", e)
            bad += 1
            if bad > 3:
                break
    nx.w8("SKIPDRAW", 0)
    nx.close()
    print("saltos: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    return bad == 0


def cmd_juego(rooms):
    """Tu juego convertido en build/sd: clics al azar en cada habitacion,
    comparando solo numeros (actor, camara, tiles y atributos)."""
    g, _ = C.find_game(ORIGINAL)
    hdr = open(os.path.join(SD_JUEGO, "GAME.DAT"), "rb").read()
    costume = hdr[5]
    cost = g.costume(costume)
    rooms = rooms or list(hdr[7:7 + hdr[6]])
    rng = random.Random(3)
    nx = Next(sd=SD_JUEGO)
    bad = 0
    for room in rooms:
        rd = C.RoomData(g.room(room), g.index)
        clicks = []
        t = 0
        while t < 60:
            clicks.append((t, rng.randint(-20, rd.width + 20), rng.randint(-10, rd.height + 10)))
            t += rng.randint(1, 25)
        b = run_script(nx, room, clicks, 60, g, costume)
        # objetos: unos cuantos a estado 1, y las tiras que tocan == modelo
        eng = M.Engine(rd, g.costume(costume))
        nx.load_room(room)
        cand = [k for k, o in enumerate(eng.objs) if any(im is not None for im in o.images)]
        rng.shuffle(cand)
        touched = set()
        for k in cand[:6]:
            o = eng.objs[k]
            eng.set_state(k, 1)
            nx.set_state(k, 1)
            touched.update(range(o.x, o.x + o.w))
        rec = (8 + len(rd.zplanes)) * rd.height
        # (como compare_strips: las que cambiaron fuera de la vista se quedan atrasadas,
        # STALE, y se rehacen al entrar en ella; ninguna puede estar a la vista)
        stale = nx.read("STALE", 16)
        ss = nx.r8("CAM_SS")
        sb = [s_ for s_ in sorted(touched)
              if (ss <= s_ < ss + 40 if stale[s_ >> 3] & (1 << (s_ & 7))
                  else nx.strip(s_, rec) != expected_strip(eng, s_))]
        print("habitacion %3d (%4dx%3d, %2d cajas, %2d objetos): andar %s, objetos %s" % (
            room, rd.width, rd.height, len(rd.boxes), len(eng.objs),
            "igual" if not b else "%d pasos distintos" % b,
            ("igual (%d tiras)" % len(touched)) if not sb else "tiras distintas %s" % sb[:8]))
        bad += b + bool(sb)
        # scripts: la maquina virtual desde cero, entrando aqui; paso a paso == modelo
        w = make_world(g, cost, room)
        nx.reset_vm(room)
        e0 = compare_vm(nx, w, "entrada")
        on0 = sum(1 for o in w.eng.objs if w.vm.get_state(o.id)) if w.room else 0
        ex0 = w.vm.executed
        vclicks = {}
        t = 0
        while t < 60:
            t += rng.randint(5, 30)
            vclicks[t] = (rng.randint(0, rd.width), rng.randint(0, rd.height))
        vb = bool(e0) + run_world(nx, w, 60, "habitacion %d" % room, vclicks, quiet=True)
        live = sum(1 for sl in w.vm.slots if sl.status)
        on = sum(1 for o in w.eng.objs if w.vm.get_state(o.id)) if w.room else 0
        print("    scripts: %s; %d instrucciones al entrar, %d despues; %d ranuras vivas; "
              "objetos con estado: %d al entrar, %d al final; habitacion al final %d" % (
                  "igual" if not vb else "distinto", ex0, w.vm.executed - ex0, live, on0, on, w.room))
        bad += vb
    print("%d habitaciones: %s" % (len(rooms), "igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


# send-keys-event de ZEsarUX: las letras, cifras y signos en ASCII; estas, aparte
ZK_SPACE, ZK_ENTER, ZK_CAPS, ZK_SYM = 128, 129, 133, 136


def cmd_teclas(port=None):
    """El juego de prueba en modo normal: ESC (CAPS + SPACE) salta la escena del
    principio, la tecla de un verbo y ENTER sobre otro lo eligen, CAPS + 7 sube el
    cursor. Mira las variables del juego (no hay modelo: el tiempo es el real)."""
    from zrcp import PORT
    import fixture_ui as F
    z = Zrcp(port=port or PORT)
    sy = symbols()
    z.cmd("hard-reset-cpu")
    time.sleep(0.5)
    z.load(os.path.join(SD, "scumm.nex"))

    def var(n):
        return struct.unpack("<h", z.read(sy["VARS"] + 2 * n, 2))[0]

    def r16(name):
        return struct.unpack("<h", z.read(sy[name], 2))[0]

    def w16(name, v):
        z.write(sy[name], (v & 0xFFFF).to_bytes(2, "little"))

    def until(cond, timeout=6.0):
        t0 = time.time()
        while time.time() - t0 < timeout:
            if cond():
                return True
            time.sleep(0.05)
        return False

    def press(*codes, hold=0.15):
        for c in codes:
            z.key(c, True)
        time.sleep(hold)
        for c in reversed(codes):
            z.key(c, False)

    bad = 0

    def check(what, ok):
        nonlocal bad
        print("    %-44s %s" % (what, "bien" if ok else "MAL"))
        bad += not ok
    until(lambda: var(47) >= 45, 30)            # VAR_TIMER_TOTAL: ya va por la escena del arranque
    #                                             (su override se pone en el paso 8; antes, ESC no hace nada)
    check("en la escena del principio (sin control)", var(F.V_VERB) == F.WALK and r16("USERPUT") <= 0)
    press(ZK_CAPS, ZK_SPACE)
    check("CAPS + SPACE (ESC): cursor y control", until(lambda: r16("USERPUT") > 0))
    press(ord("g"))
    check("tecla g: Coger", until(lambda: var(F.V_VERB) == F.TAKE))
    _, _, x, y, _ = next(v for v in F.VERB_LIST if v[0] == F.LOOK)
    w16("CURX", x + 3)
    w16("CURY", M.ROOM_Y0 + y + 3)
    time.sleep(0.1)
    press(ZK_ENTER)
    check("ENTER sobre Mirar", until(lambda: var(F.V_VERB) == F.LOOK))
    y0 = r16("CURY")
    press(ZK_CAPS, ord("7"), hold=0.6)
    check("CAPS + 7: el cursor sube", r16("CURY") < y0 - 10)
    time.sleep(0.5)
    check("(y CAPS + 7 no es una tecla)", var(F.V_VERB) == F.LOOK)
    print("teclas: %s" % ("bien" if not bad else "con fallos"))
    z.close()
    return bad == 0


def cmd_guardar():
    """Guardar y cargar con el juego de prueba: el plan de la prueba interfaz hasta
    el paso 300, guardar (hueco 1), 60 pasos mas, cargar: todo (maquina virtual,
    interfaz, pantalla) == modelo; seguir el plan con todo comparado; guardar en el
    almacen (hueco 2) y cargar la del patio (hueco 1) desde alli."""
    g = game()
    w = boot_world(g, g.costume(1))
    nx = Next()
    nx.boot()
    plan = dict(IFACE_PLAN)
    st = {"mouse": (160, 100)}
    bad = 0

    def step(t, check=False):
        nonlocal bad
        button = key = 0
        if t in plan:
            m, button, key, room = resolve(w, plan[t])
            if room:
                w.enter_with_ego(room)
                nx.enter_ego(room)
            if m is not None:
                st["mouse"] = m
        fr = w.tick(mouse=st["mouse"], button=button, key=key)
        nx.step(mouse=st["mouse"], button=button, key=key)
        if check:
            e = []
            if w.room and not compare_tick(nx, w.eng, fr, t, quiet=True):
                e.append("(motor)")
            e += compare_ui(nx, w) + compare_vm(nx, w, "guardar")
            if e:
                print("paso %d:" % t, e[:5])
                bad += 1
        return fr

    def check_all(label):
        nonlocal bad
        e = compare_vm(nx, w, label) + compare_ui(nx, w, full=True)
        if not world_screen(nx, w, None, label, 0):
            e.append("(pantalla)")
        print("%s: %s" % (label, "igual que el modelo" if not e else e[:6]))
        bad += bool(e)

    for t in range(301):
        step(t)
    r = nx.save(1)
    snap1 = w.snapshot()
    print("guardar en el paso 300: %s" % ("bien" if r == 0 else "FALLA"))
    bad += r != 0
    for t in range(301, 361):
        step(t)
    r = nx.load(1)
    w.load_state(snap1)
    print("cargar: %s" % ("bien" if r == 0 else "FALLA"))
    bad += r != 0
    check_all("despues de cargar")
    for t in range(301, IFACE_STEPS):
        step(t, check=True)
        if t == 560:
            r = nx.save(2)
            w.snapshot()
            print("guardar en el almacen (paso 560): %s" % ("bien" if r == 0 else "FALLA"))
            bad += r != 0
            r = nx.load(1)
            w.load_state(snap1)
            print("cargar la del patio desde el almacen: %s" % ("bien" if r == 0 else "FALLA"))
            bad += r != 0
            check_all("despues de cargar la del patio")
            break
    for t in range(301, 400):
        step(t, check=True)
    r = nx.load(7)
    print("cargar un hueco vacio (7): %s" % ("falla, como debe" if r else "NO FALLA"))
    bad += r == 0
    print("guardar: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


SOUND_EXPECT = [1, 1, 1, 0, 5, 0, 0, 0, 120, 1, 0, 5, 1, 1, 1, 4, 1, 0, 1]   # variables 230-248


def cmd_sonido():
    """El sonido con el juego de prueba (lo que ven los scripts: tools/sound.py): el
    plan de la interfaz hasta el paso 300; la tecla M arranca el script 27, que pone
    efectos y pistas del CD, mira isSoundRunning y VAR_MUSIC_TIMER y para unos y
    otros; cada paso, todo == modelo, y al acabar, las variables 230-246 como deben.
    Despues, otra vez, guardando con una pista sonando y cargando."""
    g = game()
    w = boot_world(g, g.costume(1))
    nx = Next()
    nx.boot()
    plan = dict(IFACE_PLAN)
    st = {"mouse": (160, 100)}
    bad = 0

    def step(t, key=0, check=True):
        nonlocal bad
        button = 0
        if t in plan:
            m, button, key2, room = resolve(w, plan[t])
            key = key or key2
            if room:
                w.enter_with_ego(room)
                nx.enter_ego(room)
            if m is not None:
                st["mouse"] = m
        fr = w.tick(mouse=st["mouse"], button=button, key=key)
        nx.step(mouse=st["mouse"], button=button, key=key)
        if check:
            e = []
            if w.room and not compare_tick(nx, w.eng, fr, t, quiet=True):
                e.append("(motor)")
            e += compare_ui(nx, w) + compare_vm(nx, w, "sonido")
            if e:
                print("paso %d:" % t, e[:5])
                bad += 1
        return w.vm.vars[246]

    for t in range(301):
        step(t, check=(t % 25 == 0))
    w.vm.vars[246] = 0
    nx.z.write(nx.s["VARS"] + 2 * 246, bytes(2))
    t = 301
    step(t, key=ord("M"))
    while t < 400 and not w.vm.vars[246]:
        t += 1
        step(t)
    got = [w.vm.vars[i] for i in range(230, 249)]
    print("prueba de sonido (pasos 301-%d): %s" % (t, "como debe" if got == SOUND_EXPECT else got))
    bad += got != SOUND_EXPECT
    w.vm.vars[246] = 0
    nx.z.write(nx.s["VARS"] + 2 * 246, bytes(2))
    t += 2
    step(t, key=ord("M"))
    snap = None
    for k in range(80):
        t += 1
        step(t)
        if k == 8:                          # con la pista del CD sonando
            snap = w.snapshot()
            r = nx.save(4)
            print("guardar con la pista sonando: %s" % ("bien" if r == 0 else "FALLA"))
            bad += r != 0
        elif k == 14:
            w.load_state(snap)
            r = nx.load(4)
            print("cargar: %s" % ("bien" if r == 0 else "FALLA"))
            bad += r != 0
            e = compare_vm(nx, w, "cargar") + compare_ui(nx, w, full=True)
            if e:
                print("despues de cargar:", e[:5])
                bad += 1
        if w.vm.vars[246]:
            break
    print("sonido: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


def random_action(w, rng):
    """Una accion al azar con lo que hay ahora en el modelo: (raton, boton, tecla,
    pasos hasta la siguiente). Tras un clic en la escena se espera mas (para llegar)."""
    ui = w.ui
    left = w.cam_left() if w.room else 0
    r = rng.random()
    verbs = [v for v in ui.verbs if v.verbid and v.curmode == 1 and v.right > v.left]
    if r < 0.3 and verbs:
        v = rng.choice(verbs)
        return ((v.left + v.right) // 2, (v.top + v.bottom) // 2), 1, 0, rng.randint(2, 12)
    objs = []
    if w.room:
        for o in w.eng.objs:
            x = o.x * 8 + o.w * 4 - left
            y = o.y + o.h // 2
            if 0 <= x < 320 and 0 <= y < ui.main_h and o.w and o.h:
                objs.append((x, y))
    if r < 0.7 and objs:
        return rng.choice(objs), rng.choice((0, 1, 1, 1)), 0, rng.randint(10, 70)
    if r < 0.93:
        return ((rng.randint(0, 319), rng.randint(0, max(ui.main_h - 1, 0))), rng.choice((0, 1, 1)), 0,
                rng.randint(5, 50))
    if r < 0.97:
        return None, 0, 27, rng.randint(2, 20)          # ESC
    return None, 0, 46, rng.randint(2, 20)              # '.'


def cmd_arranque(steps=600, seed=1, tour=None, per_room=60, save_every=0):
    """Tu juego desde el script 1: ESC en la intro y luego acciones al azar; cada paso,
    la maquina virtual, el motor y la interfaz == modelo (solo numeros). tour: despues,
    el protagonista a cada una de esas habitaciones (con lo que ya hizo el arranque) y
    per_room pasos de acciones al azar en cada una. save_every: cada tantas
    habitaciones, guardar a los 20 pasos (hueco 3), 25 pasos mas, cargar y comparar."""
    g, _ = C.find_game(ORIGINAL)
    hdr = open(os.path.join(SD_JUEGO, "GAME.DAT"), "rb").read()
    w = boot_world(g, g.costume(hdr[5]))
    nx = Next(sd=SD_JUEGO)
    nx.boot()
    bad = 0
    errs = compare_vm(nx, w, "arranque") + compare_ui(nx, w, full=True, show_text=False)
    if errs:
        print("al arrancar:", errs[:6])
        bad += 1
    rng = random.Random(seed)
    st = dict(mouse=(160, 100), nxt=0)
    rooms = []
    t0 = time.time()

    def step(t, key=0, first_action=90):
        nonlocal bad
        button = 0
        if not key and t >= first_action and t >= st["nxt"]:
            m, button, key, gap = random_action(w, rng)
            if m is not None:
                st["mouse"] = m
            st["nxt"] = t + gap
        fr = w.tick(mouse=st["mouse"], button=button, key=key)
        nx.step(mouse=st["mouse"], button=button, key=key)
        if not rooms or rooms[-1] != w.room:
            rooms.append(w.room)
        e = []
        if w.room and not compare_tick(nx, w.eng, fr, t, quiet=True):
            e.append("(motor)")
        e += compare_ui(nx, w, full=(t % 50 == 49), show_text=False)
        e += compare_vm(nx, w, "arranque")
        if e:
            print("paso %d (habitacion %d):" % (t, w.room))
            for x in e[:6]:
                print("   ", x)
            if not bad:
                print("    ficheros abiertos en el Z80:", nx.z.cmd("esxdoshandler-get-open-files")[:300])
            bad += 1
        return bad <= 3

    for t in range(steps):
        if not step(t, key=27 if t in (39, 79) else 0):  # la intro, como en el juego: ESC
            break
        if t % 100 == 99:
            print("    paso %d: habitacion %d, %d objetos en el inventario (%.0fs)" % (
                t, w.room, sum(1 for x in w.ui.inventory if x), time.time() - t0))
    t = steps
    for ri, room in enumerate((tour or []) if bad <= 3 else []):
        w.enter_with_ego(room)
        nx.enter_ego(room)
        st["nxt"] = t + 5
        b0 = bad
        snap = None
        for k in range(per_room):
            ok = step(t, first_action=0)
            t += 1
            if not ok:
                break
            if save_every and ri % save_every == 0:
                if k == 20:
                    snap = w.snapshot()
                    if nx.save(3):
                        print("    habitacion %d: no se ha podido guardar" % room)
                        bad += 1
                elif k == 45 and snap is not None:
                    w.load_state(snap)
                    if nx.load(3):
                        print("    habitacion %d: no se ha podido cargar" % room)
                        bad += 1
                    e = compare_vm(nx, w, "cargar") + compare_ui(nx, w, full=True, show_text=False)
                    if e:
                        print("    habitacion %d, despues de cargar:" % room, e[:5])
                        bad += 1
        print("    habitacion %3d: %s (%.0fs)" % (room, "igual" if bad == b0 else "distinta", time.time() - t0))
        if bad > 3:
            break
    print("habitaciones: %s" % rooms)
    print("arranque: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


def cmd_partida(nombre, cada=10, hasta=None, desde=0):
    """Las entradas (raton, boton, tecla) de cada paso de una partida jugada en el modelo
    con tools/partida.py, otra vez desde el arranque en el modelo y en el Z80: maquina
    virtual (y motor e interfaz de vez en cuando) == modelo; al final, el modelo repetido
    == la partida guardada (que lo jugado no dependa de las copias ni de lo guardado)."""
    import partida as PA
    j = PA.cargar(nombre)
    entradas = j.inputs[:hasta] if hasta else j.inputs
    g, _ = C.find_game(ORIGINAL)
    hdr = open(os.path.join(SD_JUEGO, "GAME.DAT"), "rb").read()
    w = boot_world(g, g.costume(hdr[5]))
    nx = Next(sd=SD_JUEGO)
    nx.boot()
    bad = 0
    errs = compare_vm(nx, w, "partida") + compare_ui(nx, w, full=True, show_text=False)
    if errs:
        print("al arrancar:", errs[:6])
        bad += 1
    print("%s: %d pasos" % (nombre, len(entradas)))
    sys.stdout.flush()
    t0 = time.time()
    sala = w.room
    rooms = [w.room]
    for t, (mouse, button, key) in enumerate(entradas):
        fr = w.tick(mouse=mouse, button=button, key=key)
        nx.step(mouse=mouse, button=button, key=key)
        cambio = w.room != sala
        if cambio:
            sala = w.room
            rooms.append(w.room)
        if t < desde or not (cambio or t % cada == cada - 1 or t == len(entradas) - 1):
            continue
        e = []
        if w.room and (cambio or t % 100 == 99) and not compare_tick(nx, w.eng, fr, t, quiet=True):
            e.append("(motor)")
        e += compare_ui(nx, w, full=(t % 500 == 499), show_text=False)
        e += compare_vm(nx, w, "partida")
        if e:
            print("paso %d (habitacion %d):" % (t, w.room))
            for x in e[:6]:
                print("   ", x)
            sys.stdout.flush()
            bad += 1
            if bad > 3:
                break
        if t % 2000 == 1999:
            print("    paso %d: habitacion %d (%.0fs)" % (t, w.room, time.time() - t0))
            sys.stdout.flush()
    print("habitaciones: %s" % rooms)
    if not hasta and bad <= 3:
        a, b = model_vm_state(w), model_vm_state(j.w)
        dif = [k for k in a if a[k] != b[k]]
        print("modelo repetido == partida guardada: %s" % ("si" if not dif else "no (%s)" % dif))
        if dif:
            bad += 1
    print("partida: %s" % ("igual que el modelo" if not bad else "con diferencias"))
    nx.close()
    return bad == 0


def cmd_juegos(port=None):
    """El menu de juegos en modo normal: una tarjeta (build/menu_sd) con el juego de
    prueba suelto junto al .nex y dos copias en carpetas (AAA "Prueba zeta", ZZZ
    "Prueba alfa"). La lista, por nombre; con 3 y ENTER, el de AAA; desde el menu de
    partidas, J y ESC no cambia nada; J, el raton encima del primero y ENTER, el de
    aqui (y sus partidas se guardan aqui, con el nombre que se escribe: G, letras y
    ENTER; G con el que tenia, CAPS + 0 y otra letra; G, una letra y ESC no guarda);
    J, 2 y ENTER, el de ZZZ."""
    import shutil
    from zrcp import PORT
    card = os.path.join(ROOT, "build", "menu_sd")
    if os.path.isdir(card):
        shutil.rmtree(card)
    os.makedirs(card)
    for d, title in (("", None), ("AAA", "Prueba zeta"), ("ZZZ", "Prueba alfa")):
        dst = os.path.join(card, d)
        os.makedirs(dst, exist_ok=True)
        for f in os.listdir(SD):
            if f.endswith(".DAT") and not f.startswith("SAVE"):
                shutil.copy(os.path.join(SD, f), dst)
        if title:
            with open(os.path.join(dst, "TITULO.TXT"), "wb") as fh:
                fh.write(title.encode("latin-1") + bytes((13, 10)))
    shutil.copy(os.path.join(SD, "scumm.nex"), card)
    z = Zrcp(port=port or PORT)
    sy = symbols()
    z.cmd("hard-reset-cpu")
    time.sleep(0.5)
    z.load(os.path.join(card, "scumm.nex"))
    ovs = lambda name, n: z.read_phys(OVS_PAGE * 0x2000 + sy[name] - 0xC000, n)
    r8 = lambda name: z.read(sy[name], 1)[0]
    var = lambda n: struct.unpack("<h", z.read(sy["VARS"] + 2 * n, 2))[0]
    cstr = lambda b: b.split(b"\0")[0].decode("latin-1")
    folder = lambda: cstr(ovs("GCURDIR", 13))

    def until(cond, timeout=10.0):
        t0 = time.time()
        while time.time() - t0 < timeout:
            if cond():
                return True
            time.sleep(0.05)
        return False

    def press(*codes, hold=0.15):
        for c in codes:
            z.key(c, True)
        time.sleep(hold)
        for c in reversed(codes):
            z.key(c, False)
        time.sleep(0.2)

    def runs():
        t = var(47)                             # VAR_TIMER_TOTAL
        return until(lambda: var(47) > t + 20, 15)

    def pick(*keys):
        press(ZK_CAPS, ord("1"))
        time.sleep(1.0)
        press(ord("j"))
        until(lambda: r8("GMENUON") == 1, 5)
        for k in keys:
            press(k)
    bad = 0

    def check(what, ok):
        nonlocal bad
        print("    %-52s %s" % (what, "bien" if ok else "MAL"))
        bad += not ok
    time.sleep(3)
    n = ovs("GN", 1)[0]
    raw = ovs("GLIST", 9 * 45)
    li = [(cstr(raw[45 * i:45 * i + 13]), cstr(raw[45 * i + 13:45 * i + 45])) for i in range(n)]
    check("tres juegos, por nombre", li == [("", "El juego de esta carpeta"),
                                             ("ZZZ", "Prueba alfa"), ("AAA", "Prueba zeta")])
    t0 = var(47)
    time.sleep(1.0)
    check("esperando (sin juego todavia)", r8("CURROOM") == 0 and var(47) == t0)
    press(ord("3"))
    check("3: el tercero elegido", until(lambda: ovs("GSEL", 1)[0] == 2, 3))
    press(ZK_ENTER)
    check("ENTER: el de AAA, y anda", until(lambda: folder() == "AAA", 20) and runs())
    pick(ZK_CAPS)                               # (CAPS solo: nada)
    check("J: la lista", r8("GMENUON") == 1)
    press(ZK_CAPS, ZK_SPACE)
    check("ESC: el menu de partidas otra vez", until(lambda: r8("GMENUON") == 0, 5))
    press(ZK_CAPS, ZK_SPACE)
    time.sleep(1.0)
    check("ESC: al mismo juego, que sigue", r8("GAMEREQ") == 0 and folder() == "AAA" and runs())
    pick()
    z.write(sy["CURY"], (M.ROOM_Y0 + 36 + 3).to_bytes(2, "little"))     # el raton encima del 1
    check("el raton encima del primero: elegido", until(lambda: ovs("GSEL", 1)[0] == 0, 3))
    press(ZK_ENTER)
    check("ENTER: el de aqui, desde el principio, y anda",
          until(lambda: folder() == "" and r8("GAMEREQ") == 0 and r8("GMENUON") == 0, 20) and runs())
    for d in ("", "AAA", "ZZZ"):
        f = os.path.join(card, d, "SAVE3.DAT")
        if os.path.exists(f):
            os.remove(f)
    press(ZK_CAPS, ord("1"))
    time.sleep(1.0)
    press(ord("3"))
    press(ord("g"))
    check("G: a escribir el nombre", until(lambda: ovs("MEDIT", 1)[0] == 1, 3))
    for k in ((ZK_CAPS, ord("h")), (ord("o"),), (ord("l"),), (ord("a"),), (ZK_SPACE,), (ord("1"),)):
        press(*k)
    check("el nombre escrito: Hola 1", cstr(ovs("MNAME", 25)) == "Hola 1")
    save3 = os.path.join(card, "SAVE3.DAT")
    nombre = lambda: cstr(open(save3, "rb").read()[32:57]) if os.path.exists(save3) else None
    lista = lambda: cstr(ovs("SLOTNM", 8 * 25)[50:75])
    press(ZK_ENTER)
    check("ENTER: guardada, con su nombre (fichero y lista)",
          until(lambda: ovs("MEDIT", 1)[0] == 0 and ovs("MMSG", 1)[0] == 1, 8)
          and nombre() == "Hola 1" and lista() == "Hola 1")

    def colores():
        """Los colores de Layer 2 en la fila de cada hueco (sin el negro del fondo)."""
        l2 = b"".join(z.read_phys((sy["L2_PAGE"] + p) * 0x2000, 0x2000) for p in range(10))
        out = []
        for n in range(8):
            y0 = M.ROOM_Y0 + 32 + 12 * n
            out.append(set(l2[(x >> 5) * 0x2000 + (x & 31) * 256 + y]
                           for x in range(320) for y in range(y0, y0 + 8)) - {0})
        return out
    check("los huecos en gris y el elegido (el 3) en amarillo",
          colores() == [{253}] * 2 + [{254}] + [{253}] * 5)
    press(ord("g"))
    press(ZK_CAPS, ord("0"))
    press(ord("2"))
    press(ZK_ENTER)
    check("G, CAPS + 0 y 2: Hola 2 (empieza con el que tenia)",
          until(lambda: ovs("MEDIT", 1)[0] == 0 and nombre() == "Hola 2", 8) and lista() == "Hola 2")
    press(ord("g"))
    press(ord("x"))
    press(ZK_CAPS, ZK_SPACE)
    time.sleep(1.0)
    check("G, x y ESC: no se guarda", ovs("MEDIT", 1)[0] == 0 and nombre() == "Hola 2")
    press(ZK_CAPS, ZK_SPACE)
    check("guardar: SAVE3.DAT junto al .nex (no en las carpetas)",
          os.path.exists(os.path.join(card, "SAVE3.DAT"))
          and not any(os.path.exists(os.path.join(card, d, "SAVE3.DAT")) for d in ("AAA", "ZZZ")))
    pick(ord("2"), ZK_ENTER)
    check("J, 2, ENTER: el de ZZZ, y anda", until(lambda: folder() == "ZZZ", 20) and runs())
    print("juegos: %s" % ("bien" if not bad else "%d MAL" % bad))
    z.close()
    return bad == 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "walk"
    arg = sys.argv[2] if len(sys.argv) > 2 else None
    if cmd == "unit":
        ok = cmd_unit(int(arg or 200))
    elif cmd == "walk":
        ok = cmd_walk()
    elif cmd == "random":
        ok = cmd_random(int(arg or 400))
    elif cmd == "screen":
        ok = cmd_screen()
    elif cmd == "objetos":
        ok = cmd_objetos(int(arg or 40))
    elif cmd == "escala":
        ok = cmd_escala()
    elif cmd == "costumes":
        ok = cmd_costumes()
    elif cmd == "scripts":
        ok = cmd_scripts()
    elif cmd == "actores":
        ok = cmd_actores()
    elif cmd == "pseudo":
        ok = cmd_pseudo()
    elif cmd == "saltos":
        ok = cmd_saltos(int(arg) if arg else 240)
    elif cmd == "interfaz":
        ok = cmd_interfaz(int(arg) if arg else IFACE_STEPS)
    elif cmd == "sonido":
        ok = cmd_sonido()
    elif cmd == "guardar":
        ok = cmd_guardar()
    elif cmd == "teclas":
        ok = cmd_teclas(int(arg) if arg else None)
    elif cmd == "juegos":
        ok = cmd_juegos(int(arg) if arg else None)
    elif cmd == "arranque":
        save_every = 0
        if len(sys.argv) > 3 and sys.argv[-1].startswith("guardar"):
            save_every = int(sys.argv[-1][7:] or 5)
            sys.argv.pop()
        tour = None
        if len(sys.argv) > 3:
            hdr = open(os.path.join(SD_JUEGO, "GAME.DAT"), "rb").read()
            tour = (list(hdr[7:7 + hdr[6]]) if sys.argv[3] == "todas"
                    else [int(v) for v in sys.argv[3:]])
        ok = cmd_arranque(int(arg) if arg else 600, tour=tour, save_every=save_every)
    elif cmd == "juego":
        ok = cmd_juego([int(v) for v in sys.argv[2:]])
    elif cmd == "partida":
        ok = cmd_partida(arg or "_fin", int(sys.argv[3]) if len(sys.argv) > 3 else 10,
                         int(sys.argv[4]) if len(sys.argv) > 4 else None,
                         int(sys.argv[5]) if len(sys.argv) > 5 else 0)
    elif cmd == "gif":
        ok = cmd_gif(arg or os.path.join(ROOT, "docs", "demo.gif"))
    else:
        sys.exit(__doc__)
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
