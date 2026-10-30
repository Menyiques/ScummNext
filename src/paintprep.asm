; ===========================================================================
;  El pintor por rachas (paint.asm, en el banco 0): lo que se prepara para cada
;  actor y para cada dibujo
; ===========================================================================

; --- para cada dibujo (IY = el item): carry si no se puede -----------------------
; PY0 = y0, PCY0 = su fila en el lienzo, PSLIM = filas de origen que se pintan en
; cada columna (las de debajo del fondo de la habitacion o del lienzo no)
PAINTPREP:
        ld a,(iy+IT_H+1)
        or a
        scf
        ret nz
        xor a
        ld (PSKIP),a
        ld l,(iy+IT_Y0)
        ld h,(iy+IT_Y0+1)
        bit 7,h
        jr z,.y0
        call NEGHL                  ; empieza por encima de la habitacion: se salta
        ld a,h                      ; hasta la fila de destino -y0
        or a
        jp nz,.none
        ld c,l
        ld a,(CSC)
        inc a
        ld a,c                      ; (sin escala: esas mismas filas de origen)
        jr z,.sk
        ld hl,KEEPT                 ; con escala: hasta la que se queda con ese numero
        ld b,(iy+IT_H)
        ld e,0
.s0:    ld a,(hl)
        or a
        jr z,.n0
        ld a,c
        or a
        jr z,.d0
        dec c
.n0:    inc hl
        inc e
        djnz .s0
.d0:    ld a,e
.sk:    cp (iy+IT_H)
        jp nc,.none
        ld (PSKIP),a
        ld hl,0                     ; y desde ahi, la fila 0
.y0:    ld (PY0),hl
        ld de,(BMINY)
        or a
        sbc hl,de
        ld a,l
        ld (PCY0),a
        ld hl,(RH)                  ; filas de destino: hasta el fondo de la habitacion
        ld de,(PY0)
        or a
        sbc hl,de
        ld b,0
        jr c,.k1
        ld b,255
        ld a,h
        or a
        jr nz,.k1
        ld b,l
.k1:    ld a,(CH16)                 ; y del lienzo
        ld hl,PCY0
        sub (hl)
        jr nc,.k2
        xor a
.k2:    cp b
        jr c,.k3
        ld a,b
.k3:    ld c,a                      ; C = filas de destino
        ld a,(CSC)
        inc a
        jr nz,.sc
        ld hl,PRUN                  ; sin escala: min(alto, C)
        ld (PJR+1),hl
        ld hl,PTRN
        ld (PJT+1),hl
        ld a,(PSKIP)
        ld b,a
        ld a,(iy+IT_H)
        sub b
        cp c
        jr c,.s1
        ld a,c
.s1:    ld (PSLIM),a
        or a
        ret
.sc:    ld hl,PSRUN                 ; con escala: hasta la fila que se queda y no cabe
        ld (PJR+1),hl
        ld hl,PSTRN
        ld (PJT+1),hl
        ld a,(PSKIP)
        ld e,a
        ld a,(iy+IT_H)
        sub e
        ld b,a
        ld hl,KEEPT
        ld d,0
        add hl,de
        ld e,0
.sl:    ld a,(hl)
        or a
        jr z,.sn
        ld a,c
        or a
        jr z,.sd
        dec c
.sn:    inc hl
        inc e
        djnz .sl
.sd:    ld a,e
        ld (PSLIM),a
        or a
        ret
.none:  xor a                       ; no se ve nada: solo se lee
        ld (PSKIP),a
        ld (PSLIM),a
        ret

