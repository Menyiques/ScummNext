; La prueba de la musica (tools/mustest.py), en su propia pagina de capa (MT_PAGE, en
; $C000): en la memoria principal no cabe. Se entra con OVCALL y no vuelve; lo que
; llama (LOADROOM, MUSPOLLC, FLUSHOBJ...) deja la capa como estaba al volver.
MUSTEST:
        nextreg $69,0               ; blanco 2 s: empieza la prueba
        nextreg $4A,$FF
        ld b,100
        call MTWAIT
        xor a
        ld (VMON),a
        ld a,200
        ld (MAINH),a
        ld a,6                      ; SND_LOOP: la pista 2, siempre
        ld (OVA),a
        ld hl,MUSSTART
        ld a,OVA_PAGE
        call OVCALLR
        IFDEF MTSFX
        ld a,7                      ; el 7 del juego de prueba (AdLib): da vueltas toda la
        ld (OVA),a                  ; prueba, debajo de los demas efectos
        ld hl,SNDPLAY
        ld a,OVA_PAGE
        call OVCALLR
        ENDIF
        ld b,8
.f:     push bc
        call MUSPOLLC
        pop bc
        djnz .f
        ld b,25
        call MTWAIT
        ld a,1
        ld (MTON),a
        ld b,12
.lp:    push bc
        nextreg $4A,$03             ; (azul mientras carga: la Layer 2 esta apagada)
        ld a,b                      ; habitaciones 1, 2, 3, 1...
.m3:    cp 3
        jr c,.r
        sub 3
        jr .m3
.r:     inc a
        ld (OVA),a                  ; (LOADROOM y FLUSHOBJ dejan otra pagina en $C000:
        ld hl,LOADROOM              ; por OVCALL, que deja la de la prueba al volver)
        ld a,MT_PAGE
        call OVCALLR
        nextreg $69,0               ; (cian despues de cada una, sin ver la habitacion)
        nextreg $4A,$1F
        ld b,50                     ; y una imagenes como el bucle principal
.id:    push bc
        call MUSPOLLC
        ld b,1
        call MTWAIT
        IFDEF MTSFX
        call MTSFXT
        ENDIF
        pop bc
        djnz .id
        pop bc
        djnz .lp
        ld b,100                    ; despues, 100 imagenes rehaciendo todas las tiras de
.fl:    push bc                     ; la habitacion (FLUSHOBJ, como un paso con muchos
        ld hl,DIRTY                 ; objetos cambiando: el bar de Monkey Island)
        ld b,16
.d:     ld (hl),$FF
        inc hl
        djnz .d
        ld a,1
        ld (DIRTYF),a
        call ZON                    ; (todas las filas)
        ld hl,$6000+ZYMNO
        ld b,128
.fz:    ld (hl),0
        set 7,l
        ld (hl),$FF
        res 7,l
        inc l
        djnz .fz
        call ZUNMAP
        IFDEF MTDI
        di                          ; (como antes: sin interrupciones)
        ENDIF
        ld hl,FLUSHOBJ
        ld a,MT_PAGE
        call OVCALL
        IFDEF MTDI
        ei
        ENDIF
        call MUSPOLLC
        ld b,1
        call MTWAIT
        IFDEF MTSFX
        call MTSFXT
        ENDIF
        pop bc
        djnz .fl
        xor a
        ld (MTON),a
        nextreg $69,0
        IFDEF MTSFX
        ld hl,(MTSN)                ; (magenta: un canal de efectos no saco ninguna
        ld a,h                      ; muestra; el efecto 4 dura 50 imagenes y se lanza
        or l                        ; otro cada 16: tienen que sonar los dos)
        ld a,$C3
        jr z,.c
        ld hl,(MTSN2)
        ld a,h
        or l
        ld a,$C3
        jr z,.c
        ld a,(AUSND)                ; (y magenta si el 7 ya no suena: no ha dado vueltas)
        ld hl,(AULEN)
        cp 7
        jr z,.lc
        ld a,(AUSND2)
        ld hl,(AULEN2)
        cp 7
        ld a,$C3
        jr nz,.c
.lc:    ld a,h
        or l
        ld a,$C3
        jr z,.c
        ENDIF
        ld a,(MUPLAY)
        or a
        ld a,$FC                    ; amarillo: se acabo el anillo
        jr z,.c
        ld hl,(MTSTALL)
        ld a,h
        or l
        ld a,$1C                    ; verde
        jr z,.c
        ld a,$E0                    ; rojo
.c:     nextreg $4A,a
.end:   jr .end

        IFDEF MTSFX
; (con -DMTSFX, despues de cada imagen) un efecto cada 16 imagenes, el 3 o el 4 del
; juego de prueba: el CTC 0 sonando casi siempre, tambien mientras se lee la SD
MTSFXT: ld a,(FRAMES)
        ld c,a
        and 15
        ret nz
        ld a,c
        and 16
        ld a,3
        jr z,.p
        inc a
.p:
        IFDEF MTSFX4
        ld a,4                      ; (solo el 4: constante del CTC distinta de 0)
        ENDIF
        ld (OVA),a
        IFDEF MTMARK
        nextreg $4A,$C3             ; (marca: lanzando el efecto)
        ENDIF
        ld hl,SNDPLAY
        ld a,OVA_PAGE
        call OVCALLR
        IFDEF MTMARK
        nextreg $4A,$1F             ; (marca: lanzado: cian otra vez)
        ENDIF
        ret
        ENDIF

; B imagenes (FRAMES)
MTWAIT:
        ld a,(FRAMES)
.w:     ld hl,FRAMES
        IFDEF MTMARK
        ld c,a                      ; (marca: esperando una imagen, colores que cambian;
        ld a,i                      ; rojo fijo si las interrupciones estan quitadas)
        ld a,$E0
        jp po,.mk
        ld a,r
        and $1C
        or $04
.mk:    nextreg $4A,a
        ld a,c
        ENDIF
        cp (hl)
        jr z,.w
        djnz MTWAIT
        ret

