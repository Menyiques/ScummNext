**ScummNext** es un intérprete de aventuras gráficas **SCUMM v5** para el **ZX Spectrum Next**, escrito en ensamblador Z80N, con un conversor para Windows que prepara los ficheros de tu propia copia del juego.

Probado con ***The Secret of Monkey Island*** en su versión CD (VGA): jugado de principio a fin en un Next de verdad.

> **No incluye ningún juego ni nada sacado de ningún juego.** Como en ScummVM, aquí solo está el motor: hace falta tu copia original (`MONKEY.000` y `MONKEY.001` del CD y, para la música, sus pistas de audio; o la imagen del CD).

### Novedades

- El conversor abre directamente la **imagen del CD**: `.cue` con sus `.bin`, `.img` o `.wav`, CloneCD (`.ccd` + `.img`) e `.iso`. Saca de ella `MONKEY.000`, `MONKEY.001` y la música de las pistas de audio, sin programas aparte ni ficheros que renombrar. En la ventana, botón «Imagen de CD…». Un `.iso` solo lleva los datos (sin música); `.mds`/`.mdf`, `.nrg` y `.chd` hay que pasarlas antes a `.cue`/`.bin`.

### Qué hace

- La habitación en Layer 2 a 256 colores, con scroll y la zona de verbos e inventario debajo.
- Los actores con sprites por hardware, con su escala, sus planos Z y sus animaciones.
- Los scripts del juego en una máquina virtual SCUMM v5: verbos, frases, inventario, conversaciones y escenas.
- Los textos con las fuentes del juego, los efectos digitalizados y la música del CD. Los sonidos que solo existen para AdLib se sintetizan al convertir.
- Guardar y cargar en 8 huecos, con nombre.
- Varios juegos en la misma tarjeta, con un menú para elegir (hasta 9).
- Se juega con ratón Kempston o con el teclado.

### Qué hace falta

- Un ZX Spectrum Next con **2 MB** de memoria.
- Windows 10 u 11 de 64 bits para el conversor.

### Cómo se usa

1. Descarga `ScummNext-20261030b.zip` y descomprímelo.
2. Abre `ConversorScumm.exe`. No está firmado: si Windows avisa, pulsa «Más información» y «Ejecutar de todas formas».
3. Pulsa «Convertir un juego…» y elige la carpeta donde están `MONKEY.000` y `MONKEY.001` («Carpeta…») o la imagen del CD («Imagen de CD…»).
4. Copia la carpeta de trabajo (de serie, `Documentos\ScummNext`) a la SD del Next.
5. En el Next, abre `scumm.nex` desde el navegador.

Los controles y el resto de instrucciones están en el `LEEME.txt` del ZIP.

### Limitaciones

- Solo entiende SCUMM v5 y solo está probado Monkey Island 1 en CD. Otro juego v5 saldría en el menú, pero lo más probable es que no funcione bien.
- El conversor con ventana es solo para Windows. Sin Windows se puede convertir con `tools/convert.py` (Python), aunque no está probado en otros sistemas.
- El % de cada partida en el menú necesita un `PROGRESO.DAT`, que sale de una partida grabada del juego y por eso no se incluye. Sin él, todo funciona igual, sin el %.

### Licencia

GPL v3 o posterior. Buena parte del motor y del conversor traduce el código y la documentación de SCUMM de [ScummVM](https://www.scummvm.org): gracias a su equipo. El ZIP lleva el código fuente completo y las licencias de lo que va dentro del conversor (`AVISOS_TERCEROS.txt`).

Monkey Island, SCUMM y LucasArts son marcas de Lucasfilm Ltd. ScummVM es una marca del equipo de ScummVM. ZX Spectrum Next es una marca de SpecNext Ltd. ScummNext no tiene relación con ninguno de ellos ni cuenta con su respaldo.

---

### English

**ScummNext** is a **SCUMM v5** adventure game interpreter for the **ZX Spectrum Next**, written in Z80N assembly, plus a Windows converter that prepares the files from your own copy of the game. It has been tested with *The Secret of Monkey Island* (CD/VGA version), played from start to finish on real hardware. **No game data is included: you need your own original copy** (`MONKEY.000`, `MONKEY.001` and, for music, the CD audio tracks), or a CD image of it (`.cue`/`.bin`, CloneCD `.ccd`/`.img` or `.iso`), which the converter now reads directly. It needs a 2 MB Next. The converter and the documentation are in Spanish. Licensed under GPL v3 or later; based on ScummVM's work.

---

`ScummNext-20261030b.zip` · SHA-256 `5ff0dee90d5323bbfe960e69ef1e152e7fcae9b92aeff340f852160516cdbb60`
