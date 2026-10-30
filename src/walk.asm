; ===========================================================================
;  Andar: un paso por eje, calcMovementFactor, walkActor y putActor
;  (sigue a actor.asm; el actor va en IX).
; ===========================================================================

; Un paso en un eje: pos:frac += (delta >> 8) * 255
; B = desplazamiento del delta (32 bits), C = de la fraccion, E = de la posicion
STEPAX:
        ld a,c
        ld (SAFRAC),a
        ld a,e
        ld (SAPOS),a
        push ix
        pop hl
        ld a,b
        add hl,a
        call LD32                   ; DEHL = delta = [b0 b1 b2 b3]
        ld a,h                      ; q = delta >> 8 = [b1 b2 b3 signo]
        ld (T1),a
        ld a,e
        ld (T1+1),a
        ld a,d
        ld (T1+2),a
        rla
        sbc a,a
        ld (T1+3),a
        ld hl,(T1)                  ; q * escala
        ld de,(T1+2)
        ld a,(SASCALE)
        ld c,a
        ld b,0
        call MULS32_16
        ld (T2),hl
        ld (T2+2),de
        push ix                     ; frac += parte baja
        pop hl
        ld a,(SAFRAC)
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        dec hl
        push hl
        ex de,hl
        ld bc,(T2)
        add hl,bc
        ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
        push af                     ; el acarreo, para la posicion
        push ix
        pop hl
        ld a,(SAPOS)
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        dec hl
        pop af
        ex de,hl
        ld bc,(T2+2)
        adc hl,bc
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        ret

; calcMovementFactor(CMNX, CMNY) -> A = actorWalkStep (Z si no se mueve)
CALCMOVE:
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        ld de,(CMNX)
        or a
        sbc hl,de
        jr nz,.go
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        ld de,(CMNY)
        or a
        sbc hl,de
        jr nz,.go
        xor a
        ret
.go:    ld hl,(CMNX)
        ld e,(ix+A_X)
        ld d,(ix+A_X+1)
        or a
        sbc hl,de
        ld (CMDX),hl
        ld hl,(CMNY)
        ld e,(ix+A_Y)
        ld d,(ix+A_Y+1)
        or a
        sbc hl,de
        ld (CMDY),hl
        ld hl,0                     ; dyf = speedy << 16
        call GETSPY
        ld e,a
        ld d,0
        ld a,(CMDY+1)
        bit 7,a
        call nz,NEG32
        ld (CMYF),hl
        ld (CMYF+2),de
        ld bc,(CMDX)                ; dxf = dyf * dx
        call MULS32_16
        push hl
        ld hl,(CMDY)
        ld a,h
        or l
        pop hl
        jr z,.dy0
        ld bc,(CMDY)
        call DIVS32_16              ; dxf /= dy
        jr .sx
.dy0:   push hl
        ld hl,0
        ld (CMYF),hl
        ld (CMYF+2),hl
        pop hl
.sx:    ld (CMXF),hl
        ld (CMXF+2),de
        call ABS32                  ; |dxf| / 65536 > speedx ? (la parte entera)
        ld a,d
        or a
        jr nz,.clampx
        call GETSPX
        cp e
        jr nc,.store
.clampx:
        ld hl,0
        call GETSPX
        ld e,a
        ld d,0
        ld a,(CMDX+1)
        bit 7,a
        call nz,NEG32
        ld (CMXF),hl
        ld (CMXF+2),de
        ld bc,(CMDY)                ; dyf = dxf * dy
        call MULS32_16
        push hl
        ld hl,(CMDX)
        ld a,h
        or l
        pop hl
        jr z,.dx0
        ld bc,(CMDX)
        call DIVS32_16              ; dyf /= dx
        ld (CMYF),hl
        ld (CMYF+2),de
        jr .store
.dx0:   ld (CMYF),hl
        ld (CMYF+2),de
        ld hl,0
        ld (CMXF),hl
        ld (CMXF+2),hl
.store: ld a,(ix+A_X)
        ld (ix+A_CURX),a
        ld a,(ix+A_X+1)
        ld (ix+A_CURX+1),a
        ld a,(ix+A_Y)
        ld (ix+A_CURY),a
        ld a,(ix+A_Y+1)
        ld (ix+A_CURY+1),a
        ld hl,(CMNX)
        ld (ix+A_NEXTX),l
        ld (ix+A_NEXTX+1),h
        ld hl,(CMNY)
        ld (ix+A_NEXTY),l
        ld (ix+A_NEXTY+1),h
        push ix
        pop de
        ld hl,A_DXF
        add hl,de
        ex de,hl
        ld hl,CMXF
        ld bc,8                     ; dxf y dyf van seguidos
        ldir
        xor a
        ld (ix+A_XFRAC),a
        ld (ix+A_XFRAC+1),a
        ld (ix+A_YFRAC),a
        ld (ix+A_YFRAC+1),a
        call CMFACE
        ld (ix+A_TFACE),l
        ld (ix+A_TFACE+1),h
        jp WALKSTEP

; Hacia donde mira al andar (ScummVM 2.8): |dy| * 3 > |dx| ? (dyf > 0 ? 180 : 0)
; : (dxf > 0 ? 90 : 270)
CMFACE:
        ld hl,(CMDY)
        call ABSHL
        ld d,h
        ld e,l
        add hl,hl
        add hl,de                   ; |dy| * 3
        ex de,hl                    ; DE = |dy| * 3
        ld hl,(CMDX)
        call ABSHL
        call CPU16                  ; |dy|*3 > |dx|  <=>  |dx| < |dy|*3
        jr nc,.horiz
        push ix
        pop hl
        ld de,A_DYF
        add hl,de
        call GT0
        or a
        ld hl,180
        ret nz
        ld hl,0
        ret
.horiz: push ix
        pop hl
        ld de,A_DXF
        add hl,de
        call GT0
        or a
        ld hl,90
        ret nz
        ld hl,270
        ret

; walkActor
WALK:
        ld a,(ix+A_MOV)
        or a
        ret z
        bit 0,a
        jr nz,.newleg
        bit 1,a
        jr z,.nostep
        call WALKSTEP
        ret nz
.nostep:
        ld a,(ix+A_MOV)
        bit 3,a
        jr z,.noend
        ld (ix+A_MOV),0             ; fin del camino
        ld a,(ix+A_DESTBOX)
        call SETBOX
        ld a,(ACTOR+R_FSTAND)
        call STARTANIM
        ld l,(ix+A_TFACE)
        ld h,(ix+A_TFACE+1)
        ld e,(ix+A_DESTDIR)
        ld d,(ix+A_DESTDIR+1)
        or a
        sbc hl,de
        ret z
        ex de,hl
        jp TURNTO
.noend: bit 2,a
        jr z,.setbox
        xor a                       ; girando
        call UPDDIR
        ld e,(ix+A_FACE)
        ld d,(ix+A_FACE+1)
        push hl
        or a
        sbc hl,de
        pop hl
        jp nz,SETDIR
        ld (ix+A_MOV),0
        ret
.setbox:
        ld a,(ix+A_CURBOX)
        call SETBOX
        ld a,(ix+A_MOV)
        and MF_IN_LEG
        ld (ix+A_MOV),a
.newleg:
        res 0,(ix+A_MOV)
.loop:  ld a,(ix+A_BOX)
        cp INVALID
        jr nz,.l1
        ld a,(ix+A_DESTBOX)
        call SETBOX
        ld (ix+A_CURBOX),a
        jr .last
.l1:    cp (ix+A_DESTBOX)
        jr z,.last
        ld a,(ix+A_DESTBOX)
        ld (NBTO),a
        ld a,(ix+A_BOX)
        call NEXTBOX
        bit 7,a
        jr z,.l2
        ld a,(ix+A_BOX)             ; no hay camino: se queda en su caja
        ld (ix+A_DESTBOX),a
        set 3,(ix+A_MOV)
        ret
.l2:    ld (ix+A_CURBOX),a
        ld (FPB2),a
        ld a,(ix+A_DESTBOX)
        ld (FPB3),a
        ld a,(ix+A_BOX)
        call FINDPATH
        jr c,.last
        ld hl,(FPX)
        ld (CMNX),hl
        ld hl,(FPY)
        ld (CMNY),hl
        call CALCMOVE
        ret nz
        ld a,(ix+A_CURBOX)
        call SETBOX
        jr .loop
.last:  set 3,(ix+A_MOV)
        ld l,(ix+A_DESTX)
        ld h,(ix+A_DESTX+1)
        ld (CMNX),hl
        ld l,(ix+A_DESTY)
        ld h,(ix+A_DESTY+1)
        ld (CMNY),hl
        jp CALCMOVE

; initActor(-1): la ficha del actor a 0 con lo de siempre (numero A)
INITREC:
        push af
        push ix
        pop hl
        ld (hl),0
        ld d,h
        ld e,l
        inc de
        ld bc,R_SIZE-1
        ldir
        pop af
        ld (ACTOR+R_NUM),a
        ld hl,$FFFF
        ld (ACTOR+R_STR0),hl
        ld (ACTOR+R_STR1),hl
        ld (ix+A_FACE),180
        ld (ix+A_TFACE),180
; initActor(0): lo que pone siempre
INITACT0:
        xor a
        ld (ACTOR+R_ELEV),a
        ld (ACTOR+R_ELEV+1),a
        ld (ACTOR+R_IGNB),a
        ld (ACTOR+R_CLIP),a
        ld (ACTOR+R_SND),a
        ld (ix+A_ASPD),a
        ld (ix+A_MOV),a
        ld a,24
        ld (ACTOR+R_WIDTH),a
        ld a,15
        ld (ACTOR+R_TALKC),a
        ld hl,255
        ld (ACTOR+R_BOXSC),hl
        ld a,255
        ld (ACTOR+A_SCALEX),a
        ld (ACTOR+A_SCALEY),a
        ld l,(ix+A_FACE)
        ld h,(ix+A_FACE+1)
        ld (ix+A_TFACE),l
        ld (ix+A_TFACE+1),h
        ld hl,ACTOR+R_FINIT
        ld a,1
        ld b,5
.fr:    ld (hl),a
        inc hl
        inc a
        djnz .fr
        ld a,8                      ; setActorWalkSpeed(8, 2)
        ld e,2
        jp SETSPEED

; El actor solo del motor (las pruebas sin scripts): costume 1, visible, sus colores
ACTINIT:
        ld a,1
        call INITREC
        ld a,1
        ld (ACTOR+R_COST),a
        ld (ACTOR+R_VIS),a
        ld hl,ACTOR+R_PAL
        ld b,32
.p:     ld (hl),$FF
        inc hl
        djnz .p
        ret

; putActor(PAX, PAY): lo coloca en la caja mas cercana y lo deja quieto
PUTACTOR:
        ld hl,(PAX)
        ld (AJX),hl
        ld hl,(PAY)
        ld (AJY),hl
        call ADJXY
        ld hl,(AJRX)
        ld (ix+A_X),l
        ld (ix+A_X+1),h
        ld hl,(AJRY)
        ld (ix+A_Y),l
        ld (ix+A_Y+1),h
        ld (ix+A_DESTBOX),a
        call SETBOX
        ld (ix+A_DESTX),$FF
        ld (ix+A_DESTX+1),$FF
        ld (ix+A_MOV),0
        ld a,(ACTOR+R_FINIT)
        call STARTANIM
        ld a,(ACTOR+R_FSTAND)
        jp STARTANIM

; ---------------------------------------------------------------------------
; caja A para el actor (setBox), y su escala (no cambia A)
SETBOX:
        ld (ix+A_BOX),a
        push af
        call SETUPSCALE
        pop af
        ret

; setupActorScale: la escala de su caja en su posicion (sin cajas, la que tenga)
SETUPSCALE:
        ld a,(ACTOR+R_IGNB)
        or a
        ret nz
        ld a,(ix+A_BOX)
        call GETBOXSC
        ld (ACTOR+R_BOXSC),hl
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        ld (GSX),hl
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        ld (GSY),hl
        ld a,(ix+A_BOX)
        call GETSCALE
        push ix
        pop hl
        ld de,A_SCALEX
        add hl,de
        ld (hl),a
        inc hl
        ld (hl),a
        ret

; setActorWalkSpeed(A, E): si cambia y anda, calcMovementFactor hacia el punto
SETSPEED:
        ld hl,ACTOR+A_SPX
        cp (hl)
        jr nz,.ch
        inc hl
        ld d,a
        ld a,e
        cp (hl)
        ret z
        ld a,d
.ch:    ld (ACTOR+A_SPX),a
        ld a,e
        ld (ACTOR+A_SPY),a
        ld a,(ix+A_MOV)
        or a
        ret z
        ld l,(ix+A_NEXTX)
        ld h,(ix+A_NEXTX+1)
        ld (CMNX),hl
        ld l,(ix+A_NEXTY)
        ld h,(ix+A_NEXTY+1)
        ld (CMNY),hl
        jp CALCMOVE

; A = escala x / y del actor
GETSCX:
        push hl
        push de
        ld de,A_SCALEX
        jr GETSP
GETSCY:
        push hl
        push de
        ld de,A_SCALEY
        jr GETSP

; A = velocidad x / y del actor (no cambia nada mas)
GETSPX:
        push hl
        push de
        ld de,A_SPX
        jr GETSP
GETSPY:
        push hl
        push de
        ld de,A_SPY
GETSP:  push ix
        pop hl
        add hl,de
        ld a,(hl)
        pop de
        pop hl
        ret

; ---------------------------------------------------------------------------
; Variables
CPAGE:  db 0
C_NANIM: db 0
C_NOMIR: db 0
C_FMT:  db 0
C_NCOL: db 0
C_CMDS: dw 0
C_LIMBT: dw 0
C_ANIMT: dw 0
DFR:    db 0
DMASK:  dw 0
DR:     dw 0
DJ:     dw 0
DEXTRA: db 0
UMASK:  dw 0
IAHIGH: db 0
IAI:    dw 0
IAEND:  dw 0
IASTART: dw 0
RMD:    dw 0
RMF:    db 0
RMFX:   db 0
RMFY:   db 0
UDW:    db 0
UDFROM: db 0
SWX:    dw 0
SWY:    dw 0
SWB:    db 0
SWD:    dw -1                       ; direccion al llegar (-1: la que tenga)
SANF:   db 0
SDNEW:  db 0
SDSEL:  db 0
SDFR:   db 0
DANIM:  dw 0
AJPLAY: db 1
WNF:    dw 0
WDX:    dw 0
WDY:    dw 0
SAFRAC: db 0
SAPOS:  db 0
SASCALE: db 255
T1:     dd 0
T2:     dd 0
CMNX:   dw 0
CMNY:   dw 0
CMDX:   dw 0
CMDY:   dw 0
CMXF:   dd 0
CMYF:   dd 0
PAX:    dw 0
PAY:    dw 0
