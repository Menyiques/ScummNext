"""Convierte un juego SCUMM v5 a los ficheros que carga el Next.

    python tools/convert.py CARPETA_DEL_JUEGO [NOMBRE] [SALIDA]

CARPETA_DEL_JUEGO tiene NOMBRE.000 y NOMBRE.001 (por ejemplo MONKEY.000 y
MONKEY.001 de tu CD). Si no se da NOMBRE, se busca el primer *.000 de la carpeta.
SALIDA es la carpeta de datos (por defecto build/data). Para tener varios juegos en
la tarjeta, cada uno en una carpeta junto a scumm.nex (SALIDA = TARJETA/MONKEY, por
ejemplo): al arrancar sale un menu para elegir. --titulo "Nombre" pone lo que se ve
en ese menu (TITULO.TXT; sin el, el nombre de la carpeta). Ahi quedan:

    GAME.DAT        lista de habitaciones y el costume del protagonista
    Rnnn.DAT        una habitacion (con sus scripts)
    Cnnn.DAT        un costume (el bloque COST tal cual)
    SCRIPTS.DAT     los scripts globales: 200 x 5 bytes de indice (posicion en
                    el fichero, $FFFFFF si no esta, y longitud) y el codigo
    OBJ.DAT         objetos: numero (2 bytes), duenos, estados y clases (4 bytes)
    TITULO.TXT      (con --titulo) el nombre en el menu de juegos

Al final dice si todo cabe en el Next o que no cabe y por cuanto (la tabla de
limites, mas abajo); si algo no cabe, escribe los ficheros igual pero sale con
error, porque en el Next eso fallaria sin avisar. --list lo dice sin escribir nada.

Los ficheros generados contienen los graficos del juego: son para tu uso, no
para repartirlos.

Formato de Rnnn.DAT (little endian):

  pagina 0 (8192 bytes, el Z80 la deja en $4000):
     0  "SR5", 3           version
     4  ancho, alto        en pixeles
     8  nz                 planos Z
     9  ncajas
    10  x, y de inicio     un punto dentro de la caja mas grande
    14  ntiras            ancho / 8
    16  bytes por tira     (8 + nz) * alto
    18  paginas de tiras
    19  tiras por pagina
    20  offset de la matriz de cajas y su hueco (lo que cabe la mas larga que puede
        hacer createBoxMatrix; BOXM no lo llena)
    24  offset de la tabla de tiras
    26  offset de la tabla de copias limpias
    28  offset de la tabla de objetos
    30  numero de objetos
    31  paginas de datos (tiras, copias e imagenes de objetos)
    32  paleta: 256 x 2 bytes de 9 bits, listos para NR $44
   544  escalas (SCAL): 4 x (escala1, y1, escala2, y2)
   576  scripts: entrada (posicion 3 bytes y longitud 2), salida (3 y 2),
        numero de locales (1) y offset de su tabla (2): por local, numero (1),
        posicion (3) y longitud (2). Las posiciones son lineales en las
        paginas de datos (pagina * 8192 + offset); $FFFFFF si no hay.
   589  offset de la tabla de vecinas (0 si no hay): un bit por pareja de cajas
        i < j, si se tocan (model.box_near_bits), para createBoxMatrix
   591  1 si los scripts de la habitacion tienen createBoxMatrix
   592  (0; el Z80 pone 1 cuando rehace la matriz, y se guarda con la partida)
   640  cajas: ncajas x 20 bytes (como BOXD)
        matriz de cajas (BOXM tal cual: una lista por caja, cada una acaba en $FF),
          en su hueco
        tabla de tiras: por tira, pagina (relativa) y direccion en $C000-$DFFF
        copias limpias: por tira, pagina ($FF si ningun objeto la toca) y
          direccion en $E000-$FFFF
        objetos (24 bytes): numero, x, y, ancho, alto (x y ancho en tiras, ya
          recortados a la habitacion), padre, estado del padre, estado,
          imagenes, offset de su tabla de imagenes (3 bytes por imagen:
          pagina o $FF, direccion en $E000), posicion lineal de su bloque
          VERB (3), punto al que se anda (x, y) y longitud del bloque VERB
        tabla de las locales, y la de vecinas
  paginas 1..: tiras. Cada tira son 8 columnas de `alto` bytes (de arriba
  abajo) y despues `alto` bytes de cada plano Z (bit 7 = pixel izquierdo).
  Despues, las copias limpias de las tiras que tocan los objetos, y las
  imagenes: una cabecera (planos que trae y un puntero por tira) y por tira 8
  columnas de pixeles, `alto` bytes de opacidad (bit 7 = columna izquierda) y
  `alto` bytes de cada plano. Nada de eso cruza un limite de pagina, y un
  bloque igual a otro ya puesto no se repite (apunta al mismo sitio). Al
  final, el codigo de los scripts de la habitacion (este si puede cruzar).
"""
import glob
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scumm as S  # noqa: E402
import sound as SN  # noqa: E402

ROOT = os.path.dirname(HERE)
PAGE = 8192
META_PAL8 = 7168            # en la pagina META: la paleta de 8 bits (768 bytes)
META_CYCL = 7936            # y los 16 ciclos de color (5 bytes cada uno)
MAX_PAGES = 51              # paginas 27-77 del Next (la 78 es la de los actores)
OBJ_SIZE = 24
NONE24 = 0xFFFFFF
L2_TRANSPARENT = 0xE3       # NR $14

# Lo que cabe en el Next (si el juego se pasa, el Z80 no avisa: corta el fichero, se
# salta lo que sobra o se para con el borde rojo). Lo demas que fija SCUMM v5 (100
# verbos, 13 actores, 150 nombres nuevos, 50 cadenas) es igual en todos sus juegos.
LIM_SCRIPTS = 16 * PAGE     # SCRIPTS.DAT: las 16 paginas de SPAGES (LOADSCRIPTS, src/vmdata.asm)
LIM_GLOBAL = 200            # scripts globales: NUMGLOBAL (src/vmdata.asm)
LIM_GAMEDAT = 256           # GAME.DAT: GAMEBUF (LOADGAME, src/scumm.asm)
LIM_NUMBER = 255            # numeros de habitacion y de costume: un byte (GAME.DAT, MKNAME)
LIM_SOUNDS = 56 * PAGE      # SOUNDS.DAT: SND_MAX paginas desde SND_PAGE (SNDINIT, src/ova.asm)
LIM_SAMPLE = 0xFFFF         # un efecto: su largo, 2 bytes (sound.sounds_file lo corta)
LIM_CHARS = 2 * PAGE        # CHARS.DAT: CHAR_MAX paginas desde CHARP (src/uidata.asm)
LIM_CHARSETS = 8            # fuentes: las 8 posiciones del indice de CHARS.DAT
LIM_VERBIMG = 100           # imagenes de verbo: VIDX_MAX (LOADIDX, src/ovu.asm)
LIM_VERBIMG_H = 79          # alto de una: menos que GLYPHMAX (src/ovt.asm, src/uivars.asm)
LIM_OBJECTS = 1000          # objetos: NOBJMAX (LOADOBJS, src/vmdata.asm; LOADIDX, src/ovu.asm)
LIM_INVOBJ = 0xFFFF         # INVOBJ.DAT: posiciones de 2 bytes
LIM_INVCODE = 1024          # bloque VERB de un objeto del inventario: CODEBUF0 (CODELOAD,
                            # src/ovu.asm; el otro hueco, CODEBUF1, es de CODEMAX1 = 960)
LIM_EGO = 3 * PAGE          # costume del protagonista: COST_MAX paginas (LOADCOST, src/scumm.asm)
LIM_CAST_PAGES = MAX_PAGES  # los demas costumes: detras de los datos de la habitacion, hasta
                            # la pagina 77 (CCNEXT y CAST_PAGE, src/ovu.asm)
LIM_VARS = 800              # variables: NVARS (src/vmdata.asm)
LIM_BITS = 2048             # variables de un bit: BITS, 256 bytes (src/vmdata.asm, src/vm.asm)
LIM_INV = 80                # objetos en el inventario: NUM_INV (src/uidata.asm)
LIM_STRIPS = 128            # tiras de una habitacion: DIRTY (src/vm.asm), ZSTO y ZYMNO
                            # (src/uidata.asm)
LIM_ROOM_OBJ = 255          # objetos de una habitacion: NOBJ (un byte), ZOBID ($FF: no esta)


class RoomData:
    """Una habitacion ya decodificada (lo que usa el modelo y lo que va al Next)."""

    def __init__(self, room, index=None):
        self.num = room.num
        self.width, self.height = room.width, room.height
        self.bg = room.background()
        self.zplanes = room.zplanes()
        self.boxes = room.boxes
        self.matrix = room.matrix
        self.palette = room.palette
        self.cycles = S.parse_cycles(room.cycles)
        self.scale_slots = (list(room.scale_slots) + [(0, 0, 0, 0)] * 4)[:4]
        self.objects = S.room_objects(room, index)
        for o in self.objects:              # como los ve el Z80: recortados a la habitacion
            o.w, o.h = clipped(o, self.width // 8, self.height)
            o.x, o.y = min(o.x, 255), min(o.y, 255)
            if not (o.w and o.h):
                o.images = []
        self.code = S.room_scripts(room)
        self.start = start_point(self.boxes, self.width, self.height)
        self._pages = None
        self._near = None
        self._bmown = None

    @property
    def data_pages(self):
        """Paginas de datos de Rnnn.DAT (sin la primera): detras van los costumes."""
        if self._pages is None:
            self._pages = room_file(self)[31]
        return self._pages

    @property
    def box_near(self):
        """(tabla de vecinas o None, hueco de la matriz), como van en Rnnn.DAT."""
        if getattr(self, "_near", None) is None:
            room_file(self)
        return self._near

    @property
    def box_matrix_own(self):
        """Si sus scripts piden createBoxMatrix: al cargar una partida aqui la matriz se
        rehace siempre (las partidas de antes no dicen si estaba rehecha)."""
        if getattr(self, "_bmown", None) is None:
            self._bmown = calls_box_matrix(self)
        return self._bmown


def game_charsets(game):
    """{numero: Charset} de las fuentes del juego."""
    import charset as CH
    out = {}
    for i in range(len(game.index.dirs.get("DCHR", []))):
        r = game.resource("DCHR", i)
        if r is not None:
            out[i] = CH.Charset(bytes(game.data[r[1]:r[2]]))
    return out


def verb_images(game):
    """(habitacion, objeto) -> (ancho, alto, pixeles, opacos): la imagen 1 del
    objeto en su habitacion, sin recortar (los iconos del inventario)."""
    cache = {}

    def get(room, obj):
        if room not in cache:
            try:
                objs = S.room_objects(game.room(room), game.index)
            except Exception:                       # noqa: BLE001
                objs = []
            cache[room] = {o.id: o for o in objs}
        o = cache[room].get(obj)
        if o is None or not o.images or o.images[0] is None:
            return None
        im = o.images[0]
        h, w = im.pix.shape
        return w, h, im.pix.tolist(), im.opaque.tolist()
    return get


def start_point(boxes, w, h):
    best, pt = -1, (w // 2, h - 10)
    for b in boxes[1:]:
        if b.flags & 0x80:
            continue
        xs = [p[0] for p in b.corners()]
        ys = [p[1] for p in b.corners()]
        area = (max(xs) - min(xs)) * (max(ys) - min(ys))
        if area > best:
            best = area
            pt = (sum(xs) // 4, sum(ys) // 4)
    return pt


def next_color(rgb):
    """RGB de 8 bits -> los dos bytes de 9 bits de NR $44 (sin el transparente)."""
    r, g, b = [(int(v) * 7 + 127) // 255 for v in rgb]
    hi = r << 5 | g << 2 | b >> 1
    lo = b & 1
    if hi == L2_TRANSPARENT:
        hi, lo = hi - 1, 1          # azul 7 -> 5: nunca sale transparente
    return hi, lo


def palette_bytes(pal):
    out = bytearray()
    for rgb in pal:
        out += bytes(next_color(rgb))
    return bytes(out)


class Packer:
    """Reparte bloques en paginas de 8 KB sin que ninguno cruce de pagina. Un bloque
    igual a otro ya puesto no se repite (el Z80 solo los lee): en la 39 (las
    catacumbas, 52 imagenes de tuneles) asi quedan paginas para los costumes."""

    def __init__(self, first_page):
        self.page = first_page
        self.pages = []
        self.used = PAGE
        self.seen = {}

    def put(self, data):
        if len(data) > PAGE:
            raise ValueError("bloque de %d bytes" % len(data))
        key = bytes(data)
        if key in self.seen:
            return self.seen[key]
        if self.used + len(data) > PAGE:
            self.pages.append(bytearray(PAGE))
            self.used = 0
        o = self.used
        self.pages[-1][o:o + len(data)] = data
        self.used += len(data)
        self.seen[key] = (self.page + len(self.pages) - 1, o)
        return self.seen[key]


def clipped(o, ns, H):
    w = min(o.w, ns - o.x) if o.x < ns else 0
    h = min(o.h, H - o.y) if o.y < H else 0
    return max(w, 0), max(h, 0)


def moved_strips(rd, ns):
    """Las tiras a las que los scripts de la habitacion mueven objetos (drawObject con
    setXY): las de cada objeto en cada sitio al que va (todas, si el sitio no es una
    constante)."""
    import opcodes as O
    ancho = {o.id: o.w for o in rd.objects}
    out = set()
    for k, code in rd.code.items():
        if not isinstance(code, (bytes, bytearray)):
            continue
        pc = 0
        if isinstance(k, tuple) and k[0] == "obj":
            vt = rd.code.get(("verbs", k[1])) or []
            pc = min([o for _, o in vt], default=0)
        while pc < len(code):
            try:
                _, name, args, pc = O.decode(code, pc)
            except Exception:
                break
            if name == "drawObject" and len(args) > 3 and args[1] == ("sub", 1):
                obj, x = args[0], args[2]
                if not isinstance(obj, int) or not isinstance(x, int):
                    return set(range(ns))
                if x != 0xFF:
                    out.update(s_ for s_ in range(x, x + ancho.get(obj, 0)) if s_ < ns)
    return out


def calls_box_matrix(rd):
    """Si algun script de la habitacion tiene createBoxMatrix (matrixOps 4)."""
    import opcodes as O
    for k, code in rd.code.items():
        if not isinstance(code, (bytes, bytearray)):
            continue
        pc = 0
        if isinstance(k, tuple) and k[0] == "obj":
            vt = rd.code.get(("verbs", k[1])) or []
            pc = min([o for _, o in vt], default=0)
        while pc < len(code):
            try:
                _, name, args, pc = O.decode(code, pc)
            except Exception:
                break
            if name == "matrixOps" and args and args[0] == ("sub", 4):
                return True
    return False


def box_matrix_room(rd, rest):
    """createBoxMatrix en el Next: la tabla de vecinas (model.box_near_bits) y el hueco
    de la matriz, el que puede ocupar la mas larga (sin pasar de los 2000 bytes de
    ScummVM, y nunca menos que BOXM). rest: lo demas que va en la pagina de datos
    detras de la matriz. Si no caben, el hueco de BOXM; y si tampoco cabe la tabla,
    sin ella (y createBoxMatrix no hace nada)."""
    import model as M
    nb = len(rd.boxes)
    base = 640 + 20 * nb + len(rd.matrix) + rest
    if nb > 64:
        return None, len(rd.matrix)
    near = M.box_near_bits([b.corners() for b in rd.boxes])
    cap = max(len(rd.matrix), min(2000, nb * (1 + 3 * nb) + 1))
    if base + cap - len(rd.matrix) + len(near) > META_PAL8:
        cap = len(rd.matrix)
        if base + len(near) > META_PAL8:
            return None, cap
    return near, cap


def room_file(rd):
    W, H, nz = rd.width, rd.height, len(rd.zplanes)
    ns = W // 8
    if ns > LIM_STRIPS:
        raise ValueError("%d tiras de ancho (caben %d)" % (ns, LIM_STRIPS))
    if len(rd.objects) > LIM_ROOM_OBJ:
        raise ValueError("%d objetos (caben %d)" % (len(rd.objects), LIM_ROOM_OBJ))
    rec = (8 + nz) * H
    spp = PAGE // rec
    if spp < 1:
        raise ValueError("habitacion %d: tira de %d bytes" % (rd.num, rec))
    npages = (ns + spp - 1) // spp
    strip = []
    pages = bytearray(npages * PAGE)
    for s_ in range(ns):
        p = (s_ // spp) * PAGE + (s_ % spp) * rec
        st = rd.bg[:, 8 * s_:8 * s_ + 8]
        data = bytearray(st.T.tobytes())                # por columnas
        for z in range(nz):
            data += rd.zplanes[z][:, s_].tobytes()
        pages[p:p + rec] = data
        strip.append(bytes(data))
    # copias limpias de las tiras que tocan los objetos con imagen (y de aquellas a las
    # que los scripts los mueven: drawObject con setXY)
    pk = Packer(npages)
    covered = set()
    for o in rd.objects:
        w, h = clipped(o, ns, H)
        if w and h and any(im is not None for im in o.images):
            covered.update(range(o.x, o.x + w))
    if getattr(rd, "mover", True):
        covered |= moved_strips(rd, ns)     # (si no caben: room_file lo repite sin ellas)
    pristine = {}
    for s_ in sorted(covered):
        pristine[s_] = pk.put(strip[s_])
    # imagenes de los objetos
    objtab = bytearray()
    imgtab = bytearray()
    for o in rd.objects:
        w, h = clipped(o, ns, H)
        ptrs = []
        for im in (o.images if w and h else []):
            if im is None:
                ptrs.append(None)
                continue
            planes = [pl for pl in sorted(im.planes) if 1 <= pl <= nz]
            recs = []
            for j in range(w):
                d = bytearray(im.pix[:h, 8 * j:8 * j + 8].T.tobytes())
                op = np.packbits(im.opaque[:h, 8 * j:8 * j + 8].astype(np.uint8), axis=1)[:, 0]
                d += op.tobytes()
                for pl in planes:
                    d += im.planes[pl][:h, j].tobytes()
                recs.append(pk.put(d))
            mask = 0
            for pl in planes:
                mask |= 1 << (pl - 1)
            hdr = bytearray((mask,))
            for pg, off in recs:
                hdr += struct.pack("<BH", pg, 0xE000 + off)
            ptrs.append(pk.put(hdr))
        objtab += struct.pack("<HBBBBBBBBH3shh5x", o.id, min(o.x, 255), min(o.y, 255), w, h,
                              o.parent, o.parentstate, o.actor_dir & 3, len(ptrs), len(imgtab),
                              b"\xff\xff\xff", o.walk_x, o.walk_y)
        for ptr in ptrs:
            imgtab += struct.pack("<BH", 0xFF, 0) if ptr is None else struct.pack("<BH", ptr[0], 0xE000 + ptr[1])
    # el codigo de los scripts, seguido, en las paginas siguientes
    first = npages + len(pk.pages)
    area = bytearray()

    def lin(blob):
        if blob is None:
            return NONE24
        pos = first * PAGE + len(area)
        area.extend(blob)
        return pos

    code = rd.code
    encd = lin(code.get("encd"))
    excd = lin(code.get("excd"))
    locs = [(k, lin(code[k])) for k in sorted(k for k in code if isinstance(k, int))]
    for k, o in enumerate(rd.objects):
        vb = code.get(("obj", o.id))
        objtab[OBJ_SIZE * k + 12:OBJ_SIZE * k + 15] = lin(vb).to_bytes(3, "little")
        objtab[OBJ_SIZE * k + 19:OBJ_SIZE * k + 21] = struct.pack("<H", len(vb) if vb else 0)
    for k, o in enumerate(rd.objects):         # los nombres (para la linea de frase)
        nm = o.name.encode("latin1") if isinstance(o.name, str) else bytes(o.name or b"")
        objtab[OBJ_SIZE * k + 21:OBJ_SIZE * k + 24] = lin(nm + b"\0").to_bytes(3, "little")
    meta = bytearray(PAGE)
    meta[32:32 + 512] = palette_bytes(rd.palette)
    # al final de la pagina: la paleta de 8 bits (darkenPalette parte de ella) y los
    # 16 huecos de ciclos de color (delay (2), flags, primero, ultimo)
    for i, rgb in enumerate(list(rd.palette)[:256]):
        meta[META_PAL8 + 3 * i:META_PAL8 + 3 * i + 3] = bytes(int(v) & 0xFF for v in rgb)
    for i, cy in enumerate(rd.cycles):
        if cy is not None:
            delay, flags, start, end = cy
            struct.pack_into("<HBBB", meta, META_CYCL + 5 * i, delay, flags & 0xFF, start, end)
    for k, sl in enumerate(rd.scale_slots):
        struct.pack_into("<4H", meta, 544 + 8 * k, *sl)
    near, cap = box_matrix_room(rd, 6 * ns + len(objtab) + len(imgtab) + 6 * len(locs))
    rd._near = (near, cap)
    o = 640
    for b in rd.boxes:
        meta[o:o + 20] = b.pack()
        o += 20
    moff = o
    meta[o:o + len(rd.matrix)] = rd.matrix
    o += cap
    toff = o
    for s_ in range(ns):
        meta[o:o + 3] = struct.pack("<BH", s_ // spp, 0xC000 + (s_ % spp) * rec)
        o += 3
    ptoff = o
    for s_ in range(ns):
        pg, off = pristine.get(s_, (0xFF, 0))
        meta[o:o + 3] = struct.pack("<BH", pg, 0xE000 + off if pg != 0xFF else 0)
        o += 3
    otoff = o
    itoff = otoff + len(objtab)
    for k in range(len(rd.objects)):
        rel = struct.unpack_from("<H", objtab, OBJ_SIZE * k + 10)[0]
        objtab[OBJ_SIZE * k + 10:OBJ_SIZE * k + 12] = struct.pack("<H", itoff + rel)
    meta[otoff:otoff + len(objtab)] = objtab
    meta[itoff:itoff + len(imgtab)] = imgtab
    o = itoff + len(imgtab)
    ltoff = o
    for k, pos in locs:
        meta[o:o + 6] = bytes((k,)) + pos.to_bytes(3, "little") + struct.pack("<H", len(code[k]))
        o += 6
    if near is not None:
        struct.pack_into("<H", meta, 589, o)
        meta[o:o + len(near)] = near
        o += len(near)
    meta[591] = 1 if calls_box_matrix(rd) else 0

    def ln(key):
        return len(code[key]) if key in code else 0

    meta[576:576 + 13] = encd.to_bytes(3, "little") + struct.pack("<H", ln("encd")) + \
        excd.to_bytes(3, "little") + struct.pack("<H", ln("excd")) + \
        bytes((len(locs),)) + struct.pack("<H", ltoff)
    if o > META_PAL8:
        raise ValueError("habitacion %d: la pagina de datos no cabe (%d bytes)" % (rd.num, o))
    total = first + (len(area) + PAGE - 1) // PAGE
    if total > MAX_PAGES:
        if getattr(rd, "mover", True) and moved_strips(rd, ns):
            rd.mover = False                # sin copias para los objetos movidos: se
            return room_file(rd)            # pintan encima de la tira (RECOMPOSE)
        raise ValueError("habitacion %d: %d paginas de datos (caben %d)" % (rd.num, total, MAX_PAGES))
    sx, sy = rd.start
    struct.pack_into("<4sHHBBhhHHBBHHHHHBB", meta, 0, b"SR5\x04", W, H, nz, len(rd.boxes),
                     sx, sy, ns, rec, npages, spp, moff, cap, toff, ptoff, otoff,
                     len(rd.objects), total)
    area += bytes((-len(area)) % PAGE)
    return bytes(meta) + bytes(pages) + b"".join(bytes(pg) for pg in pk.pages) + bytes(area)


def scripts_file(game):
    """SCRIPTS.DAT: indice de 200 posiciones de 3 bytes y el codigo seguido."""
    n = 200
    index = bytearray(b"\xff\xff\xff\x00\x00" * n)
    body = bytearray()
    for i in range(min(n, len(game.index.dirs.get("DSCR", [])))):
        r = game.resource("DSCR", i)
        if r is None:
            continue
        tag, a, b = r
        index[5 * i:5 * i + 5] = (5 * n + len(body)).to_bytes(3, "little") + struct.pack("<H", b - a)
        body += game.data[a:b]
    return bytes(index) + bytes(body)


def compact_charset(d):
    """El bloque CHAR con la tabla de caracteres de 2 bytes en vez de 4 (desde el
    principio de la fuente, el byte 21, como la original)."""
    d = bytes(d)
    f = d[21:]
    n = f[2] | f[3] << 8
    out = bytearray(d[:21] + f[:4])
    for c in range(n):
        o = int.from_bytes(f[4 + 4 * c:8 + 4 * c], "little")
        out += struct.pack("<H", o - 2 * n if o else 0)
    out += f[4 + 4 * n:]
    return bytes(out)


def charsets_file(game):
    """CHARS.DAT: 8 posiciones de 3 bytes ($FFFFFF si no hay) y las fuentes seguidas
    (con la tabla de caracteres de 2 bytes)."""
    index = bytearray(b"\xff\xff\xff" * 8)
    body = bytearray()
    for i in range(min(8, len(game.index.dirs.get("DCHR", [])))):
        r = game.resource("DCHR", i)
        if r is None:
            continue
        index[3 * i:3 * i + 3] = (24 + len(body)).to_bytes(3, "little")
        body += compact_charset(game.data[r[1]:r[2]])
    return bytes(index) + bytes(body)


def invobj_file(game):
    """INVOBJ.DAT: numero de objetos (2), la posicion de cada uno (2, $FFFF si no hay)
    y sus datos: largo del bloque VERB (2), el bloque (con su cabecera) y el nombre
    con su 0. Es lo que el Z80 lee cuando un objeto esta en el inventario."""
    n = len(game.index.objects or [])
    recs = {}
    for room in game.rooms():
        try:
            r = game.room(room)
            sc = S.room_scripts(r)
            objs = S.room_objects(r, game.index)
        except Exception:                       # noqa: BLE001
            continue
        for o in objs:
            if 0 < o.id < n and o.id not in recs:
                vb = bytes(sc.get(("obj", o.id)) or b"")
                nm = o.name.encode("latin1") if isinstance(o.name, str) else bytes(o.name or b"")
                recs[o.id] = struct.pack("<H", len(vb)) + vb + nm + b"\0"
    index = bytearray(b"\xff\xff" * n)
    body = bytearray()
    for i in sorted(recs):
        index[2 * i:2 * i + 2] = struct.pack("<H", len(body))
        body += recs[i]
    if len(body) > LIM_INVOBJ:
        raise ValueError("INVOBJ.DAT (los objetos del inventario): %d bytes, caben %d (sobran %d)"
                         % (len(body), LIM_INVOBJ, len(body) - LIM_INVOBJ))
    return struct.pack("<H", n) + bytes(index) + bytes(body)


def game_ops(game):
    """(nombre, args) de cada instruccion de todos los scripts (los globales, los de
    cada habitacion y los bloques VERB de sus objetos, desde cada verbo), de corrido."""
    import opcodes as O
    codes = []
    for i in range(len(game.index.dirs.get("DSCR", []))):
        r = game.resource("DSCR", i)
        if r is not None:
            codes.append((bytes(game.data[r[1]:r[2]]), [0]))
    for n in game.rooms():
        try:
            sc = S.room_scripts(game.room(n))
        except Exception:                       # noqa: BLE001
            continue
        for k, v in sc.items():
            if isinstance(k, tuple) and k[0] == "verbs":
                continue
            starts = sorted(set(o for _, o in sc[("verbs", k[1])])) if isinstance(k, tuple) else [0]
            codes.append((v, starts))
    for code, starts in codes:
        seen = set()
        for st in starts:
            pc = st
            while pc < len(code) and pc not in seen:
                seen.add(pc)
                try:
                    op, name, args, nxt = O.decode(code, pc)
                except O.Bad:
                    break
                yield name, args
                pc = nxt


def verb_image_rooms(game):
    """Las habitaciones de donde salen las imagenes de los verbos (verbOps 22 con
    numeros fijos en cualquier script)."""
    rooms = set()
    for name, args in game_ops(game):
        if name == "verbOps":
            for k, prm in args[1:]:
                if k == 22 and isinstance(prm[1], int):
                    rooms.add(prm[1])
    return sorted(rooms)


def picked_objects(game):
    """Los objetos que algun script le da a alguien con un numero fijo (pickupObject,
    setOwnerOf): los que pueden llegar al inventario."""
    out = set()
    for name, args in game_ops(game):
        if name in ("pickupObject", "pickupObjectOld", "setOwnerOf") and isinstance(args[0], int):
            out.add(args[0])
    return out


def verbimg_file(game, skipped=None):
    """VERBIMG.DAT: numero (2) y entradas de 8 bytes (habitacion, objeto (2), ancho,
    alto, posicion (3)); cada imagen por columnas: alto pixeles y alto/8 bytes de
    mascara (bit 7 = la fila de arriba). Las de mas de 255 pixeles no van (a skipped)."""
    get = verb_images(game)
    entries = []
    for room in verb_image_rooms(game):
        try:
            objs = S.room_objects(game.room(room), game.index)
        except Exception:                       # noqa: BLE001
            continue
        for o in objs:
            img = get(room, o.id)
            if img is not None and img[0] <= 255 and img[1] <= 255:
                entries.append((room, o.id, img))
            elif img is not None and skipped is not None:
                skipped.append((room, o.id, img[0], img[1]))
    head = bytearray(struct.pack("<H", len(entries)))
    body = bytearray()
    base = 2 + 8 * len(entries)
    for room, oid, (w, h, pix, opq) in entries:
        head += struct.pack("<BHBB", room, oid, w, h) + (base + len(body)).to_bytes(3, "little")
        mb = (h + 7) // 8
        for x in range(w):
            body += bytes(pix[y][x] for y in range(h))
            m = bytearray(mb)
            for y in range(h):
                if opq[y][x]:
                    m[y >> 3] |= 0x80 >> (y & 7)
            body += m
    return bytes(head) + bytes(body)


def objects_file(game):
    """OBJ.DAT: numero de objetos, duenos, estados y clases."""
    objs = game.index.objects or []
    n = len(objs)
    out = bytearray(struct.pack("<H", n))
    out += bytes(o[0] for o in objs)
    out += bytes(o[1] for o in objs)
    for o in objs:
        out += struct.pack("<I", o[2] & 0xFFFFFFFF)
    return bytes(out)


def find_game(folder, name=None):
    if name is None:
        cands = sorted(glob.glob(os.path.join(folder, "*.000")))
        if not cands:
            raise SystemExit("no hay ningun .000 en %s" % folder)
        name = os.path.splitext(os.path.basename(cands[0]))[0]
    p0 = os.path.join(folder, name + ".000")
    p1 = os.path.join(folder, name + ".001")
    return S.Game(p0, p1), name


class Card:
    """Los ficheros del Next de un juego, en memoria (files: nombre -> bytes), y lo que
    no cabe en el Next (bad: una linea por cosa, con cuanto se pasa)."""

    def __init__(self, game, folder, player_costume=None, first_room=None, progress=None):
        """progress(k, n): va por la habitacion k de n (puede lanzar una excepcion para
        parar)."""
        self.files = {}
        self.bad = []
        self.notes = []                     # (avisos que no impiden que quepa)
        ix = game.index
        self.rooms = []
        pages = {}
        todas = game.rooms()
        for k, n in enumerate(todas):
            if progress:
                progress(k, len(todas))
            try:
                rd = RoomData(game.room(n), ix)
                data = room_file(rd)
            except Exception as e:          # una habitacion rara no para el resto
                why = str(e)
                if why.startswith("habitacion %d: " % n):
                    why = why[len("habitacion %d: " % n):]
                self.bad.append("habitacion %d: %s" % (n, why))
                continue
            self.files["R%03d.DAT" % n] = data
            self.rooms.append(n)
            pages[n] = data[31]
        self.files["SCRIPTS.DAT"] = scripts_file(game)
        self.size("SCRIPTS.DAT (los scripts globales)", len(self.files["SCRIPTS.DAT"]), LIM_SCRIPTS)
        dscr = ix.dirs.get("DSCR", [])
        lost = [i for i in range(LIM_GLOBAL, len(dscr)) if game.resource("DSCR", i)]
        if lost:
            self.bad.append("scripts globales: %d con numero %d o mas (caben del 0 al %d)"
                            % (len(lost), LIM_GLOBAL, LIM_GLOBAL - 1))
        nobj = len(ix.objects or [])
        self.files["OBJ.DAT"] = objects_file(game)
        self.size("objetos (OBJ.DAT)", nobj, LIM_OBJECTS, "")
        mx = ix.maxs
        for k, what, lim in ((0, "variables", LIM_VARS), (2, "variables de un bit", LIM_BITS),
                             (8, "objetos en el inventario", LIM_INV)):
            if len(mx) > k:
                self.size(what + " (MAXS)", mx[k], lim, "")
        self.files["CHARS.DAT"] = charsets_file(game)
        self.size("CHARS.DAT (las fuentes)", len(self.files["CHARS.DAT"]), LIM_CHARS)
        dchr = ix.dirs.get("DCHR", [])
        lost = [i for i in range(LIM_CHARSETS, len(dchr)) if game.resource("DCHR", i)]
        if lost:
            self.bad.append("fuentes: %d con numero %d o mas (caben de la 0 a la %d)"
                            % (len(lost), LIM_CHARSETS, LIM_CHARSETS - 1))
        skipped = []
        vi = self.files["VERBIMG.DAT"] = verbimg_file(game, skipped)
        nvi = struct.unpack_from("<H", vi)[0]
        self.size("imagenes de verbo (VERBIMG.DAT)", nvi, LIM_VERBIMG, "")
        tall = [vi[2 + 8 * k + 4] for k in range(nvi) if vi[2 + 8 * k + 4] > LIM_VERBIMG_H]
        tall += [h for _, _, w, h in skipped]
        if tall:
            self.bad.append("imagenes de verbo: %d de mas de %d pixeles de alto (la mas alta, %d)"
                            % (len(tall), LIM_VERBIMG_H, max(tall)))
        try:
            iv = self.files["INVOBJ.DAT"] = invobj_file(game)
        except ValueError as e:
            self.bad.append(str(e))
            iv = None
        if iv is not None:                  # el bloque VERB de los que pueden llegar al inventario
            n = struct.unpack_from("<H", iv)[0]
            big = []
            for o in sorted(picked_objects(game)):
                p = struct.unpack_from("<H", iv, 2 + 2 * o)[0] if 0 < o < n else 0xFFFF
                if p != 0xFFFF:
                    ln = struct.unpack_from("<H", iv, 2 + 2 * n + p)[0]
                    if ln > LIM_INVCODE:
                        big.append((o, ln))
            if big:
                self.bad.append("objetos del inventario: %d con el bloque de verbos de mas de %d "
                                "bytes (el %d, %d); no harian nada"
                                % (len(big), LIM_INVCODE, big[0][0], big[0][1]))
        self.sres = SN.sound_resources(game)    # los efectos y las pistas del CD (duraciones)
        try:
            info = {}
            snd = self.files["SOUNDS.DAT"] = SN.sounds_file(self.sres, SN.sound_table(self.sres, folder),
                                                            LIM_SOUNDS - SN.SAMPLES_AT, info)
            self.size("SOUNDS.DAT (los efectos)", len(snd), LIM_SOUNDS)
            if info.get("fuera"):
                self.notes.append("sonidos de AdLib que no caben entre los efectos (no sonaran, "
                                  "aunque para los scripts si suenan): %s" % info["fuera"])
        except ValueError as e:
            self.bad.append("SOUNDS.DAT: %s" % e)
        long_ = [k for k, r in self.sres.items() if r["kind"] == SN.SBL and len(r["data"]) > LIM_SAMPLE]
        if long_:
            self.bad.append("efectos: %d de mas de %d bytes (se cortan; el %d)"
                            % (len(long_), LIM_SAMPLE, long_[0]))
        self.costs = []
        for i in range(len(ix.dirs.get("DCOS", []))):
            r = game.resource("DCOS", i)
            if r is None:
                continue
            tag, a, b = r
            blk = game.data[a - 8:b]
            try:
                S.Costume(blk, i)
            except ValueError as e:
                self.bad.append("costume %d: %s" % (i, e))
                continue
            if i > LIM_NUMBER:
                self.bad.append("costume %d: los numeros llegan hasta %d" % (i, LIM_NUMBER))
                continue
            self.files["C%03d.DAT" % i] = bytes(blk)
            self.costs.append(i)
        if player_costume is None or player_costume not in self.costs:
            player_costume = self.costs[0] if self.costs else 0
        ego = len(self.files.get("C%03d.DAT" % player_costume, b""))
        self.size("costume %d (el del protagonista)" % player_costume, ego, LIM_EGO)
        if pages:                           # los demas, detras de los datos de la habitacion
            free = LIM_CAST_PAGES - min(pages.values())
            for i in self.costs:
                pg = (len(self.files["C%03d.DAT" % i]) + PAGE - 1) // PAGE
                if i != player_costume and pg > free:
                    self.bad.append("costume %d: %d paginas; no cabe ni detras de la habitacion "
                                    "mas pequena (%d libres)" % (i, pg, free))
        if not self.rooms:
            self.bad.append("ninguna habitacion")
        if first_room is None or first_room not in self.rooms:
            first_room = self.rooms[0] if self.rooms else 0
        # GAME.DAT: firma, primera habitacion, costume del protagonista,
        # habitaciones (n + lista) y costumes (n + lista)
        if len(self.costs) > LIM_NUMBER:
            self.size("costumes", len(self.costs), LIM_NUMBER, "")
            self.costs = self.costs[:LIM_NUMBER]
        hdr = struct.pack("<4sBBB", b"SG5\x01", first_room, player_costume, len(self.rooms))
        hdr += bytes(self.rooms) + bytes((len(self.costs),)) + bytes(self.costs)
        self.files["GAME.DAT"] = hdr
        self.size("GAME.DAT (la lista de habitaciones y costumes)", len(hdr), LIM_GAMEDAT)

    def size(self, what, n, lim, unit="bytes"):
        if n > lim:
            u = " " + unit if unit else ""
            self.bad.append("%s: %d%s, caben %d (sobran %d)" % (what, n, u, lim, n - lim))

    def report(self, log=print):
        """Todo cabe, o la lista de lo que no cabe. True si cabe."""
        for nt in self.notes:
            log("aviso: " + nt)
        if not self.bad:
            log("todo cabe en el Next")
            return True
        log("NO CABE en el Next (%d):" % len(self.bad))
        for b in self.bad:
            log("  - " + b)
        return False


def convert(folder, name=None, out=None, player_costume=None, first_room=None, log=print,
            title=None, problems=None):
    """Convierte el juego y dice si cabe; lo que no cabe, tambien a problems (una lista)."""
    game, name = find_game(folder, name)
    out = out or os.path.join(ROOT, "build", "data")
    os.makedirs(out, exist_ok=True)
    if title:                           # el nombre en el menu de juegos (Latin-1, una linea)
        with open(os.path.join(out, "TITULO.TXT"), "wb") as f:
            f.write(title.strip()[:31].encode("latin-1", "replace") + bytes((13, 10)))
    card = Card(game, folder, player_costume, first_room)
    for fn, data in card.files.items():
        with open(os.path.join(out, fn), "wb") as f:
            f.write(data)
    tracks = SN.music_files(card.sres, folder, out, log)   # la musica del CD (Tnn.DAT)
    if tracks:
        log("musica: %d pistas del CD" % len(tracks))
    log("%s: %d habitaciones y %d costumes en %s" % (name, len(card.rooms), len(card.costs), out))
    if not card.report(log):
        log("(los ficheros estan escritos, pero en el Next eso fallaria)")
    if problems is not None:
        problems.extend(card.bad)
    return game, card.rooms, card.costs


def list_game(folder, name=None, player_costume=None):
    """Lo que hay en el juego: habitaciones y costumes (solo datos, sin imagenes), y si
    cabe en el Next (sin escribir nada). True si cabe."""
    game, name = find_game(folder, name)
    print("%s: %d habitaciones" % (name, len(game.rooms())))
    for n in game.rooms():
        try:
            r = game.room(n)
            print("  habitacion %3d %-10s %4dx%3d  %2d cajas" % (
                n, game.index.room_names.get(n, ""), r.width, r.height, len(r.boxes)))
        except Exception as e:
            print("  habitacion %3d: %s" % (n, e))
    print("costumes:")
    for i in range(len(game.index.dirs.get("DCOS", []))):
        r = game.resource("DCOS", i)
        if r is None:
            continue
        tag, a, b = r
        try:
            c = S.Costume(game.data[a - 8:b], i)
            limbs = sorted({x[0] for k in range(c.num_anim + 1) for x in (c.anim(k) or [])})
            print("  costume %3d  %6d bytes  %3d animaciones  %2d colores  miembros %s" % (
                i, b - a + 8, c.num_anim + 1, c.num_colors, limbs))
        except ValueError as e:
            print("  costume %3d: %s" % (i, e))
    return Card(game, folder, player_costume).report()


def main():
    import argparse
    ap = argparse.ArgumentParser(description="Convierte un juego SCUMM v5 para el Next.")
    ap.add_argument("carpeta", help="carpeta con NOMBRE.000 y NOMBRE.001")
    ap.add_argument("nombre", nargs="?", help="por ejemplo MONKEY (por defecto, el primer .000)")
    ap.add_argument("salida", nargs="?", help="carpeta de datos (por defecto build/data)")
    ap.add_argument("--costume", type=int, help="costume del protagonista")
    ap.add_argument("--room", type=int, help="primera habitacion")
    ap.add_argument("--list", action="store_true",
                    help="solo lista habitaciones y costumes, y dice si cabe")
    ap.add_argument("--titulo", help="el nombre en el menu de juegos (TITULO.TXT)")
    a = ap.parse_args()
    if a.list:
        ok = list_game(a.carpeta, a.nombre, a.costume)
    else:
        bad = []
        convert(a.carpeta, a.nombre, a.salida, a.costume, a.room, title=a.titulo, problems=bad)
        ok = not bad
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
