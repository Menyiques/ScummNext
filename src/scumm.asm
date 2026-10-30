; ===========================================================================
;  SCUMM para ZX Spectrum Next - primer hito
;
;  Motor de aventuras SCUMM v5 para el Next. Esta version carga una
;  habitacion y el costume del protagonista desde la tarjeta SD (los ficheros
;  que genera tools/convert.py a partir de tu copia del juego), dibuja la
;  habitacion en Layer 2 con scroll, y mueve al actor con sprites por las
;  cajas de la habitacion, como el SCUMM original:
;
;  - el fondo va en Layer 2 de 320x256; el scroll horizontal es el de Layer 2
;    y cada paso de camara (8 pixeles) copia una tira nueva;
;  - los actores se dibujan con sus miembros en tiles de sprite de 16x16 (4
;    bits, u 8 si el costume es de 32 colores), escalados segun su caja,
;    tapados por el plano Z de la caja donde estan y por orden de y;
;  - los objetos de la habitacion se pintan sobre el fondo segun su estado
;    (la tecla E cambia el del objeto que hay bajo el cursor);
;  - andar, girar y animar siguen el codigo de SCUMM v5 (ver tools/model.py,
;    que hace lo mismo con la misma aritmetica y sirve para las pruebas);
;  - una maquina virtual de SCUMM v5 (vm.asm) ejecuta los scripts: los de
;    entrada y salida de cada habitacion, los locales, los de los objetos y
;    los globales (SCRIPTS.DAT), que cambian estados de objetos, variables,
;    la camara, el protagonista... y hasta de habitacion.
;
;  Ensamblar: python tools/build.py  ->  build/scumm.nex
; ===========================================================================

        DEVICE ZXSPECTRUMNEXT

; --- memoria -----------------------------------------------------------------
; $0000-$3FFF  codigo (banco 0, paginas 0 y 1); la ROM solo un momento, para
;              las llamadas de esxDOS
; $4000-$5FFF  MMU2: pagina META de la habitacion (cabecera, paleta, cajas,
;              matriz, tabla de tiras). La interrupcion la cambia un momento
;              para escribir en Layer 2.
; $6000-$7FFF  MMU3: SPRBUF, tiles de los actores (64 de 4 bits; los de 8 bits, 31,
;              en SPRB_PAGE: esa se pone aqui mientras se compone un actor de 32 colores)
; $8000-$BFFF  codigo, variables y pila (banco 2)
; $C000-$DFFF  MMU6: ventana de las tiras de la habitacion
; $E000-$FFFF  MMU7: ventana compartida (costume, imagenes de objetos, scripts,
;              clases): MAP7 apunta en SHMMU7 la pagina que tiene
L2_BANK     EQU 8               ; Layer 2: paginas 16-25
L2_PAGE     EQU 16
META_PAGE   EQU 26
STRIP_PAGE  EQU 27              ; datos de la habitacion: paginas 27-77 (y detras,
STRIP_MAX   EQU 51              ; los costumes de los demas actores)
CAST_PAGE   EQU 78              ; los actores: su animacion (CASTS) y la cabecera de un costume
SPR_PAGE    EQU 79
SPRB_PAGE   EQU 223             ; los tiles de 8 bits (costumes de 32 colores): huecos 32-62
SPR8_BYTES  EQU 7936            ; (el 63 es del cursor y del medidor)
COST_PAGE   EQU 80              ; costume del protagonista: paginas 80-82 (24 KB)
COST_MAX    EQU 3
COST_CACHE  EQU 16              ; costumes de los demas, como mucho, por habitacion
                                ; scripts globales: 2,3,6,7,8,9,12 y 83-91 (SPAGES)
                                ; clases de los objetos: pagina 13

META        EQU $4000
SCALT       EQU META+544
BOXES       EQU META+640
SPRBUF      EQU $6000

ISR_JP      EQU $BBBB           ; JP ISR
IM2_T       EQU $BC00           ; 257 bytes de $BB
STACK       EQU $C000           ; la pila: de $BE00 a $BFFF
MUBUF       EQU $BD00           ; la musica que va a sonar (255, desde MUBUF+1: el primero es
                                ; de la tabla de IM2, $FF en ZEsarUX; MUFILL la llena)
STACK_LOW   EQU MUBUF+256
STACK_FILL  EQU $A5             ; (lo que no ha usado nunca la pila)

ROOM_Y0     EQU 44              ; linea de Layer 2 donde empieza la habitacion
ISR_LINE    EQU 216             ; la interrupcion: debajo de todo lo que se ve

; Llamar a una rutina de una capa (OVT u OVU) pasandole A y HL
OTCALL  MACRO rutina
        ld (OVA),a
        ld (OVHL),hl
        ld hl,rutina
        ld a,OVT_PAGE
        call OVCALLR
        ENDM
PMARK   MACRO parte
        IFDEF PROF
        push af
        ld a,parte
        ld (PCUR),a
        pop af
        ENDIF
        ENDM
OKCALL  MACRO rutina
        ld (OVA),a
        ld (OVHL),hl
        ld hl,rutina
        ld a,OVK_PAGE
        call OVCALLR
        ENDM
OUCALL  MACRO rutina
        ld (OVA),a
        ld (OVHL),hl
        ld hl,rutina
        ld a,OVU_PAGE
        call OVCALLR
        ENDM
CMAXW       EQU 8
CMAXH       EQU 8
NSPR_ACTOR  EQU 64              ; sprites de los actores: 0..63
SPR_BYTES   EQU $2000           ; patrones de 4 bits de los actores (SPRBUF, SPR_PAGE)
PAL8        EQU 208             ; colores de sprite de un costume de 32 (208..239)
ACTOR_BANK  EQU 1               ; sin maquina virtual (con ella, el actor n usa el banco n)
CURSOR_BANK EQU 15
CURSOR_SPR  EQU 127
CURSOR_PAT  EQU 127
METER_SPR   EQU 126             ; el medidor de tiempos (CAPS + 2): sprite y patron
METER_PAT   EQU 126
INVALID     EQU 255
CAM_FOLLOW  EQU 1
CAM_NORMAL  EQU 2
CAM_PAN     EQU 3

; ===========================================================================
        ORG $8000
START:
        di
        ld sp,STACK
        ld hl,STACK_LOW             ; la pila sin usar, para medirla (nexttest.py)
        ld de,STACK_LOW+1
        ld bc,STACK-STACK_LOW-17
        ld (hl),STACK_FILL
        ldir
        nextreg $50,0               ; el codigo del banco 0 en $0000
        nextreg $51,1
        nextreg $52,META_PAGE
        nextreg $53,SPR_PAGE
        ld a,META_PAGE
        ld (SHMMU2),a
        ld hl,F_BOOT                ; los registros, el cursor y las dos pantallas
        ld a,OVF_PAGE               ; (capa OVF: solo al arrancar)
        call OVCALL
        ; IM2 con la interrupcion de linea
        ld hl,IM2_T
        ld (hl),ISR_JP&$FF
        ld de,IM2_T+1
        ld bc,256
        ldir
        ld a,$C3
        ld (ISR_JP),a
        ld hl,ISR
        ld (ISR_JP+1),hl
        ld a,IM2_T>>8
        ld i,a
        im 2
        ; el juego (si hay varios, el que se elija: capa OVS)
        ld hl,G_SELECT
        ld a,OVS_PAGE
        call OVCALL
        jp c,FAIL
        call GAMEINIT
        jp c,FAIL
        nextreg $22,%00000110       ; interrupcion de linea, sin la del ULA
        ei
        IFDEF MTBUILD
        ld hl,MUSTEST               ; (la prueba de la musica: en su pagina, no vuelve)
        ld a,MT_PAGE
        jp OVCALL
        ENDIF

; --- bucle principal -------------------------------------------------------
MAIN:
        ld a,(TMODE)
        or a
        jp nz,TESTLOOP
        ld a,(UPLOAD)               ; espera a que se suba el paso anterior
        or a
        jr nz,MAIN
        call MUSPOLLC               ; (la musica del CD, en los ratos libres)
        ; Un paso cada TICKV imagenes (lo que pide el juego: VMTICK; DUE: cuando
        ; toca el siguiente). Si no da abasto, el juego va algo mas lento.
        ld a,(TICKV)
        ld c,a
        ld a,(FRAMES)
        ld hl,DUE
        sub (hl)                    ; A = imagenes que hace que tocaba
        jp p,.due
        add a,c                     ; aun no toca
        jr c,MAIN
        ld a,(FRAMES)               ; (muy lejos: algo largo; la cuenta, desde ahora)
        ld (DUE),a
        xor a
.due:   ld b,a
        ld a,(DUE)
        add a,c
        ld (DUE),a
        ld a,c
        add a,a
        add a,a
        ld d,a
        ld a,b
        cp d                        ; demasiado retraso (4 pasos): no se recupera
        jr c,.late
        ld a,(FRAMES)
        add a,c
        ld (DUE),a
.late:  xor a                       ; (siempre se pintan los actores: con el
        ld (SKIPDRAW),a             ; desplazamiento suave, sin pintar se ve a saltos)
        IFNDEF MTBUILD
        ld a,(FRAMES)               ; (el medidor: cuando empieza el paso)
        ld (STEPF0),a
        ENDIF
        call PADIN                  ; el raton y la tecla o el boton de este paso
        call STEP
        jr MAIN

; El juego de la carpeta en la que se esta: sus datos y la maquina virtual desde el
; script 1 (capa OVF: F_GAMEINIT). Carry si falla.
GAMEINIT:
        ld hl,F_GAMEINIT
        ld a,OVF_PAGE
        jp OVCALL

; Otro juego (el elegido en el menu de partidas: G_PICK), al empezar el paso (capa
; OVS: G_SWITCH)
GSWITCH:
        ld hl,G_SWITCH
        ld a,OVS_PAGE
        jp OVCALL

; Un paso del motor (model.World.tick): scripts, clic, andar, camara, dibujo,
; animacion
STEP:
        PMARK 0
        IFDEF PROF
        ld hl,(PSTEPS)
        inc hl
        ld (PSTEPS),hl
        ENDIF
        ld a,(VMON)                 ; (las pruebas del motor van sin scripts)
        or a
        jp z,.novm
        ld a,(RESTARTREQ)           ; systemOps 1 del paso anterior: desde el principio
        or a
        call nz,RESTART
        ld a,(GAMEREQ)              ; otro juego (menu de partidas)
        or a
        call nz,GSWITCH
        call VMTICK                 ; relojes, texto y esperas
        call STEPIN                 ; raton, tecla y boton
        PMARK 1
        ld a,(HAVEMSG)
        ld l,a
        ld h,0
        ld (VARS+2*VAR_HAVE_MSG),hl
        ld a,(CURROOM)
        or a
        jr z,.r1
        ld hl,(CAM_CUR)
        ld (VARS+2*VAR_CAMERA_POS_X),hl
.r1:    call RUNALL
        ld hl,U_CHECKEXEC
        call OVUCALL
        ld hl,U_CHECKSENT
        call OVUCALL
        PMARK 2
        ld a,(CURROOM)
        or a
        jp z,.room0
        ld a,(TCLICK)               ; andar directo (sin script de verbos), si el
        cp 1                        ; protagonista esta aqui
        jr nz,.wall
        ld hl,(VARS+2*VAR_VERB_SCRIPT)
        ld a,h
        or l
        jr nz,.wall
        ld a,(VARS+2*VAR_EGO+1)
        or a
        jr nz,.wall
        ld a,(VARS+2*VAR_EGO)
        call EGOHERE
        jr nc,.wall
        ld a,(VARS+2*VAR_EGO)
        call ACTLOAD
        call .click
.wall:  ld hl,K_WALKALL             ; walkActors: todos los de la habitacion
        call OVKCALL
        PMARK 3
        ld hl,(VARS+2*VAR_CAMERA_MIN_X)
        ld (CAM_MIN),hl
        ld hl,(VARS+2*VAR_CAMERA_MAX_X)
        ld (CAM_MAX),hl
        call FLUSHOBJ                ; las tiras de los objetos que han cambiado
        jr .cam
.novm:  call FLUSHOBJ
        ld ix,ACTOR
        ld a,(TCLICK)
        cp 1
        call z,.click
        ld ix,ACTOR
        call WALK
.cam:   ld hl,(ACTOR+A_X)           ; la camara sigue a FOLLOWS
        ld a,(VMON)
        or a
        call nz,FOLLOWX
        ld (CFX),hl
        ld hl,(CAM_CUR)
        ld (CAMOLD),hl
        ld ix,ACTOR
        call CAMMOVE
        ld a,(VMON)
        or a
        jr z,.comp
        ld hl,(CAM_CUR)
        ld de,(CAMOLD)
        or a
        sbc hl,de
        call nz,SCROLLSCR
        call CAMTALK
        PMARK 4
        call UITEXT
        call FXSTEPC                ; ciclos de color y temblor
        PMARK 5
.comp:  ld a,(VMON)                 ; sin maquina virtual: el actor solo
        or a
        jr nz,.cast
        call EGOCOMP
        ld ix,ACTOR
        call ANIMATE
        jr .up
.cast:  ld hl,K_CASTDRAW            ; todos los actores de la habitacion
        call OVKCALL
        PMARK 6
        call FXINC                  ; fadeIn (si se entro en una habitacion)
        call SNDPROCA               ; playActorSounds y processSound
        PMARK 7
.up:    ld hl,(CAM_CUR)
        ld (CAMLAST),hl
.upl:   call VFLUSHC                ; los verbos de este paso, a la vista
        ld a,1
        ld (UPLOAD),a
        ret
.room0: call UITEXT
        call FXSTEPC
        call HIDEACT
        call FXINC
        call SNDPROC
        call ACTSYNC
        jr .upl
; el actor de ACTOR anda hasta donde se ha pulsado
.click: ld hl,(TCX)
        ld (SWX),hl
        ld hl,(TCY)
        ld (SWY),hl
        ld hl,-1
        ld (SWD),hl
        jp STARTWALK

; La musica del CD: una pagina mas del anillo, si hace falta (capa OVA)
MUSPOLLC:
        ld hl,MUSPOLL
        ld a,OVA_PAGE
        jp OVCALL

; processSound: la cola de sonidos del paso (al final de cada paso); en una
; habitacion, antes los sonidos de los actores (SNDPROCA)
SNDPROCA:
        ld hl,SN_ACTORS
        jr SNDPA
SNDPROC:
        ld hl,SN_PROCESS
SNDPA:  ld a,OVA_PAGE
        jp OVCALL

; --- modo prueba ---------------------------------------------------------------
; TREQ = 1: un paso (con clic si TCLICK, en TCX/TCY de la habitacion)
; TREQ = 2: entra en la habitacion TROOM (solo el motor, sin scripts)
; TREQ = 3: llama a una rutina (TFUNC) con los datos de TARGS
; TREQ = 4: estado TSTATE para el objeto TOBJ (el indice en la habitacion)
; TREQ = 5: carga el costume TCOST (despues, TREQ = 2 para verlo)
; TREQ = 6: maquina virtual (y pantalla) desde cero y el protagonista en TROOM
; TREQ = 7: startScene(TROOM) con sus scripts (salida de la anterior)
; TREQ = 8: el protagonista a la habitacion TROOM (y la camara le sigue)
; TREQ = 9: la maquina virtual (y pantalla) desde cero y el script 1 (el arranque)
; TREQ = 10 / 11: guardar / cargar la partida del hueco TROOM (TRES = 1 si falla)
; En cada paso: TMX/TMY (raton en la pantalla), TBUT (boton 1 o 2) y TKEY (tecla)
TESTLOOP:
        ld a,(TREQ)
        or a
        jr z,TESTLOOP
        ld b,a
        xor a
        ld (TREQ),a
        ld a,b
        cp 1
        jr nz,.t2
        ld hl,(TMX)                 ; el raton y lo que se pulsa en este paso
        ld (UMX),hl
        ld hl,(TMY)
        ld (UMY),hl
        ld a,(TBUT)
        ld (TBUTV),a
        ld a,(TKEY)
        ld (TKEYV),a
        call STEP
.up:    ld a,(UPLOAD)               ; espera a la interrupcion
        or a
        jr nz,.up
        call MUSPOLLC
        jp .done
.t2:    cp 2
        jr nz,.t3
        xor a                       ; solo el motor: sin scripts
        ld (VMON),a
        call VMINIT                 ; (los estados de OBJ.DAT, sin lo que hizo el arranque)
        ld a,200                    ; la habitacion entera
        ld (MAINH),a
        ld a,(TROOM)
        call LOADROOM
        jp .done
.t3:    cp 3
        jr nz,.t4
        ld hl,F_TESTFUNC            ; (capa OVF)
        ld a,OVF_PAGE
        call OVCALL
        jp .done
.t4:    cp 4
        jr nz,.t5
        ld a,(TOBJ)
        call OBJPTR
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld a,(TSTATE)
        call PUTSTATE
        call FLUSHOBJ
        jr .done
.t5:    cp 5
        jr nz,.t6
        di
        ld a,(TCOST)
        call LOADCOST
        ei
        jr .done
.t6:    ld c,a
        ld a,1                      ; 6 a 9: con la maquina virtual
        ld (VMON),a
        ld a,c
        cp 6
        jr nz,.t7
        call L2CLEAR                ; 6: desde cero (la pantalla tambien), y el
        xor a                       ; protagonista en TROOM
        ld (CURROOM),a
        call VMINIT
        ld a,(TROOM)
        call ENTEREGO
        jr .done
.t7:    cp 7
        jr nz,.t8
        ld hl,0                     ; 7: a la habitacion TROOM (startScene)
        ld (SCOBJ),hl
        ld a,(TROOM)
        call STARTSCENE
        jr .done
.t8:    cp 8
        jr nz,.t9
        ld a,(TROOM)                ; 8: el protagonista a TROOM
        call ENTEREGO
        jr .done
.t9:    cp 9
        jr nz,.t10
        call L2CLEAR                ; 9: el arranque (script 1), con la pantalla en negro
        call BOOT
        jr .done
.t10:   ld hl,T_SAVE                ; 10: guardar la partida en el hueco TROOM
        cp 10
        jr z,.sv
        ld hl,T_LOAD                ; 11: cargar la del hueco TROOM
.sv:    ld a,OVS_PAGE
        call OVCALL
        ld a,0
        rla
        ld (TRES),a                 ; 1 si ha fallado
.done:  call VFLUSHC
        ld a,1
        ld (TDONE),a
        jp TESTLOOP

; HL >>= 3 con signo
SHR3:
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ret

; A = A mod 40
MOD40:
        cp 40
        ret c
        sub 40
        jr MOD40

; ---------------------------------------------------------------------------
; Layer 2

; Copia la tira A de la habitacion a su sitio en Layer 2 (todas sus filas)
DRAWSTRIP:
        ld bc,$FF00                 ; filas 0..255
        jr DSCORE
; Lo mismo, solo con las filas [DSY0, DSY1) (borrar un texto)
DRAWSTRIPR:
        ld bc,(DSY0)                ; C = DSY0, B = DSY1
DSCORE:
        push af                     ; filas de la habitacion: min(RH, MAINH); el resto a 0
        ld a,(MAINH)
        ld e,a                      ; E = MAINH
        ld hl,(RH)
        ld a,h
        or a
        ld a,e
        jr nz,.r1
        ld a,l
        cp e
        jr c,.r1
        ld a,e
.r1:    ld d,a                      ; D = filas
        ld a,b                      ; copia [C, min(B, filas))
        cp d
        jr c,.r2
        ld a,d
.r2:    sub c
        jr nc,.r3
        xor a
.r3:    ld (DSN),a
        ld a,c
        ld (DSA0),a
        ld a,c                      ; a 0: [max(C, filas), min(B, MAINH))
        cp d
        jr nc,.r4
        ld a,d
.r4:    ld (DSC0),a
        ld d,a
        ld a,b
        cp e
        jr c,.r5
        ld a,e
.r5:    sub d
        jr nc,.r6
        xor a
.r6:    ld (DSCLR),a
        pop af
        ld c,a
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,(STRIPT)
        add hl,de
        ld a,(hl)                   ; pagina de la tira
        add a,STRIP_PAGE
        nextreg $56,a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        ld a,c                      ; columna de Layer 2: (tira mod 40) * 8
        call MOD40
        add a,a
        add a,a
        add a,a                     ; 0..312
        ld l,a
        ld a,0
        adc a,0
        ld h,a
        ld a,l                      ; pagina = L2_PAGE + col >> 5
        srl h
        rra
        srl a
        srl a
        srl a
        srl a
        add a,L2_PAGE
        nextreg $52,a
        ld a,c
        call MOD40
        add a,a
        add a,a
        add a,a
        and 31                      ; columna dentro de la pagina
        add a,$40
        ld d,a
        pop hl
        push iy                     ; (IYL cuenta las columnas; la interrupcion no guarda IY)
        ld a,(DSN)
        or a
        jr z,.nc
        ld iyl,8
        push de
        ld a,(DSA0)                 ; desde la fila DSA0
        add hl,a
        add a,ROOM_Y0
        ld e,a
        ld (.e0+1),a
        ld a,(DSN)                  ; (de 32 filas en adelante, por el DMA; DMACP esta en
        cp 32                       ; el banco 0: no si la interrupcion llega con la ROM)
        jr c,.col
        ld a,(ROMUP)
        or a
        jr z,.dma
.col:   push hl
        ld bc,(DSN)                 ; (DSN + 1 siempre 0)
        ldir
        pop hl                      ; la columna siguiente: RH bytes despues
        ld bc,(RH)
        add hl,bc
.e0:    ld e,0
        inc d
        dec iyl
        jr nz,.col
        pop de
        jr .nc
.dma:   push hl
        ld bc,(DSN)
        call DMACP
        pop hl
        ld bc,(RH)
        add hl,bc
        ld a,(.e0+1)
        ld e,a
        inc d
        dec iyl
        jr nz,.dma
        pop de
.nc:    ld a,(DSCLR)                ; las filas de debajo de la habitacion, a 0
        or a
        jr z,.end
        ld iyl,8
        ld a,(DSC0)
        add a,ROOM_Y0
        ld (.e1+1),a
.e1:    ld e,0
        ld a,(DSCLR)
        ld b,a
        xor a
.cl:    ld (de),a
        inc e
        djnz .cl
        inc d
        dec iyl
        jr nz,.e1
.end:   pop iy
        ld a,(SHMMU6)
        nextreg $56,a
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; Toda la vista desde la tira de la izquierda
FULLDRAW:
        ld a,(CAM_SS)
        ld b,40
.lp:    push bc
        push af
        ld hl,RNS
        cp (hl)
        call c,DRAWFRESH
        pop af
        inc a
        pop bc
        djnz .lp
        ret

; Layer 2 a negro (y se ve: sin transicion a medias), y B (los verbos se pintan alli)
L2CLEAR:
        nextreg $12,L2_BANK
        xor a
        ld (HIDDEN),a
        ld b,20
        ld a,L2_PAGE
.pg:    push bc
        push af
        nextreg $52,a
        ld hl,$4000
        ld (hl),0
        ld de,$4001
        ld bc,$1FFF
        ldir
        pop af
        inc a
        cp L2_PAGE+10
        jr nz,.n
        ld a,L2B_PAGE
.n:     pop bc
        djnz .pg
        ld a,(SHMMU2)
        nextreg $52,a
        ret

; El copper: la habitacion con el scroll SCRL hasta la pantalla de verbos, y
; los verbos sin scroll (linea del copper = fila de Layer 2 - 32)
COPPERSET:
        nextreg $62,0               ; parado, direccion 0
        nextreg $61,0
        ld bc,$243B
        ld a,$60
        out (c),a
        inc b
        ld hl,(SCRL)
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
        ld a,$FF                    ; HALT
        out (c),a
        out (c),a
        nextreg $62,%11000000       ; en marcha, otra vez desde 0 en cada imagen
        ld a,(SHAKEY)               ; el temblor: Layer 2 baja SHAKEY filas
        neg
        nextreg $17,a
        ret

; Pone el scroll de Layer 2 (SCRL)
SETSCROLL:
        ld hl,(SCRL)
        ld a,l
        nextreg $16,a
        ld a,h
        nextreg $71,a
        ret

; ---------------------------------------------------------------------------
; Sprites

; Sube los tiles de los actores y sus atributos (desde SPRBUF y ATTRBUF), por DMA: los de
; 8 bits (SPRB_PAGE) desde el hueco 32 y los de 4 (SPR_PAGE, que se queda en $6000) desde
; el 0. A trozos (DMAOUTC) y sin que el CTC pare el DMA: si lo parase, despues de cada
; RETI el programa empieza una instruccion antes de que el DMA vuelva, y con muchas
; muestras (la musica y un efecto) llegaba al OUT de $303B o al DMA siguiente con la
; subida a medias: tiles con lo del paso anterior
SPRUPLOAD:
        ld a,SPRB_PAGE
        ld hl,(SPRUSD8)
        ld e,32
        call .up
        ld a,SPR_PAGE
        ld hl,(SPRUSED)
        ld e,0
        call .up
        ld bc,$303B
        xor a
        out (c),a
        ld hl,ATTRBUF
        ld bc,NSPR_ACTOR*5
        ld de,$0057
        jp DMAOUTC
.up:    ld (AUM3),a                 ; (AUM3 primero: es la que deja el CTC)
        nextreg $53,a
        ld bc,$303B
        ld a,e
        out (c),a
        ld b,h                      ; bytes de patrones
        ld c,l
        ld a,b
        or c
        ret z
        ld hl,SPRBUF
        ld de,$005B
        jp DMAOUTC

; Como DMAOUT, a trozos de 256: el CTC no para el DMA (NR $CD a 0) y lo que pida espera
; al final del trozo, menos de una muestra
DMAOUTC:
        ld a,b
        or a
        jr z,.last
        push bc
        push hl
        ld bc,256
        call DMAOUT
        pop hl
        pop bc
        inc h
        dec b
        jr DMAOUTC
.last:  or c
        ret z
        jp DMAOUT

; HL = el byte de ZOBTOP del objeto de indice A de la habitacion, A = su bit (cambia C)
ZTOPAD: ld c,a
        and 7
        ld hl,BITMASKS
        add hl,a
        ld a,c
        ld c,(hl)
        rrca
        rrca
        rrca
        and $1F
        add a,ZOBTOP & $FF
        ld l,a
        ld h,ZOBTOP >> 8
        ld a,c
        ret

; DMA (zxnDMA) de BC bytes desde HL al puerto DE
DMAOUT:
        xor a                       ; (de memoria a un puerto: DMACP, todo otra vez)
        ld (DMAMEM),a
        ld (DMASRC),hl
        ld (DMALEN),bc
        ld (DMADST),de
        ld hl,DMAPROG
        ld b,DMAPLEN
        ld c,$6B
        otir
        ret
DMAPROG:
        db $83                      ; para el DMA
        db %01111101                ; WR0: de A a B, direccion y longitud
DMASRC: dw 0
DMALEN: dw 0
        db %01010100                ; WR1: A es memoria y avanza
        db %00000010
        db %01101000                ; WR2: B es un puerto fijo
        db %00000010
        db %10101101                ; WR4: continuo, direccion de B
DMADST: dw 0
        db %10000010                ; WR5
        db $CF                      ; carga
        db $87                      ; en marcha
DMAPLEN EQU $-DMAPROG
DMAMEM: db 0                        ; 1: el DMA sigue de memoria a memoria (DMACP; DMAOUT
                                    ; lo cambia, tambien desde la interrupcion con la ROM)


; Oculta todos los sprites
HIDESPR:
        IFNDEF MTBUILD
        ld a,$FF                    ; (sin desplazamiento suave hasta el paso siguiente,
        ld (SMJ),a                  ; que sale de golpe)
        ld (SMSCR+1),a
        ENDIF
        ld bc,$303B
        xor a
        out (c),a
        ld e,128
.lp:    ld bc,$57
        xor a
        out (c),a
        out (c),a
        out (c),a
        ld a,$40
        out (c),a
        xor a
        out (c),a
        dec e
        jr nz,.lp
        ret

; Atributos del cursor (o escondido en modo prueba)
CURSORSPR:
        ld bc,$303B
        ld a,CURSOR_SPR
        out (c),a
        ld bc,$57
        ld a,(TMODE)
        or a
        jr nz,.hide
        ld a,(GMENUON)              ; (en el menu de juegos)
        or a
        jr nz,.show
        ld a,(VMON)
        or a
        jr z,.show
        ld hl,(VARS+2*VAR_VERB_SCRIPT)
        ld a,h
        or l
        jr z,.show
        ld hl,(CURSTATE)
        bit 7,h
        jr nz,.hide
        ld a,h
        or l
        jr z,.hide
.show:
        ld hl,(CURX)
        ld de,7
        or a
        sbc hl,de
        out (c),l
        ld de,(CURY)
        ld a,e
        sub 7
        out (c),a
        ld a,h
        and 1
        or CURSOR_BANK<<4
        out (c),a
        ld a,$C0|(CURSOR_PAT>>1)
        out (c),a
        ld a,$80|((CURSOR_PAT&1)<<6)
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

; ---------------------------------------------------------------------------
; Interrupcion de linea (despues de la habitacion): la tira nueva, el scroll
; y los sprites del paso preparado; despues el cursor.
ISR:
        push af
        push bc
        push de
        push hl
        ld bc,$243B                 ; las ventanas que tuviera el programa
        ld a,$52
        out (c),a
        inc b
        in a,(c)
        ld (ISRM2),a
        dec b
        ld a,$56
        out (c),a
        inc b
        in a,(c)
        ld (ISRM6),a
        dec b
        ld a,$57
        out (c),a
        inc b
        in a,(c)
        ld (ISRM7),a
        nextreg $C8,%00000010       ; (IM2 de hardware: la de linea, atendida)
        ei                          ; el CTC (los efectos) puede interrumpir esto: un RETI
        call RETINEST               ; le dice a la cadena de prioridades que ya puede
        ld hl,FRAMES
        inc (hl)
        ld a,SM_PAGE                ; la musica, del anillo a MUBUF (capa SM)
        nextreg $57,a
        call MUFILL
        IFDEF PROF
        ld a,(ROMUP)                ; (las medidas estan en el banco 0)
        or a
        call z,PSAMPLE
        ENDIF
        IFDEF MTBUILD
        call MTFRAME
        ENDIF
        ld a,(UPLOAD)
        or a
        jr z,.noup
        IFNDEF MTBUILD
        ld a,(TMODE)                ; en modo normal, el desplazamiento suave (capa SM)
        or a
        jr nz,.old
        ld a,SM_PAGE
        nextreg $57,a
        call SM_UPLOAD
        jr .upd
.old:
        ENDIF
        ld a,(PSTRIP)
        cp $FF
        call nz,DRAWSTRIP
        ld a,$FF
        ld (PSTRIP),a
        di                          ; (el copper va por los puertos $243B / $253B)
        call COPPERSET
        ei
        call SPRUPLOAD
.upd:   xor a
        ld (UPLOAD),a

.noup:
        IFNDEF MTBUILD
        ld a,(TMODE)                ; (cada imagen, hasta el final del paso)
        or a
        jr nz,.nosm
        ld a,SM_PAGE
        nextreg $57,a
        call SM_FRAME
.nosm:
        ENDIF
        ld a,(ROMUP)                ; raton, teclas y botones: usan el banco 0
        or a                        ; (CPS16, KEYSCAN), que no esta mientras esxDOS
        jr nz,.rom                  ; lee con la ROM puesta (y con interrupciones)
        ld a,(TMODE)
        or a
        call z,INPUT
        call KEYSCAN
.rom:   call CURSORSPR
        di
        ld a,(ISRM2)
        nextreg $52,a
        ld a,(ISRM6)
        nextreg $56,a
        ld a,(ISRM7)
        nextreg $57,a
        pop hl
        pop de
        pop bc
        pop af
        ei
        reti
RETINEST:
        reti

; ---------------------------------------------------------------------------
; Sonido (capa OVA): las interrupciones del CTC, en la memoria que nunca se pagina
; (asi siguen mientras se lee la SD). La pagina de la muestra se pone un momento en
; $6000 y despues se deja la que toca (AUM3: la de los sprites, o la 11 de esxDOS).

; CTC 0 y CTC 2: una muestra del efecto de su canal (pueden sonar dos a la vez, cada
; uno a su ritmo). El DAC A y D lleva la suma de las ultimas muestras de los dos (AUMIX)
SNDCH   MACRO pg, ptr, len, smp, ctc, ack, cnt, lpg, lpt, lln
        push af
        push hl
        IFDEF MTSFX
        ld hl,(cnt)
        inc hl
        ld (cnt),hl
        ENDIF
        ld a,(pg)
        nextreg $53,a
        ld hl,(ptr)
        ld a,(hl)
        ld (smp),a
        ld a,(AUM3)
        nextreg $53,a
        inc hl
        bit 7,h
        jr z,.p
        ld h,$60                    ; la pagina siguiente
        ld a,(pg)
        inc a
        ld (pg),a
.p:     ld (ptr),hl
        ld hl,(len)
        dec hl
        ld (len),hl
        ld a,h
        or l
        jr nz,.x
        ld hl,(lln)                 ; se acabo: si da vueltas, otra vez desde su bucle
        ld a,h
        or l
        jr z,.e
        ld (len),hl
        ld hl,(lpt)
        ld (ptr),hl
        ld a,(lpg)
        ld (pg),a
        jr .x
.e:     push bc                     ; si no, su CTC parado y su muestra, silencio
        ld bc,ctc
        ld a,%00000011
        out (c),a
        pop bc
        ld a,$80
        ld (smp),a
.x:     call AUMIX
        nextreg $C9,ack
        pop hl
        pop af
        ei
        reti
        ENDM

SNDISR:
        SNDCH AUPG, AUPTR, AULEN, AUS1, $183B, %00000001, MTSN, AULPG, AULPT, AULLN
SNDISR2:
        SNDCH AUPG2, AUPTR2, AULEN2, AUS2, $1A3B, %00000100, MTSN2, AULPG2, AULPT2, AULLN2

; El DAC A y D = AUS1 + AUS2 (sin signo, centradas en $80: se suman con signo y se
; recorta; con un solo efecto, el otro es $80 y sale igual que antes). Toca A y L
AUMIX:
        ld a,(AUS2)
        xor $80
        ld l,a
        ld a,(AUS1)
        xor $80
        add a,l
        jp po,.ok                   ; (P/V: desborde)
        ld a,l                      ; desborda: los dos tienen el signo de L
        rla
        ld a,$7F
        adc a,0                     ; $7F o, si es negativo, $80
.ok:    xor $80
        nextreg $2D,a
        ret

; CTC 1: una muestra de la musica (DAC B y C), de MUBUF (MUFILL va por delante)
MUSISR:
        push af
MURD:   ld a,(MUBUF+1)              ; (el byte bajo de la direccion: por donde va)
        nextreg $2C,a
        nextreg $2E,a
        IFDEF MTBUILD
        push hl
        ld hl,(MTCNT)
        inc hl
        ld (MTCNT),hl
        pop hl
        ENDIF
        ld a,(MURD+1)
        inc a
        jr nz,.k
        inc a                       ; (el 0 no)
.k:     ld (MURD+1),a
        nextreg $C9,%00000010
        pop af
        ei
        reti

AUM3:   db SPR_PAGE
SPRCUR: db SPR_PAGE                 ; la pagina de SPRBUF (SPRB_PAGE mientras se compone un
                                    ; actor de 32 colores, K_COMP): la vuelven a poner
                                    ; ZUNMAP y FILESOFF
SPRUSD8: dw 0                       ; bytes de patrones de 8 bits de este paso (en SPRB_PAGE)
AUPG:   db 0                        ; el efecto del canal 1 (CTC 0): pagina, posicion en
AUPTR:  dw $6000                    ; $6000, lo que le queda, su numero y su ultima
AULEN:  dw 0                        ; muestra ($80: nada)
AUSND:  db 0
AUS1:   db $80
AULPG:  db 0                        ; su bucle (los de AdLib que dan vueltas): pagina,
AULPT:  dw $6000                    ; posicion y largo (0: no da vueltas)
AULLN:  dw 0
AUPG2:  db 0                        ; y el del canal 2 (CTC 2)
AUPTR2: dw $6000
AULEN2: dw 0
AUSND2: db 0
AUS2:   db $80
AULPG2: db 0
AULPT2: dw $6000
AULLN2: dw 0
SNDOK:  db 0                        ; SOUNDS.DAT cargado
MUPG:   db MUS_PAGE                 ; la musica: por donde va,
MUPTR:  dw $6000
MUAV:   db 0                        ; paginas del anillo llenas y sin oir
MUPLAY: db 0                        ; el CTC 1 en marcha
MUWB:   db 1                        ; (MUFILL) por donde se escribe en MUBUF (1..255)

; ---------------------------------------------------------------------------
; Entrada: raton Kempston y teclado (cada frame, desde la interrupcion)
INPUT:
        ; raton
        ld bc,$FBDF
        in a,(c)
        ld hl,MOUSEX
        ld d,(hl)
        ld (hl),a
        sub d                       ; dx
        ld e,a
        ld bc,$FFDF
        in a,(c)
        ld hl,MOUSEY
        ld d,(hl)
        ld (hl),a
        sub d                       ; dy (hacia arriba)
        neg
        ld d,a
        ld a,(MOUSEON)              ; la primera lectura solo es referencia
        or a
        jr nz,.mv
        inc a
        ld (MOUSEON),a
        ld de,0
.mv:    push de
        ld a,e
        call ADDX                   ; (cambia DE)
        pop de
        ld a,d
        call ADDY
        ; teclado: CAPS + 5 6 7 8 mueven el cursor (las teclas, en KEYSCAN)
        ld bc,$FEFE
        in a,(c)
        rrca
        ret c
        ld bc,$EFFE                 ; 7 (arriba)
        in a,(c)
        bit 3,a
        ld a,-2
        call z,ADDY
        ld bc,$EFFE                 ; 6 (abajo)
        in a,(c)
        bit 4,a
        ld a,2
        call z,ADDY
        ld bc,$F7FE                 ; 5 (izquierda)
        in a,(c)
        bit 4,a
        ld a,-2
        call z,ADDX
        ld bc,$EFFE                 ; 8 (derecha)
        in a,(c)
        bit 2,a
        ld a,2
        call z,ADDX
        ret

; CURX += A (con signo), acotado a 0..319
ADDX:
        ld hl,(CURX)
        ld c,a
        rla
        sbc a,a
        ld b,a
        add hl,bc
        bit 7,h
        jr z,.n
        ld hl,0
.n:     ld de,320
        call CPS16
        jr c,.ok
        ld hl,319
.ok:    ld (CURX),hl
        ret

; CURY += A, acotado a la pantalla de SCUMM (200 lineas)
ADDY:
        ld hl,(CURY)
        ld c,a
        rla
        sbc a,a
        ld b,a
        add hl,bc
        ld de,ROOM_Y0
        call CPS16
        jr nc,.n
        ex de,hl
.n:     ld de,ROOM_Y0+199
        call CPS16
        jr c,.ok
        jr z,.ok
        ex de,hl
.ok:    ld (CURY),hl
        ret

; ---------------------------------------------------------------------------
; Ficheros (esxDOS: los punteros van en IX)

; Abre el fichero (HL = nombre). A = manejador; carry si falla.
FOPEN:
        push ix
        push hl
        pop ix
        ld a,'*'
        ld b,1
        call ROMIN
        rst 8
        db $9A
        call ROMOUT
        pop ix
        ret

; Lee BC bytes en HL. BC = leidos.
FREAD:
        push ix
        push hl
        pop ix
        call ROMIN
        rst 8
        db $9D
        call ROMOUT
        pop ix
        ret

FCLOSE:
        call ROMIN
        rst 8
        db $9B
        jp ROMOUT

; La llamada de esxDOS ESXN (con A, B, IX como pida); vuelven A y los flags
ESXCALL:
        call ROMIN
        rst 8
ESXN:   db 0
        jp ROMOUT

; Paginas de siempre en $4000-$7FFF para esxDOS, y las nuestras despues. Se puede
; con las interrupciones puestas: AUM3 va primero al entrar y al salir, para que
; las del CTC (el sonido) dejen en $6000 la pagina que toca.
FILESON:
        push af
        ld a,11
        ld (AUM3),a
        nextreg $53,11
        nextreg $52,10
        pop af
        ret
FILESOFF:
        push af
        ld a,(SPRCUR)               ; (la de los sprites que se estan componiendo)
        ld (AUM3),a
        nextreg $53,a
        ld a,(SHMMU2)
        nextreg $52,a
        pop af
        ret

; Carga el fichero HL en paginas seguidas desde la A (como mucho B).
; carry si falla.
; Con las interrupciones puestas, entre pagina y pagina la musica lee lo suyo
; (MUSPOLL), para que no se acabe el anillo mientras se carga una habitacion.
LOADPAGES:
        ld (LPAGE),a
        ld a,b
        ld (LPMAX),a
        call FILESON                ; esxDOS con los bancos 5 en su sitio
        call FOPEN
        jr c,.err
        ld (LHANDLE),a
.pg:    ld a,(LPAGE)
        call MAP7
        call FILESON
        ld a,(LHANDLE)
        ld hl,$E000
        ld bc,$2000
        call FREAD
        jr c,.cerr
        call FILESOFF
        ld a,i                      ; (P/V = IFF2: solo si hay interrupciones)
        jp po,.nm
        push bc
        call MUSPOLLC
        pop bc
.nm:    ld hl,LPAGE
        inc (hl)
        ld hl,LPMAX
        dec (hl)
        jr z,.end
        ld a,b                      ; pagina incompleta: fin del fichero
        cp $20
        jr z,.pg
.end:   call FILESON
        ld a,(LHANDLE)
        call FCLOSE
        or a
        jp FILESOFF
.cerr:  ld a,(LHANDLE)
        call FCLOSE
.err:   scf
        jp FILESOFF

; Nombre "Xnnn.DAT" en NAMEBUF (A = numero, C = letra)
MKNAME:
        ld hl,NAMEBUF
        ld (hl),c
        inc hl
        ld c,'0'-1
.c:     inc c
        sub 100
        jr nc,.c
        add a,100
        ld (hl),c
        inc hl
        ld c,'0'-1
.d:     inc c
        sub 10
        jr nc,.d
        add a,10+'0'
        ld (hl),c
        inc hl
        ld (hl),a
        ret

; Carga el costume A (el del protagonista)
LOADCOST:
        ld (ECOST),a
        ld c,'C'
        call MKNAME
        ld hl,NAMEBUF
        ld a,COST_PAGE
        ld b,COST_MAX
        call LOADPAGES
        ret c
        call COSTHDR
        or a
        ret

; Carga la habitacion A y pone al actor
; A = la habitacion de verdad de la A (de 128 en adelante: pseudoRoom, RESMAP)
ROOMRES:
        cp $80
        ret c
        push hl
        and $7F
        ld l,a
        ld a,(SHMMU7)
        push af
        ld a,UIP
        call MAP7
        ld a,l
        ld hl,RESMAP
        add hl,a
        ld l,(hl)
        pop af
        call MAP7
        ld a,l
        pop hl
        ret

LOADROOM:
        ld (CURROOM),a
        nextreg $69,0               ; Layer 2 apagada mientras carga
        ld a,i                      ; (los sprites: la interrupcion mueve el cursor)
        push af
        di
        call HIDESPR
        pop af
        jp po,.h
        ei
.h:
        ld a,(CURROOM)
        call ROOMRES                ; (de una pseudohabitacion, la de verdad)
        ld c,'R'
        call MKNAME
        ld hl,NAMEBUF
        ld a,META_PAGE
        ld b,1+STRIP_MAX
        call LOADPAGES
        jr nc,.ok
        ld a,(TMODE)
        or a
        jr nz,.fail
        ei
        scf
        ret
.fail:  scf
        ret
.ok:    ld hl,(META+4)              ; cabecera
        ld (RW),hl
        ld hl,(META+6)
        ld (RH),hl
        ld a,(META+8)
        ld (RNZ),a
        ld a,(META+9)
        ld (NBOXES),a
        ld hl,(META+14)
        ld a,l
        ld (RNS),a
        ld hl,(META+20)
        ld de,META
        add hl,de
        ld (MATRIX),hl
        ld hl,(META+24)
        add hl,de
        ld (STRIPT),hl
        ld hl,(META+26)
        add hl,de
        ld (PRISTAB),hl
        ld hl,(META+28)
        add hl,de
        ld (OBJT),hl
        ld a,(META+30)
        ld (NOBJ),a
        ld hl,(META+16)
        ld (RREC),hl
        ld hl,(RW)
        ld de,160
        or a
        sbc hl,de
        ld (CAM_MAX),hl
        ld hl,160
        ld (CAM_MIN),hl
        ld a,CAM_FOLLOW
        ld (CAM_MODE),a
        ; la paleta de Layer 2 (las de los actores las pone COMPOSE)
        nextreg $43,%00010000
        nextreg $40,0
        ld hl,META+32
        ld b,0
.pal:   ld a,(hl)
        inc hl
        nextreg $44,a
        ld a,(hl)
        inc hl
        nextreg $44,a
        djnz .pal
        ld hl,F_ROOMINIT            ; los ciclos de color, desde cero
        ld a,OVF_PAGE
        call OVCALL
        ld hl,RSTAMP                ; (las cajas de los demas actores, otra vez)
        inc (hl)
        ld hl,(CGEN)                ; (y los dibujos guardados ya no valen)
        inc hl
        ld (CGEN),hl
        xor a                       ; los costumes de los demas: detras de la habitacion
        ld (CCN),a
        ld a,(META+31)
        add a,STRIP_PAGE
        ld (CCNEXT),a
        ld a,(VMON)
        or a
        call z,L2CLEAR
        call CLEARDIRTY
        call RECOMPALL              ; los objetos sobre el fondo
        ld ix,ACTOR
        ld a,(VMON)
        or a
        jr nz,.vmcam
        ld (ACTN),a                 ; sin maquina virtual: el actor solo, en el punto de inicio
        call ACTINIT
        ld hl,(META+10)
        ld (PAX),hl
        ld hl,(META+12)
        ld (PAY),hl
        call PUTACTOR
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        call CAMSETAT
        jr .draw
.vmcam: ld hl,160                   ; SCUMM: la camara quieta en 160
        ld (CAM_CUR),hl
        ld (CAM_DEST),hl
        ld a,CAM_NORMAL
        ld (CAM_MODE),a
        xor a
        ld (CAM_MTA),a
        call CAMMOVED
        call NARROW
.draw:  call FULLDRAW
        ld a,(CAM_SS)
        ld (L2SS),a
        ld a,(CAM_SS)
        call MOD40
        add a,a
        add a,a
        ld l,a
        ld h,0
        add hl,hl
        ld (SCRL),hl
        ld a,$FF
        ld (PSTRIP),a
        ld a,(VMON)
        or a
        jr nz,.vmspr
        call EGOCOMP
        ld hl,ROOM_Y0+72            ; el cursor, en medio
        ld (CURY),hl
        ld hl,160
        ld (CURX),hl
        jr .spr
.vmspr: call HIDEACT
.spr:   di                          ; (el copper y los sprites: tambien los usa la
        call COPPERSET              ; interrupcion de linea)
        call SPRUPLOAD
        xor a
        ld (UPLOAD),a
        ld a,ISR_LINE               ; la interrupcion, debajo de todo
        nextreg $23,a
        nextreg $22,%00000110
        nextreg $69,%10000000       ; Layer 2 visible
        ld a,(FRAMES)
        ld (DUE),a
        xor a
        ld (SKIPN),a
        ei
        or a
        ret

; HL = lista de costumes de GAME.DAT, C = cuantos
COSTLIST:
        ld a,(GAMEBUF+6)
        ld hl,GAMEBUF+7
        add hl,a
        ld c,(hl)
        inc hl
        ret

; Sin maquina virtual: el actor solo (banco ACTOR_BANK, sin elevacion)
EGOCOMP:
        call HIDEACT
        ld a,ACTOR_BANK
        ld (CABANK),a
        ld hl,0
        ld (CELEV),hl
        ld ix,ACTOR
        ld hl,K_COMP                ; (COMPOSE con sus tiles en su pagina)
        jp OVKCALL

; Error: borde rojo y quieto
FAIL:
        di
        nextreg $68,0               ; ULA visible para el borde
        ld a,2
        out ($FE),a
.l:     jr .l

        INCLUDE "compose.asm"
        INCLUDE "paintprep.asm"
        INCLUDE "uidata.asm"
        INCLUDE "vmdata.asm"
        IFDEF MTBUILD
        INCLUDE "mustest.asm"
        ENDIF

; ---------------------------------------------------------------------------
; Variables
TMODE:  db 0
VMON:   db 1
TMX:    dw 160
TMY:    dw 100
TBUT:   db 0
TKEY:   db 0
TBUTV:  db 0
TKEYV:  db 0
CFX:    dw 0
CAMOLD: dw 0
DSY0:   db 0                        ; filas de DRAWSTRIPR (DSY1 detras)
DSY1:   db 0
DSN:    dw 0                        ; (el alto, siempre 0)
DSA0:   db 0
DSC0:   db 0
DSCLR:  db 0
ISRM2:  db 0
ISRM6:  db 0
ISRM7:  db 0
TREQ:   db 0
TDONE:  db 0
TFUNC:  db 0
TARGS:  ds 16
TRES:   ds 8
TROOM:  db 0
TOBJ:   db 0
TSTATE: db 0
TCOST:  db 0
TCLICK: db 0
TCX:    dw 0
TCY:    dw 0
FRAMES: db 0
GAMEREQ: db 0                       ; 1: otro juego al empezar el paso (GSWITCH)
GMENUON: db 0                       ; 1: el menu de juegos (el cursor se ve)
DUE:    db 0                        ; la imagen en la que toca el paso siguiente
SKIPN:  db 0                        ; pasos pintados desde el ultimo sin pintar
SKIPDRAW: db 0                      ; este paso, sin pintarlos (si va con retraso)
LDRAWN: dw 0                        ; LEFT cuando se pintaron por ultima vez
UPLOAD: db 0
HIDDEN: db 0                        ; transicion: se ve la otra pantalla (B)
SMSCR:  dw $FFFF                    ; desplazamiento suave: el scroll del paso que se ve
SMJ:    db $FF                      ; y la imagen de ese paso ($FF: quieto)
STEPF0: db 0                        ; FRAMES al empezar el paso (el medidor)
METERON: db 0                       ; el medidor, a la vista (CAPS + 2)
PSTRIP: db $FF
SCRL:   dw 0
L2SS:   db 0
SHMMU2: db META_PAGE
SHMMU6: db STRIP_PAGE
ACTP:   dw ACTOR
CURX:   dw 160
CURY:   dw ROOM_Y0+72
MOUSEX: db 0
MOUSEY: db 0
MOUSEON: db 0
CURCI:  db 0
ECOST:  db 0                        ; el costume de las paginas 80-82
RSTAMP: db 0                        ; habitaciones cargadas
CCN:    db 0                        ; costumes de los demas en la cache (CCNUM, CCPG en OVU)
CCNEXT: db 0                        ; la primera pagina libre para otro costume
CURROOM: db 0
CURRI:  db 0
RW:     dw 0
RH:     dw 0
RNZ:    db 0
NBOXES: db 0
RNS:    db 0
MATRIX: dw 0
STRIPT: dw 0
PRISTAB: dw 0
OBJT:   dw 0
NOBJ:   db 0
RREC:   dw 0
LEFT:   dw 0
CAM_CUR: dw 0               ; camara (el orden de Camera.pack())
CAM_DEST: dw 0
CAM_MTA: db 0
CAM_SS: db 0
CAM_MODE: db CAM_FOLLOW
CAM_MAX: dw 0
CAM_MIN: dw 160
SHMMU7: db 0
LPAGE:  db 0
LPMAX:  db 0
LHANDLE: db 0
GAMENAME: db "GAME.DAT",0
CHARSNAME: db "CHARS.DAT",0
VIMGNAME: db "VERBIMG.DAT",0
NAMEBUF: db "R000.DAT",0
ACTOR:  ds A_SIZE
ATTRBUF: ds NSPR_ACTOR*5
GAMEBUF: ds 256
CODE_END:

        ASSERT CODE_END <= ISR_JP, el programa no cabe

; ===========================================================================
; Banco 0 ($0000-$3FFF): tablas y despues el codigo. En $0000-$05FF y
; $3D00-$3DFF solo hay datos (ahi la DivMMC puede saltar al leer codigo).
        MMU 0 1, 0, $0000
        INCLUDE "gen/vmtab.asm"
        ASSERT $ <= $0600, las tablas no caben
        ORG $0600
        INCLUDE "math.asm"
        INCLUDE "boxes.asm"
        INCLUDE "actor.asm"
        INCLUDE "walk.asm"
        INCLUDE "objects.asm"
        INCLUDE "vm.asm"
        INCLUDE "vmcam.asm"
        INCLUDE "cast.asm"
        INCLUDE "paint.asm"
        IFDEF PROF
        INCLUDE "prof.asm"
        ENDIF
BANK0_END:
        ASSERT BANK0_END <= $3D00, el banco 0 no cabe
        ORG $3E00                   ; (detras de la traza de $3D00)
        INCLUDE "camera.asm"
BANK0B_END:
        ASSERT BANK0B_END <= $4000, el banco 0 no cabe (desde $3E00)

; ===========================================================================
; Las capas de la interfaz, en $C000 (MMU6) cuando se usan
        MMU 6 n, OVT_PAGE, $C000
        INCLUDE "ovt.asm"
        MMU 6 n, OVU_PAGE, $C000
        INCLUDE "ovu.asm"
        MMU 6 n, OVF_PAGE, $C000
        INCLUDE "ovf.asm"
        MMU 6 n, OVS_PAGE, $C000
        INCLUDE "ovs.asm"
        MMU 6 n, OVA_PAGE, $C000
        INCLUDE "ova.asm"
        MMU 7 n, SM_PAGE, $E000
        INCLUDE "smooth.asm"
        MMU 6 n, OVK_PAGE, $C000
        INCLUDE "ovk.asm"
        IFDEF MTBUILD
MT_PAGE EQU 210                     ; (libre: la prueba de la musica)
        MMU 6 n, MT_PAGE, $C000
        INCLUDE "mtpage.asm"
MTP_END:
        ASSERT MTP_END <= $D000, la prueba de la musica pisa TBUF
        ENDIF

        IFDEF MTBUILD
        SAVENEX OPEN "../build/mustest.nex", START, STACK, 0
        ELSE
        IFDEF PROF
        SAVENEX OPEN "../build/prof.nex", START, STACK, 0
        ELSE
        SAVENEX OPEN "../build/scumm.nex", START, STACK, 0
        ENDIF
        ENDIF
        SAVENEX CORE 3,1,0
        SAVENEX CFG 0,0,0,1            ; solo para Nexts de 2 MB
        SAVENEX AUTO
        SAVENEX CLOSE
