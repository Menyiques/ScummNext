; ===========================================================================
;  Cajas por donde se anda (BOXD / BOXM). Traduccion de tools/model.py:
;  punto mas cercano en un segmento y en una caja, punto dentro de una caja,
;  ajustar un destino a la caja mas cercana, siguiente caja y paso de una
;  caja a la siguiente (findPathTowards).
;
;  Cada caja son 20 bytes: ul.x ul.y ur.x ur.y lr.x lr.y ll.x ll.y (16 bits
;  con signo), mascara, flags y escala.
; ===========================================================================

; HL = direccion de la caja A
BOXPTR:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        ld de,BOXES
        add hl,de
        ret

; A = flags de la caja A (0 si no existe)
BOXFLAGS:
        ld e,17
        jr BOXBYTE
; A = mascara de la caja A (0 si no existe)
BOXMASK:
        ld e,16
BOXBYTE:
        ld hl,NBOXES
        cp (hl)
        jr nc,.none
        push de
        call BOXPTR
        pop de
        ld d,0
        add hl,de
        ld a,(hl)
        ret
.none:  xor a
        ret

; Copia las 4 esquinas de la caja A a DE (16 bytes)
BOXCOPY:
        push de
        call BOXPTR
        pop de
        ld bc,16
        ldir
        ret

; MINV / MAXV de las 4 coordenadas que empiezan en HL (cada 4 bytes)
MINMAX4:
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (MINV),de
        ld (MAXV),de
        ld b,3
.lp:    inc hl
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        push hl
        push bc
        ex de,hl                    ; hl = valor
        ld de,(MINV)
        call CPS16
        jr nc,.n1
        ld (MINV),hl
.n1:    ex de,hl                    ; de = valor
        ld hl,(MAXV)
        call CPS16
        jr nc,.n2
        ld (MAXV),de
.n2:    pop bc
        pop hl
        djnz .lp
        ret

; Z si los puntos (4 bytes) en HL y DE son iguales
PTEQ:
        ld b,4
.lp:    ld a,(de)
        cp (hl)
        ret nz
        inc hl
        inc de
        djnz .lp
        ret

; ---------------------------------------------------------------------------
; closestPtOnLine(LST, LEN, LP) -> LRX, LRY
CLOSEST:
        ld hl,(LEN)
        ld de,(LST)
        or a
        sbc hl,de
        ld (LXD),hl
        ld hl,(LEN+2)
        ld de,(LST+2)
        or a
        sbc hl,de
        ld (LYD),hl
        ld hl,(LXD)
        ld a,h
        or l
        jr nz,.notv
        ld hl,(LST)                 ; vertical
        ld (LRX),hl
        ld hl,(LP+2)
        ld (LRY),hl
        jp .clamp
.notv:  ld hl,(LYD)
        ld a,h
        or l
        jr nz,.gen
        ld hl,(LP)                  ; horizontal
        ld (LRX),hl
        ld hl,(LST+2)
        ld (LRY),hl
        jp .clamp
.gen:   ld hl,(LXD)                 ; dist = lxd^2 + lyd^2
        ld d,h
        ld e,l
        call MULS16
        ld (LDIST),hl
        ld (LDIST+2),de
        ld hl,(LYD)
        ld d,h
        ld e,l
        call MULS16
        ld bc,LDIST
        call ADD32M
        ld (LDIST),hl
        ld (LDIST+2),de
        call ABSCMP                 ; carry si |lyd| < |lxd|
        jp nc,.ybr
        ; --- |lxd| > |lyd| ---
        ld hl,(LST)                 ; a = st.x * lyd / lxd
        ld de,(LYD)
        call MULS16
        ld bc,(LXD)
        call DIVS32_16
        ld (LA),hl
        ld (LA+2),de
        ld hl,(LP)                  ; b = p.x * lxd / lyd
        ld de,(LXD)
        call MULS16
        ld bc,(LYD)
        call DIVS32_16
        ld bc,LA                    ; s = a + b - st.y + p.y
        call ADD32M
        ld bc,(LST+2)
        call SUB32_16
        ld bc,(LP+2)
        call ADD32_16
        call CCALC                  ; c
        ld (LRX),hl
        ld bc,(LYD)                 ; ry = c*lyd/lxd - a + st.y
        call MULS32_16
        ld bc,(LXD)
        call DIVS32_16
        ld de,(LA)
        or a
        sbc hl,de
        ld de,(LST+2)
        add hl,de
        ld (LRY),hl
        jr .clamp
.ybr:   ; --- |lxd| <= |lyd| ---
        ld hl,(LST+2)               ; a = st.y * lxd / lyd
        ld de,(LXD)
        call MULS16
        ld bc,(LYD)
        call DIVS32_16
        ld (LA),hl
        ld (LA+2),de
        ld hl,(LP+2)                ; b = p.y * lyd / lxd
        ld de,(LYD)
        call MULS16
        ld bc,(LXD)
        call DIVS32_16
        ld bc,LA
        call ADD32M
        ld bc,(LST)
        call SUB32_16
        ld bc,(LP)
        call ADD32_16
        call CCALC
        ld (LRY),hl
        ld bc,(LXD)                 ; rx = c*lxd/lyd - a + st.x
        call MULS32_16
        ld bc,(LYD)
        call DIVS32_16
        ld de,(LA)
        or a
        sbc hl,de
        ld de,(LST)
        add hl,de
        ld (LRX),hl
.clamp: call ABSCMP
        jr nc,.cy
        ; por x
        ld hl,(LXD)
        call POSITIVE
        jr nc,.xneg
        ld hl,(LRX)                 ; lxd > 0
        ld de,(LST)
        call CPS16
        jr c,.rst
        ld de,(LEN)
        ex de,hl
        call CPS16                  ; en.x < rx ?
        jr c,.ren
        ret
.xneg:  ld hl,(LST)
        ld de,(LRX)
        call CPS16                  ; st.x < rx ?
        jr c,.rst
        ld hl,(LRX)
        ld de,(LEN)
        call CPS16
        jr c,.ren
        ret
.cy:    ld hl,(LYD)
        call POSITIVE
        jr nc,.yneg
        ld hl,(LRY)
        ld de,(LST+2)
        call CPS16
        jr c,.rst
        ld de,(LEN+2)
        ex de,hl
        call CPS16
        jr c,.ren
        ret
.yneg:  ld hl,(LST+2)
        ld de,(LRY)
        call CPS16
        jr c,.rst
        ld hl,(LRY)
        ld de,(LEN+2)
        call CPS16
        jr c,.ren
        ret
.rst:   ld hl,(LST)
        ld (LRX),hl
        ld hl,(LST+2)
        ld (LRY),hl
        ret
.ren:   ld hl,(LEN)
        ld (LRX),hl
        ld hl,(LEN+2)
        ld (LRY),hl
        ret

; carry si |LYD| < |LXD|
ABSCMP:
        ld hl,(LXD)
        call ABSHL
        ex de,hl
        ld hl,(LYD)
        call ABSHL
        or a
        sbc hl,de
        ret

; carry si HL > 0 (con signo)
POSITIVE:
        bit 7,h
        jr nz,.no
        ld a,h
        or l
        ret z                       ; cero: nc
        scf
        ret
.no:    or a                        ; negativo: nc
        ret

; c = (s * lyd * lxd) / dist, con s en DEHL. Devuelve c en DEHL y LC.
CCALC:
        ld bc,(LYD)
        call MULS32_16
        ld bc,(LXD)
        call MULS32_16
        push hl
        push de
        ld hl,(LDIST)
        ld (DV),hl
        ld hl,(LDIST+2)
        ld (DV+2),hl
        pop de
        pop hl
        call DIVS32
        ld (LC),hl
        ld (LC+2),de
        ret

; DEHL += BC (con signo)
ADD32_16:
        ld a,b
        add hl,bc
        ld b,0
        bit 7,a
        jr z,.p
        dec b
.p:     ld a,e
        adc a,b
        ld e,a
        ld a,d
        adc a,b
        ld d,a
        ret
; DEHL -= BC (con signo)
SUB32_16:
        or a
        ld a,b
        sbc hl,bc
        ld b,0
        bit 7,a
        jr z,.p
        dec b
.p:     ld a,e
        sbc a,b
        ld e,a
        ld a,d
        sbc a,b
        ld d,a
        ret

; ---------------------------------------------------------------------------
; sqrDist(LP, LRX/LRY) -> DEHL
SQRD:
        ld hl,(LP)
        ld de,(LRX)
        or a
        sbc hl,de
        call ABSHL
        ld a,h
        cp $10
        jr nc,.big
        push hl
        ld hl,(LP+2)
        ld de,(LRY)
        or a
        sbc hl,de
        call ABSHL
        ld a,h
        cp $10
        jr nc,.big1
        ld d,h
        ld e,l
        call MULU16
        ld (SQT),hl
        ld (SQT+2),de
        pop hl
        ld d,h
        ld e,l
        call MULU16
        ld bc,SQT
        jp ADD32M
.big1:  pop hl
.big:   ld hl,$FFFF
        ld de,$00FF
        ret

; ---------------------------------------------------------------------------
; checkXYInBoxBounds(A, PX, PY): carry si esta dentro
INBOX:
        cp INVALID
        jp z,.no
        ld hl,NBOXES
        cp (hl)
        jp nc,.no
        ld de,BQ
        call BOXCOPY
        ld hl,BQ
        call MINMAX4
        ld hl,(PX)
        ld de,(MINV)
        call CPS16
        jp c,.no
        ld de,(MAXV)
        ex de,hl
        call CPS16
        jp c,.no
        ld hl,BQ+2
        call MINMAX4
        ld hl,(PY)
        ld de,(MINV)
        call CPS16
        jp c,.no
        ld de,(MAXV)
        ex de,hl
        call CPS16
        jp c,.no
        ld hl,BQ                    ; caja que es una linea?
        ld de,BQ+4
        call PTEQ
        jr nz,.l2
        ld hl,BQ+8
        ld de,BQ+12
        call PTEQ
        jr z,.line
.l2:    ld hl,BQ
        ld de,BQ+12
        call PTEQ
        jr nz,.slopes
        ld hl,BQ+4
        ld de,BQ+8
        call PTEQ
        jr nz,.slopes
.line:  ld hl,BQ
        ld de,LST
        ld bc,4
        ldir
        ld hl,BQ+8
        ld de,LEN
        ld bc,4
        ldir
        ld hl,(PX)
        ld (LP),hl
        ld hl,(PY)
        ld (LP+2),hl
        call CLOSEST
        call SQRD
        ld a,d
        or e
        or h
        jr nz,.slopes
        ld a,l
        cp 5
        jr c,.yes
.slopes:
        ld hl,BQ
        ld de,BQ+4
        call SLOPE
        jr c,.no
        ld hl,BQ+4
        ld de,BQ+8
        call SLOPE
        jr c,.no
        ld hl,BQ+8
        ld de,BQ+12
        call SLOPE
        jr c,.no
        ld hl,BQ+12
        ld de,BQ
        call SLOPE
        jr c,.no
.yes:   scf
        ret
.no:    or a
        ret

; compareSlope(p1 = (HL), p2 = (DE), p3 = PX,PY): carry si NO se cumple
SLOPE:
        push de
        ld de,S1
        ld bc,4
        ldir
        pop hl
        ld de,S2
        ld bc,4
        ldir
        ld hl,(S2+2)                ; (p2.y - p1.y) * (p3.x - p1.x)
        ld de,(S1+2)
        or a
        sbc hl,de
        push hl
        ld hl,(PX)
        ld de,(S1)
        or a
        sbc hl,de
        pop de
        call MULS16
        ld (SL),hl
        ld (SL+2),de
        ld hl,(PY)                  ; (p3.y - p1.y) * (p2.x - p1.x)
        ld de,(S1+2)
        or a
        sbc hl,de
        push hl
        ld hl,(S2)
        ld de,(S1)
        or a
        sbc hl,de
        pop de
        call MULS16
        ld bc,(SL)                  ; derecha - izquierda: negativo = no
        or a
        sbc hl,bc
        ex de,hl
        ld bc,(SL+2)
        sbc hl,bc
        ld a,h
        rla
        ret

; ---------------------------------------------------------------------------
; getClosestPtOnBox(A, PX, PY) -> DEHL = distancia, CBX/CBY = punto
CLOSEBOX:
        ld de,BQ
        call BOXCOPY
        ld hl,(PX)
        ld (LP),hl
        ld hl,(PY)
        ld (LP+2),hl
        ld hl,$FFFF
        ld (CBD),hl
        ld hl,$00FF
        ld (CBD+2),hl
        ld hl,0
        ld (CBX),hl
        ld (CBY),hl
        ld hl,BQ
        ld de,BQ+4
        call .edge
        ld hl,BQ+4
        ld de,BQ+8
        call .edge
        ld hl,BQ+8
        ld de,BQ+12
        call .edge
        ld hl,BQ+12
        ld de,BQ
        call .edge
        ld hl,(CBD)
        ld de,(CBD+2)
        ret
.edge:  push de
        ld de,LST
        ld bc,4
        ldir
        pop hl
        ld de,LEN
        ld bc,4
        ldir
        call CLOSEST
        call SQRD
        ; d < best ? (sin signo)
        push hl
        push de
        ld bc,(CBD)
        or a
        sbc hl,bc
        ex de,hl
        ld bc,(CBD+2)
        sbc hl,bc
        pop de
        pop hl
        ret nc
        ld (CBD),hl
        ld (CBD+2),de
        ld hl,(LRX)
        ld (CBX),hl
        ld hl,(LRY)
        ld (CBY),hl
        ret

; inBoxQuickReject(A, AJX, AJY, umbral en TH): carry si se descarta
QUICKREJ:
        ld de,BQ
        call BOXCOPY
        ld hl,BQ
        call MINMAX4
        ld hl,(AJX)                 ; x - th > max ?
        ld de,(TH)
        or a
        sbc hl,de
        ld de,(MAXV)
        ex de,hl
        call CPS16
        ret c
        ld hl,(AJX)                 ; x + th < min ?
        ld de,(TH)
        add hl,de
        ld de,(MINV)
        call CPS16
        ret c
        ld hl,BQ+2
        call MINMAX4
        ld hl,(AJY)
        ld de,(TH)
        or a
        sbc hl,de
        ld de,(MAXV)
        ex de,hl
        call CPS16
        ret c
        ld hl,(AJY)
        ld de,(TH)
        add hl,de
        ld de,(MINV)
        jp CPS16

; ---------------------------------------------------------------------------
; adjustXYToBeInBox(AJX, AJY) -> AJRX, AJRY, A = caja
ADJXY:
        ld hl,(AJX)
        ld (AJRX),hl
        ld hl,(AJY)
        ld (AJRY),hl
        ld a,(NBOXES)
        cp 2
        jr nc,.go
        ld a,INVALID
        ret
.go:    ld hl,THRESH
.th:    ld a,(hl)
        inc hl
        push hl
        ld (TH),a
        xor a
        ld (TH+1),a
        ld hl,$FFFF
        ld (AJB),hl
        ld hl,0
        ld (AJB+2),hl
        ld a,INVALID
        ld (AJBB),a
        ld a,(NBOXES)
        dec a
.box:   ld (AJK),a
        call BOXFLAGS
        bit 7,a                     ; invisible: no vale, salvo si es solo del
        jr z,.vis                   ; jugador y el actor no lo es
        bit 5,a
        jr z,.next
        ld a,(AJPLAY)
        or a
        jr nz,.next
.vis:
        ld a,(TH)
        or a
        jr z,.noq
        ld a,(AJK)
        call QUICKREJ
        jr c,.next
.noq:   ld hl,(AJX)
        ld (PX),hl
        ld hl,(AJY)
        ld (PY),hl
        ld a,(AJK)
        call INBOX
        jr nc,.out
        ld hl,(AJX)
        ld (AJRX),hl
        ld hl,(AJY)
        ld (AJRY),hl
        pop hl
        ld a,(AJK)
        ret
.out:   ld a,(AJK)
        call CLOSEBOX
        push hl
        push de
        ld bc,(AJB)                 ; d < best ?
        or a
        sbc hl,bc
        ex de,hl
        ld bc,(AJB+2)
        sbc hl,bc
        pop de
        pop hl
        jr nc,.next
        ld bc,(CBX)
        ld (AJRX),bc
        ld bc,(CBY)
        ld (AJRY),bc
        ld a,h
        or l
        or d
        or e
        jr nz,.best
        pop hl
        ld a,(AJK)
        ret
.best:  ld (AJB),hl
        ld (AJB+2),de
        ld a,(AJK)
        ld (AJBB),a
.next:  ld a,(AJK)
        dec a
        jp nz,.box
        ; th == 0 o th*th >= best: esta caja
        ld a,(TH)
        or a
        jr z,.done
        ld e,a
        ld d,a
        mul d,e
        ld hl,(AJB+2)
        ld a,h
        or l
        jr nz,.again                ; best >= 65536 > th*th
        ld hl,(AJB)
        ex de,hl
        or a
        sbc hl,de                   ; th*th - best
        jr nc,.done
.again: pop hl
        jp .th
.done:  pop hl
        ld a,(AJBB)
        ret

THRESH: db 30, 80, 0

; ---------------------------------------------------------------------------
; getNextBox(A = desde, NBTO = hasta) -> A (>= $80: negativo, no hay camino)
NEXTBOX:
        ld b,a
        ld a,(NBTO)
        cp b
        ret z
        cp INVALID
        jr nz,.n1
        ld a,$FF
        ret
.n1:    ld a,b
        cp INVALID
        jr nz,.n2
        ld a,(NBTO)
        ret
.n2:    ld hl,(MATRIX)
        ld a,b
        or a
        jr z,.scan
        ld c,b
.skip:  ld a,(hl)
        cp $FF
        jr z,.endl
        inc hl
        inc hl
        inc hl
        jr .skip
.endl:  inc hl
        dec c
        jr nz,.skip
.scan:  ld e,$FF
.sl:    ld a,(hl)
        cp $FF
        jr z,.done
        ld d,a
        ld a,(NBTO)
        cp d
        jr c,.nx                    ; hasta < lo
        inc hl
        ld d,(hl)
        dec hl
        cp d
        jr z,.take
        jr nc,.nx                   ; hasta > hi
.take:  inc hl
        inc hl
        ld e,(hl)
        dec hl
        dec hl
.nx:    inc hl
        inc hl
        inc hl
        jr .sl
.done:  ld a,e
        ret

; ---------------------------------------------------------------------------
; findPathTowards(A = caja1, FPB2, FPB3) con el actor en IX (en la capa OVF: fpath.asm).
; carry: ya se puede ir recto. Si no, el punto en FPX, FPY.
FINDPATH:
        ld (OVA),a
        ld hl,F_FINDPATH
        ld a,OVF_PAGE
        jp OVCALLR

; getBoxScale(A) -> HL (16 bits; 255 sin caja)
GETBOXSC:
        ld hl,255
        cp INVALID
        ret z
        ld de,NBOXES
        ex de,hl
        cp (hl)
        ex de,hl
        ret nc
        call BOXPTR
        ld de,18
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; ---------------------------------------------------------------------------
; getScale(A = caja, GSX, GSY) -> A: la escala de la caja, directa o de una
; franja de SCAL (escala1, y1, escala2, y2): la recta por esos dos puntos en la y
; del actor (en 0..199, como la tabla de 200 filas del original; y1 puede ser la de
; abajo), entre 1 y 255
GETSCALE:
        cp INVALID
        jr z,.full
        ld hl,NBOXES
        cp (hl)
        jr nc,.full
        call BOXPTR
        ld de,18
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        bit 7,d
        jr nz,.slot
        ld a,d
        or a
        jr nz,.full
        ld a,e
        ret
.full:  ld a,255
        ret
.slot:  res 7,d
        ld a,d
        or a
        jr nz,.full
        ld a,e
        cp 4
        jr nc,.full
        add a,a
        add a,a
        add a,a
        ld hl,SCALT
        add hl,a
        ld de,GS1
        ld bc,8
        ldir
        ld hl,(GY1)
        ld de,(GY2)
        or a
        sbc hl,de
        jr z,.full
        ld hl,(GSY)
        bit 7,h
        jr z,.c1
        ld hl,0
.c1:    ex de,hl
        ld hl,199
        call CPS16                  ; 199 < y ?
        jr c,.cy
        ex de,hl
.cy:    ld de,(GY1)
        or a
        sbc hl,de
        push hl
        ld hl,(GS2)
        ld de,(GS1)
        or a
        sbc hl,de
        pop de
        call MULS16
        push hl
        push de
        ld hl,(GY2)
        ld de,(GY1)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        pop de
        pop hl
        call DIVS32_16
        ld de,(GS1)
        add hl,de
        bit 7,h
        jr nz,.one
        ld a,h
        or a
        jr nz,.full
        ld a,l
        or a
        ret nz
.one:   ld a,1
        ret

; ---------------------------------------------------------------------------
; Variables
GSX:    dw 0
GSY:    dw 0
GS1:    dw 0
GY1:    dw 0
GS2:    dw 0
GY2:    dw 0
LST:    dw 0,0
LEN:    dw 0,0
LP:     dw 0,0
LRX:    dw 0
LRY:    dw 0
LXD:    dw 0
LYD:    dw 0
LDIST:  dd 0
LA:     dd 0
LC:     dd 0
SQT:    dd 0
MINV:   dw 0
MAXV:   dw 0
BQ:     ds 16
S1:     dw 0,0
S2:     dw 0,0
SL:     dd 0
PX:     dw 0
PY:     dw 0
CBD:    dd 0
CBX:    dw 0
CBY:    dw 0
TH:     dw 0
AJX:    dw 0
AJY:    dw 0
AJRX:   dw 0
AJRY:   dw 0
AJB:    dd 0
AJBB:   db 0
AJK:    db 0
NBTO:   db 0
FPB2:   db 0
FPB3:   db 0
FPI:    db 0
FPJ:    db 0
FB1:    ds 16
FB2:    ds 16
ROTT:   ds 4
U1:     ds 8
U2:     ds 8
FPX:    dw 0
FPY:    dw 0
FPPOS:  dd 0
FPQ32:  dd 0
FPQV:   dw 0
FDX:    dw 0
FDY:    dd 0
QLO1:   dw 0
QHI1:   dw 0
QLO2:   dw 0
QHI2:   dw 0
