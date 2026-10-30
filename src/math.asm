; ===========================================================================
;  Aritmetica de 16 y 32 bits (con signo, como C: la division trunca hacia
;  cero y los productos de 32 bits dan la vuelta).
;
;  Convencion: un valor de 32 bits va en DEHL (D el byte alto, L el bajo).
; ===========================================================================

; HL = -HL
NEGHL:
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; DE = -DE
NEGDE:
        xor a
        sub e
        ld e,a
        sbc a,a
        sub d
        ld d,a
        ret

; DEHL = -DEHL
NEG32:
        xor a
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a
        ld a,0
        sbc a,e
        ld e,a
        ld a,0
        sbc a,d
        ld d,a
        ret

; HL = |HL|
ABSHL:
        bit 7,h
        ret z
        jr NEGHL

; carry si HL < DE (con signo). No cambia HL ni DE.
CPS16:
        ld a,h
        xor d
        jp m,.diff
        push hl
        or a
        sbc hl,de
        pop hl
        ret
.diff:  ld a,h
        rla
        ret

; DEHL = HL * DE sin signo
MULU16:
        ld (MA),hl
        ld (MB),de
        ld d,l
        ld a,(MB)
        ld e,a
        mul d,e                     ; lo * lo
        ld (MR),de
        ld a,(MA+1)
        ld d,a
        ld a,(MB+1)
        ld e,a
        mul d,e                     ; hi * hi
        ld (MR+2),de
        ld a,(MA)
        ld d,a
        ld a,(MB+1)
        ld e,a
        mul d,e                     ; lo * hi
        call .mid
        ld a,(MA+1)
        ld d,a
        ld a,(MB)
        ld e,a
        mul d,e                     ; hi * lo
        call .mid
        ld hl,(MR)
        ld de,(MR+2)
        ret
.mid:   ld hl,(MR+1)                ; MR += DE << 8
        add hl,de
        ld (MR+1),hl
        ret nc
        ld hl,MR+3
        inc (hl)
        ret

; DEHL = HL * DE con signo
MULS16:
        ld a,h
        xor d
        push af
        call ABSHL
        bit 7,d
        call nz,NEGDE
        call MULU16
        pop af
        ret p
        jp NEG32

; DEHL = DEHL * BC (BC con signo), los 32 bits bajos
MULS32_16:
        ld (MX),hl
        ld (MX+2),de
        ld d,b
        ld e,c
        call MULU16                 ; parte baja * BC
        push hl
        push de
        ld hl,(MX+2)
        ld d,b
        ld e,c
        call MULU16                 ; parte alta * BC (solo cuentan 16 bits)
        pop de
        add hl,de
        bit 7,b
        jr z,.pos
        ld de,(MX)                  ; BC negativo: resta la parte baja << 16
        or a
        sbc hl,de
.pos:   ex de,hl
        pop hl
        ret

; DV = BC con signo extendido a 32 bits
SETDV16:
        ld (DV),bc
        ld a,b
        rla
        sbc a,a
        ld (DV+2),a
        ld (DV+3),a
        ret

; DEHL = DEHL / DV sin signo (resto en RM)
DIVU32:
        ld (DN),hl
        ld (DN+2),de
        ld hl,0
        ld (RM),hl
        ld (RM+2),hl
        ld b,32
.lp:    ld hl,DN
        sla (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        ld hl,RM
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        ld hl,(RM)
        ld de,(DV)
        or a
        sbc hl,de
        push hl
        ld hl,(RM+2)
        ld de,(DV+2)
        sbc hl,de
        jr c,.no
        ld (RM+2),hl
        pop hl
        ld (RM),hl
        ld hl,DN
        set 0,(hl)
        djnz .lp
        jr .done
.no:    pop hl
        djnz .lp
.done:  ld hl,(DN)
        ld de,(DN+2)
        ret

; DEHL = DEHL / DV con signo (trunca hacia cero). Cambia DV.
DIVS32:
        ld a,d
        ld c,a
        bit 7,d
        call nz,NEG32
        push hl
        push de
        ld a,(DV+3)
        xor c
        ld c,a
        ld a,(DV+3)
        bit 7,a
        jr z,.dp
        ld hl,(DV)
        ld de,(DV+2)
        call NEG32
        ld (DV),hl
        ld (DV+2),de
.dp:    pop de
        pop hl
        push bc
        call DIVU32
        pop bc
        bit 7,c
        ret z
        jp NEG32

; DEHL = DEHL / BC con signo
DIVS32_16:
        push hl
        push de
        call SETDV16
        pop de
        pop hl
        jr DIVS32

; DEHL += el valor de 32 bits al que apunta BC
ADD32M:
        push de
        ld a,(bc)
        add a,l
        ld l,a
        inc bc
        ld a,(bc)
        adc a,h
        ld h,a
        inc bc
        pop de
        ld a,(bc)
        adc a,e
        ld e,a
        inc bc
        ld a,(bc)
        adc a,d
        ld d,a
        ret

; DEHL = HL con signo extendido
SEXT:
        ld a,h
        rla
        sbc a,a
        ld d,a
        ld e,a
        ret

; carry si DEHL (con signo) < 0
SIGN32:
        ld a,d
        rla
        ret

; Variables de trabajo
MA:     dw 0
MB:     dw 0
MR:     dd 0
MX:     dd 0
DV:     dd 0
DN:     dd 0
RM:     dd 0
