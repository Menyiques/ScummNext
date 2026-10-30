; ===========================================================================
;  Las fichas de los actores 1-12 (model.Actor.pack(): A_* y R_* de actor.asm)
;
;  Estan en CAST_PAGE (CASTS, R_SIZE bytes cada una). Con la que se trabaja se
;  copia a ACTOR (ACTLOAD; IX = ACTOR siempre) y ACTN dice de que actor es;
;  vuelve a su sitio al cargar otra o con ACTSYNC (al final del paso y antes
;  de guardar). ACTRD / ACTWR leen y escriben un campo de cualquiera sin
;  cambiar de actor. Sin maquina virtual, ACTOR es el actor solo del motor
;  (ACTN = 0).
; ===========================================================================

CASTS   EQU $E000                   ; (en CAST_PAGE) los actores 1-12
        ASSERT CASTS+12*R_SIZE <= CHDR

; HL = la ficha del actor A (y MMU7 en CAST_PAGE). No cambia BC ni DE.
ACTREC:
        push de
        push af
        ld a,CAST_PAGE
        call MAP7
        pop af
        dec a
        ld e,a
        ld d,R_SIZE
        mul d,e
        ld hl,CASTS
        add hl,de
        pop de
        ret

; El actor A a ACTOR (el que habia, a su ficha); IX = ACTOR. A = 0: ninguno.
ACTLOAD:
        ld ix,ACTOR
        ld hl,ACTN
        cp (hl)
        ret z
        push af
        call ACTSYNC
        pop af
        ld (ACTN),a
        or a
        ret z
        ld b,a
        ld a,(SHMMU7)
        push af
        ld a,b
        call ACTREC
        ld de,ACTOR
        ld bc,R_SIZE
        call DMACP                  ; (por el DMA, de una vez: R_SIZE < 256)
        pop af
        jp MAP7

; ACTOR, otra vez a su ficha (si es de un actor)
ACTSYNC:
        ld a,(ACTN)
        or a
        ret z
        ld b,a
        ld a,(SHMMU7)
        push af
        ld a,b
        call ACTREC
        ex de,hl
        ld hl,ACTOR
        ld bc,R_SIZE
        call DMACP
        pop af
        jp MAP7

; HL = palabra del campo E del actor A (1-12)
ACTRD:
        ld d,0
        ld hl,ACTN
        cp (hl)
        jr nz,.rec
        ld hl,ACTOR
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
.rec:   ld b,a
        ld a,(SHMMU7)
        ld c,a
        ld a,b
        call ACTREC
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,c
        jp MAP7

; campo E del actor A (1-12) = HL
ACTWR:
        ld d,0
        ld b,a
        ld a,(ACTN)
        cp b
        jr nz,.rec
        ex de,hl                    ; DE = valor, HL = campo
        ld bc,ACTOR
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        ret
.rec:   push hl
        ld a,(SHMMU7)
        ld c,a
        ld a,b
        call ACTREC
        add hl,de
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ld a,c
        jp MAP7

; carry si 0 < A < NACT
ACTOK:
        or a
        ret z
        cp NACT
        ret

; carry si el actor A esta en la habitacion (que no es la 0). No cambia BC.
INROOM:
        call ACTOK
        ret nc
        push bc
        ld e,R_ROOM
        call ACTRD
        pop bc
        ld a,(CURROOM)
        or a
        ret z
        cp l
        scf
        ret z
        or a
        ret

; carry si el actor A es el protagonista y esta en la habitacion
EGOHERE:
        ld hl,(VARS+2*VAR_EGO)
        cp l
        jr nz,.no
        inc h
        dec h
        jr z,INROOM
.no:    or a
        ret

; HL = x, DE = y del actor HL (0, 0 si no es un actor)
ACTXY:
        ld a,h
        or a
        jr nz,.z
        ld a,l
        call ACTOK
        jr nc,.z
        push af
        ld e,A_Y
        call ACTRD
        pop af
        push hl
        ld e,A_X
        call ACTRD
        pop de
        ret
.z:     ld hl,0
        ld d,h
        ld e,l
        ret

; A = moving del actor HL (0 si no es un actor)
ACTMOVING:
        ld a,h
        or a
        jr nz,.z
        ld a,l
        call ACTOK
        jr nc,.z
        ld e,A_MOV
        call ACTRD
        ld a,l
        ret
.z:     xor a
        ret

; El costume que empieza en la pagina A (COST_PAGE o de la cache): su cabecera
COSTSEL:
        ld (CMAPB+1),a
        jp COSTHDR

ACTN:   db 0                        ; el actor que esta en ACTOR (0: ninguno)
