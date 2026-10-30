"""Imagenes y GIF del modelo, sin emulador.

    python tools/preview.py gif SALIDA.gif [carpeta de datos del juego] [habitacion]
    python tools/preview.py walk           # paseo guionizado por el juego de prueba

Con el juego de prueba (build/prueba) no hace falta nada mas.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import convert as C  # noqa: E402
import model as M  # noqa: E402

ROOT = os.path.dirname(HERE)
PRUEBA = os.path.join(ROOT, "build", "prueba")

# paseo por el patio: (paso, x, y) clics en coordenadas de la habitacion
WALK = [(0, 560, 112), (40, 60, 98), (95, 300, 132), (130, 470, 110), (160, 140, 110)]


def engine(folder=PRUEBA, room=1, costume=1):
    game, _ = C.find_game(folder)
    rd = C.RoomData(game.room(room), game.index)
    cost = game.costume(costume)
    pal9 = C.palette_bytes(rd.palette)
    return M.Engine(rd, cost), M.Screen(rd, pal9, cost)


def scripted(eng, steps=200, clicks=WALK):
    todo = dict((t, (x, y)) for t, x, y in clicks)
    for t in range(steps):
        fr = eng.tick(todo.get(t))
        yield t, fr


def cmd_gif(out, folder=PRUEBA, room=1):
    eng, scr = engine(folder, room)
    imgs = []
    for t, fr in scripted(eng):
        imgs.append(Image.fromarray(scr.render(eng.cam.left(), fr)).resize((640, 512), Image.NEAREST))
    imgs[0].save(out, save_all=True, append_images=imgs[1:], duration=80, loop=0)
    print("GIF:", out, len(imgs), "pasos")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "walk"
    if cmd == "gif":
        cmd_gif(sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "build", "modelo.gif"),
                *(sys.argv[3:4] or [PRUEBA]), *[int(v) for v in sys.argv[4:5]])
    elif cmd == "walk":
        eng, _ = engine()
        for t, fr in scripted(eng):
            a = eng.actor
            if t % 10 == 0:
                print("%3d x=%4d y=%3d face=%3d box=%d mov=%x cam=%d tiles=%d" % (
                    t, a.x, a.y, a.facing, a.box, a.moving, eng.cam.cur, fr.ntiles))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
