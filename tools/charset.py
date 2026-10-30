"""Fuentes de SCUMM v5 (bloque CHAR) y el texto tal como lo pinta el motor.

El bloque, sin su cabecera de 8 bytes:
    0   tamano (4)
    4   version (2)
    6   15 colores (los indices 1 a 15 del mapa de colores)
    21  bits por pixel (1, 2 o 4), alto de la fuente, numero de caracteres (2)
    25  desplazamientos de cada caracter (4 bytes), desde el byte 21; 0 = no hay
Cada caracter: ancho, alto, desplazamiento x e y (con signo) y los pixeles
seguidos, fila a fila, sin rellenar al final de cada fila.
"""

FONT = 21                       # donde empieza la fuente dentro del bloque


class Charset:
    def __init__(self, data):
        self.data = bytes(data)
        f = self.data[FONT:]
        self.font = f
        self.colors = list(self.data[6:21])
        self.bpp = f[0]
        self.height = f[1]
        self.nchars = f[2] | f[3] << 8

    def offset(self, c):
        if not 0 <= c < self.nchars:
            return 0
        return int.from_bytes(self.font[4 + 4 * c:8 + 4 * c], "little")

    def glyph(self, c):
        """(ancho, alto, dx, dy, pixeles por filas) o None."""
        o = self.offset(c)
        if not o:
            return None
        f = self.font
        w, h = f[o], f[o + 1]
        dx = f[o + 2] - 256 if f[o + 2] & 0x80 else f[o + 2]
        dy = f[o + 3] - 256 if f[o + 3] & 0x80 else f[o + 3]
        bits = f[o + 4:]
        px = []
        pos = 0
        cur = bits[0] if bits else 0
        nb = 8
        bpp = self.bpp
        for _ in range(h):
            row = []
            for _ in range(w):
                row.append((cur >> (8 - bpp)) & ((1 << bpp) - 1))
                cur = (cur << bpp) & 0xFF
                nb -= bpp
                if nb == 0:
                    pos += 1
                    cur = bits[pos] if pos < len(bits) else 0
                    nb = 8
            px.append(row)
        return w, h, dx, dy, px

    def char_width(self, c):
        """getCharWidth: ancho + desplazamiento x."""
        o = self.offset(c)
        if not o:
            return 0
        dx = self.font[o + 2]
        return self.font[o] + (dx - 256 if dx & 0x80 else dx)


def encode(height, bpp, glyphs, colors=None, nchars=256):
    """Bloque CHAR (sin cabecera) a partir de {codigo: (dx, dy, filas de pixeles)}."""
    colors = list(colors or range(1, 16))[:15]
    colors += [0] * (15 - len(colors))
    table = bytearray(4 * nchars)
    body = bytearray()
    base = 4 + 4 * nchars
    for c in sorted(glyphs):
        dx, dy, rows = glyphs[c]
        h = len(rows)
        w = len(rows[0]) if rows else 0
        table[4 * c:4 * c + 4] = (base + len(body)).to_bytes(4, "little")
        body += bytes((w, h, dx & 0xFF, dy & 0xFF))
        acc, nb = 0, 0
        for row in rows:
            for p in row:
                acc = (acc << bpp) | (p & ((1 << bpp) - 1))
                nb += bpp
                if nb == 8:
                    body.append(acc)
                    acc, nb = 0, 0
        if nb:
            body.append((acc << (8 - nb)) & 0xFF)
    font = bytes((bpp, height)) + nchars.to_bytes(2, "little") + bytes(table) + bytes(body)
    head = (FONT + len(font)).to_bytes(4, "little") + b"\x00\x00" + bytes(colors)
    return head + font
