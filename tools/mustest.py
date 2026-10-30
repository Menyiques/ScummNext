"""La musica mientras se cargan habitaciones, en CSpect (ZEsarUX no emula las
interrupciones del CTC). Ensambla build/mustest.nex con -DMTBUILD (src/mustest.asm)
y lo abre con el juego de prueba (build/prueba_sd) como SD; mira el color con el
que se queda la pantalla.

    python tools/mustest.py        # verde: la musica sono en todas las imagenes (cargando
                                   # habitaciones y rehaciendo todas las tiras)
    python tools/mustest.py di     # las tiras sin interrupciones, como antes: rojo
    python tools/mustest.py sfx    # y ademas un efecto cada 16 imagenes (el 4 dura 50:
                                   # suenan los dos canales, CTC 0 y CTC 2): verde;
                                   # magenta si un canal no saco ninguna muestra
"""
import os
import subprocess
import sys
import time

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import build  # noqa: E402
import run  # noqa: E402

COLORS = {"verde": lambda c: c[1] > 200 and c[0] < 80 and c[2] < 80,
          "rojo": lambda c: c[0] > 200 and c[1] < 80 and c[2] < 80,
          "amarillo": lambda c: c[0] > 200 and c[1] > 200 and c[2] < 80,
          "magenta": lambda c: c[0] > 150 and c[1] < 80 and c[2] > 150}


def main():
    defs = ["-DMTBUILD"] + (["-DMTDI"] if "di" in sys.argv[1:] else []) + \
        (["-DMTSFX"] if "sfx" in sys.argv[1:] else [])
    r = subprocess.run([build.SJASMPLUS, "--zxnext", "--nologo", "--msg=war"] + defs +
                       ["--sym=../build/mustest.sym", "scumm.asm"],
                       cwd=os.path.join(ROOT, "src"), capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    sd = os.path.join(ROOT, "build", "prueba_sd")
    nex = os.path.join(ROOT, "build", "mustest.nex")
    p = subprocess.Popen([run.CSPECT, "-w2", "-zxnext", "-s28", "-nodelay", "-mmc=" + sd + os.sep, nex],
                         cwd=os.path.dirname(run.CSPECT), stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    out = os.path.join(ROOT, "build", "_mustest.png")
    res = None
    try:
        for _ in range(90):
            time.sleep(1)
            subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File",
                            os.path.join(HERE, "wincap.ps1"), "-ProcessId", str(p.pid), "-Out", out],
                           capture_output=True)
            try:
                c = Image.open(out).convert("RGB").getpixel((20, 20))
            except (OSError, IndexError):
                continue
            res = next((k for k, f in COLORS.items() if f(c)), None)
            if res:
                break
    finally:
        p.kill()
    print("musica al cargar habitaciones y rehacer tiras:", res or "sin resultado")
    return res == ("rojo" if "-DMTDI" in defs else "verde")


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
