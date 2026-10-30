"""Decodificador de instrucciones de SCUMM v5.

Para cada codigo de operacion sabe que operandos lleva, sin ejecutar nada:
sirve para recorrer un script entero, comprobar que se decodifica justo
hasta su ultimo byte (tools/vm.py lo usa para ejecutar).

Operandos (los bits altos del codigo dicen si cada parametro es directo o
una variable):
- byte / word: valor directo, o una variable (palabra; si lleva el bit
  $2000, otra palabra de indice).
- var: un numero de variable (con indice si lleva el bit $2000).
- string: texto hasta el 0, con escapes $FF codigo (y dos bytes mas si el
  codigo no es 1, 2, 3 u 8).
"""
PARAM_1, PARAM_2, PARAM_3 = 0x80, 0x40, 0x20


class Bad(Exception):
    pass


class Reader:
    """Lee operandos de un script (bytes) desde pc."""

    def __init__(self, code, pc=0):
        self.code = code
        self.pc = pc

    def byte(self):
        if self.pc >= len(self.code):
            raise Bad("fin del script dentro de una instruccion")
        b = self.code[self.pc]
        self.pc += 1
        return b

    def word(self):
        lo = self.byte()
        return lo | self.byte() << 8

    def sword(self):
        w = self.word()
        return w - 0x10000 if w & 0x8000 else w

    def var(self):
        """Numero de variable: ('var', n, indice) con el indice si lleva $2000."""
        v = self.word()
        if v & 0x2000:
            idx = self.word()
            return ("var", v & ~0x2000, ("var", idx & ~0x2000, None) if idx & 0x2000 else idx & 0xFFF)
        return ("var", v, None)

    def p8(self, op, mask):
        return self.var() if op & mask else self.byte()

    def p16(self, op, mask):
        return self.var() if op & mask else self.sword()

    def vararg(self):
        out = []
        while True:
            b = self.byte()
            if b == 0xFF:
                return out
            out.append(self.p16(b, PARAM_1))

    def string(self):
        start = self.pc
        while True:
            c = self.byte()
            if c == 0:
                return self.code[start:self.pc - 1]
            if c == 0xFF:
                k = self.byte()
                if k not in (1, 2, 3, 8):
                    self.byte()
                    self.byte()

    def jump(self):
        off = self.sword()
        return self.pc + off


# ---------------------------------------------------------------------------
# Cada funcion lee los operandos de una instruccion y devuelve (nombre, args).
# args es una lista; los saltos van como ('jump', destino).
def _result(r):
    return ("res", r.var())


def op_stop(op, r):
    return "stopObjectCode", []


def op_putActor(op, r):
    return "putActor", [r.p8(op, PARAM_1), r.p16(op, PARAM_2), r.p16(op, PARAM_3)]


def op_byte1(name):
    def f(op, r):
        return name, [r.p8(op, PARAM_1)]
    f.opname = name
    return f


def op_word1(name):
    def f(op, r):
        return name, [r.p16(op, PARAM_1)]
    f.opname = name
    return f


def op_res_byte(name):
    def f(op, r):
        res = _result(r)
        return name, [res, r.p8(op, PARAM_1)]
    f.opname = name
    return f


def op_res_word(name):
    def f(op, r):
        res = _result(r)
        return name, [res, r.p16(op, PARAM_1)]
    f.opname = name
    return f


def op_res_word2(name):
    def f(op, r):
        res = _result(r)
        return name, [res, r.p16(op, PARAM_1), r.p16(op, PARAM_2)]
    f.opname = name
    return f


def op_res_byte2(name):
    def f(op, r):
        res = _result(r)
        return name, [res, r.p8(op, PARAM_1), r.p8(op, PARAM_2)]
    f.opname = name
    return f


def op_compare(name):
    def f(op, r):
        a = r.var()
        b = r.p16(op, PARAM_1)
        return name, [a, b, ("jump", r.jump())]
    f.opname = name
    return f


def op_drawObject(op, r):
    obj = r.p16(op, PARAM_1)
    sub = r.byte()
    args = [obj, ("sub", sub)]
    k = sub & 0x1F
    if k == 1:
        args += [r.p16(sub, PARAM_1), r.p16(sub, PARAM_2)]
    elif k == 2:
        args += [r.p16(sub, PARAM_1)]
    elif k != 0x1F:
        raise Bad("drawObject: subcodigo %d" % sub)
    return "drawObject", args


def op_setState(op, r):
    return "setState", [r.p16(op, PARAM_1), r.p8(op, PARAM_2)]


def op_faceActor(op, r):
    return "faceActor", [r.p8(op, PARAM_1), r.p16(op, PARAM_2)]


def op_startScript(op, r):
    s = r.p8(op, PARAM_1)
    return "startScript", [s, r.vararg(), ("flags", op & 0x60)]


def op_resourceRoutines(op, r):
    sub = r.byte()
    args = [("sub", sub)]
    if sub != 17:
        args.append(r.p8(sub, PARAM_1))
    k = sub & 0x3F
    if k == 20:
        args.append(r.p16(sub, PARAM_2))
    elif not (1 <= k <= 19):
        raise Bad("resourceRoutines: subcodigo %d" % sub)
    return "resourceRoutines", args


def op_walkActorToActor(op, r):
    return "walkActorToActor", [r.p8(op, PARAM_1), r.p8(op, PARAM_2), r.byte()]


def op_putActorAtObject(op, r):
    return "putActorAtObject", [r.p8(op, PARAM_1), r.p16(op, PARAM_2)]


def op_ifState(name):
    def f(op, r):
        a = r.p16(op, PARAM_1)
        b = r.p8(op, PARAM_2)
        return name, [a, b, ("jump", r.jump())]
    f.opname = name
    return f


def op_animateActor(op, r):
    return "animateActor", [r.p8(op, PARAM_1), r.p8(op, PARAM_2)]


ACTOR_SUBOPS = {
    0: "b", 1: "b", 2: "bb", 3: "b", 4: "b", 5: "bb", 6: "b", 7: "bbb", 8: "", 9: "w", 10: "",
    11: "bb", 12: "b", 13: "s", 14: "b", 16: "b", 17: "bb", 18: "", 19: "b", 20: "", 21: "",
    22: "b", 23: "b",
}


def params(r, sub, fmt):
    out = []
    masks = (PARAM_1, PARAM_2, PARAM_3)
    i = 0
    for c in fmt:
        if c == "b":
            out.append(r.p8(sub, masks[i]))
            i += 1
        elif c == "w":
            out.append(r.p16(sub, masks[i]))
            i += 1
        elif c == "s":
            out.append(("str", r.string()))
        elif c == "B":                      # byte directo
            out.append(r.byte())
        elif c == "W":
            out.append(r.sword())
        elif c == "v":                      # lista variable
            out.append(r.vararg())
        elif c == "n":                      # siguiente subcodigo (cambia las mascaras)
            sub = r.byte()
            out.append(("sub", sub))
            i = 0
    return out


def op_actorOps(op, r):
    act = r.p8(op, PARAM_1)
    args = [act]
    while True:
        sub = r.byte()
        if sub == 0xFF:
            return "actorOps", args
        k = sub & 0x1F
        if k not in ACTOR_SUBOPS:
            raise Bad("actorOps: subcodigo %d" % sub)
        args.append((k, params(r, sub, ACTOR_SUBOPS[k])))


def parse_string_ops(r):
    """decodeParseString: hasta $FF, o hasta el texto (que termina la lista)."""
    out = []
    while True:
        sub = r.byte()
        if sub == 0xFF:
            return out
        k = sub & 0xF
        if k == 0:
            out.append(("at", r.p16(sub, PARAM_1), r.p16(sub, PARAM_2)))
        elif k == 1:
            out.append(("color", r.p8(sub, PARAM_1)))
        elif k == 2:
            out.append(("clipped", r.p16(sub, PARAM_1)))
        elif k == 3:
            out.append(("erase", r.p16(sub, PARAM_1), r.p16(sub, PARAM_2)))
        elif k in (4, 6, 7):
            out.append(("flag", k))
        elif k == 8:
            out.append(("voice", r.p16(sub, PARAM_1), r.p16(sub, PARAM_2)))
        elif k == 15:
            out.append(("text", r.string()))
            return out
        else:
            raise Bad("print: subcodigo %d" % sub)


def op_print(op, r):
    act = r.p8(op, PARAM_1)
    return "print", [act, parse_string_ops(r)]


def op_printEgo(op, r):
    return "printEgo", [parse_string_ops(r)]


def op_arith(name):
    def f(op, r):
        res = _result(r)
        return name, [res, r.p16(op, PARAM_1)]
    f.opname = name
    return f


def op_jump(op, r):
    return "jumpRelative", [("jump", r.jump())]


def op_doSentence(op, r):
    verb = r.p8(op, PARAM_1)
    if verb == 0xFE:
        return "doSentence", [verb]
    return "doSentence", [verb, r.p16(op, PARAM_2), r.p16(op, PARAM_3)]


def op_ifClassOfIs(op, r):
    obj = r.p16(op, PARAM_1)
    cls = []
    while True:
        b = r.byte()
        if b == 0xFF:
            break
        cls.append(r.p16(b, PARAM_1))
    return "ifClassOfIs", [obj, cls, ("jump", r.jump())]


def op_walkActorTo(op, r):
    return "walkActorTo", [r.p8(op, PARAM_1), r.p16(op, PARAM_2), r.p16(op, PARAM_3)]


def op_isActorInBox(op, r):
    a = r.p8(op, PARAM_1)
    b = r.p8(op, PARAM_2)
    return "isActorInBox", [a, b, ("jump", r.jump())]


def op_none(name):
    def f(op, r):
        return name, []
    f.opname = name
    return f


def op_loadRoomWithEgo(op, r):
    return "loadRoomWithEgo", [r.p16(op, PARAM_1), r.p8(op, PARAM_2), r.sword(), r.sword()]


def op_pickupObject(op, r):
    return "pickupObject", [r.p16(op, PARAM_1), r.p8(op, PARAM_2)]


def op_setVarRange(op, r):
    res = _result(r)
    n = r.byte()
    vals = [r.sword() if op & 0x80 else r.byte() for _ in range(n or 256)]
    return "setVarRange", [res, vals]


def op_stringOps(op, r):
    sub = r.byte()
    k = sub & 0x1F
    if k == 1:
        return "stringOps", [("sub", 1), r.p8(sub, PARAM_1), ("str", r.string())]
    if k in (2, 5):
        return "stringOps", [("sub", k), r.p8(sub, PARAM_1), r.p8(sub, PARAM_2)]
    if k == 3:
        return "stringOps", [("sub", k), r.p8(sub, PARAM_1), r.p8(sub, PARAM_2), r.p8(sub, PARAM_3)]
    if k == 4:
        res = _result(r)
        return "stringOps", [("sub", k), res, r.p8(sub, PARAM_1), r.p8(sub, PARAM_2)]
    raise Bad("stringOps: subcodigo %d" % sub)


def op_equalZero(name):
    def f(op, r):
        a = r.var()
        return name, [a, ("jump", r.jump())]
    f.opname = name
    return f


def op_setOwnerOf(op, r):
    return "setOwnerOf", [r.p16(op, PARAM_1), r.p8(op, PARAM_2)]


def op_delayVariable(op, r):
    return "delayVariable", [r.var()]


CURSOR_SUBOPS = {1: "", 2: "", 3: "", 4: "", 5: "", 6: "", 7: "", 8: "", 10: "bb", 11: "bbb",
                 12: "b", 13: "b", 14: "v"}


def op_cursorCommand(op, r):
    sub = r.byte()
    k = sub & 0x1F
    if k not in CURSOR_SUBOPS:
        raise Bad("cursorCommand: subcodigo %d" % sub)
    return "cursorCommand", [("sub", k)] + params(r, sub, CURSOR_SUBOPS[k])


def op_putActorInRoom(op, r):
    return "putActorInRoom", [r.p8(op, PARAM_1), r.p8(op, PARAM_2)]


def op_delay(op, r):
    d = r.byte() | r.byte() << 8 | r.byte() << 16
    return "delay", [d]


MATRIX_SUBOPS = {1: "bb", 2: "bb", 3: "bb", 4: ""}


def op_matrixOps(op, r):
    sub = r.byte()
    k = sub & 0x1F
    if k not in MATRIX_SUBOPS:
        raise Bad("matrixOps: subcodigo %d" % sub)
    return "matrixOps", [("sub", k)] + params(r, sub, MATRIX_SUBOPS[k])


ROOM_SUBOPS = {1: "ww", 3: "ww", 4: "wwwnb", 5: "", 6: "", 7: "bbbnbb", 8: "bbb", 9: "bb",
               10: "w", 11: "wwwnbb", 12: "wwwnbb", 13: "bs", 14: "bs", 15: "bnbbnb", 16: "bb"}


def op_roomOps(op, r):
    sub = r.byte()
    k = sub & 0x1F
    if k not in ROOM_SUBOPS:
        raise Bad("roomOps: subcodigo %d" % sub)
    return "roomOps", [("sub", k)] + params(r, sub, ROOM_SUBOPS[k])


def op_walkActorToObject(op, r):
    return "walkActorToObject", [r.p8(op, PARAM_1), r.p16(op, PARAM_2)]


def op_startObject(op, r):
    obj = r.p16(op, PARAM_1)
    s = r.p8(op, PARAM_2)
    return "startObject", [obj, s, r.vararg()]


def op_drawBox(op, r):
    x = r.p16(op, PARAM_1)
    y = r.p16(op, PARAM_2)
    sub = r.byte()
    return "drawBox", [x, y, r.p16(sub, PARAM_1), r.p16(sub, PARAM_2), r.p8(sub, PARAM_3)]


def op_cutscene(op, r):
    return "cutscene", [r.vararg()]


def op_chainScript(op, r):
    s = r.p8(op, PARAM_1)
    return "chainScript", [s, r.vararg()]


def op_incdec(name):
    def f(op, r):
        return name, [_result(r)]
    f.opname = name
    return f


def op_soundKludge(op, r):
    return "soundKludge", [r.vararg()]


def op_override(op, r):
    b = r.byte()
    if b:
        # beginOverride se salta el salto que sigue (lo usa el que interrumpe)
        j = r.byte()
        if j != 0x18:
            raise Bad("override sin salto detras")
        return "beginOverride", [("jump", r.jump())]
    return "endOverride", []


def op_oldRoomEffect(op, r):
    sub = r.byte()
    if (sub & 0x1F) == 3:
        return "oldRoomEffect", [("sub", 3), r.p16(sub, PARAM_1)]
    return "oldRoomEffect", [("sub", sub & 0x1F)]


def op_setClass(op, r):
    obj = r.p16(op, PARAM_1)
    cls = []
    while True:
        b = r.byte()
        if b == 0xFF:
            return "setClass", [obj, cls]
        cls.append(r.p16(b, PARAM_1))


def op_setObjectName(op, r):
    return "setObjectName", [r.p16(op, PARAM_1), ("str", r.string())]


def op_lights(op, r):
    return "lights", [r.p8(op, PARAM_1), r.byte(), r.byte()]


VERB_SUBOPS = {1: "w", 2: "s", 3: "b", 4: "b", 5: "ww", 6: "", 7: "", 8: "", 9: "", 16: "b",
               17: "", 18: "b", 19: "", 20: "w", 22: "wb", 23: "b"}


def op_verbOps(op, r):
    verb = r.p8(op, PARAM_1)
    args = [verb]
    while True:
        sub = r.byte()
        if sub == 0xFF:
            return "verbOps", args
        k = sub & 0x1F
        if k not in VERB_SUBOPS:
            raise Bad("verbOps: subcodigo %d" % sub)
        args.append((k, params(r, sub, VERB_SUBOPS[k])))


def op_systemOps(op, r):
    return "systemOps", [r.byte()]


def op_saveRestoreVerbs(op, r):
    sub = r.byte()
    return "saveRestoreVerbs", [("sub", sub & 0x1F), r.p8(sub, PARAM_1), r.p8(sub, PARAM_2),
                                r.p8(sub, PARAM_3)]


def op_expression(op, r):
    res = _result(r)
    items = []
    while True:
        sub = r.byte()
        if sub == 0xFF:
            return "expression", [res, items]
        k = sub & 0x1F
        if k == 1:
            items.append(("push", r.p16(sub, PARAM_1)))
        elif k in (2, 3, 4, 5):
            items.append(("op", k))
        elif k == 6:
            inner = r.byte()
            items.append(("opcode", decode_at(r, inner)))
        else:
            raise Bad("expression: subcodigo %d" % sub)


def op_wait(op, r):
    sub = r.byte()
    k = sub & 0x1F
    if k == 1:
        return "wait", [("sub", 1), r.p8(sub, PARAM_1)]
    if k in (2, 3, 4):
        return "wait", [("sub", k)]
    raise Bad("wait: subcodigo %d" % sub)


def op_pseudoRoom(op, r):
    i = r.byte()
    lst = []
    while True:
        j = r.byte()
        if j == 0:
            return "pseudoRoom", [i, lst]
        lst.append(j)


def op_dummy(op, r):
    return "dummy", []


def op_getStringWidth(op, r):
    res = _result(r)
    return "getStringWidth", [res, r.p8(op, PARAM_1)]


def op_pickupObjectOld(op, r):
    return "pickupObjectOld", [r.p16(op, PARAM_1)]


def op_actorFollowCamera(op, r):
    return "actorFollowCamera", [r.p8(op, PARAM_1)]


def op_debug(op, r):
    return "debug", [r.p16(op, PARAM_1)]


def op_stopObjectScript(op, r):
    return "stopObjectScript", [r.p16(op, PARAM_1)]


def op_freeze(op, r):
    return "freezeScripts", [r.p8(op, PARAM_1)]


def op_stopScript(op, r):
    return "stopScript", [r.p8(op, PARAM_1)]


def op_loadRoom(op, r):
    return "loadRoom", [r.p8(op, PARAM_1)]


# --- tabla: el mismo manejador para los codigos que solo cambian los bits de parametro
TABLE = [None] * 256


def setop(codes, f):
    for c in codes:
        TABLE[c] = f


def fam(base, nbits=3):
    """base con todas las combinaciones de los bits de parametro altos."""
    out = set()
    bits = [0x80, 0x40, 0x20][:nbits]
    for m in range(1 << nbits):
        c = base
        for i, b in enumerate(bits):
            if m >> i & 1:
                c |= b
        out.add(c)
    return sorted(out)


setop([0x00, 0xA0], op_stop)
setop(fam(0x01), op_putActor)
setop([0x02, 0x82], op_byte1("startMusic"))
setop([0x03, 0x83], op_res_byte("getActorRoom"))
setop([0x04, 0x84], op_compare("isGreaterEqual"))
setop([0x05, 0x85], op_drawObject)
setop([0x06, 0x86], op_res_byte("getActorElevation"))
setop(fam(0x07, 2), op_setState)
setop([0x08, 0x88], op_compare("isNotEqual"))
setop(fam(0x09, 2), op_faceActor)
setop(fam(0x0A), op_startScript)
setop(fam(0x0B, 2), op_res_word2("getVerbEntrypoint"))
setop([0x0C, 0x8C], op_resourceRoutines)
setop(fam(0x0D, 2), op_walkActorToActor)
setop(fam(0x0E, 2), op_putActorAtObject)
setop([0x0F, 0x8F], op_res_word("getObjectState"))
setop([0x10, 0x90], op_res_word("getObjectOwner"))
setop(fam(0x11, 2), op_animateActor)
setop([0x12, 0x92], op_word1("panCameraTo"))
setop([0x13, 0x53, 0x93, 0xD3], op_actorOps)
setop([0x14, 0x94], op_print)
setop(fam(0x15, 2), op_res_word2("actorFromPos"))
setop([0x16, 0x96], op_res_byte("getRandomNr"))
setop([0x17, 0x97], op_arith("and"))
setop([0x18], op_jump)
setop(fam(0x19), op_doSentence)
setop([0x1A, 0x9A], op_arith("move"))
setop([0x1B, 0x9B], op_arith("multiply"))
setop([0x1C, 0x9C], op_byte1("startSound"))
setop([0x1D, 0x9D], op_ifClassOfIs)
setop(fam(0x1E), op_walkActorTo)
setop(fam(0x1F, 2), op_isActorInBox)
setop([0x20], op_none("stopMusic"))
setop([0x22, 0xA2], op_res_byte("getAnimCounter"))
setop([0x23, 0xA3], op_res_word("getActorY"))
setop(fam(0x24, 2), op_loadRoomWithEgo)
setop(fam(0x25, 2), op_pickupObject)
setop([0x26, 0xA6], op_setVarRange)
setop([0x27], op_stringOps)
setop([0x28], op_equalZero("equalZero"))
setop(fam(0x29, 2), op_setOwnerOf)
setop([0x2B], op_delayVariable)
setop([0x2C], op_cursorCommand)
setop(fam(0x2D, 2), op_putActorInRoom)
setop([0x2E], op_delay)
setop(fam(0x2F, 2), op_ifState("ifNotState"))
setop([0x30, 0xB0], op_matrixOps)
setop([0x31, 0xB1], op_res_byte("getInventoryCount"))
setop([0x32, 0xB2], op_word1("setCameraAt"))
setop([0x33, 0x73, 0xB3, 0xF3], op_roomOps)
setop(fam(0x34, 2), op_res_word2("getDist"))
setop(fam(0x35, 2), op_res_word2("findObject"))
setop(fam(0x36, 2), op_walkActorToObject)
setop(fam(0x37, 2), op_startObject)
setop([0x38, 0xB8], op_compare("isLessEqual"))
setop([0x3A, 0xBA], op_arith("subtract"))
setop([0x3B, 0xBB], op_res_byte("getActorScale"))
setop([0x3C, 0xBC], op_byte1("stopSound"))
setop(fam(0x3D, 2), op_res_byte2("findInventory"))
setop(fam(0x3F), op_drawBox)
setop([0x40], op_cutscene)
setop([0x42, 0xC2], op_chainScript)
setop([0x43, 0xC3], op_res_word("getActorX"))
setop([0x44, 0xC4], op_compare("isLess"))
setop([0x46], op_incdec("increment"))
setop([0x48, 0xC8], op_compare("isEqual"))
setop([0x4C], op_soundKludge)
setop(fam(0x4F, 2), op_ifState("ifState"))
setop([0x50, 0xD0], op_pickupObjectOld)
setop([0x52, 0xD2], op_actorFollowCamera)
setop([0x54, 0xD4], op_setObjectName)
setop([0x56, 0xD6], op_res_byte("getActorMoving"))
setop([0x57, 0xD7], op_arith("or"))
setop([0x58], op_override)
setop([0x5A, 0xDA], op_arith("add"))
setop([0x5B, 0xDB], op_arith("divide"))
setop([0x5C, 0xDC], op_oldRoomEffect)
setop([0x5D, 0xDD], op_setClass)
setop([0x60, 0xE0], op_freeze)
setop([0x62, 0xE2], op_stopScript)
setop([0x63, 0xE3], op_res_byte("getActorFacing"))
setop([0x66, 0xE6], op_res_word("getClosestObjActor"))
setop([0x67, 0xE7], op_getStringWidth)
setop([0x68, 0xE8], op_res_byte("isScriptRunning"))
setop([0x6B, 0xEB], op_debug)
setop([0x6C, 0xEC], op_res_byte("getActorWidth"))
setop([0x6E, 0xEE], op_stopObjectScript)
setop([0x70, 0xF0], op_lights)
setop([0x71, 0xF1], op_res_byte("getActorCostume"))
setop([0x72, 0xF2], op_loadRoom)
setop([0x78, 0xF8], op_compare("isGreater"))
setop([0x7A, 0xFA], op_verbOps)
setop([0x7B, 0xFB], op_res_byte("getActorWalkBox"))
setop([0x7C, 0xFC], op_res_byte("isSoundRunning"))
setop([0x80], op_none("breakHere"))
setop([0x98], op_systemOps)
setop([0xA7], op_dummy)
setop([0xA8], op_equalZero("notEqualZero"))
setop([0xAB], op_saveRestoreVerbs)
setop([0xAC], op_expression)
setop([0xAE], op_wait)
setop([0xC0], op_none("endCutscene"))
setop([0xC6], op_incdec("decrement"))
setop([0xCC], op_pseudoRoom)
setop([0xD8], op_printEgo)


def decode_at(r, op):
    f = TABLE[op]
    if f is None:
        raise Bad("codigo $%02X desconocido" % op)
    name, args = f(op, r)
    return name, args


def decode(code, pc):
    """(nombre, args, siguiente pc)."""
    r = Reader(code, pc)
    op = r.byte()
    name, args = decode_at(r, op)
    return op, name, args, r.pc


def jumps(args):
    out = []
    for a in args:
        if isinstance(a, tuple) and a and a[0] == "jump":
            out.append(a[1])
        elif isinstance(a, tuple) and a and a[0] == "opcode":
            out += jumps(a[1][1])
        elif isinstance(a, list):
            out += jumps(a)
    return out


def check(code, start=0):
    """Recorre el script: devuelve (instrucciones, nombres usados) o lanza Bad."""
    pc = start
    starts = set()
    targets = []
    names = []
    while pc < len(code):
        starts.add(pc)
        op, name, args, nxt = decode(code, pc)
        names.append(name)
        targets += jumps(args)
        pc = nxt
    if pc != len(code):
        raise Bad("se pasa del final")
    starts.add(len(code))
    for t in targets:
        if t not in starts:
            raise Bad("salto a %d, que no es el principio de una instruccion" % t)
    return len(names), names


PLAIN = {"stop": "stopObjectCode", "jump": "jumpRelative", "freeze": "freezeScripts"}


def name_of(op):
    """Nombre de la instruccion del codigo op (None si no existe)."""
    f = TABLE[op]
    if f is None:
        return None
    if hasattr(f, "opname"):
        return f.opname
    k = f.__name__[3:]
    return PLAIN.get(k, k)
