"""Una partida guiada en el modelo: un jugador que lee una solucion (fichero de texto
con verbos, objetos, conversaciones...) y la juega como una persona: pulsa el verbo,
pulsa el objeto (o el del inventario, o el actor) y espera a que acabe. Guarda la
entrada de cada paso (raton, boton, tecla) para repetir la misma partida en el Z80
(nexttest.py partida) y deja puntos de control para seguir desde ahi.

    python tools/partida.py SOLUCION              # la juega desde el arranque
    python tools/partida.py SOLUCION --desde N    # desde el punto de control N
    python tools/partida.py SOLUCION --ver        # y lo que hay en cada habitacion

La solucion va aparte (con los nombres del juego no se reparte). Cada linea:

    # comentario
    @ nombre                       un punto de control
    esc | punto                    las teclas ESC y '.'
    esperar [N]                    hasta que se pueda jugar (o N pasos)
    ir NOMBRE                      pulsar el objeto (o actor) sin verbo: andar hasta el
    ir X Y                         pulsar en (X, Y) de la habitacion
    entrar NOMBRE N                pulsar NOMBRE (sin verbo) hasta estar en la habitacion N
    ir_a N [ABRIR]                 hasta la habitacion N por las salidas (se busca el camino
                                   probandolas en copias; ABRIR: el verbo para las puertas)
    buscar NOMBRE                  hasta una habitacion donde se pueda pulsar ese objeto
    VERBO: A [: B]                 el verbo con A (y con B: "usar A con B", "dar A a B")
    decir N | decir TEXTO          la opcion N (1, 2...) de la conversacion, o la que
                                   contenga TEXTO
    hasta estado NOMBRE V | hab N | actor NOMBRE | noactor NOMBRE | libre |
          anda NOMBRE der|izq | charla | nocharla | opcion TEXTO | tiene NOMBRE |
          notiene NOMBRE | nohab N | clase OBJ C |
          noclase OBJ C
                                   pasos sin hacer nada hasta que pase eso
    si COND => LINEA               la linea solo si se cumple COND (las de hasta, y var N V,
                                   var N V+ y bit N V)
    bucle N ... hasta_que COND     las lineas de dentro, hasta N veces, hasta que se cumpla
    ver                            (para escribirla) lo que hay: verbos, objetos...
    charlar N                      decir N mientras haya conversacion
    duelo V1 V2 [aprender]         jugar el duelo a insultos de ahora (V1, V2: las variables
                                   de los puntos propios y del rival); cada opcion se
                                   prueba en una copia: los puntos y lo que ensena
    seguir NOMBRE HAB [ABRIR]      seguir a un actor (por donde sale) hasta la habitacion HAB
                                   (ABRIR: el verbo para las puertas cerradas)
    pelear N V1 V2 HAB RETO        en el mapa, N duelos para aprender con quien aparezca
                                   (HAB: la del duelo; RETO: la opcion que lo empieza)
    pelear_ganar N V1 V2 HAB RETO  lo mismo, para ganar
    saber BITS A-B,C-D             los bits que cuentan como aprendido en los duelos
                                   (A-B: lo que se aprende cuando ataca el otro; sabido,
                                   se aprende ganando asaltos)
    elegir N                       la opcion N, sin esperar a poder jugar (una ultima)
    ir_var V                       andar al objeto cuyo numero guarda la variable V (lo
                                   que senala el juego, p. ej. un laberinto al azar)
    charla_hasta COND              las opciones de la conversacion de ahora que llevan a
                                   COND (buscadas en copias)
    quitar TEXTO | quitar -        si sale sola una conversacion con esa opcion (alguien
                                   que aparece), elegirla al esperar (- : ya no)
    alterna V1 V2 OBJETO VAR N     una combinacion que guarda el juego: V1 sobre OBJETO
                                   (variable VAR) veces, V2 (VAR+1) veces, y asi N grupos
    inventario P H S A B V         el inventario: verbos P.. (H huecos), las flechas A y B,
                                   que mueven S objetos, y la variable V (filas movidas)
    hab N                          comprobar que se esta en la habitacion N
    tiene NOMBRE | notiene NOMBRE  comprobar el inventario
    var N V                        comprobar la variable N

Los nombres se buscan sin mayusculas y por trozos (vale un trozo del nombre); si
hay varios, el que es igual, si no el primero; NOMBRE#N es el objeto (o actor) N.
"""
import importlib
import io
import os
import pickle
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import nexttest as T  # noqa: E402
import convert as C  # noqa: E402

DIR = os.path.join(os.path.dirname(HERE), "build", "partida")
if hasattr(sys.stdout, "reconfigure"):          # (los nombres llevan letras del DOS)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
VAR_EGO = 1


def txt(b):
    if b is None:
        return ""
    if isinstance(b, str):
        return b
    return bytes(b).decode("cp437")             # (las fuentes de SCUMM: como el DOS)


def low(s):
    return txt(s).lower()


class Atasco(Exception):
    """La solucion no se puede seguir (no hay tal cosa, o no se acaba)."""


class Jugador:
    def __init__(self, w):
        self.w = w
        self.t = 0
        self.mouse = (160, 100)
        self.inputs = []                    # (raton, boton, tecla) de cada paso
        self.log = []

    # --- un paso ---------------------------------------------------------------
    def tick(self, mouse=None, button=0, key=0):
        if mouse is not None:
            self.mouse = (int(mouse[0]), int(mouse[1]))
        self.w.tick(mouse=self.mouse, button=button, key=key)
        self.inputs.append((self.mouse, button, key))
        self.t += 1

    def ego(self):
        vm = self.w.vm
        return vm.actors[vm.vars[VAR_EGO]]

    def libre(self):
        """Se puede jugar: sin escena, con el cursor y la entrada, sin que hable el
        protagonista, sin frase pendiente y el protagonista parado."""
        w, ui = self.w, self.w.ui
        if ui.cursor_state <= 0 or ui.userput <= 0:
            return False
        if w.vm.cs_sp:                      # (en una escena: solo si espera una opcion)
            return bool(self.opciones()) and not ui.have_msg
        if ui.have_msg and ui.talking_actor() == w.vm.vars[VAR_EGO]:
            return False                    # (lo que hablan otros, o un letrero, no impide jugar)
        if ui.sentence:
            return False
        if w.room and self.ego().moving:
            return False
        return True

    def esperar(self, maximo=3000, seguidos=4):
        n = 0
        for _ in range(maximo):
            if getattr(self, "quitar", None) and self.cortar():
                n = 0
                continue
            if self.libre():
                n += 1
                if n >= seguidos:
                    return
            else:
                n = 0
            self.tick()
        raise Atasco("no se acaba (paso %d, habitacion %d)" % (self.t, self.w.room))

    def charla_hasta(self, cond, nodos=400):
        """Las opciones de la conversacion de ahora (por anchura, en copias) que llevan a
        que se cumpla cond; None si no se encuentra."""
        from collections import deque
        self.esperar()
        if self.condicion(cond)():
            return []
        for _ in range(3000):
            if self.opciones():
                break
            self.tick()
        cola = deque([(self, [])])
        vistos = {tuple(n for _, n in self.opciones())}
        n = 0
        while cola and n < nodos:
            j, ruta = cola.popleft()
            for k, _ in enumerate(j.opciones()):
                c = j.copia()
                n += 1
                ok = c.condicion(cond)
                try:
                    c.hacer("decir %d" % (k + 1))
                    for _ in range(3000):
                        if c.opciones() or ok():
                            break
                        c.tick()
                except Atasco:
                    continue
                if ok():
                    return ruta + [k + 1]
                clave = tuple(nn for _, nn in c.opciones())
                if clave and clave not in vistos:
                    vistos.add(clave)
                    cola.append((c, ruta + [k + 1]))
        return None

    def cortar(self):
        """Una conversacion que sale sola (ver 'quitar'): elegir su despedida."""
        ops = self.opciones()
        for v, n in ops:
            if any(q in low(n) for q in self.quitar):
                self.pulsar(self.punto_verbo(v))
                return True
        return False

    def pasos(self, n):
        for _ in range(n):
            self.tick()

    # --- lo que hay ---------------------------------------------------------------
    def verbos(self):
        """(ranura, verbo) visibles"""
        ui = self.w.ui
        return [(i, v) for i, v in enumerate(ui.verbs)
                if i and v.verbid and v.curmode == 1 and not v.saveid and v.right > v.left]

    def nombre_verbo(self, v):
        if v.name is None:
            return ""
        return txt(self.w.ui.convert(v.name))

    def objetos(self):
        w = self.w
        if not w.room:
            return []
        return [(o, txt(w.object_name(o.id))) for o in w.eng.objs if o.id]

    def actores(self):
        w = self.w
        out = []
        for i, a in enumerate(w.vm.actors):
            if i and a.in_room() and a.visible:
                out.append((i, txt(w.ui.actor_names.get(i, b""))))
        return out

    def inventario(self):
        ui = self.w.ui
        return [(o, txt(ui.obj_or_actor_name(o))) for o in ui.inventory
                if o and self.w.vm.owner_of(o) == self.w.vm.vars[VAR_EGO]]

    # --- pulsar -----------------------------------------------------------------------
    def pulsar(self, punto, boton=1):
        self.tick(mouse=punto, button=boton)

    def punto_verbo(self, v):
        return (v.left + 3, v.top + 3)

    def buscar(self, nombre, lista):
        if "#" in nombre:                   # nombre#numero: ese objeto (o actor)
            n, k = nombre.rsplit("#", 1)
            for x in lista:
                xid = x[0] if isinstance(x[0], int) else getattr(x[0], "id", None)
                if xid == int(k):
                    return x
            return None
        n = low(nombre)
        igual = [x for x in lista if low(x[1]) == n]
        if igual:
            return igual[0]
        trozo = [x for x in lista if n in low(x[1])]
        return trozo[0] if trozo else None

    def pulsar_verbo(self, nombre):
        x = self.buscar(nombre, [(v, self.nombre_verbo(v)) for _, v in self.verbos()])
        if x is None:
            raise Atasco("no hay verbo '%s'" % nombre)
        self.pulsar(self.punto_verbo(x[0]))

    def punto_objeto(self, oid):
        w = self.w
        left = w.cam_left()
        for o in w.eng.objs:
            if o.id != oid:
                continue
            x0, x1 = max(o.x * 8, left), min((o.x + o.w) * 8, left + 320)
            y0, y1 = o.y, min(o.y + o.h, w.ui.main_h)
            cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
            pts = sorted(((x, y) for x in range(x0, x1) for y in range(y0, y1)),
                         key=lambda p: (abs(p[0] - cx) + abs(p[1] - cy), p))
            for x, y in pts:
                if w.find_object(x, y) == oid and not w.actor_from_pos(x, y):
                    return (x - left, y)
            for x, y in pts:
                if w.find_object(x, y) == oid:
                    return (x - left, y)
            return None
        return None

    def punto_actor(self, n):
        w = self.w
        a = w.vm.actors[n]
        left = w.cam_left()
        pts = [(a.x + dx, (a.top + a.bottom) // 2 + dy) for dy in range(-40, 80, 2) for dx in (0, -4, 4, -8, 8)]
        pts = [(x, y) for x, y in pts if left <= x < left + 320 and 0 <= y < w.ui.main_h
               and w.actor_from_pos(x, y) == n]
        for x, y in pts:                    # (mejor donde no hay objeto debajo)
            if not w.find_object(x, y):
                return (x - left, y)
        return (pts[0][0] - left, pts[0][1]) if pts else None

    def acercar(self, x):
        """La camara hasta que se vea la x de habitacion: andar hacia ese lado."""
        w = self.w
        sala = w.room
        for _ in range(12):
            if w.room != sala:              # (andando se ha salido de la habitacion)
                return False
            left = w.cam_left()
            if left + 8 <= x < left + 312:
                return True
            tx = 316 if x >= left + 312 else 4
            # (un punto del borde sin objetos ni actores: si no, se iria a ellos)
            pt = None
            for dy in (0, 2, 4, 6, -2, -4, 8, 10, -6, 12, 16, -10, 20):
                for dx in (0, -8, -16, -24, -32):
                    xx = tx + dx if tx > 160 else tx - dx
                    yy = self.ego().y - 2 + dy
                    if 0 <= yy < w.ui.main_h and not w.find_object(xx + left, yy)                             and not w.actor_from_pos(xx + left, yy):
                        pt = (xx, yy)
                        break
                if pt:
                    break
            self.pulsar(pt or (tx, self.ego().y - 2))
            self.esperar()
        # (si no: otros puntos del borde, a cualquier altura, tambien sobre objetos sin
        # nombre, que suelen ser pasos de una parte a otra)
        for yy in range(8, w.ui.main_h, 12):
            if w.room != sala:
                return False
            left = w.cam_left()
            if left + 8 <= x < left + 312:
                return True
            tx = 316 if x >= left + 312 else 4
            ob = w.find_object(tx + left, yy)
            if (ob and txt(w.object_name(ob))) or w.actor_from_pos(tx + left, yy):
                continue
            self.pulsar((tx, yy))
            self.esperar()
        left = w.cam_left()
        return w.room == sala and left + 8 <= x < left + 312

    def a_la_vista(self, nombre):
        """Si es un objeto o un actor de la habitacion que no se ve, andar hasta verlo
        (antes de pulsar el verbo: andar lo cambiaria)."""
        if self.buscar(nombre, self.inventario()) is not None:
            return
        ob = self.buscar(nombre, self.objetos())
        if ob is not None:
            if self.punto_objeto(ob[0].id) is None:
                self.acercar(ob[0].x * 8 + ob[0].w * 4)
            return
        ac = self.buscar(nombre, self.actores())
        if ac is not None and self.punto_actor(ac[0]) is None:
            self.acercar(self.w.vm.actors[ac[0]].x)

    def pulsar_cosa(self, nombre):
        """El inventario, un objeto de la habitacion o un actor."""
        inv = self.buscar(nombre, self.inventario())
        if inv is not None:
            # el inventario son verbos de imagen: el n-esimo objeto del protagonista (en
            # el orden del inventario), en el verbo primero + n - desplazamiento; si no
            # se ve, las flechas (ver 'inventario')
            primero, huecos, paso, arriba, abajo, var = getattr(self, "inv_cfg", (200, 8, 4, 0, 0, None))
            k = [o for o, _ in self.inventario()].index(inv[0])
            for _ in range(20):
                desp = self.w.vm.vars[var] * paso if var is not None else 0
                if desp <= k < desp + huecos:
                    break
                flecha = arriba if k < desp else abajo
                f = next((v for _, v in self.verbos() if v.verbid == flecha), None)
                if f is None:
                    raise Atasco("'%s' esta en el inventario pero no se ve (puesto %d)" % (nombre, k))
                self.pulsar(((f.left + f.right) // 2, (f.top + f.bottom) // 2))
                self.pasos(3)
            desp = self.w.vm.vars[var] * paso if var is not None else 0
            for _, v in self.verbos():
                if v.verbid == primero + k - desp:
                    self.pulsar(((v.left + v.right) // 2, (v.top + v.bottom) // 2))
                    return
            raise Atasco("'%s' esta en el inventario pero no se ve (puesto %d)" % (nombre, k))
        ob = self.buscar(nombre, self.objetos())
        if ob is not None:
            o = ob[0]
            sala = self.w.room
            p = self.punto_objeto(o.id)
            if p is None and self.acercar(o.x * 8 + o.w * 4):
                p = self.punto_objeto(o.id)
            if p is None and self.w.room != sala:
                return                      # (al acercarse ya ha salido por ahi)
            if p is None:
                raise Atasco("el objeto '%s' (%d) no se puede pulsar" % (nombre, o.id))
            self.pulsar(p)
            return
        ac = self.buscar(nombre, self.actores())
        if ac is not None:
            p = self.punto_actor(ac[0])
            if p is None and self.acercar(self.w.vm.actors[ac[0]].x):
                p = self.punto_actor(ac[0])
            if p is None:
                raise Atasco("el actor '%s' no se puede pulsar" % nombre)
            self.pulsar(p)
            return
        raise Atasco("no hay '%s' (habitacion %d)" % (nombre, self.w.room))

    # --- una linea de la solucion -------------------------------------------------
    def hacer(self, linea):
        s = linea.strip()
        if not s or s.startswith("#"):
            return
        self.log.append((self.t, self.w.room, s))
        cmd, _, rest = s.partition(" ")
        cmd = cmd.lower()
        if cmd == "esc":
            self.tick(key=27)
            return
        if cmd == "punto":
            self.tick(key=46)
            return
        if cmd == "esperar":
            if rest.strip():
                self.pasos(int(rest))
            else:
                self.esperar()
            return
        if cmd == "hasta":
            self.hasta(rest)
            return
        if cmd == "si":
            cond, _, linea = rest.partition("=>")
            self.esperar()
            if self.condicion(cond.strip())():
                self.hacer(linea)
            return
        if cmd == "charlar":
            for _ in range(200):
                self.esperar()
                if not self.opciones():
                    return
                self.hacer("decir %s" % rest)
            raise Atasco("charlar: no se acaba")
        if cmd == "duelo":
            a = rest.split()
            self.duelo(int(a[0]), int(a[1]), a[2] if len(a) > 2 else "ganar")
            return
        if cmd == "ir_a":                   # ir_a HAB [ABRIR]: por las salidas (en copias)
            a = rest.split()
            camino = self.camino_a(int(a[0]), a[1] if len(a) > 1 else None, hondo=10)
            if camino is None:              # (las salidas sin nombre: los mapas)
                camino = self.camino_a(int(a[0]), a[1] if len(a) > 1 else None, hondo=10,
                                       sin_nombre=True)
            if camino is None:
                raise Atasco("no se encuentra el camino a la habitacion %s" % a[0])
            for oid in camino:
                self.salir_por(oid, a[1] if len(a) > 1 else None)
            if self.w.room != int(a[0]):
                raise Atasco("ir_a: en la habitacion %d, no en la %s" % (self.w.room, a[0]))
            return
        if cmd == "buscar":                 # buscar NOMBRE: ir a donde esta (en copias)
            camino = self.camino_a_objeto(rest.strip())
            if camino is None:
                raise Atasco("no se encuentra '%s'" % rest.strip())
            for oid in camino:
                self.salir_por(oid)
            return
        if cmd == "seguir":
            a = rest.split()
            self.seguir(a[0], int(a[1]), a[2] if len(a) > 2 else None)
            return
        if cmd in ("pelear", "pelear_ganar"):
            a = rest.split(None, 4)
            self.pelear(int(a[0]), int(a[1]), int(a[2]), int(a[3]), a[4],
                        "ganar" if cmd == "pelear_ganar" else "aprender")
            return
        if cmd == "inventario":             # inventario PRIMERO HUECOS PASO ARRIBA ABAJO VAR
            a = [int(x) for x in rest.split()]
            self.inv_cfg = tuple(a)
            return
        if cmd == "saber":                  # saber BITS a-b,c-d: lo que cuenta como aprendido
            self.rangos = [tuple(int(x) for x in r.split("-")) for r in rest.split()[1].split(",")]
            return
        if cmd == "entrar":
            nombre, sala = rest.rsplit(" ", 1)
            for _ in range(400):
                if self.w.room == int(sala):
                    self.esperar()
                    return
                if self.libre() and self.buscar(nombre, self.objetos() + self.actores()) is not None:
                    self.pulsar_cosa(nombre)
                    self.pasos(8)
                else:
                    self.pasos(2)
            raise Atasco("no se llega a la habitacion %s" % sala)
        if cmd == "ver":
            self.esperar()
            self.ver()
            return
        if cmd == "hab":
            if self.w.room != int(rest):
                raise Atasco("en la habitacion %d, no en la %s" % (self.w.room, rest))
            return
        if cmd in ("tiene", "notiene"):
            esta = self.buscar(rest, self.inventario()) is not None
            if esta != (cmd == "tiene"):
                raise Atasco("%s: %s" % (cmd, rest))
            return
        if cmd == "elegir":                 # elegir N: la opcion N, sin esperar despues (el final)
            for _ in range(3000):
                if self.opciones():
                    break
                self.tick()
            ops = self.opciones()
            if not 0 < int(rest) <= len(ops):
                raise Atasco("elegir: no hay opcion %s" % rest)
            self.pulsar(self.punto_verbo(ops[int(rest) - 1][0]))
            return
        if cmd == "ir_var":                 # ir_var V: al objeto cuyo numero guarda la variable V
            v, vm, sala = int(rest), self.w.vm, self.w.room
            self.esperar()
            for _ in range(1500):           # (hasta que el juego lo decida: no 0)
                if vm.vars[v]:
                    break
                self.tick()
            self.salir_por(vm.vars[v])
            for _ in range(1500):           # (y hasta que lo borre: otra pantalla)
                if vm.vars[v] == 0 or self.w.room != sala:
                    break
                self.tick()
            self.esperar()
            return
        if cmd == "charla_hasta":           # charla_hasta COND: buscar las opciones (en copias)
            ruta = self.charla_hasta(rest.strip())
            if ruta is None:
                raise Atasco("charla_hasta: no se llega a '%s'" % rest.strip())
            for k in ruta:
                self.hacer("decir %d" % k)
            self.esperar()
            return
        if cmd == "quitar":                 # quitar TEXTO: la despedida de quien sale solo
            if rest.strip() == "-":         # (quitar -: ya no)
                self.quitar = []
            else:
                self.quitar = getattr(self, "quitar", []) + [low(rest.strip())]
            return
        if cmd == "alterna":                # alterna V1 V2 OBJETO VAR N
            v1, v2, ob, var, n = rest.split()
            for k in range(int(n)):
                for _ in range(self.w.vm.vars[int(var) + k]):
                    self.hacer("%s: %s" % (v2 if k % 2 else v1, ob))
                    self.esperar()
            return
        if cmd == "var":
            n, v = (int(x) for x in rest.split())
            if self.w.vm.vars[n] != v:
                raise Atasco("var %d = %d, no %d" % (n, self.w.vm.vars[n], v))
            return
        if cmd == "decir":
            self.esperar()
            for _ in range(3000):           # (las opciones salen cuando acaban de hablar)
                if self.opciones():
                    break
                self.tick()
            ops = self.opciones()
            if rest.strip().isdigit():
                k = int(rest) - 1
                if not 0 <= k < len(ops):
                    raise Atasco("solo hay %d opciones" % len(ops))
                v = ops[k][0]
            else:
                x = self.buscar(rest, ops)
                if x is None:
                    raise Atasco("no hay opcion '%s'" % rest)
                v = x[0]
            self.pulsar(self.punto_verbo(v))
            self.esperar()
            return
        if cmd == "ir":
            self.esperar()
            a = rest.split()
            if len(a) == 2 and all(x.lstrip("-").isdigit() for x in a):
                x, y = int(a[0]), int(a[1])
                if self.acercar(x):
                    self.pulsar((x - self.w.cam_left(), y))
            else:
                for _ in range(6):          # (si no hace nada, otra vez: a veces un
                    antes = (self.w.room, self.ego().x, self.ego().y)   # script no deja)
                    self.pulsar_cosa(rest)
                    self.esperar()
                    if (self.w.room, self.ego().x, self.ego().y) != antes:
                        break
                    self.pasos(10)
                    self.esperar()
            self.esperar()
            return
        if ":" in s:
            partes = [p.strip() for p in s.split(":")]
            self.esperar()
            for p in partes[1:]:
                self.a_la_vista(p)
            self.pulsar_verbo(partes[0])
            self.pulsar_cosa(partes[1])
            if len(partes) > 2:
                self.pasos(2)
                self.pulsar_cosa(partes[2])
            self.esperar()
            return
        raise Atasco("no entiendo '%s'" % s)

    def hasta(self, cond, maximo=6000):
        """Pasos sin hacer nada hasta: estado NOMBRE V | hab N | actor NOMBRE |
        noactor NOMBRE | libre | anda NOMBRE der|izq"""
        ok = self.condicion(cond)
        self.prev = {}
        for _ in range(maximo):
            if ok():
                return
            self.tick()
        raise Atasco("hasta %s: no pasa" % cond)

    def condicion(self, cond):
        a = cond.split()
        k = a[0].lower()
        self.prev = {}

        def ok():
            if k == "estado":
                ob = self.buscar(" ".join(a[1:-1]), self.objetos())
                return ob is not None and self.w.vm.state[ob[0].id] == int(a[-1])
            if k in ("hab", "nohab"):
                return (self.w.room == int(a[1])) == (k == "hab")
            if k in ("actor", "noactor"):
                esta = self.buscar(" ".join(a[1:]), self.actores()) is not None
                return esta == (k == "actor")
            if k == "libre":
                return self.libre()
            if k in ("clase", "noclase"):       # clase OBJ C: el objeto OBJ tiene la clase C
                return bool(self.w.vm.classes[int(a[1])] >> (int(a[2]) - 1) & 1) == (k == "clase")
            if k in ("tiene", "notiene"):       # tiene NOMBRE: en el inventario (o no)
                return (self.buscar(" ".join(a[1:]), self.inventario()) is not None) == (k == "tiene")
            if k in ("charla", "nocharla"):     # hay opciones de conversacion (o no)
                return bool(self.opciones()) == (k == "charla")
            if k == "opcion":                   # opcion TEXTO: hay una opcion con ese texto
                return self.buscar(" ".join(a[1:]), [(v, n) for v, n in self.opciones()]) is not None
            if k == "var":                      # var N V: la variable N vale V (o mas: V+)
                n, v = int(a[1]), a[2]
                return self.w.vm.vars[n] >= int(v[:-1]) if v.endswith("+") else self.w.vm.vars[n] == int(v)
            if k == "bit":
                n = int(a[1])
                bits = self.w.vm.bits
                return ((bits[n >> 3] >> (n & 7)) & 1) == int(a[2])
            if k == "anda":                 # anda NOMBRE der|izq: andando hacia ese lado
                ac = self.buscar(" ".join(a[1:-1]), self.actores())
                if ac is None:
                    return False
                act = self.w.vm.actors[ac[0]]
                antes = self.prev.get(ac[0], act.x)
                self.prev[ac[0]] = act.x
                return act.moving and ((act.x > antes) if a[-1].startswith("d") else (act.x < antes))
            raise Atasco("no entiendo la condicion '%s'" % cond)
        return ok

    # --- duelos (a insultos) -------------------------------------------------------
    def copia(self):
        b = io.BytesIO()
        _Guardar(b, protocol=pickle.HIGHEST_PROTOCOL).dump(self)
        b.seek(0)
        return _Cargar(b).load()

    def opciones(self):
        """Las opciones de una conversacion (vacio si estan los verbos normales)."""
        vs = sorted(self.verbos(), key=lambda iv: (iv[1].top, iv[1].left))
        if not vs or any(v.verbid < 100 for _, v in vs):
            return []
        return [(v, self.nombre_verbo(v)) for _, v in vs]

    def saber(self):
        """Lo que se ha aprendido: los bits puestos de los rangos de 'saber BITS' (o de
        todos)."""
        bits = getattr(self.w.vm, "bits", None)
        if bits is None:
            return 0
        rangos = getattr(self, "rangos", None)
        if not rangos:
            return sum(bin(b).count("1") for b in bits)
        return sum((bits[i >> 3] >> (i & 7)) & 1 for a, b in rangos for i in range(a, b + 1))

    def falta(self, k):
        """Los bits sin poner del rango k de 'saber BITS' (0 sin rangos)."""
        rangos = getattr(self, "rangos", None)
        if not rangos or k >= len(rangos):
            return 0
        bits = self.w.vm.bits
        a, b = rangos[k]
        return sum(1 - ((bits[i >> 3] >> (i & 7)) & 1) for i in range(a, b + 1))

    @staticmethod
    def flecha(n):
        """Las flechas de una lista de opciones que no cabe (empiezan con codigos)."""
        n = txt(n)
        return bool(n) and (n[0] == " " or n[0] < " ")

    def paginas(self, maximo=24):
        """Las paginas de un menu de opciones con flechas: (las flechas que hay que
        pulsar desde aqui, una copia en esa pagina); hacia abajo (la flecha que no es la
        primera opcion) y hacia arriba (la primera)."""
        out = [([], self)]
        for abajo in (True, False):
            j, ruta = self, []
            for _ in range(maximo):
                fl = [k for k, (v, n) in enumerate(j.opciones()) if self.flecha(n) and (k > 0) == abajo]
                if not fl:
                    break
                c = j.copia()
                try:
                    c.hacer("decir %d" % (fl[0] + 1))
                except Atasco:
                    break
                ruta = ruta + [fl[0]]
                out.append((ruta, c))
                j = c
        return out

    def duelo(self, nuestros, suyos, modo="ganar", evitar="rindo", rendirse=40, maximo=200):
        """El duelo que hay ahora: en cada eleccion, cada opcion de todas las paginas del
        menu (las flechas) en una copia hasta la siguiente eleccion. Lo que ensena: los
        bits de 'saber BITS' (o textos nuevos en las opciones siguientes). modo ganar:
        antes los puntos (nuestros - suyos), luego lo que ensena; aprender: al reves.
        Despues, la menos usada. Tras rendirse elecciones: rendirse (la opcion evitar) o
        perder pronto."""
        if not hasattr(self, "conocidas"):
            self.conocidas = set()
        usadas = {}
        for d in range(maximo):
            self.esperar()
            ops = self.opciones()
            if not ops:
                return
            self.conocidas.update(n for _, n in ops)
            vars_ = self.w.vm.vars
            d0 = vars_[nuestros] - vars_[suyos]
            s0 = self.saber()
            mejor = None
            vistas = set()
            pags = self.paginas() if any(self.flecha(n) for _, n in ops) else [([], self)]
            for ruta, pj in pags:
                for k, (v, n) in enumerate(pj.opciones()):
                    if self.flecha(n) or n in vistas:
                        continue
                    vistas.add(n)
                    rendir = evitar and evitar in low(n)
                    if rendir and d < rendirse:
                        continue
                    if rendir:
                        punt = (1 << 30,)
                    else:
                        c = pj.copia()
                        try:
                            c.hacer("decir %d" % (k + 1))
                        except Atasco:
                            continue
                        cv = c.w.vm.vars
                        pts = cv[nuestros] - cv[suyos] - d0
                        sig = c.opciones()
                        nuevas = c.saber() - s0 if getattr(self, "rangos", None) else                             len(set(nn for _, nn in sig) - self.conocidas)
                        if d >= rendirse:   # (no se acaba: perder pronto, para seguir)
                            punt = (-pts, -usadas.get(n, 0), -len(ruta))
                        elif modo == "aprender":    # aprender; y que ataque el (se le oyen
                            # insultos) o, sabidos, que siga el duelo ganando asaltos (se le
                            # oyen las respuestas)
                            if self.falta(0):
                                punt = (nuevas, -pts, -usadas.get(n, 0), -len(ruta))
                            else:
                                punt = (nuevas, 1 if sig else 0, pts, -usadas.get(n, 0), -len(ruta))
                        else:
                            punt = (pts, nuevas, -usadas.get(n, 0), -len(ruta))
                    if mejor is None or punt > mejor[0]:
                        mejor = (punt, ruta, k, n)
            if mejor is None:
                raise Atasco("duelo: ninguna opcion sirve")
            _, ruta, k, n = mejor
            usadas[n] = usadas.get(n, 0) + 1
            for m in ruta:
                self.hacer("decir %d" % (m + 1))
            self.hacer("decir %d" % (k + 1))
        raise Atasco("duelo: no se acaba")

    def cerca_de(self, act):
        """Un punto del suelo junto al actor (sin objetos ni actores, y lejos de donde
        se entra en los sitios: los puntos de llegada de los objetos)."""
        w = self.w
        left = w.cam_left()
        llegadas = [(o.walk_x, o.walk_y) for o, _ in self.objetos() if o.walk_x or o.walk_y]
        for r in range(0, 14, 2):
            for dx, dy in ((0, 0), (r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r), (r, -r), (-r, r)):
                x, y = act.x + dx, act.y + dy
                if not (left <= x < left + 320 and 0 <= y < w.ui.main_h):
                    continue
                if w.find_object(x, y) or w.actor_from_pos(x, y):
                    continue
                if any(abs(x - lx) + abs(y - ly) < 24 for lx, ly in llegadas):
                    continue
                return (x - left, y)
        return None

    def salir_por(self, oid, abrir=None):
        """Andar hasta la salida oid (y si no se sale y hay verbo de abrir, abrirla y otra
        vez); la habitacion en la que se acaba."""
        w = self.w
        antes = w.room
        o = next((o for o, _ in self.objetos() if o.id == oid), None)
        if o is None:
            return w.room
        if self.punto_objeto(oid) is None:
            self.acercar(o.x * 8 + o.w * 4)
        if w.room != antes:
            return w.room
        pt = self.punto_objeto(oid)
        if pt is None:
            return w.room
        self.pulsar(pt)
        self.esperar()
        if w.room == antes and abrir:       # (una puerta cerrada)
            self.hacer("%s: #%d" % (abrir, oid))
            pt = self.punto_objeto(oid)
            if pt:
                self.pulsar(pt)
                self.esperar()
        return w.room

    def camino_a(self, meta, abrir=None, hondo=3, sin_nombre=False):
        """Las salidas (hasta hondo) que llevan a la habitacion meta, probadas en copias
        (por anchura); None si no hay. sin_nombre: tambien los objetos sin nombre que se
        pueden pulsar (las salidas de los mapas)."""
        nivel = [(self, [])]
        vistas = {self.w.room}
        for _ in range(hondo):
            sig = []
            for j, ruta in nivel:
                for o, nm in j.objetos():
                    if not nm and not (sin_nombre and j.punto_objeto(o.id) is not None):
                        continue
                    c = j.copia()
                    try:
                        r = c.salir_por(o.id, abrir)
                    except Atasco:
                        continue
                    if r == meta:
                        return ruta + [o.id]
                    if r not in vistas:
                        vistas.add(r)
                        sig.append((c, ruta + [o.id]))
            nivel = sig
        return None

    def camino_a_objeto(self, nombre, abrir=None, hondo=10):
        """Las salidas que llevan a una habitacion donde se puede pulsar el objeto
        nombre (probadas en copias, por anchura); None si no hay."""
        def aqui(j):
            ob = j.buscar(nombre, j.objetos())
            return ob is not None and j.punto_objeto(ob[0].id) is not None
        if aqui(self):
            return []
        nivel = [(self, [])]
        vistas = {self.w.room}
        for _ in range(hondo):
            sig = []
            for j, ruta in nivel:
                for o, nm in j.objetos():
                    if not nm:
                        continue
                    c = j.copia()
                    try:
                        r = c.salir_por(o.id, abrir)
                    except Atasco:
                        continue
                    if r in vistas:
                        continue
                    vistas.add(r)
                    if aqui(c):
                        return ruta + [o.id]
                    sig.append((c, ruta + [o.id]))
            nivel = sig
        return None

    def seguir(self, nombre, sala, abrir=None, maximo=30000):
        """Seguir a un actor hasta la habitacion sala: si esta aqui, ir junto a el; si
        esta en otra, la salida que lleva alli (cada una se prueba en una copia)."""
        w = self.w
        ac = self.buscar(nombre, [(i, txt(w.ui.actor_names.get(i, b""))) for i in range(1, len(w.vm.actors))])
        if ac is None:
            raise Atasco("seguir: no hay '%s'" % nombre)
        n = ac[0]
        t0 = self.t
        while self.t - t0 < maximo:
            if w.room == sala:
                self.esperar()
                return
            a = w.vm.actors[n]
            if not self.libre():
                self.pasos(5)
                continue
            if a.room == w.room:
                g = self.ego()
                if abs(g.x - a.x) + abs(g.y - a.y) > 30:
                    p = self.cerca_de(a)
                    if p:
                        self.pulsar(p)
                self.pasos(10)
                continue
            if not a.room:
                self.pasos(10)
                continue
            camino = self.camino_a(a.room, abrir)
            if camino is None:
                self.pasos(10)
                continue
            for oid in camino:
                self.salir_por(oid, abrir)
        raise Atasco("seguir: no se llega a la habitacion %d" % sala)

    def pelear(self, veces, nuestros, suyos, sala, reto, modo="aprender"):
        """En el mapa: ir hacia el pirata mas cercano hasta que empiece un duelo (la
        habitacion sala), decir el reto y jugarlo; veces duelos."""
        w = self.w
        mapa = w.room
        for n in range(veces):
            for _ in range(600):
                if w.room == sala and self.opciones():
                    break
                if w.room not in (mapa, sala):
                    # (se ha metido en un sitio del mapa: de vuelta por su camino)
                    if self.libre() and self.buscar("camino", self.objetos()) is not None:
                        self.pulsar_cosa("camino")
                        self.esperar()
                    self.pasos(6)
                    continue
                if w.room == mapa and self.libre():
                    g = self.ego()
                    otros = [i for i, _ in self.actores() if i != w.vm.vars[VAR_EGO]]
                    if otros:
                        i = min(otros, key=lambda i: abs(w.vm.actors[i].x - g.x) + abs(w.vm.actors[i].y - g.y))
                        p = self.cerca_de(w.vm.actors[i])
                        if p:
                            self.pulsar(p)
                self.pasos(15)
            else:
                raise Atasco("pelear: no aparece ningun pirata")
            guardar(self, "_antes_duelo")
            self.hacer("decir %s" % reto)
            self.duelo(nuestros, suyos, modo)
            self.esperar()
            print("    duelo %d: %d a %d, sabe %d (paso %d)" % (
                n + 1, w.vm.vars[nuestros], w.vm.vars[suyos], self.saber(), self.t))
            sys.stdout.flush()
            if w.room != mapa:
                self.esperar()
            if modo == "aprender" and getattr(self, "rangos", None) and                     not any(self.falta(k) for k in range(len(self.rangos))):
                print("    ya se sabe todo")
                break

    # --- ver lo que hay ---------------------------------------------------------------
    def ver(self):
        w = self.w
        print("  paso %d, habitacion %d, camara %d" % (self.t, w.room, w.cam_left() if w.room else 0))
        print("    verbos:", ["%d %s" % (v.verbid, self.nombre_verbo(v)) for _, v in self.verbos()])
        print("    inventario:", [n for _, n in self.inventario()])
        print("    objetos:", ["%d %s (%d,%d %dx%d) st%d" % (o.id, n, o.x * 8, o.y, o.w * 8, o.h, w.vm.state[o.id])
                               for o, n in self.objetos() if n])
        print("    actores:", ["%d %s (%d,%d)" % (i, n, w.vm.actors[i].x, w.vm.actors[i].y) for i, n in self.actores()])


def arranque():
    g, _ = C.find_game(T.ORIGINAL)
    hdr = open(os.path.join(T.SD_JUEGO, "GAME.DAT"), "rb").read()
    return Jugador(T.boot_world(g, g.costume(hdr[5])))


class _Guardar(pickle.Pickler):
    """Los modulos y las funciones locales de make_world (cargar habitaciones y
    costumes), por su nombre: al cargar, los de un mundo recien hecho."""
    def persistent_id(self, obj):
        if isinstance(obj, types.ModuleType):
            return ("mod", obj.__name__)
        if isinstance(obj, types.FunctionType) and "<locals>" in obj.__qualname__:
            return ("fn", obj.__qualname__)
        return None


class _Cargar(pickle.Unpickler):
    fns = None

    def persistent_load(self, pid):
        kind, name = pid
        if kind == "mod":
            return importlib.import_module(name)
        if _Cargar.fns is None:
            g, _ = C.find_game(T.ORIGINAL)
            hdr = open(os.path.join(T.SD_JUEGO, "GAME.DAT"), "rb").read()
            w = T.make_world(g, g.costume(hdr[5]), 0)
            _Cargar.fns = {f.__qualname__: f for f in w._init if isinstance(f, types.FunctionType)}
        return _Cargar.fns[name]


def guardar(j, nombre):
    os.makedirs(DIR, exist_ok=True)
    with open(os.path.join(DIR, "%s.pkl" % nombre), "wb") as f:
        _Guardar(f, protocol=pickle.HIGHEST_PROTOCOL).dump(j)


def cargar(nombre):
    with open(os.path.join(DIR, "%s.pkl" % nombre), "rb") as f:
        return _Cargar(f).load()


def leer(sol):
    return open(sol, encoding="utf-8").read().splitlines()


def jugar(sol, desde=None, ver=False):
    lineas = leer(sol)
    i0 = 0
    if desde:
        j = cargar(desde)
        i0 = next(i for i, l in enumerate(lineas) if l.strip() == "@ " + desde) + 1
    else:
        j = arranque()
    sala = None
    i = i0 - 1
    while i + 1 < len(lineas):
        i += 1
        l = lineas[i]
        try:
            if l.strip().lower().startswith("bucle "):
                fin = next(k for k in range(i + 1, len(lineas)) if lineas[k].strip().lower().startswith("hasta_que "))
                cond = lineas[fin].strip()[len("hasta_que "):]
                for vuelta in range(int(l.split()[1])):
                    for k in range(i + 1, fin):
                        j.hacer(lineas[k])
                    print("    vuelta %d de '%s' (paso %d)" % (vuelta + 1, cond, j.t))
                    sys.stdout.flush()
                    if j.condicion(cond)():
                        break
                else:
                    raise Atasco("bucle: no se cumple '%s'" % cond)
                i = fin
                continue
            if l.strip().startswith("@"):
                nombre = l.strip()[1:].strip()
                guardar(j, nombre)
                print("[%s] paso %d, habitacion %d" % (nombre, j.t, j.w.room))
                sys.stdout.flush()
                continue
            j.hacer(l)
        except Atasco as e:
            print("linea %d (%s): %s" % (i + 1, l.strip(), e))
            j.ver()
            guardar(j, "_atasco")
            return j, False
        if ver and j.w.room != sala:
            sala = j.w.room
            j.esperar()
            j.ver()
    print("fin: paso %d, habitacion %d" % (j.t, j.w.room))
    guardar(j, "_fin")
    return j, True


if __name__ == "__main__":
    import partida as P                     # (que lo guardado sea de partida.Jugador)
    a = sys.argv[1:]
    sol = a[0]
    desde = a[a.index("--desde") + 1] if "--desde" in a else None
    _, ok = P.jugar(sol, desde, ver="--ver" in a)
    sys.exit(0 if ok else 1)
