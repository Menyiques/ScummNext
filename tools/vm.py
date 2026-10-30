"""Maquina virtual de SCUMM v5: el modelo de referencia del interprete del Z80.

Sigue la semantica de SCUMM v5 tal como la documenta ScummVM:

- variables globales, de bit y locales (25 por script), con indice;
- ranuras de script (NSLOTS) que se ejecutan por turnos: breakHere, delay,
  wait; startScript / startObject / chainScript ejecutan anidado;
- tablas globales de objetos: estado, dueno y clases;
- cambio de habitacion: script de salida, se matan los scripts de la
  habitacion y despues el de entrada.

Los textos, los verbos, el cursor, las frases y el inventario los lleva
tools/ui.py. Las instrucciones de sonido y de paletas se decodifican y no
hacen nada. Los actores son una tabla: el protagonista (VAR_EGO) es el actor
que se ve y anda por las cajas cuando esta en la habitacion; los demas andan
en linea recta hacia su destino, sin verse. Todo en enteros de 16 bits.
"""
import opcodes as O
import sound as SN
import ui as U

NSLOTS = 20
NLOCALS = 25
MAXNEST = 12
NUM_ACTORS = 13
DELTA = 5                   # jiffies (1/60 s) por paso del motor
NUM_GLOBAL_SCRIPTS = 200    # los locales van del 200 en adelante

SS_DEAD, SS_PAUSED, SS_RUNNING = 0, 1, 2
WIO_INVENTORY, WIO_ROOM, WIO_GLOBAL, WIO_LOCAL = 0, 1, 2, 3
ROOM_EXIT, ROOM_ENTRY = 10001, 10002
OWNER_ROOM = 0x0F
CLASS_UNTOUCHABLE = 32

VAR_EGO, VAR_CAMERA_POS_X, VAR_HAVE_MSG, VAR_ROOM, VAR_OVERRIDE = 1, 2, 3, 4, 5
VAR_CURRENT_LIGHTS = 9
# resetScummVars (v5, Monkey Island): numero de variable -> valor al empezar
INIT_VARS = ((9, 11),           # VAR_CURRENT_LIGHTS: paleta base, colores, luces
             (37, 4),           # VAR_CHARINC
             (40, 1400),        # VAR_HEAPSPACE
             (48, 3),           # VAR_SOUNDCARD (AdLib)
             (49, 19),          # VAR_VIDEOMODE (VGA)
             (51, 1),           # VAR_FIXEDDISK
             (54, -0x50),       # VAR_V5_TALK_STRING_Y
             (59, 3),           # VAR_FADE_DELAY
             (67, 3),           # VAR_INPUTMODE (raton)
             (74, 1225))        # Monkey Island lo comprueba al arrancar (script 176)
VAR_TMR_1, VAR_TMR_2, VAR_TMR_3, VAR_MUSIC_TIMER = 11, 12, 13, 14
VAR_ACTOR_RANGE_MIN, VAR_ACTOR_RANGE_MAX = 15, 16
VAR_LAST_SOUND = 23
VAR_SCROLL_SCRIPT = 27
VAR_TIMER, VAR_TIMER_TOTAL = 46, 47
VAR_CAMERA_MIN_X, VAR_CAMERA_MAX_X = 17, 18
VAR_ROOM_RESOURCE = 22
VAR_ENTRY_SCRIPT, VAR_ENTRY_SCRIPT2 = 28, 29
VAR_EXIT_SCRIPT, VAR_EXIT_SCRIPT2 = 30, 31
VAR_SENTENCE_SCRIPT = 33
VAR_CHARINC = 37
VAR_WALKTO_OBJ = 38
VAR_CUTSCENE_START_SCRIPT, VAR_CUTSCENE_END_SCRIPT = 35, 36


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


class Slot:
    __slots__ = ("number", "where", "code", "pc", "status", "freeze_res", "recursive",
                 "freeze_count", "delay", "cs_override", "locals")

    def __init__(self):
        self.number = 0
        self.where = 0
        self.code = None            # (tipo, clave) del codigo
        self.pc = 0
        self.status = SS_DEAD
        self.freeze_res = False
        self.recursive = False
        self.freeze_count = 0
        self.delay = 0
        self.cs_override = 0
        self.locals = [0] * NLOCALS


def new_dir_to_old_dir(d):
    """newDirToOldDir: 0 izquierda, 1 derecha, 2 de frente, 3 de espaldas."""
    if 71 <= d <= 109:
        return 1
    if 109 <= d <= 251:
        return 2
    if 251 <= d <= 289:
        return 0
    return 3


def toward(a, b, step):
    """Un paso de a hacia b, como mucho step."""
    if a < b:
        return min(a + step, b)
    if a > b:
        return max(a - step, b)
    return a


class VM:
    """world: lo que la maquina ve de la habitacion y del actor (ver World en model.py)."""

    def __init__(self, scripts, objects, nvars=800, nbits=2048, world=None, charsets=None, verb_image=None,
                 sounds=None):
        self.scripts = scripts                      # {numero: bytes} globales
        self.sound = SN.Sound(sounds or {})         # lo que ven los scripts del sonido
        self.vars = [0] * nvars
        self.bits = bytearray((nbits + 7) // 8)
        self.slots = [Slot() for _ in range(NSLOTS)]
        self.nest = []
        self.cur = None                             # ranura en marcha (indice) o None
        self.state = [st for own, st, cl in objects]
        self.res_map = [0] * 128                    # pseudoRoom: habitacion 128+i -> la real
        self.owner = [own for own, st, cl in objects]
        self.classes = [cl for own, st, cl in objects]
        import model as M
        self.actors = [M.Actor(None, i, world) for i in range(NUM_ACTORS)]    # initActor(-1)
        for i in range(1, NUM_ACTORS):              # (y sin clases)
            if i < len(self.classes):
                self.classes[i] = 0
        self.cs_sp = 0
        self.cs_data = [0] * 6
        self.cs_ptr = [0] * 6
        self.cs_script = [0] * 6
        self.cs_index = None
        self.seed = 0x1234
        self.world = world
        self.room_code = {}                         # ('encd'|'excd'|n local|('obj', id)) -> bytes
        self.executed = 0
        self.ui = U.UI(self, charsets or {}, verb_image)
        for n, v in INIT_VARS:
            self.vars[n] = v

    # --- variables -------------------------------------------------------
    def var_number(self, spec):
        """('var', n, indice) -> numero de variable ya con el indice sumado."""
        _, n, idx = spec
        if idx is None:
            return n
        add = self.read_var(idx) if isinstance(idx, tuple) else idx
        return (((n | 0x2000) + add) & 0xFFFF) & ~0x2000

    def read_num(self, n):
        if not n & 0xF000:
            return self.vars[n] if n < len(self.vars) else 0
        if n & 0x8000:
            b = n & 0x7FFF
            return (self.bits[b >> 3] >> (b & 7)) & 1 if (b >> 3) < len(self.bits) else 0
        if n & 0x4000:
            k = n & 0xFFF
            if self.cur is None or k >= NLOCALS:
                return 0
            return self.slots[self.cur].locals[k]
        return 0

    def write_num(self, n, v):
        v = s16(v)
        if not n & 0xF000:
            if n < len(self.vars):
                self.vars[n] = v
        elif n & 0x8000:
            b = n & 0x7FFF
            if (b >> 3) < len(self.bits):
                if v:
                    self.bits[b >> 3] |= 1 << (b & 7)
                else:
                    self.bits[b >> 3] &= ~(1 << (b & 7)) & 0xFF
        elif n & 0x4000:
            k = n & 0xFFF
            if self.cur is not None and k < NLOCALS:
                self.slots[self.cur].locals[k] = v

    def read_var(self, spec):
        return self.read_num(self.var_number(spec))

    def val(self, a):
        if isinstance(a, tuple) and a[0] == "var":
            return self.read_var(a)
        return s16(a)

    def result(self, spec, v):
        self.write_num(self.var_number(spec[1]), v)

    def rand(self, mx):
        self.seed = (self.seed * 25173 + 13849) & 0xFFFF
        return ((self.seed >> 8) * ((mx & 0xFF) + 1)) >> 8

    # --- objetos -----------------------------------------------------------
    def owner_of(self, obj):
        return self.owner[obj] if 0 <= obj < len(self.owner) else 0

    def where_is(self, obj):
        """whereIsObject: WIO_ROOM, WIO_INVENTORY o None."""
        if not 0 < obj < len(self.owner):
            return None
        if self.owner[obj] != OWNER_ROOM:
            return WIO_INVENTORY if obj in self.ui.inventory else None
        if self.world is not None and self.world.object_in_room(obj):
            return WIO_ROOM
        return None

    def verb_table(self, obj, where):
        if where == WIO_INVENTORY:
            return self.ui.inv_data[obj][0]
        return self.room_code.get(("verbs", obj)) or []

    def verb_entry(self, obj, entry):
        """getVerbEntrypoint: la posicion del codigo del verbo (0 si no hay)."""
        where = self.where_is(obj)
        if where is None:
            return 0
        for v, o in self.verb_table(obj, where):
            if v == entry or v == 0xFF:
                return o
        return 0

    def get_state(self, obj):
        return self.state[obj] if 0 <= obj < len(self.state) else 0

    def put_state(self, obj, v):
        if 0 <= obj < len(self.state):
            self.state[obj] = v & 0xFF
            if self.world:
                self.world.object_changed(obj)

    def get_class(self, obj, cls):
        cls &= 0x7F
        if not (0 <= obj < len(self.classes)) or not 1 <= cls <= 32:
            return 0
        return (self.classes[obj] >> (cls - 1)) & 1

    def put_class(self, obj, cls, on):
        cls &= 0x7F
        if not (0 <= obj < len(self.classes)) or not 1 <= cls <= 32:
            return
        if on:
            self.classes[obj] |= 1 << (cls - 1)
        else:
            self.classes[obj] &= ~(1 << (cls - 1)) & 0xFFFFFFFF

    # --- ranuras -----------------------------------------------------------
    def free_slot(self):
        for i in range(1, NSLOTS):
            if self.slots[i].status == SS_DEAD:
                return i
        return None

    def running(self, script):
        for s in self.slots:
            if s.number == script and s.status != SS_DEAD and s.where in (WIO_GLOBAL, WIO_LOCAL):
                return 1
        return 0

    def stop_script(self, script):
        if not script:
            return
        for i, s in enumerate(self.slots):
            if s.number == script and s.status != SS_DEAD and s.where in (WIO_GLOBAL, WIO_LOCAL):
                s.number = 0
                s.status = SS_DEAD
                if self.cur == i:
                    self.cur = None
        for n in self.nest:
            if n[0] == script and n[1] in (WIO_GLOBAL, WIO_LOCAL):
                n[0], n[1], n[2] = 0xFF, 0xFF, 0xFF

    def stop_object_script(self, obj):
        if not obj:
            return
        for i, s in enumerate(self.slots):
            if s.number == obj and s.status != SS_DEAD and s.where in (WIO_ROOM, WIO_INVENTORY):
                s.number = 0
                s.status = SS_DEAD
                if self.cur == i:
                    self.cur = None
        for n in self.nest:
            if n[0] == obj and n[1] in (WIO_ROOM, WIO_INVENTORY):
                n[0], n[1], n[2] = 0xFF, 0xFF, 0xFF

    def start_slot(self, number, where, code, pc, args=(), freeze_res=False, recursive=False):
        i = self.free_slot()
        if i is None:
            return
        s = self.slots[i]
        s.number, s.where, s.code, s.pc = number, where, code, pc
        s.status = SS_RUNNING
        s.freeze_res, s.recursive = freeze_res, recursive
        s.freeze_count = 0
        s.delay = 0
        s.cs_override = 0
        s.locals = [s16(a) for a in list(args)[:NLOCALS]] + [0] * (NLOCALS - min(len(args), NLOCALS))
        self.run_nested(i)

    def run_script(self, script, freeze_res=False, recursive=False, args=()):
        if not script:
            return
        if not recursive:
            self.stop_script(script)
        if script < NUM_GLOBAL_SCRIPTS:
            if script not in self.scripts:
                return
            self.start_slot(script, WIO_GLOBAL, ("global", script), 0, args, freeze_res, recursive)
        else:
            if script not in self.room_code:
                return
            self.start_slot(script, WIO_LOCAL, ("room", script), 0, args, freeze_res, recursive)

    def run_object_script(self, obj, entry, args=()):
        if not obj:
            return
        self.stop_object_script(obj)
        where = self.where_is(obj)
        if where is None:
            return
        off = self.verb_entry(obj, entry)
        if not off:
            return
        code = ("inv", obj) if where == WIO_INVENTORY else ("room", ("obj", obj))
        self.start_slot(obj, where, code, off, args)

    def run_nested(self, i):
        if len(self.nest) >= MAXNEST:
            return
        if self.cur is None:
            entry = [0, 0xFF, 0xFF]
        else:
            s = self.slots[self.cur]
            entry = [s.number, s.where, self.cur]
        self.nest.append(entry)
        self.cur = i
        self.execute()
        self.nest.pop()
        if entry[0] and entry[0] != 0xFF:
            s = self.slots[entry[2]]
            if s.number == entry[0] and s.where == entry[1] and s.status != SS_DEAD and not s.freeze_count:
                self.cur = entry[2]
                return
        self.cur = None

    def code_of(self, s):
        kind, key = s.code
        if kind == "global":
            return self.scripts[key]
        if kind == "inv":
            return self.ui.inv_data[key][1]
        return self.room_code[key]

    def execute(self, limit=20000):
        n = 0
        while self.cur is not None:
            s = self.slots[self.cur]
            code = self.code_of(s)
            if s.pc >= len(code):
                self.stop_code()
                continue
            op, name, args, nxt = O.decode(code, s.pc)
            start = s.pc
            s.pc = nxt
            self.executed += 1
            self.op(op, name, args, start)
            n += 1
            if n >= limit:              # un script que no suelta: se para
                self.stop_code()

    def run_all(self):
        self.cur = None
        done = [False] * NSLOTS
        for i in range(NSLOTS):
            s = self.slots[i]
            if s.status == SS_RUNNING and not done[i]:
                done[i] = True
                self.cur = i
                self.execute()
        self.cur = None

    def decrease_delays(self, amount=DELTA):
        for s in self.slots:
            if s.status == SS_PAUSED:
                s.delay -= amount
                if s.delay < 0:
                    s.status = SS_RUNNING
                    s.delay = 0

    def timers(self, amount=DELTA):
        """Lo del principio de cada paso: relojes (el de la musica es el de la pista
        del CD que suena, como en ScummVM), los sonidos que se acaban y el texto."""
        for v in (VAR_TMR_1, VAR_TMR_2, VAR_TMR_3):
            self.vars[v] = s16(self.vars[v] + amount)
        self.vars[VAR_MUSIC_TIMER] = s16(self.sound.tick(amount))
        self.vars[VAR_TIMER] = amount
        self.vars[VAR_TIMER_TOTAL] = s16(self.vars[VAR_TIMER_TOTAL] + amount)
        self.ui.tick_delay(amount)

    def abort_cutscene(self):
        i = self.cs_sp
        if self.cs_ptr[i]:
            s = self.slots[self.cs_script[i]]
            if s.status == SS_DEAD:
                # el script del override ya no esta (lo paro un cambio de habitacion):
                # ScummVM lo volveria a poner en marcha en la posicion vieja, con
                # codigo que ya no es el suyo; aqui solo se olvida el override
                self.cs_ptr[i] = 0
                return
            s.pc = self.cs_ptr[i]
            s.status = SS_RUNNING
            s.freeze_count = 0
            if s.cs_override > 0:
                s.cs_override -= 1
            self.vars[VAR_OVERRIDE] = 1
            self.cs_ptr[i] = 0

    def in_room(self, act):
        return bool(0 < act < NUM_ACTORS and self.actors[act].in_room())

    def is_ego_here(self, act):
        return act == self.vars[VAR_EGO] and self.world is not None and self.in_room(act)

    def actor(self, act):
        """derefActor (None si no es un actor)."""
        return self.actors[act] if 0 < act < NUM_ACTORS else None

    def boxes(self):
        w = self.world
        return w.eng.boxes if w is not None and w.room and w.eng is not None else None

    def walk_actors(self):
        """walkActors: los de la habitacion, por orden."""
        bx = self.boxes()
        for i in range(1, NUM_ACTORS):
            a = self.actors[i]
            if a.in_room() and bx is not None:
                a.walk(bx)

    def actor_moving(self, act):
        a = self.actor(act)
        return a.moving if a is not None else 0

    def actor_xy(self, act):
        a = self.actor(act)
        return (a.x, a.y) if a is not None else (0, 0)

    def obj_xy(self, obj, k):
        """getObjX / getObjY."""
        if obj < 1:
            return 0
        if obj < NUM_ACTORS:
            return self.actor_xy(obj)[k]
        if self.where_is(obj) is None:
            return -1
        xy = self.world.object_or_actor_xy(obj) if self.world is not None else None
        return -1 if xy is None else xy[k]

    def process_sound(self):
        """processSound: la cola del paso (al final de cada paso, o con soundKludge(-1));
        una pista del CD que empieza pone VAR_MUSIC_TIMER a 0 (playCDTrack)."""
        started = self.sound.process()
        if any(k == SN.CD for k, _ in started):
            self.vars[VAR_MUSIC_TIMER] = 0
        return started

    def play_actor_sounds(self):
        """playActorSounds: el primer actor de la habitacion cuyo costume ha pasado
        por un comando de sonido ($78) pone el suyo (startSound) y se olvidan los
        de todos."""
        for i in range(1, NUM_ACTORS):
            a = self.actors[i]
            if a.sound_counter and a.in_room():
                self.vars[VAR_LAST_SOUND] = a.sound
                self.sound.start(a.sound)
                for b in self.actors[1:]:
                    b.sound_counter = 0
                return

    def stop_code(self):
        s = self.slots[self.cur]
        s.number = 0
        s.status = SS_DEAD
        self.cur = None

    def break_here(self):
        self.cur = None

    def freeze(self, flag):
        for i, s in enumerate(self.slots):
            if self.cur != i and s.status != SS_DEAD and (not s.freeze_res or flag >= 0x80):
                s.status |= 0x80
                s.freeze_count += 1
        if self.cs_index is not None:
            s = self.slots[self.cs_index]
            s.status &= 0x7F
            s.freeze_count = 0

    def unfreeze(self):
        for s in self.slots:
            if s.status & 0x80:
                s.freeze_count -= 1
                if not s.freeze_count:
                    s.status &= 0x7F

    # --- cambio de habitacion ------------------------------------------------------
    def kill_room_scripts(self):
        for s in self.slots:
            if s.where in (WIO_ROOM, WIO_LOCAL) and s.status != SS_DEAD:
                s.cs_override = 0
                s.status = SS_DEAD
                s.number = 0

    def run_exit(self):
        if self.vars[VAR_EXIT_SCRIPT]:
            self.run_script(self.vars[VAR_EXIT_SCRIPT])
        if "excd" in self.room_code:
            self.start_slot(ROOM_EXIT, WIO_ROOM, ("room", "excd"), 0)
        if self.vars[VAR_EXIT_SCRIPT2]:
            self.run_script(self.vars[VAR_EXIT_SCRIPT2])

    def run_entry(self):
        if self.vars[VAR_ENTRY_SCRIPT]:
            self.run_script(self.vars[VAR_ENTRY_SCRIPT])
        if "encd" in self.room_code:
            self.start_slot(ROOM_ENTRY, WIO_ROOM, ("room", "encd"), 0)
        if self.vars[VAR_ENTRY_SCRIPT2]:
            self.run_script(self.vars[VAR_ENTRY_SCRIPT2])

    def change_room_from_script(self, room, obj=0):
        """loadRoom desde un script: si el script es de la habitacion, muere."""
        if self.cur is not None:
            s = self.slots[self.cur]
            if s.where in (WIO_ROOM, WIO_LOCAL):
                self.cur = None
        saved = self.cur
        if self.world:
            self.world.start_scene(room, obj)
        self.cur = saved if saved is not None and self.slots[saved].status != SS_DEAD else None

    # --- instrucciones -----------------------------------------------------------
    def jump_if(self, cond, target):
        if not cond:
            self.slots[self.cur].pc = target

    def op(self, op, name, a, start):
        v = self.val
        w = self.world
        if name == "breakHere":
            self.break_here()
        elif name == "stopObjectCode":
            self.stop_code()
        elif name == "jumpRelative":
            self.slots[self.cur].pc = a[0][1]
        elif name in ("isEqual", "isNotEqual", "isLess", "isLessEqual", "isGreater", "isGreaterEqual"):
            x = self.read_var(a[0])
            y = v(a[1])
            cond = {"isEqual": y == x, "isNotEqual": y != x, "isLess": y < x,
                    "isLessEqual": y <= x, "isGreater": y > x, "isGreaterEqual": y >= x}[name]
            self.jump_if(cond, a[2][1])
        elif name == "equalZero":
            self.jump_if(self.read_var(a[0]) == 0, a[1][1])
        elif name == "notEqualZero":
            self.jump_if(self.read_var(a[0]) != 0, a[1][1])
        elif name == "move":
            self.result(a[0], v(a[1]))
        elif name in ("add", "subtract", "multiply", "divide", "and", "or"):
            n = self.var_number(a[0][1])
            x = self.read_num(n)
            y = v(a[1])
            if name == "add":
                r = x + y
            elif name == "subtract":
                r = x - y
            elif name == "multiply":
                r = x * y
            elif name == "divide":
                r = cdiv(x, y) if y else x
            elif name == "and":
                r = x & y
            else:
                r = x | y
            self.write_num(n, r)
        elif name in ("increment", "decrement"):
            n = self.var_number(a[0][1])
            self.write_num(n, self.read_num(n) + (1 if name == "increment" else -1))
        elif name == "setVarRange":
            n = self.var_number(a[0][1])
            for k, x in enumerate(a[1]):
                self.write_num(n + k, s16(x))
        elif name == "expression":
            dst = self.var_number(a[0][1])          # el destino se fija al empezar
            stack = []
            for item in a[1]:
                if item[0] == "push":
                    stack.append(v(item[1]))
                elif item[0] == "op":
                    y = stack.pop() if stack else 0
                    x = stack.pop() if stack else 0
                    k = item[1]
                    if k == 2:
                        r = x + y
                    elif k == 3:
                        r = x - y
                    elif k == 4:
                        r = x * y
                    else:
                        r = cdiv(x, y) if y else 0
                    stack.append(s16(r))
                else:
                    iname, iargs = item[1]
                    self.op(None, iname, iargs, start)
                    stack.append(self.vars[0])
            self.write_num(dst, stack.pop() if stack else 0)
        elif name == "getRandomNr":
            self.result(a[0], self.rand(v(a[1])))
        elif name == "delay":
            s = self.slots[self.cur]
            s.delay = a[0]
            s.status = SS_PAUSED
            self.break_here()
        elif name == "delayVariable":
            s = self.slots[self.cur]
            s.delay = self.read_var(a[0])
            s.status = SS_PAUSED
            self.break_here()
        elif name == "wait":
            k = a[0][1]
            again = False
            if k == 1:
                again = bool(self.actor_moving(v(a[1])))
            elif k == 2:
                again = bool(self.vars[VAR_HAVE_MSG])
            elif k == 3:
                again = w is not None and w.camera_moving()
            elif k == 4:
                again = self.ui.sentence_busy()
            if again:
                self.slots[self.cur].pc = start
                self.break_here()
        elif name == "isScriptRunning":
            self.result(a[0], self.running(v(a[1])))
        elif name == "startScript":
            flags = a[2][1]
            self.run_script(v(a[0]), bool(flags & 0x20), bool(flags & 0x40), [v(x) for x in a[1]])
        elif name == "chainScript":
            script = v(a[0])
            args = [v(x) for x in a[1]]
            s = self.slots[self.cur]
            fr, rec = s.freeze_res, s.recursive
            s.number = 0
            s.status = SS_DEAD
            self.cur = None
            self.run_script(script, fr, rec, args)
        elif name == "stopScript":
            script = v(a[0])
            if not script:
                self.stop_code()
            else:
                self.stop_script(script)
        elif name == "freezeScripts":
            f = v(a[0])
            if f:
                self.freeze(f)
            else:
                self.unfreeze()
        elif name == "cutscene":
            args = [v(x) for x in a[0]]
            s = self.slots[self.cur]
            s.cs_override += 1
            if self.cs_sp < 5:
                self.cs_sp += 1
            self.cs_data[self.cs_sp] = args[0] if args else 0
            self.cs_script[self.cs_sp] = 0
            self.cs_ptr[self.cs_sp] = 0
            self.cs_index = self.cur
            if self.vars[VAR_CUTSCENE_START_SCRIPT]:
                self.run_script(self.vars[VAR_CUTSCENE_START_SCRIPT], args=args)
            self.cs_index = None
        elif name == "endCutscene":
            s = self.slots[self.cur]
            if s.cs_override > 0:
                s.cs_override -= 1
            args = [self.cs_data[self.cs_sp]]
            self.vars[VAR_OVERRIDE] = 0
            if self.cs_ptr[self.cs_sp] and s.cs_override > 0:
                s.cs_override -= 1
            self.cs_script[self.cs_sp] = 0
            self.cs_ptr[self.cs_sp] = 0
            if self.cs_sp > 0:
                self.cs_sp -= 1
            if self.vars[VAR_CUTSCENE_END_SCRIPT]:
                self.run_script(self.vars[VAR_CUTSCENE_END_SCRIPT], args=args)
        elif name == "beginOverride":
            self.cs_ptr[self.cs_sp] = start + 2
            self.cs_script[self.cs_sp] = self.cur
            self.vars[VAR_OVERRIDE] = 0
        elif name == "endOverride":
            self.cs_ptr[self.cs_sp] = 0
            self.cs_script[self.cs_sp] = 0
            self.vars[VAR_OVERRIDE] = 0
        elif name == "startObject":
            self.run_object_script(v(a[0]), v(a[1]) & 0xFF, [v(x) for x in a[2]])
        elif name == "stopObjectScript":
            self.stop_object_script(v(a[0]))
        # --- objetos ---
        elif name == "setState":
            if w is not None:
                w.draw_top(v(a[0]), False)          # (otra vez en el orden de los indices)
            self.put_state(v(a[0]), v(a[1]))
        elif name == "getObjectState":
            self.result(a[0], self.get_state(v(a[1])))
        elif name in ("ifState", "ifNotState"):
            st = self.get_state(v(a[0]))
            want = v(a[1])
            self.jump_if(st == want if name == "ifState" else st != want, a[2][1])
        elif name == "drawObject":
            obj = v(a[0])
            st = 1
            if a[1][1] & 0x1F == 2:
                st = v(a[2])
            if a[1][1] & 0x1F == 1 and v(a[2]) != 0xFF and w is not None:
                w.move_object(obj, v(a[2]), v(a[3]))      # setXY
            if w is not None and w.object_in_room(obj):
                for other in w.same_rect(obj):
                    self.put_state(other, 0)
                w.draw_top(obj, True)
                self.put_state(obj, st)
        elif name == "setOwnerOf":
            obj = v(a[0])
            own = v(a[1]) & 0xFF
            if 0 <= obj < len(self.owner):
                if own == 0:
                    self.stop_object_script(obj)
                    if self.owner[obj] != OWNER_ROOM:
                        self.ui.clear_owner(obj)
                self.owner[obj] = own
            self.ui.run_inventory_script(0)
        elif name == "getObjectOwner":
            obj = v(a[1])
            self.result(a[0], self.owner[obj] if 0 <= obj < len(self.owner) else 0)
        elif name == "pickupObject":
            obj = v(a[0])
            self.ui.add_to_inventory(obj)
            if 0 <= obj < len(self.owner):
                self.owner[obj] = self.vars[VAR_EGO] & 0xFF
            self.put_class(obj, CLASS_UNTOUCHABLE, True)
            if w is not None:
                w.draw_top(obj, False)
            self.put_state(obj, 1)
            self.ui.run_inventory_script(1)
        elif name == "setClass":
            obj = v(a[0])
            for c in a[1]:
                cls = v(c)
                if (cls & 0xFF) == 0:
                    if 0 <= obj < len(self.classes):
                        self.classes[obj] = 0
                else:
                    self.put_class(obj, cls, bool(cls & 0x80))
        elif name == "ifClassOfIs":
            obj = v(a[0])
            cond = True
            for c in a[1]:
                cls = v(c)
                b = self.get_class(obj, cls)
                if (cls & 0x80 and not b) or (not cls & 0x80 and b):
                    cond = False
            self.jump_if(cond, a[2][1])
        elif name == "findObject":
            self.result(a[0], w.find_object(v(a[1]), v(a[2])) if w else 0)
        elif name == "getInventoryCount":
            self.result(a[0], self.ui.inventory_count(v(a[1]) & 0xFF))
        elif name == "findInventory":
            self.result(a[0], self.ui.find_inventory(v(a[1]) & 0xFF, v(a[2]) & 0xFF))
        elif name == "getVerbEntrypoint":
            self.result(a[0], self.verb_entry(v(a[1]), v(a[2])))
        elif name == "doSentence":
            if len(a) == 1:
                self.ui.do_sentence(0xFE, 0, 0)
            else:
                self.ui.do_sentence(v(a[0]) & 0xFF, v(a[1]), v(a[2]))
        elif name == "verbOps":
            self.ui.verb_ops(v(a[0]) & 0xFF, a[1:])
        elif name == "saveRestoreVerbs":
            self.ui.save_restore_verbs(a[0][1], v(a[1]) & 0xFF, v(a[2]) & 0xFF, v(a[3]) & 0xFF)
        elif name == "cursorCommand":
            self.ui.cursor_command(a[0][1], a[1:])
        elif name == "stringOps":
            self.ui.string_ops(a)
        elif name == "setObjectName":
            self.ui.set_object_name(v(a[0]), a[1][1])
        elif name == "resourceRoutines":
            if a[0][1] & 0x3F == 18:
                self.ui.load_charset(v(a[1]) & 0xFF)
        elif name == "drawBox":
            if w is not None:
                w.draw_box(v(a[0]), v(a[1]), v(a[2]), v(a[3]), v(a[4]) & 0xFF)
        # --- habitacion ---
        elif name == "pseudoRoom":                  # (las que valen 128 o mas)
            for j in a[1]:
                if j >= 0x80:
                    self.res_map[j & 0x7F] = a[0]
        elif name == "loadRoom":
            self.change_room_from_script(v(a[0]) & 0xFF)
        elif name == "loadRoomWithEgo":
            obj = v(a[0])
            room = v(a[1]) & 0xFF
            x, y = s16(a[2]), s16(a[3])
            ego = self.actor(self.vars[VAR_EGO])
            if ego is not None and w is not None:
                ego.put_actor(ego.x, ego.y, room)
                w.ego_positioned = False
                self.vars[VAR_WALKTO_OBJ] = obj
                self.change_room_from_script(ego.room, obj)
                self.vars[VAR_WALKTO_OBJ] = 0
                if w.room:
                    c = w.eng.cam
                    c.cur = c.dest = ego.x
                    w.camera_follows(ego.number)
                    if x != -1:
                        ego.start_walk(w.eng.boxes, x, y, -1)
        elif name == "lights":
            if a[2] == 0:
                self.vars[VAR_CURRENT_LIGHTS] = v(a[0])
        elif name == "roomOps" and a[0][1] == 1:
            # roomScroll: los dos entre 160 y el ancho - 160 (o5_roomOps; con el ancho
            # de la ultima habitacion cargada)
            top = (w.room_w if w is not None else 0) - 160
            x1, x2 = v(a[1]), v(a[2])
            self.vars[VAR_CAMERA_MIN_X] = min(max(x1, 160), top)
            self.vars[VAR_CAMERA_MAX_X] = min(max(x2, 160), top)
        elif name == "systemOps":
            k = a[0] & 0xFF
            if w is not None:
                if k == 1:
                    w.restart_req = True        # (se reinicia al empezar el paso siguiente)
                elif k == 3:
                    w.quit_req = True
        elif name == "roomOps" and a[0][1] == 4:
            if w is not None:
                w.set_pal_color(v(a[5]), v(a[1]), v(a[2]), v(a[3]))
        elif name == "roomOps" and a[0][1] in (5, 6):
            if w is not None:
                w.set_shake(a[0][1] == 5)
        elif name == "roomOps" and a[0][1] == 8:
            if w is not None:
                s = v(a[1]) & 0xFF
                w.darken(s, s, s, v(a[2]) & 0xFF, v(a[3]) & 0xFF)
        elif name == "roomOps" and a[0][1] == 10:
            if w is not None:
                w.room_effect(v(a[1]))
        elif name == "roomOps" and a[0][1] == 11:
            if w is not None:
                w.darken(v(a[1]), v(a[2]), v(a[3]), v(a[5]) & 0xFF, v(a[6]) & 0xFF)
        elif name == "roomOps" and a[0][1] == 3:
            if w is not None:
                w.set_screen(v(a[1]), v(a[2]))
        elif name == "matrixOps" and a[0][1] in (1, 2, 3, 4):
            if w is not None:
                if a[0][1] == 1:
                    w.set_box_flags(v(a[1]), v(a[2]))
                elif a[0][1] == 4:
                    w.create_box_matrix()
                else:
                    w.set_box_scale(v(a[1]), v(a[2]))
        # --- actores (las de ScummVM 2.8, con Actor de model.py) ---
        elif name == "putActor":
            act = self.actor(v(a[0]) & 0xFF)
            if act is not None:
                act.put_actor(s16(v(a[1])), s16(v(a[2])), act.room)
        elif name == "walkActorTo":
            act = self.actor(v(a[0]) & 0xFF)
            if act is not None:
                act.start_walk(self.boxes(), s16(v(a[1])), s16(v(a[2])), -1)
        elif name == "walkActorToObject":
            act = self.actor(v(a[0]) & 0xFF)
            obj = v(a[1])
            if act is not None and self.where_is(obj) is not None and w is not None:
                xyd = w.object_walk_xyd(obj)
                if xyd is not None:
                    act.start_walk(self.boxes(), xyd[0], xyd[1], xyd[2])
        elif name == "putActorAtObject":
            act = self.actor(v(a[0]) & 0xFF)
            obj = v(a[1])
            if act is not None:
                xy = w.object_walk_xy(obj) if w is not None and self.where_is(obj) is not None else None
                x, y = xy if xy is not None else (240, 120)
                act.put_actor(x, y, act.room)
        elif name == "walkActorToActor":
            act, act2 = self.actor(v(a[0]) & 0xFF), self.actor(v(a[1]) & 0xFF)
            dist = a[2]
            if act is not None and act.in_room() and act2 is not None and act2.in_room():
                if dist == 0xFF:
                    dist = act.scalex * act.width // 0xFF
                    dist += (act2.scalex * act2.width // 0xFF) // 2
                x, y = act2.x, act2.y
                x = x + dist if x < act.x else x - dist
                act.start_walk(self.boxes(), s16(x), y, -1)
        elif name == "putActorInRoom":
            act = self.actor(v(a[0]) & 0xFF)
            room = v(a[1]) & 0xFF
            if act is not None:
                if act.visible and (w.room if w else 0) != room and self.ui.talking_actor() == act.number:
                    self.ui.stop_talk()
                act.room = room
                if not room:
                    act.put_actor(0, 0, 0)
        elif name == "faceActor":
            act = self.actor(v(a[0]) & 0xFF)
            if act is not None:
                act.face_to(v(a[1]))
        elif name == "animateActor":
            act = self.actor(v(a[0]) & 0xFF)
            if act is not None:
                act.animate_actor(v(a[1]))
        elif name == "actorOps":
            act = self.actor(v(a[0]) & 0xFF)
            for k, params in a[1:]:
                if act is None:
                    continue
                pv = [v(x) for x in params] if k != 13 else []
                if k == 1:
                    act.set_costume(pv[0])
                elif k == 2:
                    act.set_walk_speed(pv[0] & 0xFF, pv[1] & 0xFF)
                elif k == 3:
                    act.sound = pv[0] & 0xFF
                elif k == 4:
                    act.walk_frame = pv[0] & 0xFF
                elif k == 5:
                    act.talk_start, act.talk_stop = pv[0] & 0xFF, pv[1] & 0xFF
                elif k == 6:
                    act.stand_frame = pv[0] & 0xFF
                elif k == 8:
                    act.init_actor(0)
                elif k == 9:
                    act.elevation = s16(pv[0])
                elif k == 10:
                    act.init_frame, act.walk_frame, act.stand_frame = 1, 2, 3
                    act.talk_start, act.talk_stop = 4, 5
                elif k == 11:
                    if 0 <= (pv[0] & 0xFF) < 32:
                        act.palette[pv[0] & 0xFF] = pv[1] & 0xFF
                elif k == 12:
                    act.talk_color = pv[0] & 0xFF
                elif k == 13:
                    self.ui.actor_names[act.number] = bytes(params[0][1])
                elif k == 14:
                    act.init_frame = pv[0] & 0xFF
                elif k == 16:
                    act.width = pv[0] & 0xFF
                elif k == 17:
                    act.boxscale = pv[0] & 0xFF
                    act.scalex, act.scaley = pv[0] & 0xFF, pv[1] & 0xFF
                elif k == 18:
                    act.force_clip = 0
                elif k == 19:
                    act.force_clip = pv[0] & 0xFF
                elif k in (20, 21):
                    act.ignore_boxes = k == 20
                    act.force_clip = 0
                    if act.in_room():
                        act.put_actor(act.x, act.y, act.room)
                elif k == 22:
                    act.anim_speed = pv[0] & 0xFF
                    act.anim_progress = 0
        elif name in ("getActorX", "getActorY"):
            self.result(a[0], self.obj_xy(v(a[1]), 0 if name == "getActorX" else 1))
        elif name == "getActorRoom":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], act.room if act is not None else 0)
        elif name == "getActorCostume":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], act.costume if act is not None else 0)
        elif name == "getActorMoving":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], act.moving if act is not None else 0)
        elif name == "getActorElevation":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], act.elevation if act is not None else 0)
        elif name == "getActorFacing":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], new_dir_to_old_dir(act.facing) if act is not None else 0)
        elif name == "getActorWalkBox":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], act.box if act is not None else 0)
        elif name == "getActorWidth":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], act.width if act is not None else 0)
        elif name == "getActorScale":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], act.scalex if act is not None else 0)
        elif name == "getAnimCounter":
            act = self.actor(v(a[1]) & 0xFF)
            self.result(a[0], act.anim_counter if act is not None else 0)
        elif name == "actorFromPos":
            self.result(a[0], w.actor_from_pos(s16(v(a[1])), s16(v(a[2]))) if w is not None and w.room else 0)
        elif name == "getDist":
            self.result(a[0], w.obj_act_dist(v(a[1]), v(a[2])) if w is not None else 0xFF)
        elif name == "getClosestObjActor":
            act = v(a[1])
            best, best_d = 0xFF, 0xFF
            obj = self.vars[VAR_ACTOR_RANGE_MAX]
            while True:
                d = w.obj_act_dist(act, obj) if w is not None else 0xFF
                if d < best_d:
                    best_d, best = d, obj
                obj -= 1
                if obj < self.vars[VAR_ACTOR_RANGE_MIN]:
                    break
            self.result(a[0], best)
        elif name in ("getStringWidth",):
            self.result(a[0], 0)
        elif name == "isActorInBox":
            act = self.actor(v(a[0]) & 0xFF)
            box = v(a[1]) & 0xFF
            bx = self.boxes()
            cond = act is not None and bx is not None and bx.in_box(box, act.x, act.y)
            self.jump_if(cond, a[2][1])
        elif name == "print":
            self.ui.decode_print(v(a[0]) & 0xFF, a[1])
        elif name == "printEgo":
            self.ui.decode_print(self.vars[VAR_EGO] & 0xFF, a[0])
        # --- sonido (Sound de ScummVM: tools/sound.py) ---
        elif name == "startSound":
            n = v(a[0]) & 0xFF
            self.vars[VAR_MUSIC_TIMER] = 0
            self.vars[VAR_LAST_SOUND] = n
            self.sound.start(n)
        elif name == "startMusic":
            n = v(a[0]) & 0xFF
            self.vars[VAR_LAST_SOUND] = n
            self.sound.start(n)
        elif name == "stopSound":
            self.sound.stop(v(a[0]))
        elif name == "stopMusic":
            self.sound.stop_all()
        elif name == "isSoundRunning":
            self.result(a[0], self.sound.running(v(a[1])))
        elif name == "soundKludge":
            items = [v(x) for x in a[0]]
            if items and s16(items[0]) == -1:
                self.process_sound()
        elif name == "setCameraAt":
            if w is not None:
                w.camera_at(v(a[0]))
        elif name == "panCameraTo":
            if w is not None:
                w.camera_pan(v(a[0]))
        elif name == "actorFollowCamera":
            act = v(a[0])
            if w is not None and 0 < act < NUM_ACTORS:
                old = w.cam_follows()
                w.camera_follows(act)
                if w.cam_follows() != old:
                    self.ui.run_inventory_script(0)
        # el resto (sonido, paletas...) no hace nada todavia
