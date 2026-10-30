"""Arranca el motor en un emulador con ventana, con build/sd como tarjeta SD.

    python tools/run.py                    # CSpect con build/sd (tu juego)
    python tools/run.py zesarux            # ZEsarUX
    python tools/run.py cspect prueba      # el juego de prueba (build/prueba_sd)

En la carpeta tienen que estar scumm.nex y los .DAT (tools/convert.py con tu
juego, o python tools/build.py prueba). Las rutas se pueden cambiar con las
variables de entorno CSPECT y ZESARUX.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SD = os.path.join(ROOT, "build", "sd")
NEX = os.path.join(SD, "scumm.nex")
CSPECT = os.environ.get("CSPECT", r"C:\Users\User\ZX\CSpect\CSpect.exe")
ZESARUX = os.environ.get(
    "ZESARUX", r"C:\Users\User\ZX\ZEsarUX_windows-13.0\zesarux.exe")


def args_for(emu, window=3, sd=SD):
    nex = os.path.join(sd, "scumm.nex")
    if emu == "cspect":
        return [CSPECT, "-w%d" % window, "-zxnext", "-s28", "-nodelay",
                "-mmc=" + sd + os.sep, nex]
    if emu == "zesarux":
        # al cargar un .nex, ZEsarUX usa su carpeta como tarjeta SD
        return [ZESARUX, "--noconfigfile", "--machine", "TBBlue", "--tbblue-fast-boot-mode",
                "--allowturbotbbluerom", "--realvideo", "--zoom", "2", "--nowelcomemessage",
                "--enablekempstonmouse", nex]
    sys.exit(__doc__)


def main():
    emu = sys.argv[1] if len(sys.argv) > 1 else "cspect"
    sd = SD
    if len(sys.argv) > 2:
        sd = os.path.join(ROOT, "build", "prueba_sd") if sys.argv[2] == "prueba" else os.path.abspath(sys.argv[2])
    for f in ("scumm.nex", "GAME.DAT"):
        if not os.path.exists(os.path.join(sd, f)):
            sys.exit("falta %s: python tools/build.py y tools/convert.py (o build.py prueba)"
                     % os.path.join(sd, f))
    a = args_for(emu, sd=sd)
    subprocess.Popen(a, cwd=os.path.dirname(a[0]))


if __name__ == "__main__":
    main()
