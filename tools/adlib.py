"""Los sonidos de AdLib de SCUMM v5 ('ADL ' dentro de 'SOU ': MDhd y un MIDI con los
sysex de iMuse) a escrituras en los registros del OPL2, tal como los toca ScummVM: el
reproductor de iMuse (engines/scumm/imuse: Player, Part, sysexHandler_Scumm), su
analizador MIDI (audio/midiparser.cpp, con el salto "listo" y las notas colgadas) y el
driver de AdLib en modo OPL2 (audio/adlib.cpp: MidiDriver_ADLIB, con sus envolventes
por programa). Todo va al ritmo del reloj del driver: una llamada cada 4 ms (250 Hz);
en cada una, primero iMuse y despues las envolventes, y luego el chip genera 4 ms.

    escrituras(adl) -> Toque: las escrituras de cada llamada, cuando acaba la pista
    (fin, en llamadas; None si da vueltas para siempre) y desde cuando se repite.
"""
import struct

TIMER_US = 4000                 # 1000000 / OPL::kDefaultCallbackFrequency
TICKS_PER_BEAT = 480            # (iMuse)
IMUSE_SYSEX_ID = 0x7D

# --- audio/adlib.cpp ------------------------------------------------------------------
OP1 = (0, 1, 2, 8, 9, 10, 16, 17, 18)
OP2 = (3, 4, 5, 11, 12, 13, 19, 20, 21)
SET_PARAM = (                   # (registro base, desplazamiento, mascara, inversion)
    (0x40, 0, 63, 63), (0xE0, 2, 0, 0), (0x40, 6, 192, 0), (0x20, 0, 15, 0),
    (0x60, 4, 240, 15), (0x60, 0, 15, 15), (0x80, 4, 240, 15), (0x80, 0, 15, 15),
    (0xE0, 0, 3, 0), (0x20, 7, 128, 0), (0x20, 6, 64, 0), (0x20, 5, 32, 0),
    (0x20, 4, 16, 0), (0xC0, 0, 1, 0), (0xC0, 1, 14, 0))
PARAM_TABLE1 = (29, 28, 27, 0, 3, 4, 7, 8, 13, 16, 17, 20, 21, 30, 31, 0)
MAX_VAL = (0x2FF, 0x1F, 0x7, 0x3F, 0x0F, 0x0F, 0x0F, 0x3, 0x3F, 0x0F, 0x0F, 0x0F, 0x3, 0x3E, 0x1F, 0)
NUM_STEPS = (1, 2, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 21, 24, 30,
             36, 50, 64, 82, 100, 136, 160, 192, 240, 276, 340, 460, 600, 860, 1200, 1600)
NOTE_FREQ = (
    90, 91, 92, 92, 93, 94, 94, 95, 96, 96, 97, 98, 98, 99, 100, 101,
    101, 102, 103, 104, 104, 105, 106, 107, 107, 108, 109, 110, 111, 111, 112, 113,
    114, 115, 115, 116, 117, 118, 119, 120, 121, 121, 122, 123, 124, 125, 126, 127,
    128, 129, 130, 131, 132, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142,
    143, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 157, 158, 159, 160,
    161, 162, 163, 165, 166, 167, 168, 169, 171, 172, 173, 174, 176, 177, 178, 180,
    181, 182, 184, 185, 186, 188, 189, 190, 192, 193, 194, 196, 197, 199, 200, 202,
    203, 205, 206, 208, 209, 211, 212, 214, 215, 217, 218, 220, 222, 223, 225, 226,
    228, 230, 231, 233, 235, 236, 238, 240, 242, 243, 245, 247, 249, 251, 252, 254)
VOLUME_TABLE = (
    0, 4, 7, 11, 13, 16, 18, 20, 22, 24, 26, 27, 29, 30, 31, 33,
    34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 44, 45, 46, 47, 47,
    48, 49, 49, 50, 51, 51, 52, 53, 53, 54, 54, 55, 55, 56, 56, 57,
    57, 58, 58, 59, 59, 60, 60, 60, 61, 61, 62, 62, 62, 63, 63, 63)
_VOL_FLAT = [0] * (64 * 32)           # g_volumeLookupTable[64][32] (plana: en C una fila
for _i in range(64):                    # puede pasarse a la siguiente)
    _s = _i
    for _j in range(32):
        _VOL_FLAT[_i * 32 + _j] = _s >> 5
        _s += _i
    _VOL_FLAT[_i * 32] = 0
FUERA = []                              # (lecturas fuera de la tabla: no deberia haber)


def vl(a, b):
    k = a * 32 + b
    if not 0 <= k < len(_VOL_FLAT):
        FUERA.append((a, b))
        return 0
    return _VOL_FLAT[k]
# el instrumento de GM 0 (AdLibPart::init -> programChange(0); un sysex lo cambia antes
# de la primera nota)
GM0 = bytes((0xC2, 0xC5, 0x2B, 0x99, 0x58, 0xC2, 0x1F, 0x1E, 0xC8, 0x7C, 0x0A, 0)) + bytes(17) + bytes((0x23,))


def s8(v):
    v &= 0xFF
    return v - 256 if v & 0x80 else v


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def c_div(a, b):
    """Division de C (hacia 0)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def c_mod(a, b):
    return a - b * c_div(a, b)


def lookup_volume(a, b):
    if b == 0:
        return 0
    if b == 31:
        return a
    if a < -63 or a > 63:
        return (b * (a + 1)) >> 5
    if b < 0:
        return vl(-a, -b) if a < 0 else -vl(a, -b)
    return -vl(-a, b) if a < 0 else vl(a, b)


class Instr:
    """AdLibInstrument (30 bytes)."""
    def __init__(self, b):
        b = bytes(b[:30]).ljust(30, b"\0")
        (self.modChar, self.modScal, self.modAD, self.modSR, self.modWave,
         self.carChar, self.carScal, self.carAD, self.carSR, self.carWave,
         self.feedback, self.flagsA) = b[:12]
        self.extraA = b[12:20]
        self.flagsB = b[20]
        self.extraB = b[21:29]
        self.duration = b[29]


class S10:
    def __init__(self):
        self.active = 0
        self.curVal = 0
        self.count = 0
        self.maxValue = 0
        self.startValue = 0
        self.loop = 0
        self.tableA = [0] * 4
        self.tableB = [0] * 4
        self.unk3 = 0
        self.modWheel = 0
        self.modWheelLast = 0
        self.speedLoMax = 0
        self.numSteps = 0
        self.speedHi = 0
        self.direction = 0
        self.speedLo = 0
        self.speedLoCounter = 0


class S11:
    def __init__(self):
        self.modifyVal = 0
        self.param = 0
        self.flag0x40 = 0
        self.flag0x10 = 0
        self.s10 = None


class Voice:
    def __init__(self, ch):
        self.part = None
        self.next = None
        self.prev = None
        self.waitForPedal = False
        self.note = 0
        self.channel = ch
        self.twoChan = 0
        self.vol1 = 0
        self.vol2 = 0
        self.duration = 0
        self.s10a, self.s11a, self.s10b, self.s11b = S10(), S11(), S10(), S11()
        self.s11a.s10 = self.s10b
        self.s11b.s10 = self.s10a


class AdPart:
    """AdLibPart (el canal MIDI del driver)."""
    def __init__(self, owner, ch):
        self.owner = owner
        self.channel = ch
        self.voice = None
        self.pitchBend = 0
        self.pitchBendFactor = 2
        self.transposeEff = 0
        self.volEff = 0
        self.detuneEff = 0
        self.modWheel = 0
        self.pedal = False
        self.program = 0
        self.priEff = 127
        self.pan = 64
        self.allocated = False
        self.instr = Instr(GM0)

    def voices(self):
        v = self.voice
        while v:
            nxt = v.next
            yield v
            v = nxt

    def _renote(self):
        for v in self.voices():
            self.owner.note_on(v.channel, v.note + self.transposeEff,
                               ((self.pitchBend * self.pitchBendFactor) >> 6) + self.detuneEff)

    def note_off(self, note):
        self.owner.part_key_off(self, note)

    def note_on(self, note, vel):
        self.owner.part_key_on(self, self.instr, note, vel)

    def pitch_bend(self, bend):
        self.pitchBend = bend
        self._renote()

    def modulation_wheel(self, value):
        self.modWheel = value
        for v in self.voices():
            if v.s10a.active and v.s11a.flag0x40:
                v.s10a.modWheel = self.modWheel >> 2
            if v.s10b.active and v.s11b.flag0x40:
                v.s10b.modWheel = self.modWheel >> 2

    def volume(self, value):
        self.volEff = value
        o = self.owner
        for v in self.voices():
            o.set_param(v.channel, 0, VOLUME_TABLE[vl(v.vol2, self.volEff >> 2)])
            if v.twoChan:
                o.set_param(v.channel, 13, VOLUME_TABLE[vl(v.vol1, self.volEff >> 2)])

    def pitch_bend_factor(self, value):
        self.pitchBendFactor = value
        self._renote()

    def detune(self, value):
        self.detuneEff = value
        self._renote()

    def transpose(self, value):
        self.transposeEff = value
        self._renote()

    def sustain(self, value):
        self.pedal = value
        if not value:
            for v in self.voices():
                if v.waitForPedal:
                    self.owner.mc_off(v)

    def all_notes_off(self):
        while self.voice:
            self.owner.mc_off(self.voice)

    def custom_instrument(self, data):
        self.instr = Instr(data)


class Driver:
    """MidiDriver_ADLIB en modo OPL2 (ni el modo de SCUMM v3 ni el OPL3)."""
    def __init__(self):
        self.reg = [0] * 256
        self.writes = []                    # (registro, valor) de la llamada de ahora
        self.timerCounter = 0
        self.voiceIndex = -1
        self.curNot = [0] * 9
        self.chanTab2 = [0] * 9
        self.voices = [Voice(i) for i in range(9)]
        self.parts = [AdPart(self, i + (1 if i >= 9 else 0)) for i in range(32)]
        self.randSeed = 1
        self.write(8, 0x40)
        self.write(0xBD, 0)
        self.write(1, 0x20)

    def write(self, reg, value):
        value &= 0xFF
        if self.reg[reg] == value:
            return
        self.reg[reg] = value
        self.writes.append((reg, value))

    def allocate_channel(self):
        for p in self.parts:
            if not p.allocated:
                p.allocated = True
                return p
        return None

    def on_timer(self, timer_proc):
        timer_proc()
        self.timerCounter += 0xD69
        while self.timerCounter >= 0x411B:
            self.timerCounter -= 0x411B
            for v in self.voices:
                if not v.part:
                    continue
                if v.duration:
                    v.duration -= 0x11
                    if v.duration <= 0:
                        self.mc_off(v)
                        return
                if v.s10a.active:
                    self.mc_inc(v, v.s10a, v.s11a)
                if v.s10b.active:
                    self.mc_inc(v, v.s10b, v.s11b)

    def mc_off(self, v):
        self.key_off(v.channel)
        tmp = v.prev
        if v.next:
            v.next.prev = tmp
        if tmp:
            tmp.next = v.next
        else:
            v.part.voice = v.next
        v.part = None

    def mc_inc(self, v, s10, s11):
        part = v.part
        code = self.s10_on_timer(s10, s11)
        if code & 1:
            if s11.param == 0:
                v.vol2 = (s10.startValue + s11.modifyVal) & 0xFF
                self.set_param(v.channel, 0, VOLUME_TABLE[vl(v.vol2, part.volEff >> 2)])
            elif s11.param == 13:
                v.vol1 = (s10.startValue + s11.modifyVal) & 0xFF
                if v.twoChan:
                    self.set_param(v.channel, 13, VOLUME_TABLE[vl(v.vol1, part.volEff >> 2)])
                else:
                    self.set_param(v.channel, 13, v.vol1)
            elif s11.param == 30:
                s11.s10.modWheel = s8(s11.modifyVal)
            elif s11.param == 31:
                s11.s10.unk3 = s8(s11.modifyVal)
            else:
                self.set_param(v.channel, s11.param, s10.startValue + s11.modifyVal)
        if code & 2 and s11.flag0x10:
            self.key_on_off(v.channel)

    def key_off(self, ch):
        r = ch + 0xB0
        self.write(r, self.reg[r] & ~0x20)

    def s10_on_timer(self, s10, s11):
        result = 0
        if s10.count:
            s10.count = s16(s10.count - 17)
            if s10.count <= 0:
                s10.active = 0
                return 0
        i = s10.curVal + s10.speedHi
        s10.speedLoCounter = (s10.speedLoCounter + s10.speedLo) & 0xFFFF
        if s10.speedLoCounter >= s10.speedLoMax:
            s10.speedLoCounter = (s10.speedLoCounter - s10.speedLoMax) & 0xFFFF
            i += s10.direction
        if s10.curVal != i or s10.modWheel != s10.modWheelLast:
            s10.curVal = s16(i)
            s10.modWheelLast = s10.modWheel
            i = lookup_volume(i, s10.modWheelLast)
            if i != s11.modifyVal:
                s11.modifyVal = s16(i)
                result = 1
        s10.numSteps = (s10.numSteps - 1) & 0xFFFF
        if not s10.numSteps:
            s10.active += 1
            if s10.active > 4:
                if s10.loop:
                    s10.active = 1
                    result |= 2
                    self.s10_setup(s10)
                else:
                    s10.active = 0
            else:
                self.s10_setup(s10)
        return result

    def set_param(self, ch, param, value):
        if param <= 12:
            reg = OP2[ch]
        elif param <= 25:
            param -= 13
            reg = OP1[ch]
        elif param <= 27:
            param -= 13
            reg = ch
        elif param in (28, 29):
            value -= 15 if param == 28 else 383
            value *= 16
            self.chanTab2[ch] = value & 0xFFFF
            self.play_note(ch, self.curNot[ch] + value)
            return
        else:
            return
        base, shift, mask, inv = SET_PARAM[param]
        if inv:
            value = inv - value
        reg += base
        self.write(reg, (self.reg[reg] & ~mask) | ((value & 0xFF) << shift))

    def key_on_off(self, ch):
        r = ch + 0xB0
        val = self.reg[r]
        self.write(r, val & ~0x20)
        self.write(r, val | 0x20)

    def s10_setup(self, s10):
        b = s10.unk3
        f = s10.active - 1
        t = s10.tableA[f]
        e = NUM_STEPS[vl(t & 0x7F, b)]
        if t & 0x80:
            e = self.random(e)
        if e == 0:
            e += 1
        s10.numSteps = s10.speedLoMax = e
        if f != 2:
            c = s10.maxValue
            g = s10.startValue
            t = s10.tableB[f]
            d = lookup_volume(c, (t & 0x7F) - 31)
            if t & 0x80:
                d = self.random(d)
            if d + g > c:
                h = c - g
            else:
                h = d
                if d + g < 0:
                    h = -g
            h -= s10.curVal
        else:
            h = 0
        s10.speedHi = s16(c_div(h, e))
        if h < 0:
            h = -h
            s10.direction = -1
        else:
            s10.direction = 1
        s10.speedLo = c_mod(h, e) & 0xFFFF
        s10.speedLoCounter = 0

    def play_note(self, ch, note):
        note2 = ((note >> 7) - 4) & 0xFF
        note2 = note2 if note2 < 128 else 0
        octv = note2 // 12
        octv = (7 << 2) if octv > 7 else (octv << 2)
        notex = note2 % 12 + 3
        old = self.reg[ch + 0xB0]
        if old & 0x20:
            old &= ~0x20
            if octv > old:
                if notex < 6:
                    notex += 12
                    octv -= 4
            elif octv < old:
                if notex > 11:
                    notex -= 12
                    octv += 4
        i = (notex << 3) + ((note >> 4) & 7)
        self.write(ch + 0xA0, NOTE_FREQ[i])
        self.write(ch + 0xB0, (octv & 0xFF) | 0x20)

    def random(self, a):
        if self.randSeed & 1:
            self.randSeed = (self.randSeed >> 1) ^ 0xB8
        else:
            self.randSeed >>= 1
        return (self.randSeed * a) >> 8

    def part_key_off(self, part, note):
        for v in part.voices():
            if v.note == note:
                if part.pedal:
                    v.waitForPedal = True
                else:
                    self.mc_off(v)

    def part_key_on(self, part, instr, note, vel):
        v = self.allocate_voice(part.priEff)
        if not v:
            return
        v.part = part
        v.next = part.voice
        part.voice = v
        v.prev = None
        if v.next:
            v.next.prev = v
        self.mc_key_on(v, instr, note, vel)

    def allocate_voice(self, pri):
        best = None
        for _ in range(9):
            self.voiceIndex += 1
            if self.voiceIndex >= 9:
                self.voiceIndex = 0
            ac = self.voices[self.voiceIndex]
            if not ac.part:
                return ac
            if not ac.next and ac.part.priEff <= pri:
                pri = ac.part.priEff
                best = ac
        if best:
            self.mc_off(best)
        return best

    def mc_key_on(self, v, ins, note, vel):
        part = v.part
        v.twoChan = ins.feedback & 1
        v.note = note
        v.waitForPedal = False
        v.duration = ins.duration * 63
        vol1 = min(0x3F, (ins.modScal & 0x3F) + vl(vel >> 1, ins.modWave >> 2))
        v.vol1 = vol1
        vol2 = min(0x3F, (ins.carScal & 0x3F) + vl(vel >> 1, ins.carWave >> 2))
        v.vol2 = vol2
        c = part.volEff >> 2
        vol2 = VOLUME_TABLE[vl(vol2, c)]
        if v.twoChan:
            vol1 = VOLUME_TABLE[vl(vol1, c)]
        self.setup_channel(v.channel, ins, vol1, vol2)
        self.note_on_ex(v.channel, (note + part.transposeEff) & 0xFF,
                        part.detuneEff + ((part.pitchBend * part.pitchBendFactor) >> 6))
        if ins.flagsA & 0x80:
            self.mc_init(v, v.s10a, v.s11a, ins.flagsA, ins.extraA)
        else:
            v.s10a.active = 0
        if ins.flagsB & 0x80:
            self.mc_init(v, v.s10b, v.s11b, ins.flagsB, ins.extraB)
        else:
            v.s10b.active = 0

    def setup_channel(self, ch, ins, vol1, vol2):
        o = OP1[ch]
        self.write(o + 0x20, ins.modChar)
        self.write(o + 0x40, (ins.modScal | 0x3F) - vol1)
        self.write(o + 0x60, ~ins.modAD)
        self.write(o + 0x80, ~ins.modSR)
        self.write(o + 0xE0, ins.modWave)
        o = OP2[ch]
        self.write(o + 0x20, ins.carChar)
        self.write(o + 0x40, (ins.carScal | 0x3F) - vol2)
        self.write(o + 0x60, ~ins.carAD)
        self.write(o + 0x80, ~ins.carSR)
        self.write(o + 0xE0, ins.carWave)
        self.write(ch + 0xC0, ins.feedback)

    def mc_init(self, v, s10, s11, flags, ie):
        part = v.part
        s11.modifyVal = 0
        s11.flag0x40 = flags & 0x40
        s10.loop = flags & 0x20
        s11.flag0x10 = flags & 0x10
        s11.param = PARAM_TABLE1[flags & 0xF]
        s10.maxValue = MAX_VAL[flags & 0xF]
        s10.unk3 = 31
        s10.modWheel = (part.modWheel >> 2) if s11.flag0x40 else 31
        if s11.param == 0:
            s10.startValue = v.vol2
        elif s11.param == 13:
            s10.startValue = v.vol1
        elif s11.param == 30:
            s10.startValue = 31
            s11.s10.modWheel = 0
        elif s11.param == 31:
            s10.startValue = 0
            s11.s10.unk3 = 0
        else:
            s10.startValue = self.get_param(v.channel, s11.param)
        # struct10Init
        s10.active = 1
        s10.curVal = 0
        s10.modWheelLast = 31
        s10.count = ie[0] * 63
        s10.tableA = [ie[1], ie[3], ie[5], ie[6]]
        s10.tableB = [ie[2], ie[4], 0, ie[7]]
        self.s10_setup(s10)

    def get_param(self, ch, param):
        if param <= 12:
            reg = OP2[ch]
        elif param <= 25:
            param -= 13
            reg = OP1[ch]
        elif param <= 27:
            param -= 13
            reg = ch
        elif param == 28:
            return 0xF
        elif param == 29:
            return 0x17F
        else:
            return 0
        base, shift, mask, inv = SET_PARAM[param]
        val = (self.reg[reg + base] & mask) >> shift
        if inv:
            val = inv - val
        return val

    def note_on(self, ch, note, mod):
        code = ((note & 0xFF) << 7) + mod
        self.curNot[ch] = code & 0xFFFF
        self.play_note(ch, s16(self.chanTab2[ch]) + code)

    def note_on_ex(self, ch, note, mod):
        code = (note << 7) + mod
        self.curNot[ch] = code & 0xFFFF
        self.chanTab2[ch] = 0
        self.play_note(ch, code)


# --- el MIDI (MidiParser_SMF con mpSmartJump) ---------------------------------------
def _vlq(d, p):
    v = 0
    for _ in range(4):
        c = d[p]
        p += 1
        v = v << 7 | c & 0x7F
        if not c & 0x80:
            break
    return v, p


def smf_events(smf):
    """MThd + MTrk: (ppqn, [(delta, tipo, datos)]) de la primera pista. tipo: el byte de
    estado (0x80..0xEF), 0xF0 (datos del sysex) o (0xFF, tipo de meta)."""
    if smf[:4] != b"MThd":
        raise ValueError("ADL: sin MThd")
    hl = struct.unpack(">I", smf[4:8])[0]
    ppqn = struct.unpack(">H", smf[12:14])[0]
    o = 8 + hl
    while smf[o:o + 4] != b"MTrk":
        o += 8 + struct.unpack(">I", smf[o + 4:o + 8])[0]
    n = struct.unpack(">I", smf[o + 4:o + 8])[0]
    d = smf[o + 8:o + 8 + n]
    out = []
    p = 0
    run = 0
    while p < len(d):
        delta, p = _vlq(d, p)
        st = d[p]
        if st & 0x80:
            p += 1
            if st < 0xF0:
                run = st
        else:
            st = run
        if st == 0xFF:
            typ = d[p]
            ln, p = _vlq(d, p + 1)
            out.append((delta, (0xFF, typ), d[p:p + ln]))
            p += ln
        elif st in (0xF0, 0xF7):
            ln, p = _vlq(d, p)
            out.append((delta, 0xF0, d[p:p + ln]))
            p += ln
        else:
            k = 1 if (st & 0xF0) in (0xC0, 0xD0) else 2
            ev = st
            data = d[p:p + k]
            if (st & 0xF0) == 0x90 and data[1] == 0:
                ev = 0x80 | (st & 15)            # (nota con velocidad 0: fin de nota)
            out.append((delta, ev, data))
            p += k
    return ppqn, out


class Parser:
    def __init__(self, ppqn, events, player):
        self.ppqn = ppqn
        self.events = events
        self.player = player
        self.timerRate = TIMER_US
        self.set_tempo(500000)
        self.active = [0] * 128             # (bit por canal)
        self.hanging = []                   # [canal, nota, tiempo que le queda]
        self.reset()

    def set_tempo(self, tempo):
        self.tempo = tempo
        self.psec = (tempo + (self.ppqn >> 2)) // self.ppqn

    def reset(self):
        self.pos = 0
        self.playTime = 0
        self.lastEventTime = 0
        self.lastEventTick = 0
        self.playTick = 0
        self.tracking = True

    def send(self, ev, data):
        self.player.send(ev, data)

    def active_note(self, ch, note, on):
        if on:
            self.active[note] |= 1 << ch
        else:
            self.active[note] &= ~(1 << ch)
        for h in self.hanging:
            if h[2] and h[0] == ch and h[1] == note:
                h[2] = 0

    def hanging_note(self, ch, note, left, recycle=True):
        best = None
        for h in self.hanging:
            if h[0] == ch and h[1] == note:
                if h[2] and h[2] < left and recycle:
                    return
                best = h
                if h[2] and recycle:
                    self.send(0x80 | ch, bytes((note, 0)))
                break
        if not best:
            for h in self.hanging:
                if h[2] == 0:
                    best = h
                    break
        if not left or left < 0:
            left = 1
        if best:
            best[0], best[1], best[2] = ch, note, left
        else:
            self.hanging.append([ch, note, left])

    def on_timer(self):
        if not self.tracking:
            return
        self.abort = False
        end = self.playTime + self.timerRate
        for h in self.hanging:
            if h[2]:
                if h[2] <= self.timerRate:
                    self.send(0x80 | h[0], bytes((h[1], 0)))
                    h[2] = 0
                else:
                    h[2] -= self.timerRate
        while not self.abort:
            if self.pos >= len(self.events):
                self.tracking = False
                return
            delta, ev, data = self.events[self.pos]
            tick = self.lastEventTick + delta
            etime = self.lastEventTime + delta * self.psec
            if etime > end:
                break
            if not isinstance(ev, tuple) and ev < 0xF0:
                if ev & 0xF0 == 0x80:
                    self.active_note(ev & 15, data[0], False)
                elif ev & 0xF0 == 0x90:
                    self.active_note(ev & 15, data[0], True)
            if not self.process(ev, data, True):
                return
            if not self.abort:
                self.playTime = self.lastEventTime = etime
                self.playTick = self.lastEventTick = tick
                self.pos += 1
        if not self.abort:
            self.playTime = end
            self.playTick = (end - self.lastEventTime) // self.psec + self.lastEventTick

    def process(self, ev, data, fire):
        if ev == 0xF0:
            if fire:
                n = len(data) - 1 if data and data[-1] == 0xF7 else len(data)
                self.player.sysex(data[:n])
        elif isinstance(ev, tuple):
            typ = ev[1]
            if typ == 0x2F:
                self.tracking = False
                if fire:
                    self.player.meta(typ)
                return False
            if typ == 0x51 and len(data) >= 3:
                self.set_tempo(data[0] << 16 | data[1] << 8 | data[2])
        elif fire:
            self.send(ev, data)
        return True

    def jump_to_tick(self, target):
        cur = (self.pos, self.playTime, self.lastEventTime, self.lastEventTick, self.playTick, self.tracking)
        self.reset()
        if target > 0:
            while True:
                if self.pos >= len(self.events):
                    (self.pos, self.playTime, self.lastEventTime, self.lastEventTick,
                     self.playTick, self.tracking) = cur
                    return False
                delta, ev, data = self.events[self.pos]
                tick = self.lastEventTick + delta
                if tick >= target:
                    self.playTime += (target - self.lastEventTick) * self.psec
                    self.playTick = target
                    break
                if isinstance(ev, tuple) and ev[1] == 0x2F:
                    (self.pos, self.playTime, self.lastEventTime, self.lastEventTick,
                     self.playTick, self.tracking) = cur
                    return False
                self.process(ev, data, False)
                self.playTime = self.lastEventTime = self.lastEventTime + delta * self.psec
                self.playTick = self.lastEventTick = tick
                self.pos += 1
        # salto "listo": las notas que suenan se quedan colgadas hasta su fin de nota
        # (buscado desde donde se estaba)
        target_state = (self.pos, self.playTime, self.lastEventTime, self.lastEventTick, self.playTick)
        self.hang_all(cur)
        self.pos, self.playTime, self.lastEventTime, self.lastEventTick, self.playTick = target_state
        self.tracking = True
        self.abort = True
        return True

    def hang_all(self, cur):
        # (como MidiParser::hangAllActiveNotes: empieza en el evento de detras del que
        # salta, contando desde el tic del anterior a este; asi lo hace ScummVM)
        temp = list(self.active)
        pos, _, _, last_tick, _, _ = cur
        base_tick = last_tick
        tick = last_tick
        p = pos + 1
        while any(temp):
            if p >= len(self.events):
                for n in range(128):
                    for ch in range(16):
                        if temp[n] & (1 << ch):
                            self.active_note(ch, n, False)
                            self.send(0x80 | ch, bytes((n, 0)))
                break
            delta, ev, data = self.events[p]
            tick += delta
            if not isinstance(ev, tuple) and ev < 0xF0 and ev & 0xF0 == 0x80:
                ch, n = ev & 15, data[0]
                if temp[n] & (1 << ch):
                    self.hanging_note(ch, n, (tick - base_tick) * self.psec, False)
                    temp[n] &= ~(1 << ch)
            elif isinstance(ev, tuple) and ev[1] == 0x2F:
                for n in range(128):
                    for ch in range(16):
                        if temp[n] & (1 << ch):
                            self.active_note(ch, n, False)
                            self.send(0x80 | ch, bytes((n, 0)))
                break
            p += 1


# --- iMuse: Part y Player (sistema viejo: MI1, MI2, DOTT) -----------------------------
def decode_sysex(src, n):
    out = []
    i = 0
    while n >= 0:
        a = src[i] if i < len(src) else 0
        b = src[i + 1] if i + 1 < len(src) else 0
        out.append(((a << 4) & 0xFF) | (b & 0x0F))
        i += 2
        n -= 2
    return out


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


class Part:
    def __init__(self, player, chan):
        self.player = player
        self.chan = chan
        self.on = True
        self.pri = 0
        self.pri_eff = player.priority
        self.vol = 127
        self.vol_eff = player.vol_eff
        self.pan = clamp(player.pan, -64, 63)
        self.pan_eff = self.pan
        self.transpose = 0
        self.transpose_eff = player.transpose
        self.detune = 0
        self.detune_eff = player.detune
        self.pitchbend_factor = 2
        self.pitchbend = 0
        self.modwheel = 0
        self.pedal = False
        self.instrument = None
        self.unassigned = True
        self.mc = None

    def set_onoff(self, on):
        if self.on != on:
            self.on = on
            if not on:
                self.off(True)

    def set_pri(self, pri):
        self.pri = s8(pri)
        self.pri_eff = clamp(self.pri + self.player.priority, 0, 255)
        if self.mc:
            self.mc.priEff = self.pri_eff

    def volume(self, v):
        self.vol = v
        self.send_volume()

    def send_volume(self):
        self.vol_eff = ((self.vol + 1) * self.player.vol_eff) >> 7
        if self.mc:
            self.mc.volume(self.vol_eff)

    def set_pan(self, pan):
        self.pan = s8(pan)
        self.pan_eff = clamp(self.pan + self.player.pan, -64, 63)
        if self.mc:
            self.mc.pan = self.pan_eff + 0x40

    def set_transpose(self, t, lo, hi):
        self.transpose = s8(t)
        self.transpose_eff = 0 if self.transpose == -128 else clamp(self.transpose + self.player.transpose, lo, hi)
        if self.mc:
            self.mc.transpose(self.transpose_eff)

    def set_detune(self, d):
        self.detune = s8(d)
        self.detune_eff = clamp(self.detune + self.player.detune, -128, 127)
        if self.mc:
            self.mc.detune(self.detune_eff)

    def pitch_bend_factor(self, v):
        if v > 12:
            return
        self.pitch_bend(0)
        self.pitchbend_factor = v
        if self.mc:
            self.mc.pitch_bend_factor(v)

    def pitch_bend(self, v):
        self.pitchbend = v
        if self.mc:
            self.mc.pitch_bend(v)

    def sustain(self, v):
        self.pedal = v
        if self.mc:
            self.mc.sustain(v)

    def modulation_wheel(self, v):
        self.modwheel = v
        if self.mc:
            self.mc.modulation_wheel(v)

    def set_instrument(self, data):
        self.instrument = bytes(data[:30])
        if self.mc:
            self.mc.custom_instrument(self.instrument)

    def send_all(self):
        mc = self.mc
        if not mc:
            return
        mc.pitch_bend_factor(self.pitchbend_factor)
        mc.transpose(self.transpose_eff)
        mc.detune(self.detune_eff)
        mc.pitch_bend(self.pitchbend)
        mc.volume(self.vol_eff)
        mc.sustain(self.pedal)
        mc.modulation_wheel(self.modwheel)
        mc.pan = self.pan_eff + 0x40
        if self.instrument is not None:
            mc.custom_instrument(self.instrument)
        mc.priEff = self.pri_eff

    def note_on(self, note, vel):
        if not self.on:
            return
        if self.unassigned:
            self.unassigned = False
            if self.instrument is None:
                return
        if self.mc and self.instrument is not None:
            self.mc.note_on(note, vel)

    def note_off(self, note):
        if self.on and self.mc:
            self.mc.note_off(note)

    def off(self, release):
        if self.mc:
            self.mc.sustain(False)
            self.mc.all_notes_off()
            if release:
                self.mc.allocated = False
                self.mc = None

    def uninit(self):
        self.off(False)
        if self.mc:
            self.mc.allocated = False
        self.mc = None


class Player:
    def __init__(self, driver, adl):
        self.driver = driver
        self.active = True
        self.priority, self.volume, self.pan, self.transpose, self.detune = 0x80, 0x7F, 0, 0, 0
        self.vol_eff = 127
        mdhd = adl[8:16] if adl[:4] == b"MDhd" else b""
        if len(mdhd) == 8 and (mdhd[2] | mdhd[3] | mdhd[7]):
            self.priority, self.volume, self.pan = mdhd[2], mdhd[3], s8(mdhd[4])
            self.transpose, self.detune = s8(mdhd[5]), s8(mdhd[6])
        smf = adl[8 + struct.unpack(">I", adl[4:8])[0]:] if adl[:4] == b"MDhd" else adl
        self.parts = {}
        self.jumps = 0
        self.jump_at = []                   # (llamada, tic al que salta)
        self.notes_after_jump = 0           # notas que empiezan despues del primer salto
        self.calls = 0
        ppqn, events = smf_events(smf)
        self.parser = Parser(ppqn, events, self)

    def get_part(self, chan):
        if chan not in self.parts:
            self.parts[chan] = Part(self, chan)
        return self.parts[chan]

    def on_timer(self):
        if self.active:
            self.parser.on_timer()

    def send(self, ev, data):
        cmd, chan = ev & 0xF0, ev & 15
        part = self.parts.get(chan) if cmd != 0xB0 else self.parts.get(chan)
        if cmd == 0x80:
            if part:
                part.note_off(data[0])
        elif cmd == 0x90:
            if self.jump_at:
                self.notes_after_jump += 1
            if part:
                part.note_on(data[0], data[1])
        elif cmd == 0xB0:
            if not part:
                return
            c, v = data[0], data[1]
            if c == 1:
                part.modulation_wheel(v)
            elif c == 7:
                part.volume(v)
            elif c == 10:
                part.set_pan(v - 0x40)
            elif c == 16:
                part.pitch_bend_factor(v)
            elif c == 17:
                part.set_detune(v - 0x40)
            elif c == 18:
                part.set_pri(v - 0x40)
            elif c == 64:
                part.sustain(v != 0)
            elif c == 123:
                if part.mc:
                    part.mc.all_notes_off()
        elif cmd == 0xE0:
            if part:
                part.pitch_bend(((data[1] << 7) | data[0]) - 0x2000)

    def meta(self, typ):
        if typ == 0x2F:
            self.clear()

    def clear(self):
        if not self.active:
            return
        for p in list(self.parts.values()):
            p.uninit()
        self.parts = {}
        self.active = False

    def sysex(self, msg):
        if not msg or msg[0] != IMUSE_SYSEX_ID:
            return
        p = msg[1:]
        n = len(msg) - 2
        code = p[0]
        p = p[1:]
        if code == 0:
            part = self.get_part(p[0] & 0x0F)
            buf = [0] + decode_sysex(p[1:], n - 1)
            part.set_onoff(buf[1] & 1)
            part.set_pri(buf[2])
            part.volume(buf[3])
            part.set_pan(buf[4])
            part.set_transpose(buf[5], -12, 12)
            part.set_detune(buf[6])
            part.pitch_bend_factor(buf[7])
            if part.mc is None:
                part.mc = self.driver.allocate_channel()
            part.send_all()
        elif code == 1:
            part = self.parts.pop(p[0], None)
            if part:
                part.uninit()
        elif code == 2:
            pass
        elif code == 16:
            part = self.get_part(p[0] & 0x0F)
            if n in (62, 48):
                part.set_instrument(decode_sysex(p[2:], n - 2))
        elif code == 48:
            buf = decode_sysex(p[1:], n - 1)
            if buf[0] == 0:
                self.jump(buf[1] << 8 | buf[2], buf[3] << 8 | buf[4], buf[5] << 8 | buf[6])
        else:
            raise ValueError("ADL: sysex de iMuse %d sin hacer" % code)

    def jump(self, track, beat, tick):
        target = (beat - 1) * TICKS_PER_BEAT + tick
        if not self.parser.jump_to_tick(target):
            return
        self.jumps += 1
        self.jump_at.append((self.calls, target))
        for part in self.parts.values():
            if part.pedal:
                part.sustain(False)


class Toque:
    def __init__(self):
        self.calls = []                     # escrituras de cada llamada (antes de sus 4 ms)
        self.fin = None                     # llamada en la que acaba la pista (None: no acaba)
        self.salto = None                   # (llamada del primer salto, llamada del segundo)
        self.musical = False                # la vuelta tiene notas (una melodia, no notas
                                            # que se quedan sonando)


def escrituras(adl, max_calls=250 * 30):
    """Toca el sonido 'ADL ' (sin la cabecera del bloque) hasta que acaba la pista o,
    si salta, hasta la segunda vuelta; o max_calls llamadas."""
    drv = Driver()
    pl = Player(drv, bytes(adl))
    t = Toque()
    init = drv.writes
    drv.writes = []
    for k in range(max_calls):
        pl.calls = k
        drv.on_timer(pl.on_timer)
        w = drv.writes
        drv.writes = []
        if k == 0:
            w = init + w
        t.calls.append(w)
        if not pl.active and t.fin is None:
            t.fin = k
            break
        if len(pl.jump_at) >= 2:
            t.salto = (pl.jump_at[0][0], pl.jump_at[1][0])
            t.musical = pl.notes_after_jump > 0
            break
    return t


# --- el sonido para el Next ---------------------------------------------------------
def duracion(adl):
    """Lo que la pista suena para los scripts (isSoundRunning), en jiffies (1/60 s):
    hasta el fin de la pista, o 0xFFFF si salta para siempre; 0 si no se puede leer."""
    try:
        t = escrituras(adl)
    except (ValueError, IndexError, struct.error):
        return 0
    if t.fin is None:
        return 0xFFFF
    return max(1, -(-t.fin * 4 * 60 // 1000))


def _resample(x, src, dst):
    """De src a dst muestras por segundo: un filtro paso bajo (sinc con ventana de
    Blackman, corte al 45 % de dst) y despues interpolacion lineal."""
    import numpy as np
    fc = 0.45 * dst / src
    n = 801
    k = np.arange(n) - (n - 1) / 2
    h = 2 * fc * np.sinc(2 * fc * k) * np.blackman(n)
    h /= h.sum()
    m = len(x) + n - 1
    size = 1 << (m - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(h, size), size)[:m]
    y = y[(n - 1) // 2:(n - 1) // 2 + len(x)]
    t = np.arange(int(len(x) * dst / src)) * (src / dst)
    return np.interp(t, np.arange(len(x)), y)


def audio(adl, rate, bucle_s=0.5, pico=100):
    """(muestras de 8 bits sin signo a rate, principio del bucle o None) del sonido 'ADL ',
    con el OPL2 de tools/opl2.py. Lo que acaba: hasta que se calla (con la cola de
    la ultima nota). Lo que da vueltas: el principio y un trozo de unos bucle_s
    segundos que se repite (con un fundido al final, para que no se oiga el salto);
    si a la segunda vuelta ya no suena nada, como uno que acaba. Cada sonido, con
    su pico en +-pico."""
    import numpy as np
    import opl2
    ri = int(round(rate))
    t = escrituras(adl)
    chip = opl2.Opl2()
    smp = []
    marks = []
    acc = 0.0
    for w in t.calls:
        marks.append(len(smp))
        for r, v in w:
            chip.write(r, v)
        acc += opl2.RATE / 250
        m = int(acc)
        acc -= m
        smp += chip.generate(m)
    if t.fin is not None:
        cola = 0
        while not chip.silent() and cola < 2 * opl2.RATE:
            smp += chip.generate(1000)
            cola += 1000
    x = np.array(smp, dtype=float)
    top = float(np.abs(x).max()) if len(x) else 0.0
    if top == 0:
        return b"", None
    y = _resample(x, opl2.RATE, rate) * (pico / top)
    loop = None
    if t.fin is None:
        a, b = (int(marks[c] * rate / opl2.RATE) for c in t.salto)
        firme = float(np.sqrt((y[a:b] ** 2).mean())) if b > a else 0.0
        if t.musical:                       # una melodia: la vuelta entera (la segunda)
            y = y[:b]
            loop = a
        elif firme >= 0.5:                  # notas que siguen sonando: un trozo corto
            w = max(1, ri // 50)
            rms = [float(np.sqrt((y[i:i + w] ** 2).mean())) for i in range(0, a, w)]
            t0 = len(rms) - 5
            for i in range(2, len(rms) - 5):
                if all(0.6 * firme <= v <= 1.6 * firme for v in rms[i:i + 5]):
                    t0 = i
                    break
            t0 = max(t0 * w, ri // 25)
            seg = y[t0:t0 + ri // 5]
            ln = int(bucle_s * rate)
            if len(seg) > 64:               # (si es un tono, un numero entero de periodos)
                seg = seg - seg.mean()
                ac = np.correlate(seg, seg, "full")[len(seg) - 1:]
                lo, hi = max(2, ri // 4000), min(len(ac) - 1, ri // 40)
                if hi > lo:
                    per = lo + int(np.argmax(ac[lo:hi]))
                    if ac[per] > 0.8 * ac[0]:
                        ln = max(per, int(round(ln / per)) * per)
            f = min(ri // 60, t0, ln // 2)
            r = np.linspace(0.0, 1.0, f, endpoint=False)
            e = t0 + ln
            y[e - f:e] = y[e - f:e] * (1 - r) + y[t0 - f:t0] * r
            y = y[:e]
            loop = t0
    if loop is None:
        on = np.nonzero(np.abs(y) >= 1.5)[0]
        if not len(on):
            return b"", None
        y = y[:on[-1] + 1]
        f = min(len(y), ri // 300)
        if f:
            y[-f:] *= np.linspace(1.0, 0.0, f)
    u = np.clip(np.round(128 + y), 1, 255).astype(np.uint8)
    return bytes(u), loop
