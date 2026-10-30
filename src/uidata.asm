; ===========================================================================
;  Interfaz (tools/ui.py): paginas, enlaces con las capas y variables
;  (banco 2, siempre visible)
;
;  El codigo de la interfaz va en dos capas que se ponen en $C000 (MMU6):
;  OVT (textos y verbos) y OVU (instrucciones, entrada, frases, inventario).
;  OVCALL las llama y despues vuelve a poner la que hubiera. Desde una capa
;  se puede llamar a lo de los bancos 0 y 2 que deje MMU6 como estaba
;  (DRAWSTRIP si; RECOMPOSE y COMPOSE no).
; ===========================================================================
OVT_PAGE    EQU 92              ; textos y verbos
OVU_PAGE    EQU 93              ; instrucciones de la interfaz
OVF_PAGE    EQU 106             ; efectos de paleta y pantalla (2 MB)
OVS_PAGE    EQU 107             ; guardar y cargar, y el menu (instantanea: 108-114)
OVA_PAGE    EQU 123             ; el sonido
SND_PAGE    EQU 124             ; SOUNDS.DAT: indice y muestras de los efectos (124-179)
SND_MAX     EQU 56
OVK_PAGE    EQU 184             ; los actores de la maquina virtual
ACACHE_PAGE EQU 185             ; los ultimos dibujos de los actores 1-12 (2 paginas cada uno)
TMASK_PAGE  EQU 209             ; los pixeles del texto de la principal (1 bit cada uno)
TBUF_PAGE   EQU 210             ; (TDPASS) los pixeles de texto de una tira, en TBUF por
TBUF        EQU $7000           ;  $6000 (detras de la prueba de la musica, MT_PAGE)
ZSCR_PAGE   EQU 211             ; (RECOMPOSE: los planos Z de antes de una tira)
ZGENO       EQU $1000           ;  y en esa pagina: el ultimo sello de planos Z (2)
ZSTO        EQU $1002           ;  y el de cada tira, cuando cambiaron sus planos (2 x 128)
ZYMNO       EQU $1200           ;  y las filas apuntadas de cada tira: desde (128)
ZYMXO       EQU $1280           ;  y hasta (128; vacias: $FF y 0)
ZOBXO       EQU $1300           ;  y de cada objeto de la habitacion, su x (256)
ZOBWO       EQU $1400           ;  y su ancho (256)
ZOBIV       EQU $1500           ;  y lo que se sabe de su imagen: 0 nada, 1 no se dibuja,
ZOBIP       EQU $1600           ;  2 su cabecera: en la pagina ZOBIP, en ZOBIH:ZOBIL
ZOBIL       EQU $1700           ;  (RECOMPOSER; la olvidan REDRAWOBJ y CLEARDIRTY)
ZOBIH       EQU $1800
ZOBID       EQU $1900           ;  y el indice de cada objeto de 0 a NOBJMAX - 1 ($FF: no esta)
        ASSERT ZOBID + NOBJMAX <= $2000
ZOBBM       EQU $1D00           ;  y de cada tira (hasta 96), los objetos que la tocan: 8 bytes, bit k
        ASSERT ZOBID + NOBJMAX <= ZOBBM
SM_PAGE     EQU 212             ; capa SM en $E000: el desplazamiento suave (interrupcion)
MUS_PAGE    EQU 180             ; la musica: un anillo de MUS_N paginas
MUS_N       EQU 4
MUS_TC      EQU 159             ; CTC 1: 28 MHz / 16 / 159 = 11006 Hz (las pistas, a 11025)
L2B_PAGE    EQU 96              ; la otra pantalla de Layer 2 (96-105, banco 48)
UIP         EQU 94              ; ranuras de verbo, nombres de actor, inventario, indices
HEAPP       EQU 95              ; nombres de verbos, cadenas y nombres nuevos (un monton)
CHARP       EQU 14              ; fuentes (CHARS.DAT, paginas 14 y 15: el banco 7)
CHAR_MAX    EQU 2
INVP        EQU 13              ; en la pagina de las clases, por $F000: imagen de un
                                ; verbo (2 KB), dos huecos para el codigo de objetos del
                                ; inventario (1 KB) y su nombre (64 bytes)
IMGBUF      EQU $F000
CODEBUF0    EQU $F800
CODEBUF1    EQU $FC00
CODEMAX1    EQU 960
NMBUFI      EQU $FFC0

NUM_VERBS   EQU 100
NUM_INV     EQU 80
NUM_NN      EQU 150
NUM_STR     EQU 50

; en la pagina UIP (por $E000)
VSLOTS      EQU $E000           ; 100 x VSZ
VSZ         EQU 36
VS_ID       EQU 0
VS_L        EQU 1
VS_T        EQU 3
VS_R        EQU 5
VS_B        EQU 7
VS_OL       EQU 9               ; el rectangulo pintado
VS_OT       EQU 11
VS_OR       EQU 13
VS_OB       EQU 15
VS_OV       EQU 17              ; hay rectangulo pintado
VS_COL      EQU 18
VS_HI       EQU 19
VS_DIM      EQU 20
VS_BK       EQU 21
VS_TYPE     EQU 22              ; 0 texto, 1 imagen
VS_CS       EQU 23
VS_MODE     EQU 24
VS_SAVE     EQU 25
VS_KEY      EQU 26
VS_CEN      EQU 27
VS_IMGI     EQU 28              ; imgindex (2)
VS_IROOM    EQU 30              ; imagen: habitacion y objeto
VS_IOBJ     EQU 31
VS_HASN     EQU 33              ; tiene nombre
VS_HASI     EQU 34              ; tiene imagen
ANAMES      EQU VSLOTS+NUM_VERBS*VSZ    ; 13 x 32
INVOBJ      EQU ANAMES+13*32            ; 80 x 2
NNOBJ       EQU INVOBJ+2*NUM_INV        ; 150 x 2
HP_VERB     EQU NNOBJ+2*NUM_NN          ; punteros al monton: nombres de verbo (100)
HP_STR      EQU HP_VERB+2*NUM_VERBS     ; cadenas (50)
HP_NN       EQU HP_STR+2*NUM_STR        ; nombres nuevos (150)
SNDST       EQU HP_NN+2*NUM_NN          ; el sonido que ven los scripts (capa OVA)
SNDST_SZ    EQU 41
UIPCLR_END  EQU SNDST+SNDST_SZ          ; (hasta aqui lo borra VMINIT)
VIDX        EQU UIPCLR_END              ; indice de VERBIMG.DAT (2 + 8 x 100)
VIDX_MAX    EQU 100
IIDX        EQU VIDX+2+8*VIDX_MAX       ; indice de INVOBJ.DAT (2 + 2 x 1000)
RESMAP      EQU IIDX+2+2*NOBJMAX    ; pseudoRoom: la habitacion de verdad de la 128 + i
UIP_END     EQU RESMAP+128
        ASSERT UIP_END <= $10000, la pagina UIP no cabe

; Ranuras de texto (_string): actual y por defecto
ST_X        EQU 0
ST_Y        EQU 2
ST_R        EQU 4
ST_COL      EQU 6
ST_CS       EQU 7
ST_CEN      EQU 8
ST_OVH      EQU 9
ST_NTA      EQU 10
STSZ        EQU 11              ; y el por defecto detras: +STSZ
STABSZ      EQU 2*STSZ

; Las variables del motor que lleva la interfaz
VAR_KEYPRESS    EQU 0
VAR_CAMERA_POS_X EQU 2
VAR_MUSIC_TIMER EQU 14
VAR_VIRT_MOUSE_X EQU 20
VAR_VIRT_MOUSE_Y EQU 21
VAR_CUTSCENEEXIT_KEY EQU 24
VAR_TALK_ACTOR  EQU 25
VAR_SCROLL_SCRIPT EQU 27
VAR_VERB_SCRIPT EQU 32
VAR_INVENTORY_SCRIPT EQU 34
VAR_CHARINC     EQU 37
VAR_WALKTO_OBJ  EQU 38
VAR_MOUSE_X     EQU 44
VAR_MOUSE_Y     EQU 45
VAR_TIMER       EQU 46
VAR_TIMER_TOTAL EQU 47
VAR_CURSORSTATE EQU 52
VAR_USERPUT     EQU 53
VAR_TALK_STRING_Y EQU 54
VAR_TALKSTOP_KEY EQU 57

; --- llamar a una capa ---------------------------------------------------------
; A = pagina, HL = rutina. BC y DE pasan tal cual; vuelven A, HL, BC, DE y flags.
OVCALL:
        push hl
        ld hl,(SHMMU6)
        ex (sp),hl                  ; en la pila, la capa que habia (L)
        ld (SHMMU6),a
        nextreg $56,a
        call JPHL
        ex (sp),hl
        push af
        ld a,l
        ld (SHMMU6),a
        nextreg $56,a
        pop af
        pop hl
        ret
JPHL:   jp (hl)

; Como OVCALL, pero la rutina recibe A = (OVA) y HL = (OVHL) (macros OTCALL, OUCALL)
OVCALLR:
        ld (OVTGT),hl
        push hl
        ld hl,(SHMMU6)
        ex (sp),hl
        ld (SHMMU6),a
        nextreg $56,a
        ld a,(OVA)
        ld hl,(OVHL)
        call .jmp
        ex (sp),hl
        push af
        ld a,l
        ld (SHMMU6),a
        nextreg $56,a
        pop af
        pop hl
        ret
.jmp:   push hl
        ld hl,(OVTGT)
        ex (sp),hl
        ret
OVA:    db 0
OVHL:   dw 0
OVTGT:  dw 0

; Desde una capa, una rutina HL que puede dejar otra pagina en MMU6
SAFECALL:
        push hl
        ld hl,(SHMMU6)
        ex (sp),hl
        call JPHL
        ex (sp),hl
        push af
        ld a,l
        ld (SHMMU6),a
        nextreg $56,a
        pop af
        pop hl
        ret

; --- punteros largos -------------------------------------------------------------
; FARP / FARQ: direccion lineal de 24 bits (pagina = lineal >> 13; los bancos
; 2 y 5 tienen la misma direccion que su lineal, porque son las paginas 4-5 y 10-11)
; A = byte en FARP; FARP + 1
FARGET:
        push hl
        push bc
        ld hl,FARP
        call FARMAP
        ld a,(hl)
        ld hl,FARP
        call FARINC
        pop bc
        pop hl
        ret
; byte A en FARQ; FARQ + 1
FARPUT:
        push hl
        push bc
        push af
        ld hl,FARQ
        call FARMAP
        pop af
        ld (hl),a
        ld hl,FARQ
        call FARINC
        pop bc
        pop hl
        ret
; HL = puntero (3 bytes) -> MMU7 en su pagina, HL = direccion en $E000-$FFFF
FARMAP:
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld a,(hl)
        add a,a
        add a,a
        add a,a
        ld l,a
        ld a,b
        rlca
        rlca
        rlca
        and 7
        or l                        ; pagina
        ld l,a
        ld a,(SHMMU7)
        cp l
        ld a,l
        call nz,MAP7
        ld a,b
        and $1F
        or $E0
        ld h,a
        ld l,c
        ret
; el puntero HL + 1
FARINC:
        inc (hl)
        ret nz
        inc hl
        inc (hl)
        ret nz
        inc hl
        inc (hl)
        ret
; FARP = pagina A, desplazamiento HL (0-8191)
FARSET:
        ld (FARP),hl
        push af
        rrca
        rrca
        rrca
        ld c,a
        and $E0
        ld b,a
        ld a,(FARP+1)
        and $1F
        or b
        ld (FARP+1),a
        ld a,c
        and $1F
        ld (FARP+2),a
        pop af
        ret
; --- leer de un fichero ------------------------------------------------------------
; HL = nombre; FROFF (4 bytes) = desde donde; FRLEN; FRPAGE (0: FRADDR es del
; banco 2) y FRADDR (en $E000-$FFFF si hay pagina). Carry si falla.
FILEREAD:
        call FILESON
        call FOPEN
        jr c,.err
        ld (FRH),a
        ld a,(FRPAGE)
        or a
        call nz,MAP7
        ld a,(FRH)
        ld de,(FROFF)
        ld bc,(FROFF+2)
        call FSEEK
        ld a,(FRH)
        ld hl,(FRADDR)
        ld bc,(FRLEN)
        call FREAD
        ld a,(FRH)
        call FCLOSE
        call FILESOFF
        ld a,$FF                    ; (MMU2 vuelve a META)
        ld (L2CUR),a
        or a
        ret
.err:   call FILESOFF
        scf
        ret
; F_SEEK: A = fichero, BCDE = posicion desde el principio
FSEEK:
        push ix
        ld ix,0
        call ROMIN
        rst 8
        db $9F
        call ROMOUT
        pop ix
        ret
FRH:    db 0
FROFF:  ds 4
FRLEN:  dw 0
FRPAGE: db 0
FRADDR: dw 0
INVOBJNAME: db "INVOBJ.DAT",0

; FARQ = FARP
FARPQ:
        ld hl,(FARP)
        ld (FARQ),hl
        ld a,(FARP+2)
        ld (FARQ+2),a
        ret

; --- variables ----------------------------------------------------------------
; (van dentro de VMDATA: VMINIT las pone a 0 y despues pone los valores de
; partida)
