"""El paquete para repartir: el motor, el conversor y su codigo, sin nada de ningun juego.

    python tools/paquete.py         -> build/dist/ScummNext-AAAAMMDD.zip

Antes, python tools/build.py y python tools/build_exe.py (el .exe lleva dentro el
scumm.nex de ese momento: tiene que ser el mismo). Dentro del ZIP, una carpeta
ScummNext/ con:

    LEEME.txt, AVISOS_TERCEROS.txt     de dist/ (con la version y lo que lleva el .exe)
    LICENCIA.txt                       la GPL v3
    ConversorScumm.exe, scumm.nex
    licencias/                         las de lo que PyInstaller mete en el .exe
    fuente/                            src/, tools/, dist/, README.md y LICENCIA.txt

Solo entran ficheros de los tipos de la lista: ni .DAT, ni .pkl, ni audio, ni
imagenes, ni nada de original/ o de las tarjetas de build/.
"""
import datetime
import glob
import importlib.metadata as md
import os
import re
import shutil
import sys
import textwrap
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DIST = os.path.join(ROOT, "build", "dist")
NOMBRE = "ScummNext"
EXE = os.path.join(ROOT, "build", "exe", "ConversorScumm.exe")
NEX = os.path.join(ROOT, "build", "scumm.nex")
WORK = os.path.join(ROOT, "build", "exe", "work", "ConversorScumm")
TIPOS = {".txt", ".md", ".html", ".terms", ".exe", ".nex", ".asm", ".py"}
# (lo que PyInstaller mete y no es de Python ni nuestro: paquete, licencias)
NOMBRES = {"numpy": "NumPy", "soundfile": "python-soundfile", "cffi": "cffi",
           "pycparser": "pycparser", "PyYAML": "PyYAML", "charset-normalizer": "charset-normalizer",
           "typing_extensions": "typing_extensions"}


def paquetes_del_exe():
    """Las distribuciones de pip que hay en el .exe (por sus modulos)."""
    sys.path.insert(0, os.path.join(ROOT, "build", "pylib"))
    toc = open(os.path.join(WORK, "PYZ-00.toc"), encoding="utf-8", errors="replace").read()
    tops = {m.split(".")[0] for m in re.findall(r"\('([A-Za-z0-9_\.]+)',", toc)}
    pd = md.packages_distributions()
    dists = set()
    for t in tops:
        if os.path.exists(os.path.join(HERE, t + ".py")):
            continue
        for d in pd.get(t, []):
            if d.lower() != "pyinstaller":
                dists.add(d)
    return sorted(dists, key=str.lower)


def licencias(dist):
    """Los ficheros de licencia de una distribucion instalada."""
    d = md.distribution(dist)
    out = []
    for f in d.files or []:
        s = str(f)
        if re.search(r"(LICEN[CS]E|COPYING|NOTICE|license_notes)", s, re.I) and not s.endswith((".py", ".pyc")):
            p = d.locate_file(f)
            if os.path.isfile(p):
                out.append((s, str(p)))
    return d, out


def copiar(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def texto(src, dst, **campos):
    s = open(src, encoding="utf-8").read()
    for k, v in campos.items():
        s = s.replace("{%s}" % k, v)
    if re.search(r"\{[A-Z]+\}", s):
        sys.exit("%s: queda un campo sin rellenar" % src)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(s)


def main():
    for p in (EXE, NEX):
        if not os.path.exists(p):
            sys.exit("falta %s: antes, python tools/build.py y python tools/build_exe.py" % p)
    if os.path.getmtime(EXE) < os.path.getmtime(NEX):
        sys.exit("el .exe es de antes que build/scumm.nex: python tools/build_exe.py")
    hoy = datetime.date.today()
    version = hoy.strftime("%d-%m-%Y")
    base = os.path.join(DIST, NOMBRE)
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)

    # licencias de lo que lleva el .exe
    lic = os.path.join(base, "licencias")
    py = sys.base_prefix
    copiar(os.path.join(py, "LICENSE.txt"), os.path.join(lic, "Python_LICENSE.txt"))
    copiar(os.path.join(py, "Doc", "html", "license.html"), os.path.join(lic, "Python_license.html"))
    copiar(os.path.join(py, "tcl", "tk8.6", "license.terms"), os.path.join(lic, "Tcl_Tk_license.terms"))
    filas = []
    for dist in paquetes_del_exe():
        d, fs = licencias(dist)
        if not fs:
            sys.exit("%s va en el .exe y no tiene licencia instalada" % dist)
        nombres = []
        for rel, src in fs:
            if "_soundfile_data" in rel:
                n = "libsndfile_COPYING.txt"
            elif "license_notes" in rel:
                n = "soundfile_license_notes.md"
            else:
                n = "%s_%s" % (d.metadata["Name"], rel.split("/licenses/")[-1].replace("/", "_")
                               if "/licenses/" in rel else os.path.basename(rel))
                if not os.path.splitext(n)[1]:
                    n += ".txt"
            copiar(src, os.path.join(lic, n))
            nombres.append(n)
        ln = d.metadata.get("License-Expression") or d.metadata.get("License") or ""
        ln = ln.splitlines()[0] if ln else "(ver el fichero)"
        nombres.sort(key=lambda n: (n.startswith(("libsndfile", "soundfile_license")), n))
        donde = "licencias/" + nombres[0] + (" y %d más" % (len(nombres) - 1) if len(nombres) > 1 else "")
        nombre = "%s %s" % (NOMBRES.get(dist, d.metadata["Name"]), d.version)
        filas.append("\n".join(textwrap.wrap(ln, 78, initial_indent="  %-30s" % nombre,
                                             subsequent_indent=" " * 32)) + "\n" + " " * 32 + donde)
    pyi, fs = licencias("pyinstaller")
    copiar(fs[0][1], os.path.join(lic, "PyInstaller_COPYING.txt"))

    # textos, licencia y programas
    texto(os.path.join(ROOT, "dist", "LEEME.txt"), os.path.join(base, "LEEME.txt"), VERSION=version)
    texto(os.path.join(ROOT, "dist", "AVISOS_TERCEROS.txt"), os.path.join(base, "AVISOS_TERCEROS.txt"),
          PYTHON="%-30s" % ("Python " + sys.version.split()[0]), PAQUETES="\n".join(filas))
    copiar(os.path.join(ROOT, "LICENCIA.txt"), os.path.join(base, "LICENCIA.txt"))
    copiar(EXE, os.path.join(base, "ConversorScumm.exe"))
    copiar(NEX, os.path.join(base, "scumm.nex"))

    # el codigo
    fu = os.path.join(base, "fuente")
    for pat in ("src/*.asm", "src/gen/*.asm", "tools/*.py", "dist/*.txt"):
        for f in sorted(glob.glob(os.path.join(ROOT, pat))):
            copiar(f, os.path.join(fu, os.path.relpath(f, ROOT)))
    copiar(os.path.join(ROOT, "README.md"), os.path.join(fu, "README.md"))
    copiar(os.path.join(ROOT, "LICENCIA.txt"), os.path.join(fu, "LICENCIA.txt"))

    # nada que no sea de los tipos de la lista
    malos = []
    total = 0
    for dp, _, fns in os.walk(base):
        for fn in fns:
            total += 1
            if os.path.splitext(fn)[1].lower() not in TIPOS:
                malos.append(os.path.relpath(os.path.join(dp, fn), base))
    if malos:
        sys.exit("no deberian ir: %s" % malos)

    zp = os.path.join(DIST, "%s-%s.zip" % (NOMBRE, hoy.strftime("%Y%m%d")))
    if os.path.exists(zp):
        os.remove(zp)
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for dp, _, fns in sorted(os.walk(base)):
            for fn in sorted(fns):
                p = os.path.join(dp, fn)
                z.write(p, os.path.relpath(p, DIST))
    print("ok: %s (%d ficheros, %.1f MB)" % (zp, total, os.path.getsize(zp) / 1e6))


if __name__ == "__main__":
    main()
