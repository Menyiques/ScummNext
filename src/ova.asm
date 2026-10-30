; ===========================================================================
;  Capa OVA (pagina OVA_PAGE, en $C000): el sonido (tools/sound.py, Sound)
;
;  Lo que ven los scripts esta en la pagina UIP (SNDST, se guarda con la
;  partida): la cola de este paso, la pista del CD (sonido, si su reloj corre,
;  el reloj y lo que le queda) y los efectos que siguen sonando (sonido y
;  jiffies). Todo se cuenta en jiffies, con el reloj de la maquina virtual.
;  El indice de SOUNDS.DAT esta al principio de SND_PAGE (por $E000): por
;  sonido, tipo, jiffies y como suena; las muestras de los efectos, en las
;  paginas siguientes. Los de AdLib son como efectos (sintetizados al convertir) que
;  pueden dar vueltas; para los scripts suenan lo que su pista (o hasta que se paran,
;  si dan vueltas), y si se piden otra vez, empiezan de nuevo (iMuse). El sonido de verdad: SNDPLAY pone un efecto en uno de dos
;  canales (CTC 0 y CTC 2, cada uno a su ritmo); sus interrupciones (SNDISR y SNDISR2,
;  en la memoria principal) sacan las muestras y el DAC A y D lleva la suma (AUMIX).
; ===========================================================================

SK_CD       EQU 1
SK_SBL      EQU 2
SK_ADL      EQU 3               ; AdLib (iMuse): sintetizado al convertir (si cabe)
SQ_N        EQU 0               ; cuantos hay en la cola
SQ_Q        EQU 1               ; la cola (SQ_MAX)
SQ_MAX      EQU 10
SQ_CDS      EQU SQ_Q+SQ_MAX     ; la pista del CD: sonido
SQ_CDON     EQU SQ_CDS+1        ; su reloj corre
SQ_CDT      EQU SQ_CDON+1       ; el reloj (VAR_MUSIC_TIMER)
SQ_CDL      EQU SQ_CDT+2        ; lo que le queda ($FFFF: da vueltas)
SQ_FX       EQU SQ_CDL+2        ; NSFX x (sonido, jiffies)
NSFX        EQU 8
        ASSERT SQ_FX+3*NSFX == SNDST_SZ
SNDE        EQU $E010           ; las entradas del indice (16 bytes)

; IX = SNDST (MMU7 en UIP)
SN_ST:
        ld a,UIP
        call MAP7
        ld ix,SNDST
        ret

; --- al empezar cada paso (VMTICK): los relojes y las esperas -----------------------
; El paso dura VAR_TIMER_NEXT jiffies (1/60 s), como en SCUMM: Monkey Island pone 6,
; 10 pasos por segundo; y los relojes avanzan eso (DELTAV). Fuera de 1..15 (sin
; poner), 5. En las pruebas siempre DELTA, como el modelo. TICKV: las imagenes que
; dura el paso (a 60 Hz, una por jiffy; a 50 Hz, TICK50; NR $05 bit 2).
SN_TICK:
        ld a,(TMODE)
        or a
        ld a,DELTA
        jr nz,.dt
        ld a,(VARS+2*VAR_TIMER_NEXT+1)
        or a
        jr nz,.d5
        ld a,(VARS+2*VAR_TIMER_NEXT)
        dec a
        cp 15
        jr c,.d1
.d5:    ld a,DELTA-1
.d1:    inc a
.dt:    ld (DELTAV),a
        ld e,a
        di                          ; (la interrupcion de linea tambien usa $243B)
        ld bc,$243B
        ld a,$05
        out (c),a
        inc b
        in a,(c)
        ei
        and %00000100
        ld a,e
        jr nz,.hz
        ld d,0
        ld hl,TICK50-1
        add hl,de
        ld a,(hl)
.hz:    ld (TICKV),a
        ld b,3                      ; temporizadores (11 a 13)
        ld hl,VARS+2*VAR_TMR_1
.tm:    ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld a,(DELTAV)
        add hl,a
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        inc hl
        inc hl
        djnz .tm
        ld de,(DELTAV)              ; VAR_TIMER y VAR_TIMER_TOTAL
        ld (VARS+2*VAR_TIMER),de
        ld hl,(VARS+2*VAR_TIMER_TOTAL)
        add hl,de
        ld (VARS+2*VAR_TIMER_TOTAL),hl
        ld hl,(TALKD)               ; el texto: hasta 0
        or a
        sbc hl,de
        bit 7,h
        jr z,.ts
        ld hl,0
.ts:    ld (TALKD),hl
        xor a                       ; las esperas (delay)
.dl:    push af
        call SLOTPTR
        push hl
        pop ix
        ld a,(ix+SL_ST)
        cp SS_PAUSED
        jr nz,.dn
        ld a,(ix+SL_DLY)
        ld hl,DELTAV
        sub (hl)
        ld (ix+SL_DLY),a
        ld a,(ix+SL_DLY+1)
        sbc a,0
        ld (ix+SL_DLY+1),a
        ld a,(ix+SL_DLY+2)
        sbc a,0
        ld (ix+SL_DLY+2),a
        bit 7,a
        jr z,.dn
        ld (ix+SL_ST),SS_RUNNING
        xor a
        ld (ix+SL_DLY),a
        ld (ix+SL_DLY+1),a
        ld (ix+SL_DLY+2),a
.dn:    pop af
        inc a
        cp NSLOTS
        jr nz,.dl
        call SN_ST                  ; el reloj de la musica es el de la pista del CD
        ld a,(ix+SQ_CDON)
        or a
        jr z,.t1
        ld l,(ix+SQ_CDT)
        ld h,(ix+SQ_CDT+1)
        ld de,(DELTAV)
        add hl,de
        ld (ix+SQ_CDT),l
        ld (ix+SQ_CDT+1),h
.t1:    ld l,(ix+SQ_CDL)            ; lo que le queda (ni 0 ni $FFFF)
        ld h,(ix+SQ_CDL+1)
        call .dec
        ld (ix+SQ_CDL),l
        ld (ix+SQ_CDL+1),h
        push ix
        pop hl
        ld de,SQ_FX
        add hl,de
        ld b,NSFX
.fx:    push hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        push hl
        ex de,hl                    ; HL = lo que le queda
        ld a,h
        or l
        jr z,.fz
        call .dec
        ex de,hl
        pop hl
        ld (hl),d
        dec hl
        ld (hl),e
        ld a,d
        or e
        jr nz,.fn
        dec hl                      ; se ha acabado
        ld (hl),0
        jr .fn
.fz:    pop hl
.fn:    pop hl
        inc hl
        inc hl
        inc hl
        djnz .fx
        ld l,(ix+SQ_CDT)            ; VAR_MUSIC_TIMER: el reloj de la pista
        ld h,(ix+SQ_CDT+1)
        ld (VARS+2*VAR_MUSIC_TIMER),hl
        ld ix,ACTOR
        ret
; HL = max(0, HL - DELTAV), salvo 0 y $FFFF que se quedan
.dec:   ld a,h
        and l
        inc a
        ret z
        ld a,h
        or l
        ret z
        ld de,(DELTAV)
        or a
        sbc hl,de
        ret nc
        ld hl,0
        ret

TICK50: db 1, 2, 3, 3, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13   ; 5/6 de 1..15, redondeado

; --- startSound / startMusic (P0) ------------------------------------------------------
SN_STARTS:
        ld hl,0                     ; startSound pone VAR_MUSIC_TIMER a 0
        ld (VARS+2*VAR_MUSIC_TIMER),hl
SN_STARTM:
        ld a,(P0)
        ld l,a
        ld h,0
        ld (VARS+2*VAR_LAST_SOUND),hl
        call SN_ST
        ld a,(ix+SQ_N)              ; a la cola (si esta llena, se pierde)
        cp SQ_MAX
        jr nc,.x
        ld e,a
        inc a
        ld (ix+SQ_N),a
        push ix
        pop hl
        ld a,SQ_Q
        add a,e
        add hl,a
        ld a,(P0)
        ld (hl),a
.x:     ld ix,ACTOR
        ret

; --- isSoundRunning(P0): el resultado -----------------------------------------------
SN_RUNNING:
        ld a,(P0)
        or a
        jr z,.no
        ld c,a
        call SN_ST
        ld a,(ix+SQ_CDS)            ; la pista del CD: si suena (pollCD)
        cp c
        jr nz,.fx
        ld a,(ix+SQ_CDL)
        or (ix+SQ_CDL+1)
        jr z,.no
        jr .yes
.fx:    push ix
        pop hl
        ld de,SQ_FX
        add hl,de
        ld b,NSFX
.f:     ld a,(hl)
        inc hl
        cp c
        jr nz,.fnx
        ld a,(hl)
        inc hl
        or (hl)
        dec hl
        jr nz,.yes
.fnx:   inc hl
        inc hl
        djnz .f
        ld b,(ix+SQ_N)              ; en la cola
        push ix
        pop hl
        inc hl                      ; SQ_Q
        inc b
        jr .q
.ql:    ld a,(hl)
        inc hl
        cp c
        jr z,.yes
.q:     djnz .ql
.no:    ld hl,0
        jr .res
.yes:   ld hl,1
.res:   ld ix,ACTOR
        jp SETRESULT

; --- stopSound(P0) -------------------------------------------------------------------
SN_STOP:
        ld a,(P0)
        ld c,a
        call SN_ST
        ld a,c
        or a
        jr z,.fx
        cp (ix+SQ_CDS)
        jr nz,.fx
        call .cdoff
.fx:    push ix
        pop hl
        ld de,SQ_FX
        add hl,de
        ld b,NSFX
.f:     ld a,(hl)
        cp c
        jr nz,.fn
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
        dec hl
        dec hl
.fn:    inc hl
        inc hl
        inc hl
        djnz .f
        push ix                     ; y en la cola: a 0
        pop hl
        inc hl
        ld b,SQ_MAX
.q:     ld a,(hl)
        cp c
        jr nz,.qn
        ld (hl),0
.qn:    inc hl
        djnz .q
        ld a,c                      ; si suena (en cualquiera de los dos canales), parado
        or a
        call nz,SNDSTOPN
        ld ix,ACTOR
        ret
.cdoff: call MUSSTOP
        call SN_ST
        xor a
        ld (ix+SQ_CDS),a
        ld (ix+SQ_CDON),a
        ld (ix+SQ_CDL),a
        ld (ix+SQ_CDL+1),a
        ret

; --- stopMusic (stopAllSounds) ----------------------------------------------------------
SN_STOPALL:
        call SN_ST
        ld a,(ix+SQ_CDS)
        or a
        call nz,SN_STOP.cdoff
        call SN_CLEAR
        call SNDSTOP
        ld ix,ACTOR
        ret

; La cola y los efectos, vacios (IX = SNDST)
SN_CLEAR:
        push ix
        pop hl
        ld (hl),0                   ; SQ_N y la cola
        ld d,h
        ld e,l
        inc de
        ld bc,SQ_MAX
        ldir
        push ix
        pop hl
        ld de,SQ_FX
        add hl,de
        ld d,h
        ld e,l
        inc de
        ld (hl),0
        ld bc,3*NSFX-1
        ldir
        ret

; Al cargar una partida: la cola y los efectos digitalizados no se guardan (como en
; ScummVM); los de AdLib (iMuse) si, y los que dan vueltas suenan otra vez
SN_AFTERLOAD:
        call SN_ST
        push ix                     ; la cola, vacia
        pop hl
        ld (hl),0
        ld d,h
        ld e,l
        inc de
        ld bc,SQ_MAX
        ldir
        ld b,0                      ; los efectos, menos los de AdLib
.cl:    push bc
        call .fxp
        ld a,(hl)
        or a
        jr z,.cn
        ld (ATN),a
        call SN_ENTRY
        pop bc                      ; (B: el hueco)
        push bc
        call .fxp
        ld a,(ATK)
        cp SK_ADL
        jr z,.cn
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
.cn:    pop bc
        inc b
        ld a,b
        cp NSFX
        jr c,.cl
        call SNDSTOP
        call MUSSTOP
        call SN_ST                  ; la pista del CD que sonaba, por donde iba
        ld a,(ix+SQ_CDS)
        or a
        jr z,.x
        ld l,(ix+SQ_CDL)
        ld h,(ix+SQ_CDL+1)
        ld a,h
        or l
        jr z,.x
        ld l,(ix+SQ_CDT)
        ld h,(ix+SQ_CDT+1)
        ld (MURES),hl
        ld a,(ix+SQ_CDS)
        call MUSSTART
.x:     ld hl,0
        ld (MURES),hl
        ld b,0                      ; los de AdLib que dan vueltas ($FFFF), otra vez
.al:    push bc
        call .fxp
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        or a
        jr z,.an
        ld c,a
        ld a,d
        and e
        inc a
        ld a,c
        call z,SNDPLAY
.an:    pop bc
        inc b
        ld a,b
        cp NSFX
        jr c,.al
        ld ix,ACTOR
        ret
; HL = el hueco B de los efectos (UIP en MMU7, IX = SNDST)
.fxp:   call SN_ST
        push ix
        pop hl
        ld de,SQ_FX
        add hl,de
        ld a,b
        add a,a
        add a,b
        add hl,a
        ret

; --- soundKludge: (-1) es "la cola, ahora" ---------------------------------------------
SN_KLUDGE:
        ld a,(ARGN)
        or a
        ret z
        ld hl,(ARGS)
        inc hl
        ld a,h
        or l
        ret nz
; --- processSound: la cola, del ultimo al primero (al final de cada paso) ---------------
SN_PROCESS:
.lp:    call SN_ST
        ld a,(ix+SQ_N)
        or a
        jr z,.x
        dec a
        ld (ix+SQ_N),a
        push ix
        pop hl
        inc hl
        add hl,a
        ld a,(hl)
        ld (hl),0
        or a
        call nz,SN_TRIGGER
        jr .lp
.x:     ld ix,ACTOR
        ret

; --- playActorSounds y despues processSound (al final de un paso en una habitacion) -----
; El primer actor de la habitacion cuyo costume ha pasado por un comando de sonido
; ($78, R_SCNT) pone el suyo (startSound) y se olvidan los de todos
SN_ACTORS:
        call ACTSYNC                ; (el de ACTOR, a su ficha: se leen todas alli)
        ld b,1
.lp:    ld a,b
        call ACTREC                 ; HL = su ficha (no cambia B)
        ld de,R_SCNT
        add hl,de
        ld a,(hl)
        or a
        jr z,.nx
        ld de,R_ROOM-R_SCNT
        add hl,de
        ld a,(CURROOM)
        cp (hl)
        jr z,.snd
.nx:    inc b
        ld a,b
        cp NACT
        jr c,.lp
        jr SN_PROCESS
.snd:   ld de,R_SND-R_ROOM
        add hl,de
        ld a,(hl)
        ld (P0),a
        xor a                       ; los de todos a 0 (y ACTOR, copia de una ficha)
        ld (ACTOR+R_SCNT),a
        ld b,1
.clr:   ld a,b
        call ACTREC
        ld de,R_SCNT
        add hl,de
        ld (hl),0
        inc b
        ld a,b
        cp NACT
        jr c,.clr
        call SN_STARTM
        jr SN_PROCESS

; triggerSound(A)
SN_TRIGGER:
        ld (ATN),a
        call SN_ENTRY
        ld a,(ATK)
        cp SK_CD
        jp z,.cd
        cp SK_ADL
        jr nz,.sbl
        ld hl,(ATD)                 ; AdLib: si no se pudo leer (0 jiffies), nada
        ld a,h
        or l
        ret z
        call SN_ST                  ; si ya suena, otra vez desde el principio (iMuse)
        push ix
        pop hl
        ld de,SQ_FX
        add hl,de
        ld b,NSFX
.a:     ld a,(ATN)
        cp (hl)
        jr nz,.an
        inc hl
        ld a,(hl)
        inc hl
        or (hl)
        dec hl
        dec hl
        jr z,.an
        ld (ATP),hl
        jp .set
.an:    inc hl
        inc hl
        inc hl
        djnz .a
        jr .alloc
.sbl:   cp SK_SBL
        ret nz
.alloc: call SN_ST                   ; un efecto: el primer hueco libre o, si no hay,
        push ix                     ; el que menos le queda (el primero de ellos)
        pop hl
        ld de,SQ_FX
        add hl,de
        ld (ATP),hl
        ld de,$FFFF
        ld b,NSFX
.f:     push hl
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                      ; HL = lo que le queda
        or h
        jr z,.free
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,.fn                   ; no es menos que el mejor
        ex de,hl
        pop hl
        push hl
        ld (ATP),hl
.fn:    pop hl
        inc hl
        inc hl
        inc hl
        djnz .f
        jr .set
.free:  pop hl
        ld (ATP),hl
.set:   ld hl,(ATP)
        ld a,(ATN)
        ld (hl),a
        inc hl
        ld de,(ATD)
        ld (hl),e
        inc hl
        ld (hl),d
        ld ix,ACTOR
        ld a,(ATN)
        jp SNDPLAY
.cd:    call SN_ST                   ; una pista del CD (si es la que suena, nada)
        ld a,(ATN)
        cp (ix+SQ_CDS)
        jr nz,.new
        ld a,(ix+SQ_CDL)
        or (ix+SQ_CDL+1)
        jr nz,.cx
.new:   ld a,(ATN)
        ld (ix+SQ_CDS),a
        ld (ix+SQ_CDON),1
        xor a
        ld (ix+SQ_CDT),a
        ld (ix+SQ_CDT+1),a
        ld hl,(ATD)
        ld (ix+SQ_CDL),l
        ld (ix+SQ_CDL+1),h
        ld hl,0                     ; playCDTrack: VAR_MUSIC_TIMER a 0
        ld (VARS+2*VAR_MUSIC_TIMER),hl
        ld ix,ACTOR
        ld a,(ATN)                  ; y la musica de verdad
        jp MUSSTART
.cx:    ld ix,ACTOR
        ret

; La entrada del sonido ATN: ATK = tipo (0 si no hay), ATD = jiffies; HL = la entrada
SN_ENTRY:
        xor a
        ld (ATK),a
        ld a,(SNDOK)
        or a
        ret z
        ld a,SND_PAGE
        call MAP7
        ld hl,($E004)               ; cuantos hay
        ld a,h
        or a
        jr nz,.ok
        ld a,(ATN)
        cp l
        ret nc
.ok:    ld a,(ATN)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,SNDE
        add hl,de
        push hl
        ld a,(hl)
        ld (ATK),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (ATD),de
        pop hl
        ret

; --- el sonido de verdad ----------------------------------------------------------------
; El efecto A (o el de AdLib, con su bucle) en un canal (desde ahora, su interrupcion
; saca sus muestras): uno de AdLib que ya suena, otra vez en el suyo; si no, el que este
; libre o, si suenan los dos, el que antes iba a acabar (se corta; los que dan vueltas,
; los ultimos)
SNDPLAY:
        ld (ATN),a
        call SN_ENTRY
        ld a,(ATK)
        ld (ATKIND),a
        cp SK_SBL
        jr z,.ok
        cp SK_ADL
        ret nz
.ok:    inc hl
        inc hl
        inc hl
        ld a,(hl)                   ; constante del CTC (el 0, que seria 256, como 255:
        or a                        ; con 0 el CTC 0 de CSpect, y quiza el de algun Next,
        jr nz,.tc                   ; interrumpe sin parar y el programa se queda quieto)
        dec a
.tc:    ld (ATK),a
        inc hl
        ld e,(hl)                   ; posicion (3 bytes)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld a,(hl)                   ; largo
        ld (ATD),a
        inc hl
        ld a,(hl)
        ld (ATD+1),a
        inc hl
        ld a,(hl)                   ; (AdLib) el principio del bucle ($FFFF: no da vueltas)
        ld (ATL),a
        inc hl
        ld a,(hl)
        ld (ATL+1),a
        ld hl,(ATD)
        ld a,h
        or l
        ret z
        ld (ATPOS),de
        ld a,c
        ld (ATPOS+2),a
        call SNPP
        ld a,b
        ld (ATPG),a
        ld (ATPT),de
        ld hl,0
        ld (ATLL),hl
        ld a,(ATKIND)
        cp SK_ADL
        jr nz,.nl
        ld hl,(ATL)
        ld a,h
        and l
        inc a
        jr z,.nl
        ex de,hl                    ; DE = donde empieza el bucle
        ld hl,(ATD)
        or a
        sbc hl,de
        jr c,.nl
        jr z,.nl
        ld (ATLL),hl                ; su largo
        ld hl,(ATPOS)               ; y su sitio: posicion + principio
        add hl,de
        ex de,hl
        ld a,(ATPOS+2)
        adc a,0
        ld c,a
        call SNPP
        ld a,b
        ld (ATLPG),a
        ld (ATLPT),de
.nl:    di
        ld a,(ATKIND)               ; AdLib que ya suena: en su canal
        cp SK_ADL
        jr nz,.free
        ld a,(ATN)
        ld hl,AUSND
        cp (hl)
        jr nz,.a2
        ld hl,(AULEN)
        ld a,h
        or l
        jr nz,.c1
        ld a,(ATN)
.a2:    ld hl,AUSND2
        cp (hl)
        jr nz,.free
        ld hl,(AULEN2)
        ld a,h
        or l
        jr nz,.c2
.free:  ld hl,(AULEN)               ; uno libre, o el que antes acaba
        ld a,h
        or l
        jr z,.c1
        ld de,(AULLN)               ; (los que dan vueltas, como si no acabaran)
        ld a,d
        or e
        jr z,.r1
        ld hl,$FFFF
.r1:    ex de,hl                    ; DE = lo que le queda al 1
        ld hl,(AULEN2)
        ld a,h
        or l
        jr z,.c2
        ld bc,(AULLN2)
        ld a,b
        or c
        jr z,.r2
        ld hl,$FFFF
.r2:    or a
        sbc hl,de                   ; (al 2 le queda menos: carry)
        jr c,.c2
.c1:    ld a,(ATPG)
        ld (AUPG),a
        ld hl,(ATPT)
        ld (AUPTR),hl
        ld hl,(ATD)
        ld (AULEN),hl
        ld hl,(ATLL)
        ld (AULLN),hl
        ld a,(ATLPG)
        ld (AULPG),a
        ld hl,(ATLPT)
        ld (AULPT),hl
        ld a,(ATN)
        ld (AUSND),a
        ld bc,$183B                 ; CTC 0
        jr .go
.c2:    ld a,(ATPG)
        ld (AUPG2),a
        ld hl,(ATPT)
        ld (AUPTR2),hl
        ld hl,(ATD)
        ld (AULEN2),hl
        ld hl,(ATLL)
        ld (AULLN2),hl
        ld a,(ATLPG)
        ld (AULPG2),a
        ld hl,(ATLPT)
        ld (AULPT2),hl
        ld a,(ATN)
        ld (AUSND2),a
        ld bc,$1A3B                 ; CTC 2
.go:    ld a,%10000111              ; interrupcion, temporizador, x16, constante
        out (c),a
        ld a,(ATK)
        out (c),a
        ei
        ret

; B = la pagina y DE = la direccion (en $6000) de la posicion C:D:E de las muestras
SNPP:
        ld a,d                      ; pagina: SND_PAGE + 1 + posicion >> 13
        rlca
        rlca
        rlca
        and 7
        ld b,a
        ld a,c
        add a,a
        add a,a
        add a,a
        or b
        add a,SND_PAGE+1
        ld b,a
        ld a,d                      ; y $6000 + posicion & $1FFF
        and $1F
        or $60
        ld d,a
        ret

; Sin efectos: los CTC 0 y 2 parados y el DAC en silencio
SNDSTOP:
        di
        ld bc,$183B
        ld a,%00000011
        out (c),a
        ld b,$1A
        out (c),a
        xor a
        ld (AUSND),a
        ld (AULEN),a
        ld (AULEN+1),a
        ld (AUSND2),a
        ld (AULEN2),a
        ld (AULEN2+1),a
        ld (AULLN),a
        ld (AULLN+1),a
        ld (AULLN2),a
        ld (AULLN2+1),a
        ld a,$80
        ld (AUS1),a
        ld (AUS2),a
        nextreg $2D,a
        ei
        ret

; Sin el efecto A, en el canal (o los dos) en que suene
SNDSTOPN:
        di
        ld hl,AUSND
        cp (hl)
        jr nz,.n2
        ld (hl),0
        ld bc,$183B
        ld hl,AULEN
        ld de,AUS1
        call .off
        ld hl,0
        ld (AULLN),hl
.n2:    ld hl,AUSND2
        cp (hl)
        jr nz,.mx
        ld (hl),0
        ld bc,$1A3B
        ld hl,AULEN2
        ld de,AUS2
        call .off
        ld hl,0
        ld (AULLN2),hl
.mx:    call AUMIX
        ei
        ret
.off:   push af                     ; el CTC BC parado, el largo (HL) a 0 y la muestra
        ld a,%00000011              ; (DE) en silencio
        out (c),a
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        ld a,$80
        ld (de),a
        pop af
        ret

; Al arrancar: SOUNDS.DAT a SND_PAGE.., el DAC, el CTC 0 parado y su vector (IM2 de
; hardware: la linea da el vector 0 y el CTC 0 el 6; con el IM2 de siempre, $FF)
SNDINIT:
        xor a
        ld (SNDOK),a
        ld hl,SNDNAME
        ld a,SND_PAGE
        ld b,SND_MAX
        call LOADPAGES
        jr c,.no
        ld a,SND_PAGE
        call MAP7
        ld hl,$E000
        ld de,SNDMAGIC
        ld b,4
.m:     ld a,(de)
        cp (hl)
        jr nz,.no
        inc hl
        inc de
        djnz .m
        ld a,1
        ld (SNDOK),a
.no:    ld bc,$183B                 ; los CTC 0, 1 y 2 parados y sus vectores (CTC 2: el
        ld a,%00000011              ; segundo canal de efectos)
        out (c),a
        inc b
        out (c),a
        inc b
        out (c),a
        ld hl,SNDISR
        ld (IM2_T+6),hl
        ld hl,MUSISR
        ld (IM2_T+8),hl
        ld hl,SNDISR2
        ld (IM2_T+10),hl
        ld a,$80
        ld (AUS1),a
        ld (AUS2),a
        ld bc,$243B                 ; NR $08: los DAC encendidos
        ld a,$08
        out (c),a
        inc b
        in a,(c)
        and %01111111
        or %00001000
        nextreg $08,a
        dec b
        ld a,$C0                    ; NR $C0: IM2 de hardware, vectores desde 0
        out (c),a
        inc b
        in a,(c)
        and %00001000
        or %00000001
        nextreg $C0,a
        nextreg $CD,0               ; el CTC no para el DMA: los DMA van a trozos de 256
        ld a,$80                    ; (DMAOUTC, KFAST, DMACP), menos que una muestra
        nextreg $2D,a
        ret
; --- la musica del CD: Tnn.DAT (8 bits, 11025 Hz) por un anillo de MUS_N paginas --------
; La pista del sonido A (desde MURES jiffies, si no es 0): el fichero, adonde
; empieza, cuanto dura un trozo y cuantas veces suena; dos paginas leidas y el CTC 1
MUSSTART:
        ld (ATN),a
        call MUSSTOP
        call SN_ENTRY
        ld a,(ATK)
        cp SK_CD
        ret nz
        inc hl
        inc hl
        inc hl
        ld a,(hl)                   ; pista
        ld (MUTRK),a
        inc hl
        ld a,(hl)                   ; vueltas ($FF: siempre)
        ld (MULOOP),a
        inc hl
        ld de,MUSTRT                ; principio y trozo, en frames: por 147, en muestras
        call .x147
        ld de,MULEN
        call .x147
        ld hl,0
        ld (MUPOS),hl
        ld (MUPOS+2),hl
        ld hl,(MURES)               ; (al cargar: por donde iba, a 184 muestras el jiffy)
        ld a,h
        or l
        jr z,.nm
        ld de,184
        call MULU16                 ; DE:HL
        ld (MUPOS),hl
        ld (MUPOS+2),de
.nm:    ld a,(MUTRK)                ; "Tnn.DAT"
        ld b,0
.d:     cp 10
        jr c,.d1
        sub 10
        inc b
        jr .d
.d1:    add a,'0'
        ld (MUNAME+2),a
        ld a,b
        add a,'0'
        ld (MUNAME+1),a
        call MUESXON
        ld hl,MUNAME
        call FOPEN
        call MUESXOFF
        ret c
        ld (MUH),a
        ld a,1
        ld (MUON),a
        xor a
        ld (MUWR),a
        ld (MUEOF),a
        ld (MUAV),a
        ld (MUPLAY),a
        ld a,MUS_PAGE
        ld (MUPG),a
        ld hl,$6000
        ld (MUPTR),hl
        ld hl,(MULEN)               ; si ya ha pasado el trozo, desde el principio
        ld de,(MULEN+2)
        ld a,h
        or l
        or d
        or e
        jr z,.sk
        ld hl,(MUPOS+2)
        call CPU16                  ; (palabras altas: MUPOS < MULEN ?)
        jr c,.sk
        jr nz,.z
        ld hl,(MUPOS)
        ld de,(MULEN)
        call CPU16
        jr c,.sk
.z:     ld hl,0
        ld (MUPOS),hl
        ld (MUPOS+2),hl
.sk:    call MUSEEK
        call MUSPOLL
        jp MUSPOLL
; (DE) = (3 bytes de HL) * 147, en 32 bits; HL despues de los 3 bytes
.x147:  push de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        push hl
        push af
        ex de,hl
        ld de,147
        call MULU16                 ; DE:HL = los 16 bits bajos * 147
        ld (MXL),hl
        ld (MXL+2),de
        pop af
        ld l,a
        ld h,0
        ld de,147
        call MULU16                 ; HL = el byte alto * 147
        ld de,(MXL+2)
        add hl,de
        ld (MXL+2),hl
        pop hl
        pop de
        push hl
        ld hl,MXL
        ld bc,4
        ldir
        pop hl
        ret

; El fichero a MUSTRT + MUPOS
MUSEEK:
        ld hl,(MUSTRT)
        ld de,(MUPOS)
        add hl,de
        ex de,hl
        ld hl,(MUSTRT+2)
        ld bc,(MUPOS+2)
        adc hl,bc
        ld b,h
        ld c,l
        call MUESXON
        ld a,(MUH)
        call FSEEK
        jp MUESXOFF

; Sin musica: el CTC 1 parado, silencio y el fichero cerrado
MUSSTOP:
        di
        ld bc,$193B
        ld a,%00000011
        out (c),a
        xor a
        ld (MUPLAY),a
        ld (MUAV),a
        ld a,$80
        nextreg $2C,a
        nextreg $2E,a
        ei
        ld a,(MUON)
        or a
        ret z
        xor a
        ld (MUON),a
        call MUESXON
        ld a,(MUH)
        call FCLOSE
        jp MUESXOFF

; Una pagina mas del anillo (si cabe y queda algo por leer); el CTC 1 en marcha
; cuando hay dos (o se acabo la pista)
MUSPOLL:
        ld a,(MUON)
        or a
        ret z
        ld a,(MUAV)
        cp MUS_N
        ret nc
        ld a,(MUWR)
        add a,MUS_PAGE
        call MAP7
        ld hl,$E000
        ld (MUDST),hl
        ld hl,$2000
        ld (MUWANT),hl
        ld a,8                      ; (vueltas sin leer nada: no se cuelga)
        ld (MUWRAP),a
.rd:    ld hl,(MUWANT)              ; n = lo que falta, como mucho lo que queda del trozo
        ld (MUN),hl
        ld hl,(MULEN)
        ld de,(MULEN+2)
        ld a,h
        or l
        or d
        or e
        jr z,.go
        ld bc,(MUPOS)               ; MULEN - MUPOS
        or a
        sbc hl,bc
        ex de,hl
        ld bc,(MUPOS+2)
        sbc hl,bc
        jr c,.wrap
        ld a,h
        or l
        jr nz,.go
        ld hl,(MUN)
        call CPU16                  ; MUN < resto (DE) ?
        jr c,.go
        ld (MUN),de
        ld a,d
        or e
        jr z,.wrap
.go:    ld a,(MUWR)                 ; (MMU7 en el anillo: la pagina otra vez)
        ld a,(MUWR)
        add a,MUS_PAGE
        call MAP7
        call MUESXON
        ld a,(MUH)
        ld hl,(MUDST)
        ld bc,(MUN)
        call FREAD
        call MUESXOFF
        jr c,.pad
        ld hl,(MUPOS)               ; MUPOS += leidos
        add hl,bc
        ld (MUPOS),hl
        jr nc,.p1
        ld hl,(MUPOS+2)
        inc hl
        ld (MUPOS+2),hl
.p1:    ld hl,(MUDST)
        add hl,bc
        ld (MUDST),hl
        ld hl,(MUWANT)
        or a
        sbc hl,bc
        ld (MUWANT),hl
        jr z,.done
        ld hl,(MUN)                 ; menos de lo pedido: se acabo el fichero
        or a
        sbc hl,bc
        jp z,.rd
.wrap:  ld a,(MULOOP)               ; otra vuelta, si quedan
        cp $FF
        jr z,.again
        dec a
        ld (MULOOP),a
        jr z,.pad
.again: ld hl,MUWRAP
        dec (hl)
        jr z,.pad
        ld hl,0
        ld (MUPOS),hl
        ld (MUPOS+2),hl
        call MUSEEK
        jp .rd
.pad:   ld a,(MUWR)                 ; se acabo: el resto, silencio
        add a,MUS_PAGE
        call MAP7
        ld hl,(MUWANT)
        ld a,h
        or l
        jr z,.cl
        ld b,h
        ld c,l
        ld hl,(MUDST)
        ld (hl),$80
        dec bc
        ld a,b
        or c
        jr z,.cl
        ld d,h
        ld e,l
        inc de
        ldir
.cl:    ld a,1
        ld (MUEOF),a
        xor a
        ld (MUON),a
        call MUESXON
        ld a,(MUH)
        call FCLOSE
        call MUESXOFF
.done:  ld a,(MUWR)
        inc a
        and MUS_N-1
        ld (MUWR),a
        di
        ld hl,MUAV
        inc (hl)
        ei
        ld a,(MUPLAY)
        or a
        ret nz
        ld a,(MUAV)
        cp 2
        jr nc,.start
        ld a,(MUEOF)
        or a
        ret z
.start: di
        ld hl,MUBUF+1               ; silencio hasta que lo llene MUFILL (en la
        ld de,MUBUF+2               ; siguiente imagen)
        ld bc,254
        ld (hl),$80
        ldir
        ld a,(MURD+1)
        ld (MUWB),a
        ld a,1
        ld (MUPLAY),a
        ld bc,$193B                 ; CTC 1: interrupcion, temporizador, x16, constante
        ld a,%10000111
        out (c),a
        ld a,MUS_TC
        out (c),a
        ei
        ret

; esxDOS con las interrupciones puestas: las paginas 10 y 11 en $4000-$7FFF (AUM3
; primero, para que las interrupciones del CTC dejen la 11)
MUESXON:
        push af
        ld a,11
        ld (AUM3),a
        nextreg $53,11
        nextreg $52,10
        pop af
        ret
MUESXOFF:
        push af
        ld a,(SPRCUR)
        ld (AUM3),a
        nextreg $53,a
        ld a,(SHMMU2)
        nextreg $52,a
        pop af
        ret

MUNAME: db "T00.DAT",0
MUON:   db 0                        ; el fichero de la pista, abierto
MUH:    db 0
MUTRK:  db 0
MULOOP: db 0                        ; vueltas que quedan ($FF: siempre)
MUSTRT: ds 4                        ; donde empieza el trozo (muestras)
MULEN:  ds 4                        ; cuanto dura (0: hasta el final del fichero)
MUPOS:  ds 4                        ; por donde va la lectura en el trozo
MURES:  dw 0                        ; (al cargar una partida: jiffies que ya habian sonado)
MUWR:   db 0                        ; la pagina del anillo que se llena despues
MUEOF:  db 0
MUDST:  dw 0
MUWANT: dw 0
MUN:    dw 0
MUWRAP: db 0
MXL:    ds 4

SNDMAGIC:
        db "SN5",1
SNDNAME:
        db "SOUNDS.DAT",0

ATN:    db 0
ATK:    db 0
ATD:    dw 0
ATP:    dw 0
ATKIND: db 0                        ; (SNDPLAY) tipo, principio del bucle, posicion de las
ATL:    dw 0                        ; muestras, su pagina y direccion, y las del bucle y
ATPOS:  ds 3                        ; su largo
ATPG:   db 0
ATPT:   dw 0
ATLPG:  db 0
ATLPT:  dw 0
ATLL:   dw 0

OVA_END:
        ASSERT OVA_END <= $E000, la capa OVA no cabe
