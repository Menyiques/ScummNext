; ===========================================================================
;  Objetos de la habitacion (model.recompose / obj_visible / obj_at y los
;  ganchos de World: find_object, object_walk_xy...)
;
;  Las tiras de trabajo (las que se ven y las que usa el actor para los
;  planos Z) son el fondo con los objetos visibles encima. Cuando cambia el
;  estado de un objeto, sus tiras se rehacen desde la copia limpia: primero
;  el fondo y despues cada objeto visible que las toca, del ultimo al primero.
;  Los estados estan en la tabla global OBJST (la de la maquina virtual).
;
;  Objeto (24 bytes en META): numero(2) x(1) y(1) ancho(1) alto(1) padre(1)
;  estado del padre(1) (1 sin usar) imagenes(1) offset de la tabla de
;  imagenes(2) bloque VERB(3) x e y a donde se anda(2+2) longitud del VERB(2)
; ===========================================================================
O_X     EQU 2
O_Y     EQU 3
O_W     EQU 4
O_H     EQU 5
O_PAR   EQU 6
O_PST   EQU 7
O_DIR   EQU 8                   ; hacia donde se mira al llegar (0-3, como los antiguos)
O_NIMG  EQU 9
O_IMGT  EQU 10
O_VERB  EQU 12
O_WX    EQU 15
O_WY    EQU 17
O_VLEN  EQU 19
O_NAME  EQU 21                  ; lineal del nombre (3)
O_SIZE  EQU 24

; HL = direccion del objeto A
OBJPTR:
        ld e,a
        ld d,24
        mul d,e
        ld hl,(OBJT)
        add hl,de
        ret

; A = estado (global) del objeto IY
OSTATE:
        push hl
        push de
        ld l,(iy+0)
        ld h,(iy+1)
        call GETSTATE
        pop de
        pop hl
        ret

; carry si el objeto A se dibuja: tiene estado y cada padre esta en el
; estado que pide su hijo (drawRoomObject). Cambia IY.
VISIBLE:
        call OBJPTR
        push hl
        pop iy
        call OSTATE
        or a
        ret z                       ; sin estado: nc
        ld b,16
.lp:    ld c,(iy+O_PST)
        ld a,(iy+O_PAR)
        or a
        jr z,.yes
        ld hl,NOBJ
        cp (hl)
        jr z,.in
        jr nc,.no                   ; padre fuera de la lista
.in:    dec a
        push bc
        call OBJPTR
        pop bc
        push hl
        pop iy
        call OSTATE
        and $0F
        cp c
        jr nz,.no
        djnz .lp
.no:    or a
        ret
.yes:   scf
        ret

; Rehace la tira de trabajo A desde su copia limpia y los objetos. Si cambian sus
; planos Z, su sello (los dibujos guardados de los actores que la tapan ya no valen).
RECOMPOSE:
        ld hl,(RCY0)
        push hl
        ld hl,$FF00                 ; todas las filas
        ld (RCY0),hl
        call RECOMPOSER
        pop hl
        ld (RCY0),hl
        ret
; Lo mismo, solo en las filas [RCY0, RCY1): cada fila sale de la misma fila de la
; copia limpia y de los objetos, asi que las demas ya estan bien
RECOMPOSER:
        ld (RCS),a
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de                   ; 3 * tira
        push hl
        ld de,(PRISTAB)
        add hl,de
        ld a,(hl)
        ld (RCPRI),a                ; ($FF: sin copia limpia; los objetos, encima)
        cp $FF
        jr z,.nocov
        inc hl                      ; la copia limpia (por $E000, RCCOPY)
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (RCSRC),de
.nocov: pop hl
        ld de,(STRIPT)              ; la de trabajo, por $C000
        add hl,de
        ld a,(hl)
        add a,STRIP_PAGE
        ld (SHMMU6),a
        nextreg $56,a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (RCDST),de
        call ZSAVE                  ; (los planos de antes)
        ld a,(RCPRI)                ; la copia limpia, cuando se sepa si hace falta: no
        inc a                       ; si el primer objeto que se pone la tapa entera
        ld (RCPEND),a               ; (RCLAZY, desde APPLY); si no, antes o al final
        call ZON                    ; (la x y el ancho de cada uno: ZOBXO, ZOBWO)
        xor a                       ; primero los demas y despues, si los hay, los de
        ld (RCPASS),a               ; encima (ZOBTOP)
.pass:  ld a,(NOBJ)
        or a
        jp z,.nob
        ld b,a
        ld a,(ZBMOK)
        or a
        jr nz,.bm
        ld a,(RCS)
        ld c,a
        ld l,b
        ld h,($6000+ZOBXO)>>8
.obj:   dec l                       ; x <= tira < x + ancho: (tira - x) mod 256 < ancho
        ld a,c                      ; (en ZOBWO, como mucho 256 - x)
        sub (hl)
        inc h
        cp (hl)
        dec h
        jr c,.got
.next:  djnz .obj
        jp .endp
.got:   push bc
        push hl
        call RCOBJ
        pop hl
        pop bc
        jr .next
.bm:    ld a,(RCS)                  ; con el mapa de la tira (ZOBBM): solo los que la
        ld l,a                      ; tocan, de los de mas indice a los de menos
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,$6000+ZOBBM+7
        add hl,de
        ld b,8
.by:    ld a,(hl)
        or a
        jr nz,.bt0
.bn:    dec hl
        djnz .by
        jp .endp
.bt0:   push hl
        push bc
        ld c,a
        ld a,b
        add a,a
        add a,a
        add a,a
        ld e,a
.bt:    dec e
        sla c
        jr nc,.bs
        push bc
        push de
        ld l,e
        ld h,($6000+ZOBXO)>>8
        ld a,(RCS)
        sub (hl)
        call RCOBJ
        pop de
        pop bc
.bs:    ld a,c
        or a
        jr nz,.bt
        pop bc
        pop hl
        jr .bn
.endp:  ld hl,RCPASS
        ld a,(hl)
        or a
        jr nz,.nob
        ld a,(ZTOPN)
        or a
        jr z,.nob
        inc (hl)
        jp .pass
.nob:   call ZUNMAP
        ld a,(RCPEND)               ; (ninguno la ha tapado)
        or a
        call nz,RCCOPY
        call ZCHECK
        ld a,(CPAGE)
        jp MAP7

; (RECOMPOSER, con ZSCR por $6000) El objeto L (H = la pagina de ZOBXO), que toca la
; tira RCS en su tira A, en la de trabajo; vuelve con ZSCR otra vez por $6000
RCOBJ:  ld (RCJ),a
        ld a,l
        ld (RCK),a
        push hl                     ; (en su pasada: los de encima, en la segunda)
        call ZTOPTST
        pop hl
        ld a,(RCPASS)
        jr z,.t0
        dec a
.t0:    or a
        ret nz
        inc h
        inc h                       ; lo que ya se sabe de su imagen (ZOBIV)
        ld a,(hl)
        dec a
        ret z                       ; (1: no se dibuja)
        ld b,(hl)
        inc h
        ld c,(hl)                   ; (2: su cabecera)
        inc h
        ld e,(hl)
        inc h
        ld d,(hl)
        call ZUNMAP                 ; (lo demas, sin ella)
        push bc
        push de
        ld a,(RCK)
        call OBJPTR
        push hl
        pop iy
        pop de
        pop bc
        ld a,b
        or a
        jr nz,.hit
        ld a,(RCK)                  ; (0: se busca, y se guarda)
        call VISIBLE
        jr nc,.no
        ld a,(RCK)
        call OBJPTR
        push hl
        pop iy
        call OSTATE                 ; estado <= imagenes ?
        cp (iy+O_NIMG)
        jr z,.img
        jr nc,.no
.img:   dec a                       ; su imagen: tabla + 3 * (estado - 1)
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld e,(iy+O_IMGT)
        ld d,(iy+O_IMGT+1)
        add hl,de
        ld de,META
        add hl,de
        ld a,(hl)
        cp $FF
        jr z,.no
        add a,STRIP_PAGE            ; cabecera de la imagen
        ld c,a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld b,2
        call ZIMSET
        jr .hit
.no:    ld b,1
        call ZIMSET
        jr .nz
.hit:   ld a,c
        call MAP7
        ex de,hl
        ld a,(hl)
        ld (RCPM),a                 ; planos que trae
        inc hl
        ld a,(RCJ)                  ; puntero de su tira j
        ld e,a
        ld d,0
        add hl,de
        add hl,de
        add hl,de
        ld a,(hl)                   ; todo el puntero antes de cambiar de pagina:
        inc hl                      ; la cabecera tambien esta por $E000
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (RCREC),de
        add a,STRIP_PAGE
        call MAP7
        call APPLY
.nz:    jp ZON
ZBMOK:  db 0                        ; 1: el mapa de objetos de cada tira (ZOBBM) vale
; (RCOBJ) nz si el objeto de indice A va encima (cambia C y HL)
ZTOPTST:
        call ZTOPAD
        and (hl)
        ret

; (RECOMPOSER) Lo que se sabe de la imagen del objeto RCK: B (ZOBIV), C, DE (su cabecera)
ZIMSET: call ZON
        ld a,(RCK)
        ld l,a
        ld h,($6000+ZOBIV)>>8
        ld (hl),b
        inc h
        ld (hl),c
        inc h
        ld (hl),e
        inc h
        ld (hl),d
        jp ZUNMAP

; Se olvida lo que se sabe de las imagenes de todos los objetos (ZOBIV)
ZIVCLR: ld a,(NOBJ)
        or a
        ret z
        ld b,a
        call ZON
        ld hl,$6000+ZOBIV
.lp:    ld (hl),0
        inc l
        djnz .lp
        jp ZUNMAP

; Donde empiezan los planos en una tira (BC = 8 * alto) y lo que ocupan (HL = RREC - BC)
ZPART:
        push de
        ld a,(RH)
        ld e,a
        ld d,8
        mul d,e
        ld hl,(RREC)
        or a
        sbc hl,de
        ld b,d
        ld c,e
        pop de
        ret

; (ZCHECK, con ZSCR_PAGE por $6000) Los planos Z de la tira RCS han cambiado: su
; sello, el siguiente; si se acaban (65535 cambios), que no valga nada guardado (CGEN)
ZSTAMPSET:
        ld hl,($6000+ZGENO)
        inc hl
        ld a,h
        or l
        jr z,.full
        ld ($6000+ZGENO),hl
        ex de,hl
        ld a,(RCS)
        ld l,a
        ld h,0
        add hl,hl
        ld bc,$6000+ZSTO
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        jr ZUNMAP
.full:  ld hl,(CGEN)
        inc hl
        ld (CGEN),hl
        jr ZUNMAP

; (RECOMPOSE) Los planos de la tira de trabajo, a la pagina ZSCR_PAGE (por $6000)
ZSAVE:
        call ZMAP
        jr z,ZUNMAP
        xor a
        ld (RGCMP),a
        ld a,(RNZ)
        call RGDO
ZUNMAP: ld a,(SPRCUR)
        ld (AUM3),a
        nextreg $53,a
        ret

; (RECOMPOSE) Si los planos han cambiado, los dibujos guardados de los actores que
; tapan esta tira ya no valen (su sello)
ZCHECK:
        call ZMAP
        jr z,ZUNMAP
        ld a,1
        ld (RGCMP),a
        ld a,(RNZ)
        call RGDO
        jp nz,ZSTAMPSET             ; (la tira RCS: su sello)
        jr ZUNMAP

; (RECOMPOSE) A columnas de RH bytes desde HL y DE, solo en las filas [RCY0,
; min(RCY1, RH)): RGCMP = 0, de HL a DE; si no, las compara (nz: alguna distinta)
RGDO:   ld (RGK),a
        ld a,(RCY0)
        add hl,a
        add de,a
        ld b,a
        ld a,(RH)
        ld c,a
        ld a,(RCY1)
        cp c
        jr c,.r1
        ld a,c
.r1:    sub b
        jr c,.eq
        jr z,.eq
        ld (RGNV),a                 ; (RGNV + 1 siempre 0: BC = filas)
        ld b,a
        ld a,(RH)
        sub b
        ld (RGSK),a                 ; RH - filas: hasta la columna siguiente
        ld a,(RGK)                  ; (IYL cuenta las columnas)
        ld iyl,a
        ld a,(RGCMP)
        or a
        jr nz,.cmp
        ld a,b
        cp 32
        jr nc,.dma
        ld a,(RGSK)
.ld:    ld bc,(RGNV)                ; (pocas: LDIR)
        ldir
        add hl,a
        add de,a
        dec iyl
        jr nz,.ld
        ret                         ; (z)
.dma:   ld bc,(RGNV)
        call DMACP
        ld a,(RGSK)
        add hl,a
        add de,a
        dec iyl
        jr nz,.dma
        ret
.cmp:   ld bc,(RGNV)
.cb:    ld a,(de)
        cpi
        ret nz                      ; distinta
        inc de
        jp pe,.cb
        ld a,(RGSK)
        add hl,a
        add de,a
        dec iyl
        jr nz,.cmp
.eq:    xor a                       ; (z: iguales)
        ret
RGK:    db 0
RGNV:   dw 0
RGSK:   db 0
RGCMP:  db 0
RCTOP:  db 0                        ; (APPLY) filas de arriba que no se pintan
RCDSK:  db 0                        ; (APPLY) lo que se salta tras cada columna en la de trabajo
RCSSK:  db 0                        ; (APPLY) y en la del objeto
RCOPT:  dw 0                        ; (APPLY) la opacidad desde RCTOP

; Pone la tira RCREC del objeto IY en la tira de trabajo RCDST (solo en las filas
; [RCY0, RCY1))
APPLY:
        ld a,(iy+O_Y)
        ld (RCY),a
        ld a,(iy+O_H)
        ld (RCH),a
        ld b,a                      ; las filas que se pintan: min(alto, RH - y)
        ld a,(RH)
        sub (iy+O_Y)
        ret c
        ret z
        cp b
        jr c,.rc
        ld a,b
.rc:    ld (RCHC),a
        ld e,a                      ; opacidad en RCREC + 8 * alto
        ld d,8
        mul d,e
        ld hl,(RCREC)
        add hl,de
        ld (RCOPA),hl
        ld hl,(RCREC)
        ld (RCSP),hl
        ld a,(RCY1)                 ; las filas, a [RCY0, RCY1): hasta RCY1 - y
        sub (iy+O_Y)
        ret c
        ret z
        ld hl,RCHC
        cp (hl)
        jr nc,.e1
        ld (hl),a
.e1:    xor a                       ; y desde RCY0 - y (RCTOP: las que se saltan)
        ld (RCTOP),a
        ld a,(RCY0)
        sub (iy+O_Y)
        jr c,.t0
        jr z,.t0
        ld b,a
        ld a,(hl)
        sub b
        ret c
        ret z
        ld (hl),a
        ld a,b
        ld (RCTOP),a
        ld hl,RCY
        add a,(hl)
        ld (hl),a
.t0:    ld hl,(RCOPA)
        ld a,(RCTOP)
        add hl,a
        ld (RCOPT),hl
        ld a,(RCHC)                 ; las columnas opacas en todas estas filas (AND de
        ld b,a                      ; la opacidad): esas, de una vez
        ld a,$FF
.op:    and (hl)
        inc hl
        djnz .op
        ld (RCALL),a
        ld hl,RCPEND                ; (la copia limpia, si sigue pendiente)
        inc (hl)
        dec (hl)
        call nz,RCLAZY
        ld a,(RH)                   ; tras cada columna se saltan RH - filas en la de
        ld hl,RCHC                  ; trabajo y RCH - filas en la del objeto
        sub (hl)
        ld (RCDSK),a
        ld a,(RCH)
        sub (hl)
        ld (RCSSK),a
        ld a,$80
        ld (RCBIT),a
        ld de,(RCDST)               ; la columna 0: trabajo + y, y la del objeto desde RCTOP
        ld a,(RCY)
        add de,a
        ld hl,(RCSP)
        ld a,(RCTOP)
        add hl,a
        ld a,(RCALL)                ; todas opacas en menos de 32 filas: un bucle corto
        inc a
        jr nz,.col
        ld a,(RCHC)
        cp 32
        jr nc,.col
        ld c,a
        ld b,0
        ld a,(RCSSK)
        ld (.fs+1),a
        ld a,(RCDSK)
        ld (.fd+1),a
        ld iyl,8
.fl:    push bc
        ldir
        pop bc
.fs:    ld a,0
        add hl,a
.fd:    ld a,0
        add de,a
        dec iyl
        jr nz,.fl
        jr .pls
.col:   ld a,(RCALL)
        ld c,a
        ld a,(RCBIT)
        and c
        jr z,.msk
        ld a,(RCHC)
        ld c,a
        ld b,0
        call DMACP
        jr .cnx
.msk:   ld a,(RCBIT)                ; (con la opacidad de cada fila)
        ld (.mk+1),a
        ld a,(RCHC)
        ld iyl,a
        ld bc,(RCOPT)
.row:   ld a,(bc)
.mk:    and 0
        jr z,.tr
        ld a,(hl)
        ld (de),a
.tr:    inc hl
        inc de
        inc bc
        dec iyl
        jr nz,.row
.cnx:   ld a,(RCDSK)
        add de,a
        ld a,(RCSSK)
        add hl,a
        ld a,(RCBIT)
        rrca
        ld (RCBIT),a
        jr nc,.col
        ; planos: los que trae la imagen sustituyen a los de la habitacion
.pls:   ld hl,(RCOPA)               ; tras la opacidad
        ld a,(RCH)
        add hl,a
        ld (RCSP),hl
        ld a,1
        ld (RCC),a
.pl:    ld a,(RCC)
        ld hl,RNZ
        cp (hl)
        jr z,.pin
        ret nc
.pin:   ld b,a                      ; bit del plano
        ld a,(RCPM)
.sh:    rrca
        djnz .sh
        jr nc,.pnext                ; (el bit p-1 acaba en el acarreo)
        ld a,(RCC)                  ; destino: trabajo + (7 + p) * alto + y
        add a,7
        ld e,a
        ld a,(RH)
        ld d,a
        mul d,e
        ld hl,(RCDST)
        add hl,de
        ld a,(RCY)
        add hl,a
        ex de,hl
        ld hl,(RCSP)
        push hl
        ld a,(RCTOP)
        add hl,a
        ld a,(RCHC)
        ld c,a
        ld b,0
        ldir
        pop hl
        ld a,(RCH)
        add hl,a
        ld (RCSP),hl
.pnext: ld hl,RCC
        inc (hl)
        jr .pl

; Rehace todas las tiras que tocan los objetos (al entrar en la habitacion)
RECOMPALL:
        xor a
.lp:    ld hl,RNS
        cp (hl)
        ret nc
        push af
        call RECOMPOSE
        pop af
        inc a
        jr .lp

; carry si el objeto A es K o desciende de el (K en SSK). Cambia IY.
DESC:
        ld b,16
.lp:    ld hl,SSK
        cp (hl)
        jr z,.yes
        push bc
        call OBJPTR
        pop bc
        push hl
        pop iy
        ld a,(iy+O_PAR)
        or a
        jr z,.no
        ld hl,NOBJ
        cp (hl)
        jr z,.in
        jr nc,.no
.in:    dec a
        djnz .lp
.no:    or a
        ret
.yes:   scf
        ret

; El objeto A ha cambiado de estado: apunta sus tiras y las de sus hijos.
; Se rehacen una sola vez por paso, en FLUSHOBJ (los scripts pueden cambiar
; decenas de objetos seguidos).
REDRAWOBJ:
        ld (SSK),a
        ld a,1
        ld (DIRTYF),a
        ld a,$FF                    ; tiras afectadas: [SSMIN, SSMAX)
        ld (SSMIN),a
        xor a
        ld (SSMAX),a
        ld a,(SSK)                  ; sin hijos (lo normal): solo el
        call OBJPTR
        push hl
        pop iy
        bit 7,(iy+O_DIR)
        jr nz,.all
        call ZON                    ; (lo que se sabia de su imagen ya no vale)
        ld a,(SSK)
        ld l,a
        ld h,($6000+ZOBIV)>>8
        ld (hl),0
        ld a,(iy+O_W)
        or a
        jp z,ZUNMAP
        call ZROWS1
        ld a,(iy+O_X)
        ld (SSMIN),a
        add a,(iy+O_W)
        ld (SSMAX),a
        jp .draw
.all:   call ZIVCLR                 ; (y lo de sus hijos)
        ld a,(NOBJ)                 ; de 24 en 24 desde el ultimo
        or a
        jr z,.draw
        dec a
        ld (SSJ),a
        call OBJPTR
        push hl
        pop iy
.j:     ld a,(SSJ)
        ld hl,SSK
        cp (hl)
        jr z,.yes                   ; el mismo
        ld a,(iy+O_PAR)
        or a
        jr z,.nj                    ; sin padre no desciende de nadie (lo normal)
        push iy
        ld a,(SSJ)
        call DESC
        pop iy
        jr nc,.nj
.yes:   ld a,(iy+O_W)
        or a
        jr z,.nj
        call ZROWS                  ; sus filas, en las de sus tiras
        ld a,(iy+O_X)
        ld hl,SSMIN
        cp (hl)
        jr nc,.n1
        ld (hl),a
.n1:    add a,(iy+O_W)
        ld hl,SSMAX
        cp (hl)
        jr c,.nj
        ld (hl),a
.nj:    ld a,(SSJ)
        or a
        jr z,.draw
        dec a
        ld (SSJ),a
        ld de,-24
        add iy,de
        jr .j
.draw:  ld a,(SSMIN)
.s:     ld hl,SSMAX
        cp (hl)
        ret nc
        push af
        call DIRTYADDR
        or (hl)
        ld (hl),a
        pop af
        inc a
        jr .s

; (REDRAWOBJ) Las filas del objeto IY, en las de cada una de sus tiras
ZROWS:  call ZON
ZROWS1: ld a,(iy+O_Y)
        ld d,a                      ; desde
        add a,(iy+O_H)
        jr nc,.h
        ld a,$FF
.h:     ld e,a                      ; hasta
        ld l,(iy+O_X)
        ld h,($6000+ZYMNO)>>8
        ld b,(iy+O_W)
.lp:    bit 7,l                     ; (de la 128 en adelante no hay)
        jr nz,.end
        ld a,d
        cp (hl)
        jr nc,.n1
        ld (hl),a
.n1:    set 7,l
        ld a,e
        cp (hl)
        jr c,.n2
        ld (hl),a
.n2:    res 7,l
        inc l
        djnz .lp
.end:   jp ZUNMAP

; D = el ancho D, como mucho 256 - E (la x): la cuenta de RECOMPOSER no da la vuelta
ZWEFF:  ld a,e
        neg
        ret z
        cp d
        ret nc
        ld d,a
        ret

; (FLUSHOBJ) RCY0, RCY1 = las filas apuntadas de la tira A, que se queda sin ninguna.
; No cambia A ni los flags.
ZRGET:  push af
        ld l,a
        ld h,($6000+ZYMNO)>>8
        call ZON
        ld a,(hl)
        ld (hl),$FF
        ld (RCY0),a
        set 7,l
        ld a,(hl)
        ld (hl),0
        ld (RCY1),a
        call ZUNMAP
        pop af
        ret

; La pagina ZSCR_PAGE por $6000 (AUM3: la que pone otra vez el CTC); ZUNMAP la quita
ZON:    ld a,ZSCR_PAGE
        ld (AUM3),a
        nextreg $53,a
        ret

; BC bytes de HL a DE (como LDIR: HL y DE avanzan, BC = 0; cambia A). De 32 a 255, por
; el DMA, de una vez, con las interrupciones cortadas (la de linea tambien lo usa; el
; CTC, que no para el DMA (NR $CD a 0), espera menos de una muestra). Pocos, o con las
; interrupciones ya cortadas, LDIR.
DMACP:  ld a,b
        or a
        jr nz,.ld
        ld a,c
        cp 32
        jr c,.ld
        ld a,i                      ; P/V = IFF2
        jp po,.ld
        di                          ; (ya: la interrupcion tambien lo usa, DSCORE)
        ld (DCSRC),hl
        ld (DCDST),de
        ld (DCLEN),bc
        add hl,bc
        ex de,hl
        add hl,bc
        ex de,hl
        push hl
        push de
        ld hl,DCPROG                ; (si ya es de memoria a memoria, DMAMEM: solo
        ld bc,DCPLEN*256+$6B        ; las direcciones y la longitud)
        ld a,(DMAMEM)
        or a
        jr z,.full
        ld hl,DCSHORT
        ld b,DCSLEN
.full:  otir
        ei
        ld a,1
        ld (DMAMEM),a
        pop de
        pop hl
        ld bc,0
        ret
.ld:    ldir
        ret
DCPROG: db $83                      ; para el DMA
        db %01010100                ; WR1: A es memoria y avanza
        db %00000010
        db %01010000                ; WR2: B es memoria y avanza
        db %00000010
        db %10000010                ; WR5
DCSHORT:
        db $83
        db %01111101                ; WR0: de A a B, direccion y longitud
DCSRC:  dw 0
DCLEN:  dw 0
        db %10101101                ; WR4: continuo, direccion de B
DCDST:  dw 0
        db $CF                      ; carga
        db $87                      ; en marcha
DCPLEN  EQU $-DCPROG
DCSLEN  EQU $-DCSHORT

; Rehace las tiras apuntadas que se ven, y otra vez en pantalla; las demas quedan
; atrasadas (STALE) hasta que entren en la vista o un actor que se ve las tape
; (FRESH; K_ZFRESH). Con las
; interrupciones como esten: durante el paso la de linea no pinta (UPLOAD = 0) y
; las del CTC (la musica, los efectos) solo usan su ventana $6000 (AUM3).
FLUSHOBJ:
        ld a,(DIRTYF)
        or a
        ret z
        xor a
        ld (DIRTYF),a
.lp:    ld hl,RNS
        cp (hl)
        ret nc
        push af
        call DIRTYADDR
        ld b,a
        and (hl)
        jr z,.next
        ld a,b
        xor (hl)
        ld (hl),a
        pop af                      ; sus filas apuntadas (y la tira, sin ninguna)
        push af
        push hl
        call ZRGET
        pop hl
        add hl,STALE-DIRTY
        ld a,(CAM_SS)
        ld c,a
        pop af
        push af
        sub c                       ; se ve? izquierda <= s < izquierda + 40
        cp 40
        ld a,b
        jr c,.vis
        or (hl)                     ; no se ve: atrasada
        ld (hl),a
        jr .next
.vis:   and (hl)                    ; (si estaba atrasada, entera)
        ld c,a
        ld a,b
        cpl
        and (hl)
        ld (hl),a
        pop af
        push af
        inc c
        dec c
        jr nz,.all
        call RECOMPOSER             ; solo las filas de sus objetos
        ld hl,(RCY0)
        jr .ds
.all:   call RECOMPOSE
        ld hl,$FF00
.ds:    ld (DSY0),hl                ; (DSY1 detras)
        pop af
        push af
        call DSFLUSH
.next:  pop af
        inc a
        jr .lp

; Sin tiras apuntadas (al cargar una habitacion; en la capa OVU)
CLEARDIRTY:
        ld hl,U_CLEARDIRTY
        jp OVUCALL

; A = indice del primer objeto de la habitacion con numero HL, o $FF
; (tambien $FF si no hay habitacion)
OBJINDEX:
        ld (OIN),hl
        ld a,(CURROOM)
        or a
        jr z,.none
        ld a,(NOBJ)
        or a
        jr z,.none
        ld de,-NOBJMAX              ; (de 0 a NOBJMAX - 1: en la tabla ZOBID)
        add hl,de
        jr c,.lin
        ld hl,(OIN)
        ld de,$6000+ZOBID
        add hl,de
        call ZON
        ld e,(hl)
        call ZUNMAP
        ld a,e
        ret
.lin:   ld hl,(OIN)
        push bc
        ld b,a
        ld c,0
        ld hl,(OBJT)                ; (de 24 en 24)
        ld de,(OIN)
.lp:    ld a,(hl)
        cp e
        jr nz,.nx
        inc hl
        ld a,(hl)
        dec hl
        cp d
        jr z,.got
.nx:    add hl,24
        inc c
        djnz .lp
        pop bc
.none:  ld a,$FF
        ret
.got:   ld a,c
        pop bc
        ret

; El punto al que se anda para el objeto HL: carry, HL = x, DE = y
OBJWALK:
        call OBJINDEX
        cp $FF
        jr z,.no
        call OBJPTR
        ld de,O_WX
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        scf
        ret
.no:    or a
        ret

; BC bytes de FARP a DE (FARP y DE avanzan): con LDIR si no cambia de pagina, si no
; con FARGET (OVT: las imagenes de los verbos; aqui por sitio)
FARCPY: ld a,b
        or c
        ret z
        ld (FCN),bc
        ld hl,FARP
        call FARMAP
        ld bc,(FCN)
        push hl
        add hl,bc
        pop hl
        jr c,.slow
        ldir
        ld hl,(FARP)
        ld bc,(FCN)
        add hl,bc
        ld (FARP),hl
        ret nc
        ld hl,FARP+2
        inc (hl)
        ret
.slow:  call FARGET
        ld (de),a
        inc de
        dec bc
        ld a,b
        or c
        jr nz,.slow
        ret
FCN:    dw 0

; (COMPOSE, aqui por sitio)
; KEEPT[i] = 1 si la fila o columna i se queda con la escala CSC
MKKEEP:
        ld a,(KEEPV)                ; (la misma escala que la ultima vez: ya esta)
        or a
        jr z,.new
        ld a,(KEEPC)
        ld hl,CSC
        cp (hl)
        ret z
.new:   ld a,1
        ld (KEEPV),a
        ld a,(CSC)
        ld (KEEPC),a
        ld hl,KEEPT
        cp 255
        jr nz,.sc
        ld (hl),1                   ; sin escala: todas
        ld de,KEEPT+1
        ld bc,255
        ldir
        ret
.sc:    ld (hl),1
        inc hl
        ld c,a                      ; acumulador en DE
        ld de,0
        ld b,255
.lp:    ld a,d                      ; parte alta antes
        push af
        ld a,e
        add a,c
        ld e,a
        jr nc,.nc
        inc d
.nc:    pop af
        cp d
        ld a,0
        jr z,.st
        inc a
.st:    ld (hl),a
        inc hl
        djnz .lp
        ret

; A = objeto con imagen mas arriba en (OAX, OAY) de la habitacion, o $FF
OBJAT:
        xor a
.lp:    ld hl,NOBJ
        cp (hl)
        jr nc,.none
        ld (SSJ),a
        call OBJPTR
        push hl
        pop iy
        ld a,(iy+O_NIMG)            ; alguna imagen de verdad?
        or a
        jr z,.next
        ld b,a
        ld e,(iy+O_IMGT)
        ld d,(iy+O_IMGT+1)
        ld hl,META
        add hl,de
.im:    ld a,(hl)
        cp $FF
        jr nz,.has
        inc hl
        inc hl
        inc hl
        djnz .im
        jr .next
.has:   ld a,(iy+O_X)               ; 8x <= OAX < 8(x + ancho)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ex de,hl
        ld hl,(OAX)
        call CPS16
        jr c,.next
        ld a,(iy+O_X)
        add a,(iy+O_W)
        ld l,a
        ld a,0
        adc a,0
        ld h,a
        add hl,hl
        add hl,hl
        add hl,hl
        ex de,hl
        ld hl,(OAX)
        call CPS16
        jr nc,.next
        ld e,(iy+O_Y)               ; y <= OAY < y + alto
        ld d,0
        ld hl,(OAY)
        call CPS16
        jr c,.next
        ld a,(iy+O_Y)
        add a,(iy+O_H)
        ld e,a
        ld a,0
        adc a,0
        ld d,a
        ld hl,(OAY)
        call CPS16
        jr nc,.next
        ld a,(SSJ)
        ret
.next:  ld a,(SSJ)
        inc a
        jp .lp
.none:  ld a,$FF
        ret

; ---------------------------------------------------------------------------
RCS:    db 0
RCK:    db 0
RCJ:    db 0
RCSRC:  dw 0
RCDST:  dw 0
RCREC:  dw 0
RCPM:   db 0
RCY:    db 0
RCH:    db 0
RCC:    db 0
RCBIT:  db 0
RCSP:   dw 0
RCOPA:  dw 0
SSK:    db 0
SSJ:    db 0
SSMIN:  db 0
SSMAX:  db 0
OAX:    dw 0
OAY:    dw 0
OIN:    dw 0
