; ===========================================================================
;  Capa OVS (pagina OVS_PAGE, en $C000): guardar y cargar partidas
;  (model.World.snapshot / load_state) y el menu (CAPS SHIFT + 1)
;
;  La instantanea va en las paginas SNAP0.. (7 x 8 KB):
;    SNAP0   cabecera: "SCSV", version, tamano de VMDATA, habitacion, camara
;            (+8, 11 bytes), el nombre que le pone el jugador (+32, hasta 24 letras
;            y un 0; las partidas de antes lo tienen a 0: sin nombre) y los
;            contadores de los ciclos de color (+200, 32)
;    +1      VMDATA (variables, bits, ranuras, objetos, actores, interfaz)
;    +2..+5  las paginas 13 (clases e inventario), 78 (los actores), 94
;            (verbos, nombres, inventario) y 95 (el monton)
;    +6      la pagina de la habitacion (META): su paleta que se ve y sus cajas
;  Una partida guardada (SAVEn.DAT) son esas 7 paginas tal cual.
; ===========================================================================

SNAP0       EQU 108
NSNAP       EQU 7
HDRPAGE     EQU 115             ; para leer las cabeceras de las partidas
LOADBUF     EQU 116             ; una partida leida (7 paginas) antes de comprobarla
SV_VER      EQU 5                   ; 3: los actores, todos en CAST_PAGE; 4: con su sonido; 5: pseudoRoom
SH_ROOM     EQU 7
SH_CAM      EQU 8
SH_NAME     EQU 32
SH_FX       EQU 200
SVNMAX      EQU 24                  ; letras del nombre de una partida
SVNSZ       EQU SVNMAX+1            ; (y el 0 de detras)

; --- la instantanea en memoria ------------------------------------------------------
S_SNAP:
        call ACTSYNC                ; (el actor de ACTOR, a su ficha)
        ld a,SNAP0
        call MAP7
        ld hl,$E000
        ld de,$E001
        ld bc,255
        ld (hl),0
        ldir
        ld hl,SVMAGIC
        ld de,$E000
        ld bc,5
        ldir
        ld hl,VMDATA_END-VMDATA
        ld ($E005),hl
        ld a,(CURROOM)
        ld ($E000+SH_ROOM),a
        ld hl,CAM_CUR
        ld de,$E000+SH_CAM
        ld bc,11
        ldir
        ld a,OVF_PAGE               ; los contadores de los ciclos (en la capa OVF)
        nextreg $52,a
        ld hl,FXCNT-$C000+$4000
        ld de,$E000+SH_FX
        ld bc,32
        ldir
        ld a,(SHMMU2)
        nextreg $52,a
        ld a,SNAP0+1
        call MAP7
        ld hl,VMDATA
        ld de,$E000
        ld bc,VMDATA_END-VMDATA
        ldir
        ld a,INVP
        ld b,SNAP0+2
        call PGCOPY
        ld a,CAST_PAGE
        ld b,SNAP0+3
        call PGCOPY
        ld a,UIP
        ld b,SNAP0+4
        call PGCOPY
        ld a,HEAPP
        ld b,SNAP0+5
        call PGCOPY
        ld a,META_PAGE
        ld b,SNAP0+6
        jp PGCOPY

; La pagina A a la B (por MMU2 y MMU7)
PGCOPY:
        nextreg $52,a
        ld a,b
        call MAP7
        ld hl,$4000
        ld de,$E000
        ld bc,$2000
        ldir
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; VMDATA y las paginas 13, 78, 94 y 95 desde la instantanea
UNSNAPVM:
        ld a,SNAP0+1
        call MAP7
        ld hl,$E000
        ld de,VMDATA
        ld bc,VMDATA_END-VMDATA
        ldir
        ld a,SNAP0+2
        ld b,INVP
        call PGCOPY
        ld a,SNAP0+3
        ld b,CAST_PAGE
        call PGCOPY
        ld a,SNAP0+4
        ld b,UIP
        call PGCOPY
        ld a,SNAP0+5
        ld b,HEAPP
        call PGCOPY
        xor a                       ; (lo que hay en ACTOR ya no vale)
        ld (ACTN),a
        ld a,$FF                    ; MMU2: lo que diga SHMMU2 (no lo que habia)
        ld (L2CUR),a
        ret

; La camara, el protagonista y los contadores de los ciclos desde la instantanea
UNSNAPCAM:
        ld a,SNAP0
        call MAP7
        ld hl,$E000+SH_CAM
        ld de,CAM_CUR
        ld bc,11
        ldir
        ld a,OVF_PAGE
        nextreg $52,a
        ld hl,$E000+SH_FX
        ld de,FXCNT-$C000+$4000
        ld bc,32
        ldir
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; Volver al juego tal como estaba (despues del menu)
S_UNSNAP:
        call UNSNAPVM
        call UNSNAPCAM
        jp PALREGS

; La paleta de Layer 2 desde la que se ve (META+32)
PALREGS:
        nextreg $43,%00010000
        nextreg $40,0
        ld hl,META+32
        ld b,0
.p:     ld a,(hl)
        inc hl
        nextreg $44,a
        ld a,(hl)
        inc hl
        nextreg $44,a
        djnz .p
        ret

; --- cargar (model.World.load_state) -----------------------------------------------
; Con la instantanea ya en sus paginas: todo como estaba, la pantalla en negro, la
; habitacion otra vez (sin sus scripts) con su camara, su paleta y sus cajas, y los
; verbos pintados de nuevo
S_LOADSTATE:
        call HIDESPR                ; (los actores de antes)
        call UNSNAPVM
        ld hl,SN_AFTERLOAD           ; la cola y los efectos no se guardan
        ld a,OVA_PAGE
        call OVCALL
        ld a,SNAP0
        call MAP7
        ld a,($E000+SH_ROOM)
        ld (LSROOM),a
        call L2CLEAR                ; (y se ve A, sin transicion a medias)
        ld hl,MSGBUF
        ld (MSGP),hl
        ld a,$FF
        ld (CURSLOT),a
        ld (L2CUR),a
        xor a
        ld (NESTN),a
        ld (HASMASK),a
        ld (MASKV),a
        OTCALL TMCLRALL
        xor a
        ld (VRECTV),a
        ld (VMOVER),a
        ld a,(LSROOM)
        or a
        jr nz,.room
        ld (CURROOM),a              ; sin habitacion: la pantalla, en negro
        jr .verbs
.room:  ld hl,LOADROOM              ; (pone la camara en 160 y la paleta de la SD;
        call SAFECALL               ; deja una pagina de la habitacion en MMU6)
        call UNSNAPCAM
        ld a,SNAP0+6                ; la paleta que se veia y las cajas
        call MAP7
        ld hl,$E000+32
        ld de,META+32
        ld bc,512
        ldir
        ld a,(NBOXES)
        ld e,a
        ld d,20
        mul d,e
        ld a,d
        or e
        jr z,.nb
        ld b,d
        ld c,e
        ld hl,$E000+640
        ld de,META+640
        ldir
.nb:    ld a,($E000+592)            ; la matriz de cajas estaba rehecha (o la habitacion
        ld hl,META+591              ; la rehace: las partidas de antes no lo dicen):
        or (hl)                     ; otra vez, con los flags guardados
        jr z,.nm
        ld hl,F_BOXMATRIX
        ld a,OVF_PAGE
        call OVCALL
.nm:    call PALREGS
        ld a,(CAM_SS)               ; la camara tal como se guardo (CAMMOVED la
        ld l,a                      ; acotaria otra vez: en una habitacion estrecha
        ld h,0                      ; la dejaria en ancho - 160)
        add hl,hl
        add hl,hl
        add hl,hl
        ld (LEFT),hl
        call NARROW
        call FULLDRAW
        ld a,(CAM_SS)
        ld (L2SS),a
        call MOD40
        add a,a
        add a,a
        ld l,a
        ld h,0
        add hl,hl
        ld (SCRL),hl
        di
        call COPPERSET
        ei
        ld a,$FF
        ld (PSTRIP),a
.verbs: ld a,1                      ; todos los verbos (drawVerb(i, 0))
.v:     ld (LSV),a
        xor a
        ld (DVMODE),a
        ld a,(LSV)
        OTCALL DRAWVERB
        ld a,(LSV)
        inc a
        cp NUM_VERBS
        jr nz,.v
        xor a
        ld (VMOVER),a
        OTCALL VFLUSH
        ret

; --- ficheros --------------------------------------------------------------------------
; SVNM = "SAVEn.DAT" con n = A (1..8)
SVNAME:
        add a,'0'
        ld (SVNM+4),a
        ret

; Las paginas de la instantanea a SAVEn.DAT (A = n); carry si falla
SAVEFILE:
        call SVNAME
        ld a,i
        push af
        di
        call FILESON
        ld ix,SVNM
        ld a,'*'
        ld b,$0E                    ; escribir, y crearlo de nuevo
        call ROMIN
        rst 8
        db $9A
        call ROMOUT
        jr c,.err
        ld (SVH),a
        ld a,SNAP0
.pg:    ld (SVP),a
        call MAP7
        ld a,(SVH)
        ld ix,$E000
        ld bc,$2000
        call ROMIN
        rst 8
        db $9E
        call ROMOUT
        jr c,.cerr
        ld a,(SVP)
        inc a
        cp SNAP0+NSNAP
        jr nz,.pg
        ld a,(SVH)
        call FCLOSE
        xor a
        jr .out
.cerr:  ld a,(SVH)
        call FCLOSE
.err:   ld a,1
.out:   ld (SVERR),a
        call FILESOFF
        pop af
        jp po,.di
        ei
.di:    ld a,(SVERR)
        cp 1                        ; carry si 0? no: carry si fallo
        ccf
        ret

; SAVEn.DAT (A = n) a las paginas de la instantanea; carry si no esta o no vale
; (se lee aparte y solo si vale se copia: si falla, la instantanea sigue igual)
LOADFILE:
        call SVNAME
        ld a,i
        push af
        di
        ld hl,SVNM
        ld a,LOADBUF
        ld b,NSNAP
        call LOADPAGES
        ld a,0
        jr nc,.ok
        inc a
.ok:    ld (SVERR),a
        pop af
        jp po,.di
        ei
.di:    ld a,(SVERR)
        or a
        scf
        ret nz
        ld a,LOADBUF                ; que sea una partida de este programa
        call MAP7
        ld hl,$E000
        call HDROK
        ret c
        xor a                       ; vale: a la instantanea
.cp:    ld (SVP),a
        add a,LOADBUF
        ld b,a
        ld a,(SVP)
        add a,SNAP0
        ld c,a
        ld a,b
        ld b,c
        call PGCOPY
        ld a,(SVP)
        inc a
        cp NSNAP
        jr nz,.cp
        or a
        ret

; Carry si la cabecera de HL no es de una partida de este programa
HDROK:
        ld de,SVMAGIC
        ld b,5
.c:     ld a,(de)
        cp (hl)
        jr nz,.no
        inc hl
        inc de
        djnz .c
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld de,VMDATA_END-VMDATA
        or a
        sbc hl,de
        jr nz,.no
        or a
        ret
.no:    scf
        ret

; SLOTR[n] = la habitacion de SAVEn.DAT o $FF si no hay (n = 1..8), y su nombre en
; SLOTNM (vacio si no tiene)
SLOTSCAN:
        ld a,1
.s:     ld (SVP),a
        call SVNAME
        ld hl,0
        ld (FROFF),hl
        ld (FROFF+2),hl
        ld hl,SH_NAME+SVNSZ         ; (la cabecera hasta el nombre)
        ld (FRLEN),hl
        ld a,HDRPAGE
        ld (FRPAGE),a
        ld hl,$E000
        ld (FRADDR),hl
        ld a,HDRPAGE                ; (por si no esta: que no quede la de antes)
        call MAP7
        xor a
        ld ($E000),a
        ld hl,SVNM
        call FILEREAD
        ld a,HDRPAGE
        call MAP7
        ld hl,$E000
        call HDROK
        ld a,$FF
        jr c,.st
        ld a,($E000+SH_ROOM)
.st:    push af
        ld a,(SVP)
        ld hl,SLOTR
        add hl,a
        pop af
        ld (hl),a
        push af                     ; el nombre: SLOTNM, con solo letras de 32 a 126
        ld a,(SVP)
        call SLOTNP
        push de
        ld h,d
        ld l,e
        ld (hl),0
        inc de
        ld bc,SVNSZ-1
        ldir
        pop de
        pop af
        cp $FF
        jr z,.nx
        ld hl,$E000+SH_NAME
        ld b,SVNMAX
.nc:    ld a,(hl)
        cp ' '
        jr c,.nx
        cp 127
        jr nc,.nx
        ld (de),a
        inc hl
        inc de
        djnz .nc
.nx:    ld a,(SVP)                  ; su %: los bits de su VMDATA (SLOTP, $FF: no se sabe)
        ld hl,SLOTR
        add hl,a
        ld a,(hl)
        cp $FF
        jr z,.np
        ld a,(PGOK)
        or a
        ld a,$FF
        jr z,.np
        ld hl,$2000                 ; (VMDATA, en la segunda pagina, hasta BITS)
        ld (FROFF),hl
        ld hl,BITS-VMDATA+256
        ld (FRLEN),hl
        ld hl,$E100
        ld (FRADDR),hl
        ld hl,SVNM
        call FILEREAD
        ld a,$FF
        jr c,.np
        ld a,HDRPAGE
        call MAP7
        ld hl,$E100
        call PGPCT
.np:    push af
        ld a,(SVP)
        ld hl,SLOTP
        add hl,a
        pop af
        ld (hl),a
        ld a,(SVP)
        inc a
        cp 9
        jp nz,.s
        ret

; PROGRESO.DAT a PGTAB (tools/progreso.py); NC si esta y vale
PGLOAD:
        xor a
        ld (PGTAB),a
        ld hl,0
        ld (FROFF),hl
        ld (FROFF+2),hl
        ld hl,PGSIZE
        ld (FRLEN),hl
        ld a,OVS_PAGE               ; (esta capa, por MMU7)
        ld (FRPAGE),a
        ld hl,PGTAB-$C000+$E000
        ld (FRADDR),hl
        ld hl,PGNM
        call FILEREAD
        ld hl,PGTAB
        ld a,(hl)
        cp 'P'
        jr nz,.no
        inc hl
        ld a,(hl)
        cp 'G'
        jr nz,.no
        inc hl
        ld a,(hl)
        cp 2
        jr nz,.no
        ld a,1
        ld (PGOK),a
        or a
        ret
.no:    xor a
        ld (PGOK),a
        scf
        ret

; A = el % de la partida de HL (una copia de VMDATA: las variables y BITS): cuantas
; cosas de PROGRESO.DAT tiene (bits de la mascara puestos y variables que llegan a
; su valor) y el primer % de la partida grabada que ya tenia otras tantas
PGPCT:
        ld (PGB),hl
        ld de,BITS-VMDATA
        add hl,de
        exx
        ld bc,0                     ; BC' = la cuenta
        exx
        ld de,PGMASK
        ld b,0
.by:    ld a,(de)
        and (hl)
.bi:    jr z,.nx
        add a,a
        jr nc,.bi
        exx
        inc bc
        exx
        jr .bi
.nx:    inc hl
        inc de
        djnz .by
        ld hl,PGVARS                ; las variables: (numero, valor) con signo
        ld a,(hl)
        or a
        jr z,.cu
        ld b,a
        inc hl
.va:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,(PGB)
        add hl,de
        add hl,de
        ld e,(hl)
        inc hl
        ld a,(hl)
        xor $80                     ; (con el signo cambiado se comparan sin signo)
        ld d,a
        pop hl
        ld c,(hl)
        inc hl
        ld a,(hl)
        xor $80
        inc hl
        push hl
        ld h,a
        ld l,c
        ex de,hl
        or a
        sbc hl,de
        pop hl
        jr c,.vn
        exx
        inc bc
        exx
.vn:    djnz .va
.cu:    exx
        push bc
        exx
        pop de
        ld hl,PGCURVE
        ld b,0
.cv:    ld a,(hl)
        inc hl
        push hl
        ld h,(hl)
        ld l,a
        or a
        sbc hl,de
        pop hl
        inc hl
        ld a,b
        ret nc
        inc b
        ld a,b
        cp 101
        jr c,.cv
        ld a,100
        ret

; DE = el nombre del hueco A (1..8) en SLOTNM (HL se queda)
SLOTNP:
        push hl
        dec a
        ld d,a
        ld e,SVNSZ
        mul d,e
        ld hl,SLOTNM
        add hl,de
        ex de,hl
        pop hl
        ret

; El nombre que se ha escrito (MNAME) a la cabecera de la instantanea
SVSETNAME:
        ld a,SNAP0
        call MAP7
        ld hl,MNAME
        ld de,$E000+SH_NAME
        ld bc,SVNSZ
        ldir
        ret

; --- para las pruebas (TREQ 10 y 11) ---------------------------------------------------
T_SAVE:
        call S_SNAP
        ld a,(TROOM)
        jp SAVEFILE
T_LOAD:
        ld a,(TROOM)
        call LOADFILE
        ret c
        jp S_LOADSTATE

; --- el menu -----------------------------------------------------------------------------
; La pantalla se guarda en la otra de Layer 2 (B) y el estado en la instantanea;
; al volver, todo como estaba (salvo si se carga una partida o se reinicia)
MENU:
        OTCALL VFLUSH               ; (los verbos, todos en A)
        call S_SNAP
        xor a                       ; la pantalla (A) a B
.cp:    ld (SVP),a
        add a,L2_PAGE
        ld b,a
        ld a,(SVP)
        add a,L2B_PAGE
        ld c,a
        ld a,b
        ld b,c
        call PGCOPY
        ld a,(SVP)
        inc a
        cp 10
        jr nz,.cp
        call HIDESPR
        ld hl,(SCRL)                ; el scroll y el temblor, a 0 mientras tanto (la letra
        ld (MSCRL),hl               ; del menu va en columnas fijas de Layer 2)
        ld a,(SHAKEY)
        ld (MSHK),a
        ld hl,0
        ld (SCRL),hl
        xor a
        ld (SHAKEY),a
        di
        call COPPERSET
        ei
        call PGLOAD                 ; el % de la partida en curso (si hay PROGRESO.DAT)
        ld a,$FF
        jr c,.pn
        ld hl,VMDATA
        call PGPCT
.pn:    ld (PGNOW),a
        call SLOTSCAN
        ld a,1
        ld (VDIRECT),a              ; (el menu pinta en la que se ve, A)
        ld (MSEL),a
        xor a
        ld (MMSG),a
.draw:  call MDRAW
.key:   ld a,(KEYPEND)
        or a
        jr z,.key
        ld b,a
        xor a
        ld (KEYPEND),a
        ld a,b
        cp 27
        jp z,.back
        cp '1'
        jr c,.n1
        cp '9'
        jr nc,.n1
        sub '0'
        ld (MSEL),a
        xor a
        ld (MMSG),a
        jr .draw
.n1:    or $20                      ; (mayusculas o minusculas)
        cp 'g'
        jr nz,.n2
        call MNAMEIN                ; el nombre (ESC: no se guarda)
        jr c,.draw
        call SVSETNAME
        ld a,(MSEL)                 ; (la instantanea es el juego de antes del menu)
        call SAVEFILE
        ld a,2
        jr c,.msg
        call SLOTSCAN
        ld a,1
.msg:   ld (MMSG),a
        jr .draw
.n2:    cp 'c'
        jr nz,.n3
        ld a,(MSEL)
        call LOADFILE
        jr c,.lfail
        xor a
        ld (VDIRECT),a
        call MSCRBACK
        jp S_LOADSTATE
.lfail: ld a,3
        ld (MMSG),a
        jr .draw
.n3:    cp 'r'
        jr nz,.n4
        call .back
        ld a,1
        ld (RESTARTREQ),a
        ret
.n4:    cp 's'
        jr nz,.n5
        nextreg $02,1               ; salir: reinicio del Next
        jr .key
.n5:    cp 'j'                      ; otro juego (si hay mas de uno)
        jp nz,.key
        ld a,(GN)
        cp 2
        jp c,.key
        call G_PICK
        push af
        di                          ; (el scroll del juego otra vez)
        call COPPERSET
        ei
        pop af
        jp c,.draw                  ; ESC: el menu de partidas otra vez
        call .back
        ld a,1                      ; el paso siguiente lo carga (GSWITCH)
        ld (GAMEREQ),a
        ret
.back:  call MSCRBACK                ; volver: el scroll, la pantalla y el estado de antes
        nextreg $12,L2B_PAGE/2      ; (mientras se copia, se ve B: ya es la del juego)
        xor a
        ld (VDIRECT),a
.bp:    ld (SVP),a
        add a,L2B_PAGE
        ld b,a
        ld a,(SVP)
        add a,L2_PAGE
        ld c,a
        ld a,b
        ld b,c
        call PGCOPY
        ld a,(SVP)
        inc a
        cp 10
        jr nz,.bp
        nextreg $12,L2_BANK
        jp S_UNSNAP

; El scroll y el temblor del juego otra vez
MSCRBACK:
        ld hl,(MSCRL)
        ld (SCRL),hl
        ld a,(MSHK)
        ld (SHAKEY),a
        di
        call COPPERSET
        ei
        ret

; La pantalla del menu: todo en negro, el titulo, los 8 huecos, las teclas y el
; mensaje MMSG (1 guardada, 2 no se pudo guardar, 3 no se pudo cargar); mientras se
; escribe un nombre (MEDIT), las teclas para eso
MDRAW:
        xor a                       ; Layer 2 (A) en negro
.f:     ld (SVP),a
        add a,L2_PAGE
        nextreg $52,a
        ld hl,$4000
        ld de,$4001
        ld bc,$1FFF
        ld (hl),0
        ldir
        ld a,(SVP)
        inc a
        cp 10
        jr nz,.f
        ld a,(SHMMU2)
        nextreg $52,a
        nextreg $43,%00010000       ; 0 negro, 253 gris, 254 amarillo, 255 blanco
        nextreg $40,0
        nextreg $44,0
        nextreg $44,0
        nextreg $40,253
        nextreg $44,$6D
        nextreg $44,1
        nextreg $44,$FC
        nextreg $44,0
        nextreg $44,$FF
        nextreg $44,1
        ld hl,MT_TITLE
        ld de,12
        ld a,255
        call MTEXT
        ld a,(PGNOW)
        cp $FF
        jr z,.nt
        ld de,MT_NOW
        ld hl,MBUF
        call MCAT
        ld a,(PGNOW)
        call MPCT
        ld hl,MBUF
        ld de,12
        ld bc,160
        ld a,253
        call MTEXTX
.nt:    ld a,1                      ; los huecos
.sl:    push af
        call MROW
        pop af
        inc a
        cp 9
        jr nz,.sl
        ld a,(MEDIT)                ; escribiendo un nombre: sus teclas
        or a
        jr z,.nk
        ld hl,MT_EDIT1
        ld de,152
        ld a,255
        call MTEXT
        ld hl,MT_EDIT2
        ld de,164
        ld a,255
        jp MTEXT
.nk:
        ld hl,MT_KEYS1
        ld de,152
        ld a,255
        call MTEXT
        ld hl,MT_KEYS2
        ld de,164
        ld a,255
        call MTEXT
        ld a,(GN)                   ; (con mas de un juego)
        cp 2
        jr c,.nj
        ld hl,MT_KEYS3
        ld de,176
        ld a,255
        call MTEXT
.nj:    ld a,(MMSG)
        or a
        ret z
        ld hl,MT_SAVED
        dec a
        jr z,.m
        ld hl,MT_NOSAVE
        dec a
        jr z,.m
        ld hl,MT_NOLOAD
.m:     ld de,134
        ld a,254
        jp MTEXT

; La fila del hueco A: "> n  nombre" (o "habitacion h", o "vacio"); la elegida en
; amarillo y, si se esta escribiendo su nombre, ese nombre y el cursor en blanco
MROW:
        ld (MN),a
        ld hl,MBUF
        ld b,a
        ld a,(MSEL)
        cp b
        ld a,' '
        jr nz,.ns
        ld a,'>'
.ns:    ld (hl),a
        inc hl
        ld a,(MN)
        add a,'0'
        ld (hl),a
        inc hl
        ld (hl),' '
        inc hl
        ld (hl),' '
        inc hl
        ld a,(MEDIT)
        or a
        jr z,.nm
        ld a,(MN)
        ld b,a
        ld a,(MSEL)
        cp b
        jr nz,.nm
        ld de,MNAME                 ; escribiendo: el nombre y el cursor
        call MCAT
        ld (hl),'_'
        inc hl
        ld c,255
        jr .put
.nm:    ld a,(MN)
        ld de,SLOTR
        add de,a
        ld a,(de)
        cp $FF
        jr nz,.full
        ld de,MT_EMPTY
        call MCAT
        jr .pc
.full:  push af
        ld a,(MN)
        call SLOTNP
        ld a,(de)
        or a
        jr z,.room
        pop af
        call MCAT
        jr .pc
.room:  ld de,MT_ROOM
        call MCAT
        pop af
        call MDEC
.pc:    ld c,253
        ld a,(MN)
        ld b,a
        ld a,(MSEL)
        cp b
        jr nz,.put
        ld c,254
.put:   ld (hl),0
        ld a,c
        ld (MRC),a
        ld a,(MN)                   ; y = 32 + 12 * (n - 1)
        dec a
        ld e,a
        ld d,12
        mul d,e
        ld hl,32
        add hl,de
        ld (MRY),hl
        ex de,hl
        ld hl,MBUF
        ld a,(MRC)                  ; (A era la fila: el hueco 1 salia con el color 0)
        call MTEXT
        ld a,(MEDIT)                ; el % del hueco (no en el que se esta escribiendo)
        or a
        jr z,.pp
        ld a,(MN)
        ld b,a
        ld a,(MSEL)
        cp b
        ret z
.pp:    ld a,(MN)
        ld hl,SLOTP
        add hl,a
        ld a,(hl)
        cp $FF
        ret z
        ld hl,MBUF
        call MPCT
        ld hl,MBUF
        ld de,(MRY)
        ld bc,256
        ld a,(MRC)
        jp MTEXTX

; "A%" a HL
MPCT:
        call MDEC
        ld (hl),'%'
        inc hl
        ld (hl),0
        ret

; Las 12 filas de la fila del hueco A, en negro (las 320 columnas de A)
MCLRROW:
        dec a
        ld e,a
        ld d,12
        mul d,e
        ld a,e
        add a,32+ROOM_Y0
        ld (MCY),a
        xor a
.p:     ld (SVP),a
        add a,L2_PAGE
        nextreg $52,a
        ld a,(MCY)
        ld l,a
        ld h,$40
        ld c,32
        xor a
.c:     ld b,12
        push hl
.b:     ld (hl),a
        inc l
        djnz .b
        pop hl
        inc h
        dec c
        jr nz,.c
        ld a,(SVP)
        inc a
        cp 10
        jr nz,.p
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; Escribir el nombre de la partida del hueco MSEL en MNAME: empieza con el que tenia
; (ENTER lo deja) y la primera letra lo cambia entero; CAPS + 0 borra la ultima.
; Carry si ESC
MNAMEIN:
        ld a,(MSEL)
        call SLOTNP
        ex de,hl
        ld de,MNAME
        ld bc,SVNSZ
        ldir
        ld a,1
        ld (MEDIT),a
        ld (MNEW),a
        xor a
        ld (MMSG),a
        call MDRAW
.key:   ld a,(KEYPEND)
        or a
        jr z,.key
        ld b,a
        xor a
        ld (KEYPEND),a
        ld a,b
        cp 27
        jr z,.esc
        cp 1                        ; ENTER (o el boton del raton)
        jr z,.ok
        cp 8                        ; CAPS + 0
        jr z,.del
        cp ' '
        jr c,.key
        cp 127
        jr nc,.key
        push af
        ld a,(MNEW)
        or a
        jr z,.add
        ld hl,MNAME
        ld de,MNAME+1
        ld bc,SVNSZ-1
        ld (hl),0
        ldir
.add:   pop bc                      ; B = la letra
        call MNLEN
        cp SVNMAX
        jr nc,.key
        ld (hl),b
        jr .row
.del:   call MNLEN
        or a
        jr z,.row
        dec hl
        ld (hl),0
.row:   xor a
        ld (MNEW),a
        ld a,(MSEL)
        call MCLRROW
        ld a,(MSEL)
        call MROW
        jr .key
.esc:   scf
        jr .end
.ok:    or a
.end:   push af
        xor a
        ld (MEDIT),a
        pop af
        ret

; A = letras de MNAME, HL = su 0
MNLEN:
        ld hl,MNAME
        xor a
.l:     inc (hl)
        dec (hl)
        ret z
        inc hl
        inc a
        jr .l

; El texto HL (en esta capa) en x = 24 (o BC con MTEXTX), y = DE (de la pantalla de
; SCUMM: fila ROOM_Y0 + DE de Layer 2), color A, con la letra del menu de juegos:
; siempre la misma, sea cual sea la fuente que tenga puesta el juego
MTEXT:
        ld bc,24
MTEXTX:
        push af
        ld a,e
        add a,ROOM_Y0
        ld e,a
        ld d,0
        pop af
        call GTEXTXY
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; Copia el texto DE (acabado en 0) a HL; HL queda detras
MCAT:
        ld a,(de)
        or a
        ret z
        ld (hl),a
        inc hl
        inc de
        jr MCAT

; A en decimal a HL (sin ceros delante); HL queda detras
MDEC:
        ld c,0                      ; ya se ha puesto una cifra
        ld b,100
        call .dig
        ld b,10
        call .dig
        add a,'0'
        ld (hl),a
        inc hl
        ret
.dig:   ld e,'0'-1
.d:     inc e
        sub b
        jr nc,.d
        add a,b
        push af
        ld a,e
        cp '0'
        jr nz,.w
        ld a,c
        or a
        jr z,.s
        ld a,e
.w:     ld (hl),a
        inc hl
        ld c,1
.s:     pop af
        ret

SVMAGIC: db "SCSV",SV_VER
SVNM:   db "SAVE1.DAT",0
MT_TITLE: db "Partidas",0
MT_EMPTY: db "vac",$ED,"o",0
MT_ROOM: db "habitaci",$F3,"n ",0
MT_KEYS1: db "1-8: elegir   G: guardar   C: cargar",0
MT_KEYS2: db "R: reiniciar   S: salir   ESC: volver",0
MT_KEYS3: db "J: cambiar de juego",0
MT_EDIT1: db "Nombre: escribe y pulsa ENTER",0
MT_EDIT2: db "CAPS+0: borrar   ESC: no guardar",0
MT_NOW: db "Partida en curso: ",0
PGNM:   db "PROGRESO.DAT",0
MT_SAVED: db "Partida guardada",0
MT_NOSAVE: db "No se ha podido guardar",0
MT_NOLOAD: db "No se ha podido cargar",0
SVH:    db 0
SVP:    db 0
SVERR:  db 0
LSROOM: db 0
LSV:    db 0
MSEL:   db 1
MMSG:   db 0
MN:     db 0
SLOTR:  ds 9
SLOTNM: ds 8*SVNSZ                  ; los nombres de los 8 huecos
MNAME:  ds SVNSZ                    ; el que se esta escribiendo
MEDIT:  db 0                        ; 1: escribiendo un nombre
MNEW:   db 0                        ; 1: la primera letra lo cambia entero
MCY:    db 0
MRY:    dw 0
MSCRL:  dw 0                        ; el scroll y el temblor del juego (MENU)
MSHK:   db 0
MRC:    db 0
SLOTP:  ds 9                        ; el % de cada hueco ($FF: no se sabe)
PGNOW:  db $FF                      ; el de la partida en curso
PGOK:   db 0                        ; 1: hay PROGRESO.DAT
PGB:    dw 0
PGNV    EQU 64                      ; variables, como mucho
PGSIZE  EQU 3+256+1+4*PGNV+2*101
PGTAB:  ds PGSIZE                   ; "PG", 2, la mascara, las variables y las cuentas
PGMASK  EQU PGTAB+3
PGVARS  EQU PGMASK+256              ; n y n x (variable, valor), de 16 bits
PGCURVE EQU PGVARS+1+4*PGNV         ; la cuenta en cada % (0..100)
MBUF:   ds 48

        INCLUDE "games.asm"

OVS_END:
        ASSERT OVS_END <= $E000, la capa OVS no cabe
