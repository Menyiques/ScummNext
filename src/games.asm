; ===========================================================================
;  El menu de juegos (en la capa OVS): cada juego convertido, en una carpeta junto
;  al .nex (con su GAME.DAT; el nombre que se ve, en su TITULO.TXT), o suelto junto
;  al .nex. Al arrancar, si hay mas de uno, se elige (G_SELECT); desde el menu de
;  partidas, otro (G_PICK, y el paso siguiente lo carga: GSWITCH). Todos los
;  ficheros de un juego se abren con su nombre, sin carpeta: basta con entrar en
;  la suya (y asi sus partidas guardadas tambien van alli).
;  La letra es propia (gen/font.asm): antes de elegir no hay fuentes del juego.
; ===========================================================================

GMAX    EQU 9                       ; (de 1 a 9: una cifra cada uno)
GE_DIR  EQU 0                       ; su carpeta (vacia: la del .nex)
GE_TIT  EQU 13                      ; lo que se ve
GTMAX   EQU 31
GESZ    EQU GE_TIT+GTMAX+1
GROW0   EQU ROOM_Y0+36              ; la fila del primero
GROWH   EQU 12

; Al arrancar (sin interrupciones): la lista y, si hay varios, el menu; despues, a
; la carpeta del elegido. Carry si no hay ninguno.
G_SELECT:
        xor a
        ld (GESC),a
        ld a,$A8                    ; la carpeta del .nex (F_GETCWD)
        ld hl,GROOT
        call GESXH
        jr nc,.c
        xor a                       ; (si no se puede saber, la raiz)
        ld (GROOT+1),a
        ld a,'/'
        ld (GROOT),a
.c:     call GSCAN
        ld a,(GN)
        or a
        scf
        ret z
        xor a
        ld (GSEL),a
        ld a,(GN)
        dec a
        call nz,GMENU
        ld a,(GSEL)
        jp GENTER

; Desde el menu de partidas: otro juego (GSEL). NC: elegido (el paso siguiente lo
; carga: GSWITCH, G_GO); carry: ESC. Se sigue en la carpeta del de ahora (lo que
; queda de este paso aun es suyo). El scroll y el temblor, a 0 mientras (quien llama
; vuelve a poner el copper).
G_PICK:
        ld hl,(SCRL)
        push hl
        ld a,(SHAKEY)
        push af
        ld hl,0
        ld (SCRL),hl
        xor a
        ld (SHAKEY),a
        di
        call COPPERSET
        ei
        ld a,1
        ld (GESC),a
        ld (GMENUON),a
        call GROOTCD
        call GSCAN
        xor a
        ld (GSEL),a
        call GMENU
        push af
        xor a
        ld (GMENUON),a
        ld (GESC),a
        call GROOTCD                ; (a la del de ahora otra vez)
        ld hl,GCURDIR
        call GCD
        pop af
        pop bc                      ; (sin tocar los flags)
        ld a,b
        ld (SHAKEY),a
        pop hl
        ld (SCRL),hl
        ret

; Otro juego (el elegido en el menu de partidas: G_PICK), al empezar el paso (GSWITCH)
G_SWITCH:
        xor a
        ld (GAMEREQ),a
        ld hl,SNDSTOP               ; (sin el efecto que sonaba ni la musica)
        ld a,OVA_PAGE
        call OVCALL
        ld hl,MUSSTOP
        ld a,OVA_PAGE
        call OVCALL
        di
        call HIDESPR
        call G_GO                   ; a su carpeta
        jp c,FAIL
        call L2CLEAR
        call GAMEINIT
        jp c,FAIL
        ei
        ret

; (GSWITCH) A la carpeta del juego elegido en G_PICK; carry si falla
G_GO:   call GFCCLR
        ld a,(GSEL)
        jp GENTER

; Los bloques de VERBIMG.DAT e INVOBJ.DAT que se guardaron (CFREAD) son de otro juego
GFCCLR: ld a,LOADBUF
        ld (AUM3),a
        nextreg $53,a
        xor a
        ld ($6000),a                ; (FC_MAG: la firma)
        jp ZUNMAP

; A la carpeta del juego A de la lista (desde la del .nex), y se apunta; carry si falla
GENTER: call GENT
        push hl
        ld de,GCURDIR
        ld bc,13
        ldir
        call GROOTCD
        pop hl
        ld a,(hl)
        or a
        ret z                       ; (el de la carpeta del .nex)
GCD:    ld a,(hl)                   ; a la carpeta HL (si no esta vacia)
        or a
        ret z
        ld a,$A9                    ; F_CHDIR
        jr GESXH
GROOTCD:
        ld hl,GROOT
        ld a,$A9
; esxDOS: la llamada A (unidad la de siempre) con IX = HL y las paginas que quiere;
; IX como estaba. Vuelven A y los flags de esxDOS
GESXH:  push ix
        push hl
        pop ix
        ld (ESXN),a
        call FILESON
        ld a,'*'
        ld b,0
        call ESXCALL
        call FILESOFF               ; (no cambia A ni los flags)
        pop ix
        ret

; HL = el juego A de la lista
GENT:   ld e,a
        ld d,GESZ
        mul d,e
        ld hl,GLIST
        add hl,de
        ret

; --- la lista ---------------------------------------------------------------------
; GN juegos en GLIST: el de esta carpeta (si tiene GAME.DAT) y los de sus carpetas
; (las que lo tengan), por orden de nombre
GSCAN:  xor a
        ld (GN),a
        ld hl,GAMENAME
        call GEXIST
        jr c,.subs
        ld hl,GEMPTY                ; el de aqui
        call GADD
.subs:  ld a,$A3                    ; F_OPENDIR de la carpeta del .nex
        ld hl,GROOT
        call GESXH
        jr c,.sort
        ld (GDH),a
.rd:    ld a,(GN)
        cp GMAX
        jr nc,.cl
        ld a,$A4                    ; F_READDIR (A = el manejador)
        ld (ESXN),a
        push ix
        ld ix,GBUF
        call FILESON
        ld a,(GDH)
        call ESXCALL
        pop ix
        call FILESOFF
        jr c,.cl
        or a
        jr z,.cl                    ; (ya no hay mas)
        ld a,(GBUF)                 ; una carpeta, que no sea . ni ..
        and $10
        jr z,.rd
        ld a,(GBUF+1)
        cp '.'
        jr z,.rd
        or a
        jr z,.rd
        ld hl,GBUF+1                ; con su GAME.DAT?
        ld de,GAMENAME
        call GMKPATH
        ld hl,GPATH
        call GEXIST
        jr c,.rd
        ld hl,GBUF+1
        call GADD
        jr .rd
.cl:    ld a,(GDH)
        call FILESON
        call FCLOSE
        call FILESOFF
.sort:  ld a,(GN)                   ; por el nombre que se ve (burbuja: son pocos)
        cp 2
        ret c
        dec a
        ld (GK),a
.pass:  xor a
        ld (GSW),a
        ld b,a
.pr:    push bc
        ld a,b
        call GENT
        push hl
        ld de,GESZ
        add hl,de
        ex de,hl                    ; DE = el siguiente
        pop hl
        push hl
        push de
        ld bc,GE_TIT
        add hl,bc
        ex de,hl
        add hl,bc
        ex de,hl
.cmp:   ld a,(de)                   ; el de HL despues del de DE: se cambian
        call GUPPER
        ld c,a
        ld a,(hl)
        call GUPPER
        cp c
        jr c,.keep
        jr nz,.swap
        or a
        jr z,.keep
        inc hl
        inc de
        jr .cmp
.swap:  pop de
        pop hl
        ld b,GESZ
.sw:    ld a,(de)
        ld c,(hl)
        ld (hl),a
        ld a,c
        ld (de),a
        inc hl
        inc de
        djnz .sw
        ld a,1
        ld (GSW),a
        jr .nx
.keep:  pop de
        pop hl
.nx:    pop bc
        inc b
        ld a,(GK)
        cp b
        jr nz,.pr
        ld a,(GSW)
        or a
        jr nz,.pass
        ret

; A en mayusculas (solo a-z)
GUPPER: cp 'a'
        ret c
        cp 'z'+1
        ret nc
        sub 32
        ret

; GPATH = la carpeta HL, "/" y el fichero DE (si HL esta vacia, solo el fichero)
GMKPATH:
        push de
        ld de,GPATH
.d:     ld a,(hl)
        or a
        jr z,.e
        ld (de),a
        inc hl
        inc de
        jr .d
.e:     ld a,e
        cp GPATH & $FF
        jr z,.f
        ld a,'/'
        ld (de),a
        inc de
.f:     pop hl
.g:     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,.g
        ret

; NC si el fichero HL se puede abrir
GEXIST: call FILESON
        call FOPEN
        jr c,.no
        call FCLOSE
        or a
.no:    jp FILESOFF

; Un juego mas: la carpeta HL ("" la del .nex) y su nombre (TITULO.TXT; si no, el de
; la carpeta)
GADD:   push hl
        ld a,(GN)
        call GENT
        ld (GADP),hl
        ex de,hl
        pop hl
        push hl
        ld bc,12
.c:     ld a,(hl)                   ; la carpeta
        ld (de),a
        or a
        jr z,.t
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,.c
        xor a
        ld (de),a
.t:     pop hl
        ld de,GTITNAME
        call GMKPATH
        ld hl,(GADP)
        ld de,GE_TIT
        add hl,de
        push hl
        ld b,GTMAX+1
.z0:    ld (hl),0
        inc hl
        djnz .z0
        pop hl
        push hl
        ld hl,GPATH
        call FILESON
        call FOPEN
        jr c,.nt
        ld (GDF),a
        pop hl
        push hl
        ld bc,GTMAX
        call FREAD
        ld a,(GDF)
        call FCLOSE
        call FILESOFF
        pop hl
        ld b,GTMAX                  ; hasta el final de la linea
.l:     ld a,(hl)
        cp 32
        jr c,.z
        inc hl
        djnz .l
.z:     ld (hl),0
        ld hl,(GADP)
        ld de,GE_TIT
        add hl,de
        ld a,(hl)
        or a
        jr nz,.ok
        push hl
        jr .dn
.nt:    call FILESOFF
.dn:    pop de                      ; sin nombre: el de la carpeta
        ld hl,(GADP)
        ld a,(hl)
        or a
        jr nz,.cp
        ld hl,GT_HERE
.cp:    ld b,GTMAX
.cc:    ld a,(hl)
        ld (de),a
        or a
        jr z,.ok
        inc hl
        inc de
        djnz .cc
        xor a
        ld (de),a
.ok:    ld hl,GN
        inc (hl)
        ret

; --- el menu ----------------------------------------------------------------------
; Con las cifras o el raton (o CAPS + 5 6 7 8) y ENTER o el boton; ESC si GESC (carry).
; GSEL = el elegido
GMENU:  xor a
        ld (KEYPEND),a
        ld hl,160                   ; el cursor, debajo de la lista
        ld (CURX),hl
        ld hl,ROOM_Y0+180
        ld (CURY),hl
        ld (GLCY),hl
.draw:  call GDRAW
.wait:  call GFRAME
        ld hl,(CURY)                ; el raton, encima de otro: ese
        ld de,(GLCY)
        ld (GLCY),hl
        or a
        sbc hl,de
        jr z,.k
        ld hl,(CURY)
        ld de,GROW0-2
        or a
        sbc hl,de
        jr c,.k
        ld a,l
        ld e,GROWH
        call GDIV
        ld b,a
        ld a,h
        or a
        jr nz,.k
        ld a,(GN)
        dec a
        cp b
        jr c,.k
        ld a,(GSEL)
        cp b
        jr z,.k
        ld a,b
        ld (GSEL),a
        jr .draw
.k:     ld a,(KEYPEND)
        or a
        jr z,.wait
        ld b,a
        xor a
        ld (KEYPEND),a
        ld a,b
        cp 27
        jr nz,.n1
        ld a,(GESC)
        or a
        jr z,.wait
        scf
        ret
.n1:    cp 1                        ; ENTER o el boton izquierdo: ese
        jr nz,.n2
        or a
        ret
.n2:    sub '1'
        jr c,.wait
        ld hl,GN
        cp (hl)
        jr nc,.wait
        ld (GSEL),a
        jr .draw

; A = A / E (pocos), sin resto
GDIV:   ld d,0
.l:     sub e
        jr c,.e
        inc d
        jr .l
.e:     ld a,d
        ret

; Una imagen. Sin interrupciones (al arrancar), lo de la interrupcion aqui: la linea
; 200 a mano, el teclado, el raton y el cursor
GFRAME: ld a,i                      ; P/V = IFF2
        jp po,.di
        ld a,(FRAMES)
        ld b,a
.w:     ld a,(FRAMES)
        cp b
        jr z,.w
        ret
.di:    ld bc,$243B
        ld a,$1F
        out (c),a
        inc b
.w1:    in a,(c)
        cp 200
        jr z,.w1
.w2:    in a,(c)
        cp 200
        jr nz,.w2
        call KEYSCAN
        call INPUT
        jp CURSORSPR

; La pantalla del menu: Layer 2 (A) en negro, el titulo, la lista y las teclas
GDRAW:  xor a
.f:     ld (GK),a
        add a,L2_PAGE
        nextreg $52,a
        ld hl,$4000
        ld de,$4001
        ld bc,$1FFF
        ld (hl),0
        ldir
        ld a,(GK)
        inc a
        cp 10
        jr nz,.f
        nextreg $43,%00010000       ; 0 negro, 253 gris, 254 amarillo, 255 blanco
        nextreg $40,0
        nextreg $44,0
        nextreg $44,0
        nextreg $40,253
        nextreg $44,$6D
        nextreg $44,1
        nextreg $44,$FC
        nextreg $44,0
        nextreg $44,$FF
        nextreg $44,1
        ld hl,GT_TITLE
        ld de,ROOM_Y0+12
        ld bc,24
        ld a,255
        call GTEXTXY
        xor a
.e:     ld (GK),a
        ld hl,GN
        cp (hl)
        jr nc,.keys
        ld e,a                      ; fila: GROW0 + GROWH * n
        ld d,GROWH
        mul d,e
        ld hl,GROW0
        add hl,de
        ld (GY),hl
        ld a,(GSEL)
        ld b,a
        ld a,(GK)
        cp b
        ld a,253
        jr nz,.c
        ld a,254
        push af
        ld hl,GT_MARK               ; (el elegido)
        ld de,(GY)
        ld bc,16
        call GTEXTXY
        pop af
.c:     ld (GTCOL),a
        ld a,(GK)
        add a,'1'
        ld (GNUM),a
        ld hl,GNUM
        ld de,(GY)
        ld bc,28
        ld a,(GTCOL)
        call GTEXTXY
        ld a,(GK)
        call GENT
        ld de,GE_TIT
        add hl,de
        ld de,(GY)
        ld bc,44
        ld a,(GTCOL)
        call GTEXTXY
        ld a,(GK)
        inc a
        jr .e
.keys:  ld hl,GT_KEYS1
        ld de,ROOM_Y0+168
        ld bc,24
        ld a,255
        call GTEXTXY
        ld hl,GT_KEYS2
        ld a,(GESC)
        or a
        jr z,.k2
        ld hl,GT_KEYS3
.k2:    ld de,ROOM_Y0+180
        ld bc,24
        ld a,255
        call GTEXTXY
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; El texto HL en x = BC, fila DE de Layer 2 (A), color A
GTEXTXY:
        ld (GTCOL),a
        ld (GX),bc
        ld a,e
        ld (GY),a
; El texto HL (acabado en 0) desde (GX), fila (GY), color (GTCOL); 6 pixeles por letra
GTEXT:  ld a,(hl)
        or a
        ret z
        inc hl
        push hl
        call GGLYPH
        ld b,5
.c:     push bc
        push hl
        ld c,(hl)                   ; la columna (bit 0 arriba)
        ld hl,(GX)
        ld de,-320
        add hl,de
        jr c,.e                     ; (fuera de la pantalla)
        ld hl,(GX)
        ld a,l
        and 31
        add a,$40
        ld d,a                      ; D = $40 + (x mod 32)
        ld a,l                      ; la pagina: L2_PAGE + x / 32
        rlca
        rlca
        rlca
        and 7
        bit 0,h
        jr z,.p
        add a,8
.p:     add a,L2_PAGE
        nextreg $52,a
        ld a,(GY)
        ld e,a
        ld a,(GTCOL)
        ld b,7
.r:     rr c
        jr nc,.n
        ld (de),a
.n:     inc e
        djnz .r
.e:     ld hl,(GX)
        inc hl
        ld (GX),hl
        pop hl
        inc hl
        pop bc
        djnz .c
        ld hl,(GX)                  ; (y una columna entre letras)
        inc hl
        ld (GX),hl
        pop hl
        jr GTEXT

; HL = las 5 columnas de la letra A (Latin-1; las que no hay, '?')
GGLYPH: cp 32
        jr c,.q
        cp 127
        jr nc,.x
        sub 32
        jr .i
.x:     ld hl,GFEXT
        ld c,a
.xl:    ld a,(hl)
        or a
        jr z,.q
        inc hl
        cp c
        ld a,(hl)
        inc hl
        jr nz,.xl
        jr .i
.q:     ld a,GFQ
.i:     ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        ld de,GFONT
        add hl,de
        ret

        INCLUDE "gen/font.asm"

GT_TITLE: db "Elige un juego",0
GT_KEYS1: db "1-",'0'+GMAX," o el rat",$F3,"n: elegir     ENTER: empezar",0
GT_KEYS2: db "(las partidas de cada juego van en su carpeta)",0
GT_KEYS3: db "ESC: volver al juego de ahora",0
GT_HERE:  db "El juego de esta carpeta",0
GT_MARK:  db ">",0
GTITNAME: db "TITULO.TXT",0
GEMPTY:   db 0
GNUM:     db "1",0
GN:     db 0                        ; juegos en la lista
GSEL:   db 0                        ; el elegido
GESC:   db 0                        ; 1: ESC vuelve (G_PICK)
GK:     db 0
GSW:    db 0
GDH:    db 0                        ; (GSCAN) la carpeta abierta
GDF:    db 0                        ; (GADD) el fichero abierto
GADP:   dw 0
GX:     dw 0
GY:     dw 0
GTCOL:   db 0
GLCY:   dw 0                        ; (GMENU) la y del raton antes
GCURDIR: ds 13                      ; la carpeta del juego de ahora ("": la del .nex)
GROOT:  ds 128                      ; la carpeta del .nex
GPATH:  ds 32
GBUF:   ds 64                       ; (F_READDIR) atributos, nombre, fecha y largo
GLIST:  ds GMAX*GESZ
