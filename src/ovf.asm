; ===========================================================================
;  Capa OVF (pagina OVF_PAGE, en $C000): efectos de paleta y de pantalla
;  (model.World: set_pal_color, darken, cycle_palette, set_shake/update_shake)
;
;  La paleta que se ve esta en META+32 (los dos bytes de NR $44 de cada color);
;  los actores la copian a sus bancos al componerse (COMPOSE), asi que basta con
;  cambiarla aqui y en los registros de Layer 2. darkenPalette parte de la de 8
;  bits de la habitacion (META+META_PAL8) y los ciclos de color estan en
;  META+META_CYCL (16 huecos: delay (2), flags, primero, ultimo).
; ===========================================================================

VAR_TIMER_NEXT EQU 19
META_PAL8   EQU 7168
META_CYCL   EQU 7936

; roomOps 4, 5, 6, 8, 10 y 11: ROSUB y los parametros en P0..
F_ROOMOPS:
        call METAIN
        ld a,(ROSUB)
        cp 4
        jr z,.pal
        cp 5
        jr z,.son
        cp 6
        jr z,.soff
        cp 8
        jr z,.int
        cp 10
        jr z,.eff
        cp 11
        jp nz,METAOUT
        ld hl,(P0)                  ; rgbRoomIntensity(P0, P1, P2; colores P4..P5)
        ld (DKR),hl
        ld hl,(P1)
        ld (DKG),hl
        ld hl,(P2)
        ld (DKB),hl
        ld a,(P4)
        ld b,a
        ld a,(P5)
        call DARKEN
        jp METAOUT
.int:   ld a,(P0)                   ; roomIntensity(P0; colores P1..P2)
        ld l,a
        ld h,0
        ld (DKR),hl
        ld (DKG),hl
        ld (DKB),hl
        ld a,(P1)
        ld b,a
        ld a,(P2)
        call DARKEN
        jp METAOUT
.pal:   ld a,(P0)                   ; setPalColor(P4, P0, P1, P2)
        ld (CR),a
        ld a,(P1)
        ld (CG),a
        ld a,(P2)
        ld (CB),a
        ld a,(P4)
        call PALSET
        jp METAOUT
.son:   ld a,1                      ; temblor (setShake)
        jr .sh
.soff:  xor a
.sh:    ld (SHKON),a
        xor a
        ld (SHKF),a
        ld (SHAKEY),a
        jp METAOUT
.eff:   ld hl,(P0)                  ; el efecto de las transiciones (0: fadeIn ya, no
        ld a,h                      ; hace falta: no se tapa la pantalla)
        or l
        jp z,METAOUT
        ld (SWEFF),hl
        jp METAOUT

; MMU2 en META (por si estaba en Layer 2) y despues como estaba
METAIN:
        ld a,META_PAGE
        nextreg $52,a
        ret
METAOUT:
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; El color A de la paleta que se ve = (CR, CG, CB) de 8 bits: META+32 y NR $44
PALSET:
        ld (PSI),a
        ld a,(CR)
        call C3
        ld (R3),a
        ld a,(CG)
        call C3
        ld (G3),a
        ld a,(CB)
        call C3
        ld c,a                      ; C = b
        ld a,(R3)                   ; hi = r << 5 | g << 2 | b >> 1
        rrca
        rrca
        rrca
        and $E0
        ld e,a
        ld a,(G3)
        add a,a
        add a,a
        or e
        ld e,a
        ld a,c
        srl a
        or e
        ld h,a
        ld a,c                      ; lo = b & 1
        and 1
        ld l,a
        ld a,h                      ; el transparente no: azul 7 -> 5
        cp L2_TRANSP
        jr nz,.ok
        dec h
        ld l,1
.ok:    ld a,(PSI)
        ex de,hl                    ; DE = hi, lo
        ld l,a
        ld h,0
        add hl,hl
        ld bc,META+32
        add hl,bc
        ld (hl),d
        inc hl
        ld (hl),e
        nextreg $43,%00010000       ; la primera paleta de Layer 2
        nextreg $40,a
        ld a,d
        nextreg $44,a
        ld a,e
        nextreg $44,a
        ret

; A = (A * 7 + 127) / 255: de 8 bits a 3
C3:
        ld e,a
        ld d,7
        mul d,e
        ld hl,127
        add hl,de
        ld de,255
        xor a
.d:     or a
        sbc hl,de
        jr c,.r
        inc a
        jr .d
.r:     ret

; darkenPalette: los colores B..A de la habitacion por DKR, DKG, DKB / 255 (como
; mucho 255); nada si A < B o si no hay habitacion
DARKEN:
        ld (DKE),a
        ld a,(CURROOM)
        or a
        ret z
        ld a,(DKE)
        cp b
        ret c
        ld a,b
.lp:    ld (DKI),a
        ld l,a                      ; HL = META + META_PAL8 + 3 * i
        ld h,0
        ld e,l
        ld d,h
        add hl,hl
        add hl,de
        ld de,META+META_PAL8
        add hl,de
        push hl
        ld a,(hl)
        ld de,(DKR)
        call SCALE
        ld (CR),a
        pop hl
        inc hl
        push hl
        ld a,(hl)
        ld de,(DKG)
        call SCALE
        ld (CG),a
        pop hl
        inc hl
        ld a,(hl)
        ld de,(DKB)
        call SCALE
        ld (CB),a
        ld a,(DKI)
        call PALSET
        ld a,(DKI)
        ld hl,DKE
        cp (hl)
        ret z
        inc a
        jr .lp

; A = min(A * DE / 255, 255) (A de 8 bits, DE de 16 sin signo)
SCALE:
        ld b,a                      ; C:HL = A * DE (24 bits)
        ld (SCD),de
        ld e,b
        ld a,(SCD+1)
        ld d,a
        mul d,e                     ; DE = A * alto
        ex de,hl
        ld a,(SCD)
        ld d,a
        ld e,b
        mul d,e                     ; DE = A * bajo
        ld c,h                      ; C:HL = (A * alto) << 8 + A * bajo
        ld h,l
        ld l,0
        add hl,de
        jr nc,.nc
        inc c
.nc:    xor a                       ; / 255 (division con resto de 9 bits)
        ld b,24
.l:     add hl,hl
        rl c
        rla
        jr c,.sub
        cp 255
        jr c,.n
.sub:   sub 255
        inc l
.n:     djnz .l
        ld a,c                      ; mas de 255: 255
        or h
        ld a,l
        ret z
        ld a,255
        ret

; --- un paso (despues de UITEXT, antes de los actores): ciclos y temblor -----------
F_STEP:
        ld a,(SHKON)                ; temblor: la posicion siguiente, o a 0
        or a
        jr z,.soff
        ld a,(SHKF)
        inc a
        and 7
        ld (SHKF),a
        ld hl,SHAKETAB
        add hl,a
        ld a,(hl)
        ld (SHAKEY),a
        jr .cyc
.soff:  ld a,(SHKF)
        or a
        jr z,.cyc
        xor a
        ld (SHKF),a
        ld (SHAKEY),a
.cyc:   ld a,(CURROOM)              ; ciclos de color (cyclePalette)
        or a
        ret z
        ld hl,(VARS+2*VAR_TIMER)    ; VAR_TIMER, o VAR_TIMER_NEXT si es mayor
        ld de,(VARS+2*VAR_TIMER_NEXT)
        call CPS16
        jr nc,.a
        ex de,hl
.a:     ld (CYADD),hl
        call METAIN
        xor a
.lp:    ld (CYI),a
        ld e,a                      ; HL = META + META_CYCL + 5 * i
        ld d,5
        mul d,e
        ld hl,META+META_CYCL
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr z,.next
        ld (CYD),de
        ld a,(hl)
        ld (CYF),a
        inc hl
        ld a,(hl)
        ld (CYS),a
        inc hl
        ld b,(hl)
        ld a,b
        ld (CYE),a
        ld a,(CYS)                  ; primero > ultimo: nada
        cp b
        jr z,.go
        jr nc,.next
.go:    ld a,(CYI)                  ; contador += lo que toca (16 bits)
        add a,a
        ld hl,FXCNT
        add hl,a
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(CYADD)
        add hl,de
        ld de,(CYD)
        call CPU16
        jr c,.st
.md:    or a                        ; contador %= delay
        sbc hl,de
        call CPU16
        jr nc,.md
        push hl
        call ROTATE
        pop hl
.st:    ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
.next:  ld a,(CYI)
        inc a
        cp 16
        jr nz,.lp
        jp METAOUT

; Gira los colores CYS..CYE de META+32 (hacia delante si CYF no tiene el bit 1) y
; los escribe en Layer 2
ROTATE:
        ld a,(CYS)
        ld hl,CYE
        sub (hl)
        ret z
        neg
        add a,a                     ; BC = 2 * (ultimo - primero)
        ld c,a
        ld b,0
        jr nc,.b
        inc b
.b:     ld a,(CYS)
        call PALADDR
        ld (RTS),hl
        ld a,(CYE)
        call PALADDR
        ld (RTE),hl
        ld a,(CYF)
        bit 1,a
        jr nz,.back
        ld hl,(RTE)                 ; adelante: el ultimo pasa a ser el primero
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        ld de,(RTE)                 ; LDDR desde el ultimo byte del penultimo
        inc de
        ld hl,(RTE)
        dec hl
        lddr
        pop de
        ld hl,(RTS)
        ld (hl),e
        inc hl
        ld (hl),d
        jr .out
.back:  ld hl,(RTS)                 ; atras: el primero pasa a ser el ultimo
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        ld de,(RTS)
        ld hl,(RTS)
        inc hl
        inc hl
        ldir
        pop de
        ld hl,(RTE)
        ld (hl),e
        inc hl
        ld (hl),d
.out:   nextreg $43,%00010000       ; a Layer 2: CYS..CYE
        ld a,(CYS)
        nextreg $40,a
        ld hl,(RTS)
        ld a,(CYE)
        ld b,a
        ld a,(CYS)
        sub b
        neg
        inc a
        ld b,a
.w:     ld a,(hl)
        inc hl
        nextreg $44,a
        ld a,(hl)
        inc hl
        nextreg $44,a
        djnz .w
        ret

; HL = META + 32 + 2 * A
PALADDR:
        ld l,a
        ld h,0
        add hl,hl
        ld de,META+32
        add hl,de
        ret

; Al cargar una habitacion: los contadores de los ciclos a 0
F_ROOMINIT:
        ld hl,FXCNT
        ld b,32
.z:     ld (hl),0
        inc hl
        djnz .z
        ret

SHAKETAB: db 0,2,4,2,0,4,6,2
L2_TRANSP EQU $E3
FXCNT:  ds 32                       ; contadores de los 16 ciclos
CYADD:  dw 0
CYD:    dw 0
CYI:    db 0
CYF:    db 0
CYS:    db 0
CYE:    db 0
RTS:    dw 0
RTE:    dw 0
DKR:    dw 0
DKG:    dw 0
DKB:    dw 0
DKI:    db 0
DKE:    db 0
CR:     db 0
CG:     db 0
CB:     db 0
PSI:    db 0
R3:     db 0
G3:     db 0
SCD:    dw 0

; --- transiciones (fadeOut / fadeIn) con la otra pantalla de Layer 2 (B) ----------
; Al salir de una habitacion (startScene), el efecto de salida (SWEFF+1) en la
; pantalla que se ve (A): 128 disolver a negro en bloques de 8x4, 1 el iris (anillos
; de 8x8 de fuera adentro); los demas, de golpe. Despues se ve B (la habitacion en
; negro y sus verbos) y la habitacion nueva se pinta en A sin verse. Al final
; del paso (F_FADEIN), el efecto de entrada (SWEFF) pasa A a B, y se vuelve a ver A.
; Solo se ve: la maquina virtual y lo que queda en A no cambian.
F_FADEOUT:
        ld a,(SWEFF)                ; _newEffect: el de entrada se decide aqui (el script
        ld (NEWEFF),a               ; de entrada de la habitacion nueva puede cambiarlo)
        ld a,(HIDDEN)
        or a
        ret nz
        ld a,(CURROOM)              ; (sin habitacion no hay nada que tapar)
        or a
        ret z
        ld a,(SWEFF+1)
        or a
        ret z
        ld (FXE),a
        call HIDESPR                ; los actores (el cursor lo pone la interrupcion)
        ld hl,VFLUSH                ; (los verbos pintados hasta ahora, tambien en A)
        ld a,OVT_PAGE
        call OVCALL
        xor a                       ; a negro, en A
        ld (FXCOPY),a
        ld a,(FXE)
        call EFFECT
        call BBLACK
        nextreg $12,L2B_PAGE/2      ; se ve B
        ld a,1
        ld (HIDDEN),a
        ret

F_FADEIN:
        di                          ; el scroll y el corte de la habitacion nueva
        call COPPERSET
        ei
        ld hl,VSYNCB                ; y los verbos de ahora (pintados en A), en B
        ld a,OVT_PAGE
        call OVCALL
        ld a,1                      ; de A a B
        ld (FXCOPY),a
        ld a,(NEWEFF)
        call EFFECT
        nextreg $12,L2_BANK         ; se vuelve a ver A
        xor a
        ld (HIDDEN),a
        ret

; El efecto A (128 disolver, 1 iris; los demas nada) con FXCOPY
EFFECT:
        cp 128
        jp z,DISSOLVE
        cp 1
        jp z,IRIS
        ret

; FXS0 = la columna de Layer 2 de la izquierda de la vista / 8
FXSTART:
        ld hl,(SCRL)
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld a,l
        ld (FXS0),a
        ret

; El bloque de 8 columnas desde la x de pantalla FXBX * 8, filas FXY..FXY+FXN-1 de
; la habitacion: a negro en A (FXCOPY = 0) o de A a B (1)
BLOCK:
        ld a,(FXS0)
        ld hl,FXBX
        add a,(hl)
        cp 40
        jr c,.k
        sub 40
.k:     ld c,a                      ; bloque de columnas de Layer 2 (0..39)
        srl a
        srl a                       ; pagina (4 bloques por pagina)
        ld b,a
        add a,L2_PAGE
        nextreg $52,a
        ld a,(FXCOPY)
        or a
        jr z,.nb
        ld a,b
        add a,L2B_PAGE
        call MAP7
.nb:    ld a,c
        and 3
        add a,a
        add a,a
        add a,a
        ld (FXCH),a
        ld a,(FXY)
        add a,ROOM_Y0
        ld (FXR),a
        ld b,8
.col:   push bc
        ld a,(FXCH)
        add a,$40
        ld h,a
        ld a,(FXR)
        ld l,a
        ld a,(FXCOPY)
        or a
        jr z,.blk
        ld a,(FXCH)
        add a,$E0
        ld d,a
        ld e,l
        ld a,(FXN)
        ld c,a
        ld b,0
        ldir
        jr .nx
.blk:   ld a,(FXN)
        ld b,a
.z:     ld (hl),0
        inc l
        djnz .z
.nx:    ld hl,FXCH
        inc (hl)
        pop bc
        djnz .col
        ret

; Espera a la imagen siguiente
WAITFRAME:
        ld a,(FRAMES)
        ld b,a
.w:     ld a,(FRAMES)
        cp b
        jr z,.w
        ret

; Disolver en bloques de 8x4 en un orden al azar (un LFSR de 11 bits pasa por 1..2047)
DISSOLVE:
        call FXSTART
        ld a,(MAINH)                ; bloques: 40 x (MAINH / 4)
        srl a
        srl a
        ld e,a
        ld d,40
        mul d,e
        ld (FXNB),de
        ld a,4
        ld (FXN),a
        ld hl,1
        ld (LFSR),hl
        ld hl,2047
        ld (FXLEFT),hl
        ld a,FXPERF
        ld (FXCNTF),a
.lp:    ld hl,(LFSR)                ; el siguiente (x^11 + x^9 + 1)
        srl h
        rr l
        jr nc,.nt
        ld a,h
        xor $05
        ld h,a
.nt:    ld (LFSR),hl
        dec hl
        ld de,(FXNB)
        call CPU16
        jr nc,.skip
        ld b,0                      ; fila = n / 40, columna = n % 40
.dv:    ld de,40
        call CPU16
        jr c,.dd
        or a
        sbc hl,de
        inc b
        jr .dv
.dd:    ld a,l
        ld (FXBX),a
        ld a,b
        add a,a
        add a,a
        ld (FXY),a
        call BLOCK
        ld hl,FXCNTF
        dec (hl)
        jr nz,.skip
        ld (hl),FXPERF
        call WAITFRAME
.skip:  ld hl,(FXLEFT)
        dec hl
        ld (FXLEFT),hl
        ld a,h
        or l
        jr nz,.lp
        jp FXEND

; El iris: 13 anillos de bloques de 8x8 de fuera adentro, una imagen cada uno
IRIS:
        call FXSTART
        ld a,(MAINH)
        srl a
        srl a
        srl a
        ld (FXR8),a                 ; filas de bloques
        ld a,8
        ld (FXN),a
        xor a
.ring:  ld (FXK),a
        ld a,(FXR8)                 ; fila de arriba (k) y de abajo (filas - 1 - k)
        dec a
        ld hl,FXK
        sub (hl)
        ld (FXKB),a                 ; (puede ser < k: entonces no hay columnas)
        ld a,(FXK)
        ld hl,FXR8
        cp (hl)
        jr nc,.nt
        call .row
.nt:    ld a,(FXKB)
        bit 7,a
        jr nz,.nb
        call .row
.nb:    ld a,(FXK)                  ; columnas k y 39 - k, filas k..filas-1-k
        call .colk
        ld a,(FXK)
        neg
        add a,39
        call .colk
        ld b,IRISW                  ; imagenes por anillo
.wf:    push bc
        call WAITFRAME
        pop bc
        djnz .wf
        ld a,(FXK)
        inc a
        cp 13
        jr nz,.ring
        jp FXEND
; la fila A de bloques, columnas k..39-k
.row:   add a,a
        add a,a
        add a,a
        ld (FXY),a
        ld a,(FXK)
.rl:    ld (FXBX),a
        ld b,a
        ld a,(FXK)
        neg
        add a,39
        cp b
        ret c
        call BLOCK
        ld a,(FXBX)
        inc a
        jr .rl
; la columna de bloques A, filas k..filas-1-k
.colk:  ld (FXBX),a
        ld a,(FXK)
.cl:    ld b,a
        ld a,(FXKB)
        cp b
        ret c
        bit 7,a
        ret nz
        ld a,b
        add a,a
        add a,a
        add a,a
        ld (FXY),a
        push bc
        call BLOCK
        pop bc
        ld a,b
        inc a
        jr .cl

; MMU2 otra vez en lo suyo
FXEND:
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; B: la zona de la habitacion en negro (los verbos ya estan: se pintan alli)
BBLACK:
        xor a
.pg:    ld (FXP),a
        add a,L2B_PAGE
        call MAP7
        ld hl,$E000+ROOM_Y0
        ld b,32
.c:     push bc
        push hl
        ld a,(MAINH)
        ld b,a
.z:     ld (hl),0
        inc l
        djnz .z
        pop hl
        inc h
        pop bc
        djnz .c
        ld a,(FXP)
        inc a
        cp 10
        jr nz,.pg
        jp FXEND

; Al arrancar: B entera en negro
F_INITB:
        xor a
.pg:    ld (FXP),a
        add a,L2B_PAGE
        call MAP7
        ld hl,$E000
        ld de,$E001
        ld bc,$1FFF
        ld (hl),0
        ldir
        ld a,(FXP)
        inc a
        cp 10
        jr nz,.pg
        ret

IRISW   EQU 1                       ; imagenes por anillo del iris
FXPERF  EQU 160                     ; bloques de 8x4 por imagen al disolver
FXE:    db 0
NEWEFF: db 0
FXCOPY: db 0
FXS0:   db 0
FXBX:   db 0
FXY:    db 0
FXN:    db 0
FXR:    db 0
FXCH:   db 0
FXNB:   dw 0
LFSR:   dw 0
FXLEFT: dw 0
FXCNTF: db 0
FXR8:   db 0
FXK:    db 0
FXKB:   db 0
FXP:    db 0

; --- arranque de la maquina virtual (VMINIT: lo demas, despues, OBJ.DAT y SCRIPTS.DAT) ---
; (variable, valor) de resetScummVars: tools/vm.py INIT_VARS
INITVARS:
        db 9
        dw 11
        db 37
        dw 4
        db 40
        dw 1400
        db 48
        dw 3
        db 49
        dw 19
        db 51
        dw 1
        db 54
        dw -$50
        db 59
        dw 3
        db 67
        dw 3
        db 74
        dw 1225
        db $FF

F_VMINIT:
        ld hl,VMDATA                ; todo a 0
        ld de,VMDATA+1
        ld bc,VMDATA_END-VMDATA-1
        ld (hl),0
        ldir
        ld hl,U_CASTCLR             ; y las fichas de los actores: initActor(-1)
        call OVUCALL
        ld hl,K_CACHECLR            ; (sin dibujos guardados)
        ld a,OVK_PAGE
        call OVCALL
        ld ix,ACTOR
        xor a
        ld (ACTN),a
        inc a
.ia:    ld (ACTN),a
        call INITREC
        call ACTSYNC
        ld a,(ACTN)
        inc a
        cp NACT
        jr nz,.ia
        ld a,$FF
        ld (CURSLOT),a
        ld (CSIDX),a
        ld hl,$1234
        ld (SEED),hl
        ld hl,1                     ; el protagonista es el actor 1
        ld (VARS+2*VAR_EGO),hl
        ld hl,MSGBUF
        ld (MSGP),hl
        ld hl,INITVARS              ; las variables que pone el motor (vm.py INIT_VARS)
.iv:    ld e,(hl)
        inc hl
        ld a,e
        cp $FF
        jr z,.ivx
        ld d,0
        ex de,hl
        add hl,hl
        ld bc,VARS
        add hl,bc
        ex de,hl
        ldi
        ldi
        jr .iv
.ivx:
        ld a,144
        ld (MAINH),a
        ld a,1
        ld (FOLLOWS),a
        ld a,$FF
        ld (L2CUR),a
        ld hl,STAB                  ; las ranuras de texto: (2, 5), derecha 319, color 15
        ld b,12
.st:    ld (hl),2
        inc hl
        ld (hl),0
        inc hl
        ld (hl),5
        inc hl
        ld (hl),0
        inc hl
        ld (hl),319 & $FF
        inc hl
        ld (hl),319 >> 8
        inc hl
        ld (hl),15
        ld de,STSZ-6
        add hl,de
        djnz .st
        ld a,UIP                    ; verbos, nombres, inventario y punteros a 0
        call MAP7
        ld hl,$E000
        ld de,$E001
        ld bc,UIPCLR_END-$E000-1
        ld (hl),0
        ldir
        ld a,HEAPP                  ; el monton, vacio
        call MAP7
        ld hl,2
        ld ($E000),hl
        call LOADOBJS
        ret c
        jp LOADSCRIPTS

; --- lo que solo se usa al arrancar, al cambiar de juego o en las pruebas (antes en
; la memoria principal) -----------------------------------------------------------

; OBJ.DAT: numero, duenos, estados (banco 2) y clases (CLASS_PAGE)
LOADOBJS:
        call FILESON
        ld hl,OBJNAME
        call FOPEN
        jr c,.err
        ld (LHANDLE),a
        ld hl,NOBJG
        ld bc,2
        call FREAD
        ld hl,(NOBJG)
        ld de,NOBJMAX+1
        call CPU16
        jr nc,.cerr
        ld a,(LHANDLE)
        ld hl,OBJOWN
        ld bc,(NOBJG)
        call FREAD
        ld a,(LHANDLE)
        ld hl,OBJST
        ld bc,(NOBJG)
        call FREAD
        ld a,CLASS_PAGE
        call MAP7
        ld hl,(NOBJG)
        add hl,hl
        add hl,hl
        ld b,h
        ld c,l
        ld a,(LHANDLE)
        ld hl,$E000
        call FREAD
        ld a,(LHANDLE)
        call FCLOSE
        jp FILESOFF                 ; (sin acarreo)
.cerr:  ld a,(LHANDLE)
        call FCLOSE
.err:   call FILESOFF
        scf
        ret

; SCRIPTS.DAT en las paginas de SPAGES
LOADSCRIPTS:
        call FILESON
        ld hl,SCRNAME
        call FOPEN
        jr c,.err
        ld (LHANDLE),a
        ld hl,SPAGES
        ld b,16
.pg:    push bc
        push hl
        ld a,(hl)
        call MAP7
        ld a,(LHANDLE)
        ld hl,$E000
        ld bc,$2000
        call FREAD
        ld a,b
        pop hl
        pop bc
        inc hl
        cp $20
        jr nz,.end
        djnz .pg
.end:   ld a,(LHANDLE)
        call FCLOSE
        jp FILESOFF
.err:   call FILESOFF
        scf
        ret

SCRNAME: db "SCRIPTS.DAT",0
OBJNAME: db "OBJ.DAT",0

; Al arrancar: los registros del Next, el cursor y las dos pantallas en negro
F_BOOT:
        nextreg $07,3               ; 28 MHz
        nextreg $68,%10000000       ; ULA apagada
        nextreg $4A,0               ; color de fondo: negro
        nextreg $14,$E3             ; color transparente
        nextreg $6B,0               ; sin tilemap
        nextreg $15,%00100011       ; sprites visibles y sobre el borde (recorte con x
                                    ; doble: 0..159 son 0..319), orden S L U
        nextreg $1C,%00000011       ; reinicia los indices de recorte
        nextreg $18,0               ; Layer 2: toda la pantalla
        nextreg $18,159
        nextreg $18,0
        nextreg $18,255
        nextreg $19,0               ; sprites: toda la pantalla
        nextreg $19,159
        nextreg $19,0
        nextreg $19,255
        nextreg $12,L2_BANK
        nextreg $70,%00010000       ; Layer 2 en 320x256
        nextreg $16,0
        nextreg $71,0
        nextreg $17,0
        nextreg $4B,0               ; indice transparente de los sprites
        call HIDESPR
        call CURSORINIT
        call L2CLEAR
        jp F_INITB

; El cursor: su patron (4 bits) y sus colores
CURSORINIT:
        ld bc,$303B
        ld a,CURSOR_PAT>>1|$80      ; mitad alta del hueco 63
        out (c),a
        ld hl,CURSOR
        ld bc,$805B
        otir
        nextreg $43,%00100000       ; paleta de sprites
        nextreg $40,CURSOR_BANK*16
        ld hl,CURPAL
        ld b,8
.p:     ld a,(hl)
        inc hl
        nextreg $44,a
        ld a,(hl)
        inc hl
        nextreg $44,a
        djnz .p
        ret

        INCLUDE "gen/cursor.asm"

; El juego de la carpeta en la que se esta: sus datos y la maquina virtual desde el
; script 1. Carry si falla.
F_GAMEINIT:
        call LOADGAME
        ret c
        ld hl,SNDINIT               ; los efectos (SOUNDS.DAT), el DAC y el CTC
        ld a,OVA_PAGE
        call OVCALL
        ld a,(GAMEBUF+5)            ; costume del protagonista
        call LOADCOST
        ret c
        ld hl,CHARSNAME             ; las fuentes (si las hay)
        ld a,CHARP
        ld b,CHAR_MAX
        call LOADPAGES
        ld hl,LOADIDX               ; los indices de VERBIMG.DAT e INVOBJ.DAT (OVU)
        call OVUCALL
        xor a
        ld (CURRI),a
        call FINDCOST
        jp BOOT                     ; la maquina virtual y el script 1

; GAME.DAT: primera habitacion, costume del protagonista y habitaciones
LOADGAME:
        nextreg $52,10
        nextreg $53,11
        ld hl,GAMENAME
        call FOPEN
        jr c,.err
        ld (LHANDLE),a
        ld hl,GAMEBUF
        ld bc,256
        call FREAD
        ld a,(LHANDLE)
        call FCLOSE
        ld a,(SHMMU2)
        nextreg $52,a
        nextreg $53,SPR_PAGE
        ld hl,GAMEBUF
        ld a,(hl)
        cp 'S'
        jr nz,.bad
        or a
        ret
.err:   ld a,(SHMMU2)
        nextreg $52,a
        nextreg $53,SPR_PAGE
.bad:   scf
        ret

; CURCI = posicion del costume del protagonista en la lista
FINDCOST:
        xor a
        ld (CURCI),a
        call COSTLIST
        ld a,c
        or a
        ret z
        ld b,c
        ld c,0
        ld a,(GAMEBUF+5)
.lp:    cp (hl)
        jr z,.got
        inc hl
        inc c
        djnz .lp
        ret
.got:   ld a,c
        ld (CURCI),a
        ret

; Rutinas sueltas para las pruebas: TFUNC y argumentos en TARGS
F_TESTFUNC:
        ld ix,ACTOR
        ld a,1                      ; (las cajas, como para el jugador)
        ld (AJPLAY),a
        ld a,(TFUNC)
        cp 1
        jr nz,.f2
        ld hl,TARGS                 ; CLOSEST(st, en, p) -> LRX, LRY
        ld de,LST
        ld bc,12
        ldir
        call CLOSEST
        ld hl,(LRX)
        ld (TRES),hl
        ld hl,(LRY)
        ld (TRES+2),hl
        ret
.f2:    cp 2
        jr nz,.f3
        ld hl,(TARGS)               ; ADJXY(x, y)
        ld (AJX),hl
        ld hl,(TARGS+2)
        ld (AJY),hl
        call ADJXY
        ld (TRES+4),a
        ld hl,(AJRX)
        ld (TRES),hl
        ld hl,(AJRY)
        ld (TRES+2),hl
        ret
.f3:    cp 3
        jr nz,.f4
        ld hl,(TARGS)               ; DEHL = (TARGS) * (TARGS+4)
        ld de,(TARGS+2)
        ld bc,(TARGS+4)
        call MULS32_16
        ld (TRES),hl
        ld (TRES+2),de
        ret
.f4:    cp 4
        jr nz,.f5
        ld hl,(TARGS+4)             ; DEHL = (TARGS) / (TARGS+4..7)
        ld (DV),hl
        ld hl,(TARGS+6)
        ld (DV+2),hl
        ld hl,(TARGS)
        ld de,(TARGS+2)
        call DIVS32
        ld (TRES),hl
        ld (TRES+2),de
        ret
.f5:    cp 5
        jr nz,.f6
        ld hl,(TARGS)               ; INBOX(caja, x, y)
        ld (PX),hl
        ld hl,(TARGS+2)
        ld (PY),hl
        ld a,(TARGS+4)
        call INBOX
        sbc a,a
        ld (TRES),a
        ret
.f6:    cp 6
        jr nz,.f7
        ld a,(TARGS+1)              ; NEXTBOX(desde, hasta)
        ld (NBTO),a
        ld a,(TARGS)
        call NEXTBOX
        ld (TRES),a
        ret
.f7:    cp 7
        jr nz,.f8
        ld a,(TARGS)                ; copia la tira de trabajo a SPRBUF
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,(STRIPT)
        add hl,de
        ld a,(hl)
        add a,STRIP_PAGE
        call MAP7                   ; (en MMU7: esto va en la capa OVF, en MMU6)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld de,$2000                 ; (la tabla da direcciones de MMU6)
        add hl,de
        ld de,SPRBUF
        ld bc,(RREC)
        ldir
        ret
.f8:    cp 8
        jr nz,.f9
        ld hl,(TARGS)               ; OBJAT(x, y)
        ld (OAX),hl
        ld hl,(TARGS+2)
        ld (OAY),hl
        call OBJAT
        ld (TRES),a
        ret
.f9:    cp 9
        jr nz,.f10
        ld a,CLASS_PAGE             ; las clases, a SPRBUF
        call MAP7
        ld hl,(NOBJG)
        add hl,hl
        add hl,hl
        ld b,h
        ld c,l
        ld a,b
        or c
        ret z
        ld hl,$E000
        ld de,SPRBUF
        ldir
        ret
.f10:   cp 10                       ; la pagina TARGS a SPRBUF
        jr nz,.f11
        ld a,(TARGS)
        call MAP7
        ld hl,$E000
        ld de,SPRBUF
        ld bc,$2000
        ldir
        ret
.f11:   cp 11                       ; la pagina TARGS llena con TARGS+1
        jr nz,.f12
        ld a,(TARGS)
        call MAP7
        ld a,(TARGS+1)
        ld hl,$E000
        ld de,$E001
        ld bc,$1FFF
        ld (hl),a
        ldir
        ret
.f12:   cp 12                       ; el actor solo compuesto TARGS veces: frames
        ret nz
        ld a,(FRAMES)
        ld (TRES),a
        ei
.cl:    call EGOCOMP
        ld hl,TARGS
        dec (hl)
        jr nz,.cl
        ld a,(FRAMES)
        ld hl,TRES
        sub (hl)
        ld (hl),a
        ret

        INCLUDE "fpath.asm"
        INCLUDE "boxmat.asm"

OVF_END:
        ASSERT OVF_END <= $E000, la capa OVF no cabe
