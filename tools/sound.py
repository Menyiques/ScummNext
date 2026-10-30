"""Sonido de SCUMM v5 (la version CD de Monkey Island), como ScummVM.

- Los recursos de sonido (DSOU): referencias a pistas del CD (32 bytes: pista,
  vueltas, principio y final en minutos:segundos:frames de 1/75 s), efectos
  digitalizados (SOU con SBL: datos VOC de 8 bits sin signo) y los de AdLib (ADL:
  musica de iMuse para el chip OPL2; tools/adlib.py la toca como ScummVM y
  tools/opl2.py la sintetiza). Los de Roland no se usan (ScummVM tampoco, con AdLib).
- SOUNDS.DAT para el Next: un indice y las muestras de los efectos (los de AdLib,
  ya sintetizados, los que caben; los que dan vueltas, con su bucle).
- El estado que ven los scripts (Sound): la cola de sonidos de cada paso, la
  pista del CD que suena con su reloj (VAR_MUSIC_TIMER) y los efectos que
  siguen sonando. Lo que dura cada cosa se cuenta en jiffies (1/60 s), con el
  mismo reloj que el resto de la maquina virtual, para que el Z80 y el modelo
  den lo mismo; el sonido de verdad lo hace el Z80 aparte.
"""
import os
import struct

import scumm as S

NONE, CD, SBL, ADL, ROL = 0, 1, 2, 3, 4
INFINITE = 0xFFFF
QUEUE_MAX = 10          # Sound::_soundQueue de ScummVM
NSFX = 8                # efectos que pueden sonar a la vez (solo la cuenta)
DEFAULT_TRACK_S = 120   # si no esta el audio de una pista
FILE_MAGIC = b"SN5\x01"
ENTRY = 16
SAMPLES_AT = 8192       # las muestras empiezan en la segunda pagina del fichero
CTC_HZ = 28000000 // 16


def voc_rate(sr):
    """getSampleRateFromVOCRate."""
    if sr in (0xA5, 0xA6):
        return 11025
    if sr in (0xD2, 0xD3):
        return 22050
    return 1000000 // (256 - sr)


def ceil_div(a, b):
    return -(-a // b)


# ---------------------------------------------------------------------------
# Pistas del CD
# ---------------------------------------------------------------------------
def track_file(folder, track):
    for name in ("Track%d" % track, "track%d" % track, "Track%02d" % track, "track%02d" % track):
        for ext in (".fla", ".flac", ".wav"):
            p = os.path.join(folder, name + ext)
            if os.path.exists(p):
                return p
    return None


def track_seconds(path):
    """Duracion de una pista (FLAC: STREAMINFO; WAV: cabecera)."""
    with open(path, "rb") as f:
        d = f.read(4096)
    if d[:4] == b"fLaC":
        si = d[8:8 + 34]
        rate = si[10] << 12 | si[11] << 4 | si[12] >> 4
        ns = ((si[13] & 15) << 32) | struct.unpack(">I", si[14:18])[0]
        return ns / rate
    if d[:4] == b"RIFF" and d[8:12] == b"WAVE":
        o = 12
        fmt = None
        while o + 8 <= len(d):
            tag, size = d[o:o + 4], struct.unpack("<I", d[o + 4:o + 8])[0]
            if tag == b"fmt ":
                fmt = struct.unpack("<HHIIHH", d[o + 8:o + 24])
            elif tag == b"data" and fmt:
                ch, rate, bits = fmt[1], fmt[2], fmt[5]
                return size / (ch * (bits // 8) * rate)
            o += 8 + size + (size & 1)
    raise ValueError("%s: no es FLAC ni WAV" % path)


# ---------------------------------------------------------------------------
# Los recursos
# ---------------------------------------------------------------------------
def parse_sbl(payload):
    """(frecuencia, muestras) de un bloque SBL (AUhd + AUdt con un bloque VOC 1)."""
    o = 0
    while o + 8 <= len(payload):            # (aqui el tamano no cuenta la cabecera)
        tag, size = payload[o:o + 4], S.be32(payload, o + 4)
        if tag in (b"AUdt", b"WVdt"):
            v = payload[o + 8:o + 8 + size]
            if v[0] != 1:
                raise ValueError("SBL: bloque VOC %d" % v[0])
            n = v[1] | v[2] << 8 | v[3] << 16
            if v[5] != 0:
                raise ValueError("SBL comprimido")
            return voc_rate(v[4]), bytes(v[6:6 + n - 2])
        o += 8 + size
    raise ValueError("SBL sin datos")


def sound_resources(game):
    """{numero: dict(kind=..., ...)} de los sonidos del juego."""
    out = {}
    for i in range(len(game.index.dirs.get("DSOU", []))):
        r = game.resource("DSOU", i)
        if r is None:
            continue
        tag, a, b = r
        full = game.data[a - 8:b]
        if full[8:12] != b"SOU ":
            if len(full) < 30:
                continue
            out[i] = dict(kind=CD, track=full[24], loops=full[25],
                          start=(full[26] * 60 + full[27]) * 75 + full[28],
                          end=(full[29] * 60 + full[30]) * 75 + (full[31] if len(full) > 31 else 0))
            continue
        subs = {}                           # (dentro de SOU el tamano de cada bloque no
        o = a + 8                           # cuenta sus 8 bytes de cabecera, como lee
        while o + 8 <= b:                   # ScummVM: readSoundResource)
            t = bytes(game.data[o:o + 4])
            size = S.be32(game.data, o + 4)
            subs.setdefault(t, (o + 8, min(b, o + 8 + size)))
            o += 8 + size
        if b"SBL " in subs:                 # (lo digitalizado antes que AdLib, como ScummVM)
            p, q = subs[b"SBL "]
            rate, data = parse_sbl(game.data[p:q])
            out[i] = dict(kind=SBL, rate=rate, data=data)
        elif b"ADL " in subs:
            p, q = subs[b"ADL "]
            out[i] = dict(kind=ADL, adl=bytes(game.data[p:q]))
        elif b"ROL " in subs:
            out[i] = dict(kind=ROL)
    return out


def cd_jiffies(res, track_s):
    """Lo que suena una referencia a pista del CD, en jiffies (INFINITE si da vueltas)."""
    if res["loops"] == 0xFF:
        return INFINITE
    if res["end"] > res["start"]:
        frames = res["end"] - res["start"]
    else:
        frames = max(0, int(track_s * 75) - res["start"])
    return min(INFINITE - 1, max(1, ceil_div(frames * max(1, res["loops"]) * 60, 75)))


def sound_table(res, folder):
    """{numero: (tipo, jiffies)} para la logica (modelo y Z80)."""
    tab = {}
    for n, r in res.items():
        if r["kind"] == CD:
            p = track_file(folder, r["track"]) if folder else None
            secs = track_seconds(p) if p else DEFAULT_TRACK_S
            tab[n] = (CD, cd_jiffies(r, secs))
        elif r["kind"] == SBL:
            tab[n] = (SBL, min(INFINITE - 1, max(1, ceil_div(len(r["data"]) * 60, r["rate"]))))
        elif r["kind"] == ADL:
            tab[n] = (ADL, adl_duration(r["adl"]))
        else:
            tab[n] = (r["kind"], 0)
    return tab


_ADL_MEMO = {}


def adl_duration(adl):
    """Lo que suena un sonido de AdLib para los scripts (adlib.duracion, guardado)."""
    if adl not in _ADL_MEMO:
        import adlib
        _ADL_MEMO[adl] = adlib.duracion(adl)
    return _ADL_MEMO[adl]


def ctc_constant(rate):
    """Constante del CTC (preescala 16, a 28 MHz) para la frecuencia; 256 se escribe 0."""
    tc = max(1, min(256, round(CTC_HZ / rate)))
    return tc & 0xFF


ADL_TC = 255                # los de AdLib, a CTC_HZ / 255 (6863 por segundo)
MAX_SAMPLES = 56 * 8192 - SAMPLES_AT


def _adl_estimate(adl, rate):
    """Lo que ocupara como mucho, sin sintetizarlo (para no sintetizar lo que no cabe)."""
    import adlib
    try:
        t = adlib.escrituras(adl)
    except (ValueError, IndexError, struct.error):
        return 0
    if t.fin is not None:
        calls = t.fin + 500
    elif t.musical:
        calls = t.salto[1]
    else:
        calls = 250
    return int(calls * 0.004 * rate) + 1


def sounds_file(res, table, max_samples=MAX_SAMPLES, info=None):
    """SOUNDS.DAT: firma, numero de entradas, entradas de 16 bytes desde el byte 16
    y las muestras de los efectos desde SAMPLES_AT.

    Entrada: tipo, jiffies (2) y despues
      pista del CD: pista, vueltas, principio (3, frames), frames (3, 0 = hasta el final)
      efecto: constante del CTC, posicion en las muestras (3), largo (2)
      AdLib: como un efecto (largo 0: no cabe o no suena) y donde vuelve a empezar al
        acabar (2; $FFFF: no da vueltas)
    Los de AdLib se sintetizan aqui y entran, de menor a mayor, los que caben en
    max_samples (detras de los efectos); info["fuera"]: los que no.
    """
    n = max(res) + 1 if res else 0
    idx = bytearray(16 + ENTRY * n)
    idx[:4] = FILE_MAGIC
    idx[4:6] = struct.pack("<H", n)
    samples = bytearray()
    donde = {}                              # (los efectos repetidos, una vez)
    for k in sorted(res):                   # primero los efectos digitalizados
        if res[k]["kind"] == SBL:
            data = bytes(res[k]["data"][:0xFFFF])
            if data not in donde:
                donde[data] = len(samples)
                samples += data
    adl_audio = {}                          # despues los de AdLib que quepan
    rate = CTC_HZ / ADL_TC
    fuera = []
    cand = sorted((_adl_estimate(r["adl"], rate), k) for k, r in res.items() if r["kind"] == ADL)
    hechos = {}
    for est, k in cand:
        adl = res[k]["adl"]
        if adl in hechos:
            adl_audio[k] = hechos[adl]
            continue
        if not est:
            continue
        if len(samples) + est > max_samples:
            fuera.append(k)
            continue
        import adlib
        data, loop = adlib.audio(adl, rate)
        if not data or len(samples) + len(data) > max_samples:
            if data:
                fuera.append(k)
            continue
        if data not in donde:
            donde[data] = len(samples)
            samples += data
        hechos[adl] = adl_audio[k] = (data, loop)
    if info is not None:
        info["fuera"] = sorted(fuera)
    for k in range(n):
        r = res.get(k)
        e = bytearray(ENTRY)
        if r is not None:
            kind, dur = table[k]
            e[0] = kind
            e[1:3] = struct.pack("<H", dur)
            if kind == CD:
                frames = r["end"] - r["start"] if r["end"] > r["start"] else 0
                e[3] = r["track"]
                e[4] = r["loops"]
                e[5:8] = struct.pack("<I", r["start"])[:3]
                e[8:11] = struct.pack("<I", frames)[:3]
            elif kind == SBL:
                data = bytes(r["data"][:0xFFFF])
                e[3] = ctc_constant(r["rate"])
                e[4:7] = struct.pack("<I", donde[data])[:3]
                e[7:9] = struct.pack("<H", len(data))
            elif kind == ADL:
                data, loop = adl_audio.get(k, (b"", None))
                e[3] = ADL_TC
                e[4:7] = struct.pack("<I", donde.get(data, 0) if data else 0)[:3]
                e[7:9] = struct.pack("<H", len(data))
                e[9:11] = struct.pack("<H", 0xFFFF if loop is None else loop)
        idx[16 + ENTRY * k:16 + ENTRY * (k + 1)] = e
    if len(idx) > SAMPLES_AT:
        raise ValueError("demasiados sonidos para el indice")
    return bytes(idx) + bytes(SAMPLES_AT - len(idx)) + bytes(samples)


# ---------------------------------------------------------------------------
# La musica: las pistas del CD en 8 bits sin signo, mono, a MUSIC_RATE
# ---------------------------------------------------------------------------
MUSIC_RATE = 11025      # 147 muestras por frame del CD (1/75 s)
MUSIC_DRIVE = 2.5       # el CD va flojo (picos de 0,44 a 0,66): x 2,5 y un limitador suave
                        # (tanh: solo se comprime algo el 1-3 % de las muestras)


def read_track(path):
    """(muestras en coma flotante -1..1, mono; frecuencia) de un FLAC o un WAV."""
    import numpy as np
    if path.lower().endswith(".wav"):
        import wave
        with wave.open(path, "rb") as f:
            ch, width, rate, n = f.getnchannels(), f.getsampwidth(), f.getframerate(), f.getnframes()
            raw = f.readframes(n)
        if width == 1:
            x = (np.frombuffer(raw, np.uint8).astype(np.float32) - 128) / 128
        else:
            x = np.frombuffer(raw, np.int16).astype(np.float32) / 32768
        return x.reshape(-1, ch).mean(axis=1), rate
    pylib = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "pylib")
    if os.path.isdir(pylib) and pylib not in __import__("sys").path:
        __import__("sys").path.insert(0, pylib)
    import soundfile                    # pip install soundfile (para los FLAC)
    x, rate = soundfile.read(path, dtype="float32", always_2d=True)
    return x.mean(axis=1), rate


def music_bytes(path):
    """La pista para el Next: MUSIC_RATE Hz, 8 bits sin signo (128 = silencio)."""
    import numpy as np
    x, rate = read_track(path)
    if rate % MUSIC_RATE == 0:          # (44100 y 22050: la media de cada grupo)
        k = rate // MUSIC_RATE
        n = len(x) // k * k
        y = x[:n].reshape(-1, k).mean(axis=1)
    else:
        n = int(len(x) * MUSIC_RATE / rate)
        y = np.interp(np.arange(n) * rate / MUSIC_RATE, np.arange(len(x)), x)
    return np.clip(np.round(128 + 127 * np.tanh(MUSIC_DRIVE * y)), 0, 255).astype(np.uint8).tobytes()


def music_files(res, folder, out, log=print):
    """Tnn.DAT de cada pista del CD que usa el juego (si esta su audio en folder)."""
    tracks = sorted({r["track"] for r in res.values() if r["kind"] == CD})
    done = []
    for t in tracks:
        p = track_file(folder, t)
        if p is None:
            continue
        try:
            data = music_bytes(p)
        except ImportError:
            log("para convertir los FLAC hace falta soundfile (pip install soundfile)")
            break
        with open(os.path.join(out, "T%02d.DAT" % t), "wb") as f:
            f.write(data)
        done.append(t)
    return done


# ---------------------------------------------------------------------------
# Lo que ven los scripts
# ---------------------------------------------------------------------------
class Sound:
    """El estado de Sound de ScummVM que llega a los scripts. table: {n: (tipo, jiffies)}."""

    def __init__(self, table):
        self.table = table
        self.queue = []                 # startSound de este paso (ScummVM los dispara al final)
        self.cd_sound = 0               # _currentCDSound
        self.cd_on = False              # el reloj del CD corre
        self.cd_timer = 0               # _cdMusicTimer (jiffies desde que empezo la pista)
        self.cd_left = 0                # lo que le queda a la pista (INFINITE: da vueltas)
        self.sfx = [[0, 0] for _ in range(NSFX)]    # (sonido, jiffies que le quedan)

    def pack(self):
        """Los mismos bytes que en el Z80 (SNDST en la pagina UIP)."""
        out = bytes((len(self.queue),)) + bytes(self.queue + [0] * (QUEUE_MAX - len(self.queue)))
        out += struct.pack("<BBHH", self.cd_sound, int(self.cd_on), self.cd_timer, self.cd_left)
        for s, left in self.sfx:
            out += struct.pack("<BH", s, left)
        return out

    def tick(self, delta):
        """Al empezar cada paso: los relojes. Devuelve VAR_MUSIC_TIMER."""
        if self.cd_on:
            self.cd_timer = (self.cd_timer + delta) & 0xFFFF
        if self.cd_left not in (0, INFINITE):
            self.cd_left = max(0, self.cd_left - delta)
        for ch in self.sfx:
            if ch[1] and ch[1] != INFINITE:
                ch[1] = max(0, ch[1] - delta)
                if not ch[1]:
                    ch[0] = 0
        return self.cd_timer

    def start(self, n):
        """addSoundToQueue (la cola de ScummVM tiene 10; aqui, si esta llena, se pierde)."""
        if len(self.queue) < QUEUE_MAX:
            self.queue.append(n & 0xFF)

    def process(self):
        """processSoundQueues: los de la cola, del ultimo al primero. Devuelve los que
        empiezan a sonar ((tipo, n) en orden), para el Z80 y para poner VAR_MUSIC_TIMER."""
        started = []
        while self.queue:
            n = self.queue.pop()
            if n and self.trigger(n):
                started.append((self.table[n][0], n))
        return started

    def trigger(self, n):
        kind, dur = self.table.get(n, (NONE, 0))
        if kind == CD:
            if n == self.cd_sound and self.cd_left:
                return False
            self.cd_sound, self.cd_on, self.cd_timer, self.cd_left = n, True, 0, dur
            return True
        if kind == ADL:                     # iMuse: si ya suena, otra vez desde el principio
            if not dur:
                return False
            for ch in self.sfx:
                if ch[0] == n and ch[1]:
                    ch[1] = dur
                    return True
        if kind in (SBL, ADL):
            free = [i for i, ch in enumerate(self.sfx) if not ch[1]]
            k = free[0] if free else min(range(NSFX), key=lambda i: self.sfx[i][1])
            self.sfx[k] = [n, dur]
            return True
        return False

    def running(self, n):
        """isSoundRunning."""
        n &= 0xFF
        if not n:
            return 0
        if n == self.cd_sound:
            return int(self.cd_left != 0)
        if any(s == n and left for s, left in self.sfx):
            return 1
        return int(n in self.queue)

    def stop(self, n):
        """stopSound."""
        n &= 0xFF
        if n and n == self.cd_sound:
            self.cd_sound, self.cd_on, self.cd_left = 0, False, 0
        for ch in self.sfx:
            if ch[0] == n:
                ch[0] = ch[1] = 0
        self.queue = [0 if q == n else q for q in self.queue]

    def stop_all(self):
        """stopAllSounds (stopMusic)."""
        if self.cd_sound:
            self.cd_sound, self.cd_on, self.cd_left = 0, False, 0
        self.queue = []
        for ch in self.sfx:
            ch[0] = ch[1] = 0

    def after_load(self):
        """Al cargar una partida: la cola y los efectos digitalizados no se guardan
        (ScummVM tampoco); los de AdLib (iMuse) si, y siguen."""
        self.queue = []
        for ch in self.sfx:
            if self.table.get(ch[0], (NONE, 0))[0] != ADL:
                ch[0] = ch[1] = 0
