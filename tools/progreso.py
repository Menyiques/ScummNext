"""PROGRESO.DAT: para que el menu de partidas diga por donde va cada una (un % hasta
los creditos), sacado de una partida grabada entera (tools/partida.py).

    python tools/progreso.py PARTIDA CARPETA     # p.ej. zx_creditos build/sd

Se juega la partida en el modelo desde el arranque y se miran las variables cada
100 pasos. El 100 % es donde empiezan los creditos del final (la ultima vez que
se queda sin habitacion), no donde acaban. Cuentan los bits que, una vez puestos, ya no se quitan hasta el final,
y las variables que solo suben y toman pocos valores (cada valor nuevo cuenta
uno, como "variable >= valor"); en cada % de la partida (0..100) se apunta
cuantas cosas de esas hay. El Z80 cuenta las que tiene una partida y busca el
primer % en el que la grabada ya tenia otras tantas. Solo son numeros de
variables y cuentas, pero salen de tu juego: el fichero se queda en tu tarjeta.

Formato (siempre del mismo tamano): "PG", 2; 256 bytes de mascara (los bits que
cuentan, como BITS en VMDATA); n y 64 pares (variable, valor) de 16 bits (LE, el
valor con signo; solo valen los n primeros); 101 cuentas de 16 bits, la de cada %.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

NBYTES = 256            # BITS
NVARS = 800             # VARS (2 * NVARS bytes, delante de BITS en VMDATA)
NV = 64                 # pares (variable, valor) como mucho
CADA = 100
MAXVAL = 12             # una variable cuenta si toma como mucho tantos valores
PRIMERAS = 100          # (las de antes son del motor: camara, tiempos, raton...)


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def muestras(nombre, game_dir, sd):
    """(pasos hasta los creditos, [(paso, bits, vars)]) de la partida grabada NOMBRE
    desde el arranque, hasta donde empiezan los creditos del final."""
    import convert as C
    import nexttest as NT
    import partida as PA
    j = PA.cargar(nombre)
    g, _ = C.find_game(game_dir)
    hdr = open(os.path.join(sd, "GAME.DAT"), "rb").read()
    w = NT.boot_world(g, g.costume(hdr[5]))
    jw = PA.Jugador(w)

    def ahora(t):
        return (t, bytes(w.vm.bits[:NBYTES]).ljust(NBYTES, b"\0"),
                [s16(v) for v in list(w.vm.vars[:NVARS]) + [0] * (NVARS - len(w.vm.vars[:NVARS]))])
    out = []
    fin = 0                                 # (el primer paso sin habitacion, del final)
    for t, (m, b, k) in enumerate(j.inputs):
        if w.room and t > fin:
            fin = t + 1
        if t % CADA == 0:
            out.append(ahora(t))
        jw.tick(mouse=m, button=b, key=k)
    return fin, [x for x in out if x[0] <= fin]


def marcas(ms):
    """(mascara, [(variable, valor)]) que cuentan."""
    mask = bytearray(NBYTES)
    for i in range(NBYTES * 8):
        byte, bit = i >> 3, 1 << (i & 7)
        vals = [bool(b[byte] & bit) for _, b, _ in ms]
        if not vals[-1] or vals[0]:
            continue                        # (puesta al final y no desde el arranque)
        k = vals.index(True)
        if all(vals[k:]):
            mask[byte] |= bit
    pares = []
    for v in range(PRIMERAS, NVARS):
        vals = [vs[v] for _, _, vs in ms]
        if any(b < a for a, b in zip(vals, vals[1:])):
            continue                        # (baja alguna vez)
        dist = sorted(set(vals))
        if len(dist) < 2 or len(dist) > MAXVAL:
            continue
        pares += [(v, x) for x in dist[1:]]
    if len(pares) > NV:                     # (si sobran: las que cambian mas tarde)
        def primera(p):
            v, x = p
            return next(i for i, (_, _, vs) in enumerate(ms) if vs[v] >= x)
        pares = sorted(sorted(pares, key=primera)[-NV:])
    return bytes(mask), pares


def cuenta(bits, vs, mask, pares):
    return (sum(bin(x & y).count("1") for x, y in zip(bits, mask))
            + sum(1 for v, x in pares if vs[v] >= x))


def tabla(n, ms):
    """(mascara, pares, cuentas por %) de las muestras."""
    mask, pares = marcas(ms)
    c = [cuenta(b, vs, mask, pares) for _, b, vs in ms]
    curva = []
    for p in range(101):
        t = n * p // 100
        i = min(range(len(ms)), key=lambda i: abs(ms[i][0] - t))
        curva.append(c[i])
    return mask, pares, curva


def por_ciento(bits, vs, mask, pares, curva):
    """Lo que hace el Z80: el primer % con la cuenta de la partida."""
    c = cuenta(bits, vs, mask, pares)
    for p, v in enumerate(curva):
        if v >= c:
            return p
    return 100


def de_partida(datos):
    """(bits, vars) de un SAVEn.DAT (VMDATA en su segunda pagina)."""
    vm = datos[8192:8192 + 2 * NVARS + NBYTES]
    vs = [s16(vm[2 * i] | vm[2 * i + 1] << 8) for i in range(NVARS)]
    return vm[2 * NVARS:], vs


def fichero(mask, pares, curva):
    out = bytearray(b"PG\x02") + mask + bytes((len(pares),))
    for v, x in pares + [(0, 0)] * (NV - len(pares)):
        out += v.to_bytes(2, "little") + (x & 0xFFFF).to_bytes(2, "little")
    for v in curva:
        out += v.to_bytes(2, "little")
    return bytes(out)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    nombre, sd = sys.argv[1], sys.argv[2]
    import nexttest as NT
    n, ms = muestras(nombre, NT.ORIGINAL, sd)
    mask, pares, curva = tabla(n, ms)
    with open(os.path.join(sd, "PROGRESO.DAT"), "wb") as f:
        f.write(fichero(mask, pares, curva))
    errs = [abs(por_ciento(b, vs, mask, pares, curva) - 100 * t // n) for t, b, vs in ms]
    print("%d pasos; cuentan %d bits y %d valores de %d variables (de %d a %d); error en la "
          "propia partida: medio %.1f, maximo %d"
          % (n, sum(bin(x).count("1") for x in mask), len(pares), len({v for v, _ in pares}),
             curva[0], curva[-1], sum(errs) / len(errs), max(errs)))


if __name__ == "__main__":
    main()
