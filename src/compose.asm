; ===========================================================================
;  Dibujo de un actor en tiles de sprite de 16x16 (model.compose_into).
;
;  Los miembros del costume se decodifican (RLE por columnas) a un lienzo de
;  hasta CMAXW x CMAXH tiles en SPRBUF ($6000), detras de los patrones de los
;  actores de su tipo ya compuestos en este paso (los de 4 bits en SPR_PAGE, los
;  de 8 en SPRB_PAGE: K_COMP pone la pagina, SPRUSED y SPRLIM; el lienzo no pasa
;  de SPRLIM: si no cabe, pierde filas de tiles), con el plano Z de la caja
;  donde esta el actor. Si la escala es menor que 255, cada dibujo pierde
;  filas y columnas: la k se queda si (k * escala) >> 8 cambia (tabla KEEPT).
;  Los costumes de 16 colores dan tiles de 4 bits (banco CABANK); los de 32,
;  tiles de 8 bits con los colores PAL8 + c. Al final se juntan los tiles que
;  tienen algo y se escriben sus atributos en ATTRBUF: los actores se componen
;  de delante atras y cada tile toma el sprite 63 - SPRK (los de delante,
;  encima). HIDEACT deja todo vacio al principio de cada paso.
; ===========================================================================

; Item (un miembro a dibujar): posicion de los datos, ancho, alto, x0, y0
IT_POS  EQU 0
IT_W    EQU 2
IT_H    EQU 4
IT_X0   EQU 6
IT_Y0   EQU 8
IT_SIZE EQU 10

COMPOSE:
        PMARK 8
        ; escala (setupActorScale) y tabla de filas/columnas que se quedan
        call SETUPSCALE
        call GETSCX
        ld (CSC),a
        call MKKEEP
        ; 4 u 8 bits
        ld a,(C_NCOL)
        cp 32
        ld a,0
        jr nz,.m4
        inc a
.m4:    ld (C8),a
        ; sus colores: la paleta de la habitacion vista a traves de la del costume,
        ; en el banco CABANK (4 bits) o en PAL8.. (8 bits)
        nextreg $43,%00100000       ; paleta de sprites
        ld a,(CABANK)
        add a,a
        add a,a
        add a,a
        add a,a
        ld (CBANKH),a
        ld b,16
        ld a,(C8)
        or a
        ld a,(CBANKH)
        jr z,.p4
        ld b,32
        ld a,PAL8
.p4:    nextreg $40,a
        ld hl,10
        ld c,0
.sp:    call CBYTE                  ; (setPalette: los del actor que no son $FF;
        push hl                     ; sin luz para actores, el 8 y el 12 a 0)
        ld e,a
        ld a,(VMON)
        or a
        jr z,.lit
        ld a,(VARS+2*VAR_CURRENT_LIGHTS)
        and 8
        jr nz,.lit
        ld e,8
        ld a,c
        cp 12
        jr nz,.col
        ld e,0
        jr .col
.lit:   ld hl,ACTOR+R_PAL
        ld a,c
        add hl,a
        ld a,(hl)
        cp $FF
        jr z,.col
        ld e,a
.col:   ld l,e
        ld h,0
        add hl,hl
        ld de,META+32
        add hl,de
        ld a,(hl)
        inc hl
        nextreg $44,a
        ld a,(hl)
        nextreg $44,a
        pop hl
        inc hl
        inc c
        djnz .sp
        PMARK 9
        ; espejo: mirando al este, sur o norte, o si el costume no se invierte
        ld l,(ix+A_FACE)
        ld h,(ix+A_FACE+1)
        call OLDDIR
        ld b,a
        ld a,(C_NOMIR)
        or b
        ld (CMIR),a
        ; plano Z: el que tenga fijo, ninguno si nunca se tapa, o la mascara de su
        ; caja; como mucho el numero de planos
        ld a,(ACTOR+R_CLIP)
        or a
        jr nz,.z1
        ld a,(VMON)
        or a
        jr z,.zb
        ld a,(ACTOR+R_NUM)
        ld l,a
        ld h,0
        ld a,CL_NEVERCLIP
        call GETCLASS
        or a
        jr nz,.z0
.zb:    ld a,(ix+A_BOX)
        cp INVALID
        jr z,.z0
        call BOXMASK
        jr .z1
.z0:    xor a
.z1:    ld hl,RNZ
        cp (hl)
        jr c,.zok
        ld a,(hl)
.zok:   ld (CZB),a
        or a
        jr z,.zoff
        add a,7                     ; (7 + plano) * alto: el plano en la tira
        ld e,a
        ld a,(RH)
        ld d,a
        mul d,e
        ld (CZOFF),de
.zoff:
        ; los miembros
        call LIMB0
.limb:  push bc
        ld de,A_CURPOS
        call LIMBP
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        and e
        inc a
        jp z,.nextl                 ; $FFFF
        pop bc
        push bc
        push de
        call BITC                   ; parado?
        ld a,l
        and (ix+A_STOP)
        ld b,a
        ld a,h
        and (ix+A_STOP+1)
        or b
        pop de
        jp nz,.nextl
        res 7,d
        ld hl,(C_CMDS)
        add hl,de
        call CBYTE
        and $7F
        cp $7B
        jp z,.nextl
        call SETCODE
        pop bc                      ; frameptr = 2 + tabla del miembro
        push bc
        ld a,c
        add a,a
        ld hl,(C_LIMBT)
        add hl,a
        call CWORD
        ld hl,2
        add hl,de
        ld a,(CCODE)
        add a,a
        add hl,a
        call CWORD                  ; posicion del dibujo
        ld hl,2
        add hl,de
        ld de,PICHDR                ; cabecera: w, h, rel_x, rel_y, move_x, move_y
        ld b,12
.hdr:   call CBYTE
        ld (de),a
        inc hl
        inc de
        djnz .hdr
        push hl                     ; datos RLE
        ld hl,(ITP)
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(PICHDR)              ; ancho
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(PICHDR+2)            ; alto
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        push hl
        ld hl,(XMOVE)               ; xmc = xmove + rel_x
        ld de,(PICHDR+4)
        add hl,de
        ex de,hl
        ld hl,(XMOVE)               ; xmove += move_x
        ld bc,(PICHDR+8)
        add hl,bc
        ld (XMOVE),hl
        ex de,hl                    ; xmc escalado
        call SCALEV
        ex de,hl
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        ld a,(CMIR)
        or a
        jr z,.flip
        add hl,de                   ; x0 = x + xmc
        jr .x0
.flip:  or a
        sbc hl,de                   ; x0 = x - xmc
.x0:    ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        push hl
        ld hl,(YMOVE)               ; ymc = ymove + rel_y
        ld de,(PICHDR+6)
        add hl,de
        ex de,hl
        ld hl,(YMOVE)               ; ymove -= move_y
        ld bc,(PICHDR+10)
        or a
        sbc hl,bc
        ld (YMOVE),hl
        ex de,hl                    ; ymc escalado
        call SCALEV
        ex de,hl
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        add hl,de                   ; y0 = y - elevacion + ymc
        ld de,(CELEV)
        or a
        sbc hl,de
        ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (ITP),hl
        ld hl,NITEMS
        inc (hl)
.nextl: pop bc
        inc c
        ld a,c
        cp 16
        jp nz,.limb
        PMARK 10
        ; caja que los contiene a todos (y sin ninguno, sin tiras)
        ld hl,$FFFF
        ld (ACTOR+R_STR0),hl
        ld (ACTOR+R_STR1),hl
        ld a,(NITEMS)
        or a
        ret z
        ld hl,$7FFF
        ld (BMINX),hl
        ld (BMINY),hl
        ld hl,$8000
        ld (BMAXX),hl
        ld (BMAXY),hl
        xor a
        ld (BANY),a
        ld iy,ITEMS
        ld a,(NITEMS)
        ld b,a
.bb:    push bc
        ld l,(iy+IT_W)
        ld h,(iy+IT_W+1)
        ld a,h
        or l
        jr z,.bbn
        ld e,(iy+IT_H)
        ld d,(iy+IT_H+1)
        ld a,d
        or e
        jr z,.bbn
        ld a,1
        ld (BANY),a
        call LASTN                  ; x1 = x0 +- ultima columna
        ex de,hl
        ld l,(iy+IT_X0)
        ld h,(iy+IT_X0+1)
        call BBX                    ; x0
        ld a,(CMIR)
        or a
        jr z,.bneg
        add hl,de
        jr .bx1
.bneg:  or a
        sbc hl,de
.bx1:   call BBX
        ld l,(iy+IT_H)              ; y0 y y0 + ultima fila
        ld h,(iy+IT_H+1)
        call LASTN
        ex de,hl
        ld l,(iy+IT_Y0)
        ld h,(iy+IT_Y0+1)
        call BBY
        add hl,de
        call BBY
.bbn:   ld de,IT_SIZE
        add iy,de
        pop bc
        djnz .bb
        ld a,(BANY)
        or a
        ret z
        ld hl,(BMINY)               ; lo que ocupa: arriba = max(0, y), abajo =
        bit 7,h                     ; min(alto, maxy + 1), tiras max(0, x) >> 3
        jr z,.t0
        ld hl,0
.t0:    ld (ACTOR+R_TOP),hl
        ld hl,(BMAXY)
        inc hl
        ld de,(RH)
        call CPS16
        jr c,.b0
        ex de,hl
.b0:    ld (ACTOR+R_BOT),hl
        ld hl,(BMINX)
        call STRIPOF
        ld (ACTOR+R_STR0),hl
        ld hl,(BMAXX)
        inc hl
        call STRIPOF
        ld (ACTOR+R_STR1),hl
        ld a,(SKIPDRAW)             ; (un paso sin pintar: solo hasta aqui, lo que
        or a                        ; ven los scripts)
        ret nz
        IFNDEF MTBUILD
        ld hl,K_ZFRESH              ; si no se ve, tampoco; si se ve, las tiras
        ld a,OVK_PAGE               ; atrasadas que tapa, al dia (sus planos Z)
        call OVCALL
        ret c
        ENDIF
        PMARK 14
        ; tw = min(CMAXW, (maxx - bx + 16) >> 4), igual th
        ld hl,(BMAXX)
        ld de,(BMINX)
        or a
        sbc hl,de
        ld de,16
        add hl,de
        call SHR4
        cp CMAXW+1
        jr c,.tw
        ld a,CMAXW
.tw:    ld (CTW),a
        ld hl,(BMAXY)
        ld de,(BMINY)
        or a
        sbc hl,de
        ld de,16
        add hl,de
        call SHR4
        cp CMAXH+1
        jr c,.th
        ld a,CMAXH
.th:    ld (CTH),a
        ; el lienzo va tras los patrones de los anteriores de su tipo (K_COMP pone la
        ; pagina, SPRUSED y SPRLIM); caben (SPRLIM - inicio) / 128 o / 256 tiles
        ld hl,(SPRUSED)
        ld (CSTART),hl
        ex de,hl
        ld hl,(SPRLIM)
        or a
        sbc hl,de
        ld a,(C8)
        or a
        jr nz,.f8
        add hl,hl
.f8:    ld b,h                      ; B = tiles que caben
        ex de,hl                    ; tile del principio: inicio / 128 o / 256
        or a
        jr nz,.b8
        add hl,hl
.b8:    ld a,h
        ld (CBT),a
        ld (PUTPIX.cbt+1),a
        ld (PUTPIX8.cbt+1),a
        ld a,(CTW)                  ; tw * th > B: th = B / tw
        ld e,a
        ld a,(CTH)
        ld d,a
        mul d,e
        ld a,b
        cp e
        jr nc,.n8
        ld a,(CTW)
        ld c,a
        ld a,b
        ld b,0
.dv:    sub c
        jr c,.dd
        inc b
        jr .dv
.dd:    ld a,b
        ld (CTH),a
        or a
        ret z                       ; no cabe ni una fila
.n8:    ld a,(CTH)
        ld e,a
        ld a,(CTW)
        ld d,a
        mul d,e
        ld a,e
        ld (CNT),a                  ; tiles del lienzo
        ld a,(CTW)
        add a,a
        add a,a
        add a,a
        add a,a
        ld (CW16),a
        ld a,(CTH)
        add a,a
        add a,a
        add a,a
        add a,a
        ld (CH16),a
        call PAINTSETUP             ; (el pintor por rachas, para este lienzo)
        ld a,(VMON)                 ; el mismo dibujo que la ultima vez? (cache de
        or a                        ; cada actor, en la capa OVK): sus tiles y sus
        jr z,.nk                    ; atributos, sin pintar
        ld hl,K_CACHEUSE
        ld a,OVK_PAGE
        call OVCALL
        ret c
.nk:    PMARK 15
        ; limpia el lienzo (CNT tiles de 128 o 256 bytes) y el hueco hasta el
        ld a,(CNT)
        ld l,a
        ld h,0
        call TSIZE
        ld de,(CSTART)
        add hl,de
        ld de,(SPRUSED)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ld hl,SPRBUF
        add hl,de
        ld (hl),0
        ld d,h
        ld e,l
        inc de
        dec bc
        ld a,b
        or c
        jr z,.it0
        ldir
.it0:   ; dibuja los miembros, en orden
        PMARK 11
        ld iy,ITEMS
        ld a,(NITEMS)
        ld b,a
.it:    push bc
        call DRAWITEM
        ld de,IT_SIZE
        add iy,de
        pop bc
        djnz .it
        PMARK 12
        call PACKTILES
        PMARK 13
        ld a,(VMON)                 ; y a la cache, para la proxima vez
        or a
        ret z
        ld hl,K_CACHESAVE
        ld a,OVK_PAGE
        jp OVCALL

; HL = HL * (128 o 256): bytes de HL tiles
; HL = max(0, HL) >> 3
STRIPOF:
        bit 7,h
        jr z,.p
        ld hl,0
.p:     srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ret

TSIZE:
        ld a,(C8)
        or a
        jr nz,.t8
        ld h,l                      ; * 128 = (n << 8) >> 1
        ld l,0
        srl h
        rr l
        ret
.t8:    ld h,l
        ld l,0
        ret

; HL = HL * escala >> 8 (con signo), si la escala no es 255
SCALEV:
        ld a,(CSC)
        cp 255
        ret z
        ld e,a
        ld d,0
        call MULS16
        ld l,h
        ld h,e
        ret

; HL = ultima posicion de un dibujo de HL pixeles: n - 1, o (n - 1) * escala >> 8
LASTN:
        dec hl
        ld a,(CSC)
        cp 255
        ret z
        ld e,a
        ld d,0
        call MULU16
        ld l,h
        ld h,e
        ret

; BMINX/BMAXX con HL (no cambia HL ni DE)
BBX:
        push de
        ld de,(BMINX)
        call CPS16
        jr nc,.n1
        ld (BMINX),hl
.n1:    ld de,(BMAXX)
        ex de,hl
        call CPS16
        ex de,hl
        jr nc,.n2
        ld (BMAXX),hl
.n2:    pop de
        ret
BBY:
        push de
        ld de,(BMINY)
        call CPS16
        jr nc,.n1
        ld (BMINY),hl
.n1:    ld de,(BMAXY)
        ex de,hl
        call CPS16
        ex de,hl
        jr nc,.n2
        ld (BMAXY),hl
.n2:    pop de
        ret

; A = HL >> 4, saturado a 255
SHR4:
        ld a,h
        or a
        jr nz,.big
        ld a,l
        rrca
        rrca
        rrca
        rrca
        and $0F
        ret
.big:   bit 7,h
        ld a,0
        ret nz
        ld a,255
        ret

; ---------------------------------------------------------------------------
; Dibuja el item IY en el lienzo
DRAWITEM:
        ld l,(iy+IT_W)
        ld h,(iy+IT_W+1)
        ld a,h
        or l
        ret z
        ld (DCOLS),hl
        ld l,(iy+IT_H)
        ld h,(iy+IT_H+1)
        ld a,h
        or l
        ret z
        xor a                       ; por rachas (PAINTCOL), si se puede
        ld (FFAST),a
        call PAINTPREP
        jr c,.nf
        ld a,1
        ld (FFAST),a
.nf:
        ld l,(iy+IT_POS)            ; el RLE desde aqui
        ld h,(iy+IT_POS+1)
        call CMAP
        ld (CSPTR),hl
        ld hl,0
        ld (CREM),hl
        xor a
        ld (DCK),a
        ld l,(iy+IT_X0)             ; DX = x0 - paso: cada columna que se queda avanza
        ld h,(iy+IT_X0+1)
        ld a,(CMIR)
        or a
        jr z,.l0
        dec hl
        jr .l1
.l0:    inc hl
.l1:    ld (DX),hl
.col:   ld a,(DCK)                   ; se queda la columna?
        ld hl,KEEPT
        add hl,a
        ld a,(hl)
        or a
        jr z,.cskip
        ld hl,(DX)
        ld a,(CMIR)
        or a
        jr z,.cl
        inc hl
        jr .cs
.cl:    dec hl
.cs:    ld (DX),hl
        ld de,(BMINX)               ; cx = x - bx
        or a
        sbc hl,de
        bit 7,h
        jr nz,.cskip
        ld a,h
        or a
        jr nz,.cskip
        ld a,(CW16)
        ld b,a
        ld a,l
        cp b
        jr nc,.cskip
        ld (DCX),a
        xor a
        ld (DOFF),a
        ld hl,(DX)
        call ZCOL
        jr .rows
.cskip: ld a,1
        ld (DOFF),a
.rows:  ld a,(FFAST)
        or a
        jr z,.slow
        call PAINTCOL
        jp .ncol
.slow:  ld l,(iy+IT_Y0)             ; DY = y0 - 1
        ld h,(iy+IT_Y0+1)
        dec hl
        ld (DY),hl
        ld l,(iy+IT_H)
        ld h,(iy+IT_H+1)
        ld (DROWS),hl
        xor a
        ld (DRJ),a
.row:   call NEXTCOL
        ld c,a
        ld a,(DRJ)                   ; se queda la fila?
        ld hl,KEEPT
        add hl,a
        ld a,(hl)
        or a
        jr z,.skip
        ld hl,(DY)
        inc hl
        ld (DY),hl
        ld a,c
        or a
        jr z,.skip
        ld a,(DOFF)
        or a
        jr nz,.skip
        ld hl,(DY)                  ; 0 <= y < alto de la habitacion
        bit 7,h
        jr nz,.skip
        ld de,(RH)
        call CPS16
        jr nc,.skip
        ld de,(BMINY)               ; cy = y - by < th*16
        or a
        sbc hl,de
        ld a,h
        or a
        jr nz,.skip
        ld a,(CH16)
        ld b,a
        ld a,l
        cp b
        jr nc,.skip
        ld (DCY),a
        ld hl,(CZPTR)               ; tapado por el plano Z?
        ld a,h
        or l
        jr z,.draw
        ld de,(DY)
        add hl,de
        ld a,(CZBIT)
        and (hl)
        jr nz,.skip
.draw:  ld a,(C8)
        or a
        jr nz,.d8
        call PUTPIX
        jr .skip
.d8:    call PUTPIX8
.skip:  ld hl,DRJ
        inc (hl)
        ld hl,(DROWS)
        dec hl
        ld (DROWS),hl
        ld a,h
        or l
        jr nz,.row
.ncol:  ld hl,DCK                    ; siguiente columna
        inc (hl)
        ld hl,(DCOLS)
        dec hl
        ld (DCOLS),hl
        ld a,h
        or l
        jp nz,.col
        ret

; A = siguiente color del RLE (en CSPTR, con CREM y CCOL)
NEXTCOL:
        ld hl,(CREM)
        ld a,h
        or l
        call z,RUNHDR
        ld hl,(CREM)
        dec hl
        ld (CREM),hl
        ld a,(CCOL)
        ret

; La cabecera de la racha siguiente: CCOL = color, CREM = cuantos (1-256)
RUNHDR:
        call CRDB
        ld b,a
        ld a,(C_NCOL)
        cp 32
        jr z,.c32
        ld a,b
        and $0F
        ld l,a
        ld a,b
        rrca
        rrca
        rrca
        rrca
        and $0F
        jr .got
.c32:   ld a,b                      ; 32 colores: 5 bits de color, 3 de racha
        and $07
        ld l,a
        ld a,b
        rrca
        rrca
        rrca
        and $1F
.got:   ld (CCOL),a
        ld h,0
        ld a,l
        or a
        jr nz,.st
        call CRDB                   ; la longitud va en el byte siguiente
        ld l,a
        ld h,0
        or a
        jr nz,.st
        inc h                       ; 0 = 256
.st:    ld (CREM),hl
        ret


; A = siguiente byte del costume (CSPTR en $E000-$FFFF, cambia de pagina)
CRDB:
        ld hl,(CSPTR)
        ld a,h
        or a
        jr nz,.rd
        ld a,(CPAGE)
        inc a
        ld (CPAGE),a
        call MAP7
        ld hl,$E000
.rd:    ld a,(hl)
        inc hl
        ld (CSPTR),hl
        ret

; Prepara el plano Z de la columna x = HL: CZPTR (0 = sin mascara) y CZBIT
ZCOL:
        ld a,(CZB)
        or a
        jr z,.none
        bit 7,h
        jr nz,.none
        ld de,(RW)
        call CPS16
        jr nc,.none
        ld a,l
        and 7
        ld b,a
        ld a,$80
        jr z,.b0
.bl:    srl a
        djnz .bl
.b0:    ld (CZBIT),a
        srl h                       ; tira = x >> 3
        rr l
        srl h
        rr l
        srl h
        rr l
        ld d,h
        ld e,l
        add hl,hl
        add hl,de                   ; 3 * tira
        ld de,(STRIPT)
        add hl,de
        ld a,(hl)
        add a,STRIP_PAGE
        ld (SHMMU6),a
        nextreg $56,a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(CZOFF)
        add hl,de
        ld (CZPTR),hl
        ret
.none:  ld hl,0
        ld (CZPTR),hl
        ret

; Pixel de color C en (DCX, DCY) del lienzo de 4 bits
PUTPIX:
        ld a,(DCY)
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld d,a
        ld a,(CTW)
        ld e,a
        mul d,e                     ; ty * tw
        ld a,(DCX)
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a,e
.cbt:   add a,0                     ; tile (< 64): + el primero del lienzo
        ld h,a                      ; tile * 128 = (tile >> 1) << 8 | (tile & 1) << 7
        ld l,0
        srl h
        rr l
        ld a,(DCY)                  ; + (cy & 15) * 8
        and 15
        add a,a
        add a,a
        add a,a
        ld e,a
        ld a,(DCX)                  ; + (cx & 15) >> 1
        and 15
        srl a
        add a,e
        or l
        ld l,a
        ld a,h
        add a,SPRBUF>>8
        ld h,a
        ld a,(DCX)
        and 1
        jr nz,.lo
        ld a,c                      ; pixel izquierdo: nibble alto
        rlca
        rlca
        rlca
        rlca
        ld b,a
        ld a,(hl)
        and $0F
        or b
        ld (hl),a
        ret
.lo:    ld a,(hl)
        and $F0
        or c
        ld (hl),a
        ret

; Pixel de color C en (DCX, DCY) del lienzo de 8 bits: PAL8 + C
PUTPIX8:
        ld a,(DCY)
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
.cbt:   add a,0                     ; tile (< 32): + el primero del lienzo
        add a,SPRBUF>>8
        ld h,a
        ld a,(DCY)
        and 15
        add a,a
        add a,a
        add a,a
        add a,a
        ld l,a
        ld a,(DCX)
        and 15
        or l
        ld l,a
        ld a,c
        add a,PAL8
        ld (hl),a
        ret

; ---------------------------------------------------------------------------
; Junta los tiles con algo al principio de SPRBUF y escribe sus atributos
PACKTILES:
        xor a
        ld (PN),a
        ld (PT),a
        ld (PTY),a
.ty:    xor a
        ld (PTX),a
.tx:    ld a,(PT)
        call TILEADDR
        push hl
        ld a,(C8)                   ; tiene algo? (128 o 256 bytes)
        or a
        ld b,128
        jr z,.b
        ld b,0
.b:     xor a
.chk:   or (hl)
        inc hl
        djnz .chk
        pop hl
        or a
        jr z,.empty
        ld a,(PN)
        ld b,a
        ld a,(PT)
        cp b
        jr z,.same
        push hl
        ld a,b
        call TILEADDR
        ex de,hl
        ld l,1
        ld h,0
        call TSIZE
        ld b,h
        ld c,l
        pop hl
        ldir
.same:  ld a,(PTY)                  ; (donde va cada uno, para la cache: TLIST)
        add a,a
        add a,a
        add a,a
        add a,a
        ld hl,PTX
        or (hl)
        ld hl,PN
        ld e,(hl)
        ld d,0
        ld hl,TLIST
        add hl,de
        ld (hl),a
        call TATTR
        ld hl,PN
        inc (hl)
.empty: ld hl,PT
        inc (hl)
        ld hl,PTX
        inc (hl)
        ld a,(CTW)
        cp (hl)
        jr nz,.tx
        ld hl,PTY
        inc (hl)
        ld a,(CTH)
        cp (hl)
        jr nz,.ty
        ld a,(PN)                   ; los patrones acaban detras de estos
        ld l,a
        ld h,0
        call TSIZE
        ld de,(CSTART)
        add hl,de
        ld (SPRUSED),hl
        ld a,(PN)
        ld hl,SPRK
        add a,(hl)
        ld (hl),a
        ret

; HL = SPRBUF + (CBT + A) * (128 o 256): el tile A del lienzo
TILEADDR:
        ld hl,CBT
        add a,(hl)
        ld l,a
        ld h,0
        call TSIZE
        ld a,h
        add a,SPRBUF>>8
        ld h,a
        ret

; Atributos del tile PN: (PTX, PTY) del lienzo. Patron CBT + PN y sprite
; 63 - (SPRK + PN)
TATTR:
        ld a,(CBT)
        ld hl,PN
        add a,(hl)
        ld (TPAT),a
        ld a,(SPRK)                 ; HL = ATTRBUF + 5*sprite
        add a,(hl)
        cpl
        add a,NSPR_ACTOR
        ld e,a
        ld d,5
        mul d,e
        ld hl,ATTRBUF
        add hl,de
        push hl
        ld a,(PTX)                  ; sx = bx + 16*tx - left
        add a,a
        add a,a
        add a,a
        add a,a
        ld de,(BMINX)
        ex de,hl
        add hl,a
        ld de,(LEFT)
        or a
        sbc hl,de
        ld (TSX),hl
        ld a,(PTY)                  ; sy = ROOM_Y0 + by + 16*ty
        add a,a
        add a,a
        add a,a
        add a,a
        add a,ROOM_Y0
        ld hl,(BMINY)
        add hl,a
        ld a,(SHAKEY)               ; con el temblor, mas abajo
        add hl,a
        ld (TSY),hl
        pop hl
        ld a,(TSX)
        ld (hl),a
        inc hl
        ld a,(TSY)
        ld (hl),a
        inc hl
        ld a,(C8)
        or a
        jr nz,.a8
        ld a,(TSX+1)                ; 4 bits: banco del actor
        and 1
        ld b,a
        ld a,(CBANKH)
        or b
        ld (hl),a
        inc hl
        ld a,(TPAT)
        srl a
        or $C0
        ld (hl),a
        inc hl
        ld a,(TPAT)
        and 1
        rrca
        rrca                        ; bit 0 -> bit 6
        or $80
        ld b,a
        ld a,(TSY+1)
        and 1
        or b
        ld (hl),a
        ret
.a8:    ld a,(TSX+1)                ; 8 bits: el patron entero, desde el hueco 32
        and 1
        ld (hl),a
        inc hl
        ld a,(TPAT)
        add a,$C0+32                ; (TPAT < 31)
        ld (hl),a
        inc hl
        ld a,(TSY+1)
        and 1
        ld (hl),a
        ret

; ---------------------------------------------------------------------------
CMIR:   db 0
CSC:    db 255
C8:     db 0
CZB:    db 0
CZOFF:  dw 0
CZPTR:  dw 0
CZBIT:  db 0
XMOVE:  dw 0
YMOVE:  dw 0
NITEMS: db 0
ITP:    dw 0
CCODE:  db 0
PICHDR: ds 12
ITEMS:  ds 16*IT_SIZE
BMINX:  dw 0
BMAXX:  dw 0
BMINY:  dw 0
BMAXY:  dw 0
BANY:   db 0
CTW:    db 0
CTH:    db 0
CNT:    db 0
CW16:   db 0
CH16:   db 0
DCOLS:  dw 0
DROWS:  dw 0
DX:     dw 0
DY:     dw 0
DCK:     db 0
DRJ:     db 0
DCX:    db 0
DCY:    db 0
DOFF:   db 0
CSPTR:  dw 0
CREM:   dw 0
CCOL:   db 0
FFAST:  db 0                        ; este dibujo, por rachas (PAINTCOL)
PN:     db 0
PT:     db 0
PTX:    db 0
PTY:    db 0
TSX:    dw 0
TSY:    dw 0
TPAT:   db 0
CABANK: db ACTOR_BANK               ; banco de paleta del actor (lo pone quien llama)
CBANKH: db 0
CELEV:  dw 0                        ; su elevacion (lo pone quien llama)
CSTART: dw 0                        ; donde empieza su lienzo en SPRBUF
CBT:    db 0                        ; su primer tile
SPRUSED: dw 0                       ; bytes de patrones de 4 bits de este paso
SPRLIM: dw 0                        ; hasta donde puede llegar este actor (K_COMP)
SPRK:   db 0                        ; sprites usados en este paso
KEEPT:  ds 256
KEEPC:  db 0                        ; (MKKEEP) la escala de KEEPT
KEEPV:  db 0                        ; y si ya se hizo
