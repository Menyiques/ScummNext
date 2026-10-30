"""Construye build/scumm.nex (el motor; los datos del juego van aparte).

    python tools/build.py           # motor, copiado a build/sd y build/prueba_sd
    python tools/build.py prueba    # ademas, el juego de prueba convertido en build/prueba_sd

Cada carpeta hace de tarjeta SD: el .nex y los .DAT juntos. build/sd es para
tu juego (python tools/convert.py CARPETA_DEL_CD MONKEY build/sd) y
build/prueba_sd para el juego de prueba que usan las pruebas.
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SD = os.path.join(ROOT, "build", "sd")
SD_PRUEBA = os.path.join(ROOT, "build", "prueba_sd")
SJASMPLUS = os.environ.get(
    "SJASMPLUS", r"C:\Users\User\ZX\sjasmplus-1.20.3.win\sjasmplus.exe")


def cursor_asm():
    """Punto de mira de 16x16 y 4 bits: 1 negro, 2 blanco, 3 amarillo."""
    px = [[0] * 16 for _ in range(16)]
    for i in list(range(1, 6)) + list(range(9, 14)):
        for d in (-1, 1):
            px[i][7 + d] = px[i][7 + d] or 1
            px[7 + d][i] = px[7 + d][i] or 1
    for i in list(range(1, 6)) + list(range(9, 14)):
        px[i][7] = 2
        px[7][i] = 2
    for i in (0, 6, 8, 14):
        px[i][7] = 1
        px[7][i] = 1
    px[7][7] = 3
    lines = ["; generado por tools/build.py", "CURSOR:"]
    for row in px:
        b = [row[2 * i] << 4 | row[2 * i + 1] for i in range(8)]
        lines.append("        db " + ",".join("$%02X" % v for v in b))
    pal = [(0, 0, 0), (0, 0, 0), (255, 255, 255), (255, 220, 0)] + [(0, 0, 0)] * 4
    lines.append("CURPAL:")
    for r, g, b in pal:
        r3, g3, b3 = (r * 7 + 127) // 255, (g * 7 + 127) // 255, (b * 7 + 127) // 255
        lines.append("        db $%02X,$%02X" % (r3 << 5 | g3 << 2 | b3 >> 1, b3 & 1))
    return "\n".join(lines) + "\n"


def vm_tables():
    """La tabla de despacho del Z80 y los formatos de los subcodigos, sacados
    de tools/opcodes.py (asi el Z80 decodifica igual que el modelo)."""
    sys.path.insert(0, HERE)
    import opcodes as O
    lines = ["; generado por tools/build.py desde tools/opcodes.py", "VMTAB:"]
    for op in range(256):
        name = O.name_of(op)
        lines.append("        dw %s" % ("H_" + name if name else "H_bad"))

    def table(label, subops, n):
        out = ["%s:" % label]
        strs = []
        for k in range(n):
            fmt = subops.get(k)
            if fmt:
                out.append("        dw %s_%d" % (label, k))
                strs.append('%s_%d: db "%s",0' % (label, k, fmt))
            else:
                out.append("        dw 0")
        return out + strs

    print_fmt = {0: "ww", 1: "b", 2: "w", 3: "ww", 8: "ww"}
    str_fmt = {1: "bs", 2: "bb", 3: "bbb", 5: "bb"}
    lines += table("ACTFMT", O.ACTOR_SUBOPS, 32)
    lines += table("ROOMFMT", O.ROOM_SUBOPS, 32)
    lines += table("CURFMT", O.CURSOR_SUBOPS, 32)
    lines += table("VERBFMT", O.VERB_SUBOPS, 32)
    lines += table("MATFMT", O.MATRIX_SUBOPS, 32)
    lines += table("PRFMT", print_fmt, 16)
    lines += table("STRFMT", str_fmt, 32)
    return "\n".join(lines) + "\n"


def main():
    gen = os.path.join(ROOT, "src", "gen")
    os.makedirs(gen, exist_ok=True)
    with open(os.path.join(gen, "cursor.asm"), "w") as f:
        f.write(cursor_asm())
    with open(os.path.join(gen, "vmtab.asm"), "w") as f:
        f.write(vm_tables())
    sys.path.insert(0, HERE)
    import menufont
    with open(os.path.join(gen, "font.asm"), "w", encoding="latin-1") as f:
        f.write(menufont.font_asm())
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    r = subprocess.run([SJASMPLUS, "--zxnext", "--nologo", "--msg=war",
                        "--lst=../build/scumm.lst", "--sym=../build/scumm.sym", "scumm.asm"],
                       cwd=os.path.join(ROOT, "src"))
    if r.returncode:
        sys.exit("sjasmplus ha fallado")
    nex = os.path.join(ROOT, "build", "scumm.nex")
    for d in (SD, SD_PRUEBA):
        os.makedirs(d, exist_ok=True)
        shutil.copy(nex, d)
    print("ok:", nex, os.path.getsize(nex), "bytes")
    if len(sys.argv) > 1 and sys.argv[1] == "prueba":
        sys.path.insert(0, HERE)
        import convert
        import fixture
        fixture.build(os.path.join(ROOT, "build", "prueba"))
        convert.convert(os.path.join(ROOT, "build", "prueba"), "PRUEBA", SD_PRUEBA)


if __name__ == "__main__":
    main()
