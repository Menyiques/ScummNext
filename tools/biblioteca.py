"""La carpeta para la SD del Next (la que se copia entera a la tarjeta): el motor,
scumm.nex, y una carpeta por juego convertido, cada una con su GAME.DAT, su TITULO.TXT
(el nombre en el menu de juegos del Next) y sus partidas (SAVEn.DAT). Lo que usa la
ventana del conversor (tools/gui.py), sin ventana:

    juegos(raiz)                        los juegos que hay, con su estado
    detectar(origen)                    que juego hay en una carpeta original
    comprobar(origen, ...)              si cabe en el Next, sin escribir nada
    convertir(origen, raiz, carpeta, titulo, ...)
    a_su_carpeta(raiz, carpeta)         el juego suelto junto al .nex, a una carpeta
    quitar(raiz, carpeta)               a la papelera
    motor(raiz) / copiar_motor(raiz)    el scumm.nex de la carpeta y el que va con el conversor

Al reconvertir, las partidas guardadas (SAVEn.DAT) y el PROGRESO.DAT de la carpeta se
quedan; los demas ficheros del juego se cambian por los nuevos (los de antes que ya no
salen, como una habitacion que ahora no esta, se borran). Primero se escribe todo en
una carpeta aparte y solo al final se cambia: si algo falla, el juego de antes sigue
como estaba.
"""
import glob
import hashlib
import json
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import convert as C  # noqa: E402
import sound as SN  # noqa: E402

GMAX = 9                        # juegos que ve el menu del Next (GMAX, src/games.asm)
TITMAX = 31                     # letras del nombre en el menu (GTMAX)
INFO = "CONVERSION.JSON"        # lo que se sabe de la conversion (el Next no lo lee)
NEX = "scumm.nex"
# los ficheros que escribe el conversor (los demas de la carpeta no se tocan)
GENERADOS = re.compile(r"^(GAME|SCRIPTS|OBJ|INVOBJ|VERBIMG|CHARS|SOUNDS)\.DAT$|^[RCT]\d+\.DAT$|"
                       r"^TITULO\.TXT$|^CONVERSION\.JSON$", re.I)
PARTIDA = re.compile(r"^SAVE\d+\.DAT$", re.I)


class Parado(Exception):
    """La conversion se ha cancelado."""


def motor_incluido():
    """El scumm.nex que va con el conversor (dentro del .exe, o el de build/)."""
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return os.path.join(base, NEX)
    return os.path.join(C.ROOT, "build", NEX)


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def motor(raiz):
    """('al dia' | 'distinto' | 'falta' | 'sin motor', md5 de la carpeta, md5 del incluido)."""
    inc = motor_incluido()
    m_inc = md5(inc) if os.path.exists(inc) else None
    p = os.path.join(raiz, NEX)
    m = md5(p) if os.path.exists(p) else None
    if m_inc is None:
        return "sin motor", m, None
    if m is None:
        return "falta", None, m_inc
    return ("al dia" if m == m_inc else "distinto"), m, m_inc


def copiar_motor(raiz):
    os.makedirs(raiz, exist_ok=True)
    shutil.copyfile(motor_incluido(), os.path.join(raiz, NEX))


def leer_titulo(carpeta):
    p = os.path.join(carpeta, "TITULO.TXT")
    if not os.path.exists(p):
        return None
    with open(p, "rb") as f:
        t = f.read().split(b"\n")[0].strip().decode("latin-1")
    return t or None


def escribir_titulo(carpeta, titulo):
    """Como el conversor: una linea en Latin-1, como mucho TITMAX letras."""
    with open(os.path.join(carpeta, "TITULO.TXT"), "wb") as f:
        f.write(titulo.strip()[:TITMAX].encode("latin-1", "replace") + b"\r\n")


def leer_info(carpeta):
    try:
        with open(os.path.join(carpeta, INFO), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


class Juego:
    """Un juego de la carpeta para la SD. carpeta = '' si esta suelto junto al .nex."""

    def __init__(self, raiz, carpeta):
        self.raiz, self.carpeta = raiz, carpeta
        self.ruta = os.path.join(raiz, carpeta) if carpeta else raiz
        self.info = leer_info(self.ruta)
        self.titulo = leer_titulo(self.ruta) or carpeta or "El juego de esta carpeta"
        self.carpeta_ok = not carpeta or carpeta_valida(carpeta) is None     # (la ve el Next)
        nombres = os.listdir(self.ruta)
        self.partidas = sorted((n for n in nombres if PARTIDA.match(n)),
                               key=lambda n: int(re.sub(r"\D", "", n)))
        self.progreso = any(n.upper() == "PROGRESO.DAT" for n in nombres)
        self.pistas = sum(1 for n in nombres if re.match(r"^T\d+\.DAT$", n, re.I))
        self.habitaciones = sum(1 for n in nombres if re.match(r"^R\d+\.DAT$", n, re.I))
        self.bytes = sum(os.path.getsize(os.path.join(self.ruta, n)) for n in nombres
                         if os.path.isfile(os.path.join(self.ruta, n)))

    @property
    def estado(self):
        """'listo', 'no cabe', 'sin informe' (convertido sin la ventana) o 'carpeta larga'
        (el Next no la ve)."""
        if not self.carpeta_ok:
            return "carpeta larga"
        if "cabe" not in self.info:
            return "sin informe"
        return "listo" if self.info["cabe"] else "no cabe"

    @property
    def problemas(self):
        return self.info.get("problemas", [])


def juegos(raiz):
    """Los juegos de la carpeta: el suelto (si hay GAME.DAT junto al .nex) y los de
    sus carpetas, por el nombre que se ve (como el menu del Next)."""
    out = []
    if not os.path.isdir(raiz):
        return out
    if os.path.exists(os.path.join(raiz, "GAME.DAT")):
        out.append(Juego(raiz, ""))
    for n in sorted(os.listdir(raiz)):
        p = os.path.join(raiz, n)
        if n.startswith(".") or not os.path.isdir(p):
            continue
        if os.path.exists(os.path.join(p, "GAME.DAT")):
            out.append(Juego(raiz, n))
    out.sort(key=lambda j: j.titulo.upper())
    return out


def nombre_carpeta(texto):
    """Una carpeta que vea el Next para un nombre (MONKEY2) o un titulo: sus letras y
    cifras en mayusculas, como mucho 8 (The Secret of Monkey Island -> SECRETOF)."""
    pal = re.findall(r"[A-Za-z0-9]+", texto)
    if len(pal) > 1 and pal[0].lower() in ("the", "el", "la", "los", "las"):
        pal = pal[1:]
    return "".join(pal).upper()[:8] or "JUEGO"


def carpeta_valida(nombre):
    """None si vale; si no, por que. El menu del Next lee las carpetas sin nombres
    largos (F_OPENDIR sin LFN): de 1 a 8 letras o cifras, como un nombre corto de FAT
    (ZEsarUX no ensena las demas; el nombre que se ve es el de TITULO.TXT)."""
    if not nombre:
        return "Pon un nombre de carpeta."
    if not re.match(r"^[A-Za-z0-9_-]{1,8}$", nombre):
        return "La carpeta: de 1 a 8 letras o cifras, sin espacios ni puntos (el Next no ve otras)."
    if nombre.upper() in ("CON", "PRN", "AUX", "NUL", "COM1", "LPT1"):
        return "Ese nombre lo tiene reservado Windows."
    return None


def detectar(origen):
    """Los juegos (los *.000) de una carpeta original: [dict(nombre, habitaciones,
    salas, costumes, v5, pistas_usa, pistas_hay, error)]."""
    out = []
    for p in sorted(glob.glob(os.path.join(origen, "*.000"))):
        nombre = os.path.splitext(os.path.basename(p))[0]
        d = dict(nombre=nombre, habitaciones=0, salas=[], costumes=[], v5=False, pistas_usa=0,
                 pistas_hay=0, error=None)
        if not os.path.exists(os.path.join(origen, nombre + ".001")):
            d["error"] = "falta %s.001" % nombre
            out.append(d)
            continue
        try:
            g, _ = C.find_game(origen, nombre)
            d["salas"] = g.rooms()
            d["habitaciones"] = len(d["salas"])
            d["costumes"] = [i for i in range(len(g.index.dirs.get("DCOS", []))) if g.resource("DCOS", i)]
            d["v5"] = len(g.index.maxs) == 9        # (los v6 traen mas)
            res = SN.sound_resources(g)
            pistas = sorted({r["track"] for r in res.values() if r["kind"] == SN.CD})
            d["pistas_usa"] = len(pistas)
            d["pistas_hay"] = sum(1 for t in pistas if SN.track_file(origen, t))
        except Exception as e:                      # noqa: BLE001
            d["error"] = "no se puede leer como SCUMM v5 (%s)" % e
        out.append(d)
    return out


def _card(origen, nombre, costume, habitacion, avance):
    g, nombre = C.find_game(origen, nombre)

    def prog(k, n):
        avance("habitación %d de %d" % (k + 1, n), 0.7 * k / max(n, 1))
    card = C.Card(g, origen, costume, habitacion, progress=prog)
    return g, nombre, card


def comprobar(origen, nombre=None, costume=None, habitacion=None, avance=None):
    """El Card (files, bad, notes, rooms, costs) sin escribir nada."""
    return _card(origen, nombre, costume, habitacion, avance or (lambda *a: None))[2]


def convertir(origen, raiz, carpeta, titulo, nombre=None, costume=None, habitacion=None,
              musica=True, progreso=None, avance=None, log=None):
    """Convierte el juego de origen a raiz/carpeta. avance(texto, fraccion) puede lanzar
    Parado para cancelar. progreso: un PROGRESO.DAT para el % del menu (si no, se queda
    el que hubiera). Devuelve el dict que se guarda en CONVERSION.JSON."""
    avance = avance or (lambda *a: None)
    log = log or (lambda s: None)
    carpeta = carpeta.upper()               # (como los nombres cortos de la SD)
    why = carpeta_valida(carpeta)
    if why:
        raise ValueError(why)
    g, nombre, card = _card(origen, nombre, costume, habitacion, avance)
    destino = os.path.join(raiz, carpeta)
    tmp = os.path.join(raiz, ".convirtiendo_" + carpeta)
    if os.path.isdir(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    try:
        for fn, data in card.files.items():
            with open(os.path.join(tmp, fn), "wb") as f:
                f.write(data)
        pistas = []
        if musica:
            todas = sorted({r["track"] for r in card.sres.values() if r["kind"] == SN.CD})
            for k, t in enumerate(todas):
                avance("música: pista %d de %d" % (k + 1, len(todas)), 0.7 + 0.28 * k / max(len(todas), 1))
                p = SN.track_file(origen, t)
                if p is None:
                    continue
                with open(os.path.join(tmp, "T%02d.DAT" % t), "wb") as f:
                    f.write(SN.music_bytes(p))
                pistas.append(t)
            if todas:
                log("música: %d de %d pistas del CD" % (len(pistas), len(todas)))
        escribir_titulo(tmp, titulo)
        if progreso:
            shutil.copyfile(progreso, os.path.join(tmp, "PROGRESO.DAT"))
        info = dict(origen=os.path.abspath(origen), nombre=nombre, titulo=titulo.strip()[:TITMAX],
                    fecha=time.strftime("%Y-%m-%d %H:%M"), cabe=not card.bad,
                    problemas=list(card.bad), avisos=list(card.notes), habitaciones=len(card.rooms),
                    costumes=len(card.costs), musica=musica, pistas=pistas,
                    costume=costume, habitacion=habitacion)
        with open(os.path.join(tmp, INFO), "w", encoding="utf-8") as f:
            json.dump(info, f, ensure_ascii=False, indent=1)
        avance("cambiando los ficheros", 0.99)
        os.makedirs(destino, exist_ok=True)
        nuevos = set(n.upper() for n in os.listdir(tmp))
        for n in os.listdir(destino):           # los del juego de antes que ya no salen
            if GENERADOS.match(n) and n.upper() not in nuevos:
                os.remove(os.path.join(destino, n))
        for n in os.listdir(tmp):
            os.replace(os.path.join(tmp, n), os.path.join(destino, n))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    log("%s: %d habitaciones y %d costumes en %s" % (nombre, len(card.rooms), len(card.costs), destino))
    card.report(log)
    return info


def a_la_papelera(path):
    """Manda un fichero o carpeta a la papelera de Windows (True si se ha podido)."""
    if os.name != "nt":
        return False
    import ctypes
    from ctypes import wintypes

    class SHFILEOPSTRUCTW(ctypes.Structure):
        _fields_ = [("hwnd", wintypes.HWND), ("wFunc", wintypes.UINT),
                    ("pFrom", wintypes.LPCWSTR), ("pTo", wintypes.LPCWSTR),
                    ("fFlags", ctypes.c_ushort), ("fAnyOperationsAborted", wintypes.BOOL),
                    ("hNameMappings", ctypes.c_void_p), ("lpszProgressTitle", wintypes.LPCWSTR)]
    FO_DELETE, FOF_ALLOWUNDO, FOF_NOCONFIRMATION, FOF_SILENT = 3, 0x40, 0x10, 0x4
    op = SHFILEOPSTRUCTW(None, FO_DELETE, os.path.abspath(path) + "\0", None,
                         FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT, False, None, None)
    return ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op)) == 0 and not op.fAnyOperationsAborted


def a_su_carpeta(raiz, carpeta):
    """El juego suelto junto al .nex (como estaban las tarjetas antes) a raiz/carpeta,
    con sus partidas y su PROGRESO.DAT."""
    carpeta = carpeta.upper()               # (como los nombres cortos de la SD)
    why = carpeta_valida(carpeta)
    if why:
        raise ValueError(why)
    destino = os.path.join(raiz, carpeta)
    if os.path.exists(os.path.join(destino, "GAME.DAT")):
        raise ValueError("en %s ya hay un juego" % carpeta)
    os.makedirs(destino, exist_ok=True)
    for n in os.listdir(raiz):
        if GENERADOS.match(n) or PARTIDA.match(n) or n.upper() == "PROGRESO.DAT":
            os.replace(os.path.join(raiz, n), os.path.join(destino, n))


def quitar(raiz, carpeta):
    """La carpeta del juego, con sus partidas, a la papelera."""
    if not carpeta:
        raise ValueError("el juego suelto junto al .nex no se quita desde aqui")
    p = os.path.join(raiz, carpeta)
    if not a_la_papelera(p):
        raise OSError("no se ha podido mandar %s a la papelera" % p)
