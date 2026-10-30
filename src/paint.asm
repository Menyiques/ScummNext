; ===========================================================================
;  Pintar un dibujo de un actor columna a columna y racha a racha (DRAWITEM lo
;  usa si el dibujo no empieza por encima de la habitacion y tiene menos de 256
;  filas; si no, va pixel a pixel; PAINTSETUP y PAINTPREP, en paintprep.asm). En cada columna la direccion del lienzo
;  (HL) y la del plano Z (DE) bajan fila a fila; el RLE se lee con HL' y, con
;  escala, que filas se quedan (KEEPT) con DE'. IYH cuenta las filas de la
;  columna que se pintan e IYL las que faltan para el tile de debajo. Lo que
;  cambia con el formato (4 u 8 bits, 16 o 32 colores), la columna (nibble alto
;  o bajo), el plano Z y la escala va en constantes de las instrucciones.
; ===========================================================================

; --- para cada actor, cuando ya se sabe su lienzo (COMPOSE) --------------------
PAINTSETUP:
        ld a,(CTW)                  ; del ultimo tile al de debajo: tw * 128 - 15 * 8
        ld e,a                      ; (8 bits: tw * 256 - 15 * 16)
        ld d,128
        mul d,e
        ld bc,-120
        ld a,(C8)
        or a
        ld a,8
        jr z,.s4
        ex de,hl
        add hl,hl
        ex de,hl
        ld bc,-240
        ld a,16
.s4:    ld (PRUN.rs+1),a               ; una fila: 8 (o 16) bytes
        ld (PTRN.rs+1),a
        ld (PSRUN.rs+1),a
        ld (PSTRN.rs+1),a
        ex de,hl
        add hl,bc
        ld (PRUN.fs+2),hl
        ld (PTRN.fs+2),hl
        ld (PSRUN.fs+2),hl
        ld (PSTRN.fs+2),hl
        ld a,(C_NCOL)               ; el RLE: 16 colores (largo de 4 bits, color de 4)
        cp 32                       ; o 32 (3 y 5)
        ld a,$0F
        ld b,$0F                    ; (rrca)
        ld c,$0F
        jr nz,.c16
        ld a,$07
        ld b,$00                    ; (nop)
        ld c,$1F
.c16:   ld (PHDR.lm+1),a
        ld a,b
        ld (PHDR.r4),a
        ld a,c
        ld (PHDR.cm+1),a
        ret

; --- una columna (DOFF, DCX, CZPTR y CZBIT ya puestos; el RLE en CSPTR, CREM, CCOL) --
PAINTCOL:
        ld a,(DOFF)
        or a
        jr nz,.all
        ld a,(PSLIM)
        or a
        jr nz,.go
.all:   ld a,(iy+IT_H)              ; no se pinta: solo se lee
        jp PCONSUME
.go:    ld a,(PSKIP)                ; (las de encima de la habitacion: solo se leen)
        or a
        call nz,PCONSUME
        push iy
        ld a,(PCY0)                 ; el lienzo: tile = primero + (cy >> 4) * tw + (cx >> 4)
        ld c,a
        and 15
        neg
        add a,16
        ld (PIYL),a
        ld a,c
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld d,a
        ld a,(CTW)
        ld e,a
        mul d,e
        ld a,(DCX)
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a,e
        ld e,a
        ld a,(CBT)
        add a,e
        ld h,a
        ld l,0
        ld a,(C8)
        or a
        jr nz,.a8
        srl h                       ; 4 bits: tile * 128 + (cy & 15) * 8 + (cx & 15) / 2
        rr l
        ld a,c
        and 15
        add a,a
        add a,a
        add a,a
        ld e,a
        ld a,(DCX)
        and 15
        srl a
        add a,e
        or l
        ld l,a
        ld a,(DCX)                  ; columna par: el nibble alto; impar: el bajo
        and 1
        ld a,$0F
        ld de,PP4H
        jr z,.am
        ld a,$F0
        ld de,PP4L
        jr .am
.a8:    ld a,c                      ; 8 bits: tile * 256 + (cy & 15) * 16 + (cx & 15)
        and 15
        add a,a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld a,(DCX)
        and 15
        or e
        ld l,a
        xor a
        ld de,PP8
.am:    ld (PRUN.am+1),a
        ld (PSRUN.am+1),a
        ld (PCP+1),de
        ld a,h
        add a,SPRBUF>>8
        ld h,a
        push hl
        ld hl,(CZPTR)               ; el plano Z: CZPTR + y0 (sin plano, nunca tapa)
        ld a,h
        or l
        jr z,.nz
        ld de,(PY0)
        add hl,de
        ld a,(CZBIT)
.nz:    ld (PRUN.zb+1),a
        ld (PSRUN.zb+1),a
        ex de,hl
        pop hl
        ld a,(PSKIP)
        exx
        ld hl,(CSPTR)
        ld de,KEEPT
        add de,a
        exx
        ld a,(PIYL)
        ld iyl,a
        ld a,(PSLIM)
        ld iyh,a
        ld a,(CREM+1)               ; la racha que iba (CREM: lo que le queda; 0: otra)
        or a
        ld a,(CREM)
        ld b,a
        jr nz,.cur                  ; (256: B = 0)
        or a
        jr z,PHDR
.cur:   ld a,(CCOL)
        or a
        jr PCOLOR

; La racha siguiente del RLE: B = cuantas filas (0 = 256) y C = su color
PHDR:
        exx
        ld a,h
        or a
        call z,PNEXTPG
        ld a,(hl)
        inc hl
        exx
        ld c,a
.lm:    and $0F                     ; el largo (32 colores: los 3 bits bajos)
        ld b,a
        jr nz,.l
        exx                         ; 0: va en el byte siguiente (0 = 256)
        ld a,h
        or a
        call z,PNEXTPG
        ld a,(hl)
        inc hl
        exx
        ld b,a
.l:     ld a,c
        rrca
        rrca
        rrca
.r4:    rrca                        ; (32 colores: nop)
.cm:    and $0F                     ; el color (32 colores: $1F)
        ld (CCOL),a
PCOLOR: jr z,PJT
PCP:    jp PP4H                     ; (el color, segun la columna)
PP4H:   add a,a
        add a,a
        add a,a
        add a,a
        ld c,a
PJR:    jp PRUN                     ; (sin escala o con ella)
PP4L:   ld c,a
        jr PJR
PP8:    add a,PAL8
        ld c,a
        jr PJR
PJT:    jp PTRN

; (con HL' a $0000) el RLE sigue en la pagina siguiente
PNEXTPG:
        ld a,(CPAGE)
        inc a
        ld (CPAGE),a
        call MAP7
        ld hl,$E000
        ret

; Sin escala: B filas del color C
PRUN:   ld a,(de)
.zb:   and 0                       ; (el bit del plano Z)
        jr nz,.s
        ld a,(hl)
.am:   and $0F                     ; (lo que se queda del byte: $0F, $F0 o nada)
        or c
        ld (hl),a
.s:     inc de
        dec iyh
        jr z,.end
        dec iyl
        jr z,.t
        ld a,l
.rs:   add a,8
        ld l,a
        djnz PRUN
        jp PHDR
.t:
.fs:   add hl,0                    ; (al tile de debajo)
        ld iyl,16
        djnz PRUN
        jp PHDR
.end:   dec b
        jp PCOLEND

; Sin escala: B filas transparentes
PTRN:   inc de
        dec iyh
        jr z,.end
        dec iyl
        jr z,.t
        ld a,l
.rs:   add a,8
        ld l,a
        djnz PTRN
        jp PHDR
.t:
.fs:   add hl,0
        ld iyl,16
        djnz PTRN
        jp PHDR
.end:   dec b
        jp PCOLEND

; Con escala: B filas de origen del color C (solo bajan las que se quedan)
PSRUN:  exx
        ld a,(de)
        inc de
        exx
        or a
        jr z,.nk
        ld a,(de)
.zb:   and 0
        jr nz,.s
        ld a,(hl)
.am:   and $0F
        or c
        ld (hl),a
.s:     inc de
        dec iyl
        jr z,.t
        ld a,l
.rs:   add a,8
        ld l,a
.nk:    dec iyh
        jr z,.end
        djnz PSRUN
        jp PHDR
.t:
.fs:   add hl,0
        ld iyl,16
        jr .nk
.end:   dec b
        jp PCOLEND

; Con escala: B filas de origen transparentes
PSTRN:  exx
        ld a,(de)
        inc de
        exx
        or a
        jr z,.nk
        inc de
        dec iyl
        jr z,.t
        ld a,l
.rs:   add a,8
        ld l,a
.nk:    dec iyh
        jr z,.end
        djnz PSTRN
        jp PHDR
.t:
.fs:   add hl,0
        ld iyl,16
        jr .nk
.end:   dec b
        jp PCOLEND

; Fin de las filas que se pintan: B = lo que le queda a la racha (0: otra); el
; resto de la columna solo se lee
PCOLEND:
        pop iy
        ld a,b
        ld (CREM),a
        xor a
        ld (CREM+1),a
        exx
        ld (CSPTR),hl
        exx
        ld a,(PSKIP)
        ld b,a
        ld a,(iy+IT_H)
        sub b
        ld hl,PSLIM
        sub (hl)
        ret z
; A filas del RLE sin pintar (desde CSPTR, CREM y CCOL)
PCONSUME:
        ld c,a
.lp:    ld hl,(CREM)
        ld a,h
        or l
        jr nz,.h
        push bc
        call RUNHDR
        pop bc
        ld hl,(CREM)
.h:     ld a,h                      ; mas de las que quedan: CREM -= C, y ya
        or a
        jr nz,.more
        ld a,l
        cp c
        jr z,.eq
        jr nc,.more
        ld a,c                      ; menos: C -= CREM, y otra racha
        sub l
        ld c,a
        ld hl,0
        ld (CREM),hl
        jr .lp
.eq:    ld hl,0
        ld (CREM),hl
        ret
.more:  ld b,0
        or a
        sbc hl,bc
        ld (CREM),hl
        ret

PY0:    dw 0
PCY0:   db 0
PSLIM:  db 0
PSKIP:  db 0
CGEN:   dw 0                        ; cambia con la habitacion y sus planos Z (cache)
TLIST:  ds 64                       ; donde va cada tile juntado: ty * 16 + tx
PIYL:   db 0

; (COMPOSE) Antes de los miembros: sin desplazamiento, sin items y ningun dibujo
; (CCODES: el de cada miembro, $FF si no se pinta; es la firma de la cache). C = 0
LIMB0:
        ld hl,0
        ld (XMOVE),hl
        ld (YMOVE),hl
        xor a
        ld (NITEMS),a
        ld hl,ITEMS
        ld (ITP),hl
        ld hl,CCODES
        ld b,16
.ff:    ld (hl),$FF
        inc hl
        djnz .ff
        ld c,a
        ret

; (COMPOSE) El miembro C pinta el dibujo A
SETCODE:
        ld (CCODE),a
        ld hl,CCODES
        ld b,a
        ld a,c
        add hl,a
        ld (hl),b
        ret

CCODES: ds 16

