"""La interfaz de SCUMM v5 en el modelo: textos, verbos, cursor, frases e inventario.

Sigue a ScummVM (string.cpp, verbs.cpp, charset.cpp, script_v5.cpp):

- seis ranuras de texto (_string) con sus valores por defecto; print habla
  (CHARSET_1: saltos de linea, esperas, texto que se queda) o dibuja texto
  de sistema (drawString);
- las fuentes (tools/charset.py) con su mapa de colores (_charsetData);
- cien ranuras de verbo: de texto (con escapes que se resuelven al pintar) o
  de imagen (la imagen 1 de un objeto de otra habitacion);
- el cursor y userput, la entrada (raton y teclas -> script de verbos),
  la pila de frases y el script de frases;
- el inventario: la lista de objetos y una copia de su codigo y su nombre.

La pantalla de verdad la lleva la superficie (World.surface): aqui solo se
dice que pixel va donde. Coordenadas de pantalla: x de 0 a 319, y de 0 a
199; la pantalla principal va de 0 a main_h y la de verbos de main_h a 200.
"""

NUM_VERBS = 100
NUM_INVENTORY = 80
NUM_NEW_NAMES = 150
NUM_STRINGS = 50
NUM_CHARSETS = 8
SCREEN_W = 320

VAR_KEYPRESS = 0
VAR_CAMERA_POS_X = 2
VAR_HAVE_MSG = 3
VAR_VIRT_MOUSE_X, VAR_VIRT_MOUSE_Y = 20, 21
VAR_CUTSCENEEXIT_KEY = 24
VAR_TALK_ACTOR = 25
VAR_VERB_SCRIPT, VAR_SENTENCE_SCRIPT, VAR_INVENTORY_SCRIPT = 32, 33, 34
VAR_CHARINC = 37
VAR_MOUSE_X, VAR_MOUSE_Y = 44, 45
VAR_TIMER, VAR_TIMER_TOTAL = 46, 47
VAR_CURSORSTATE, VAR_USERPUT = 52, 53
VAR_V5_TALK_STRING_Y = 54
VAR_TALKSTOP_KEY = 57

AREA_VERB, AREA_SCENE, AREA_INVENTORY, AREA_KEY = 1, 2, 3, 4
TEXT_VERB, IMAGE_VERB = 0, 1
MAIN, VERBS = 0, 1                      # pantallas virtuales


class StringSlot:
    FIELDS = ("xpos", "ypos", "right", "color", "charset", "center", "overhead", "no_talk_anim")

    def __init__(self):
        self.xpos, self.ypos, self.right, self.color = 2, 5, SCREEN_W - 1, 15
        self.charset, self.center, self.overhead, self.no_talk_anim = 0, False, False, False

    def copy_from(self, o):
        for f in self.FIELDS:
            setattr(self, f, getattr(o, f))


class StringTab:
    def __init__(self):
        self.cur = StringSlot()
        self.default = StringSlot()

    def load_default(self):
        self.cur.copy_from(self.default)

    def save_default(self):
        self.default.copy_from(self.cur)


class VerbSlot:
    def __init__(self):
        self.verbid = 0
        self.left = self.top = 0
        self.right = self.bottom = 0
        self.old = None                         # (izq, arriba, der, abajo) pintado, o None
        self.color = self.hicolor = self.dimcolor = self.bkcolor = 0
        self.type = TEXT_VERB
        self.charset = 0
        self.curmode = 0
        self.saveid = 0
        self.key = 0
        self.center = 0
        self.imgindex = 0
        self.name = None                        # bytes (con escapes) o None
        self.image = None                       # (objeto, habitacion) o None

    def clone(self):
        v = VerbSlot()
        v.__dict__.update(self.__dict__)
        return v


def union(a, b):
    if a is None:
        return b
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def res_str_len(src):
    """resStrLen: bytes antes del 0 que termina la cadena; un 0 dentro de un escape
    ($FF, codigo y, salvo 1, 2, 3 y 8, dos bytes) no cuenta. Sin 0: todo."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == 0:
            return i
        i += 1
        if c == 0xFF:
            k = src[i] if i < n else 0
            i += 1 if k in (1, 2, 3, 8) else 3
    return n


class UI:
    """vm: la maquina virtual; world: el mundo (habitacion, camara, superficie)."""

    def __init__(self, vm, charsets, verb_image=None):
        self.vm = vm
        self.charsets = charsets                # {n: Charset}
        self.verb_image = verb_image            # (habitacion, objeto) -> (w, h, pix, opaco) o None
        self.strings = [StringTab() for _ in range(6)]
        self.charset_data = [[0] * 16 for _ in range(NUM_CHARSETS)]
        self.charset_loaded = [False] * NUM_CHARSETS
        self.cmap = [0] * 16
        self.cur_id = 0
        self.verbs = [VerbSlot() for _ in range(NUM_VERBS)]
        self.verb_mouse_over = 0
        self.cursor_state = 0
        self.userput = 0
        self.string_res = {}
        self.new_names = [0] * NUM_NEW_NAMES
        self.new_name_res = [None] * NUM_NEW_NAMES
        self.actor_names = {}
        self.inventory = [0] * NUM_INVENTORY
        self.inv_data = {}                      # objeto -> (verbos [(v, off)], codigo, nombre)
        self.sentence = []                      # [verbo, a, b, preposicion, congelada]
        self.mouse = (0, 0)
        self.mouse_kb = 0                       # _mouseAndKeyboardStat: tecla o 0x8000|boton
        self.main_h = 144
        # texto
        self.have_msg = 0
        self.talk_delay = 0
        self.keep_text = False
        self.use_talk_anims = False
        self.charset_color = 0
        self.buf = b""
        self.buf_pos = 0
        self.next_left = self.next_top = 0
        self.left = self.top = self.start_left = 0
        self.right = SCREEN_W - 1
        self.center = False
        self.first_char = True
        self.disable_offs_x = False
        self.str_rect = [0, 0, 0, 0]
        self.color = 0
        self.has_mask = False
        self.mask_screen = MAIN
        self.mask_rect = None                   # texto en la principal: (x0, y0, x1, y1), x de habitacion
        self.verb_rect = None                   # texto que se borra en la de verbos (x, y de pantalla)
        self.cam_last = 0

    # --- pantallas virtuales ------------------------------------------------
    @property
    def world(self):
        return self.vm.world

    def find_vs(self, y):
        if 0 <= y < self.main_h:
            return MAIN
        if self.main_h <= y < 200:
            return VERBS
        return None

    def vs_top(self, vs):
        return 0 if vs == MAIN else self.main_h

    def vs_h(self, vs):
        return self.main_h if vs == MAIN else 200 - self.main_h

    def xstart(self):
        return self.world.cam_left() if self.world and self.world.room else 0

    def put_pixel(self, vs, x, y, c, text=False):
        """x de pantalla, y dentro de la pantalla virtual; text: con mascara (su capa)."""
        if self.world is not None:
            self.world.surface_px(vs, x, y, c, text)

    # --- fuentes ----------------------------------------------------------------
    def load_charset(self, n):
        if not 0 < n < NUM_CHARSETS or n not in self.charsets:
            return
        cs = self.charsets[n]
        for i in range(15):
            self.charset_data[n][i + 1] = cs.colors[i]
        self.charset_loaded[n] = True

    def init_charset(self, n):
        if not 0 < n < NUM_CHARSETS:
            return
        if not self.charset_loaded[n]:
            self.load_charset(n)
        self.strings[0].default.charset = n
        self.strings[1].default.charset = n
        self.cmap = list(self.charset_data[n])

    def set_cur_id(self, n):
        self.cur_id = n

    def cs(self):
        return self.charsets.get(self.cur_id)

    def font_height(self):
        c = self.cs()
        return c.height if c else 0

    def char_width(self, c):
        cs = self.cs()
        return cs.char_width(c) if cs else 0

    def string_width(self, text, pos=0):
        width = 1
        while pos < len(text):
            c = text[pos]
            pos += 1
            if c == 0 or c == 13:
                break
            if c == ord("@"):
                continue
            if c in (0xFF, 0xFE):
                c = text[pos] if pos < len(text) else 0
                pos += 1
                if c == 3:
                    break
                if c in (10, 12, 13):
                    pos += 2
                    continue
                if c in (9, 1, 2):
                    break
                if c == 14:
                    pos += 2
                    continue
                if c == 8:
                    while pos < len(text) and text[pos] == 32:
                        pos += 1
                    pos += 1
                    continue
            width += self.char_width(c)
        return width

    def add_linebreaks(self, buf, pos, maxwidth):
        """Cambia el ultimo espacio de cada linea demasiado larga por un 13."""
        buf = bytearray(buf)
        lastspace = -1
        curw = 1
        while pos < len(buf):
            c = buf[pos]
            pos += 1
            if c == 0:
                break
            if c == ord("@"):
                continue
            if c in (0xFF, 0xFE):
                c = buf[pos] if pos < len(buf) else 0
                pos += 1
                if c == 3 or c == 2:
                    break
                if c == 1 or c == 8:
                    curw = 1
                    continue
                if c in (10, 12, 13, 9, 14):
                    pos += 2
                    continue
            if c == 32:
                lastspace = pos - 1
            curw += self.char_width(c)
            if lastspace == -1:
                continue
            if curw > maxwidth:
                buf[lastspace] = 13
                curw = 1
                pos = lastspace + 1
                lastspace = -1
        return bytes(buf)

    # --- mensajes: escapes ----------------------------------------------------
    def convert(self, msg, depth=0):
        """convertMessageToString: resuelve 4 (numero), 5 (verbo), 6 (nombre), 7 (cadena)."""
        out = bytearray()
        i = 0
        msg = bytes(msg or b"")
        while i < len(msg):
            c = msg[i]
            i += 1
            if c == 0:
                break
            if c in (0xFF, 0xFE):
                k = msg[i] if i < len(msg) else 0
                i += 1
                if k in (1, 2, 3, 8):
                    out += bytes((0xFF, k))
                    continue
                val = msg[i] | msg[i + 1] << 8 if i + 1 < len(msg) else 0
                i += 2
                if depth > 3:
                    continue
                if k == 4:
                    out += str(self.vm.read_num(val)).encode()
                elif k == 5:
                    out += self.verb_text(self.vm.read_num(val), depth)
                elif k == 6:
                    out += self.name_text(self.vm.read_num(val), depth)
                elif k == 7:                        # (en v5, la cadena misma: no una variable)
                    out += self.string_text(val, depth)
                else:
                    out += bytes((0xFF, k, val & 0xFF, val >> 8))
            elif c != ord("@"):
                out.append(c)
        return bytes(out)

    def verb_text(self, num, depth):
        if num:
            for k in range(1, NUM_VERBS):
                v = self.verbs[k]
                if v.verbid == num and v.type == TEXT_VERB and not v.saveid:
                    return self.convert(v.name, depth + 1)
        return b""

    def name_text(self, num, depth):
        if num:
            nm = self.obj_or_actor_name(num)
            if nm is not None:
                return self.convert(nm, depth + 1)
        return b""

    def string_text(self, num, depth):
        if num and num in self.string_res:
            return self.convert(self.string_res[num], depth + 1)
        return b""

    def obj_or_actor_name(self, obj):
        V = self.vm
        if 0 < obj < len(V.actors):
            return self.actor_names.get(obj, b"")
        for i in range(NUM_NEW_NAMES):
            if self.new_names[i] == obj:
                return self.new_name_res[i]
        if obj in self.inv_data and obj in self.inventory:
            return self.inv_data[obj][2]
        if self.world is not None:
            return self.world.object_name(obj)
        return None

    # --- dibujar caracteres -----------------------------------------------------
    def print_char(self, c, ignore_mask):
        vs = self.find_vs(self.top)
        if vs is None:
            vs = self.find_vs(self.top + self.font_height())
            if vs is None:
                return
        if c == ord("@"):
            return
        self.cmap[1] = self.color
        cs = self.cs()
        g = cs.glyph(c) if cs else None
        if g is None:
            return
        w, h, dx, dy, px = g
        if self.disable_offs_x:
            dx = 0
        if self.first_char:
            self.str_rect = [0, 0, 0, 0]
        self.top += dy
        self.left += dx
        if self.left + w > self.right + 1 or self.left < 0:
            self.left += w
            self.top -= dy
            return
        self.disable_offs_x = False
        if self.first_char:
            self.str_rect = [self.left, self.top, self.left, self.top]
            self.first_char = False
        self.str_rect[0] = min(self.str_rect[0], self.left)
        self.str_rect[1] = min(self.str_rect[1], self.top)
        draw_top = self.top - self.vs_top(vs)
        vh = self.vs_h(vs)
        if not ignore_mask:
            self.has_mask = True
            self.mask_screen = vs
        if not ignore_mask:                 # el texto de sistema (drawString) se queda
            if vs == MAIN:
                rx0 = self.left + self.xstart()
                self.mask_rect = union(self.mask_rect, (rx0, self.top, rx0 + w, self.top + h))
            else:
                self.verb_rect = union(self.verb_rect, (self.left, self.top, self.left + w, self.top + h))
        text = not ignore_mask and vs == MAIN
        for y in range(h):
            yy = draw_top + y
            if yy >= vh:
                break
            if yy < 0:
                continue
            row = px[y]
            for x in range(w):
                p = row[x]
                if p:
                    self.put_pixel(vs, self.left + x, yy, self.cmap[p], text)
        self.left += w
        if self.str_rect[2] < self.left:
            self.str_rect[2] = self.left
        if self.str_rect[3] < self.top + h:
            self.str_rect[3] = self.top + h
        self.top -= dy

    def restore_charset_bg(self):
        """Borra todo el texto de la pantalla del ultimo texto que se borra."""
        self.next_left = self.strings[0].cur.xpos
        self.next_top = self.strings[0].cur.ypos
        if self.has_mask:
            self.has_mask = False
            self.str_rect[0] = -1
            self.left = -1
            if self.mask_rect is not None and self.world is not None:
                self.world.tmask_clear(*self.mask_rect)     # (clearTextSurface)
            if self.mask_screen == MAIN:
                if self.mask_rect is not None and self.world is not None:
                    self.world.surface_restore(MAIN, self.mask_rect)
                self.mask_rect = None
            else:
                if self.verb_rect is not None and self.world is not None:
                    self.world.surface_restore(VERBS, self.verb_rect)
                self.verb_rect = None

    # --- texto de sistema ---------------------------------------------------------
    def draw_string(self, a, msg):
        buf = bytearray(self.convert(msg))
        st = self.strings[a].cur
        self.top = st.ypos
        self.start_left = self.left = st.xpos
        self.right = st.right
        self.center = st.center
        self.color = st.color
        self.disable_offs_x = self.first_char = True
        self.set_cur_id(st.charset)
        self.cmap[0:4] = self.charset_data[self.cur_id][0:4]
        fh = self.font_height()
        space = None
        for i, ch in enumerate(buf):
            if ch == 32:
                if space is None:
                    space = i
            else:
                space = None
        if space is not None:
            del buf[space:]
        if self.center:
            self.left -= self.string_width(bytes(buf)) // 2
        if not buf:
            buf = bytearray(b" ")
        i = 0
        while i < len(buf):
            c = buf[i]
            i += 1
            if c in (0xFF, 0xFE):
                c = buf[i] if i < len(buf) else 0
                i += 1
                if c in (9, 10, 13, 14):
                    i += 2
                elif c in (1, 8):
                    if self.center:
                        self.left = self.start_left - self.string_width(bytes(buf), i)
                    else:
                        self.left = self.start_left
                    self.top += fh
                elif c == 12:
                    col = buf[i] | buf[i + 1] << 8 if i + 1 < len(buf) else 0
                    i += 2
                    self.color = st.color if col == 0xFF else col & 0xFF
            else:
                self.print_char(c, True)
        if a == 0:
            self.next_left = self.left
            self.next_top = self.top
        st.xpos = self.str_rect[2]

    # --- hablar --------------------------------------------------------------------
    def set_talking_actor(self, a):
        self.vm.vars[VAR_TALK_ACTOR] = a

    def talking_actor(self):
        return self.vm.vars[VAR_TALK_ACTOR] & 0xFF

    def actor_in_room(self, a):
        return self.vm.in_room(a)

    def actor_talk(self, act, msg):
        self.buf = self.convert(msg) + b"\x00"
        if act == 0xFF:
            if not self.keep_text:
                self.stop_talk()
            self.set_talking_actor(0xFF)
        else:
            if not self.actor_in_room(act):
                return
            if not self.keep_text:
                self.stop_talk()
            self.set_talking_actor(act)
            if not self.strings[0].cur.no_talk_anim:
                a = self.vm.actors[act]
                a.talk_anim(a.talk_start)           # runActorTalkScript(talkStartFrame)
                self.use_talk_anims = True
        ta = self.talking_actor()
        if ta > 0x7F or not 0 < ta < len(self.vm.actors):
            self.charset_color = self.strings[0].cur.color & 0xFF
        else:
            self.charset_color = self.vm.actors[ta].talk_color
        self.buf_pos = 0
        self.talk_delay = 0
        self.have_msg = 0xFF
        self.vm.vars[VAR_HAVE_MSG] = 0xFF
        self.charset_1()

    def stop_talk(self):
        self.have_msg = 0
        self.talk_delay = 0
        act = self.talking_actor()
        if act and act < 0x80:
            if self.actor_in_room(act) and self.use_talk_anims:
                a = self.vm.actors[act]
                a.talk_anim(a.talk_stop)            # runActorTalkScript(talkStopFrame)
                self.use_talk_anims = False
            self.set_talking_actor(0xFF)
        self.keep_text = False
        self.restore_charset_bg()

    def charset_1(self):
        if not self.have_msg:
            return
        w = self.world
        if w is not None and w.room:
            cur, dest = w.cam_cur_dest()
            if dest // 8 != cur // 8 or cur != self.cam_last:
                return
        st = self.strings[0].cur
        ta = self.talking_actor()
        a = ta if ta != 0xFF and 0 < ta < len(self.vm.actors) else None
        if a is not None and st.overhead:
            x, y, elev, scaley = w.actor_talk_pos(a) if w is not None else (0, 0, 0, 255)
            st.xpos = x - self.xstart()
            st.ypos = y - elev
            ty = self.vm.vars[VAR_V5_TALK_STRING_Y]
            if ty < 0:
                s = int((scaley * ty) / 0xFF)
                st.ypos += int((ty - s) / 2) + s
            else:
                st.ypos = ty
            st.ypos = s16(st.ypos)
            if st.ypos < 1:
                st.ypos = 1
            if st.xpos < 80:
                st.xpos = 80
            if st.xpos > SCREEN_W - 80:
                st.xpos = SCREEN_W - 80
        self.top = st.ypos
        self.start_left = self.left = st.xpos
        self.right = st.right
        self.center = st.center
        self.color = self.charset_color
        self.set_cur_id(st.charset)
        self.cmap[0:4] = self.charset_data[self.cur_id][0:4]
        if self.talk_delay:
            return
        if self.have_msg == 1:
            self.stop_talk()
            return
        if a is not None and not st.no_talk_anim:
            act = self.vm.actors[a]                 # cada trozo del texto: hablando otra vez
            act.talk_anim(act.talk_start)
            self.use_talk_anims = True
        if not self.keep_text:
            self.restore_charset_bg()
        t = self.right - st.xpos - 1
        if self.center:
            if t > self.next_left:
                t = self.next_left
            t *= 2
        self.buf = self.add_linebreaks(self.buf, self.buf_pos, t)
        if self.center:
            self.next_left -= self.string_width(self.buf, self.buf_pos) // 2
            if self.next_left < 0:
                self.next_left = 0
        self.disable_offs_x = self.first_char = not self.keep_text
        buf = self.buf
        fh = self.font_height()
        while True:
            c = buf[self.buf_pos] if self.buf_pos < len(buf) else 0
            self.buf_pos += 1
            if c == 0:
                self.have_msg = 1
                self.keep_text = False
                break
            if c == 13:
                self.newline(st, fh)
                continue
            if c in (0xFE, 0xFF):
                c = buf[self.buf_pos] if self.buf_pos < len(buf) else 0
                self.buf_pos += 1
                if c == 1:
                    self.newline(st, fh)
                    continue
                if c == 2:
                    self.have_msg = 0
                    self.keep_text = True
                    break
                if c == 3:
                    self.have_msg = 0xFF
                    self.keep_text = False
                    break
                if c == 12:
                    col = buf[self.buf_pos] | buf[self.buf_pos + 1] << 8
                    self.buf_pos += 2
                    self.color = self.charset_color if col == 0xFF else col & 0xFF
                elif c == 9:                        # startAnimActor del que habla
                    f = buf[self.buf_pos] | buf[self.buf_pos + 1] << 8
                    self.buf_pos += 2
                    if a is not None:
                        self.vm.actors[a].start_anim(f)
                elif c in (10, 13, 14):
                    self.buf_pos += 2
                continue
            self.left = self.next_left
            self.top = self.next_top
            self.print_char(c, False)
            self.next_left = self.left
            self.next_top = self.top
            self.talk_delay += self.vm.vars[VAR_CHARINC]

    def newline(self, st, fh):
        self.next_left = st.xpos
        if self.center:
            self.next_left -= self.string_width(self.buf, self.buf_pos) // 2
        self.next_top += fh
        self.disable_offs_x = True

    def decode_print(self, act, items):
        """print / printEgo (decodeParseString)."""
        slot = {252: 3, 253: 2, 254: 1}.get(act, 0)
        tab = self.strings[slot]
        tab.load_default()
        st = tab.cur
        v = self.vm.val
        for it in items:
            k = it[0]
            if k == "at":
                st.xpos, st.ypos = v(it[1]), v(it[2])
                st.overhead = False
            elif k == "color":
                st.color = v(it[1]) & 0xFF
            elif k == "clipped":
                st.right = v(it[1])
            elif k == "flag":
                if it[1] == 4:
                    st.center = True
                    st.overhead = False
                elif it[1] == 6:
                    st.center = False
                    st.overhead = False
                elif it[1] == 7:
                    st.overhead = True
            elif k == "text":
                if slot == 0:
                    self.actor_talk(act, it[1])
                elif slot == 1:
                    self.draw_string(1, it[1])
                return
        tab.save_default()

    # --- verbos ----------------------------------------------------------------
    def verb_slot(self, vid, mode):
        for i in range(1, NUM_VERBS):
            if self.verbs[i].verbid == vid and self.verbs[i].saveid == mode:
                return i
        return 0

    def kill_verb(self, slot):
        if slot == 0:
            return
        vs = self.verbs[slot]
        vs.verbid = 0
        vs.curmode = 0
        vs.name = None
        if vs.saveid == 0:
            self.draw_verb(slot, 0)
            self.verb_mouse(0)
        vs.saveid = 0

    def restore_verb_bg(self, slot):
        vs = self.verbs[slot]
        if vs.old is not None:
            if self.world is not None:
                self.world.surface_fill(VERBS, vs.old, vs.bkcolor)
            vs.old = None

    def draw_verb(self, slot, mode):
        if not slot:
            return
        vs = self.verbs[slot]
        if not vs.saveid and vs.curmode and vs.verbid:
            if vs.type == IMAGE_VERB:
                self.draw_verb_bitmap(slot)
                return
            self.restore_verb_bg(slot)
            st = self.strings[4].cur
            st.charset = vs.charset
            st.xpos = vs.left
            st.ypos = vs.top
            st.right = SCREEN_W - 1
            st.center = bool(vs.center)
            if vs.curmode == 2:
                st.color = vs.dimcolor
            elif mode and vs.hicolor:
                st.color = vs.hicolor
            else:
                st.color = vs.color
            if vs.name is None:
                return
            tmp = self.center
            self.draw_string(4, vs.name)
            self.center = tmp
            vs.right = self.str_rect[2]
            vs.bottom = self.str_rect[3]
            vs.old = tuple(self.str_rect)
            self.str_rect[0] = self.str_rect[2]
        else:
            self.restore_verb_bg(slot)

    def draw_verb_bitmap(self, slot):
        vs = self.verbs[slot]
        vsn = self.find_vs(vs.top)
        img = self.verb_image(*vs.image) if (vs.image and self.verb_image) else None
        if img is None or vsn is None:
            return
        w, h, pix, opaque = img
        xs = vs.left // 8
        ydiff = vs.top - self.vs_top(vsn)
        if self.world is not None:
            self.world.surface_image(vsn, xs * 8, ydiff, img)
        vs.right = vs.left + w // 8 * 8
        vs.bottom = vs.top + h // 8 * 8
        vs.old = (vs.left, vs.top, vs.right, vs.bottom)

    def redraw_verbs(self):
        for i in range(NUM_VERBS):
            self.draw_verb(i, 0)
        self.verb_mouse(0)

    def verb_mouse(self, verb):
        if self.verb_mouse_over != verb:
            if self.verbs[self.verb_mouse_over].type != IMAGE_VERB:
                self.draw_verb(self.verb_mouse_over, 0)
                self.verb_mouse_over = verb
            if self.verbs[verb].type != IMAGE_VERB and self.verbs[verb].hicolor:
                self.draw_verb(verb, 1)
                self.verb_mouse_over = verb

    def find_verb_at(self, x, y):
        for i in range(NUM_VERBS - 1, 0, -1):
            vs = self.verbs[i]
            if vs.curmode != 1 or not vs.verbid or vs.saveid or y < vs.top or y >= vs.bottom:
                continue
            if vs.center:
                if x < -(vs.right - 2 * vs.left) or x >= vs.right:
                    continue
            elif x < vs.left or x >= vs.right:
                continue
            return i
        return 0

    def verb_ops(self, verb, subs):
        v = self.vm.val
        slot = self.verb_slot(verb, 0)
        vs = self.verbs[slot]
        vs.verbid = verb
        for k, p in subs:
            if k == 1:
                a = v(p[0])
                if slot:
                    vs.image = (self.world.room if self.world else 0, a)
                    vs.type = IMAGE_VERB
            elif k == 2:
                vs.name = bytes(p[0][1])
                if slot == 0:
                    vs.name = None
                vs.type = TEXT_VERB
                vs.imgindex = 0
            elif k == 3:
                vs.color = v(p[0]) & 0xFF
            elif k == 4:
                vs.hicolor = v(p[0]) & 0xFF
            elif k == 5:
                vs.left, vs.top = v(p[0]), v(p[1])
            elif k == 6:
                vs.curmode = 1
            elif k == 7:
                vs.curmode = 0
            elif k == 8:
                self.kill_verb(slot)
            elif k == 9:
                slot = self.verb_slot(verb, 0)
                if slot == 0:
                    for slot in range(1, NUM_VERBS):
                        if self.verbs[slot].verbid == 0:
                            break
                vs = self.verbs[slot]
                vs.verbid = verb
                vs.color, vs.hicolor, vs.dimcolor = 2, 0, 8
                vs.type = TEXT_VERB
                vs.charset = self.strings[0].default.charset
                vs.curmode = vs.saveid = vs.key = vs.center = vs.imgindex = 0
            elif k == 16:
                vs.dimcolor = v(p[0]) & 0xFF
            elif k == 17:
                vs.curmode = 2
            elif k == 18:
                vs.key = v(p[0]) & 0xFF
            elif k == 19:
                vs.center = 1
            elif k == 20:
                a = v(p[0])
                src = self.string_res.get(a) if a else None
                vs.name = b"" if src is None else bytes(src[:res_str_len(src)]) + b"\0"
                vs.type = TEXT_VERB
                vs.imgindex = 0
            elif k == 22:
                a, b = v(p[0]), v(p[1]) & 0xFF
                if slot and vs.imgindex != a:
                    vs.image = (b, a)
                    vs.type = IMAGE_VERB
                    vs.imgindex = a
            elif k == 23:
                vs.bkcolor = v(p[0]) & 0xFF
        self.draw_verb(slot, 0)
        self.verb_mouse(0)

    def save_restore_verbs(self, k, a, b, c):
        if k == 1:
            while a <= b:
                slot = self.verb_slot(a, 0)
                if slot and self.verbs[slot].saveid == 0:
                    self.verbs[slot].saveid = c
                    self.draw_verb(slot, 0)
                    self.verb_mouse(0)
                a += 1
        elif k == 2:
            while a <= b:
                slot = self.verb_slot(a, c)
                if slot:
                    slot2 = self.verb_slot(a, 0)
                    if slot2:
                        self.kill_verb(slot2)
                    slot = self.verb_slot(a, c)
                    self.verbs[slot].saveid = 0
                    self.draw_verb(slot, 0)
                    self.verb_mouse(0)
                a += 1
        elif k == 3:
            while a <= b:
                slot = self.verb_slot(a, c)
                if slot:
                    self.kill_verb(slot)
                a += 1

    # --- cursor -------------------------------------------------------------------
    def cursor_command(self, k, params):
        v = self.vm.val
        if k == 1:
            self.cursor_state = 1
            self.verb_mouse(0)
        elif k == 2:
            self.cursor_state = 0
            self.verb_mouse(0)
        elif k == 3:
            self.userput = 1
        elif k == 4:
            self.userput = 0
        elif k == 5:
            self.cursor_state += 1
            self.verb_mouse(0)
        elif k == 6:
            self.cursor_state -= 1
            self.verb_mouse(0)
        elif k == 7:
            self.userput += 1
        elif k == 8:
            self.userput -= 1
        elif k == 13:
            self.init_charset(v(params[0]) & 0xFF)
        elif k == 14:
            table = [v(x) & 0xFF for x in params[0]] + [0] * 16
            n = self.strings[1].default.charset
            for i in range(16):
                self.cmap[i] = self.charset_data[n][i] = table[i]
        self.cursor_state = s16(self.cursor_state)
        self.userput = s16(self.userput)
        self.vm.vars[VAR_CURSORSTATE] = self.cursor_state
        self.vm.vars[VAR_USERPUT] = self.userput

    # --- cadenas -----------------------------------------------------------------
    def string_ops(self, a):
        v = self.vm.val
        k = a[0][1]
        if k == 1:
            n = v(a[1]) & 0xFF
            self.string_res[n] = bytearray(a[2][1]) + b"\x00"
        elif k == 2:
            x, y = v(a[1]) & 0xFF, v(a[2]) & 0xFF
            self.string_res.pop(x, None)
            if y in self.string_res:
                src = self.string_res[y]
                self.string_res[x] = bytearray(src[:res_str_len(src)]) + b"\x00"
        elif k == 3:
            x, y, c = v(a[1]) & 0xFF, v(a[2]) & 0xFF, v(a[3]) & 0xFF
            s = self.string_res.get(x)
            if s is not None and y < len(s):
                s[y] = c
        elif k == 4:
            x, y = v(a[2]) & 0xFF, v(a[3]) & 0xFF
            s = self.string_res.get(x)
            self.vm.result(a[1], s[y] if s is not None and y < len(s) else 0)
        elif k == 5:
            x, size = v(a[1]) & 0xFF, v(a[2]) & 0xFF
            self.string_res.pop(x, None)
            if size:
                self.string_res[x] = bytearray(size)

    def set_object_name(self, obj, name):
        for i in range(NUM_NEW_NAMES):
            if self.new_names[i] == obj:
                self.new_names[i] = 0
                self.new_name_res[i] = None
                break
        for i in range(NUM_NEW_NAMES):
            if self.new_names[i] == 0:
                self.new_names[i] = obj
                self.new_name_res[i] = bytes(name)
                self.run_inventory_script(0)
                return

    # --- inventario -------------------------------------------------------------------
    def run_inventory_script(self, arg):
        s = self.vm.vars[VAR_INVENTORY_SCRIPT]
        if s:
            self.vm.run_script(s, args=[arg])

    def add_to_inventory(self, obj):
        """pickupObject: copia el codigo y el nombre del objeto de la habitacion."""
        data = self.world.object_data(obj) if self.world is not None else None
        if data is None:
            return
        for i in range(NUM_INVENTORY):
            if self.inventory[i] == 0:
                self.inventory[i] = obj
                self.inv_data[obj] = data
                return

    def clear_owner(self, obj):
        """setOwnerOf(obj, 0): sale del inventario."""
        for i in range(NUM_INVENTORY):
            if self.inventory[i] == obj:
                self.inventory[i] = 0
                self.inv_data.pop(obj, None)
        k = 0
        for i in range(NUM_INVENTORY):
            if self.inventory[i]:
                self.inventory[k] = self.inventory[i]
                k += 1
        for i in range(k, NUM_INVENTORY):
            self.inventory[i] = 0

    def inventory_count(self, owner):
        return sum(1 for o in self.inventory if o and self.vm.owner_of(o) == owner)

    def find_inventory(self, owner, idx):
        count = 1
        for o in self.inventory:
            if o and self.vm.owner_of(o) == owner:
                if count == idx:
                    return o
                count += 1
        return 0

    # --- frases --------------------------------------------------------------------
    def do_sentence(self, verb, a, b):
        if verb == 0xFE:
            self.sentence = []
            self.vm.stop_script(self.vm.vars[VAR_SENTENCE_SCRIPT])
            self.mouse_kb = 0
            return
        if len(self.sentence) < 6:
            self.sentence.append([verb, a, b, b != 0, 0])

    def script_in_use(self, n):
        return any(s.number == n for s in self.vm.slots)

    def check_sentence(self):
        ss = self.vm.vars[VAR_SENTENCE_SCRIPT]
        if self.script_in_use(ss):
            for s in self.vm.slots:
                if s.number == ss and s.status != 0 and s.freeze_count == 0:
                    return
        if not self.sentence or self.sentence[-1][4]:
            return
        verb, a, b, prep, _ = self.sentence.pop()
        if prep and a == b:
            return
        self.vm.cur = None
        if ss:
            self.vm.run_script(ss, args=[verb, a, b])

    def sentence_busy(self):
        """wait 4: mientras haya frases o el script de frases este en marcha."""
        ss = self.vm.vars[VAR_SENTENCE_SCRIPT]
        if self.sentence:
            if self.sentence[-1][4] and not self.script_in_use(ss):
                return False
            return True
        return self.script_in_use(ss)

    # --- entrada --------------------------------------------------------------------
    def set_mouse(self, x, y):
        self.mouse = (x, y)
        vm = self.vm
        vm.vars[VAR_MOUSE_X] = x
        vm.vars[VAR_MOUSE_Y] = y
        vm.vars[VAR_VIRT_MOUSE_X] = x + self.xstart()
        vm.vars[VAR_VIRT_MOUSE_Y] = y

    def key(self, k):
        """processKeyboard: salir de la escena, cortar el texto o pasar la tecla."""
        vm = self.vm
        if k == 27 and vm.vars[VAR_CUTSCENEEXIT_KEY]:
            vm.abort_cutscene()
            self.mouse_kb = vm.vars[VAR_CUTSCENEEXIT_KEY] & 0xFF
        elif k == vm.vars[VAR_TALKSTOP_KEY] and k:
            self.talk_delay = 0
        else:
            self.mouse_kb = k

    def click(self, button):
        self.mouse_kb = 0x8000 | button

    def run_input_script(self, area, val, mode):
        s = self.vm.vars[VAR_VERB_SCRIPT]
        if s:
            self.vm.run_script(s, args=[area, val, mode])

    def check_exec_verbs(self):
        st = self.mouse_kb
        self.mouse_kb = 0
        if self.userput <= 0 or st == 0:
            return
        if not st & 0x8000:
            for i in range(1, NUM_VERBS):
                vs = self.verbs[i]
                if vs.verbid and vs.saveid == 0 and vs.curmode == 1 and vs.key == st:
                    self.run_input_script(AREA_VERB, vs.verbid, 1)
                    return
            self.run_input_script(AREA_KEY, st, 1)
            return
        code = st & 0xFF
        x, y = self.mouse
        if self.find_vs(y) is None:
            return
        over = self.find_verb_at(x, y)
        if over:
            self.run_input_script(AREA_VERB, self.verbs[over].verbid, code)
        else:
            self.run_input_script(AREA_SCENE if self.find_vs(y) == MAIN else AREA_VERB, 0, code)

    # --- un paso ----------------------------------------------------------------------
    def tick_delay(self, delta):
        self.talk_delay -= delta
        if self.talk_delay < 0:
            self.talk_delay = 0
