"""Cliente minimo del protocolo remoto de ZEsarUX (ZRCP).

Arranca el emulador (si no esta ya escuchando), carga ficheros, lee memoria,
pulsa teclas y hace capturas. Lo usan las pruebas y los scripts de capturas.
"""
import os
import socket
import subprocess
import time

ZESARUX = os.environ.get(
    "ZESARUX", r"C:\Users\User\ZX\ZEsarUX_windows-13.0\zesarux.exe")
PORT = int(os.environ.get("ZRCP_PORT", 10124))  # puerto propio para no chocar con otro ZEsarUX


class Zrcp:
    def __init__(self, port=PORT, fresh=True, visible=False, sd_dir=None):
        """fresh: cierra el emulador que haya en el puerto y arranca otro.
        sd_dir: carpeta que hace de tarjeta SD (RST $08 de esxDOS)."""
        self.port = port
        self.proc = None
        self.sd_dir = sd_dir
        try:
            self.sock = socket.create_connection(("127.0.0.1", port), timeout=2)
            if not fresh:
                self._read()
                return
            self._read()
            self.sock.sendall(b"exit-emulator" + bytes((10,)))
            self.sock.close()
            time.sleep(1.0)
        except OSError:
            pass
        self._launch(visible)
        self._read()

    def _launch(self, visible):
        args = [ZESARUX, "--noconfigfile", "--machine", "TBBlue",
                "--tbblue-fast-boot-mode", "--allowturbotbbluerom", "--realvideo", "--nowelcomemessage",
                "--quickexit", "--enable-remoteprotocol",
                "--remoteprotocol-port", str(self.port)]
        if self.sd_dir:
            args += ["--enable-esxdos-handler", "--esxdos-root-dir", os.path.abspath(self.sd_dir)]
        if not visible:
            args += ["--vo", "null", "--ao", "null"]
        if os.environ.get("ZESARUX_SPEED"):        # en %: las pruebas largas, mas deprisa
            args += ["--emulatorspeed", os.environ["ZESARUX_SPEED"]]
        if os.environ.get("ZESARUX_TIMER"):        # date, sdl o usleep
            args += ["--preferred-timer", os.environ["ZESARUX_TIMER"]]
        self.proc = subprocess.Popen(args, cwd=os.path.dirname(ZESARUX),
                                     stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        for _ in range(100):
            time.sleep(0.1)
            try:
                self.sock = socket.create_connection(("127.0.0.1", self.port),
                                                     timeout=2)
                return
            except OSError:
                pass
        raise RuntimeError("ZEsarUX no responde en el puerto %d" % self.port)

    def _read(self, timeout=10.0):
        data = b""
        self.sock.settimeout(timeout)
        while not data.endswith(b"command> "):
            chunk = self.sock.recv(1 << 20)
            if not chunk:
                break
            data += chunk
        return data[:-len(b"command> ")].decode("latin1").strip()

    def cmd(self, line, timeout=10.0):
        self.sock.sendall((line + "\n").encode("latin1"))
        return self._read(timeout)

    # --- utilidades ---
    def load(self, path):
        return self.cmd("smartload " + os.path.abspath(path), timeout=30)

    def read(self, addr, n):
        """Lee n bytes de la memoria mapeada (vista del Z80)."""
        out = bytearray()
        while n > 0:
            k = min(n, 4096)
            txt = self.cmd("read-memory %d %d" % (addr, k))
            out += bytes.fromhex(txt.replace(" ", "").replace("\n", ""))
            addr += k
            n -= k
        return bytes(out)

    def read_phys(self, addr, n):
        """Lee n bytes de la RAM del Next (pagina * 8192 + desplazamiento) sin tocar lo
        que ve el Z80. En la zona 0 de ZEsarUX la RAM empieza en $40000 (antes van las
        ROM y la DivMMC, como en la SRAM del Next)."""
        self.cmd("set-memory-zone 0")
        try:
            return self.read(0x40000 + addr, n)
        finally:
            self.cmd("set-memory-zone -1")

    def write(self, addr, data):
        vals = " ".join("%d" % b for b in data)    # ZEsarUX los lee en decimal
        return self.cmd("write-memory %d %s" % (addr, vals))

    def nextreg(self, reg):
        txt = self.cmd("tbblue-get-register %d" % reg).split()[-1]
        return int(txt.rstrip("Hh"), 16)

    def screenshot(self, path):
        """Guarda la pantalla como PNG (via BMP de ZEsarUX)."""
        path = os.path.abspath(path)
        bmp = os.path.splitext(path)[0] + ".bmp"
        self.cmd("save-screen " + bmp)
        for _ in range(50):
            if os.path.exists(bmp) and os.path.getsize(bmp) > 0:
                break
            time.sleep(0.05)
        time.sleep(0.1)
        from PIL import Image
        img = Image.open(bmp).convert("RGB")
        if path.lower().endswith(".png"):
            img.save(path)
            os.remove(bmp)
        return img

    def key(self, k, down):
        return self.cmd("send-keys-event %d %d" % (k, 1 if down else 0))

    def wait_frames(self, n):
        time.sleep(n / 50.0)

    def close(self, kill=True):
        try:
            if kill and self.proc:
                self.sock.sendall(b"exit-emulator\n")
                time.sleep(0.3)
            self.sock.close()
        finally:
            if kill and self.proc:
                try:
                    self.proc.wait(3)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
