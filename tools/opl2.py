"""Un OPL2 (YM3812, el chip de las AdLib) para el conversor: registros -> muestras a su
ritmo de verdad (3579545 / 72 = 49716 por segundo). Sigue el funcionamiento del chip
tal como lo describe el analisis de su silicio (las tablas de seno logaritmico y de
exponencial de su ROM, el generador de envolventes por contador y su reloj de dos
fases, el vibrato y el tremolo, la realimentacion y las cuatro formas de onda); no
tiene el modo de ritmo (SCUMM no lo usa). Solo hace falta para convertir: el Next no
tiene este chip.

    chip = Opl2(); chip.write(reg, valor); chip.generate(n) -> lista de n muestras
"""
import math

RATE = 49716

LOGSIN = [round(-math.log2(math.sin((i + 0.5) * math.pi / 512)) * 256) for i in range(256)]
EXP = [round((2 ** ((255 - i) / 256) - 1) * 1024) + 1024 for i in range(256)]
MULT = (1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30)
KSLROM = (0, 32, 40, 45, 48, 51, 53, 55, 56, 58, 59, 60, 61, 62, 63, 64)
KSLSHIFT = (8, 1, 2, 0)
EG_INCSTEP = ((0, 0, 0, 0), (1, 0, 0, 0), (1, 0, 1, 0), (1, 1, 1, 0))
ATTACK, DECAY, SUSTAIN, RELEASE = 0, 1, 2, 3
# los operadores de cada canal (desplazamiento del registro): modulador y portador
SLOT_OFFSETS = (0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 20, 21)


def _exp(level):
    if level > 0x1FFF:
        level = 0x1FFF
    return (EXP[level & 0xFF] << 1) >> (level >> 8)


def _wave(wf, phase, env):
    """Las cuatro formas de onda del OPL2: seno, medio seno, seno en valor absoluto y
    cuartos de seno."""
    phase &= 0x3FF
    if wf == 0:
        out = LOGSIN[(phase & 0xFF) ^ 0xFF] if phase & 0x100 else LOGSIN[phase & 0xFF]
        v = _exp(out + (env << 3))
        return ~v if phase & 0x200 else v
    if wf == 1:
        if phase & 0x200:
            out = 0x1000
        else:
            out = LOGSIN[(phase & 0xFF) ^ 0xFF] if phase & 0x100 else LOGSIN[phase & 0xFF]
        return _exp(out + (env << 3))
    if wf == 2:
        out = LOGSIN[(phase & 0xFF) ^ 0xFF] if phase & 0x100 else LOGSIN[phase & 0xFF]
        return _exp(out + (env << 3))
    out = 0x1000 if phase & 0x100 else LOGSIN[phase & 0xFF]
    return _exp(out + (env << 3))


class Slot:
    __slots__ = ("ch", "mod_is_fb", "out", "prout", "fbmod", "eg_rout", "eg_out", "eg_gen",
                 "eg_ksl", "key", "pg_phase", "pg_phase_out", "pg_reset", "trem", "vib", "egt",
                 "ksr", "mult", "ksl", "tl", "ar", "dr", "sl", "rr", "wf")

    def __init__(self, ch):
        self.ch = ch
        self.out = self.prout = self.fbmod = 0
        self.eg_rout = 0x1FF
        self.eg_out = 0x1FF
        self.eg_gen = RELEASE
        self.eg_ksl = 0
        self.key = 0
        self.pg_phase = self.pg_phase_out = 0
        self.pg_reset = 0
        self.trem = self.vib = self.egt = self.ksr = 0
        self.mult = self.ksl = self.tl = self.ar = self.dr = self.sl = self.rr = self.wf = 0


class Channel:
    __slots__ = ("fnum", "block", "ksv", "fb", "con", "op1", "op2")

    def __init__(self):
        self.fnum = self.block = self.ksv = self.fb = self.con = 0


class Opl2:
    def __init__(self):
        self.chans = [Channel() for _ in range(9)]
        self.slots = []
        for c in range(9):
            pass
        # slot k (registro SLOT_OFFSETS[k]): canal (k // 6) * 3 + k % 3; los 3 primeros de
        # cada grupo de 6 son moduladores
        self.slot_by_off = {}
        for k, off in enumerate(SLOT_OFFSETS):
            ch = (k // 6) * 3 + k % 3
            s = Slot(ch)
            self.slots.append(s)
            self.slot_by_off[off] = s
            if k % 6 < 3:
                self.chans[ch].op1 = s
            else:
                self.chans[ch].op2 = s
        self.timer = 0
        self.eg_timer = 0
        self.eg_timerrem = 0
        self.eg_state = 0
        self.eg_add = 0
        self.tremolopos = 0
        self.tremolo = 0
        self.tremoloshift = 4
        self.vibpos = 0
        self.vibshift = 1
        self.nts = 0
        self.wse = 0
        self.keyed = set()                  # canales que han sonado (los demas, en silencio)

    # --- registros -----------------------------------------------------------------
    def _ksl(self, ch):
        c = self.chans[ch]
        ksl = (KSLROM[c.fnum >> 6] << 2) - ((8 - c.block) << 5)
        ksl = max(0, ksl)
        c.op1.eg_ksl = ksl
        c.op2.eg_ksl = ksl

    def write(self, reg, val):
        reg &= 0xFF
        val &= 0xFF
        hi = reg & 0xF0
        if reg == 0x01:
            self.wse = (val >> 5) & 1
        elif reg == 0x08:
            self.nts = (val >> 6) & 1
        elif reg == 0xBD:
            self.tremoloshift = 2 if val & 0x80 else 4
            self.vibshift = 0 if val & 0x40 else 1
        elif 0x20 <= reg <= 0x95 or 0xE0 <= reg <= 0xF5:
            s = self.slot_by_off.get(reg & 0x1F)
            if s is None:
                return
            base = reg & 0xE0
            if base == 0x20:
                s.trem = val >> 7
                s.vib = (val >> 6) & 1
                s.egt = (val >> 5) & 1
                s.ksr = (val >> 4) & 1
                s.mult = val & 0x0F
            elif base == 0x40:
                s.ksl = val >> 6
                s.tl = val & 0x3F
            elif base == 0x60:
                s.ar = val >> 4
                s.dr = val & 0x0F
            elif base == 0x80:
                s.sl = val >> 4
                if s.sl == 0x0F:
                    s.sl = 0x1F
                s.rr = val & 0x0F
            elif base == 0xE0:
                s.wf = (val & 3) if self.wse else 0
        elif 0xA0 <= reg <= 0xA8:
            c = self.chans[reg - 0xA0]
            c.fnum = (c.fnum & 0x300) | val
            self._upd(reg - 0xA0)
        elif 0xB0 <= reg <= 0xB8:
            ch = reg - 0xB0
            c = self.chans[ch]
            c.fnum = (c.fnum & 0xFF) | ((val & 3) << 8)
            c.block = (val >> 2) & 7
            self._upd(ch)
            key = (val >> 5) & 1
            for s in (c.op1, c.op2):
                s.key = key
            if key:
                self.keyed.add(ch)
        elif 0xC0 <= reg <= 0xC8:
            c = self.chans[reg - 0xC0]
            c.fb = (val >> 1) & 7
            c.con = val & 1

    def _upd(self, ch):
        c = self.chans[ch]
        c.ksv = (c.block << 1) | ((c.fnum >> (9 - self.nts)) & 1)
        self._ksl(ch)

    # --- un operador ---------------------------------------------------------------
    def _envelope(self, s):
        c = self.chans[s.ch]
        eg_out = s.eg_rout + (s.tl << 2) + (s.eg_ksl >> KSLSHIFT[s.ksl]) + (self.tremolo if s.trem else 0)
        s.eg_out = 0x1FF if eg_out > 0x1FF else eg_out
        reset = 0
        if s.key and s.eg_gen == RELEASE:
            reset = 1
            reg_rate = s.ar
        elif s.eg_gen == ATTACK:
            reg_rate = s.ar
        elif s.eg_gen == DECAY:
            reg_rate = s.dr
        elif s.eg_gen == SUSTAIN:
            reg_rate = 0 if s.egt else s.rr
        else:
            reg_rate = s.rr
        s.pg_reset = reset
        ks = c.ksv >> ((s.ksr ^ 1) << 1)
        rate = ks + (reg_rate << 2)
        rate_hi = rate >> 2
        rate_lo = rate & 3
        if rate_hi & 0x10:
            rate_hi = 0x0F
        eg_shift = rate_hi + self.eg_add
        shift = 0
        if reg_rate:
            if rate_hi < 12:
                if self.eg_state:
                    if eg_shift == 12:
                        shift = 1
                    elif eg_shift == 13:
                        shift = (rate_lo >> 1) & 1
                    elif eg_shift == 14:
                        shift = rate_lo & 1
            else:
                shift = (rate_hi & 3) + EG_INCSTEP[rate_lo][self.timer & 3]
                if shift & 4:
                    shift = 3
                if not shift:
                    shift = self.eg_state
        eg_rout = s.eg_rout
        eg_inc = 0
        eg_off = 0
        if reset and rate_hi == 0x0F:
            eg_rout = 0
        if (s.eg_rout & 0x1F8) == 0x1F8:
            eg_off = 1
        if s.eg_gen != ATTACK and not reset and eg_off:
            eg_rout = 0x1FF
        g = s.eg_gen
        if g == ATTACK:
            if not s.eg_rout:
                s.eg_gen = DECAY
            elif s.key and shift > 0 and rate_hi != 0x0F:
                eg_inc = (~s.eg_rout) >> (4 - shift)
        elif g == DECAY:
            if (s.eg_rout >> 4) == s.sl:
                s.eg_gen = SUSTAIN
            elif not eg_off and not reset and shift > 0:
                eg_inc = 1 << (shift - 1)
        else:
            if not eg_off and not reset and shift > 0:
                eg_inc = 1 << (shift - 1)
        s.eg_rout = (eg_rout + eg_inc) & 0x1FF
        if reset:
            s.eg_gen = ATTACK
        if not s.key:
            s.eg_gen = RELEASE

    def _phase(self, s):
        c = self.chans[s.ch]
        f = c.fnum
        if s.vib:
            rng = (f >> 7) & 7
            vp = self.vibpos
            if not vp & 3:
                rng = 0
            elif vp & 1:
                rng >>= 1
            rng >>= self.vibshift
            if vp & 4:
                rng = -rng
            f += rng
        basefreq = (f << c.block) >> 1
        phase = (s.pg_phase >> 9) & 0xFFFF
        if s.pg_reset:
            s.pg_phase = 0
        s.pg_phase = (s.pg_phase + ((basefreq * MULT[s.mult]) >> 1)) & 0xFFFFFFFF
        s.pg_phase_out = phase

    def generate(self, n):
        out = []
        chans = self.chans
        for _ in range(n):
            mix = 0
            for ch in self.keyed:
                c = chans[ch]
                m, k = c.op1, c.op2
                # modulador (con su realimentacion)
                m.fbmod = ((m.prout + m.out) >> (9 - c.fb)) if c.fb else 0
                m.prout = m.out
                self._envelope(m)
                self._phase(m)
                m.out = _wave(m.wf, m.pg_phase_out + m.fbmod, m.eg_out)
                # portador
                k.prout = k.out
                self._envelope(k)
                self._phase(k)
                k.out = _wave(k.wf, k.pg_phase_out + (0 if c.con else m.out), k.eg_out)
                mix += (m.out + k.out) if c.con else k.out
            out.append(max(-32768, min(32767, mix)))
            self._tick()
        return out

    def _tick(self):
        if (self.timer & 0x3F) == 0x3F:
            self.tremolopos = (self.tremolopos + 1) % 210
        if self.tremolopos < 105:
            self.tremolo = self.tremolopos >> self.tremoloshift
        else:
            self.tremolo = (210 - self.tremolopos) >> self.tremoloshift
        if (self.timer & 0x3FF) == 0x3FF:
            self.vibpos = (self.vibpos + 1) & 7
        self.timer = (self.timer + 1) & 0xFFFF
        self.eg_add = 0
        if self.eg_timer:
            shift = 0
            while shift < 36 and ((self.eg_timer >> shift) & 1) == 0:
                shift += 1
            self.eg_add = 0 if shift > 12 else shift + 1
        if self.eg_timerrem or self.eg_state:
            if self.eg_timer == 0xFFFFFFFFF:
                self.eg_timer = 0
                self.eg_timerrem = 1
            else:
                self.eg_timer += 1
                self.eg_timerrem = 0
        self.eg_state ^= 1

    def silent(self):
        """Todos los operadores que han sonado, ya callados."""
        return all(self.chans[ch].op1.eg_rout >= 0x1F8 and self.chans[ch].op2.eg_rout >= 0x1F8
                   for ch in self.keyed)
