; ===========================================================================
;  Camara (model.Camera): en el banco 0, desde $3E00
; ===========================================================================


; camera.moved(): acota cur y calcula la tira de la izquierda
CAMMOVED:
        ld hl,(CAM_CUR)
        ld de,160            ; (moved acota con el ancho de pantalla)
        call CPS16
        jr nc,.n1
        ld (CAM_CUR),de
        jr .ss
.n1:    push hl                     ; (con el ancho de la habitacion, no con CAM_MAX)
        ld hl,(RW)
        ld de,-160
        add hl,de
        pop de
        call CPS16                  ; ancho - 160 < cur ?
        jr nc,.ss
        ld (CAM_CUR),hl
.ss:    ld hl,(CAM_CUR)
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ld de,20
        or a
        sbc hl,de
        bit 7,h
        jr z,.pos
        ld hl,0
.pos:   ld a,l
        ld (CAM_SS),a
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld (LEFT),hl
        ret

; Al entrar: la camara salta a x = HL
CAMSETAT:
        ld (CAM_CUR),hl
        ld (CAM_DEST),hl
        ld de,(CAM_MIN)
        call CPS16
        jr nc,.n1
        ld (CAM_CUR),de
.n1:    ld hl,(CAM_CUR)
        ld de,(CAM_MAX)
        ex de,hl
        call CPS16
        jr nc,.n2
        ld (CAM_CUR),hl
.n2:    xor a
        ld (CAM_MTA),a
        jp CAMMOVED

; moveCamera siguiendo al actor (IX)
CAMMOVE:
        ld hl,(CAM_CUR)
        ld a,l
        and $F8
        ld l,a
        ld (CAM_CUR),hl
        ld de,(CAM_MIN)
        call CPS16
        jr nc,.n1
        ld de,8
        add hl,de
        ld (CAM_CUR),hl
        jp .moved
.n1:    ld de,(CAM_MAX)
        ex de,hl
        call CPS16                  ; max < cur ?
        jr nc,.n2
        ex de,hl
        ld de,8
        or a
        sbc hl,de
        ld (CAM_CUR),hl
        jp .moved
.n2:    ld a,(CAM_MODE)             ; solo siguiendo al actor
        cp CAM_FOLLOW
        jr nz,.nomta
        ld hl,(CFX)                 ; t = (x >> 3) - tira izquierda
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ld a,(CAM_SS)
        ld e,a
        ld d,0
        or a
        sbc hl,de
        ld de,10
        call CPS16
        jr c,.mta
        ld de,31
        call CPS16
        jr c,.nomta
.mta:   ld a,1
        ld (CAM_MTA),a
.nomta: ld a,(CAM_MTA)
        or a
        jr z,.dest
        ld hl,(CFX)
        ld (CAM_DEST),hl
.dest:  ld hl,(CAM_DEST)
        ld de,(CAM_MIN)
        call CPS16
        jr nc,.d1
        ld (CAM_DEST),de
.d1:    ld hl,(CAM_DEST)
        ld de,(CAM_MAX)
        ex de,hl
        call CPS16
        jr nc,.d2
        ld (CAM_DEST),hl
.d2:    ld hl,(CAM_CUR)             ; cur < dest: +8; cur > dest: -8
        ld de,(CAM_DEST)
        call CPS16
        jr nc,.c1
        ld de,8
        add hl,de
        ld (CAM_CUR),hl
.c1:    ld hl,(CAM_CUR)
        ld de,(CAM_DEST)
        ex de,hl
        call CPS16
        jr nc,.c2
        ex de,hl
        ld de,8
        or a
        sbc hl,de
        ld (CAM_CUR),hl
.c2:    ld a,(CAM_MTA)              ; ya ha llegado al actor?
        or a
        jr z,.moved
        ld hl,(CAM_CUR)
        call SHR3
        push hl
        ld hl,(CFX)
        call SHR3
        pop de
        or a
        sbc hl,de
        jr nz,.moved
        xor a
        ld (CAM_MTA),a
.moved: call CAMMOVED
        ; la tira que entra, para la interrupcion (L2SS: la vista pintada en Layer 2)
        ld a,(CAM_SS)
        ld b,a
        ld a,(L2SS)
        cp b
        jr z,.scr
        ld c,a
        ld a,b
        ld (L2SS),a
        ld a,c
        inc a
        cp b
        jr z,.right
        ld a,b
        inc a
        cp c
        jr z,.left
        call FULLDRAW               ; un salto (setCameraAt): toda la vista (con las
        ld a,$FF                    ; interrupciones como esten, como FLUSHOBJ)
        ld (PSTRIP),a
        jr .scr
.left:  ld a,b                      ; a la izquierda: entra la tira nueva
        jr .pend
.right: ld a,b                      ; a la derecha: entra la ultima
        add a,39
        ld hl,RNS
        cp (hl)
        jr nc,.scr
.pend:  call FRESH                  ; (sus pixeles, si estaban atrasados)
        ld (PSTRIP),a
.scr:   ld a,(CAM_SS)
        call MOD40
        add a,a
        add a,a
        ld l,a
        ld h,0
        add hl,hl                   ; (tira mod 40) * 8
        ld (SCRL),hl
        ret

; La tira A, a Layer 2 (FULLDRAW): antes, sus pixeles si estaban atrasados
DRAWFRESH:
        call FRESH
        jp DRAWSTRIP

; Si los pixeles de la tira A estan atrasados (cambio fuera de la vista: STALE), la
; rehace entera. No cambia A ni las paginas de $C000 y $E000.
FRESH:
        push af
        call DIRTYADDR
        add hl,STALE-DIRTY
        ld b,a
        and (hl)
        jr z,.ok
        ld a,b
        xor (hl)
        ld (hl),a
        ld a,(SHMMU7)
        ld b,a
        ld a,(SHMMU6)
        ld c,a
        pop af
        push af
        push bc
        call RECOMPOSE
        pop bc
        ld a,c
        ld (SHMMU6),a
        nextreg $56,a
        ld a,b
        call MAP7
.ok:    pop af
        ret

; (RECOMPOSE) La pagina ZSCR_PAGE por $6000 en vez de la de los sprites (AUM3
; primero: las interrupciones del CTC la dejan alli), HL = los planos de la tira de
; trabajo, DE = $6000, BC = lo que ocupan; Z si no hay
ZMAP:
        ld a,ZSCR_PAGE
        ld (AUM3),a
        nextreg $53,a
        call ZPART
        push hl
        ld hl,(RCDST)
        add hl,bc
        pop bc
        ld de,$6000
        ld a,b
        or c
        ret

; HL = byte de DIRTY de la tira A, A = su bit (aqui: en el banco 0 de antes de $3D00 no
; cabe)
DIRTYADDR:
        ld c,a
        and 7
        ld hl,BITMASKS
        add hl,a
        ld b,(hl)
        ld a,c
        rrca
        rrca
        rrca
        and 31
        ld hl,DIRTY
        add hl,a
        ld a,b
        ret
