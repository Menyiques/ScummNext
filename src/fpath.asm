; ===========================================================================
;  findPathTowards (capa OVF; antes en boxes.asm, en el banco 0): solo cuando un
;  actor pasa de una caja a otra. Sus variables siguen en boxes.asm (banco 0).
; ===========================================================================

; findPathTowards(A = caja1, FPB2, FPB3) con el actor en IX.
; carry: ya se puede ir recto. Si no, el punto en FPX, FPY.
F_FINDPATH:
        ld de,FB1
        call BOXCOPY
        ld a,(FPB2)
        ld de,FB2
        call BOXCOPY
        ld a,4
        ld (FPI),a
.outer: ld a,4
        ld (FPJ),a
.inner: ld hl,FB1
        ld de,U1
        ld bc,8
        ldir
        ld hl,FB2
        ld de,U2
        ld bc,8
        ldir
        call FPVERT
        ret z                       ; resuelto (carry dice cual)
        ld hl,FB1
        ld de,U1
        ld bc,8
        ldir
        ld hl,FB2
        ld de,U2
        ld bc,8
        ldir
        call FPHORZ
        ret z
        ld hl,FB1                   ; gira la caja 1
        call ROT4
        ld hl,FPJ
        dec (hl)
        jr nz,.inner
        ld hl,FB2
        call ROT4
        ld hl,FPI
        dec (hl)
        jr nz,.outer
        ld hl,0
        ld (FPX),hl
        ld (FPY),hl
        or a
        ret

; gira las 4 esquinas de (HL): ul = ur, ur = lr, lr = ll, ll = ul
ROT4:
        push hl
        ld de,ROTT
        ld bc,4
        ldir
        pop de
        push de
        ld hl,4
        add hl,de
        ld bc,12
        ldir
        ld hl,ROTT
        ld bc,4
        ldir
        pop hl
        ret

; U1 = ul1.x ul1.y ur1.x ur1.y, U2 igual con la caja 2
; Las dos devuelven NZ si no hay lado comun; Z si si (carry = recto).
FPVERT:
        ld hl,(U1)                  ; ul1.x == ur1.x == ul2.x == ur2.x ?
        ld de,(U1+4)
        or a
        sbc hl,de
        jp nz,FPNO
        ld hl,(U1)
        ld de,(U2)
        sbc hl,de
        jp nz,FPNO
        ld hl,(U1)
        ld de,(U2+4)
        sbc hl,de
        jp nz,FPNO
        ld ix,U1+2                  ; trabaja con las y
        ld iy,U2+2
        call FPAXIS
        ld ix,(ACTP)
        ret nz
        ; pos = y del actor; si caja2 == caja3, ajusta con el destino
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        call SEXT
        ld (FPPOS),hl
        ld (FPPOS+2),de
        ld a,(FPB2)
        ld hl,FPB3
        cp (hl)
        jr nz,.clamp
        ld l,(ix+A_DESTX)           ; dx = dest.x - x
        ld h,(ix+A_DESTX+1)
        ld e,(ix+A_X)
        ld d,(ix+A_X+1)
        or a
        sbc hl,de
        ld (FDX),hl
        ld a,h
        or l
        jr z,.clamp
        ld l,(ix+A_DESTY)           ; dy = dest.y - y
        ld h,(ix+A_DESTY+1)
        ld e,(ix+A_Y)
        ld d,(ix+A_Y+1)
        or a
        sbc hl,de
        push hl
        ld hl,(U1)                  ; bdx = ul1.x - x
        ld e,(ix+A_X)
        ld d,(ix+A_X+1)
        or a
        sbc hl,de
        pop de
        call MULS16                 ; dy *= bdx
        ld (FDY),hl
        ld (FDY+2),de
        ld bc,(FDX)
        call DIVS32_16              ; t
        ld a,h
        or l
        or d
        or e
        jr nz,.addt
        ; t == 0 y (dy <= 0 o dx <= 0) y (dy >= 0 o dx >= 0) -> t = -1
        call FDYLE0
        jr c,.c1
        ld hl,(FDX)
        call POSITIVE
        jr c,.addt0
.c1:    call FDYGE0
        jr c,.m1
        ld hl,(FDX)
        bit 7,h
        jr nz,.addt0
.m1:    ld hl,$FFFF
        ld d,h
        ld e,l
        jr .addt
.addt0: ld hl,0
        ld d,h
        ld e,h
.addt:  ld bc,FPPOS
        call ADD32M
        ld (FPPOS),hl
        ld (FPPOS+2),de
.clamp: ld hl,(U2+2)                ; q = clamp(pos, ul2.y..ur2.y, ul1.y..ur1.y)
        ld (QLO2),hl
        ld hl,(U2+6)
        ld (QHI2),hl
        ld hl,(U1+2)
        ld (QLO1),hl
        ld hl,(U1+6)
        ld (QHI1),hl
        call FPQ
        jr nz,.ret
        ld a,(FPB2)
        ld hl,FPB3
        cp (hl)
        jr nz,.ret
        xor a                       ; Z y carry: recto
        scf
        ret
.ret:   ld hl,(U1)
        ld (FPX),hl
        ld hl,(FPQV)
        ld (FPY),hl
        xor a                       ; Z sin carry
        ret

FPHORZ:
        ld hl,(U1+2)                ; ul1.y == ur1.y == ul2.y == ur2.y ?
        ld de,(U1+6)
        or a
        sbc hl,de
        jp nz,FPNO
        ld hl,(U1+2)
        ld de,(U2+2)
        sbc hl,de
        jp nz,FPNO
        ld hl,(U1+2)
        ld de,(U2+6)
        sbc hl,de
        jp nz,FPNO
        ld ix,U1
        ld iy,U2
        call FPAXIS
        ld ix,(ACTP)
        ret nz
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        call SEXT
        ld (FPPOS),hl
        ld (FPPOS+2),de
        ld a,(FPB2)
        ld hl,FPB3
        cp (hl)
        jr nz,.clamp
        ld l,(ix+A_DESTY)           ; dy = dest.y - y
        ld h,(ix+A_DESTY+1)
        ld e,(ix+A_Y)
        ld d,(ix+A_Y+1)
        or a
        sbc hl,de
        ld (FDX),hl                 ; (aqui FDX guarda dy)
        ld a,h
        or l
        jr z,.clamp
        ld l,(ix+A_DESTX)           ; dx = dest.x - x
        ld h,(ix+A_DESTX+1)
        ld e,(ix+A_X)
        ld d,(ix+A_X+1)
        or a
        sbc hl,de
        push hl
        ld hl,(U1+2)                ; bdy = ul1.y - y
        ld e,(ix+A_Y)
        ld d,(ix+A_Y+1)
        or a
        sbc hl,de
        pop de
        call MULS16                 ; dx * bdy
        ld bc,(FDX)
        call DIVS32_16
        ld bc,FPPOS
        call ADD32M
        ld (FPPOS),hl
        ld (FPPOS+2),de
.clamp: ld hl,(U2)
        ld (QLO2),hl
        ld hl,(U2+4)
        ld (QHI2),hl
        ld hl,(U1)
        ld (QLO1),hl
        ld hl,(U1+4)
        ld (QHI1),hl
        call FPQ
        jr nz,.ret
        ld a,(FPB2)
        ld hl,FPB3
        cp (hl)
        jr nz,.ret
        xor a
        scf
        ret
.ret:   ld hl,(FPQV)
        ld (FPX),hl
        ld hl,(U1+2)
        ld (FPY),hl
        xor a
        ret

FPNO:   or 1                        ; NZ
        ret

; Ordena y compara los lados en el eje que apuntan IX (caja 1) e IY (caja 2):
; (ix+0) = ul1, (ix+4) = ur1, igual con iy. NZ si no se tocan.
FPAXIS:
        ld l,(ix+0)                 ; si ul1 > ur1, intercambia
        ld h,(ix+1)
        ld e,(ix+4)
        ld d,(ix+5)
        ex de,hl                    ; hl = ur1, de = ul1
        call CPS16
        jr nc,.s1
        ld (ix+0),l
        ld (ix+1),h
        ld (ix+4),e
        ld (ix+5),d
.s1:    ld l,(iy+0)
        ld h,(iy+1)
        ld e,(iy+4)
        ld d,(iy+5)
        ex de,hl
        call CPS16
        jr nc,.s2
        ld (iy+0),l
        ld (iy+1),h
        ld (iy+4),e
        ld (iy+5),d
.s2:    ; no se tocan si ul1 > ur2, ul2 > ur1, o se tocan en un punto
        ; (ur1 == ul2 o ur2 == ul1) con los dos lados de longitud > 0
        ld l,(iy+4)                 ; ur2 < ul1 ?
        ld h,(iy+5)
        ld e,(ix+0)
        ld d,(ix+1)
        call CPS16
        jr c,.no
        ld l,(ix+4)                 ; ur1 < ul2 ?
        ld h,(ix+5)
        ld e,(iy+0)
        ld d,(iy+1)
        call CPS16
        jr c,.no
        ld l,(ix+4)                 ; ur1 == ul2 ?
        ld h,(ix+5)
        ld e,(iy+0)
        ld d,(iy+1)
        or a
        sbc hl,de
        jr z,.touch
        ld l,(iy+4)                 ; ur2 == ul1 ?
        ld h,(iy+5)
        ld e,(ix+0)
        ld d,(ix+1)
        or a
        sbc hl,de
        jr nz,.yes
.touch: ld l,(ix+0)                 ; ul1 != ur1 y ul2 != ur2 -> no
        ld h,(ix+1)
        ld e,(ix+4)
        ld d,(ix+5)
        or a
        sbc hl,de
        jr z,.yes
        ld l,(iy+0)
        ld h,(iy+1)
        ld e,(iy+4)
        ld d,(iy+5)
        or a
        sbc hl,de
        jr z,.yes
.no:    or 1
        ret
.yes:   xor a
        ret

; q = pos acotado a [QLO2, QHI2] y despues a [QLO1, QHI1] (como en el modelo:
; max, min, max, min). FPQV = q (16 bits). Z si q == pos.
FPQ:
        ld hl,(FPPOS)
        ld (FPQ32),hl
        ld hl,(FPPOS+2)
        ld (FPQ32+2),hl
        ld hl,(QLO2)
        call QMAX
        ld hl,(QHI2)
        call QMIN
        ld hl,(QLO1)
        call QMAX
        ld hl,(QHI1)
        call QMIN
        ld hl,(FPQ32)
        ld (FPQV),hl
        ld de,(FPPOS)
        or a
        sbc hl,de
        ret nz
        ld hl,(FPQ32+2)
        ld de,(FPPOS+2)
        or a
        sbc hl,de
        ret

; FPQ32 = max(FPQ32, HL)
QMAX:
        push hl
        call QCMP                   ; carry si FPQ32 < HL
        pop hl
        ret nc
        jr QSET
; FPQ32 = min(FPQ32, HL)
QMIN:
        push hl
        call QCMP
        pop hl
        ret c
        ret z
QSET:   call SEXT
        ld (FPQ32),hl
        ld (FPQ32+2),de
        ret
; compara FPQ32 con HL (con signo): carry si menor, Z si igual
QCMP:
        call SEXT
        push hl
        ld hl,(FPQ32)
        pop bc
        or a
        sbc hl,bc
        ld c,l
        ld b,h
        ld hl,(FPQ32+2)
        sbc hl,de
        jr nz,.nz
        ld a,b
        or c
        ret                         ; Z si igual (sin carry)
.nz:    ld a,h
        rla                         ; carry = signo
        ld a,1
        jr c,.neg
        or a                        ; NZ, nc
        ret
.neg:   or a
        scf
        ret

; carry si FDY (32 bits) <= 0
FDYLE0:
        ld a,(FDY+3)
        bit 7,a
        scf
        ret nz
        ld hl,(FDY)
        ld a,h
        or l
        ld hl,(FDY+2)
        or h
        or l
        scf
        ret z
        or a
        ret
; carry si FDY >= 0
FDYGE0:
        ld a,(FDY+3)
        rla
        ccf
        ret

