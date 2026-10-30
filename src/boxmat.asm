; ===========================================================================
;  createBoxMatrix (capa OVF; matrixOps 4, boxes.cpp de ScummVM; model.box_matrix):
;  la matriz de cajas otra vez, con los flags de ahora. Dos cajas son vecinas si la
;  tabla de la habitacion lo dice (META+589: un bit por pareja i < j, de la
;  geometria, hecha al convertir) y ninguna es invisible ($80). El camino mas
;  corto de cada una a cada otra, por Kleene, en la pagina BXM_PAGE por $E000: la
;  distancia en $E000 + 64 i + j y por donde se va en $F000 + 64 i + j. Despues,
;  comprimida como BOXM al principio de la misma pagina y, si cabe en su hueco
;  (META+22, y como mucho BXMAX), a MATRIX; si no, se queda la que habia. Sin
;  tabla, o con mas de 64 cajas, nada. Usa MMU7 (VMFETCH pone otra vez la del
;  script).
; ===========================================================================
BXM_PAGE    EQU HDRPAGE         ; (la de leer las cabeceras de las partidas: solo
                                ; la usa el menu)
BXMAX       EQU $0F00           ; (y una fila mas, 193 bytes, no llega a $F000)

F_BOXMATRIX:
        ld hl,(META+589)
        ld a,h
        or l
        ret z
        ld a,(NBOXES)
        or a
        ret z
        cp 65
        ret nc
        ld (BXN),a
        ld de,META
        add hl,de
        ld (BXBIT),hl
        ld hl,(META+22)             ; hasta donde puede llegar la comprimida
        ld de,BXMAX
        or a
        sbc hl,de
        add hl,de
        jr c,.cap
        ex de,hl
.cap:   ld de,$E000
        add hl,de
        ld (BXEND),hl
        ld a,BXM_PAGE
        call MAP7
        ld hl,$E000                 ; todo sin camino (255)
        ld de,$E001
        ld bc,$1FFF
        ld (hl),$FF
        ldir
        ld a,(BXN)                  ; cada una, a 0 de si misma y por ella
        ld b,a
        ld hl,$E000
        ld c,0
.dg:    ld (hl),0
        set 4,h
        ld (hl),c
        res 4,h
        ld a,65
        add hl,a
        inc c
        djnz .dg

        ; --- las vecinas: distancia 1, por ella misma ---
        xor a
        ld (BXI),a
        inc a
        ld (BXMSK),a
.ni:    ld a,(BXN)
        dec a
        ld b,a
        ld a,(BXI)
        cp b
        jr nc,.fw                   ; (la ultima ya no tiene parejas por delante)
        call BOXFLAGS
        ld (BXFI),a
        ld a,(BXI)
        inc a
        ld (BXJ),a
.nj:    ld hl,(BXBIT)               ; el bit de la pareja (i, j)
        ld a,(BXMSK)
        ld c,a
        and (hl)
        ld (BXV),a
        rlc c
        jr nc,.sb
        inc hl
        ld (BXBIT),hl
.sb:    ld a,c
        ld (BXMSK),a
        ld a,(BXV)
        or a
        jr z,.nx
        ld a,(BXFI)
        bit 7,a
        jr nz,.nx
        ld a,(BXJ)
        call BOXFLAGS
        bit 7,a
        jr nz,.nx
        ld a,(BXI)
        ld d,a
        ld a,(BXJ)
        ld e,a
        call BXSET
        ld a,(BXJ)
        ld d,a
        ld a,(BXI)
        ld e,a
        call BXSET
.nx:    ld a,(BXJ)
        inc a
        ld (BXJ),a
        ld hl,BXN
        cp (hl)
        jr c,.nj
        ld hl,BXI
        inc (hl)
        jr .ni

        ; --- Kleene: de i a j pasando por k, si es mas corto ---
.fw:    xor a
        ld (BXK),a
.k:     ld a,(BXK)                  ; la fila k
        ld d,a
        ld e,64
        mul d,e
        ld hl,$E000
        add hl,de
        ld (BXRK),hl
        xor a
        ld (BXI),a
.i:     ld a,(BXI)
        ld hl,BXK
        cp (hl)
        jr z,.in                    ; (i = k: nada que mejorar)
        ld d,a
        ld e,64
        mul d,e
        ld hl,$E000
        add hl,de                   ; la fila i
        push hl
        ld a,(BXK)
        add hl,a
        ld a,(hl)                   ; distancia de i a k
        cp $FF
        jr z,.ip                    ; (sin camino: no mejora nada)
        ld (.ik+1),a
        set 4,h
        ld a,(hl)                   ; por donde se va de i a k
        ld (.it+1),a
        pop de
        ld hl,(BXRK)
        ld a,(BXN)
        ld b,a
.j:     ld a,(hl)                   ; distancia de k a j
        cp $FF
        jr z,.jn
.ik:    add a,0                     ; + la de i a k
        ex de,hl
        cp (hl)
        jr nc,.je                   ; no es mas corto
        ld (hl),a
        set 4,h
.it:    ld (hl),0
        res 4,h
.je:    ex de,hl
.jn:    inc hl
        inc de
        djnz .j
        jr .in
.ip:    pop hl
.in:    ld hl,BXI
        inc (hl)
        ld a,(BXN)
        cp (hl)
        jr nz,.i
        ld hl,BXK
        inc (hl)
        cp (hl)
        jr nz,.k

        ; --- comprimida: por fila, (desde, hasta, por donde) y $FF ---
        ld de,$E000                 ; (las distancias ya no hacen falta)
        xor a
        ld (BXI),a
.ci:    ld hl,(BXEND)               ; si ya no cabe, se deja
        or a
        sbc hl,de
        ret c
        ld a,(BXI)
        push de
        ld d,a
        ld e,64
        mul d,e
        ld hl,$F000
        add hl,de
        pop de
        ld c,0                      ; j
.cj:    ld a,(hl)
        cp $FF
        jr z,.cn
        ld b,a
        ld a,c
        ld (de),a
        inc de
.cr:    ld a,(BXN)                  ; mientras la siguiente vaya por el mismo sitio
        dec a
        cp c
        jr z,.ce
        inc hl
        ld a,(hl)
        cp b
        jr nz,.cb
        inc c
        jr .cr
.cb:    dec hl
.ce:    ld a,c
        ld (de),a
        inc de
        ld a,b
        ld (de),a
        inc de
.cn:    inc hl
        inc c
        ld a,(BXN)
        cp c
        jr nz,.cj
        ld a,$FF                    ; fin de fila (sin el $FF de delante de ScummVM)
        ld (de),a
        inc de
        ld hl,BXI
        inc (hl)
        ld a,(BXN)
        cp (hl)
        jr nz,.ci
        ld hl,(BXEND)
        or a
        sbc hl,de
        ret c
        ex de,hl                    ; a su sitio
        ld de,$E000
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ex de,hl
        ld de,(MATRIX)
        ldir
        ld a,1                      ; (se guarda con la partida: al cargarla, otra vez)
        ld (META+592),a
        ret

; La pareja (D, E) vecinas: distancia 1 y se va por E
BXSET:  ld a,e
        ld e,64
        mul d,e
        add de,a
        ld hl,$E000
        add hl,de
        ld (hl),1
        set 4,h
        ld (hl),a
        ret

BXN:    db 0
BXI:    db 0
BXJ:    db 0
BXK:    db 0
BXFI:   db 0
BXV:    db 0
BXMSK:  db 0
BXBIT:  dw 0
BXRK:   dw 0
BXEND:  dw 0
