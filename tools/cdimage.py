"""El juego original dentro de una imagen de CD, sin tener que sacarlo antes.

    carpeta(origen)         una carpeta con NOMBRE.000 y NOMBRE.001: origen si ya es
                            una carpeta; si es una imagen, una temporal con los dos
                            ficheros sacados de ella (se borra al acabar)
    pista(origen, n)        la pista n del juego en la imagen (PistaCD), o None
    directorio(origen)      donde buscar las pistas sueltas (TrackN.flac...): la
                            carpeta de la imagen

Imagenes que entiende:
    .cue + .bin/.img/.wav   (BINARY, MOTOROLA o WAVE; MODE1/2048, MODE1/2352,
                            MODE2/2336, MODE2/2352 y AUDIO; INDEX 00 y 01, PREGAP)
    .ccd + .img             CloneCD (los sectores enteros, de 2352 bytes)
    .iso                    solo datos (2048 bytes por sector), sin musica
    .img/.bin/.iso sueltos  con su .cue o .ccd al lado, si estan; si no, solo los datos
No entiende .mds/.mdf, .nrg ni .chd: hay que pasarlos antes a .cue/.bin.

Las pistas van como en ScummVM con el CD de verdad: la pista n del juego es la n+1
del disco (la 1 es la de datos). Cada pista va de su INDEX 01 al principio de la
siguiente (su INDEX 00 si lo tiene; o el final del fichero), sin el silencio que
las separa.
"""
import atexit
import os
import re
import shutil
import struct
import tempfile

EXTS = (".cue", ".ccd", ".iso", ".img", ".bin")
RAW = 2352
COOKED = 2048
RATE = 44100


class ErrorImagen(Exception):
    pass


# ---------------------------------------------------------------------------
# Las pistas
# ---------------------------------------------------------------------------
class Pista:
    """Un trozo de un fichero: desde el byte inicio, sectores de tamano bytes."""

    def __init__(self, numero, modo, fichero, inicio, sectores, tamano, formato="BINARY"):
        self.numero = numero        # el del disco (1 = la primera)
        self.modo = modo            # "AUDIO" o el de los datos
        self.fichero = fichero
        self.inicio = inicio
        self.sectores = sectores
        self.tamano = tamano
        self.formato = formato      # BINARY, MOTOROLA (audio al reves) o WAVE

    @property
    def audio(self):
        return self.modo == "AUDIO"


class PistaCD:
    """Una pista de musica de la imagen: lo que track_file da en lugar de un fichero."""

    def __init__(self, pista, imagen):
        self.pista = pista
        self.imagen = imagen

    def __str__(self):
        return "%s (pista %d)" % (os.path.basename(self.imagen), self.pista.numero)

    def seconds(self):
        return self.pista.sectores * (RAW // 4) / RATE

    def read(self):
        """(muestras en coma flotante -1..1, mono; frecuencia), como un WAV de 16 bits."""
        import numpy as np
        p = self.pista
        with open(p.fichero, "rb") as f:
            f.seek(p.inicio)
            raw = f.read(p.sectores * RAW)
        x = np.frombuffer(raw[:len(raw) // 4 * 4], "<i2" if p.formato != "MOTOROLA" else ">i2")
        x = x.astype(np.float32) / 32768
        return x.reshape(-1, 2).mean(axis=1), RATE


def _sector_datos(f, inicio, tamano, lba):
    """Los 2048 bytes del sector lba de una pista de datos."""
    if tamano == COOKED:
        f.seek(inicio + lba * COOKED)
        return f.read(COOKED)
    f.seek(inicio + lba * tamano)
    s = f.read(tamano)
    if tamano == 2336:                      # MODE2 sin cabecera: la subcabecera y los datos
        return s[8:8 + COOKED]
    if s[15:16] == b"\x02":                 # MODE2 (XA, forma 1): 8 bytes de subcabecera
        return s[24:24 + COOKED]
    return s[16:16 + COOKED]                # MODE1


# ---------------------------------------------------------------------------
# ISO 9660
# ---------------------------------------------------------------------------
def _iso_ficheros(f, inicio, tamano):
    """{ruta en mayusculas: (lba, bytes)} de los ficheros de la pista de datos."""
    pvd = _sector_datos(f, inicio, tamano, 16)
    if pvd[:6] != b"\x01CD001":
        raise ErrorImagen("la pista de datos no es ISO 9660")
    bloque = struct.unpack("<H", pvd[128:130])[0] or COOKED
    if bloque != COOKED:
        raise ErrorImagen("bloques ISO de %d bytes" % bloque)
    out = {}
    vistos = set()

    def directorio(lba, nbytes, ruta, nivel):
        if lba in vistos or nivel > 8:
            return
        vistos.add(lba)
        for k in range((nbytes + COOKED - 1) // COOKED):
            s = _sector_datos(f, inicio, tamano, lba + k)
            o = 0
            while o < len(s) and s[o]:
                n = s[o]
                ext = struct.unpack("<I", s[o + 2:o + 6])[0]
                size = struct.unpack("<I", s[o + 10:o + 14])[0]
                flags = s[o + 25]
                nid = s[o + 32]
                ident = s[o + 33:o + 33 + nid]
                o += n
                if ident in (b"\x00", b"\x01"):
                    continue
                nombre = ident.decode("latin-1").split(";")[0].rstrip(".").upper()
                if flags & 2:
                    directorio(ext, size, ruta + nombre + "/", nivel + 1)
                else:
                    out[ruta + nombre] = (ext, size)

    raiz = pvd[156:190]
    directorio(struct.unpack("<I", raiz[2:6])[0], struct.unpack("<I", raiz[10:14])[0], "", 0)
    return out


def _tiene_iso(ruta, inicio, tamano):
    try:
        with open(ruta, "rb") as f:
            return _sector_datos(f, inicio, tamano, 16)[:6] == b"\x01CD001"
    except OSError:
        return False


# ---------------------------------------------------------------------------
# Las hojas: .cue y .ccd
# ---------------------------------------------------------------------------
def _texto(ruta):
    b = open(ruta, "rb").read()
    try:
        return b.decode("utf-8-sig")
    except UnicodeDecodeError:
        return b.decode("latin-1")


def _buscar_fichero(dirb, nombre, hojas_con_un_fichero):
    """El fichero que nombra la hoja: tal cual, sin mayusculas, o el unico que hay."""
    nombre = nombre.replace("\\", "/")
    for cand in (os.path.join(dirb, nombre), os.path.join(dirb, os.path.basename(nombre))):
        if os.path.isfile(cand):
            return cand
    base = os.path.basename(nombre).lower()
    for n in os.listdir(dirb):
        if n.lower() == base:
            return os.path.join(dirb, n)
    if hojas_con_un_fichero:
        datos = [n for n in os.listdir(dirb) if os.path.splitext(n)[1].lower() in (".bin", ".img")]
        if len(datos) == 1:
            return os.path.join(dirb, datos[0])
    raise ErrorImagen("no está %s, que nombra la hoja" % os.path.basename(nombre))


def _wav_datos(ruta):
    """(byte donde empiezan las muestras, bytes) de un WAV de 44100 Hz, 16 bits, estereo."""
    with open(ruta, "rb") as f:
        d = f.read(65536)
    if d[:4] != b"RIFF" or d[8:12] != b"WAVE":
        raise ErrorImagen("%s no es un WAV" % os.path.basename(ruta))
    o, fmt = 12, None
    while o + 8 <= len(d):
        tag, size = d[o:o + 4], struct.unpack("<I", d[o + 4:o + 8])[0]
        if tag == b"fmt ":
            fmt = struct.unpack("<HHIIHH", d[o + 8:o + 24])
        elif tag == b"data":
            if not fmt or fmt[0] != 1 or fmt[1] != 2 or fmt[2] != RATE or fmt[5] != 16:
                raise ErrorImagen("%s no es audio de CD (44100 Hz, 16 bits, estéreo)"
                                  % os.path.basename(ruta))
            return o + 8, min(size, os.path.getsize(ruta) - o - 8)
        o += 8 + size + (size & 1)
    raise ErrorImagen("%s: no se encuentran las muestras" % os.path.basename(ruta))


_TAMANOS = {"AUDIO": RAW, "MODE1/2048": COOKED, "MODE1/2352": RAW, "MODE2/2336": 2336,
            "MODE2/2352": RAW, "CDG": 2448, "MODE2/2048": COOKED, "MODE2/2324": 2324}


def _msf(s):
    m, sec, fr = (int(x) for x in s.split(":"))
    return (m * 60 + sec) * 75 + fr


def leer_cue(ruta):
    dirb = os.path.dirname(os.path.abspath(ruta))
    lineas = [ln.strip() for ln in _texto(ruta).splitlines()]
    nfich = sum(1 for ln in lineas if ln.upper().startswith("FILE "))
    fichs = []                              # [(ruta, formato, [pistas: dict])]
    for ln in lineas:
        u = ln.upper()
        if u.startswith("FILE "):
            m = re.match(r'FILE\s+(?:"([^"]*)"|(\S+))\s*(\S*)', ln, re.I)
            if not m:
                raise ErrorImagen("línea FILE rara: %s" % ln)
            nombre = m.group(1) if m.group(1) is not None else m.group(2)
            fichs.append((_buscar_fichero(dirb, nombre, nfich == 1), (m.group(3) or "BINARY").upper(), []))
        elif u.startswith("TRACK "):
            if not fichs:
                raise ErrorImagen("TRACK antes de FILE")
            p = u.split()
            if p[2] not in _TAMANOS:
                raise ErrorImagen("pistas de tipo %s" % p[2])
            fichs[-1][2].append(dict(numero=int(p[1]), modo=p[2], indices={}))
        elif u.startswith("INDEX ") and fichs and fichs[-1][2]:
            p = u.split()
            fichs[-1][2][-1]["indices"][int(p[1])] = _msf(p[2])
    pistas = []
    for fichero, formato, ps in fichs:
        if formato == "WAVE":
            base, nbytes = _wav_datos(fichero)
        else:
            base, nbytes = 0, os.path.getsize(fichero)
        if formato not in ("BINARY", "MOTOROLA", "WAVE"):
            raise ErrorImagen("ficheros de tipo %s" % formato)
        # el byte de cada sector del fichero, con el tamano de sector de cada pista
        primeros = [min(t["indices"].values()) if t["indices"] else 0 for t in ps]
        bytes_ini = []
        for k, t in enumerate(ps):
            if k == 0:
                bytes_ini.append(base + primeros[0] * _TAMANOS[t["modo"]])
            else:
                bytes_ini.append(bytes_ini[-1] + (primeros[k] - primeros[k - 1]) * _TAMANOS[ps[k - 1]["modo"]])
        for k, t in enumerate(ps):
            tam = _TAMANOS[t["modo"]]
            i1 = t["indices"].get(1, primeros[k])
            ini = bytes_ini[k] + (i1 - primeros[k]) * tam
            fin = bytes_ini[k + 1] if k + 1 < len(ps) else base + nbytes
            pistas.append(Pista(t["numero"], t["modo"], fichero, ini, max(0, (fin - ini) // tam), tam, formato))
    return sorted(pistas, key=lambda p: p.numero)


def leer_ccd(ruta):
    """CloneCD: las pistas de [TRACK n] y el final (lead-out) de [Entry] con Point=0xa2."""
    secs, actual = {}, None
    for ln in _texto(ruta).splitlines():
        ln = ln.strip()
        m = re.match(r"\[(.+)\]$", ln)
        if m:
            actual = m.group(1).strip().upper()
            secs.setdefault(actual, {})
        elif "=" in ln and actual:
            k, v = ln.split("=", 1)
            secs[actual][k.strip().upper()] = v.strip()
    img = None
    for ext in (".img", ".IMG", ".Img"):
        cand = os.path.splitext(ruta)[0] + ext
        if os.path.isfile(cand):
            img = cand
            break
    if img is None:
        raise ErrorImagen("no está el .img de %s" % os.path.basename(ruta))
    total = os.path.getsize(img) // RAW
    leadout = total
    for nombre, d in secs.items():
        if nombre.startswith("ENTRY") and d.get("POINT", "").lower() in ("0xa2", "162") and "PLBA" in d:
            leadout = min(total, int(d["PLBA"], 0))
    ts = []
    for nombre, d in secs.items():
        m = re.match(r"TRACK\s+(\d+)$", nombre)
        if m and "INDEX 1" in d:
            ts.append((int(m.group(1)), int(d.get("MODE", "0"), 0), int(d["INDEX 1"], 0),
                       int(d.get("INDEX 0", d["INDEX 1"]), 0)))
    ts.sort()
    pistas = []
    for k, (n, modo, i1, _) in enumerate(ts):
        fin = ts[k + 1][3] if k + 1 < len(ts) else leadout
        pistas.append(Pista(n, "AUDIO" if modo == 0 else "MODE%d/2352" % modo, img, i1 * RAW,
                            max(0, fin - i1), RAW))
    if not pistas:
        raise ErrorImagen("%s no tiene pistas" % os.path.basename(ruta))
    return pistas


def leer_suelta(ruta):
    """Un .iso, .img o .bin sin hoja: una sola pista de datos."""
    for tam in (COOKED, RAW):
        if _tiene_iso(ruta, 0, tam):
            n = os.path.getsize(ruta) // tam
            return [Pista(1, "MODE1/2048" if tam == COOKED else "MODE1/2352", ruta, 0, n, tam)]
    raise ErrorImagen("%s no parece una imagen de CD de datos" % os.path.basename(ruta))


def pistas_de(ruta):
    """Las pistas de una imagen (para un .img/.bin, con su .cue o .ccd si esta al lado)."""
    base, ext = os.path.splitext(ruta)
    ext = ext.lower()
    if ext == ".cue":
        return leer_cue(ruta)
    if ext == ".ccd":
        return leer_ccd(ruta)
    if ext in (".img", ".bin", ".iso"):
        dirb = os.path.dirname(os.path.abspath(ruta))
        stem = os.path.basename(base).lower()
        hojas = [n for n in sorted(os.listdir(dirb)) if os.path.splitext(n)[1].lower() in (".cue", ".ccd")]
        for n in hojas:
            if os.path.splitext(n)[0].lower() == stem:
                return pistas_de(os.path.join(dirb, n))
        for n in hojas:                     # un .cue con otro nombre que nombra este fichero
            if n.lower().endswith(".cue"):
                for ln in _texto(os.path.join(dirb, n)).splitlines():
                    m = re.match(r'\s*FILE\s+(?:"([^"]*)"|(\S+))', ln, re.I)
                    if m and os.path.basename((m.group(1) or m.group(2)).replace("\\", "/")).lower() \
                            == os.path.basename(ruta).lower():
                        return leer_cue(os.path.join(dirb, n))
    return leer_suelta(ruta)


# ---------------------------------------------------------------------------
# Lo que usa el conversor
# ---------------------------------------------------------------------------
class Imagen:
    def __init__(self, ruta):
        self.ruta = os.path.abspath(ruta)
        self.pistas = pistas_de(self.ruta)
        datos = [p for p in self.pistas if not p.audio]
        if not datos:
            raise ErrorImagen("la imagen no tiene pista de datos")
        self.datos = datos[0]
        self.carpeta = None

    def extraer(self):
        """Saca los NOMBRE.000 y NOMBRE.001 a una carpeta temporal."""
        if self.carpeta:
            return self.carpeta
        d = self.datos
        if d.tamano not in (COOKED, RAW, 2336):
            raise ErrorImagen("pista de datos de %d bytes por sector" % d.tamano)
        with open(d.fichero, "rb") as f:
            fs = _iso_ficheros(f, d.inicio, d.tamano)
            juegos = sorted((r.count("/"), r) for r in fs if r.endswith(".000"))
            if not juegos:
                raise ErrorImagen("en la imagen no hay ningún NOMBRE.000")
            dirj = juegos[0][1].rsplit("/", 1)[0] + "/" if "/" in juegos[0][1] else ""
            sacar = [r for r in fs if r.startswith(dirj) and "/" not in r[len(dirj):]
                     and r.endswith((".000", ".001"))]
            tmp = tempfile.mkdtemp(prefix="scummnext_cd_")
            _TEMPORALES.append(tmp)
            for r in sacar:
                lba, size = fs[r]
                with open(os.path.join(tmp, r[len(dirj):]), "wb") as o:
                    k = 0
                    while size > 0:
                        s = _sector_datos(f, d.inicio, d.tamano, lba + k)
                        o.write(s[:min(size, COOKED)])
                        size -= COOKED
                        k += 1
        self.carpeta = tmp
        _POR_RUTA[_clave(tmp)] = self
        return tmp

    def pista(self, n):
        """La pista n del juego: la n+1 del disco (si es de audio)."""
        p = next((p for p in self.pistas if p.numero == n + 1), None)
        return PistaCD(p, self.ruta) if p and p.audio and p.sectores else None

    def audio(self):
        return sum(1 for p in self.pistas if p.audio)


_POR_RUTA = {}
_TEMPORALES = []


def _clave(ruta):
    return os.path.normcase(os.path.abspath(ruta))


@atexit.register
def _limpiar():
    for t in _TEMPORALES:
        shutil.rmtree(t, ignore_errors=True)


def es_imagen(ruta):
    return bool(ruta) and os.path.isfile(ruta) and os.path.splitext(ruta)[1].lower() in EXTS


def imagen(origen):
    """La Imagen de origen (la ruta de la imagen o su carpeta temporal), o None."""
    if not origen:
        return None
    k = _clave(origen)
    if k in _POR_RUTA:
        return _POR_RUTA[k]
    if not es_imagen(origen):
        return None
    im = Imagen(origen)
    _POR_RUTA[k] = im
    return im


def carpeta(origen):
    im = imagen(origen)
    return im.extraer() if im else origen


def pista(origen, n):
    im = imagen(origen)
    return im.pista(n) if im else None


def directorio(origen):
    im = imagen(origen)
    return os.path.dirname(im.ruta) if im else origen
