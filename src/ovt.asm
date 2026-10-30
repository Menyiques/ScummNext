; ===========================================================================
;  Capa OVT (pagina OVT_PAGE, en $C000): textos y verbos (tools/ui.py)
;
;  - pixeles en Layer 2: la pantalla principal (con el scroll de la
;    habitacion: columna = (LEFT + x) mod 320) y la de verbos (sin scroll);
;  - las fuentes de CHARS.DAT, el mensaje con sus escapes resuelto en MSGBUF,
;    los saltos de linea, printChar, drawString y CHARSET_1;
;  - pintar los verbos: de texto o de imagen (VERBIMG.DAT).
;  No usa IX ni IY. Lo que pinta deja MMU2 como estaba (L2DONE).
; ===========================================================================

; --- Layer 2 --------------------------------------------------------------------
; Pixel A en la pantalla PXVS (0 principal, 1 verbos): x = HL de pantalla,
; y = DE dentro de la pantalla virtual. Cambia BC.
PUTPX:
        ld (PXC),a
        ld a,h                      ; 0 <= x < 320
        or a
        jr z,.x1
        cp 1
        ret nz
        ld a,l
        cp 64
        ret nc
.x1:    ld a,d
        or a
        ret nz
        ld a,(PXVS)
        or a
        ld a,(MAINH)
        jr nz,.verb
        cp e
        ret c
        ret z
        ld a,e
        add a,ROOM_Y0
        ld e,a
        push de
        ld de,(LEFT)                ; columna = (LEFT + x) mod 320
        add hl,de
        ld de,320
.md:    or a
        sbc hl,de
        jr nc,.md
        add hl,de
        pop de
        jr .wr
.verb:  ld c,a
        ld a,200
        sub c
        cp e
        ret c
        ret z
        ld b,0                      ; (el menu: en la que se ve)
        ld a,(VDIRECT)
        or a
        jr nz,.vr
        ld a,(VMIN)                 ; los verbos se pintan en la pantalla que no se
        cp e                        ; ve (B; A durante una transicion) y al final del
        jr c,.v1                    ; paso VFLUSH pasa a la vista las filas que han
        ld a,e                      ; cambiado (los scripts pueden encender y apagar
        ld (VMIN),a                 ; verbos en el mismo paso: que no se vea)
.v1:    ld a,(VMAX)
        cp e
        jr nc,.v2
        ld a,e
        ld (VMAX),a
.v2:    ld a,(HIDDEN)
        or a
        jr nz,.vr
        ld b,L2B_PAGE-L2_PAGE
.vr:    ld a,e
        add a,c
        add a,ROOM_Y0
        ld e,a
        jr .wr2
.wr:    ld b,0
.wr2:   ld a,l                      ; pagina = L2_PAGE (o L2B_PAGE) + columna >> 5
        srl h
        rra
        srl a
        srl a
        srl a
        srl a
        add a,L2_PAGE
        add a,b
        ld c,a
        ld a,(L2CUR)
        cp c
        jr z,.m
        ld a,c
        ld (L2CUR),a
        nextreg $52,a
.m:     ld a,l
        and 31
        add a,$40
        ld h,a
        ld l,e
        ld a,(PXC)
        ld (hl),a
        ret

; Las filas [VMIN, VMAX] de la pantalla de verbos, de B (donde se pintan) a la que
; se ve (A). Al final de cada paso, como SCUMM, que solo ensena la pantalla entera.
; (Durante una transicion se ve B y se pinta en A: nada hasta que acabe.)
VFLUSH:
        ld a,(HIDDEN)
        or a
        ret nz
        jr VCOPY
; Al acabar la transicion (F_FADEIN): lo pintado en A durante ella, tambien en B
VSYNCB:
        ld a,1
VCOPY:  ld (VDIR),a                 ; 0: de B a A; 1: de A a B
        ld a,(MAINH)                ; (solo las de la pantalla de verbos de ahora: si
        ld b,a                      ; ha crecido la principal, las de antes ya no son)
        ld a,200
        sub b
        jr z,.none
        dec a
        ld hl,VMAX
        cp (hl)
        jr nc,.mx
        ld (hl),a
.mx:    ld a,(VMAX)
        ld hl,VMIN
        sub (hl)
        jr c,.none
        inc a
        ld (VFN),a
        ld a,(MAINH)
        add a,(hl)
        add a,ROOM_Y0
        ld (VFR),a
        ld a,(SHMMU7)
        push af
        xor a
.pg:    ld (VFP),a
        add a,L2_PAGE
        nextreg $52,a
        ld a,(VFP)
        add a,L2B_PAGE
        call MAP7
        ld a,(VFR)
        ld l,a
        ld e,a
        ld h,$E0
        ld d,$40
        ld a,(VDIR)
        or a
        jr z,.d
        ex de,hl
.d:     ld b,32
.c:     push bc
        push hl
        push de
        ld a,(VFN)
        ld c,a
        ld b,0
        ldir
        pop de
        pop hl
        inc h
        inc d
        pop bc
        djnz .c
        ld a,(VFP)
        inc a
        cp 10
        jr nz,.pg
        pop af
        call MAP7
        call L2DONE
.none:  ld a,$FF
        ld (VMIN),a
        xor a
        ld (VMAX),a
        ret
VFN:    db 0
VFR:    db 0
VFP:    db 0
VDIR:   db 0

; Deja MMU2 como estaba (META)
L2DONE:
        ld a,$FF
        ld (L2CUR),a
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; Rectangulo [FX0, FX1) x [FY0, FY1) de la pantalla PXVS con el color A
; (recortado a la pantalla virtual)
FILLVS:
        ld (FCOL),a
        ld a,(PXVS)
        or a
        ld a,(MAINH)
        jr z,.h
        ld c,a
        ld a,200
        sub c
.h:     ld l,a                      ; alto de la pantalla virtual
        ld h,0
        ld (FVH),hl
        ld hl,(FX0)                 ; x0 = max(x0, 0), x1 = min(x1, 320)
        bit 7,h
        jr z,.a1
        ld hl,0
        ld (FX0),hl
.a1:    ld hl,(FX1)
        ld de,320
        call CPS16
        jr c,.a2
        ld (FX1),de
.a2:    ld hl,(FY0)
        bit 7,h
        jr z,.a3
        ld hl,0
        ld (FY0),hl
.a3:    ld hl,(FY1)
        ld de,(FVH)
        call CPS16
        jr c,.a4
        ld (FY1),de
.a4:    ld hl,(FX0)
        ld de,(FX1)
        call CPS16
        ret nc
        ld hl,(FY0)
        ld de,(FY1)
        call CPS16
        ret nc
        ld hl,(FX0)                 ; por columnas: la primera fila de la primera con
        ld de,(FY0)                 ; PUTPX (su pagina, VMIN y donde va) y lo demas
        ld a,(FCOL)                 ; detras: la columna siguiente es H + 1 (de $5F a
        call PUTPX                  ; $40 en la pagina siguiente; de la decima, a la
        ld a,(FY0)                  ; primera de esa pantalla)
        ld b,a
        ld a,(FY1)
        sub b
        ld (FN),a
        ld a,l
        ld (FL0),a
        ld a,(FCOL)
        ld e,a
        ld a,(FN)
        dec a
        ld b,a
        inc l
        call FILLN
        ld a,(L2CUR)
        ld c,L2_PAGE
        cp L2B_PAGE
        jr c,.b
        ld c,L2B_PAGE
.b:     ld a,c
        add a,10
        ld (FBASE),a
        push hl
        ld hl,(FX1)
        ld bc,(FX0)
        or a
        sbc hl,bc
        dec hl
        ld (FXC),hl
        pop hl
.col:   ld a,(FXC)
        ld b,a
        ld a,(FXC+1)
        or b
        jr z,.last
        inc h
        ld a,h
        cp $60
        jr nz,.sp
        ld h,$40
        ld a,(L2CUR)
        inc a
        ld c,a
        ld a,(FBASE)
        cp c
        ld a,c
        jr nz,.np
        sub 10
.np:    ld (L2CUR),a
        nextreg $52,a
.sp:    ld a,(FL0)
        ld l,a
        ld a,(FN)
        ld b,a
        call FILLN
        ld bc,(FXC)
        dec bc
        ld (FXC),bc
        jr .col
.last:  ld hl,(FY1)                 ; (y la ultima fila otra vez, para VMAX)
        dec hl
        ex de,hl
        ld hl,(FX0)
        ld a,(FCOL)
        jp PUTPX
FN:     db 0                        ; (FILLVS) las filas
FL0:    db 0                        ; el byte de la primera
FBASE:  db 0                        ; la pagina detras de la pantalla

; B bytes de color E desde HL hacia abajo en la columna (L + 1); B = 0: nada. Cambia
; A, B, C y L
FILLN:  ld a,b
        and 7
        ld c,a
        srl b
        srl b
        srl b
        jr z,.r
.o:     ld (hl),e
        inc l
        ld (hl),e
        inc l
        ld (hl),e
        inc l
        ld (hl),e
        inc l
        ld (hl),e
        inc l
        ld (hl),e
        inc l
        ld (hl),e
        inc l
        ld (hl),e
        inc l
        djnz .o
.r:     ld b,c
        inc b
        jr .rr
.r1:    ld (hl),e
        inc l
.rr:    djnz .r1
        ret

; carry si la tira A se ve (CAM_SS <= A < CAM_SS + 40 y A < RNS)
VISIBLE_S:
        ld c,a
        ld a,(RNS)
        ld b,a
        ld a,c
        cp b
        ret nc
        ld a,(CAM_SS)
        ld b,a
        ld a,c
        sub b
        ret c
        cp 40
        ret

; A = HL acotado a 0..255
CLAMP8:
        bit 7,h
        jr nz,.z
        ld a,h
        or a
        ld a,l
        ret z
        ld a,255
        ret
.z:     xor a
        ret

; Vuelve a pintar las filas [DSY0, DSY1) de las tiras de la habitacion con x de
; habitacion en [HL, DE)
REDRAWX:
        push hl
        push de
        call L2DONE                 ; DRAWSTRIP lee la tabla de tiras de META
        pop de
        pop hl
        ld a,(CURROOM)
        or a
        ret z
        push de
        call CPS16                  ; nada si x1 <= x0
        pop de
        ret nc
        bit 7,h
        jr z,.p
        ld hl,0
.p:     call SHR3
        ld a,l
        ld (RXS),a
        ex de,hl
        dec hl
        call SHR3
        ld a,l
        ld (RXE),a
        bit 7,h
        ret nz
.lp:    ld a,(RXS)
        call VISIBLE_S
        jr nc,.n
        ld a,(RXS)
        call DRAWSTRIPR             ; (solo las filas DSY0..DSY1)
        ld a,$FF
        ld (L2CUR),a
.n:     ld a,(RXS)
        ld hl,RXE
        cp (hl)
        ret z
        inc a
        ld (RXS),a
        jr .lp

; --- pantallas virtuales ------------------------------------------------------------
; A = pantalla de la y = HL (0 principal, 1 verbos, $FF ninguna)
FINDVS:
        bit 7,h
        jr nz,.no
        ld a,h
        or a
        jr nz,.no
        ld a,(MAINH)
        cp l
        jr z,.v
        jr c,.v
        xor a                       ; y < MAINH
        ret
.v:     ld a,l
        cp 200
        jr nc,.no
        ld a,1
        ret
.no:    ld a,$FF
        ret
; HL = y de arriba de la pantalla A; DE = su alto
VSTOP:
        or a
        ld hl,0
        ld a,(MAINH)
        ld e,a
        ld d,0
        ret z
        ld l,a
        ld a,200
        sub l
        ld e,a
        ret

; --- fuentes -------------------------------------------------------------------
; La fuente CURID: FONTP (lineal del byte 21 del bloque), FBPP, FONTH, FONTN
SETFONT:
        xor a
        ld (FONTN),a
        ld (FONTN+1),a
        ld (FONTH),a
        ld a,(CURID)
        cp 8
        ret nc
        ld c,a
        add a,a
        add a,c
        ld hl,0
        ld l,a
        ld a,CHARP
        call FARSET
        call FARGET
        ld e,a
        call FARGET
        ld d,a
        call FARGET
        cp $FF
        ret z
        ex de,hl                    ; A:HL = posicion en CHARS.DAT
        ld de,21
        add hl,de
        adc a,0
        ld c,a
        ld a,h                      ; + CHARP * 8192
        add a,(CHARP & 7) << 5
        ld h,a
        ld a,c
        adc a,CHARP >> 3
        ld (FONTP),hl
        ld (FONTP+2),a
        ld (FARP),hl
        ld (FARP+2),a
        call FARGET
        ld (FBPP),a
        call FARGET
        ld (FONTH),a
        call FARGET
        ld (FONTN),a
        call FARGET
        ld (FONTN+1),a
        ret

; El caracter A en GLYPH (ancho, alto, dx, dy y los bits); carry si existe
GETGLYPH:
        call GLYPHHD
        ret nc
        ld a,(GLYPH)                ; bytes = (ancho * alto * bpp + 7) / 8
        ld e,a
        ld a,(GLYPH+1)
        ld d,a
        mul d,e
        ld a,(FBPP)
        cp 2
        jr nz,.b1
        ex de,hl
        add hl,hl
        ex de,hl
.b1:    ld hl,7
        add hl,de
        call SHR3
        ld a,h
        or a
        jr nz,.big
        ld a,l
        cp GLYPHMAX-4
        jr c,.ok
.big:   ld a,GLYPHMAX-4
.ok:    ld c,a
        ld b,0
        ld de,GLYPH+4
        call FARCPY
        scf
        ret
; Solo la cabecera del caracter A (ancho, alto, dx, dy) en GLYPH: carry si existe, y
; FARP en sus bits
GLYPHHD:
        ld l,a
        ld h,0
        ld de,(FONTN)
        call CPU16
        ret nc
        add hl,hl                   ; tabla: fuente + 4 + 2 * c
        ld de,4
        add hl,de
        call FONTADD
        ld de,GLYPH
        ld bc,2
        call FARCPY
        ld hl,(GLYPH)
        ld a,h
        or l
        ret z                       ; desplazamiento 0: no hay
        xor a                       ; FARP = fuente + desplazamiento
        call FONTADDA
        ld de,GLYPH
        ld bc,4
        call FARCPY
        scf
        ret
; FARP = FONTP + HL
FONTADD:
        xor a
; FARP = FONTP + A:HL
FONTADDA:
        ld de,(FONTP)
        add hl,de
        ld e,a
        ld a,(FONTP+2)
        adc a,e
        ld (FARP),hl
        ld (FARP+2),a
        ret

; A = ancho del caracter A (ancho + dx, con signo)
CHARW:
        call GLYPHHD
        ld a,0
        ret nc
        ld a,(GLYPH)
        ld b,a
        ld a,(GLYPH+2)
        add a,b
        ret

; HL = ancho del texto de MSGBUF desde la posicion A (string_width)
STRWIDTH:
        ld (SWP),a
        ld hl,1
        ld (SWW),hl
.lp:    ld a,(SWP)
        call MSGAT
        ld hl,SWP
        inc (hl)
        or a
        jr z,.end
        cp 13
        jr z,.end
        cp '@'
        jr z,.lp
        cp $FF
        jr z,.esc
        cp $FE
        jr nz,.ch
.esc:   ld a,(SWP)
        call MSGAT
        ld hl,SWP
        inc (hl)
        cp 3
        jr z,.end
        cp 10
        jr z,.skip2
        cp 12
        jr z,.skip2
        cp 13
        jr z,.skip2
        cp 14
        jr z,.skip2
        cp 9
        jr z,.end
        cp 1
        jr z,.end
        cp 2
        jr z,.end
        cp 8
        jr nz,.ch
.sp:    ld a,(SWP)                  ; 8: se salta los espacios y uno mas
        call MSGAT
        cp 32
        jr nz,.sp1
        ld hl,SWP
        inc (hl)
        jr .sp
.sp1:   ld hl,SWP
        inc (hl)
        jr .lp
.skip2: ld hl,SWP
        inc (hl)
        inc (hl)
        jr .lp
.ch:    call CHARW
        ld e,a
        ld d,0
        bit 7,a
        jr z,.add
        dec d
.add:   ld hl,(SWW)
        add hl,de
        ld (SWW),hl
        jr .lp
.end:   ld hl,(SWW)
        ret
; A = MSGBUF[A]
MSGAT:
        ld hl,(MSGP)
        add hl,a
        ld a,(hl)
        ret

; Cambia por un 13 el ultimo espacio de cada linea mas ancha que DE (desde BUFPOS)
LINEBREAKS:
        ld (LBMAX),de
        ld a,(BUFPOS)
        ld (SWP),a
        ld a,$FF
        ld (LBSPACE),a
        ld hl,1
        ld (SWW),hl
.lp:    ld a,(SWP)
        call MSGAT
        ld hl,SWP
        inc (hl)
        or a
        ret z
        cp '@'
        jr z,.lp
        cp $FF
        jr z,.esc
        cp $FE
        jr nz,.ch
.esc:   ld a,(SWP)
        call MSGAT
        ld hl,SWP
        inc (hl)
        cp 3
        ret z
        cp 2
        ret z
        cp 1
        jr z,.nl
        cp 8
        jr z,.nl
        cp 10
        jr z,.s2
        cp 12
        jr z,.s2
        cp 13
        jr z,.s2
        cp 9
        jr z,.s2
        cp 14
        jr nz,.ch
.s2:    ld hl,SWP
        inc (hl)
        inc (hl)
        jr .lp
.nl:    ld hl,1
        ld (SWW),hl
        jr .lp
.ch:    cp 32
        jr nz,.w
        ld b,a
        ld a,(SWP)
        dec a
        ld (LBSPACE),a
        ld a,b
.w:     call CHARW
        ld e,a
        ld d,0
        bit 7,a
        jr z,.add
        dec d
.add:   ld hl,(SWW)
        add hl,de
        ld (SWW),hl
        ld a,(LBSPACE)
        cp $FF
        jr z,.lp
        ld de,(LBMAX)
        ex de,hl
        call CPS16                  ; maxwidth < curw ?
        jp nc,.lp
        ld a,(LBSPACE)
        ld hl,(MSGP)
        add hl,a
        ld (hl),13
        inc a
        ld (SWP),a
        ld hl,1
        ld (SWW),hl
        ld a,$FF
        ld (LBSPACE),a
        jp .lp

; --- mensajes: escapes ----------------------------------------------------------------
; Copia el mensaje de FARP a MSGBUF[CVOUT...] resolviendo 4 (numero), 5 (verbo),
; 6 (nombre) y 7 (cadena), sin las @. CVDEPTH: profundidad.
CONVERT:
        call L2DONE                 ; (los nombres de la habitacion estan en META)
.lp:    call FARGET
        or a
        ret z
        cp $FF
        jr z,.esc
        cp $FE
        jr z,.esc
        cp '@'
        jr z,.lp
        call CVPUT
        jr .lp
.esc:   call FARGET
        ld (CVK),a
        cp 1
        jr z,.two
        cp 2
        jr z,.two
        cp 3
        jr z,.two
        cp 8
        jr z,.two
        call FARGET
        ld l,a
        call FARGET
        ld h,a
        ld (CVVAL),hl
        ld a,(CVDEPTH)
        cp 4
        jr nc,.lp
        ld a,(CVK)
        cp 4
        jr z,.num
        cp 5
        jr z,.verb
        cp 6
        jr z,.name
        cp 7
        jr z,.str
        ld a,$FF                    ; los demas, tal cual
        call CVPUT
        ld a,(CVK)
        call CVPUT
        ld a,(CVVAL)
        call CVPUT
        ld a,(CVVAL+1)
        call CVPUT
        jr .lp
.two:   ld a,$FF
        call CVPUT
        ld a,(CVK)
        call CVPUT
        jr .lp
.num:   ld hl,(CVVAL)
        call READNUM
        call CVDEC
        jp .lp
.verb:  ld hl,(CVVAL)
        call READNUM
        call VERBTEXT
        jp .lp
.name:  ld hl,(CVVAL)
        call READNUM
        call NAMETEXT
        jp .lp
.str:   ld hl,(CVVAL)               ; (en v5, la cadena misma: no una variable)
        call STRTEXT
        jp .lp
; A al final de MSGBUF (como mucho 254 bytes)
CVPUT:
        push hl
        ld hl,CVOUT
        ld l,(hl)
        ld h,0
        push af
        ld a,l
        cp 254
        jr nc,.full
        ld a,(CVOUT)
        inc a
        ld (CVOUT),a
        ld a,l
        ld hl,(MSGP)
        add hl,a
        pop af
        ld (hl),a
        pop hl
        ret
.full:  pop af
        pop hl
        ret
; El numero HL (con signo) en decimal
CVDEC:
        bit 7,h
        jr z,.pos
        ld a,'-'
        call CVPUT
        ex de,hl
        ld hl,0
        or a
        sbc hl,de
.pos:   ld b,0                      ; cifras en la pila
.div:   ld de,10
        call DIVU16                 ; HL = HL / 10, A = resto
        add a,'0'
        push af
        inc b
        ld a,h
        or l
        jr nz,.div
.out:   pop af
        call CVPUT
        djnz .out
        ret
; HL = HL / DE (sin signo), A = resto (DE < 256)
DIVU16:
        push bc
        ld b,16
        ld a,h
        ld c,l
        ld hl,0
.lp:    sla c
        rla
        adc hl,hl
        sbc hl,de
        jr nc,.ok
        add hl,de
        jr .nx
.ok:    inc c
.nx:    djnz .lp
        ld h,a
        ld a,l
        ld l,c
        pop bc
        ret
; Anidar: guarda FARP y la profundidad, convierte desde A:HL (lineal) y vuelve
CVNEST:
        push af
        ld de,(FARP)
        ld a,(FARP+2)
        ld c,a
        ld a,(CVDEPTH)
        ld b,a
        pop af
        push bc
        push de
        ld (FARP),hl
        ld (FARP+2),a
        ld a,(CVDEPTH)
        inc a
        ld (CVDEPTH),a
        call CONVERT
        pop de
        pop bc
        ld (FARP),de
        ld a,c
        ld (FARP+2),a
        ld a,b
        ld (CVDEPTH),a
        ret
; El nombre del verbo HL (de texto y sin guardar), o nada
VERBTEXT:
        ld a,h
        or a
        ret nz
        ld a,l
        or a
        ret z
        ld (CVNUM),a
        ld a,1
.lp:    ld (CVI),a
        call VSADDR
        ld a,(CVNUM)
        cp (hl)
        jr nz,.nx
        ld de,VS_TYPE
        add hl,de
        ld a,(hl)
        or a
        jr nz,.nx
        ld de,VS_SAVE-VS_TYPE
        add hl,de
        ld a,(hl)
        or a
        jr nz,.nx
        ld de,VS_HASN-VS_SAVE
        add hl,de
        ld a,(hl)
        or a
        ret z
        ld a,(CVI)
        ld c,1
        call HPTR
        ret nc
        jp CVNEST
.nx:    ld a,(CVI)
        inc a
        cp NUM_VERBS
        jr nz,.lp
        ret
; HL = la ranura de verbo A en UIP (y MMU7 en UIP)
VSADDR:
        ld e,a
        ld d,VSZ
        mul d,e
        ld hl,VSLOTS
        add hl,de
        ld a,UIP
        jp MAP7
; A:HL = lineal de los datos del monton (tipo C: 1 nombre de verbo, 2 cadena,
; 3 nombre nuevo; numero A); carry si los hay
HPTR:
        call HPSLOT
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        or e
        ret z
        ex de,hl
        ld a,HEAPP
        call LINOF
        scf
        ret
; HL = su entrada en la tabla de punteros (MMU7 en UIP)
HPSLOT:
        ld l,a
        ld h,0
        add hl,hl
        ld de,HP_VERB
        ld a,c
        cp 2
        jr c,.ok
        ld de,HP_STR
        jr z,.ok
        ld de,HP_NN
.ok:    add hl,de
        ld a,UIP
        jp MAP7
; El nombre del objeto o actor HL
NAMETEXT:
        ld a,h
        or l
        ret z
        ld a,h
        or a
        jr nz,.notact
        ld a,l
        cp NACT
        jr nc,.notact
        ld e,a                      ; nombre de actor: ANAMES + 32 * n
        ld d,32
        mul d,e
        ld hl,ANAMES-$E000
        add hl,de
        ld a,UIP
        call LINOF
        jp CVNEST
.notact:
        ld (CVOBJ),hl
        call NNFIND                 ; los nombres nuevos
        jr nc,.inv
        ld c,3
        call HPTR
        jr nc,.inv
        jp CVNEST
.inv:   ld hl,(CVOBJ)
        call INVNAME
        jr nc,.room
        jp CVNEST
.room:  ld a,(CURROOM)
        or a
        ret z
        ld hl,(CVOBJ)
        call OBJINDEX
        cp $FF
        ret z
        call OBJPTR
        ld de,O_NAME
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        cp $FF
        ret z
        ex de,hl                    ; + STRIP_PAGE * 8192
        ld c,a
        ld a,h
        add a,(STRIP_PAGE & 7) << 5
        ld h,a
        ld a,c
        adc a,STRIP_PAGE >> 3
        jp CVNEST
; A:HL = lineal de la pagina A mas HL (A * 8192 + HL)
LINOF:
        ld c,a
        and 7
        rrca
        rrca
        rrca
        add a,h
        ld h,a
        push af
        ld a,c
        srl a
        srl a
        srl a
        ld c,a
        pop af
        ld a,c
        adc a,0
        ret
; Nombre nuevo del objeto CVOBJ: carry y A:HL = su lineal
NNFIND:
        ld a,UIP
        call MAP7
        ld hl,NNOBJ
        ld b,0
.lp:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,(CVOBJ)
        or a
        sbc hl,de
        pop hl
        jr z,.got
        inc b
        ld a,b
        cp NUM_NN
        jr nz,.lp
        or a
        ret
.got:   ld a,b                      ; A = su indice
        scf
        ret
; La cadena HL
STRTEXT:
        ld a,h
        or a
        ret nz
        ld a,l
        or a
        ret z
        cp NUM_STR
        ret nc
        ld e,a
        ld hl,STRSZ
        add hl,a
        ld a,(hl)
        or a
        ret z
        ld a,e
        ld c,2
        call HPTR
        ret nc
        jp CVNEST

; --- el inventario (los nombres, de INVOBJ.DAT) ---------------------------------------
; Si el objeto HL esta en el inventario: carry y A:HL = lineal de su nombre
INVNAME:
        push hl
        call INVFIND
        pop hl
        ret nc
        call INVREC
        ret nc
        ld hl,2                     ; el largo del bloque VERB
        ld (FRLEN),hl
        xor a
        ld (FRPAGE),a
        ld hl,IRV
        ld (FRADDR),hl
        ld hl,INVOBJNAME
        call CFREAD
        jr c,.no
        ld hl,(FROFF)               ; el nombre va detras del bloque
        ld de,(IRV)
        add hl,de
        inc hl
        inc hl
        ld (FROFF),hl
        ld hl,64
        ld (FRLEN),hl
        ld a,INVP
        ld (FRPAGE),a
        ld hl,NMBUFI
        ld (FRADDR),hl
        ld hl,INVOBJNAME
        call CFREAD
        jr c,.no
        ld a,INVP                   ; (que acabe en 0)
        call MAP7
        xor a
        ld (NMBUFI+63),a
        ld hl,NMBUFI-$E000
        ld a,INVP
        call LINOF
        scf
        ret
.no:    or a
        ret
; FROFF = posicion del registro del objeto HL en INVOBJ.DAT; carry si lo hay
INVREC:
        ex de,hl
        ld a,UIP
        call MAP7
        ld hl,(IIDX)
        ex de,hl
        call CPU16                  ; objeto < cuantos
        ret nc
        add hl,hl
        ld de,IIDX+2
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        and e
        inc a
        jr nz,.ok
        or a
        ret
.ok:    ld hl,(IIDX)
        add hl,hl
        inc hl
        inc hl
        add hl,de
        ld (FROFF),hl
        ld hl,0
        ld (FROFF+2),hl
        scf
        ret
; Si el objeto HL esta en la lista del inventario: carry, INVI = su indice
INVFIND:
        ld a,h
        or l
        ret z
        ex de,hl
        ld a,UIP
        call MAP7
        ld hl,INVOBJ
        ld b,0
.lp:    ld a,(hl)
        inc hl
        cp e
        jr nz,.n1
        ld a,(hl)
        cp d
        jr z,.got
.n1:    inc hl
        inc b
        ld a,b
        cp NUM_INV
        jr nz,.lp
        or a
        ret
.got:   ld a,b
        ld (INVI),a
        scf
        ret

; --- printChar ---------------------------------------------------------------------
; El caracter A en (TXL, TXT); PCIGN = 1: no se borra (texto de sistema)
PRINTCHAR:
        ld (PCC),a
        ld hl,(TXT)
        call FINDVS
        cp $FF
        jr nz,.vs
        ld a,(FONTH)
        ld hl,(TXT)
        add hl,a
        call FINDVS
        cp $FF
        ret z
.vs:    ld (PCVS),a
        ld a,(PCC)
        cp '@'
        ret z
        ld a,(TXCOL)
        ld (TCMAP+1),a
        ld a,(PCC)
        call GETGLYPH
        ret nc
        ld a,(TXDISOFF)
        or a
        jr z,.dx
        xor a
        ld (GLYPH+2),a
.dx:    ld a,(TXFIRST)
        or a
        jr z,.nf
        ld hl,0
        ld (STRR),hl
        ld (STRR+2),hl
        ld (STRR+4),hl
        ld (STRR+6),hl
.nf:    ld a,(GLYPH+3)              ; top += dy, left += dx
        call SXA
        ld hl,(TXT)
        add hl,de
        ld (TXT),hl
        ld a,(GLYPH+2)
        call SXA
        ld hl,(TXL)
        add hl,de
        ld (TXL),hl
        ld a,(GLYPH)                ; left + w > right + 1 o left < 0: no se pinta
        ld e,a
        ld d,0
        add hl,de
        ld de,(TXRIGHT)
        inc de
        ex de,hl
        call CPS16                  ; right + 1 < left + w ?
        jr c,.skip
        ld hl,(TXL)
        bit 7,h
        jr z,.draw
.skip:  ld a,(GLYPH)
        ld hl,(TXL)
        add hl,a
        ld (TXL),hl
        jp .undy
.draw:  xor a
        ld (TXDISOFF),a
        ld a,(TXFIRST)
        or a
        jr z,.nf2
        xor a
        ld (TXFIRST),a
        ld hl,(TXL)
        ld (STRR),hl
        ld (STRR+4),hl
        ld hl,(TXT)
        ld (STRR+2),hl
        ld (STRR+6),hl
.nf2:   ld hl,(STRR)                ; str.left = min(...), str.top = min(...)
        ld de,(TXL)
        call CPS16
        jr c,.m1
        ld (STRR),de
.m1:    ld hl,(STRR+2)
        ld de,(TXT)
        call CPS16
        jr c,.m2
        ld (STRR+2),de
.m2:    ld a,(PCVS)                 ; drawtop = top - arriba de la pantalla
        call VSTOP
        ld (PCVH),de
        ex de,hl
        ld hl,(TXT)
        or a
        sbc hl,de
        ld (PCDT),hl
        ld a,(PCIGN)
        or a
        jr nz,.nomask
        ld a,1
        ld (HASMASK),a
        ld a,(PCVS)
        ld (MASKSCR),a
        or a
        jr nz,.vr
        ld hl,(TXL)                 ; principal: x de habitacion (sin habitacion, la
        ld a,(CURROOM)              ; de pantalla: UI.xstart)
        or a
        jr z,.mx
        ld de,(LEFT)
        add hl,de
.mx:    ld de,MASKR
        ld bc,MASKV
        call GROW
        jr .nomask
.vr:    ld hl,(TXL)
        ld de,VRECT
        ld bc,VRECTV
        call GROW
.nomask:
        ld a,(PCIGN)                ; (0: con mascara en la principal: a la capa del texto)
        ld hl,PCVS
        or (hl)
        ld (PCTM),a
        ; los pixeles
        ld a,(PCVS)
        ld (PXVS),a
        ld hl,GLYPH+4
        ld (PCBP),hl
        ld a,(hl)
        ld (PCBITS),a
        ld a,8
        ld (PCNB),a
        xor a
        ld (PCY),a
        ld a,(GLYPH)                ; (hasta 64 columnas: su sitio en Layer 2, una vez)
        cp 65
        jp nc,.srow
        call PCSETUP
.row:   ld a,(PCY)
        ld hl,GLYPH+1
        cp (hl)
        jp nc,.done
        ld hl,(PCDT)                ; yy = drawtop + y
        add hl,a
        ld (PCYY),hl
        ld de,(PCVH)                ; yy >= alto: se acaba
        call CPS16
        jp nc,.done
        xor a
        ld (PCRW),a
        ld (PCX),a
        ld a,(PCYY)                 ; (con yy >= 0, su byte en la columna)
        ld hl,PCROF
        add a,(hl)
        ld (PCRL),a
        ld hl,(PCYY)                ; con yy >= 0, la fila entera de una vez
        bit 7,h
        jr nz,.px
        call PCROWF
        jr .nrow
.px:    ld a,(PCX)                  ; (yy < 0: solo sus bits)
        ld hl,GLYPH
        cp (hl)
        jr nc,.nrow
        call NEXTBITS
        ld hl,PCX
        inc (hl)
        jr .px
.nrow:  ld a,(PCRW)                 ; VMIN/VMAX como PUTPX (verbos sin VDIRECT)
        or a
        jr z,.nr2
        ld a,(PCVM)
        or a
        jr z,.nr2
        ld a,(PCYY)
        ld e,a
        ld a,(VMIN)
        cp e
        jr c,.v1
        ld a,e
        ld (VMIN),a
.v1:    ld a,(VMAX)
        cp e
        jr nc,.nr2
        ld a,e
        ld (VMAX),a
.nr2:   ld hl,PCY
        inc (hl)
        jp .row
.srow:   ld a,(PCY)
        ld hl,GLYPH+1
        cp (hl)
        jp nc,.done
        ld hl,(PCDT)                ; yy = drawtop + y
        add hl,a
        ld (PCYY),hl
        ld de,(PCVH)                ; yy >= alto: se acaba
        call CPS16
        jp nc,.done
        xor a
        ld (PCX),a
.spx:    ld a,(PCX)
        ld hl,GLYPH
        cp (hl)
        jr nc,.snrow
        call NEXTBITS               ; A = color del pixel
        or a
        jr z,.snp
        ld hl,(PCYY)
        bit 7,h
        jr nz,.snp
        ld hl,TCMAP
        add hl,a
        ld a,(hl)
        ld hl,(PCX)
        ld h,0
        ld de,(TXL)
        add hl,de
        ld de,(PCYY)
        push hl
        push de
        call PUTPX
        pop de
        pop hl
        ld a,(PCTM)
        or a
        call z,TMSET
.snp:    ld hl,PCX
        inc (hl)
        jr .spx
.snrow:  ld hl,PCY
        inc (hl)
        jr .srow
.done:  ld a,(SHMMU7)               ; (PCSETUP pone ahi la capa del texto)
        nextreg $57,a
        ld a,(GLYPH)                ; left += w
        ld hl,(TXL)
        add hl,a
        ld (TXL),hl
        ld de,(STRR+4)              ; str.right = max(str.right, left)
        ex de,hl
        call CPS16
        jr nc,.r1
        ld (STRR+4),de
.r1:    ld a,(GLYPH+1)              ; str.bottom = max(str.bottom, top + h)
        ld hl,(TXT)
        add hl,a
        ex de,hl
        ld hl,(STRR+6)
        call CPS16
        jr nc,.undy
        ld (STRR+6),de
.undy:  ld a,(GLYPH+3)              ; top -= dy
        call SXA
        ld hl,(TXT)
        or a
        sbc hl,de
        ld (TXT),hl
        ret
; (PRINTCHAR) Lo que PUTPX y TMSET calculan para cada pixel, una vez por caracter: de
; cada columna (TXL + x) su pagina de Layer 2 y su H (GCOL; pagina 0: fuera de la
; pantalla) y su byte de la fila 0 y su bit en la capa del texto; el byte de la fila 0
; de Layer 2 (PCROF) y si hay que apuntar VMIN/VMAX (PCVM). Con la capa del texto
; (PCTM = 0), su pagina por $E000 hasta el final del caracter.
PCSETUP:
        ld hl,0                     ; (PCROWF: 1 o 2 bits por pixel)
        ld (PCROWF.q3),hl
        ld (PCROWF.q2),hl
        ld (PCROWF.zq),hl
        xor a
        ld (PCROWF.q2+2),a
        ld (PCROWF.zr),a
        ld a,(FBPP)
        cp 2
        jr nz,.b1
        ld hl,$21CB                 ; sla c
        ld (PCROWF.q2),hl
        ld a,$17                    ; rla
        ld (PCROWF.q2+2),a
        ld hl,$2DDD                 ; dec ixl
        ld (PCROWF.q3),hl
        ld hl,$3FCB                 ; srl a
        ld (PCROWF.zq),hl
        ld a,$87                    ; add a,a
        ld (PCROWF.zr),a
.b1:    ld hl,0                     ; (PCROWF: con la capa del texto, nop nop; sin ella,
        ld a,(PCTM)                 ; jr .t0)
        or a
        jr nz,.t1
        ld a,TMASK_PAGE
        nextreg $57,a
        jr .t2
.t1:    ld hl,$18 | (((PCROWF.t0 - PCROWF.tj - 2) & $FF) << 8)
.t2:    ld (PCROWF.tj),hl
        ld a,(PCVS)
        call VSPARM
        ld a,(GLYPH)
        or a
        ret z
        ld b,a
        xor a
        ld (PCCF),a
        ld hl,(TXL)
        ld de,GCOL
.c:     push hl
        ld a,h                      ; 0 <= x < 320
        or a
        jr z,.x1
        cp 1
        jp nz,.no
        ld a,l
        cp 64
        jp nc,.no
.x1:    ld a,(PCVS)
        or a
        jr nz,.wr
        ld a,(PCCF)                 ; principal: columna = (LEFT + x) mod 320 (detras de
        or a                        ; otra que se ve, la siguiente)
        jr z,.c0
        ld hl,(PCCOL)
        inc hl
        ld a,h
        dec a
        jr nz,.cs
        ld a,l
        cp 64
        jr c,.cs
        ld hl,0
        jr .cs
.c0:    push de
        ld de,(LEFT)
        add hl,de
        ld de,320
.md:    or a
        sbc hl,de
        jr nc,.md
        add hl,de
        pop de
        ld a,1
        ld (PCCF),a
.cs:    ld (PCCOL),hl
.wr:    push hl
        ld a,l                      ; pagina = L2_PAGE + PCBO + columna >> 5
        srl h
        rra
        srl a
        srl a
        srl a
        srl a
        add a,L2_PAGE
        ld c,a
        ld a,(PCBO)
        add a,c
        ld (de),a
        inc de
        pop hl
        ld a,l
        and 31
        add a,$40
        ld (de),a
        inc de
        ld a,l                      ; la capa del texto: $E000 + (columna >> 3) * 200
        and 7                       ; y el bit 1 << (columna & 7)
        ld c,a
        srl h
        rr l
        srl l
        srl l
        push de
        ld d,l
        ld e,200
        mul d,e
        ld hl,$E000
        add hl,de
        pop de
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,PCBIT
        ld a,c
        add de,a
        ld a,(de)
        ld (hl),a
        inc hl
        ex de,hl
        jr .nx
.no:    xor a
        ld (de),a
        ld (PCCF),a
        ld hl,5
        add hl,de
        ex de,hl
.nx:    pop hl
        inc hl
        dec b
        jp nz,.c
        ret
PCBIT:  db 1,2,4,8,16,32,64,128
PCCOL:  dw 0                        ; (PCSETUP) la columna de Layer 2 de la anterior
PCCF:   db 0                        ; y si se veia
; Como PUTPX en la pantalla A (0 principal, 1 verbos): la pagina de Layer 2 desde
; L2_PAGE (PCBO: los verbos, en B si no es directo ni hay transicion), el byte de su
; fila 0 (PCROF) y si hay que apuntar VMIN/VMAX (PCVM)
VSPARM: ld c,a
        xor a
        ld (PCBO),a
        ld (PCVM),a
        ld a,c
        or a
        ld a,ROOM_Y0
        jr z,.ro
        ld a,(VDIRECT)
        or a
        jr nz,.vd
        ld a,1
        ld (PCVM),a
        ld a,(HIDDEN)
        or a
        jr nz,.vd
        ld a,L2B_PAGE-L2_PAGE
        ld (PCBO),a
.vd:    ld a,(MAINH)
        add a,ROOM_Y0
.ro:    ld (PCROF),a
        ret
; (PRINTCHAR) Una fila del caracter con yy >= 0: los bits en C (quedan IXL), GCOL en
; DE, el byte de la fila en IXH; como NEXTBITS, PUTPX y (con la capa del texto) TMSET
PCROWF: push ix
        ld a,(GLYPH)
        ld b,a
        ld de,GCOL
        ld a,(PCBITS)
        ld c,a
        ld a,(PCNB)
        ld ixl,a
        ld a,(PCRL)
        ld ixh,a
        ld a,(PCYY)                 ; (la fila en la capa del texto)
        ld (.yy+1),a
.p:     ld a,c                      ; los bits que quedan del byte, todos 0: esos pixeles
        or a                        ; (hasta el final de la fila) de una vez
        jr z,.z
        xor a
        sla c
        rla
.q2:    nop                         ; (2 bits por pixel: sla c / rla)
        nop
        nop
        dec ixl
.q3:    nop                         ; (2 bits: dec ixl)
        nop
        jr nz,.h
        ld hl,(PCBP)
        inc hl
        ld (PCBP),hl
        ld c,(hl)
        ld ixl,8
.h:     or a
        jr z,.n
        ld hl,TCMAP
        add hl,a
        ld a,(hl)
        ld (PXC),a
        ld a,(de)                   ; su pagina (0: fuera)
        or a
        jr z,.n
        ld hl,L2CUR
        cp (hl)
        jr z,.m
        ld (hl),a
        nextreg $52,a
.m:     ex de,hl                    ; HL = su columna en GCOL
        inc hl
        ld d,(hl)
        ld a,ixh
        ld e,a
        ld a,(PXC)
        ld (de),a
.tj:    jr .t0                      ; (con la capa del texto: nop nop)
        inc hl
        ld a,(hl)                   ; su byte: el de la fila 0 + yy
.yy:    add a,0
        ld e,a
        inc hl
        ld a,(hl)
        adc a,0
        ld d,a
        inc hl
        ld a,(de)
        or (hl)
        ld (de),a
        inc hl
        ex de,hl
        djnz .p
        jr .e
.t0:    ld a,1
        ld (PCRW),a
        ld de,4
        add hl,de
        ex de,hl
        djnz .p
        jr .e
.n:     ld hl,5
        add hl,de
        ex de,hl
        djnz .p
.e:     ld a,c
        ld (PCBITS),a
        ld a,ixl
        ld (PCNB),a
        pop ix
        ret
.z:     ld a,ixl                    ; n = min(los pixeles que quedan del byte, B)
.zq:    nop                         ; (2 bits por pixel: srl a)
        nop
        cp b
        jr c,.z1
        ld a,b
.z1:    ld h,a
        ld l,a                      ; DE + 5 n
        add a,a
        add a,a
        add a,l
        add a,e
        ld e,a
        adc a,d
        sub e
        ld d,a
        ld a,b                      ; B - n
        sub h
        ld b,a
        ld a,h                      ; IXL - n (sus bits)
.zr:    nop                         ; (2 bits: add a,a)
        ld l,a
        ld a,ixl
        sub l
        ld ixl,a
        jr nz,.zc
        ld hl,(PCBP)                ; (el byte siguiente)
        inc hl
        ld (PCBP),hl
        ld c,(hl)
        ld ixl,8
.zc:    ld a,b
        or a
        jp nz,.p
        jp .e
GCOL:   ds 5*64
PCBO:   db 0
PCVM:   db 0
PCROF:  db 0
PCRL:   db 0
PCRW:   db 0

; DE = A con signo
SXA:
        ld e,a
        ld d,0
        bit 7,a
        ret z
        dec d
        ret
; A = siguientes bits (FBPP) del caracter
NEXTBITS:
        ld a,(FBPP)
        cp 2
        ld a,(PCBITS)
        jr z,.two
        rlca
        ld (PCBITS),a
        and 1
        ld c,a
        ld a,(PCNB)
        dec a
        jr .next
.two:   rlca
        rlca
        ld (PCBITS),a
        and 3
        ld c,a
        ld a,(PCNB)
        dec a
        dec a
.next:  ld (PCNB),a
        jr nz,.ret
        ld a,8
        ld (PCNB),a
        ld hl,(PCBP)
        inc hl
        ld (PCBP),hl
        ld a,(hl)
        ld (PCBITS),a
.ret:   ld a,c
        ret
; El rectangulo (HL, TXT, HL + ancho, TXT + alto) se une al de DE (valido en BC)
GROW:
        ld (GRP),de
        ld (GRN),hl
        ld a,(GLYPH)
        add hl,a
        ld (GRN+4),hl
        ld hl,(TXT)
        ld (GRN+2),hl
        ld a,(GLYPH+1)
        add hl,a
        ld (GRN+6),hl
        ld a,(bc)
        ld (GRV),a
        ld a,1
        ld (bc),a
        ld a,(GRV)
        or a
        jr nz,.u
        ld hl,GRN                   ; el primero
        ld bc,8
        ldir
        ret
.u:     ld hl,GRN
        ld de,(GRP)
        ld b,2
.mn:    push bc
        call GRWORD                 ; minimo
        call CPS16
        call c,GRSET
        pop bc
        call GRNEXT
        djnz .mn
        ld b,2
.mx:    push bc
        call GRWORD                 ; maximo
        ex de,hl
        call CPS16
        ex de,hl
        call c,GRSET
        pop bc
        call GRNEXT
        djnz .mx
        ret
; HL = nuevo (en GRN), DE = actual (en GRP); deja los punteros en GRA / GRB
GRWORD:
        ld (GRA),hl
        ld (GRB),de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl                    ; HL = nuevo, DE = actual
        ret
; el actual = HL (el nuevo)
GRSET:
        ex de,hl
        ld hl,(GRB)
        ld (hl),e
        inc hl
        ld (hl),d
        ret
GRNEXT:
        ld hl,(GRA)
        inc hl
        inc hl
        ld de,(GRB)
        inc de
        inc de
        ret

; Borra el texto que se borra (restoreCharsetBg)
RESTOREBG:
        ld hl,(STAB+ST_X)
        ld (NEXTL),hl
        ld hl,(STAB+ST_Y)
        ld (NEXTT),hl
        ld a,(HASMASK)
        or a
        ret z
        xor a
        ld (HASMASK),a
        ld hl,-1
        ld (STRR),hl
        ld (TXL),hl
        ld a,(MASKV)                ; (clearTextSurface: sin los pixeles del texto)
        or a
        call nz,TMCLRR
        ld a,(MASKSCR)
        or a
        jr nz,.verb
        ld a,(MASKV)
        or a
        ret z
        xor a
        ld (MASKV),a
        ld hl,(MASKR+2)             ; solo las filas del texto
        call CLAMP8
        ld (DSY0),a
        ld hl,(MASKR+6)
        call CLAMP8
        ld (DSY1),a
        ld hl,(MASKR)
        ld de,(MASKR+4)
        call REDRAWX
        jp L2DONE
.verb:  ld a,(VRECTV)
        or a
        ret z
        xor a
        ld (VRECTV),a
        ld a,1
        ld (PXVS),a
        ld a,(MAINH)
        ld e,a
        ld d,0
        ld hl,(VRECT)
        ld (FX0),hl
        ld hl,(VRECT+4)
        ld (FX1),hl
        ld hl,(VRECT+2)
        or a
        sbc hl,de
        ld (FY0),hl
        ld hl,(VRECT+6)
        or a
        sbc hl,de
        ld (FY1),hl
        xor a
        call FILLVS
        jp L2DONE

; --- drawString -------------------------------------------------------------------
; El mensaje de FARP con la ranura de texto A (texto de sistema: no se borra)
DRAWSTRING:
        ld (DSA),a
        ld hl,DSBUF                 ; su propio buffer (no el del texto que se habla)
        ld (MSGP),hl
        xor a
        ld (CVOUT),a
        ld (CVDEPTH),a
        call CONVERT
        ld a,(CVOUT)
        ld hl,(MSGP)
        add hl,a
        ld (hl),0
        ld a,(DSA)
        call STPTR                  ; HL = ranura de texto
        ld (DSST),hl
        call STLOAD                 ; TXT, TXL... desde la ranura
        ld a,1
        ld (TXDISOFF),a
        ld (TXFIRST),a
        call SETFONT
        call CMAP03
        ld a,(CVOUT)                ; quita los espacios del final
        or a
        jr z,.trim
        ld b,a
        ld hl,(MSGP)
        add hl,a
.tr:    dec hl
        ld a,(hl)
        cp 32
        jr nz,.trim
        ld (hl),0
        djnz .tr
.trim:  ld a,(TXCEN)
        or a
        jr z,.nc
        xor a
        call STRWIDTH
        call HALF                   ; left -= ancho / 2
        ex de,hl
        ld hl,(TXL)
        or a
        sbc hl,de
        ld (TXL),hl
.nc:    ld hl,(MSGP)
        ld a,(hl)
        or a
        jr nz,.go
        ld hl,(MSGP)
        ld (hl),32
        inc hl
        ld (hl),0
.go:    xor a
        ld (DSI),a
.lp:    ld a,(DSI)
        call MSGAT
        ld hl,DSI
        inc (hl)
        or a
        jp z,.end
        cp $FF
        jr z,.esc
        cp $FE
        jr z,.esc
        ld b,a
        ld a,1
        ld (PCIGN),a
        ld a,b
        call PRINTCHAR
        jr .lp
.esc:   ld a,(DSI)
        call MSGAT
        ld hl,DSI
        inc (hl)
        cp 9
        jr z,.s2
        cp 10
        jr z,.s2
        cp 13
        jr z,.s2
        cp 14
        jr z,.s2
        cp 1
        jr z,.nl
        cp 8
        jr z,.nl
        cp 12
        jr nz,.lp
        ld a,(DSI)                  ; color
        call MSGAT
        ld c,a
        ld a,(DSI)
        inc a
        call MSGAT
        ld b,a
        ld hl,DSI
        inc (hl)
        inc (hl)
        ld a,b
        or a
        jr nz,.cl
        ld a,c
        cp $FF
        jr nz,.cl
        ld hl,(DSST)
        ld a,ST_COL
        add hl,a
        ld c,(hl)
.cl:    ld a,c
        ld (TXCOL),a
        jr .lp
.s2:    ld hl,DSI
        inc (hl)
        inc (hl)
        jr .lp
.nl:    ld a,(TXCEN)
        or a
        ld hl,(TXSTART)
        jr z,.nl2
        ld a,(DSI)
        call STRWIDTH
        ex de,hl
        ld hl,(TXSTART)
        or a
        sbc hl,de
.nl2:   ld (TXL),hl
        ld a,(FONTH)
        ld hl,(TXT)
        add hl,a
        ld (TXT),hl
        jp .lp
.end:   ld a,(DSA)
        or a
        jr nz,.x
        ld hl,(TXL)
        ld (NEXTL),hl
        ld hl,(TXT)
        ld (NEXTT),hl
.x:     ld hl,(DSST)                ; xpos = str.right
        ld de,(STRR+4)
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,MSGBUF
        ld (MSGP),hl
        jp L2DONE
; HL = HL / 2 hacia abajo (con signo, como el // de Python)
HALF:
        sra h
        rr l
        ret
; HL = la ranura de texto A (la actual; la por defecto esta STSZ despues)
STPTR:
        ld e,a
        ld d,STABSZ
        mul d,e
        ld hl,STAB
        add hl,de
        ret
; TXT, TXSTART, TXL, TXRIGHT, TXCEN, TXCOL y CURID desde la ranura HL
STLOAD:
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (TXSTART),de
        ld (TXL),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (TXT),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (TXRIGHT),de
        ld a,(hl)
        inc hl
        ld (TXCOL),a
        ld a,(hl)
        inc hl
        ld (CURID),a
        ld a,(hl)
        ld (TXCEN),a
        ret
; TCMAP[0..3] = los colores de la fuente CURID
CMAP03:
        ld a,(CURID)
        and 7
        add a,a
        add a,a
        add a,a
        add a,a
        ld hl,CHDATA
        add hl,a
        ld de,TCMAP
        ld bc,4
        ldir
        ret

; --- hablar: CHARSET_1 -----------------------------------------------------------------
CHARSET1:
        ld a,(HAVEMSG)
        or a
        ret z
        ld a,(CURROOM)              ; nada mientras se mueve la camara
        or a
        jr z,.cam
        ld hl,(CAM_DEST)
        call SHR3
        ex de,hl
        ld hl,(CAM_CUR)
        call SHR3
        or a
        sbc hl,de
        ret nz
        ld hl,(CAM_CUR)
        ld de,(CAMLAST)
        or a
        sbc hl,de
        ret nz
.cam:   ld a,(VARS+2*VAR_TALK_ACTOR)
        ld (C1ACT),a
        cp $FF
        jr z,.noact
        or a
        jr z,.noact
        cp NACT
        jr nc,.noact
        ld a,(STAB+ST_OVH)
        or a
        jr z,.noact
        call TALKPOS
.noact: ld hl,STAB                  ; desde la ranura 0
        call STLOAD
        ld hl,(TXSTART)             ; (STLOAD pone TXL = xpos)
        ld (TXL),hl
        ld a,(CSCOL)
        ld (TXCOL),a
        call SETFONT
        call CMAP03
        ld hl,(TALKD)
        ld a,h
        or l
        ret nz
        ld a,(HAVEMSG)
        cp 1
        jp z,STOPTALK
        call C1ACTOK                ; cada trozo del texto: hablando otra vez
        jr nc,.nta
        ld a,(STAB+ST_NTA)
        or a
        jr nz,.nta
        ld a,(C1ACT)
        OKCALL K_TALKSTART
        ld a,1
        ld (USETALK),a
.nta:   ld a,(TKEEP)
        or a
        call z,RESTOREBG
        ld hl,(TXRIGHT)             ; t = right - xpos - 1
        ld de,(STAB+ST_X)
        or a
        sbc hl,de
        dec hl
        ld a,(TXCEN)
        or a
        jr z,.t1
        ld de,(NEXTL)
        call CPS16                  ; t < nextl: se queda
        jr c,.t2
        ex de,hl                    ; si no, t = nextl
.t2:    add hl,hl
.t1:    ex de,hl
        call LINEBREAKS
        ld a,(TXCEN)
        or a
        jr z,.nc
        ld a,(BUFPOS)
        call STRWIDTH
        call HALF
        ex de,hl
        ld hl,(NEXTL)
        or a
        sbc hl,de
        bit 7,h
        jr z,.nl0
        ld hl,0
.nl0:   ld (NEXTL),hl
.nc:    ld a,(TKEEP)
        or a
        ld a,1
        jr z,.k
        xor a
.k:     ld (TXDISOFF),a
        ld (TXFIRST),a
.lp:    ld a,(BUFPOS)
        call MSGAT
        ld hl,BUFPOS
        inc (hl)
        or a
        jr z,.fin
        cp 13
        jr z,.newl
        cp $FE
        jr z,.esc
        cp $FF
        jr z,.esc
        ld (C1C),a
        ld hl,(NEXTL)
        ld (TXL),hl
        ld hl,(NEXTT)
        ld (TXT),hl
        xor a
        ld (PCIGN),a
        ld a,(C1C)
        call PRINTCHAR
        ld hl,(TXL)
        ld (NEXTL),hl
        ld hl,(TXT)
        ld (NEXTT),hl
        ld hl,(TALKD)               ; + VAR_CHARINC
        ld de,(VARS+2*VAR_CHARINC)
        add hl,de
        ld (TALKD),hl
        jr .lp
.fin:   ld a,1
        ld (HAVEMSG),a
        xor a
        ld (TKEEP),a
        jp L2DONE
.newl:  call NEWLINE
        jr .lp
.esc:   ld a,(BUFPOS)
        call MSGAT
        ld hl,BUFPOS
        inc (hl)
        cp 1
        jr z,.newl
        cp 2
        jr z,.keep
        cp 3
        jr z,.wait
        cp 12
        jr z,.col
        cp 9
        jr z,.anim
        cp 10
        jr z,.s2
        cp 13
        jr z,.s2
        cp 14
        jp nz,.lp
.s2:    ld hl,BUFPOS
        inc (hl)
        inc (hl)
        jp .lp
.anim:  call C1ACTOK                ; startAnimActor del que habla
        jr nc,.s2
        ld a,(BUFPOS)
        call MSGAT
        ld l,a
        ld a,(C1ACT)
        OKCALL K_ESCANIM
        jr .s2
.col:   ld a,(BUFPOS)
        call MSGAT
        ld c,a
        ld a,(BUFPOS)
        inc a
        call MSGAT
        ld b,a
        ld hl,BUFPOS
        inc (hl)
        inc (hl)
        ld a,b
        or a
        jr nz,.c2
        ld a,c
        cp $FF
        jr nz,.c2
        ld a,(CSCOL)
        ld c,a
.c2:    ld a,c
        ld (TXCOL),a
        jp .lp
.keep:  xor a
        ld (HAVEMSG),a
        inc a
        ld (TKEEP),a
        jp L2DONE
.wait:  ld a,$FF
        ld (HAVEMSG),a
        xor a
        ld (TKEEP),a
        jp L2DONE
; Linea nueva en CHARSET_1
NEWLINE:
        ld hl,(STAB+ST_X)
        ld (NEXTL),hl
        ld a,(TXCEN)
        or a
        jr z,.n
        ld a,(BUFPOS)
        call STRWIDTH
        call HALF
        ex de,hl
        ld hl,(NEXTL)
        or a
        sbc hl,de
        ld (NEXTL),hl
.n:     ld a,(FONTH)
        ld hl,(NEXTT)
        add hl,a
        ld (NEXTT),hl
        ld a,1
        ld (TXDISOFF),a
        ret

; carry si C1ACT es un actor (1-12)
C1ACTOK:
        ld a,(C1ACT)
        jp ACTOK

; La posicion del texto encima del actor C1ACT (CHARSET_1 con overhead)
TALKPOS:
        ld a,(C1ACT)
        ld l,a
        ld h,0
        call ACTXY                  ; HL = x, DE = y
        push de
        call XSTART
        or a
        sbc hl,de
        ld (STAB+ST_X),hl
        ld a,(C1ACT)                ; su escala y y su elevacion
        ld e,A_SCALEY
        call ACTRD
        ld a,l
        ld (TPSC),a
        ld a,(C1ACT)
        ld e,R_ELEV
        call ACTRD
        ex de,hl
        pop hl
        or a
        sbc hl,de                   ; y - elevacion
        ld (TPY),hl
        ld hl,(VARS+2*VAR_TALK_STRING_Y)
        bit 7,h
        jr nz,.neg
        ld (STAB+ST_Y),hl
        jr .clamp
.neg:   ; s = trunc(escala * ty / 255); y += trunc((ty - s) / 2) + s
        ex de,hl
        ld hl,0
        or a
        sbc hl,de                   ; |ty|
        ld (TPTY),hl
        ld a,(TPSC)                 ; escala * |ty| (32 bits) / 255
        ld e,a
        ld d,0
        call MULU16
        ld bc,255
        call DIVU32_16
        ld (TPS),hl                 ; |s|
        ex de,hl
        ld hl,(TPTY)                ; |ty| - |s| >= 0; (ty - s) / 2 = -((|ty| - |s|) / 2)
        or a
        sbc hl,de
        srl h
        rr l
        ld de,(TPS)
        add hl,de                   ; |(ty - s)/2| + |s|
        ex de,hl
        ld hl,(TPY)
        or a
        sbc hl,de
        ld (STAB+ST_Y),hl
.clamp: ld hl,(STAB+ST_Y)
        ld de,1
        call CPS16
        jr nc,.c1
        ld (STAB+ST_Y),de
.c1:    ld hl,(STAB+ST_X)
        ld de,80
        call CPS16
        jr nc,.c2
        ld (STAB+ST_X),de
        ret
.c2:    ld de,240
        ex de,hl
        call CPS16                  ; 240 < x ?
        ret nc
        ld (STAB+ST_X),hl
        ret
; DE = x de la izquierda de la camara (0 sin habitacion), como xstart() de ui.py
XSTART:
        ld de,0
        ld a,(CURROOM)
        or a
        ret z
        ld de,(LEFT)
        ret

; HL = DE:HL / BC (sin signo; el cociente cabe en 16 bits)
DIVU32_16:
        ld a,16
        ex de,hl                    ; HL = alto, DE = bajo
.lp:    ex de,hl
        add hl,hl
        ex de,hl
        adc hl,hl
        jr c,.sub
        or a
        sbc hl,bc
        jr nc,.one
        add hl,bc
        jr .n
.sub:   or a
        sbc hl,bc
.one:   inc e
.n:     dec a
        jr nz,.lp
        ex de,hl
        ret

; stopTalk
STOPTALK:
        xor a
        ld (HAVEMSG),a
        ld hl,0
        ld (TALKD),hl
        ld a,(VARS+2*VAR_TALK_ACTOR)
        or a
        jr z,.k
        cp $80
        jr nc,.k
        call INROOM
        jr nc,.n
        ld a,(USETALK)              ; deja de hablar (talkStopFrame)
        or a
        jr z,.n
        ld a,(VARS+2*VAR_TALK_ACTOR)
        OKCALL K_TALKSTOP
        xor a
        ld (USETALK),a
.n:     ld hl,$FF
        ld (VARS+2*VAR_TALK_ACTOR),hl
.k:     xor a
        ld (TKEEP),a
        jp RESTOREBG

; actorTalk: el actor A dice el mensaje de BOUNCE
ACTORTALK:
        ld (ATA),a
        xor a                       ; el mensaje a MSGBUF (aunque no se vea)
        ld (CVOUT),a
        ld (CVDEPTH),a
        ld hl,BOUNCE
        ld (FARP),hl
        ld (FARP+2),a
        call CONVERT
        ld a,(CVOUT)
        ld hl,MSGBUF
        add hl,a
        ld (hl),0
        ld a,(ATA)
        cp $FF
        jr nz,.act
        ld a,(TKEEP)
        or a
        call z,STOPTALK
        ld hl,$FF
        ld (VARS+2*VAR_TALK_ACTOR),hl
        jr .color
.act:   call INROOM
        jp nc,L2DONE
        ld a,(TKEEP)
        or a
        call z,STOPTALK
        ld a,(ATA)
        ld l,a
        ld h,0
        ld (VARS+2*VAR_TALK_ACTOR),hl
        ld a,(STAB+ST_NTA)
        or a
        jr nz,.color
        ld a,(ATA)                  ; a hablar (talkStartFrame)
        OKCALL K_TALKSTART
        ld a,1
        ld (USETALK),a
.color: ld a,(VARS+2*VAR_TALK_ACTOR)
        or a
        jr z,.scol
        cp NACT
        jr nc,.scol
        ld e,R_TALKC
        call ACTRD
        ld a,l
        jr .sc
.scol:  ld a,(STAB+ST_COL)
.sc:    ld (CSCOL),a
        xor a
        ld (BUFPOS),a
        ld hl,0
        ld (TALKD),hl
        ld a,$FF
        ld (HAVEMSG),a
        ld hl,$FF
        ld (VARS+2*VAR_HAVE_MSG),hl
        call CHARSET1
        jp L2DONE

; --- verbos ----------------------------------------------------------------------------
; VTMP = la ranura A (y VSLOT = A)
VLOAD:
        ld (VSLOT),a
        call VSADDR
        ld de,VTMP
        ld bc,VSZ
        ldir
        ret
VSTORE:
        ld a,(VSLOT)
        call VSADDR
        ex de,hl
        ld hl,VTMP
        ld bc,VSZ
        ldir
        ret

; drawVerb(A = ranura, DVMODE = 1 resaltado)
DRAWVERB:
        or a
        ret z
        call VLOAD
        ld a,(VTMP+VS_SAVE)
        or a
        jr nz,.rest
        ld a,(VTMP+VS_MODE)
        or a
        jr z,.rest
        ld a,(VTMP+VS_ID)
        or a
        jr z,.rest
        ld a,(VTMP+VS_TYPE)
        or a
        jr z,.text
        call VBITMAP
        call VSTORE
        jp L2DONE
.rest:  call VRESTBG
        call VSTORE
        jp L2DONE
.text:  call VRESTBG
        ld hl,STAB+4*STABSZ         ; la ranura de texto 4
        ld de,(VTMP+VS_L)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(VTMP+VS_T)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),319 & $FF
        inc hl
        ld (hl),319 >> 8
        inc hl
        ld a,(VTMP+VS_MODE)         ; color
        cp 2
        ld a,(VTMP+VS_DIM)
        jr z,.cl
        ld a,(DVMODE)
        or a
        jr z,.nm
        ld a,(VTMP+VS_HI)
        or a
        jr nz,.cl
.nm:    ld a,(VTMP+VS_COL)
.cl:    ld (hl),a
        inc hl
        ld a,(VTMP+VS_CS)
        ld (hl),a
        inc hl
        ld a,(VTMP+VS_CEN)
        or a
        jr z,.c0
        ld a,1
.c0:    ld (hl),a
        ld a,(VTMP+VS_HASN)
        or a
        jr z,.st
        ld a,(VSLOT)
        ld c,1
        call HPTR
        jr nc,.st
        ld (FARP),hl
        ld (FARP+2),a
        ld a,(TXCEN)
        push af
        ld a,4
        call DRAWSTRING
        pop af
        ld (TXCEN),a
        ld a,(VSLOT)                ; (DRAWSTRING ha usado VTMP? no; pero si MMU7)
        ld hl,(STRR+4)
        ld (VTMP+VS_R),hl
        ld hl,(STRR+6)
        ld (VTMP+VS_B),hl
        ld hl,STRR
        ld de,VTMP+VS_OL
        ld bc,8
        ldir
        ld a,1
        ld (VTMP+VS_OV),a
        ld hl,(STRR+4)
        ld (STRR),hl
.st:    call VSTORE
        jp L2DONE

; restoreVerbBG de VTMP
VRESTBG:
        ld a,(VTMP+VS_OV)
        or a
        ret z
        xor a
        ld (VTMP+VS_OV),a
        ld hl,(VTMP+VS_OL)
        ld (FX0),hl
        ld hl,(VTMP+VS_OR)
        ld (FX1),hl
        ld hl,(VTMP+VS_OT)
        bit 7,h
        jr z,.t
        ld hl,0
.t:     ld (FY0),hl
        ld hl,(VTMP+VS_OB)
        ld (FY1),hl
        ld hl,(FX0)                 ; nada si l >= r o t >= b
        ld de,(FX1)
        call CPS16
        ret nc
        ld hl,(FY0)
        ld de,(FY1)
        call CPS16
        ret nc
        ld hl,(FY0)
        call FINDVS
        cp $FF
        ret z
        ld (PXVS),a
        or a
        jr nz,.verb
        ld a,(CURROOM)              ; principal: las tiras (sus filas)
        or a
        jr z,.verb
        ld hl,(FY0)
        call CLAMP8
        ld (DSY0),a
        ld hl,(FY1)
        call CLAMP8
        ld (DSY1),a
        ld hl,(FX0)
        ld de,(LEFT)
        add hl,de
        push hl
        ld hl,(FX1)
        add hl,de
        ex de,hl
        pop hl
        push hl                     ; (y sin texto: restoreBackground)
        push de
        call TMCLR
        pop de
        pop hl
        jp REDRAWX
.verb:  ld a,(PXVS)
        call VSTOP
        ex de,hl
        ld hl,(FY0)
        or a
        sbc hl,de
        ld (FY0),hl
        ld hl,(FY1)
        or a
        sbc hl,de
        ld (FY1),hl
        ld a,(VTMP+VS_BK)
        jp FILLVS

; La imagen del verbo de VTMP (drawVerbBitmap)
VBITMAP:
        ld a,(VTMP+VS_HASI)
        or a
        ret z
        call VIMGFIND               ; FARP = datos; VIW, VIH
        ret nc
        ld hl,(VTMP+VS_T)
        call FINDVS
        cp $FF
        ret z
        ld (PXVS),a
        call VSTOP                  ; ydiff = top - arriba
        ld (VBVH),de                ; (y el alto de esa pantalla)
        ex de,hl
        ld hl,(VTMP+VS_T)
        or a
        sbc hl,de
        ld (VBY),hl
        ld hl,(VTMP+VS_L)           ; x = (left // 8) * 8
        call SHR3
        add hl,hl
        add hl,hl
        add hl,hl
        ld (VBX),hl
        ld a,(VIH)                  ; bytes de mascara = (alto + 7) / 8
        add a,7
        srl a
        srl a
        srl a
        ld (VBMB),a
        ld a,(VIH)
        and $F8
        ld (VBH8),a
        ld hl,VBRM                  ; las filas que se pintan (fila < VBH8) y se ven
        ld (VBMP),hl                ; (0 <= VBY + fila < alto): sus bits, como la
        ld hl,(VBY)                 ; mascara (VBRM)
        ld e,a
        ld d,0
        ld a,(VBMB)
        or a                        ; (alto 0: ninguna)
        jr z,.rmx
.rm:    push af
        ld bc,$0800
.rb:    sla c
        ld a,d
        cp e
        jr nc,.r0
        ld a,h
        or a
        jr nz,.r0
        ld a,(VBVH)
        cp l
        jr c,.r0
        jr z,.r0
        inc c
.r0:    inc hl
        inc d
        djnz .rb
        push hl
        ld hl,(VBMP)
        ld (hl),c
        inc hl
        ld (VBMP),hl
        pop hl
        pop af
        dec a
        jr nz,.rm
.rmx:   ld a,(PXVS)                 ; su pantalla (como PUTPX) y el byte de la fila VBY
        call VSPARM
        ld a,(VBY)
        ld hl,PCROF
        add a,(hl)
        ld (VBL),a
        ld a,(VIH)                  ; (la mascara de la columna, detras de sus pixeles)
        ld hl,VBCOL
        add hl,a
        ld (VBMK),hl
        xor a
        ld (VBC),a
.col:   ld a,(VBC)
        ld hl,VIW
        cp (hl)
        jp nc,.end
        ld hl,VBEND                 ; otro trozo de columnas de la tarjeta?
        cp (hl)
        jr nz,.rdc
        call VICHUNK
        jp nc,.end
.rdc:   ld de,VBCOL                 ; la columna: pixeles y mascara
        ld a,(VICS)
        ld c,a
        ld b,0
        call FARCPY
        ld a,(VBC)                  ; la columna x: fuera de 0..319, nada
        ld hl,(VBX)
        add hl,a
        ld a,h
        or a
        jr z,.x1
        cp 1
        jp nz,.ncol
        ld a,l
        cp 64
        jp nc,.ncol
.x1:    ld (VBXC),hl                ; por columnas: solo las filas de VBRM; el primer
        ld hl,(VBMK)                ; pixel en su sitio (como PUTPX) y los demas detras
        ld de,VBRM
        ld a,(VBMB)
        or a
        jp z,.ncol
        ld b,a
.am:    ld a,(de)
        and (hl)
        ld (hl),a
        inc hl
        inc de
        djnz .am
        ld hl,(VBMK)                ; el primer pixel: su fila C (la mascara, un byte
        ld a,(VBMB)                 ; cada 8 filas, el bit 7 primero)
        ld b,a
        ld c,0
.fz:    ld a,(hl)
        or a
        jr nz,.fb
        inc hl
        ld a,c
        add a,8
        ld c,a
        djnz .fz
        jp .ncol
.fb:    add a,a
        jr c,.f1
        inc c
        jr .fb
.f1:    ld (VBMC),a                 ; (lo que queda de su byte, y los de detras)
        ld (VBMP),hl
        dec b
        ld a,b
        ld (VBMN),a
        ld a,c
        ld (VBR0),a
        ld hl,(VBXC)                ; su columna de Layer 2 (principal: (LEFT + x) mod
        ld a,(PXVS)                 ; 320): la pagina y H
        or a
        jr nz,.cv
        ld de,(LEFT)
        add hl,de
        ld de,320
.md:    or a
        sbc hl,de
        jr nc,.md
        add hl,de
.cv:    ld a,l
        and 31
        add a,$40
        ld d,a
        ld a,l
        srl h
        rra
        srl a
        srl a
        srl a
        srl a
        add a,L2_PAGE
        ld hl,PCBO
        add a,(hl)
        ld hl,L2CUR
        cp (hl)
        jr z,.pm
        ld (hl),a
        nextreg $52,a
.pm:    ld a,(VBL)                  ; y su fila: VBL + VBR0
        ld hl,VBR0
        add a,(hl)
        ld e,a
        ld (VBL0),a
        ld a,(hl)
        ex de,hl
        ld de,VBCOL
        add de,a
        ld a,(de)
        ld (hl),a
        push ix
        ld a,l
        ld ixh,a                    ; (IXH: el byte de la ultima fila con pixel)
        ld a,(VBMN)
        ld ixl,a                    ; (IXL: los bytes de mascara que quedan)
        ld a,(VBR0)
        and 7
        xor 7
        ld b,a
        ld a,(VBMC)
        ld c,a
        inc b
        jr .bs
.bit:   inc l
        inc de
        sla c
        jr nc,.bs
        ld a,(de)
        ld (hl),a
        ld a,l
        ld ixh,a
.bs:    djnz .bit
.nb:    ld a,ixl                    ; el byte siguiente
        or a
        jr z,.last
        dec ixl
        push hl
        ld hl,(VBMP)
        inc hl
        ld (VBMP),hl
        ld c,(hl)
        pop hl
        ld b,8
        ld a,c
        or a
        jr nz,.bit
        ld a,l                      ; (8 filas sin pixel)
        add a,b
        ld l,a
        ld a,b
        add de,a
        jr .nb
.last:  ld a,ixh                    ; C = filas del primero al ultimo
        pop ix
        ld hl,VBL0
        sub (hl)
        ld c,a
        ld a,(PCVM)                 ; VMIN/VMAX como PUTPX (verbos sin VDIRECT)
        or a
        jr z,.ncol
        ld a,(VBY)                  ; y del primero
        ld hl,VBR0
        add a,(hl)
        ld e,a
        ld a,(VMIN)
        cp e
        jr c,.v1
        ld a,e
        ld (VMIN),a
.v1:    ld a,e                      ; y del ultimo
        add a,c
        ld e,a
        ld a,(VMAX)
        cp e
        jr nc,.ncol
        ld a,e
        ld (VMAX),a
.ncol:  ld hl,VBC
        inc (hl)
        jp .col
.end:   ld a,(VIW)                  ; right = left + (w // 8) * 8, bottom = top + (h // 8) * 8
        and $F8
        ld hl,(VTMP+VS_L)
        add hl,a
        ld (VTMP+VS_R),hl
        ld a,(VBH8)
        ld hl,(VTMP+VS_T)
        add hl,a
        ld (VTMP+VS_B),hl
        ld hl,VTMP+VS_L             ; old = (left, top, right, bottom)
        ld de,VTMP+VS_OL
        ld bc,8
        ldir
        ld a,1
        ld (VTMP+VS_OV),a
        ret
VBVH:   dw 0                        ; (VBITMAP) el alto de la pantalla
VBXC:   dw 0                        ; la x de la columna
VBMP:   dw 0                        ; el byte de la mascara
VBMC:   db 0                        ; y lo que queda de el
VBMN:   db 0                        ; y los que quedan detras
VBR0:   db 0                        ; la fila del primer pixel
VBL0:   db 0                        ; y donde fue (L)
VBL:    db 0                        ; el byte de la fila VBY en la columna
VBMK:   dw 0                        ; la mascara de la columna (en VBCOL)
VBRM:   ds 10                       ; las filas que se pintan y se ven (como la mascara)
VBCOL:  ds GLYPHMAX+10              ; la columna: pixeles y mascara
; Busca en el indice de VERBIMG.DAT la imagen (VS_IROOM, VS_IOBJ) de VTMP y la lee
; a IMGBUF si no estaba: carry, FARP, VIW, VIH. Si no cabe en IMGBUF se lee por
; trozos de columnas al pintarla (VICHUNK cuando VBC llega a VBEND)
VIMGFIND:
        ld a,UIP
        call MAP7
        ld hl,(VIDX)
        ld b,h
        ld c,l
        ld hl,VIDX+2
.lp:    ld a,b
        or c
        ret z
        push hl
        ld a,(VTMP+VS_IROOM)
        cp (hl)
        jr nz,.no
        inc hl
        ld a,(VTMP+VS_IOBJ)
        cp (hl)
        jr nz,.no
        inc hl
        ld a,(VTMP+VS_IOBJ+1)
        cp (hl)
        jr nz,.no
        inc hl
        ld a,(hl)
        ld (VIW),a
        inc hl
        ld a,(hl)
        ld (VIH),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        ld (FROFF),de
        ld (FROFF+2),a
        xor a
        ld (FROFF+3),a
        pop hl
        jr .got
.no:    pop hl
        ld de,8
        add hl,de
        dec bc
        jr .lp
.got:   ld a,(VIH)                  ; columna = alto + mascara
        cp GLYPHMAX
        ret nc
        ld e,a
        add a,7
        rrca
        rrca
        rrca
        and $1F
        add a,e
        ld (VICS),a
        ld e,a                      ; columnas por trozo = 2048 / columna (como mucho 255)
        ld d,0
        ld hl,2048
        ld b,0
.k:     or a
        sbc hl,de
        jr c,.kk
        inc b
        jr nz,.k
        dec b
.kk:    ld a,b
        ld (VIK),a
        ld a,(VIW)
        cp b
        jr c,.whole
        jr z,.whole
        ld hl,(FROFF)               ; por trozos: desde el principio, sin cache
        ld (VINEXT),hl
        ld a,(FROFF+2)
        ld (VINEXT+2),a
        xor a
        ld (VBEND),a
        ld (VICROOM),a
        scf
        ret
.whole: ld (VBEND),a                ; entera (VBEND = ancho: no se vuelve a leer)
        ld d,a
        ld a,(VICS)
        ld e,a
        mul d,e
        ex de,hl
        ld (FRLEN),hl
        ld a,(VTMP+VS_IROOM)        ; ya estaba?
        ld hl,VICROOM
        cp (hl)
        jr nz,.rd
        ld hl,(VTMP+VS_IOBJ)
        ld de,(VICOBJ)
        or a
        sbc hl,de
        jr z,.ok
.rd:    ld a,INVP
        ld (FRPAGE),a
        ld hl,IMGBUF
        ld (FRADDR),hl
        ld hl,VIMGNAME              ; (en la cache, seguida: alli mismo; IMGBUF ya no
        call CFFAR                  ; la tiene)
        jr nc,.cpy
        ld (FARP),hl
        ld (FARP+2),a
        xor a
        ld (VICROOM),a
        scf
        ret
.cpy:   call CFREAD
        jr c,.fail
        ld a,(VTMP+VS_IROOM)
        ld (VICROOM),a
        ld hl,(VTMP+VS_IOBJ)
        ld (VICOBJ),hl
.ok:    ld hl,IMGBUF-$E000
        ld a,INVP
        call LINOF
        ld (FARP),hl
        ld (FARP+2),a
        scf
        ret
.fail:  xor a
        ld (VICROOM),a
        ret

; El trozo siguiente de la imagen grande: min(VIK, VIW - VBC) columnas desde VINEXT
; a IMGBUF; FARP, VBEND; carry si se ha leido
VICHUNK:
        ld a,(VBC)
        ld b,a
        ld a,(VIW)
        sub b
        ld hl,VIK
        cp (hl)
        jr c,.n
        ld a,(hl)
.n:     ld d,a
        add a,b
        ld (VBEND),a
        ld a,(VICS)
        ld e,a
        mul d,e
        ld (FRLEN),de
        ld hl,(VINEXT)
        ld (FROFF),hl
        ld a,(VINEXT+2)
        ld (FROFF+2),a
        add hl,de                   ; el siguiente trozo, detras
        adc a,0
        ld (VINEXT),hl
        ld (VINEXT+2),a
        xor a
        ld (FROFF+3),a
        ld a,INVP
        ld (FRPAGE),a
        ld hl,IMGBUF
        ld (FRADDR),hl
        ld hl,VIMGNAME
        call CFREAD
        ccf
        ret nc
        ld hl,IMGBUF-$E000
        ld a,INVP
        call LINOF
        ld (FARP),hl
        ld (FARP+2),a
        scf
        ret
VBEND:  db 0                        ; la columna en la que hay que leer otro trozo
VICS:   db 0                        ; bytes por columna (pixeles y mascara)
VIK:    db 0                        ; columnas por trozo
VINEXT: ds 3                        ; posicion del trozo siguiente en VERBIMG.DAT

; --- INVOBJ.DAT y VERBIMG.DAT, por bloques de 512 bytes en memoria ------------------
; En el Next cada lectura de la SD abre, busca y cierra el fichero (milisegundos), y el
; inventario pide decenas en un paso: las imagenes, y la tabla y el codigo de sus
; objetos. Los bloques leidos se quedan en las paginas FC_SLOT0.. (las de LOADBUF:
; cargar una partida las pisa, y con ellas la firma FC_MAG: se empieza de nuevo); las
; tablas, en la primera, por $6000.
FC_PAGE  EQU LOADBUF
FC_SLOT0 EQU LOADBUF+1              ; 6 paginas de 16 bloques
FC_N     EQU 6*16
FC_MAG   EQU $6000                  ; la firma: "FBC", 1
FC_MAPV  EQU $6004                  ; bloque -> su hueco + 1 (0: no esta): VERBIMG.DAT
FC_MAPI  EQU FC_MAPV+200            ;  (200 bloques) e INVOBJ.DAT (120)
FC_OWN   EQU FC_MAPI+120            ; hueco -> la entrada del mapa de su bloque (0: ninguno)
FC_NEXT  EQU FC_OWN+2*FC_N          ; el hueco siguiente

; Como FILEREAD (HL = nombre; FROFF, FRLEN, FRPAGE, FRADDR; carry si falla). Los demas
; ficheros, o mas de 8 bloques, con FILEREAD.
CFREAD:
        call CFSET
        jp nc,FILEREAD
        call CFGET
        jr c,CFERR
        ld a,(CFPG)                 ; a donde va (como FILEREAD)
        or a
        jr nz,.m7
        ld a,(CFM7)
.m7:    call MAP7
        ld hl,(CFOFF)               ; desde la posicion del primer bloque
        ld a,h
        and 1
        ld h,a
        ld (CFO),hl
        ld de,(CFAD)
        ld hl,CFSL
        ld (CFP),hl
.cl:    ld hl,(CFP)                 ; el bloque, por $6000
        ld a,(hl)
        inc hl
        ld (CFP),hl
        ld c,a
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a,FC_SLOT0
        ld (AUM3),a
        nextreg $53,a
        ld a,c
        and 15
        add a,a
        add a,$60
        ld h,a
        ld l,0
        ld bc,(CFO)
        add hl,bc
        push hl
        ld hl,512                   ; min(512 - posicion, lo que queda)
        or a
        sbc hl,bc
        ld bc,(CFLEN)
        push hl
        or a
        sbc hl,bc
        pop hl
        jr c,.n1
        ld h,b
        ld l,c
.n1:    ld b,h
        ld c,l
        ld hl,(CFLEN)
        or a
        sbc hl,bc
        ld (CFLEN),hl
        pop hl
        ldir
        ld hl,0
        ld (CFO),hl
        ld hl,(CFLEN)
        ld a,h
        or l
        jr nz,.cl
        call ZUNMAP
        or a
        ret
CFERR:  call FCMAP                  ; (no se sabe que hay en esos huecos: todo de nuevo)
        xor a
        ld (FC_MAG),a
        call ZUNMAP
        ld a,(CFM7)
        call MAP7
        scf
        ret

; Como CFREAD pero sin copiar: carry y A:HL = lineal de los datos, si estan seguidos en
; una pagina de la cache (FRPAGE y FRADDR no cuentan); si no, o si no se puede, NC y
; HL = el nombre
CFFAR:
        call CFSET
        ret nc
        call CFGET
        jr c,.er
        ld hl,CFSL                  ; seguidos?
        ld a,(CFK)
        ld b,a
        ld a,(hl)
        ld c,a
        and 15
        add a,b
        cp 17
        jr nc,.no
.s:     ld a,(hl)
        cp c
        jr nz,.no
        inc hl
        inc c
        djnz .s
        call ZUNMAP
        ld a,(CFSL)                 ; su pagina y la posicion en ella
        ld c,a
        and 15
        add a,a
        ld h,a
        ld l,0
        ld de,(CFOFF)
        ld a,d
        and 1
        ld d,a
        add hl,de
        ld a,c
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a,FC_SLOT0
        call LINOF
        scf
        ret
.no:    call ZUNMAP
        ld hl,(CFNM)
        or a
        ret
.er:    call CFERR
        ld hl,(CFNM)
        or a
        ret

; (CFREAD) Si es INVOBJ.DAT o VERBIMG.DAT (HL) y caben sus bloques: carry, y lo que se
; pide guardado (CFNM, CFMAP, CFB0, CFK, CFOFF, CFLEN, CFPG, CFAD, CFM7); si no, NC y
; HL como estaba
CFSET:
        ld (CFNM),hl
        ld de,FC_MAPV
        ld bc,VIMGNAME
        ld a,200
        or a
        sbc hl,bc
        add hl,bc
        jr z,.f
        ld de,FC_MAPI
        ld bc,INVOBJNAME
        ld a,120
        or a
        sbc hl,bc
        add hl,bc
        jr nz,.no
.f:     ld (CFMAP),de
        ld (CFMAX),a
        ld hl,(FRLEN)
        ld a,h
        or l
        jr z,.no
        ld a,(FROFF+3)
        or a
        jr nz,.no
        ld a,(FROFF+2)
        cp 2
        jr nc,.no
        ld hl,(FROFF+1)             ; el primer bloque: posicion >> 9
        srl h
        rr l
        ld a,l
        ld (CFB0),a
        ld hl,(FROFF)               ; el ultimo: (posicion + largo - 1) >> 9
        ld de,(FRLEN)
        dec de
        add hl,de
        ld a,(FROFF+2)
        adc a,0
        cp 2
        jr nc,.no
        srl a
        ld a,h
        rra
        ld hl,CFMAX
        cp (hl)
        jr nc,.no
        ld hl,CFB0
        sub (hl)
        cp 8
        jr nc,.no
        inc a
        ld (CFK),a
        ld hl,(FROFF)               ; lo que se pide
        ld (CFOFF),hl
        ld hl,(FRLEN)
        ld (CFLEN),hl
        ld a,(FRPAGE)
        ld (CFPG),a
        ld hl,(FRADDR)
        ld (CFAD),hl
        ld a,(SHMMU7)
        ld (CFM7),a
        scf
        ret
.no:    ld hl,(CFNM)
        or a
        ret

; (CFREAD) Los bloques en memoria (los que faltan, todos de la SD a CFK huecos
; seguidos): sus huecos en CFSL, y la pagina de las tablas por $6000; carry si falla
CFGET:
        call FCLOOK
        ccf
        ret nc
        call FCALLOC
        ld a,(CFB0)                 ; desde el bloque CFB0 (* 512)
        ld l,0
        add a,a
        ld h,a
        ld a,0
        adc a,a
        ld (FROFF),hl
        ld (FROFF+2),a
        xor a
        ld (FROFF+3),a
        ld l,a
        ld a,(CFK)
        add a,a
        ld h,a
        ld (FRLEN),hl
        ld a,(CFS)
        ld c,a
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a,FC_SLOT0
        ld (FRPAGE),a
        ld a,c
        and 15
        add a,a
        add a,$E0
        ld h,a
        ld l,0
        ld (FRADDR),hl
        ld hl,(CFNM)
        call FILEREAD
        ret c
        call FCLOOK
        ccf
        ret

; La pagina de las tablas por $6000 (AUM3 primero: es la que deja alli el CTC); sin
; la firma, todo vacio
FCMAP:
        ld a,FC_PAGE
        ld (AUM3),a
        nextreg $53,a
        ld hl,FC_MAG
        ld de,FCSIG
        ld b,4
.c:     ld a,(de)
        cp (hl)
        jr nz,.new
        inc hl
        inc de
        djnz .c
        ret
.new:   ld hl,FC_MAG
        ld de,FC_MAG+1
        ld bc,FC_NEXT-FC_MAG
        ld (hl),0
        ldir
        ld hl,FCSIG
        ld de,FC_MAG
        ld bc,4
        ldir
        ret
FCSIG:  db "FBC",1

; Los huecos de los bloques CFB0.. (CFK) en CFSL; carry si estan todos
FCLOOK:
        call FCMAP
        ld hl,(CFMAP)
        ld a,(CFB0)
        add hl,a
        ld de,CFSL
        ld a,(CFK)
        ld b,a
.lp:    ld a,(hl)
        or a
        ret z
        dec a
        ld (de),a
        inc hl
        inc de
        djnz .lp
        scf
        ret

; CFK huecos seguidos en una pagina desde FC_NEXT (los bloques que tenian se olvidan)
; para los bloques CFB0..: CFS = el primero
FCALLOC:
        call FCMAP
        ld a,(FC_NEXT)
        ld b,a
        and 15
        ld hl,CFK
        add a,(hl)
        cp 17
        ld a,b
        jr c,.in
        and $F0
        add a,16
.in:    cp FC_N
        jr c,.ok
        xor a
.ok:    ld (CFS),a
        ld c,a                      ; C = hueco, E = bloque
        ld b,(hl)
        ld a,(CFB0)
        ld e,a
.lp:    push bc
        push de
        ld l,c
        ld h,0
        add hl,hl
        ld de,FC_OWN
        add hl,de
        ld e,(hl)                   ; el bloque que tenia, fuera del mapa
        inc hl
        ld d,(hl)
        ld a,d
        or e
        jr z,.fr
        ld a,(de)
        dec a
        cp c
        jr nz,.fr
        xor a
        ld (de),a
.fr:    pop de                      ; y el nuevo
        push de
        push hl
        ld hl,(CFMAP)
        ld a,e
        add hl,a
        ld a,c
        inc a
        ld (hl),a
        ex de,hl
        pop hl
        ld (hl),d
        dec hl
        ld (hl),e
        pop de
        pop bc
        inc c
        inc e
        djnz .lp
        ld a,c
        cp FC_N
        jr c,.n
        xor a
.n:     ld (FC_NEXT),a
        ret
CFNM:   dw 0                        ; (CFREAD) el fichero,
CFMAP:  dw 0                        ; su mapa
CFMAX:  db 0                        ; y cuantos bloques caben en el
CFB0:   db 0                        ; el primer bloque
CFK:    db 0                        ; cuantos
CFS:    db 0                        ; (FCALLOC) el primer hueco
CFOFF:  dw 0                        ; lo que se pide: posicion (los 16 bits de abajo),
CFLEN:  dw 0                        ; largo, pagina y direccion
CFPG:   db 0
CFAD:   dw 0
CFM7:   db 0                        ; MMU7 al entrar
CFO:    dw 0                        ; la posicion en el bloque
CFP:    dw 0
CFSL:   ds 8                        ; el hueco de cada bloque

; A = ranura del verbo en (UMX, UMY) o 0 (findVerbAtPos)
FINDVERB:
        ld a,NUM_VERBS-1
.lp:    ld (FVI),a
        call VSADDR
        push hl
        pop de
        ld a,(de)                   ; verbid
        or a
        jp z,.nx
        ld hl,VS_MODE
        add hl,de
        ld a,(hl)
        cp 1
        jp nz,.nx
        ld hl,VS_SAVE
        add hl,de
        ld a,(hl)
        or a
        jp nz,.nx
        ld hl,VS_T                  ; top <= y < bottom
        add hl,de
        call LDHLHL
        push de
        ld de,(UMY)
        ex de,hl
        call CPS16                  ; y < top ?
        pop de
        jr c,.nx
        ld hl,VS_B
        add hl,de
        call LDHLHL
        push de
        ld de,(UMY)
        call CPS16                  ; bottom < y o =: y >= bottom
        pop de
        jr c,.nx
        jr z,.nx
        ld hl,VS_CEN
        add hl,de
        ld a,(hl)
        or a
        jr nz,.cen
        ld hl,VS_L
        add hl,de
        call LDHLHL
        push de
        ld de,(UMX)
        ex de,hl
        call CPS16                  ; x < left ?
        pop de
        jr c,.nx
        jr .right
.cen:   ld hl,VS_L                  ; x < -(right - 2 * left) ?
        add hl,de
        call LDHLHL
        add hl,hl
        ld (FVT),hl
        ld hl,VS_R
        add hl,de
        call LDHLHL
        push de
        ld de,(FVT)
        or a
        sbc hl,de
        ex de,hl
        ld hl,0
        or a
        sbc hl,de
        ex de,hl
        ld hl,(UMX)
        call CPS16
        pop de
        jr c,.nx
.right: ld hl,VS_R
        add hl,de
        call LDHLHL
        push de
        ld de,(UMX)
        call CPS16                  ; right < x o =: x >= right
        pop de
        jr c,.nx
        jr z,.nx
        ld a,(FVI)
        ret
.nx:    ld a,(FVI)
        dec a
        jp nz,.lp
        xor a
        ret
; HL = palabra en (HL)
LDHLHL:
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; verbMouseOver(el verbo bajo el raton)
VMOUSEAT:
        call FINDVERB
; verbMouseOver(A = ranura)
VERBMOUSE:
        ld hl,VMOVER
        cp (hl)
        ret z
        ld (VMNEW),a
        ld a,(VMOVER)               ; el de antes, si no es de imagen, normal
        call VSADDR
        ld de,VS_TYPE
        add hl,de
        ld a,(hl)
        or a
        jr nz,.n1
        xor a
        ld (DVMODE),a
        ld a,(VMOVER)
        call DRAWVERB
        ld a,(VMNEW)
        ld (VMOVER),a
.n1:    ld a,(VMNEW)                ; el nuevo, resaltado si es de texto y tiene color
        call VSADDR
        push hl
        ld de,VS_TYPE
        add hl,de
        ld a,(hl)
        pop hl
        or a
        ret nz
        ld de,VS_HI
        add hl,de
        ld a,(hl)
        or a
        ret z
        ld a,1
        ld (DVMODE),a
        ld a,(VMNEW)
        call DRAWVERB
        xor a
        ld (DVMODE),a
        ld a,(VMNEW)
        ld (VMOVER),a
        ret

; --- la capa del texto (el _textSurface de ScummVM) ---------------------------------
; Un bit por pixel de la principal en TMASK_PAGE: el byte (columna de Layer 2 >> 3) *
; 200 + fila, el bit columna & 7. Lo marca printChar (con mascara), lo quitan
; restoreCharsetBg / restoreBackground / la entrada en una habitacion, y FLUSHOBJ
; deja esos pixeles como estaban (TDRAWS): el texto queda encima de las tiras.

; El bit del pixel x = HL (de pantalla), y = DE (de la principal)
TMSET:
        call TMADDR
        ret nc
        ld c,a
        ld a,TMASK_PAGE
        nextreg $57,a
        ld a,(hl)
        or c
        ld (hl),a
        ld a,(SHMMU7)
        nextreg $57,a
        ret

; Carry, HL = su byte (en $E000) y A = su bit si x = HL, y = DE esta en la principal
TMADDR:
        ld a,h                      ; 0 <= x < 320
        or a
        jr z,.x1
        cp 1
        jr nz,.no
        ld a,l
        cp 64
        jr nc,.no
.x1:    ld a,d                      ; 0 <= y < MAINH
        or a
        jr nz,.no
        ld a,(MAINH)
        cp e
        jr c,.no
        jr z,.no
        push de
        ld de,(LEFT)                ; columna = (LEFT + x) mod 320
        add hl,de
        ld de,320
.md:    or a
        sbc hl,de
        jr nc,.md
        add hl,de
        ld a,l
        and 7
        ld b,a
        srl h
        rr l
        srl l
        srl l
        ld d,l
        ld e,200
        mul d,e
        pop hl                      ; + y
        add hl,de
        ld de,$E000
        add hl,de
        ld a,1                      ; A = 1 << (columna & 7)
        inc b
.sh:    dec b
        jr z,.ok
        add a,a
        jr .sh
.ok:    scf
        ret
.no:    or a
        ret

; Sin texto en MASKR (sus tiras y sus filas)
TMCLRR:
        ld hl,(MASKR+2)
        call CLAMP8
        ld (DSY0),a
        ld hl,(MASKR+6)
        call CLAMP8
        ld (DSY1),a
        ld hl,(MASKR)
        ld de,(MASKR+4)
; Sin texto en las tiras de x de habitacion [HL, DE) y las filas [DSY0, DSY1)
TMCLR:
        push de
        call CPS16                  ; nada si x1 <= x0
        pop de
        ret nc
        bit 7,h
        jr z,.p
        ld hl,0
.p:     call SHR3
        ld a,l
        ld (TMS),a
        ex de,hl
        dec hl
        call SHR3
        bit 7,h
        ret nz
        ld a,l
        ld (TME),a
        ld a,(DSY1)                 ; filas [DSY0, min(DSY1, 200))
        cp 201
        jr c,.y
        ld a,200
.y:     ld hl,DSY0
        sub (hl)
        ret c
        ret z
        ld (TMN),a
        ld a,TMASK_PAGE
        nextreg $57,a
.lp:    ld a,(TMS)
        call MOD40
        ld d,a
        ld e,200
        mul d,e
        ld hl,$E000
        add hl,de
        ld a,(DSY0)
        add hl,a
        ld a,(TMN)
        ld b,a
.z:     ld (hl),0
        inc hl
        djnz .z
        ld a,(TMS)
        ld hl,TME
        cp (hl)
        jr z,.end
        inc a
        ld (TMS),a
        jr .lp
.end:   ld a,(SHMMU7)
        nextreg $57,a
        ret

; Toda la capa del texto, vacia
TMCLRALL:
        ld a,TMASK_PAGE
        nextreg $57,a
        ld hl,$E000
        ld de,$E001
        ld bc,40*200-1
        ld (hl),0
        ldir
        ld a,(SHMMU7)
        nextreg $57,a
        ret

; (FLUSHOBJ, con texto en la principal) La tira C: sus pixeles de texto, guardados en
; TBUF; la tira (DRAWSTRIP); y esos pixeles otra vez. Solo las filas de MASKR.
TDRAWS:
        ld a,c
        ld (TDS),a
        ld hl,(MASKR+2)             ; las filas del texto que se van a pintar otra vez:
        call CLAMP8                 ; [max(arriba, DSY0), min(abajo, DSY1))
        ld hl,DSY0
        cp (hl)
        jr nc,.y0
        ld a,(hl)
.y0:    ld (TDY0),a
        ld hl,(MASKR+6)
        call CLAMP8
        cp 201
        jr c,.y1
        ld a,200
.y1:    ld hl,DSY1
        cp (hl)
        jr c,.y2
        ld a,(hl)
.y2:    ld hl,TDY0
        sub (hl)
        jr c,.plain
        jr z,.plain
        ld (TDN),a
        xor a                       ; guardar
        call TDPASS
        ld a,(TDS)
        call DRAWSTRIPR
        ld a,1                      ; y poner
        jp TDPASS
.plain: ld a,(TDS)
        jp DRAWSTRIPR

; Los pixeles de texto de la tira TDS en las filas [TDY0, TDY0 + TDN): A = 0, de
; Layer 2 a TBUF; A = 1, de TBUF a Layer 2
TDPASS:
        ld (TDMODE),a
        ld a,(TDS)
        call MOD40
        ld (TDR),a
        srl a                       ; su pagina de Layer 2: (tira * 8) >> 5
        srl a
        add a,L2_PAGE
        nextreg $52,a
        ld a,TMASK_PAGE
        nextreg $57,a
        ld a,(TDR)
        ld d,a
        ld e,200
        mul d,e
        ld hl,$E000
        add hl,de
        ld a,(TDY0)
        add hl,a
        ld (TDMP),hl
        ld a,(TDR)                  ; su primera columna en $4000
        and 3
        add a,a
        add a,a
        add a,a
        add a,$40
        ld (TDCH),a
        ld a,TBUF_PAGE              ; TBUF por $6000 en vez de los sprites (AUM3 primero:
        ld (AUM3),a                 ; es la que deja alli el CTC)
        nextreg $53,a
        ld hl,TBUF
        ld (TDBP),hl
        ld a,(TDY0)
        add a,ROOM_Y0
        ld (TDROW),a
        ld a,(TDN)
        ld b,a
.row:   push bc
        ld hl,(TDMP)
        ld c,(hl)
        inc hl
        ld (TDMP),hl
        ld a,c
        or a
        jr z,.nr
        ld a,(TDCH)
        ld d,a
        ld a,(TDROW)
        ld e,a
        ld hl,(TDBP)
        ld b,8
.bit:   srl c
        jr nc,.nb
        ld a,(TDMODE)
        or a
        jr nz,.put
        ld a,(de)
        ld (hl),a
        jr .inc
.put:   ld a,(hl)
        ld (de),a
.inc:   inc hl
.nb:    inc d
        djnz .bit
        ld (TDBP),hl
.nr:    ld hl,TDROW
        inc (hl)
        pop bc
        djnz .row
        ld a,(SHMMU7)
        nextreg $57,a
        call ZUNMAP
        jp L2DONE

PCTM:   db 0                        ; 0: el caracter va a la capa del texto
TMS:    db 0
TME:    db 0
TMN:    db 0
TDS:    db 0
TDR:    db 0
TDY0:   db 0
TDN:    db 0
TDMODE: db 0
TDCH:   db 0
TDROW:  db 0
TDMP:   dw 0
TDBP:   dw 0

OVT_END:
        ASSERT OVT_END <= $E000, la capa OVT no cabe
