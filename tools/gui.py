"""La ventana del conversor (Windows; tkinter): la carpeta para la SD del Next, con el
motor (scumm.nex) y una carpeta por juego, y lo que hace falta para convertir uno
nuevo desde su original. El trabajo lo hace tools/biblioteca.py; esto solo lo ensena.

    python tools/gui.py                  la ventana
    python tools/gui.py --prueba RAIZ F [PNG]   (pruebas) abre la ventana con RAIZ,
                                         apunta en F lo que ensena (y, con PNG, la captura
                                         de la ventana y del dialogo) y se cierra
    python tools/gui.py --convertir ORIGEN RAIZ CARPETA TITULO F
                                         (pruebas del .exe) convierte sin ventana y
                                         apunta en F el registro y el resultado

tools/build_exe.py la empaqueta en build/exe/ConversorScumm.exe (con el motor dentro).
"""
import json
import os
import queue
import sys
import threading
import traceback
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import biblioteca as B  # noqa: E402

APP = "ScummNext: conversor de juegos SCUMM para el Next"
CONF = os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~"), "ConversorScumm", "config.json")
# el nombre en el menu (31 letras) que se propone para los juegos conocidos
CONOCIDOS = {"MONKEY": "The Secret of Monkey Island",
             "MONKEY2": "Monkey Island 2",
             "ATLANTIS": "Fate of Atlantis"}
AUTO = "Automático"
VERDE, ROJO, GRIS = "#2f7d32", "#b3261e", "#6b6b6b"


def cargar_conf():
    try:
        with open(CONF, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def guardar_conf(c):
    try:
        os.makedirs(os.path.dirname(CONF), exist_ok=True)
        with open(CONF, "w", encoding="utf-8") as f:
            json.dump(c, f, ensure_ascii=False, indent=1)
    except OSError:
        pass


def mb(n):
    return "%.0f MB" % (n / 1e6) if n >= 1e6 else "%.0f KB" % (n / 1e3)


class Tarea:
    """fn(avance, log) en otro hilo; los mensajes llegan a la ventana por una cola:
    al_avance(texto, fraccion), al_log(linea), al_final(resultado, error). parar()
    hace que el siguiente avance lance B.Parado."""

    def __init__(self, widget, fn, al_avance=None, al_log=None, al_final=None):
        self.widget, self.fn = widget, fn
        self.al_avance = al_avance or (lambda t, f: None)
        self.al_log = al_log or (lambda s: None)
        self.al_final = al_final or (lambda r, e: None)
        self.q = queue.Queue()
        self._parar = threading.Event()
        self.viva = True
        threading.Thread(target=self._run, daemon=True).start()
        widget.after(80, self._mira)

    def parar(self):
        self._parar.set()

    def _avance(self, texto, frac):
        if self._parar.is_set():
            raise B.Parado()
        self.q.put(("avance", texto, frac))

    def _run(self):
        try:
            r = self.fn(self._avance, lambda s: self.q.put(("log", s, None)))
            self.q.put(("fin", r, None))
        except B.Parado:
            self.q.put(("fin", None, "Cancelado"))
        except Exception as e:                      # noqa: BLE001
            self.q.put(("log", traceback.format_exc(), None))
            self.q.put(("fin", None, str(e) or e.__class__.__name__))

    def _mira(self):
        while True:
            try:
                k, a, b = self.q.get_nowait()
            except queue.Empty:
                break
            if k == "avance":
                self.al_avance(a, b)
            elif k == "log":
                self.al_log(a)
            else:
                self.viva = False
                self.al_final(a, b)
                return
        self.widget.after(80, self._mira)


class Ventana(tk.Tk):
    def __init__(self, raiz=None):
        super().__init__()
        self.title(APP)
        self.geometry("980x620")
        self.minsize(820, 520)
        self.conf = cargar_conf()
        defecto = os.path.join(os.path.expanduser("~"), "Documents", "ScummNext")
        self.raiz = tk.StringVar(value=raiz or self.conf.get("raiz") or defecto)
        self.lista = []
        self.sel = None
        self._interfaz()
        self.refrescar()

    # --- la ventana ---------------------------------------------------------------
    def _interfaz(self):
        top = ttk.Frame(self, padding=(10, 8, 10, 4))
        top.pack(fill="x")
        ttk.Label(top, text="Carpeta para la SD").grid(row=0, column=0, sticky="w", padx=(0, 8))
        ttk.Entry(top, textvariable=self.raiz, state="readonly").grid(row=0, column=1, sticky="we")
        ttk.Button(top, text="Cambiar…", command=self.cambiar_raiz).grid(row=0, column=2, padx=(8, 0))
        self.l_motor = ttk.Label(top, text="")
        self.l_motor.grid(row=1, column=0, columnspan=2, sticky="w", pady=(6, 0))
        self.b_motor = ttk.Button(top, text="Copiar el motor", command=self.copiar_motor)
        self.b_motor.grid(row=1, column=2, padx=(8, 0), pady=(6, 0), sticky="e")
        top.columnconfigure(1, weight=1)

        pan = ttk.PanedWindow(self, orient="horizontal")
        pan.pack(fill="both", expand=True, padx=10, pady=6)
        izq = ttk.Frame(pan)
        der = ttk.Frame(pan, padding=(12, 0, 0, 0))
        pan.add(izq, weight=1)
        pan.add(der, weight=1)

        cab = ttk.Frame(izq)
        cab.pack(fill="x")
        ttk.Label(cab, text="Tus juegos", font=("Segoe UI", 10, "bold")).pack(side="left")
        self.l_cuenta = ttk.Label(cab, text="", foreground=GRIS)
        self.l_cuenta.pack(side="left", padx=8)
        self.arbol = ttk.Treeview(izq, columns=("estado",), show="tree headings", selectmode="browse")
        self.arbol.heading("#0", text="Juego")
        self.arbol.heading("estado", text="Estado")
        self.arbol.column("#0", width=260)
        self.arbol.column("estado", width=110, anchor="center")
        self.arbol.tag_configure("listo", foreground=VERDE)
        self.arbol.tag_configure("no cabe", foreground=ROJO)
        self.arbol.tag_configure("sin informe", foreground=GRIS)
        self.arbol.tag_configure("carpeta larga", foreground=ROJO)
        self.arbol.pack(fill="both", expand=True, pady=(4, 6))
        self.arbol.bind("<<TreeviewSelect>>", lambda e: self.ensenar())
        ttk.Button(izq, text="+ Convertir un juego…", command=self.nuevo).pack(anchor="w")

        self.v_titulo = tk.StringVar()
        filas = ttk.Frame(der)
        filas.pack(fill="x")
        ttk.Label(filas, text="Nombre en el menú").grid(row=0, column=0, sticky="w", pady=2)
        self.e_titulo = ttk.Entry(filas, textvariable=self.v_titulo)
        self.e_titulo.grid(row=0, column=1, sticky="we", pady=2)
        self.b_titulo = ttk.Button(filas, text="Guardar", command=self.guardar_titulo)
        self.b_titulo.grid(row=0, column=2, padx=(6, 0))
        self.datos = {}
        for i, k in enumerate(("Carpeta", "Original", "Contenido", "% en el menú", "Partidas"), 1):
            ttk.Label(filas, text=k).grid(row=i, column=0, sticky="nw", pady=2, padx=(0, 10))
            v = ttk.Label(filas, text="", wraplength=380, justify="left")
            v.grid(row=i, column=1, columnspan=2, sticky="w", pady=2)
            self.datos[k] = v
        filas.columnconfigure(1, weight=1)
        self.t_informe = tk.Text(der, height=7, wrap="word", relief="flat", borderwidth=0,
                                 font=("Segoe UI", 9), padx=8, pady=6)
        self.t_informe.pack(fill="both", expand=True, pady=(10, 8))
        self.t_informe.configure(state="disabled")
        bot = ttk.Frame(der)
        bot.pack(fill="x")
        self.b_reconv = ttk.Button(bot, text="Reconvertir", command=self.reconvertir)
        self.b_reconv.pack(side="left")
        self.b_abrir = ttk.Button(bot, text="Abrir carpeta", command=self.abrir)
        self.b_abrir.pack(side="left", padx=6)
        self.b_mover = ttk.Button(bot, text="Pasar a su carpeta…", command=self.a_su_carpeta)
        self.b_quitar = ttk.Button(bot, text="Quitar…", command=self.quitar)
        self.b_quitar.pack(side="left")

        self.l_pie = ttk.Label(self, text="", foreground=GRIS, padding=(10, 0, 10, 8))
        self.l_pie.pack(fill="x")

    # --- lo que se ensena ---------------------------------------------------------
    def refrescar(self, elegir=None):
        raiz = self.raiz.get()
        estado, m, m_inc = B.motor(raiz)
        txt = {"al dia": "Motor scumm.nex: al día",
               "distinto": "Motor scumm.nex: no es el que trae el conversor",
               "falta": "Falta el motor scumm.nex en la carpeta",
               "sin motor": "Este conversor no trae el motor scumm.nex"}[estado]
        if m:
            txt += " (%s)" % m[:8]
        self.l_motor.configure(text=txt, foreground=VERDE if estado == "al dia" else ROJO)
        self.b_motor.configure(state="normal" if estado in ("distinto", "falta") else "disabled")
        prev = elegir if elegir is not None else (self.sel.carpeta if self.sel else None)
        self.lista = B.juegos(raiz)
        self.arbol.delete(*self.arbol.get_children())
        for i, j in enumerate(self.lista):
            est = {"listo": "Listo", "no cabe": "No cabe (%d)" % len(j.problemas),
                   "sin informe": "Sin informe", "carpeta larga": "Carpeta larga"}[j.estado]
            self.arbol.insert("", "end", iid=str(i), text=j.titulo, values=(est,), tags=(j.estado,))
        n = len(self.lista)
        self.l_cuenta.configure(text="%d de %d" % (n, B.GMAX), foreground=ROJO if n > B.GMAX else GRIS)
        pie = "Copia la carpeta entera a la SD del Next y abre scumm.nex: si hay más de un juego, sale la lista."
        if n > B.GMAX:
            pie = "El Next solo enseña %d juegos: sobran %d." % (B.GMAX, n - B.GMAX)
        self.l_pie.configure(text=pie)
        idx = next((i for i, j in enumerate(self.lista) if j.carpeta == prev), 0 if self.lista else None)
        if idx is not None:
            self.arbol.selection_set(str(idx))
            self.arbol.see(str(idx))
        self.ensenar()

    def ensenar(self):
        s = self.arbol.selection()
        self.sel = self.lista[int(s[0])] if s else None
        j = self.sel
        hay = j is not None
        for b in (self.e_titulo, self.b_titulo, self.b_reconv, self.b_abrir, self.b_quitar):
            b.configure(state="normal" if hay else "disabled")
        self.b_mover.pack_forget()
        if not hay:
            self.v_titulo.set("")
            for v in self.datos.values():
                v.configure(text="")
            self._informe("Todavía no hay juegos en esta carpeta. Pulsa «Convertir un juego…».", None)
            return
        self.v_titulo.set(j.titulo if j.carpeta or B.leer_titulo(j.ruta) else "")
        self.datos["Carpeta"].configure(text=j.carpeta or "(suelto junto a scumm.nex)")
        self.datos["Original"].configure(text=j.info.get("origen", "—"))
        cont = ["%d habitaciones" % j.habitaciones]
        if j.pistas:
            cont.append("%d pistas de CD" % j.pistas)
        cont.append(mb(j.bytes))
        self.datos["Contenido"].configure(text=", ".join(cont))
        self.datos["% en el menú"].configure(text="Sí (PROGRESO.DAT)" if j.progreso else "No")
        self.datos["Partidas"].configure(
            text=" ".join(os.path.splitext(p)[0] for p in j.partidas) or "Ninguna")
        if j.estado == "carpeta larga":
            self._informe("El Next no ve esta carpeta: su nombre tiene que ser de 1 a 8 letras o cifras, "
                          "sin espacios ni puntos. Cámbiale el nombre (por ejemplo, %s) desde el Explorador."
                          % B.nombre_carpeta(j.carpeta), "mal")
        elif j.estado == "listo":
            txt = "Todo cabe en el Next."
            if j.info.get("fecha"):
                txt += " Convertido el %s." % j.info["fecha"]
            txt += "".join("\n\nAviso: " + a for a in j.info.get("avisos", []))
            self._informe(txt, "ok")
        elif j.estado == "no cabe":
            self._informe("No cabe en el Next:\n" + "\n".join("- " + p for p in j.problemas), "mal")
        else:
            self._informe("Convertido sin esta ventana: reconviértelo para saber si cabe.", None)
        if not j.carpeta:
            self.b_mover.pack(side="left", padx=(6, 0), before=self.b_quitar)
            self.b_quitar.configure(state="disabled")

    def _informe(self, txt, tipo):
        bg = {"ok": "#e6f2e6", "mal": "#fbe9e7"}.get(tipo, "#f2f2f2")
        fg = {"ok": VERDE, "mal": ROJO}.get(tipo, "#333333")
        self.t_informe.configure(state="normal", background=bg, foreground=fg)
        self.t_informe.delete("1.0", "end")
        self.t_informe.insert("1.0", txt)
        self.t_informe.configure(state="disabled")

    # --- botones ------------------------------------------------------------------
    def cambiar_raiz(self):
        d = filedialog.askdirectory(parent=self, title="La carpeta para la SD del Next",
                                    initialdir=self.raiz.get() if os.path.isdir(self.raiz.get()) else None)
        if d:
            self.raiz.set(os.path.normpath(d))
            self.conf["raiz"] = self.raiz.get()
            guardar_conf(self.conf)
            self.refrescar()

    def copiar_motor(self):
        try:
            B.copiar_motor(self.raiz.get())
        except OSError as e:
            messagebox.showerror(APP, "No se ha podido copiar el motor:\n%s" % e, parent=self)
        self.refrescar()

    def guardar_titulo(self):
        t = self.v_titulo.get().strip()
        if not t:
            messagebox.showwarning(APP, "Escribe un nombre.", parent=self)
            return
        if len(t) > B.TITMAX:
            messagebox.showwarning(APP, "Caben %d letras; ese tiene %d." % (B.TITMAX, len(t)), parent=self)
            return
        B.escribir_titulo(self.sel.ruta, t)
        self.refrescar()

    def abrir(self):
        if self.sel:
            os.startfile(self.sel.ruta)             # noqa: S606 (Windows)

    def quitar(self):
        j = self.sel
        if not j or not j.carpeta:
            return
        extra = "\n\nTambién sus partidas guardadas: %s." % ", ".join(j.partidas) if j.partidas else ""
        if not messagebox.askyesno(APP, "¿Mandar «%s» (la carpeta %s) a la papelera?%s"
                                   % (j.titulo, j.carpeta, extra), icon="warning", parent=self):
            return
        try:
            B.quitar(j.raiz, j.carpeta)
        except (OSError, ValueError) as e:
            messagebox.showerror(APP, str(e), parent=self)
        self.refrescar()

    def a_su_carpeta(self):
        j = self.sel
        if not j or j.carpeta:
            return
        n = simpledialog.askstring(APP, "Este juego está suelto junto a scumm.nex. ¿En qué carpeta lo pongo?\n"
                                   "(con sus partidas guardadas; de 1 a 8 letras o cifras)", parent=self,
                                   initialvalue=B.nombre_carpeta(B.leer_titulo(j.ruta) or "JUEGO"))
        if not n:
            return
        try:
            B.a_su_carpeta(j.raiz, n.strip())
        except (OSError, ValueError) as e:
            messagebox.showerror(APP, str(e), parent=self)
            return
        self.refrescar(elegir=n.strip().upper())

    def nuevo(self):
        Convertir(self, None)

    def reconvertir(self):
        if not self.sel:
            return
        if not self.sel.carpeta:
            messagebox.showinfo(APP, "Para reconvertirlo, pásalo antes a su carpeta.", parent=self)
            return
        Convertir(self, self.sel)


class Convertir(tk.Toplevel):
    """Convertir un juego (juego: el que se reconvierte, o None para uno nuevo)."""

    def __init__(self, ventana, juego):
        super().__init__(ventana)
        self.ventana, self.juego = ventana, juego
        self.title("Reconvertir un juego" if juego else "Convertir un juego")
        self.transient(ventana)
        self.resizable(True, True)
        self.minsize(600, 520)
        self.tarea = None
        self.detectados = []
        self.carpeta_tocada = bool(juego)
        info = juego.info if juego else {}
        self.v_origen = tk.StringVar(value=info.get("origen", ""))
        self.v_nombre = tk.StringVar(value=info.get("nombre", ""))
        self.v_titulo = tk.StringVar(value=juego.titulo if juego else "")
        self.v_carpeta = tk.StringVar(value=juego.carpeta if juego else "")
        self.v_musica = tk.BooleanVar(value=info.get("musica", True))
        self.v_cost = tk.StringVar(value=str(info["costume"]) if info.get("costume") is not None else AUTO)
        self.v_sala = tk.StringVar(value=str(info["habitacion"]) if info.get("habitacion") is not None else AUTO)
        self.v_prog = tk.StringVar(value="")
        self._interfaz()
        self.protocol("WM_DELETE_WINDOW", self.cerrar)
        self.v_titulo.trace_add("write", lambda *a: self._titulo_cambia())
        self.v_carpeta.trace_add("write", lambda *a: self._carpeta_cambia())
        if self.v_origen.get():
            self.detectar()
        self.grab_set()

    def _interfaz(self):
        f = ttk.Frame(self, padding=12)
        f.pack(fill="both", expand=True)
        r = 0
        ttk.Label(f, text="Carpeta del original").grid(row=r, column=0, sticky="w", pady=3)
        e = ttk.Entry(f, textvariable=self.v_origen)
        e.grid(row=r, column=1, sticky="we", pady=3)
        e.bind("<Return>", lambda ev: self.detectar())
        e.bind("<FocusOut>", lambda ev: self.detectar())
        ttk.Button(f, text="Examinar…", command=self.examinar).grid(row=r, column=2, padx=(6, 0))
        r += 1
        self.c_nombre = ttk.Combobox(f, textvariable=self.v_nombre, state="readonly", width=12)
        self.c_nombre.bind("<<ComboboxSelected>>", lambda ev: self._elegido())
        self.l_det = ttk.Label(f, text="Elige la carpeta donde están NOMBRE.000 y NOMBRE.001 (y las pistas del CD).",
                               foreground=GRIS, wraplength=440, justify="left")
        self.l_det.grid(row=r, column=1, columnspan=2, sticky="w", pady=(0, 8))
        r += 1
        ttk.Label(f, text="Nombre en el menú").grid(row=r, column=0, sticky="w", pady=3)
        ttk.Entry(f, textvariable=self.v_titulo).grid(row=r, column=1, sticky="we", pady=3)
        self.l_letras = ttk.Label(f, text="", foreground=GRIS, width=6)
        self.l_letras.grid(row=r, column=2, sticky="w", padx=(6, 0))
        r += 1
        ttk.Label(f, text="Carpeta en la SD").grid(row=r, column=0, sticky="w", pady=3)
        ec = ttk.Entry(f, textvariable=self.v_carpeta)
        ec.grid(row=r, column=1, sticky="we", pady=3)
        ttk.Label(f, text="hasta 8", foreground=GRIS).grid(row=r, column=2, sticky="w", padx=(6, 0))
        ec.bind("<Key>", lambda ev: setattr(self, "carpeta_tocada", True))
        if self.juego:
            ec.configure(state="readonly")
        r += 1
        ttk.Separator(f).grid(row=r, column=0, columnspan=3, sticky="we", pady=8)
        r += 1
        ttk.Checkbutton(f, text="Música del CD (si están las pistas)", variable=self.v_musica).grid(
            row=r, column=0, columnspan=3, sticky="w", pady=2)
        r += 1
        ttk.Label(f, text="Protagonista (costume)").grid(row=r, column=0, sticky="w", pady=3)
        self.c_cost = ttk.Combobox(f, textvariable=self.v_cost, values=[AUTO], width=14)
        self.c_cost.grid(row=r, column=1, sticky="w", pady=3)
        r += 1
        ttk.Label(f, text="Primera habitación").grid(row=r, column=0, sticky="w", pady=3)
        self.c_sala = ttk.Combobox(f, textvariable=self.v_sala, values=[AUTO], width=14)
        self.c_sala.grid(row=r, column=1, sticky="w", pady=3)
        r += 1
        ttk.Label(f, text="Progreso (%)").grid(row=r, column=0, sticky="w", pady=3)
        pf = ttk.Frame(f)
        pf.grid(row=r, column=1, columnspan=2, sticky="we")
        self.l_prog = ttk.Label(pf, text="", foreground=GRIS)
        self.l_prog.pack(side="left")
        ttk.Button(pf, text="Elegir PROGRESO.DAT…", command=self.elegir_progreso).pack(side="right")
        r += 1
        ttk.Label(f, text="Las partidas guardadas (SAVEn.DAT) de la carpeta se conservan.",
                  foreground=GRIS).grid(row=r, column=0, columnspan=3, sticky="w", pady=(6, 4))
        r += 1
        self.barra = ttk.Progressbar(f, maximum=1.0)
        self.barra.grid(row=r, column=0, columnspan=3, sticky="we", pady=(6, 2))
        r += 1
        self.l_paso = ttk.Label(f, text="", foreground=GRIS)
        self.l_paso.grid(row=r, column=0, columnspan=3, sticky="w")
        r += 1
        self.t_log = tk.Text(f, height=9, wrap="word", font=("Consolas", 9), relief="solid", borderwidth=1)
        self.t_log.grid(row=r, column=0, columnspan=3, sticky="nsew", pady=(4, 8))
        self.t_log.configure(state="disabled")
        f.rowconfigure(r, weight=1)
        r += 1
        bot = ttk.Frame(f)
        bot.grid(row=r, column=0, columnspan=3, sticky="we")
        self.b_comp = ttk.Button(bot, text="Comprobar si cabe", command=self.comprobar)
        self.b_comp.pack(side="left")
        self.b_conv = ttk.Button(bot, text="Convertir", command=self.convertir)
        self.b_conv.pack(side="right")
        self.b_cerrar = ttk.Button(bot, text="Cancelar", command=self.cerrar)
        self.b_cerrar.pack(side="right", padx=6)
        f.columnconfigure(1, weight=1)
        self._titulo_cambia()
        self._progreso_txt()

    # --- campos -------------------------------------------------------------------
    def _titulo_cambia(self):
        t = self.v_titulo.get().strip()
        self.l_letras.configure(text="%d/%d" % (len(t), B.TITMAX),
                                foreground=ROJO if len(t) > B.TITMAX else GRIS)

    def _carpeta_cambia(self):
        c = self.v_carpeta.get()
        if c != c.upper():
            self.v_carpeta.set(c.upper())

    def _progreso_txt(self):
        p = self.v_prog.get()
        if p:
            txt = p
        elif self.juego and self.juego.progreso:
            txt = "el PROGRESO.DAT que ya tiene"
        else:
            txt = "ninguno"
        self.l_prog.configure(text=txt)

    def elegir_progreso(self):
        p = filedialog.askopenfilename(parent=self, title="PROGRESO.DAT",
                                       filetypes=[("PROGRESO.DAT", "PROGRESO.DAT"), ("Todos", "*.*")])
        if p:
            self.v_prog.set(os.path.normpath(p))
            self._progreso_txt()

    def examinar(self):
        d = filedialog.askdirectory(parent=self, title="La carpeta del juego original",
                                    initialdir=self.v_origen.get() or self.ventana.conf.get("origen"))
        if d:
            self.v_origen.set(os.path.normpath(d))
            self.ventana.conf["origen"] = os.path.dirname(self.v_origen.get())
            guardar_conf(self.ventana.conf)
            self.detectar()

    def detectar(self):
        o = self.v_origen.get().strip()
        if not o or getattr(self, "_detectado", None) == o or (self.tarea and self.tarea.viva):
            return
        self._detectado = o
        if not os.path.isdir(o):
            self.l_det.configure(text="Esa carpeta no existe.", foreground=ROJO)
            return
        self.l_det.configure(text="Mirando…", foreground=GRIS)
        self.tarea = Tarea(self, lambda av, lg: B.detectar(o), al_final=self._detectado_fin)

    def _detectado_fin(self, r, err):
        if err:
            self.l_det.configure(text="No se ha podido leer: %s" % err, foreground=ROJO)
            return
        self.detectados = r or []
        if not self.detectados:
            self.l_det.configure(text="No hay ningún NOMBRE.000 en esa carpeta.", foreground=ROJO)
            self.c_nombre.grid_forget()
            return
        nombres = [d["nombre"] for d in self.detectados]
        if len(nombres) > 1:
            self.c_nombre.configure(values=nombres)
            self.c_nombre.grid(row=1, column=0, sticky="nw", pady=(0, 8))
        else:
            self.c_nombre.grid_forget()
        if self.v_nombre.get() not in nombres:
            self.v_nombre.set(nombres[0])
        self._elegido()

    def _elegido(self):
        d = next((x for x in self.detectados if x["nombre"] == self.v_nombre.get()), None)
        if d is None:
            return
        if d["error"]:
            self.l_det.configure(text="%s: %s" % (d["nombre"], d["error"]), foreground=ROJO)
            return
        partes = ["%s.000 y .001" % d["nombre"],
                  "SCUMM v5" if d["v5"] else "no parece SCUMM v5 (el Next solo lleva v5)",
                  "%d habitaciones" % d["habitaciones"]]
        if d["pistas_usa"]:
            partes.append("%d de %d pistas del CD" % (d["pistas_hay"], d["pistas_usa"]))
        self.l_det.configure(text=" · ".join(partes), foreground=GRIS if d["v5"] else ROJO)
        self.c_cost.configure(values=[AUTO] + [str(c) for c in d["costumes"]])
        self.c_sala.configure(values=[AUTO] + [str(s) for s in d["salas"]])
        if not self.juego:
            if not self.v_titulo.get().strip():
                self.v_titulo.set(CONOCIDOS.get(d["nombre"].upper(), d["nombre"].capitalize()))
            if not self.carpeta_tocada:
                self.v_carpeta.set(B.nombre_carpeta(d["nombre"]))

    def _numero(self, v, cual):
        v = v.get().strip()
        if v in ("", AUTO):
            return None
        if not v.isdigit():
            raise ValueError("%s: pon un número o «%s»." % (cual, AUTO))
        return int(v)

    # --- trabajo ------------------------------------------------------------------
    def _log(self, s):
        self.t_log.configure(state="normal")
        self.t_log.insert("end", s.rstrip() + "\n")
        self.t_log.see("end")
        self.t_log.configure(state="disabled")

    def _avance(self, txt, frac):
        self.l_paso.configure(text=txt)
        self.barra.configure(value=frac)

    def _ocupado(self, si):
        for b in (self.b_comp, self.b_conv):
            b.configure(state="disabled" if si else "normal")
        self.b_cerrar.configure(text="Parar" if si else "Cerrar")

    def _opciones(self):
        o = self.v_origen.get().strip()
        if not o or not os.path.isdir(o):
            raise ValueError("Elige la carpeta del original.")
        if not self.detectados:
            raise ValueError("En esa carpeta no hay ningún juego.")
        return dict(origen=o, nombre=self.v_nombre.get() or None,
                    costume=self._numero(self.v_cost, "Protagonista"),
                    habitacion=self._numero(self.v_sala, "Primera habitación"))

    def comprobar(self):
        try:
            op = self._opciones()
        except ValueError as e:
            messagebox.showwarning(APP, str(e), parent=self)
            return
        self._log("Comprobando %s…" % op["origen"])
        self._ocupado(True)

        def fn(av, lg):
            card = B.comprobar(op["origen"], op["nombre"], op["costume"], op["habitacion"], av)
            card.report(lg)
            return card
        self.tarea = Tarea(self, fn, self._avance, self._log, self._fin_comprobar)

    def _fin_comprobar(self, card, err):
        self._ocupado(False)
        self._avance("" if err else "Comprobado (no se ha escrito nada)", 0 if err else 1.0)
        if err:
            self._log(err)

    def convertir(self):
        try:
            op = self._opciones()
        except ValueError as e:
            messagebox.showwarning(APP, str(e), parent=self)
            return
        titulo = self.v_titulo.get().strip()
        carpeta = self.v_carpeta.get().strip().upper()
        if not titulo:
            messagebox.showwarning(APP, "Pon el nombre que se verá en el menú.", parent=self)
            return
        if len(titulo) > B.TITMAX:
            messagebox.showwarning(APP, "El nombre del menú tiene %d letras; caben %d." % (len(titulo), B.TITMAX),
                                   parent=self)
            return
        why = B.carpeta_valida(carpeta)
        if why:
            messagebox.showwarning(APP, why, parent=self)
            return
        raiz = self.ventana.raiz.get()
        destino = os.path.join(raiz, carpeta)
        if os.path.exists(os.path.join(destino, "GAME.DAT")):
            otro = B.leer_info(destino).get("nombre")
            if otro and otro.upper() != (op["nombre"] or "").upper():
                if not messagebox.askyesno(APP, "En %s hay otro juego (%s). Si lo reconviertes con %s, sus partidas "
                                           "guardadas ya no valdrán. ¿Seguir?" % (carpeta, otro, op["nombre"]),
                                           icon="warning", parent=self):
                    return
            elif not self.juego and not messagebox.askyesno(
                    APP, "Ya hay un juego en %s. ¿Reconvertirlo encima? (sus partidas se quedan)" % carpeta,
                    parent=self):
                return
        elif len(B.juegos(raiz)) >= B.GMAX:
            if not messagebox.askyesno(APP, "Ya hay %d juegos y el Next solo enseña %d. ¿Seguir?" % (
                    len(B.juegos(raiz)), B.GMAX), icon="warning", parent=self):
                return
        prog = self.v_prog.get() or None
        musica = self.v_musica.get()
        self._log("Convirtiendo %s en %s…" % (op["origen"], destino))
        self._ocupado(True)

        def fn(av, lg):
            info = B.convertir(op["origen"], raiz, carpeta, titulo, op["nombre"], op["costume"],
                               op["habitacion"], musica, prog, av, lg)
            if B.motor(raiz)[0] == "falta":
                B.copiar_motor(raiz)
                lg("scumm.nex copiado a %s" % raiz)
            return info
        self.carpeta = carpeta
        self.tarea = Tarea(self, fn, self._avance, self._log, self._fin_convertir)

    def _fin_convertir(self, info, err):
        self._ocupado(False)
        if err:
            self._avance("", 0)
            self._log("No se ha convertido: %s" % err)
        else:
            self._avance("Hecho: %s" % ("todo cabe en el Next" if info["cabe"] else "no cabe en el Next"), 1.0)
        self.ventana.refrescar(elegir=self.carpeta)

    def cerrar(self):
        if self.tarea and self.tarea.viva:
            if self.b_cerrar.cget("text") == "Parar":
                self.tarea.parar()
                self._log("Parando…")
            return
        self.grab_release()
        self.destroy()


def captura(win, png):
    """La ventana win (solo ella) a png."""
    from PIL import ImageGrab
    win.update()
    x, y = win.winfo_rootx(), win.winfo_rooty()
    ImageGrab.grab((x, y, x + win.winfo_width(), y + win.winfo_height())).save(png)


def prueba(raiz, salida, png=None):
    """La ventana con raiz: lo que ensena (y el dialogo de reconvertir el primero) a
    salida, y se cierra."""
    w = Ventana(raiz)
    lineas = []

    def mira():
        if png:
            w.lift()
            captura(w, png + "_ventana.png")
        lineas.append("motor: %s" % w.l_motor.cget("text"))
        lineas.append("cuenta: %s" % w.l_cuenta.cget("text"))
        for iid in w.arbol.get_children():
            lineas.append("juego: %s | %s" % (w.arbol.item(iid, "text"), w.arbol.item(iid, "values")[0]))
        if w.sel:
            lineas.append("titulo: %s" % w.v_titulo.get())
            for k, v in w.datos.items():
                lineas.append("%s: %s" % (k, v.cget("text")))
            lineas.append("informe: %s" % w.t_informe.get("1.0", "end").strip().replace("\n", " / "))
            d = Convertir(w, w.sel) if w.sel.carpeta else Convertir(w, None)
            w.after(3000, lambda: dialogo(d))
        else:
            fin()

    def dialogo(d):
        if png:
            d.lift()
            captura(d, png + "_dialogo.png")
        lineas.append("dialogo: %s" % d.title())
        lineas.append("dialogo origen: %s" % d.v_origen.get())
        lineas.append("dialogo detectado: %s" % d.l_det.cget("text"))
        lineas.append("dialogo titulo: %s (%s) carpeta: %s" % (d.v_titulo.get(), d.l_letras.cget("text"),
                                                               d.v_carpeta.get()))
        lineas.append("dialogo progreso: %s" % d.l_prog.cget("text"))
        d.cerrar()
        fin()

    def fin():
        with open(salida, "w", encoding="utf-8") as f:
            f.write("\n".join(lineas) + "\n")
        w.destroy()
    w.after(800, mira)
    w.mainloop()


def main():
    try:                                            # nitida con la pantalla escalada
        import ctypes
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except (AttributeError, OSError):
        pass
    if len(sys.argv) > 3 and sys.argv[1] == "--prueba":
        prueba(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
        return
    if len(sys.argv) > 6 and sys.argv[1] == "--convertir":
        origen, raiz, carpeta, titulo, salida = sys.argv[2:7]
        lineas = []
        try:
            info = B.convertir(origen, raiz, carpeta, titulo, log=lineas.append)
            if B.motor(raiz)[0] == "falta":
                B.copiar_motor(raiz)
            lineas.append("resultado: " + json.dumps(info, ensure_ascii=False))
        except Exception:                           # noqa: BLE001
            lineas.append(traceback.format_exc())
        with open(salida, "w", encoding="utf-8") as f:
            f.write("\n".join(lineas) + "\n")
        return
    Ventana().mainloop()


if __name__ == "__main__":
    main()
