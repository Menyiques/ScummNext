; ===========================================================================
;  Maquina virtual: datos y enlace con el motor (banco 2, siempre visible)
; ===========================================================================
NSLOTS      EQU 20
NLOCALS     EQU 25
MAXNEST     EQU 12
NACT        EQU 13
DELTA       EQU 5               ; jiffies por paso
NUMGLOBAL   EQU 200
NVARS       EQU 800
NOBJMAX     EQU 1000
CLASS_PAGE  EQU 13

SS_DEAD     EQU 0
SS_PAUSED   EQU 1
SS_RUNNING  EQU 2
WIO_INVENTORY EQU 0
WIO_ROOM    EQU 1
WIO_GLOBAL  EQU 2
WIO_LOCAL   EQU 3
ROOM_EXIT   EQU 10001
ROOM_ENTRY  EQU 10002

VAR_EGO     EQU 1
VAR_HAVE_MSG EQU 3
VAR_ROOM    EQU 4
VAR_OVERRIDE EQU 5
VAR_CURRENT_LIGHTS EQU 9
VAR_ACTOR_RANGE_MIN EQU 15
VAR_ACTOR_RANGE_MAX EQU 16
VAR_TMR_1   EQU 11
VAR_LAST_SOUND EQU 23
VAR_CAMERA_MIN_X EQU 17
VAR_CAMERA_MAX_X EQU 18
VAR_ROOM_RESOURCE EQU 22
VAR_ENTRY_SCRIPT EQU 28
VAR_ENTRY_SCRIPT2 EQU 29
VAR_EXIT_SCRIPT EQU 30
VAR_EXIT_SCRIPT2 EQU 31
VAR_SENTENCE_SCRIPT EQU 33
VAR_CUTSCENE_START_SCRIPT EQU 35
VAR_CUTSCENE_END_SCRIPT EQU 36

; Ranura (el mismo orden que compara tools/nexttest.py)
SL_ST   EQU 0                   ; estado (| $80 congelada)
SL_WH   EQU 1                   ; donde: inventario, habitacion, global, local
SL_NUM  EQU 2                   ; numero de script u objeto
SL_BASE EQU 4                   ; posicion lineal del codigo (3 bytes)
SL_KIND EQU 7                   ; 0: scripts globales, 1: datos de la habitacion
SL_PC   EQU 8
SL_LEN  EQU 10
SL_FRES EQU 12
SL_REC  EQU 13
SL_FCNT EQU 14
SL_CSO  EQU 15
SL_DLY  EQU 16                  ; 24 bits con signo
SL_LOC  EQU 20                  ; 25 locales de 16 bits
SLOTSZ  EQU 70

; MMU7 = pagina A (y se apunta, para no cambiarla si no hace falta)
MAP7:
        ld (SHMMU7),a
        nextreg $57,a
        ret

; ROM abajo para esxDOS, y el codigo otra vez despues (no cambian ni A ni flags).
; ROMUP: la interrupcion no llama al banco 0 mientras esta la ROM
ROMIN:
        push hl
        ld hl,ROMUP
        ld (hl),1
        pop hl
        nextreg $50,$FF
        nextreg $51,$FF
        ret
ROMOUT:
        nextreg $50,0
        nextreg $51,1
        push hl
        ld hl,ROMUP
        ld (hl),0
        pop hl
        ret
ROMUP:  db 0

; --- cajas --------------------------------------------------------------------
SETBOXFLAGS:                        ; caja HL, flags DE
        ld bc,17
        jr SETBOXB
SETBOXSCALE:                        ; caja HL, escala DE
        ld bc,18
        ld a,1
        jr SETBOXW
SETBOXB:
        xor a
SETBOXW:
        ld (SBW),a
        ld a,h
        or a
        ret nz
        ld a,(NBOXES)
        cp l
        ret z
        ret c
        push bc
        push de
        ld a,l
        call BOXPTR
        pop de
        pop bc
        add hl,bc
        ld (hl),e
        ld a,(SBW)
        or a
        ret z
        inc hl
        ld (hl),d
        ret

; pseudoRoom: la habitacion de verdad y las que valen como ella (las de 128 o mas)
H_pseudoRoom:
        call VMFETCH
        ld c,a
.lp:    call VMFETCH
        or a
        ret z
        cp $80
        jr c,.lp
        and $7F
        ld hl,RESMAP
        add hl,a
        ld a,UIP
        call MAP7
        ld (hl),c
        jr .lp

; DRAWSTRIPR de FLUSHOBJ (las filas [DSY0, DSY1)): si hay texto en la principal, sus
; pixeles se quedan (TDRAWS)
DSFLUSH:
        ld c,a
        ld a,(MASKV)
        or a
        ld a,c
        jp z,DRAWSTRIPR
        ld hl,TDRAWS
        ld a,OVT_PAGE
        jp OVCALL

; (APPLY, con la copia limpia pendiente; A = RCALL, HL = RCPEND) Si este objeto, el
; primero que se pone en la tira, tapa todas las filas que se rehacen (opaco en las 8
; columnas, y con todos los planos), la copia limpia no hace falta; si no, ahora (y la
; pagina de la imagen otra vez por $E000)
RCLAZY: ld (hl),0
        inc a
        jr nz,.cp
        ld a,(RCY0)                 ; desde la primera (RCY = max(y, RCY0))
        ld b,a
        ld a,(RCY)
        cp b
        jr nz,.cp
        ld hl,RCHC                  ; hasta la ultima: RCY + RCHC >= min(RCY1, RH)
        add a,(hl)
        ld b,a
        ld a,(RH)
        ld c,a
        ld a,(RCY1)
        cp c
        jr c,.m
        ld a,c
.m:     dec a
        cp b
        jr nc,.cp
        ld a,(RNZ)                  ; los planos 1..RNZ: bits 0..RNZ-1 de RCPM
        ld b,a
        ld a,(RCPM)
        inc b
.pl:    dec b
        ret z
        rrca
        jr c,.pl
.cp:    ld a,(SHMMU7)
        push af
        call RCCOPY
        pop af
        jp MAP7

; (RECOMPOSER) La copia limpia en la de trabajo, en las filas [RCY0, RCY1): los pixeles
; y los planos, 8 + RNZ columnas
RCCOPY: xor a
        ld (RCPEND),a
        ld (RGCMP),a
        ld a,(RCPRI)
        add a,STRIP_PAGE
        call MAP7
        ld hl,(RCSRC)
        ld de,(RCDST)
        ld a,(RNZ)
        add a,8
        jp RGDO
RCPEND: db 0                        ; (RECOMPOSER) la copia limpia, todavia no

; --- cambio de habitacion (World.start_scene) ------------------------------------
; A = habitacion; SCOBJ = objeto donde aparece el protagonista (loadRoomWithEgo)
STARTSCENE:
        ld (SCROOM),a
        ld hl,(SCOBJ)
        ld (SCO),hl
        ld hl,0
        ld (SCOBJ),hl
        ld a,OVT_PAGE
        ld hl,STOPTALK
        call OVCALL
        call FXOUTC                 ; fadeOut (la transicion de salida)
        ld a,(CURROOM)
        or a
        call nz,RUNEXIT
        call KILLROOM
        ld hl,K_HIDEALL             ; todos los actores, ocultos
        call OVKCALL
        ld a,(SCROOM)
        or a
        jr nz,.load
        xor a
        ld (CURROOM),a
        ld hl,0
        ld (VARS+2*VAR_ROOM),hl
        ld (VARS+2*VAR_ROOM_RESOURCE),hl
        ret
.load:  call LOADROOM
        ret c
        ld a,(SCROOM)
        ld l,a
        ld h,0
        ld (VARS+2*VAR_ROOM),hl
        call ROOMRES                ; (pseudoRoom)
        ld l,a
        ld (VARS+2*VAR_ROOM_RESOURCE),hl
        ld hl,160
        ld (VARS+2*VAR_CAMERA_MIN_X),hl
        ld hl,(RW)
        ld de,160
        or a
        sbc hl,de
        ld (VARS+2*VAR_CAMERA_MAX_X),hl
        ld a,(ESTART)               ; (prueba) el protagonista en el punto de inicio
        or a
        jr z,.ne
        xor a
        ld (ESTART),a
        ld a,(VARS+2*VAR_EGO)
        call ACTLOAD
        ld hl,(META+10)
        ld (ix+A_X),l
        ld (ix+A_X+1),h
        ld hl,(META+12)
        ld (ix+A_Y),l
        ld (ix+A_Y+1),h
.ne:    ld hl,(SCO)                 ; loadRoomWithEgo: el protagonista en el objeto,
        ld a,h                      ; mirando al reves
        or l
        jr z,.show
        ld (OVHL),hl
        ld a,(SCROOM)
        ld (OVA),a
        ld hl,K_EGOATOBJ
        ld a,OVK_PAGE
        call OVCALLR
.show:  ld hl,K_SHOWALL             ; showActors
        call OVKCALL
        ld hl,TMCLRALL              ; (la capa del texto, vacia)
        ld a,OVT_PAGE
        call OVCALL
        xor a
        ld (HASMASK),a
        ld (MASKV),a
        ld (EGOPOS),a
        ld hl,(SCO)                 ; (el objeto y la habitacion, en la pila)
        push hl
        ld a,(SCROOM)
        push af
        call RUNENTRY
        pop af
        pop hl
        ld b,a
        ld a,h
        or l
        jr z,.fl
        ld a,(EGOPOS)               ; si el script de entrada no lo ha puesto, alli
        or a
        jr nz,.fl
        ld (OVHL),hl
        ld a,b
        ld (OVA),a
        ld hl,K_EGOATOBJ2
        ld a,OVK_PAGE
        call OVCALLR
.fl:    call FLUSHOBJ
        ld ix,ACTOR
        ret

; Para las pruebas: el protagonista a la habitacion A (punto de inicio) y la
; camara siguiendole (World.enter_with_ego)
ENTEREGO:
        ld (EEROOM),a
        ld a,(VARS+2*VAR_EGO+1)
        or a
        jr nz,.go
        ld a,(VARS+2*VAR_EGO)
        call ACTOK
        jr nc,.go
        call ACTLOAD
        ld a,(EEROOM)
        ld (ACTOR+R_ROOM),a
        ld (ix+A_MOV),0
        ld a,1
        ld (ESTART),a
.go:    ld hl,0
        ld (SCOBJ),hl
        ld a,(EEROOM)
        call STARTSCENE
        ld a,(CURROOM)
        or a
        ret z
        ld a,(VARS+2*VAR_EGO)
        jp CAMFOLLOWS

; El arranque del juego: la maquina virtual desde cero y el script 1
BOOT:
        call VMINIT
        ret c
        xor a
        ld (CURROOM),a
        ld (ARGS),a
        ld (ARGS+1),a
        ld (SSFRES),a
        ld (SSREC),a
        inc a
        ld (ARGN),a
        ld a,$FF
        ld (CURSLOT),a
        ld a,1
        jp RUNSCRIPT

; --- arranque de la maquina virtual ----------------------------------------------
; (en la capa OVF: solo al arrancar y al reiniciar)
VMINIT:
        ld hl,F_VMINIT
        ld a,OVF_PAGE
        jp OVCALL

; Paginas de los scripts globales (128 KB)
SPAGES: db 2, 3, 6, 7, 8, 9, 12, 83, 84, 85, 86, 87, 88, 89, 90, 91
BITMASKS: db 1, 2, 4, 8, 16, 32, 64, 128
ZERO16: dw 0

; --- datos de la maquina virtual --------------------------------------------------
VMDATA:
VARS:   ds 2*NVARS
BITS:   ds 256
SLOTS:  ds NSLOTS*SLOTSZ
OBJOWN: ds NOBJMAX
OBJST:  ds NOBJMAX
NOBJG:  dw 0
NEST:   ds 4*MAXNEST
NESTN:  db 0
CURSLOT: db 0
CURSL:  dw 0
VMOP:   db 0
VMSTART: dw 0
RESVAR: dw 0
PIDX:   db 0
MASKI:  db 0
P0:     dw 0
P1:     dw 0
P2:     dw 0
P3:     dw 0
P4:     dw 0
P5:     dw 0
P6:     dw 0
P7:     dw 0
ARGS:   ds 2*NLOCALS
ARGN:   db 0
STRLEN: dw 0
EXSTK:  ds 32
EXSP:   db 0
EXDST:  dw 0
SEED:   dw 0
TALKDLY: dw 0
CSSP:   db 0
CSDATA: ds 12
CUTPTR:  ds 12
CSSCR:  ds 6
CSIDX:  db 0
EXECN:  dw 0
BITTMP: db 0
SSNUM:  dw 0
SSWH:   db 0
SSKIND: db 0
SSBASE: ds 3
SSPC:   dw 0
SSLEN:  dw 0
SSFRES: db 0
SSREC:  db 0
SSI:    db 0
RSN:    db 0
STN:    dw 0
STW1:   db 0
STW2:   db 0
NRSL:   db 0
ROV:    db 0
ROO:    dw 0
FRF16:  dw 0
CRR:    db 0
CRSAVED: db 0
SVRN:   dw 0
STFL:   db 0
DOOBJ:  dw 0
DOST:   dw 0
DORECT: ds 4
DOK:    db 0
CLSOBJ: dw 0
CLSC:   db 0
CLSN:   db 0
MATK:   db 0
AOACT:  dw 0
AOK:    db 0
SCROOM: db 0
SCOBJ:  dw 0
SCO:    dw 0
SCAX:   dw 0
CFOLD:  db 0
CFARG:  db 0
EEROOM: db 0
SBW:    db 0
BADOP:  db 0
BADN:   dw 0
        INCLUDE "uivars.asm"
ROSUB:  db 0                        ; roomOps: el subcodigo
SHKON:  db 0                        ; temblor: en marcha, posicion y filas hacia abajo
SHKF:   db 0
SHAKEY: db 0
SWEFF:  dw 0                        ; efectos de las transiciones (entrada, salida)
RESTARTREQ: db 0                    ; systemOps 1: reiniciar al empezar el paso siguiente
VMDATA_END:
