; ===========================================================================
;  Camara, protagonista y piezas del paso que van en el banco 0
;  (no las usa la interrupcion ni se llaman con la ROM puesta)
; ===========================================================================

; --- camara (camera.cpp) ----------------------------------------------------------
; setCameraAt(HL): salta si no sigue a nadie o si esta lejos; acotada por las variables
SETCAMAT:
        ld (SCAX),hl
        ld a,(CAM_MODE)
        cp CAM_FOLLOW
        jr nz,.cur
        ld de,(CAM_CUR)             ; |x - cur| > 160 ?
        or a
        sbc hl,de
        bit 7,h
        jr z,.ab
        ex de,hl
        ld hl,0
        or a
        sbc hl,de
.ab:    ld de,161
        call CPS16
        jr c,.dest
.cur:   ld hl,(SCAX)
        ld (CAM_CUR),hl
.dest:  ld hl,(SCAX)
        ld (CAM_DEST),hl
        ld hl,(CAM_CUR)
        ld de,(VARS+2*VAR_CAMERA_MIN_X)
        call CPS16
        jr nc,.m1
        ld (CAM_CUR),de
.m1:    ld hl,(CAM_CUR)
        ld de,(VARS+2*VAR_CAMERA_MAX_X)
        ex de,hl
        call CPS16                  ; max < cur ?
        jr nc,.m2
        ld (CAM_CUR),hl
.m2:    call SCROLLSCR
; Si la camara se ha movido con texto en pantalla: stopTalk (redrawBGAreas, v4-6)
CAMTALK:
        ld hl,(CAM_CUR)
        ld de,(CAMLAST)
        or a
        sbc hl,de
        ret z
        ld a,(HASMASK)
        or a
        ret z
        ld a,OVT_PAGE
        ld hl,STOPTALK
        jp OVCALL
; El script de scroll (VAR_SCROLL_SCRIPT), si hay
SCROLLSCR:
        ld hl,(VARS+2*VAR_SCROLL_SCRIPT)
        ld a,h
        or l
        ret z
        push hl
        ld hl,(CAM_CUR)
        ld (VARS+2*VAR_CAMERA_POS_X),hl
        pop hl
        jp RUNVARSCR
; setCameraAt de los scripts (setCameraAtEx): modo normal y salta a HL
CAMAT:
        ld a,(CURROOM)
        or a
        ret z
        ld a,CAM_NORMAL
        ld (CAM_MODE),a
        ld (CAM_CUR),hl
        call SETCAMAT
        xor a
        ld (CAM_MTA),a
        ret
CAMPAN:                             ; panCameraTo
        ld a,(CURROOM)
        or a
        ret z
        ld (CAM_DEST),hl
        ld a,CAM_PAN
        ld (CAM_MODE),a
        xor a
        ld (CAM_MTA),a
        ret
; actorFollowCamera(A): si cambia a quien sigue, el script de inventario
CAMFOLLOW:
        ld c,a
        ld a,(FOLLOWS)
        ld (CFOLD),a
        ld a,c
        call CAMFOLLOWS
        ld a,(CFOLD)
        ld hl,FOLLOWS
        cp (hl)
        ret z
        xor a
        ld hl,RUNINVSCR
        ld a,OVU_PAGE               ; (RUNINVSCR esta en OVU; con A = 0 en ARGS)
        ld (CFARG),a
        xor a
        ld (ARGS),a
        ld (ARGS+1),a
        inc a
        ld (ARGN),a
        ld hl,(VARS+2*VAR_INVENTORY_SCRIPT)
        ld a,h
        or l
        ret z
        xor a
        ld (SSFRES),a
        ld (SSREC),a
        ld a,l
        call RUNSCRIPT
        jp RESTOREIY
; setCameraFollows(A): si el actor esta en otra habitacion, se va alli
CAMFOLLOWS:
        ld (FOLLOWS),a
        ld a,CAM_FOLLOW
        ld (CAM_MODE),a
        ld a,(FOLLOWS)
        call INROOM
        jr c,.here
        ld a,(FOLLOWS)              ; a su habitacion
        ld e,R_ROOM
        call ACTRD
        ld a,l
        ld hl,0
        ld (SCOBJ),hl
        call CHANGEROOM
        ld a,(CURROOM)
        or a
        ret z
        ld a,CAM_FOLLOW
        ld (CAM_MODE),a
        call FOLLOWX
        ld (CAM_CUR),hl
        call SETCAMAT
.here:  ld a,(CURROOM)
        or a
        ret z
        call FOLLOWX                ; t = x / 8 - tira de la izquierda
        call SHR3
        ld a,(CAM_SS)
        ld e,a
        ld d,0
        or a
        sbc hl,de
        ld de,10
        call CPS16
        jr c,.set
        ld de,31
        call CPS16
        jr c,.inv
.set:   call FOLLOWX
        call SETCAMAT
.inv:   xor a                       ; el script de inventario (0)
        ld (ARGS),a
        ld (ARGS+1),a
        inc a
        ld (ARGN),a
        ld hl,(VARS+2*VAR_INVENTORY_SCRIPT)
        ld a,h
        or l
        jr z,.mta
        xor a
        ld (SSFRES),a
        ld (SSREC),a
        ld a,l
        call RUNSCRIPT
        call RESTOREIY
.mta:   xor a
        ld (CAM_MTA),a
        ret
; HL = x del actor que sigue la camara
FOLLOWX:
        ld a,(FOLLOWS)
        ld l,a
        ld h,0
        push de
        call ACTXY
        pop de
        ret

; Los sprites de los actores, ocultos y sin patrones (el principio de cada paso)
HIDEACT:
        ld hl,ATTRBUF
        ld b,NSPR_ACTOR
.lp:    ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),$40
        inc hl
        ld (hl),0
        inc hl
        djnz .lp
        ld h,b
        ld l,b
        ld (SPRUSED),hl
        ld (SPRUSD8),hl
        xor a
        ld (SPRK),a
        ret

; La entrada del paso: el raton (UMX, UMY), una tecla (TKEYV) y un boton (TBUTV)
STEPIN:
        ld hl,U_SETMOUSE
        call OVUCALL
        ld a,(TKEYV)
        or a
        jr z,.nk
        ld b,a
        xor a
        ld (TKEYV),a
        ld a,b
        OUCALL U_KEY
.nk:    ld a,(TBUTV)
        or a
        ret z
        ld l,a
        ld h,$80
        ld (MOUSEKB),hl
        xor a
        ld (TBUTV),a
        ret

; CHARSET_1 y el verbo bajo el raton
UITEXT:
        ld a,OVT_PAGE
        ld hl,CHARSET1
        call OVCALL
        ld hl,(CURSTATE)
        bit 7,h
        ret nz
        ld a,h
        or l
        ret z
        ld a,OVT_PAGE
        ld hl,VMOUSEAT
        jp OVCALL

; Habitacion de menos de 320 pixeles: el resto de la pantalla principal, en negro
NARROW:
        ld a,(RNS)
        cp 40
        ret nc
        add a,a
        add a,a
        add a,a                     ; primera columna
        ld l,a
        ld h,0
        ld (NRC),hl
        ld a,$FF
        ld (L2CUR),a
.col:   ld a,(NRC)                  ; pagina = L2_PAGE + col / 32 (col < 320: aqui < 256+64)
        ld l,a
        ld h,0
        ld a,(NRC+1)
        ld h,a
        ld a,l
        srl h
        rra
        srl a
        srl a
        srl a
        srl a
        add a,L2_PAGE
        nextreg $52,a
        ld a,(NRC)
        and 31
        add a,$40
        ld h,a
        ld l,ROOM_Y0
        ld a,(MAINH)
        or a
        jr z,.nx
        ld b,a
.cl:    ld (hl),0
        inc hl
        djnz .cl
.nx:    ld hl,(NRC)
        inc hl
        ld (NRC),hl
        ld de,320
        or a
        sbc hl,de
        jr nz,.col
        ld a,(SHMMU2)
        nextreg $52,a
        ret
NRC:    dw 0

MENUK   EQU 5                       ; codigo de la tecla del menu (CAPS + 1)
METERK  EQU 6                       ; y la del medidor de tiempos (CAPS + 2)

; systemOps 1: el juego desde el principio (como TREQ 9)
RESTART:
        ld hl,(UMX)                 ; (el raton de este paso ya esta puesto)
        push hl
        ld hl,(UMY)
        push hl
        ld hl,SNDSTOP               ; (sin el efecto que sonaba ni la musica)
        ld a,OVA_PAGE
        call OVCALL
        ld hl,MUSSTOP
        ld a,OVA_PAGE
        call OVCALL
        call L2CLEAR
        call BOOT
        pop hl
        ld (UMY),hl
        pop hl
        ld (UMX),hl
        ret

; Ciclos de color y temblor (capa OVF)
FXSTEPC:
        ld hl,F_STEP
        ld a,OVF_PAGE
        jp OVCALL

; Transiciones: la de salida (en startScene, con la maquina virtual) y la de entrada
; (al final del paso, si la pantalla esta tapada)
FXOUTC:
        ld a,(VMON)
        or a
        ret z
        ld hl,F_FADEOUT
        ld a,OVF_PAGE
        jp OVCALL
FXINC:
        ld a,(HIDDEN)
        or a
        ret z
        ld hl,F_FADEIN
        ld a,OVF_PAGE
        jp OVCALL

; --- la entrada en el juego ------------------------------------------------------
; El teclado y los botones del raton (desde la interrupcion, cada frame): lo recien
; pulsado a KEYPEND si esta libre. Codigos: 1 / 2 = botones izquierdo / derecho
; (raton, ENTER / CAPS + ENTER); letras y cifras en ASCII (con CAPS, mayusculas),
; espacio, ESC (CAPS + SPACE), borrar (CAPS + 0) y . , ? - : (SYM + M N C J Z).
; CAPS + 5 6 7 8 mueven el cursor (en la interrupcion).
KEYSCAN:
        call .now
        ld hl,KLAST
        ld a,(hl)
        ld (hl),e
        cp e
        ret z
        ld a,e
        or a
        ret z
        ld a,(KEYPEND)
        or a
        ret nz
        ld a,e
        ld (KEYPEND),a
        ret
; E = lo que hay pulsado ahora (0: nada)
.now:   ld bc,$FADF                 ; los botones del raton (0 = pulsado)
        in a,(c)
        ld e,1
        bit 1,a
        ret z
        inc e
        bit 0,a
        ret z
        ld bc,$FEFE                 ; D: bit 0 CAPS, bit 1 SYM
        in a,(c)
        cpl
        and 1
        ld d,a
        ld b,$7F
        in a,(c)
        cpl
        and 2
        or d
        ld d,a
        ld hl,KEYTAB
        ld b,$FE
.row:   ld c,$FE
        in a,(c)
        ld c,5
.bit:   rrca
        jr c,.nx
        ld e,(hl)
        inc e
        dec e
        jr nz,.key
.nx:    inc hl
        dec c
        jr nz,.bit
        rlc b
        jr c,.row
        ld e,0
        ret
.key:   ld a,d
        or a
        jr z,.plain
        bit 0,d
        jr z,.sym
        ld a,e                      ; con CAPS
        cp ' '
        jr nz,.c1
        ld e,27
        ret
.c1:    cp '0'
        jr nz,.c1b
        ld e,8
        ret
.c1b:   cp '1'                      ; CAPS + 1: el menu de partidas
        jr nz,.c1c
        ld e,MENUK
        ret
.c1c:   cp '2'                      ; CAPS + 2: el medidor (capa SM)
        jr nz,.c2
        ld e,METERK
        ret
.c2:    cp '5'
        jr c,.c3
        cp '9'
        jr nc,.c3
        ld e,0                      ; (el cursor)
        ret
.c3:    cp KENTER
        jr nz,.c4
        ld e,2
        ret
.c4:    cp 'a'
        ret c
        cp 'z'+1
        ret nc
        sub 32
        ld e,a
        ret
.sym:   ld hl,SYMTAB                ; con SYM
        ld b,5
.s1:    ld a,(hl)
        inc hl
        cp e
        ld a,(hl)
        inc hl
        jr z,.s2
        djnz .s1
        ld e,0
        ret
.s2:    ld e,a
        ret
.plain: ld a,e
        cp KENTER
        ret nz
        ld e,1
        ret
KENTER  EQU 13
; filas $FE, $FD, $FB, $F7, $EF, $DF, $BF y $7F; bits 0 a 4 (0: CAPS y SYM)
KEYTAB: db 0,"zxcv"
        db "asdfg"
        db "qwert"
        db "12345"
        db "09876"
        db "poiuy"
        db KENTER,"lkjh"
        db " ",0,"mnb"
SYMTAB: db "m.n,c?j-z:"
KEYPEND: db 0
KLAST:  db 0

; La entrada de un paso en el juego: el raton (CURX, CURY) en la pantalla de SCUMM y
; lo que haya en KEYPEND: un boton (el 1 tambien anda sin script de verbos) o una tecla
PADIN:
        xor a
        ld (TCLICK),a
        ld hl,(CURX)
        ld (UMX),hl
        ld hl,(CURY)
        ld de,ROOM_Y0
        or a
        sbc hl,de
        ld (UMY),hl
        ld a,(KEYPEND)
        or a
        ret z
        ld b,a
        xor a
        ld (KEYPEND),a
        ld a,b
        cp MENUK
        jr z,.menu
        cp METERK
        jr z,.meter
        cp 3
        jr c,.but
        ld (TKEYV),a
        ret
.meter: ld a,(METERON)
        xor 1
        ld (METERON),a
        ret
.menu:  ld hl,MENU                  ; el menu (guardar, cargar, reiniciar, salir)
        ld a,OVS_PAGE
        jp OVCALL
.but:   ld (TBUTV),a
        dec a
        ret nz
        ld hl,(UMX)                 ; andar directo (si no hay script de verbos)
        ld de,(LEFT)
        add hl,de
        ld (TCX),hl
        ld hl,(UMY)
        ld (TCY),hl
        ld a,1
        ld (TCLICK),a
        ret

; Los verbos pintados en este paso, a la vista (VFLUSH, capa OVT)
VFLUSHC:
        ld hl,VFLUSH
        ld a,OVT_PAGE
        jp OVCALL

