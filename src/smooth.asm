; ===========================================================================
;  Desplazamiento suave (pagina SM_PAGE en $E000, desde la interrupcion de linea;
;  solo en modo normal). El paso mueve la camara de 8 en 8 pixeles y los actores lo
;  que anden; aqui, en cada imagen, el scroll de Layer 2 y los sprites van del sitio
;  del paso anterior al de este durante las TICKV imagenes que dura el paso (la
;  vista va un paso por detras). Si la camara salta, nada que repartir.
;  Con el anillo de 320 de Layer 2, a medio camino la tira que sale (por un lado) y
;  la que entra (por el otro) comparten columna: la columna tiene la que sale hasta
;  la mitad del camino y la que entra desde ahi (SMDEF), asi que lo que no toca nunca
;  pasa de 4 pixeles, y en las habitaciones anchas el copper tapa 4 columnas a cada
;  lado de la habitacion (Layer 2 y sprites).
;  Solo se ve: la maquina virtual y lo que comparan las pruebas no cambian.
; ===========================================================================

; Al subir un paso (UPLOAD): lo que se ha movido la vista, la tira nueva, y lo de
; este paso (sprites, lo que se ha movido cada actor) para las imagenes siguientes
SM_UPLOAD:
        ld hl,(SCRL)
        ld de,(SMSCR)
        ld (SMSCR),hl
        or a
        sbc hl,de                   ; +-8 (o 312 dando la vuelta): suave
        ld bc,8
        call .eq
        jr z,.r
        ld bc,-312
        call .eq
        jr z,.r
        ld bc,-8
        call .eq
        jr z,.l
        ld bc,312
        call .eq
        jr z,.l
        ld a,h
        or l
        ld a,0
        jr z,.dc                    ; quieta
        ld a,$80                    ; de golpe
        jr .dc
.r:     ld a,8
        jr .dc
.l:     ld a,-8
.dc:    ld (SMDC),a
        cp $80                      ; la tira nueva
        jr nz,.nj
        ld a,$FF                    ; de golpe: la que esperaba ya no vale (esta todo
        ld (SMDEF),a                ; pintado)
        jr .ps
.nj:    call .def                   ; (la del paso anterior, si aun no habia llegado
        ld a,(SMDC)                 ; a la mitad)
        or a
        jr z,.ps
        ld a,(PSTRIP)               ; +-8: a mitad de camino (SM_FRAME)
        ld (SMDEF),a
        jr .st
.ps:    ld a,(PSTRIP)
        cp $FF
        call nz,SMDRAW
.st:    ld a,$FF
        ld (PSTRIP),a
        ld hl,ATTRBUF               ; los sprites del paso (ATTRBUF se rehace en el
        ld de,SMATTR                ; siguiente mientras se ven estos)
        ld bc,NSPR_ACTOR*5
        ldir
        ld a,(SMDC)
        cp $80
        jr z,.zero
        ld hl,SMPDX
        ld de,SMDX
        ld bc,2*NSPR_ACTOR
        ldir
        jr .tk
.zero:  xor a
        ld (SMDC),a
        ld hl,SMDX
        ld (hl),a
        ld de,SMDX+1
        ld bc,2*NSPR_ACTOR-1
        ldir
.tk:    ld a,(STEPF0)               ; el medidor: lo que tardan 10 pasos (decimas de
        ld b,a                      ; imagen por paso)
        ld a,(FRAMES)
        sub b
        ld hl,SMMSUM
        add a,(hl)
        jr nc,.m1
        ld a,255
.m1:    ld (hl),a
        ld hl,SMMCNT
        inc (hl)
        ld a,(hl)
        cp 10
        jr c,.m2
        ld (hl),0
        ld a,(SMMSUM)
        cp 100
        jr c,.m3
        ld a,99
.m3:    ld (SMMVAL),a
        xor a
        ld (SMMSUM),a
        ld a,(METERON)
        or a
        call nz,SMMDRAW
.m2:    ld a,(SPRK)                 ; los sprites que se usan: de 64 - SPRK a 63
        ld b,a
        ld a,NSPR_ACTOR
        sub b
        ld (SMS0),a
        ld a,(FRAMES)               ; lo que dura el reparto: lo que ha tardado este
        ld hl,SMLAST                ; paso (si va con retraso, que no se pare a
        ld b,(hl)                   ; esperar), entre TICK y 2 * TICK, y en media con
        ld (hl),a                   ; el anterior
        sub b
        ld c,a
        ld a,(SMPTICK)
        ld b,a
        ld a,c
        cp b
        jr nc,.t1
        ld a,b
.t1:    ld c,a
        ld a,b
        add a,a
        cp 16
        jr c,.t2
        ld a,15
.t2:    cp c
        jr nc,.t3
        ld c,a
.t3:    ld a,(SMTICK)
        add a,c
        inc a
        srl a
        ld (SMTICK),a
        ld a,(SMPBAND)
        ld (SMBAND),a
        xor a
        ld (SMJ),a
        jp SPRUPLOAD
.eq:    push hl
        or a
        sbc hl,bc
        pop hl
        ret
.def:   ld a,(SMDEF)
        cp $FF
        ret z
        push af
        ld a,$FF
        ld (SMDEF),a
        pop af
; DRAWSTRIP desde la interrupcion: la tabla de las tiras esta en META, por $4000,
; donde el programa puede tener otra pagina (Layer 2, esxDOS...); la interrupcion
; deja despues las ventanas como estaban. Lo que DSCORE guarda en memoria (filas,
; desde donde, y sus constantes en el codigo) tambien se repone: la interrupcion puede
; llegar con el programa dentro de DSCORE (FLUSHOBJ rehace tiras mientras la vista se
; desliza), y seguiria con lo de esta tira
SMDRAW: nextreg $52,META_PAGE
        ld e,a                      ; (E = la tira)
        ld hl,(DSN)
        push hl
        ld hl,(DSA0)                ; (DSA0 y DSC0)
        push hl
        ld a,(DSCLR)
        ld h,a
        ld a,(DSCORE.e0+1)
        ld l,a
        push hl
        ld a,(DSCORE.e1+1)
        ld d,a
        push de
        ld a,e
        call DRAWSTRIP
        pop de
        ld a,d
        ld (DSCORE.e1+1),a
        pop hl
        ld a,l
        ld (DSCORE.e0+1),a
        ld a,h
        ld (DSCLR),a
        pop hl
        ld (DSA0),hl
        pop hl
        ld (DSN),hl
        ret

; Cada imagen, hasta el final del paso: el scroll y los sprites de esta imagen
SM_FRAME:
        call SMMETER
        ld a,(SMJ)
        ld hl,SMTICK
        cp (hl)
        jr z,.go
        ret nc                      ; (ya en su sitio: nada)
.go:    ld b,a                      ; peso de esta imagen: (TICK - J) / TICK
        inc a
        ld (SMJ),a
        ld a,(hl)
        sub b
        ld hl,0
        jr z,.w                     ; la ultima: 0
        ld c,a
        ld a,b
        or a
        ld hl,256
        jr z,.w                     ; la primera: todo (el sitio del paso anterior)
        ld a,(SMTICK)
        ld hl,SMRCP
        add hl,a
        ld d,(hl)
        ld e,c
        mul d,e
        ex de,hl
.w:     ld (SMW),hl
        ld a,(SMDC)                 ; el scroll: el final menos lo que falta
        call SMOFF
        push af
        bit 7,a                     ; a mitad de camino (falta 4 o menos): la tira
        jr z,.ab                    ; que entra, en la columna que comparte
        neg
.ab:    cp 5
        call c,SM_UPLOAD.def
        pop af
        call SMSEXT
        ld a,(SMDC)                 ; la franja, en todo el paso si la vista se mueve (con
        or a                        ; la vista quieta no hace falta y taparia letras); en
        jr z,.nb                    ; las imagenes en que la vista ya esta en su sitio
        ld a,(SMBAND)               ; tambien, o parpadearia
.nb:    ld (SMBNOW),a
        ld hl,(SMSCR)
        or a
        sbc hl,de
        ld de,320
        bit 7,h
        jr z,.p1
        add hl,de
        jr .p2
.p1:    or a
        sbc hl,de
        jr nc,.p2
        add hl,de
.p2:    di                          ; (el copper va por los puertos $243B / $253B)
        call SMCOPPER
        ei
        ld a,(HIDDEN)               ; (en una transicion los actores no se ven)
        or a
        ret nz
        ld a,(SMS0)                 ; los sprites que usan los actores (desde SMS0)
        cp NSPR_ACTOR
        ret nc                      ; (ninguno)
        ld bc,$303B
        out (c),a
        ld (SMS),a
        ld e,a
        ld d,5
        mul d,e
        ld hl,SMATTR
        add hl,de
.sp:    ld de,SMX
        ld bc,5
        ldir
        push hl
        ld a,(SMA3)
        bit 7,a
        jr z,.out                   ; (no se ve)
        ld a,(SMS)                  ; x + peso * (camara - lo que ha andado)
        ld hl,SMDX
        add hl,a
        ld a,(SMDC)
        sub (hl)
        call SMOFF
        call SMSEXT
        ld hl,SMX
        ld a,(SMA2)
        call .add9
        ld (SMA2),a
        ld a,(SMS)                  ; y - peso * lo que ha andado
        ld hl,SMDY
        add hl,a
        xor a
        sub (hl)
        call SMOFF
        call SMSEXT
        ld hl,SMY
        ld a,(SMA4)
        call .add9
        ld (SMA4),a
.out:   ld hl,SMX
        ld bc,$0557
        otir
        pop hl
        ld a,(SMS)
        inc a
        ld (SMS),a
        cp NSPR_ACTOR
        jr nz,.sp
        ret
; (HL) = 8 bits bajos, bit 0 de A el noveno; + DE: devuelve A con el noveno nuevo
.add9:  push af
        and 1
        ld b,a
        ld c,(hl)
        ex de,hl
        add hl,bc
        ex de,hl
        ld (hl),e
        pop af
        and $FE
        ld b,a
        ld a,d
        and 1
        or b
        ret

; A (con signo) por el peso SMW (0..256), redondeado
SMOFF:  ld c,a
        ld a,(SMW+1)
        or a
        ld a,c
        ret nz                      ; 256: todo
        or a
        ret z
        jp p,.mul
        neg
        call .mul
        neg
        ret
.mul:   ld d,a
        ld a,(SMW)
        ld e,a
        mul d,e
        ld a,e
        add a,128
        ld a,d
        adc a,0
        ret

; DE = A con signo
SMSEXT:   ld e,a
        ld d,0
        bit 7,a
        ret z
        dec d
        ret

; El copper con el scroll HL: como COPPERSET, y en las habitaciones anchas, mientras la
; vista se mueve (SMBNOW), una franja de 4 columnas a cada lado (recorte de Layer 2 y
; de los sprites) hasta la pantalla de verbos
SMCOPPER:
        push hl
        nextreg $62,0
        nextreg $61,0
        ld bc,$243B
        ld a,$60
        out (c),a
        inc b
        ld de,2*256+157             ; (x en pares de pixeles: 4..315)
        ld a,(SMBNOW)
        or a
        call nz,.clip
        pop hl
        ld a,$16                    ; MOVE $16, scroll
        out (c),a
        out (c),l
        ld a,$71                    ; MOVE $71, bit 8 del scroll
        out (c),a
        ld a,h
        and 1
        out (c),a
        ld a,(MAINH)                ; WAIT linea ROOM_Y0 + MAINH - 32 (y el temblor)
        add a,ROOM_Y0-32
        ld e,a
        ld a,(SHAKEY)
        add a,e
        ld e,a
        ld a,$80
        out (c),a
        out (c),e
        ld a,$16                    ; los verbos, sin scroll
        out (c),a
        xor a
        out (c),a
        ld a,$71
        out (c),a
        xor a
        out (c),a
        ld de,0*256+159
        ld a,(SMBNOW)
        or a
        call nz,.clip
        ld a,$FF                    ; HALT
        out (c),a
        out (c),a
        nextreg $62,%11000000
        ld a,(SHAKEY)
        neg
        nextreg $17,a
        ret
.clip:  ld a,$1C                    ; MOVE $1C,3: los indices de los recortes de
        out (c),a                   ; Layer 2 y de los sprites
        ld a,3
        out (c),a
        ld a,$18                    ; Layer 2: D..E, 0..255
        call .cl4
        ld a,$19                    ; sprites: lo mismo
.cl4:   out (c),a
        out (c),d
        out (c),a
        out (c),e
        out (c),a
        ld l,0
        out (c),l
        out (c),a
        ld l,255
        out (c),l
        ret

; El medidor (sprite METER_SPR, arriba a la izquierda, encima de la habitacion), o
; escondido
SMMETER:
        ld bc,$303B
        ld a,METER_SPR
        out (c),a
        ld bc,$57
        ld a,(METERON)
        or a
        jr z,.hide
        ld a,8
        out (c),a
        out (c),a
        ld a,CURSOR_BANK<<4
        out (c),a
        ld a,$C0|(METER_PAT>>1)
        out (c),a
        ld a,$80|((METER_PAT&1)<<6)
        out (c),a
        ret
.hide:  xor a
        out (c),a
        out (c),a
        out (c),a
        ld a,$40
        out (c),a
        xor a
        out (c),a
        ret

; SMMVAL (0..99) en dos cifras amarillas sobre negro, al patron METER_PAT
SMMDRAW:
        ld hl,SMPAT
        ld b,128
.z:     ld (hl),0
        inc hl
        djnz .z
        ld c,3                      ; el fondo: filas 3..12, columnas 1..14, color 1
.fr:    ld b,1
.fc:    ld a,1
        call .px
        inc b
        ld a,b
        cp 15
        jr nz,.fc
        inc c
        ld a,c
        cp 13
        jr nz,.fr
        ld a,(SMMVAL)               ; decenas y unidades
        ld b,0
.d10:   cp 10
        jr c,.u
        sub 10
        inc b
        jr .d10
.u:     push af
        ld a,b
        ld b,2
        call .dig
        pop af
        ld b,8
        call .dig
        ld bc,$303B                 ; al patron (4 bits: la mitad baja del hueco)
        ld a,METER_PAT>>1
        out (c),a
        ld hl,SMPAT
        ld bc,$805B
        otir
        ret
; la cifra A en la columna B, filas 4..10 (5 x 7)
.dig:   ld e,a
        ld d,7
        mul d,e
        ld hl,SMFONT
        add hl,de
        ld c,4
.dr:    ld a,(hl)
        push hl
        ld l,a
        ld h,b
        ld e,5
.dc:    sla l
        sla l
        sla l
        jr .dk
.dk:    ld a,l
        and $80
        jr z,.d0
        ld a,3
        call .px
.d0:    sla l
        inc b
        dec e
        jr nz,.dk
        ld b,h
        pop hl
        inc hl
        inc c
        ld a,c
        cp 11
        jr nz,.dr
        ret
; el pixel (B, C) de SMPAT con el color A (4 bits: el de la izquierda, arriba)
.px:    push hl
        push de
        ld d,a
        ld a,c
        add a,a
        add a,a
        add a,a                     ; fila * 8
        ld e,a
        ld a,b
        srl a
        add a,e
        ld hl,SMPAT
        add hl,a
        ld a,b
        and 1
        ld a,d
        jr nz,.lo
        add a,a
        add a,a
        add a,a
        add a,a
        ld e,a
        ld a,(hl)
        and $0F
        or e
        jr .st
.lo:    ld e,a
        ld a,(hl)
        and $F0
        or e
.st:    ld (hl),a
        pop de
        pop hl
        ret

; las cifras, 5 x 7 (los 5 bits bajos)
SMFONT: db %01110,%10001,%10011,%10101,%11001,%10001,%01110
        db %00100,%01100,%00100,%00100,%00100,%00100,%01110
        db %01110,%10001,%00001,%00010,%00100,%01000,%11111
        db %11111,%00010,%00100,%00010,%00001,%10001,%01110
        db %00010,%00110,%01010,%10010,%11111,%00010,%00010
        db %11111,%10000,%11110,%00001,%00001,%10001,%01110
        db %00110,%01000,%10000,%11110,%10001,%10001,%01110
        db %11111,%00001,%00010,%00100,%01000,%01000,%01000
        db %01110,%10001,%10001,%01110,%10001,%10001,%01110
        db %01110,%10001,%10001,%01111,%00001,%00010,%01100

; 256 / t, redondeado (t = 2..15: (t - 1) * esto < 256)
SMRCP:  db 0, 0, 128, 85, 64, 51, 43, 37, 32, 28, 26, 23, 21, 20, 18, 17

; --- lo que deja cada paso (K_CASTDRAW y KSMOOTH, capa OVK) ---
SMPDX:  ds NSPR_ACTOR               ; por sprite: lo que ha andado su actor (x, y)
SMPDY:  ds NSPR_ACTOR
SMPTICK: db 5                       ; imagenes que dura el paso
SMPBAND: db 0                       ; habitacion ancha (la franja)
; --- el paso que se esta viendo ---
SMDX:   ds NSPR_ACTOR
SMDY:   ds NSPR_ACTOR
SMATTR: ds NSPR_ACTOR*5
SMTICK: db 5
SMBAND: db 0
SMBNOW: db 0                        ; (SM_FRAME) la franja en esta imagen
SMDC:   db 0                        ; lo que se ha movido la camara: -8, 0 u 8
SMDEF:  db $FF                      ; la tira que entra por la izquierda, por pintar
SMW:    dw 0                        ; peso de esta imagen (0..256)
SMS:    db 0
SMS0:   db 0                        ; el primer sprite usado
SMMSUM: db 0                        ; el medidor: imagenes de los pasos de esta decena
SMMCNT: db 0
SMMVAL: db 0
SMPAT:  ds 128                      ; su patron
SMLAST: db 0                        ; FRAMES en la subida anterior
SMX:    db 0                        ; los 5 bytes del sprite que se esta escribiendo
SMY:    db 0
SMA2:   db 0
SMA3:   db 0
SMA4:   db 0
; (interrupcion de linea, cada imagen) La musica del anillo (MUPG, MUPTR) a MUBUF
; (los 255 desde MUBUF+1), hasta el byte antes del que va a sonar (MURD); con el
; anillo vacio, el CTC 1 parado (MUSPOLL lo pone en marcha otra vez). Usa MMU6 (la
; interrupcion la deja como estaba).
MUFILL: ld a,(MUPLAY)
        or a
        ret z
.ch:    ld a,(MURD+1)               ; lo que cabe: (rd - wb) mod 255, menos 1
        ld hl,MUWB
        sub (hl)
        jr z,.w0                    ; (vacio)
        jr nc,.w1
        dec a
.w1:    dec a
        ret z
        jr .w2
.w0:    ld a,254
.w2:    ld c,a
        ld a,(hl)                   ; y hasta el final de MUBUF
        neg
        jr z,.c1
        cp c
        jr nc,.c1
        ld c,a
.c1:    ld a,(MUAV)
        or a
        jr z,.empty
        ld hl,(MUPTR)               ; y lo que queda de la pagina ($8000 - MUPTR)
        ld a,h
        cp $7F
        jr nz,.c2
        ld a,l
        neg
        jr z,.c2
        cp c
        jr nc,.c2
        ld c,a
.c2:    ld a,(MUPG)                 ; la pagina, por $C000
        nextreg $56,a
        ld de,$6000
        add hl,de
        ld a,(MUWB)
        ld e,a
        ld d,MUBUF>>8
        ld b,0
        push bc
        ldir
        pop bc
        ld a,(MUWB)
        add a,c
        jr nz,.w3
        inc a                       ; (despues del 255, el 1)
.w3:    ld (MUWB),a
        ld hl,(MUPTR)
        add hl,bc
        bit 7,h
        jr z,.c3
        ld h,$60                    ; se acabo la pagina: una menos en el anillo
        ld a,(MUPG)
        inc a
        cp MUS_PAGE+MUS_N
        jr c,.c4
        ld a,MUS_PAGE
.c4:    ld (MUPG),a
        ld a,(MUAV)
        dec a
        ld (MUAV),a
.c3:    ld (MUPTR),hl
        jr .ch
.empty: ld bc,$193B                 ; vacio: el CTC 1 parado hasta que haya mas
        ld a,%00000011
        out (c),a
        xor a
        ld (MUPLAY),a
        ret

SM_END:
        ASSERT SM_END <= $10000, la capa SM no cabe
