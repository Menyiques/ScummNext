"""Lector de recursos SCUMM v5 (juegos de LucasArts en version CD/VGA).

Lee el indice (NNN.000) y el fichero de datos (NNN.001), los dos cifrados con
XOR 0x69, y decodifica lo que necesita el Next:

- fondos de habitacion (SMAP) e imagenes de objeto, en tiras de 8 pixeles;
- planos Z (ZP01..), que dicen que pixeles tapan a los actores;
- la paleta (CLUT), las cajas por donde se anda (BOXD, BOXM) y las escalas (SCAL);
- los costumes (COST): animaciones, miembros y dibujos RLE.

Tambien tiene los codificadores inversos, para que tools/fixture.py pueda
fabricar un juego de prueba propio en el mismo formato.

Nada de esto lleva datos de ningun juego: solo sabe leer el formato.
"""
import os
import struct

import numpy as np

XOR = 0x69


def cdiv(a, b):
    """Division entera de C (trunca hacia cero)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def le16(b, o):
    return b[o] | b[o + 1] << 8


def les16(b, o):
    v = b[o] | b[o + 1] << 8
    return v - 0x10000 if v & 0x8000 else v


def le32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def be32(b, o):
    return struct.unpack_from(">I", b, o)[0]


def read_xor(path):
    return (np.fromfile(path, dtype=np.uint8) ^ XOR).tobytes()


def write_xor(path, data):
    (np.frombuffer(bytes(data), dtype=np.uint8) ^ XOR).tofile(path)


def blocks(buf, start, end):
    """Bloques (tag, inicio de los datos, fin) entre start y end."""
    o = start
    while o + 8 <= end:
        tag = buf[o:o + 4].decode("latin1")
        size = be32(buf, o + 4)
        if size < 8 or o + size > end:
            raise ValueError("bloque %r roto en %d (tamano %d)" % (tag, o, size))
        yield tag, o + 8, o + size
        o += size


def block_at(buf, o):
    tag = buf[o:o + 4].decode("latin1")
    return tag, o + 8, o + be32(buf, o + 4)


def make_block(tag, payload):
    return tag.encode("latin1") + struct.pack(">I", len(payload) + 8) + bytes(payload)


# ---------------------------------------------------------------------------
# Indice y fichero de datos
# ---------------------------------------------------------------------------
DIR_TAGS = ("DROO", "DSCR", "DSOU", "DCOS", "DCHR")


class Index:
    def __init__(self, buf):
        self.room_names = {}
        self.dirs = {}
        self.maxs = ()
        self.objects = None
        for tag, a, b in blocks(buf, 0, len(buf)):
            d = buf[a:b]
            if tag == "RNAM":
                o = 0
                while o < len(d) and d[o]:
                    name = bytes(c ^ 0xFF for c in d[o + 1:o + 10]).split(b"\0")[0]
                    self.room_names[d[o]] = name.decode("latin1")
                    o += 10
            elif tag == "MAXS":
                self.maxs = struct.unpack_from("<%dH" % (len(d) // 2), d)
            elif tag in DIR_TAGS:
                n = le16(d, 0)
                rooms = d[2:2 + n]
                offs = struct.unpack_from("<%dI" % n, d, 2 + n)
                self.dirs[tag] = list(zip(rooms, offs))
            elif tag == "DOBJ":
                n = le16(d, 0)
                own = d[2:2 + n]
                cls = struct.unpack_from("<%dI" % n, d, 2 + n)
                self.objects = [(o & 15, o >> 4, c) for o, c in zip(own, cls)]


class Game:
    """Un juego SCUMM v5: indice + fichero de datos."""

    def __init__(self, path000, path001):
        self.folder = os.path.dirname(os.path.abspath(path000))     # (y las pistas del CD)
        self.index = Index(read_xor(path000))
        self.data = read_xor(path001)
        tag, a, b = block_at(self.data, 0)
        if tag != "LECF":
            raise ValueError("%s no empieza por LECF (%r)" % (path001, tag))
        self.room_offs = {}
        for t, a2, b2 in blocks(self.data, a, b):
            if t == "LOFF":
                for i in range(self.data[a2]):
                    room, off = struct.unpack_from("<BI", self.data, a2 + 1 + 5 * i)
                    self.room_offs[room] = off
        self._rooms = {}

    def rooms(self):
        return sorted(self.room_offs)

    def room(self, n):
        if n not in self._rooms:
            self._rooms[n] = Room(self.data, self.room_offs[n], n)
        return self._rooms[n]

    def resource(self, dir_tag, idx):
        """(tag, inicio, fin) del recurso idx del directorio dir_tag."""
        room, off = self.index.dirs[dir_tag][idx]
        if room == 0 or room not in self.room_offs:
            return None
        return block_at(self.data, self.room_offs[room] + off)

    def costume(self, idx):
        r = self.resource("DCOS", idx)
        if r is None:
            return None
        tag, a, b = r
        if tag != "COST":
            raise ValueError("costume %d: bloque %r" % (idx, tag))
        return Costume(self.data[a - 8:b], idx)


# ---------------------------------------------------------------------------
# Habitaciones
# ---------------------------------------------------------------------------
class Box:
    __slots__ = ("ul", "ur", "lr", "ll", "mask", "flags", "scale")

    def __init__(self, ul, ur, lr, ll, mask=0, flags=0, scale=255):
        self.ul, self.ur, self.lr, self.ll = ul, ur, lr, ll
        self.mask, self.flags, self.scale = mask, flags, scale

    def corners(self):
        return [self.ul, self.ur, self.lr, self.ll]

    def pack(self):
        return struct.pack("<8hBBH", *self.ul, *self.ur, *self.lr, *self.ll,
                           self.mask, self.flags, self.scale)


BOX_SIZE = 20


class Room:
    def __init__(self, buf, off, num=0):
        self.num = num
        tag, a, b = block_at(buf, off)
        if tag != "ROOM":
            raise ValueError("habitacion %d: bloque %r en %d" % (num, tag, off))
        self.buf = buf
        self.sub = {}
        self.objects_im = []
        self.objects_cd = []
        self.local_scripts = []
        for t, a2, b2 in blocks(buf, a, b):
            if t == "OBIM":
                self.objects_im.append((a2, b2))
            elif t == "OBCD":
                self.objects_cd.append((a2, b2))
            elif t == "LSCR":
                self.local_scripts.append((a2, b2))
            else:
                self.sub[t] = (a2, b2)
        d = self.data("RMHD")
        self.width, self.height, self.num_objects = struct.unpack_from("<3H", d)
        self.palette = np.frombuffer(self.data("CLUT")[:768], dtype=np.uint8).reshape(256, 3)
        t = self.data("TRNS")
        self.trans = le16(t, 0) if t else 0
        self.boxes = self._boxes()
        self.matrix = self.data("BOXM") or b""
        s = self.data("SCAL")
        self.scale_slots = [struct.unpack_from("<4H", s, 8 * i) for i in range(len(s) // 8)] if s else []
        self.cycles = self.data("CYCL") or b""

    def data(self, tag):
        if tag not in self.sub:
            return None
        a, b = self.sub[tag]
        return self.buf[a:b]

    def _boxes(self):
        d = self.data("BOXD")
        if not d:
            return []
        out = []
        for i in range(d[0]):
            v = struct.unpack_from("<8hBBH", d, 2 + BOX_SIZE * i)
            out.append(Box(v[0:2], v[2:4], v[4:6], v[6:8], v[8], v[9], v[10]))
        return out

    def _image(self):
        """Bloques del IM00 de RMIM: {tag: (a, b)} y numero de planos Z."""
        a, b = self.sub["RMIM"]
        nz, im = 0, None
        for t, a2, b2 in blocks(self.buf, a, b):
            if t == "RMIH":
                nz = le16(self.buf, a2)
            elif t == "IM00":
                im = {t3: (a3, b3) for t3, a3, b3 in blocks(self.buf, a2, b2)}
        return im, nz

    def background(self):
        """Fondo (height, width) en indices de la paleta."""
        im, _ = self._image()
        a, b = im["SMAP"]
        img, _ = decode_smap(self.buf[a - 8:b], self.width, self.height, self.trans)
        return img

    def zplanes(self):
        """Planos Z empaquetados: lista de (height, width/8) uint8, bit 7 = pixel izquierdo."""
        im, nz = self._image()
        out = []
        for i in range(1, nz + 1):
            tag = "ZP%02d" % i
            if tag in im:
                a, b = im[tag]
                out.append(decode_zplane(self.buf[a - 8:b], self.width, self.height))
            else:
                out.append(np.zeros((self.height, self.width // 8), dtype=np.uint8))
        return out

    def get_next_box(self, frm, to):
        """BOXM: la caja siguiente para ir de frm a to (-1 si no hay camino)."""
        if frm == to:
            return to
        if to == INVALID_BOX:
            return -1
        if frm == INVALID_BOX:
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


INVALID_BOX = 255


# ---------------------------------------------------------------------------
# Tiras de imagen (SMAP / OBIM)
# ---------------------------------------------------------------------------
class _Bits:
    """El lector de bits de SCUMM (macros FILL_BITS / READ_BIT de ScummVM)."""
    __slots__ = ("src", "p", "bits", "cl")

    def __init__(self, src, p):
        self.src = src
        self.bits = src[p]
        self.p = p + 1
        self.cl = 8

    def fill(self):
        if self.cl <= 8:
            self.bits |= self.src[self.p] << self.cl
            self.p += 1
            self.cl += 8

    def bit(self):
        self.cl -= 1
        b = self.bits & 1
        self.bits >>= 1
        return b


def strip_basic(src, p, h, shr, vertical):
    """Codigos 14-18/24-28 (y 34-38/44-48 con transparencia): 8*h pixeles."""
    out = np.zeros((h, 8), dtype=np.uint8)
    color = src[p]
    bs = _Bits(src, p + 1)
    mask = 0xFF >> (8 - shr)
    inc = -1
    order = [(y, x) for x in range(8) for y in range(h)] if vertical else \
            [(y, x) for y in range(h) for x in range(8)]
    for y, x in order:
        bs.fill()
        out[y, x] = color
        if not bs.bit():
            pass
        elif not bs.bit():
            bs.fill()
            color = bs.bits & mask
            bs.bits >>= shr
            bs.cl -= shr
            inc = -1
        elif not bs.bit():
            color = (color + inc) & 0xFF
        else:
            inc = -inc
            color = (color + inc) & 0xFF
    return out


def strip_complex(src, p, h, shr):
    """Codigos 64-68/104-108 (y 84-88/124-128 con transparencia)."""
    out = np.zeros(8 * h, dtype=np.uint8)
    color = src[p]
    bs = _Bits(src, p + 1)
    mask = 0xFF >> (8 - shr)
    n = 8 * h
    i = 0
    while i < n:
        bs.fill()
        out[i] = color
        i += 1
        while True:                         # againPos
            if not bs.bit():
                break
            if not bs.bit():
                bs.fill()
                color = bs.bits & mask
                bs.bits >>= shr
                bs.cl -= shr
                break
            incm = (bs.bits & 7) - 4
            bs.cl -= 3
            bs.bits >>= 3
            if incm:
                color = (color + incm) & 0xFF
                break
            bs.fill()
            reps = bs.bits & 0xFF or 256
            for _ in range(reps):
                if i >= n:
                    return out.reshape(h, 8)
                out[i] = color
                i += 1
            # el original sale en cuanto se acaba la tira, antes de mirar mas bits
            bs.bits >>= 8
            bs.bits |= bs.src[bs.p] << (bs.cl - 8)
            bs.p += 1
            if i >= n:
                return out.reshape(h, 8)
    return out.reshape(h, 8)


TRANSPARENT_CODES = set(range(34, 39)) | set(range(44, 49)) | set(range(84, 89)) | set(range(124, 129))


def decode_strip(src, p, h):
    """Una tira de 8 pixeles de ancho. Devuelve (pixeles, usa_transparencia)."""
    code = src[p]
    p += 1
    shr = code % 10
    if code == 1:
        return np.frombuffer(src[p:p + 8 * h], dtype=np.uint8).reshape(h, 8).copy(), False
    if 14 <= code <= 18 or 34 <= code <= 38:
        return strip_basic(src, p, h, shr, True), code >= 34
    if 24 <= code <= 28 or 44 <= code <= 48:
        return strip_basic(src, p, h, shr, False), code >= 44
    if 64 <= code <= 68 or 104 <= code <= 108:
        return strip_complex(src, p, h, shr), False
    if 84 <= code <= 88 or 124 <= code <= 128:
        return strip_complex(src, p, h, shr), True
    raise ValueError("codigo de tira %d no soportado" % code)


def decode_smap(smap, width, height, trans=None):
    """SMAP completo (con su cabecera de 8 bytes). Devuelve (imagen, opaco)."""
    ns = width // 8
    img = np.zeros((height, width), dtype=np.uint8)
    opaque = np.ones((height, width), dtype=bool)
    smap = bytes(smap) + bytes(16)      # el lector de bits lee uno o dos bytes por delante
    for s in range(ns):
        off = le32(smap, 8 + 4 * s)
        px, transp = decode_strip(smap, off, height)
        img[:, 8 * s:8 * s + 8] = px
        if transp and trans is not None:
            opaque[:, 8 * s:8 * s + 8] = px != trans
    return img, opaque


def decode_zplane(zp, width, height):
    """ZPnn (con su cabecera): (height, width/8) bytes de mascara."""
    ns = width // 8
    out = np.zeros((height, ns), dtype=np.uint8)
    for s in range(ns):
        off = le16(zp, 8 + 2 * s)
        if not off:
            continue
        p = off
        y = 0
        while y < height:
            b = zp[p]
            p += 1
            if b & 0x80:
                b &= 0x7F
                c = zp[p]
                p += 1
                while True:
                    out[y, s] = c
                    y += 1
                    b -= 1
                    if not b or y >= height:
                        break
            else:
                while True:
                    out[y, s] = zp[p]
                    p += 1
                    y += 1
                    b -= 1
                    if not b or y >= height:
                        break
    return out


def unpack_mask(zp):
    """(h, w/8) bytes -> (h, w) bool."""
    return np.unpackbits(zp, axis=1).astype(bool)


# --- codificadores (para el juego de prueba) --------------------------------
class _BitWriter:
    def __init__(self):
        self.out = bytearray()
        self.acc = 0
        self.n = 0

    def put(self, value, nbits):
        """nbits bits de value, del menos significativo al mas."""
        for i in range(nbits):
            self.acc |= ((value >> i) & 1) << self.n
            self.n += 1
            if self.n == 8:
                self.out.append(self.acc)
                self.acc = 0
                self.n = 0

    def flush(self):
        if self.n:
            self.out.append(self.acc)
            self.acc = 0
            self.n = 0
        return bytes(self.out)


def encode_strip_basic(px, shr=8, vertical=False):
    """Codifica una tira (h, 8) con el metodo basico: igual, +-1 o color nuevo."""
    code = (10 if vertical else 20) + shr
    h = px.shape[0]
    seq = [int(px[y, x]) for x in range(8) for y in range(h)] if vertical else \
          [int(px[y, x]) for y in range(h) for x in range(8)]
    w = _BitWriter()
    color = seq[0]
    inc = -1
    for v in seq[1:]:
        if v == color:
            w.put(0, 1)
        elif v == (color + inc) & 0xFF:
            w.put(0b011, 3)                 # 1,1,0
            color = v
        elif v == (color - inc) & 0xFF:
            w.put(0b111, 3)                 # 1,1,1
            inc = -inc
            color = v
        else:
            w.put(0b01, 2)                  # 1,0
            w.put(v, shr)
            color = v
            inc = -1
    w.put(0, 8)                             # relleno: el lector lee por delante
    return bytes((code, seq[0])) + w.flush()


def encode_strip_complex(px, shr=8):
    """Codifica una tira (h, 8) con el metodo complejo (con repeticiones)."""
    code = 60 + shr
    seq = [int(v) for v in px.reshape(-1)]
    n = len(seq)
    w = _BitWriter()
    color = seq[0]
    i = 1
    while i < n:
        v = seq[i]
        run = 1
        while i + run < n and seq[i + run] == color and run < 255:
            run += 1
        if v == color and run >= 4:
            w.put(1, 1)
            w.put(1, 1)
            w.put(4, 3)                     # incm = 0: repeticion
            w.put(run, 8)
            i += run
            # tras la repeticion se vuelve a mirar el siguiente comando sin pintar
            if i < n:
                v = seq[i]
                d = (v - color) & 0xFF
                if d == 0:
                    w.put(0, 1)
                elif d <= 3 or d >= 252:
                    incm = d if d <= 3 else d - 256
                    w.put(1, 1)
                    w.put(1, 1)
                    w.put(incm + 4, 3)
                else:
                    w.put(1, 1)
                    w.put(0, 1)
                    w.put(v, shr)
                color = v
                i += 1
            continue
        d = (v - color) & 0xFF
        if d == 0:
            w.put(0, 1)
        elif d <= 3 or d >= 252:
            incm = d if d <= 3 else d - 256
            w.put(1, 1)
            w.put(1, 1)
            w.put(incm + 4, 3)
        else:
            w.put(1, 1)
            w.put(0, 1)
            w.put(v, shr)
        color = v
        i += 1
    w.put(0, 16)
    return bytes((code, seq[0])) + w.flush()


def encode_smap(img, method="mix"):
    """Imagen (h, w) -> bloque SMAP. method: raw, basic, complex o mix (alterna)."""
    h, wd = img.shape
    ns = wd // 8
    strips = []
    for s in range(ns):
        px = img[:, 8 * s:8 * s + 8]
        m = method if method != "mix" else ("complex", "basic", "basicv", "raw")[s % 4]
        if m == "raw":
            strips.append(bytes((1,)) + px.tobytes())
        elif m == "basic":
            strips.append(encode_strip_basic(px, 8, False))
        elif m == "basicv":
            strips.append(encode_strip_basic(px, 8, True))
        else:
            strips.append(encode_strip_complex(px, 8))
    offs = []
    o = 8 + 4 * ns
    for s in strips:
        offs.append(o)
        o += len(s)
    return make_block("SMAP", struct.pack("<%dI" % ns, *offs) + b"".join(strips))


def encode_zplane(tag, mask):
    """mask (h, w) bool -> bloque ZPnn (RLE de SCUMM; tiras vacias con offset 0)."""
    h, wd = mask.shape
    ns = wd // 8
    packed = np.packbits(mask.astype(np.uint8), axis=1)
    body = bytearray()
    offs = []
    base = 8 + 2 * ns
    for s in range(ns):
        col = packed[:, s]
        if not col.any():
            offs.append(0)
            continue
        offs.append(base + len(body))
        y = 0
        while y < h:
            run = 1
            while y + run < h and col[y + run] == col[y] and run < 127:
                run += 1
            if run >= 3:
                body += bytes((0x80 | run, col[y]))
                y += run
            else:
                lit = []
                while y < h and len(lit) < 127:
                    r = 1
                    while y + r < h and col[y + r] == col[y] and r < 3:
                        r += 1
                    if r >= 3:
                        break
                    lit.append(col[y])
                    y += 1
                body += bytes((len(lit),)) + bytes(lit)
    return make_block(tag, struct.pack("<%dH" % ns, *offs) + bytes(body))


# ---------------------------------------------------------------------------
# Costumes
# ---------------------------------------------------------------------------
class Picture:
    __slots__ = ("width", "height", "rel_x", "rel_y", "move_x", "move_y", "data")

    def __init__(self, width, height, rel_x, rel_y, move_x, move_y, data):
        self.width, self.height = width, height
        self.rel_x, self.rel_y, self.move_x, self.move_y = rel_x, rel_y, move_x, move_y
        self.data = data            # el RLE tal cual, desde el primer byte


class Costume:
    """COST de v5. Los offsets son relativos a base = inicio del bloque + 2."""

    def __init__(self, blk, idx=0):
        self.idx = idx
        self.blk = blk
        b = self.base = 2
        self.num_anim = blk[b + 6]
        fmt = blk[b + 7]
        self.format = fmt & 0x7F
        self.no_mirror = bool(fmt & 0x80)
        if self.format not in (0x58, 0x59):
            raise ValueError("costume %d: formato %#x" % (idx, self.format))
        self.num_colors = 16 if self.format == 0x58 else 32
        self.shr = 4 if self.num_colors == 16 else 3
        self.rle_mask = 15 if self.num_colors == 16 else 7
        p = b + 8
        self.palette = list(blk[p:p + self.num_colors])
        p += self.num_colors
        self.anim_cmds_off = le16(blk, p)
        self.limb_table = p + 2             # 16 offsets de miembro
        self.anim_table = p + 34            # num_anim+1 offsets de animacion
        self.cmds = blk[b + self.anim_cmds_off:]

    def abs(self, off):
        return self.base + off

    def anim(self, a):
        """Animacion a: lista de (miembro, inicio, fin, sin_bucle) o 'stop'/'start'."""
        if a > self.num_anim:
            return None
        off = le16(self.blk, self.anim_table + 2 * a)
        if off == 0:
            return None
        r = self.abs(off)
        mask = le16(self.blk, r)
        r += 2
        out = []
        for limb in range(16):
            if mask & (0x8000 >> limb):
                j = le16(self.blk, r)
                r += 2
                if j == 0xFFFF:
                    out.append((limb, "hide"))
                else:
                    extra = self.blk[r]
                    r += 1
                    out.append((limb, j, j + (extra & 0x7F), bool(extra & 0x80)))
        return out

    def limb_picture(self, limb, code):
        frameptr = self.abs(le16(self.blk, self.limb_table + 2 * limb))
        p = self.abs(le16(self.blk, frameptr + 2 * code))
        v = struct.unpack_from("<2H4h", self.blk, p)
        return Picture(*v, p + 12)

    def decode_picture(self, pic):
        """(height, width) de indices 0..num_colors-1 (0 = transparente)."""
        h, w = pic.height, pic.width
        out = np.zeros(w * h, dtype=np.uint8)       # por columnas
        src = self.blk
        p = pic.data
        i = 0
        n = w * h
        while i < n:
            b = src[p]
            p += 1
            color = b >> self.shr
            run = b & self.rle_mask
            if not run:
                run = src[p] or 256
                p += 1
            k = min(run, n - i)
            out[i:i + k] = color
            i += run
        return out.reshape(w, h).T


def encode_costume(num_anim, palette, anims, limbs, no_mirror=False, colors=16):
    """Fabrica un COST de v5 con dibujos de 16 o 32 colores.

    anims: lista de num_anim+1 entradas; cada una None o lista de
           (miembro, [codigos], sin_bucle) o (miembro, None) para ocultar.
    limbs: {miembro: [Picture con data = array (h, w) de indices]}.
    Los codigos de cada animacion se copian seguidos a la lista de comandos.
    """
    # cabecera: num_anim, formato, paleta, off cmds, 16 miembros, anims
    hdr = 2 + colors + 2 + 32 + 2 * (num_anim + 1)
    # base = inicio del bloque + 2 -> offset = 6 + posicion en el payload
    def off(pos):
        return 6 + pos
    anim_data = bytearray()
    anim_offs = []
    cmd_list = []
    for a in anims:
        if a is None:
            anim_offs.append(None)
            continue
        mask = 0
        entries = bytearray()
        for item in a:
            mask |= 0x8000 >> item[0]
        for item in sorted(a, key=lambda t: t[0]):
            if item[1] is None:
                entries += struct.pack("<H", 0xFFFF)
            else:
                limb, seq, noloop = item[0], item[1], item[2]
                start = len(cmd_list)
                cmd_list.extend(seq)
                entries += struct.pack("<HB", start, (len(seq) - 1) | (0x80 if noloop else 0))
        anim_offs.append(len(anim_data))
        anim_data += struct.pack("<H", mask) + entries
    cmds = bytes(cmd_list)
    # dibujos
    pics = bytearray()
    limb_tables = bytearray()
    limb_offs = {}
    pic_base = hdr + len(anim_data) + len(cmds)
    tables_size = sum(2 * len(limbs[l]) for l in limbs)
    pic_pos = pic_base + tables_size
    for limb in sorted(limbs):
        limb_offs[limb] = pic_base + len(limb_tables)
        for pic in limbs[limb]:
            limb_tables += struct.pack("<H", off(pic_pos + len(pics)))
            pics += struct.pack("<2H4h", pic.width, pic.height, pic.rel_x, pic.rel_y,
                                pic.move_x, pic.move_y) + rle_costume(pic.data, colors)
    payload = bytearray()
    payload += bytes((num_anim, (0x58 if colors == 16 else 0x59) | (0x80 if no_mirror else 0)))
    payload += bytes(palette[:colors]) + bytes(colors - len(palette[:colors]))
    payload += struct.pack("<H", off(hdr + len(anim_data)))
    empty = limb_offs[min(limb_offs)]
    for limb in range(16):
        payload += struct.pack("<H", off(limb_offs.get(limb, empty)))
    for ao in anim_offs:
        payload += struct.pack("<H", 0 if ao is None else off(hdr + ao))
    assert len(payload) == hdr
    payload += anim_data + cmds + limb_tables + pics
    return make_block("COST", payload)


def rle_costume(px, colors=16):
    """(h, w) de indices -> RLE de costume (por columnas).
    16 colores: color en 4 bits y racha en 4; 32 colores: 5 y 3."""
    shr, rmax = (4, 15) if colors == 16 else (3, 7)
    seq = [int(v) for v in px.T.reshape(-1)]
    out = bytearray()
    i = 0
    while i < len(seq):
        c = seq[i]
        run = 1
        while i + run < len(seq) and seq[i + run] == c and run < 255:
            run += 1
        if run <= rmax:
            out.append(c << shr | run)
        else:
            out += bytes((c << shr, run))
        i += run
    return bytes(out)


# ---------------------------------------------------------------------------
# Objetos de una habitacion (OBCD + OBIM)
# ---------------------------------------------------------------------------
class ObjImage:
    """Imagen de un objeto para un estado: pixeles, cuales se pintan y planos Z."""
    __slots__ = ("pix", "opaque", "planes")

    def __init__(self, pix, opaque, planes):
        self.pix = pix              # (h, w) indices
        self.opaque = opaque        # (h, w) bool
        self.planes = planes        # {plano (1..): (h, w/8) uint8}


class RoomObject:
    __slots__ = ("id", "x", "y", "w", "h", "parent", "parentstate", "state", "images", "name",
                 "walk_x", "walk_y", "actor_dir")

    def __init__(self, oid, x, y, w, h, parent, parentstate, state, images, name="",
                 walk_x=0, walk_y=0, actor_dir=0):
        self.id, self.x, self.y, self.w, self.h = oid, x, y, w, h   # x y w en tiras y pixeles
        self.parent, self.parentstate, self.state = parent, parentstate, state
        self.images = images
        self.name = name
        self.walk_x, self.walk_y = walk_x, walk_y
        self.actor_dir = actor_dir            # hacia donde se mira al llegar (0-3, como los antiguos)


def room_objects(room, index=None):
    """Objetos en el orden de los OBCD (el de _objs en SCUMM, desde 1).
    x y ancho van en tiras de 8 pixeles; y y alto en pixeles."""
    buf = room.buf
    ims = {}
    for a, b in room.objects_im:
        sub = list(blocks(buf, a, b))
        hd = [t for t in sub if t[0] == "IMHD"]
        if not hd:
            continue
        oid = le16(buf, hd[0][1])
        imgs = {}
        for t, a2, b2 in sub:
            if t.startswith("IM") and t != "IMHD" and t[2:].isdigit():
                imgs[int(t[2:])] = {t3: (a3, b3) for t3, a3, b3 in blocks(buf, a2, b2)}
        ims[oid] = imgs
    out = []
    for a, b in room.objects_cd:
        sub = {t: (a2, b2) for t, a2, b2 in blocks(buf, a, b)}
        ca, _ = sub["CDHD"]
        oid, x, y, w, h, flags, parent, walk_x, walk_y = struct.unpack_from("<HBBBBBBhh", buf, ca)
        cb = sub["CDHD"][1]
        actor_dir = buf[ca + 12] if cb - ca > 12 else 0
        name = ""
        if "OBNA" in sub:
            na, nb = sub["OBNA"]
            name = bytes(buf[na:nb]).split(b"\0")[0].decode("latin1")
        pstate = 1 if flags == 0x80 else flags & 0xF
        state = 0
        if index is not None and index.objects and oid < len(index.objects):
            state = index.objects[oid][1]
        W, H = w * 8, h * 8
        images = []
        found = ims.get(oid, {})
        for n in range(1, (max(found) if found else 0) + 1):
            blk = found.get(n)
            if blk is None or "SMAP" not in blk or not W or not H:
                images.append(None)
                continue
            sa, sb = blk["SMAP"]
            pix, opaque = decode_smap(buf[sa - 8:sb], W, H, room.trans)
            planes = {}
            for t, (za, zb) in blk.items():
                if t.startswith("ZP") and t[2:].isdigit():
                    planes[int(t[2:])] = decode_zplane(buf[za - 8:zb], W, H)
            images.append(ObjImage(pix, opaque, planes))
        out.append(RoomObject(oid, x, y * 8, w, H, parent, pstate, state, images, name, walk_x, walk_y,
                              actor_dir))
    return out


def parse_cycles(data):
    """CYCL de v5 (initCycl): hasta 16 ciclos de color. Cada entrada: numero (1..16),
    2 bytes que no se usan, velocidad (BE16), flags (BE16), primer y ultimo color.
    Devuelve 16 huecos: None o (delay, flags, primero, ultimo), con delay =
    16384 / velocidad como en ScummVM (0: parado)."""
    out = [None] * 16
    p = 0
    data = bytes(data or b"")
    while p < len(data) and data[p]:
        j = data[p]
        if not 1 <= j <= 16 or p + 9 > len(data):
            raise ValueError("CYCL: ciclo %d" % j)
        rate = data[p + 3] << 8 | data[p + 4]
        flags = data[p + 5] << 8 | data[p + 6]
        start, end = data[p + 7], data[p + 8]
        out[j - 1] = ((16384 // rate) & 0xFFFF if rate else 0, flags, start, end)
        p += 9
    return out


def encode_cycles(cycles):
    """El bloque CYCL para (numero, velocidad, flags, primero, ultimo)."""
    out = bytearray()
    for j, rate, flags, start, end in cycles:
        out += bytes((j, 0, 0)) + struct.pack(">HH", rate, flags) + bytes((start, end))
    return bytes(out) + b"\0"


def room_scripts(room):
    """Codigo de la habitacion: {'encd', 'excd', n local, ('obj', id), ('verbs', id)}.
    Los offsets de los verbos de un objeto son desde el principio de su bloque
    VERB (con la cabecera); ('obj', id) es ese bloque entero."""
    buf = room.buf
    out = {}
    for t, k in (("ENCD", "encd"), ("EXCD", "excd")):
        if t in room.sub:
            a, b = room.sub[t]
            if b > a:
                out[k] = bytes(buf[a:b])
    for a, b in room.local_scripts:
        out[buf[a]] = bytes(buf[a + 1:b])
    for a, b in room.objects_cd:
        sub = {t: (a2, b2) for t, a2, b2 in blocks(buf, a, b)}
        if "VERB" not in sub or "CDHD" not in sub:
            continue
        oid = le16(buf, sub["CDHD"][0])
        va, vb = sub["VERB"]
        verbs = []
        p = va
        while p < vb and buf[p]:
            verbs.append((buf[p], le16(buf, p + 1)))
            p += 3
        if verbs:
            out[("obj", oid)] = bytes(buf[va - 8:vb])
            out[("verbs", oid)] = verbs
    return out


def encode_cdhd(oid, x, y, w, h, parent=0, parentstate=0, actor_dir=0):
    """CDHD de v5: x, y, ancho y alto en unidades de 8 pixeles."""
    flags = parentstate & 0xF
    return make_block("CDHD", struct.pack("<HBBBBBBhhB", oid, x, y // 8, w, h // 8, flags, parent,
                                          x * 8, y + h, actor_dir))
