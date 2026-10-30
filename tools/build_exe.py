"""El conversor con ventana (tools/gui.py) en un solo .exe de Windows, con el motor
(build/scumm.nex, el de la ultima vez que se hizo tools/build.py) dentro:

    python tools/build_exe.py           -> build/exe/ConversorScumm.exe

Hace falta PyInstaller (pip install pyinstaller); soundfile (para la musica en FLAC)
sale de build/pylib, como en el resto de herramientas. El .exe no lleva nada de
ningun juego: los datos los saca cada uno de su original.
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "build", "exe")
NOMBRE = "ConversorScumm"


def main():
    nex = os.path.join(ROOT, "build", "scumm.nex")
    if not os.path.exists(nex):
        sys.exit("falta build/scumm.nex: antes, python tools/build.py")
    work = os.path.join(OUT, "work")
    shutil.rmtree(work, ignore_errors=True)
    args = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onefile", "--windowed",
            "--name", NOMBRE, "--distpath", OUT, "--workpath", work, "--specpath", work,
            "--paths", HERE, "--paths", os.path.join(ROOT, "build", "pylib"),
            "--add-data", nex + os.pathsep + ".",
            "--hidden-import", "soundfile",
            "--exclude-module", "PIL", "--exclude-module", "matplotlib",
            os.path.join(HERE, "gui.py")]
    r = subprocess.run(args)
    if r.returncode:
        sys.exit(r.returncode)
    exe = os.path.join(OUT, NOMBRE + ".exe")
    print("ok: %s %.1f MB" % (exe, os.path.getsize(exe) / 1e6))


if __name__ == "__main__":
    main()
