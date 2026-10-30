; ===========================================================================
;  Manejadores de las instrucciones de SCUMM v5 (tools/vm.py, metodo op)
;  La tabla de despacho (gen/vmtab.asm) la genera tools/build.py desde
;  tools/opcodes.py: H_<nombre> para cada instruccion.
; ===========================================================================

H_bad:
        ld a,(VMOP)                 ; (se apunta, para las pruebas)
        ld (BADOP),a
        ld hl,(BADN)
        inc hl
        ld (BADN),hl
        jp STOPCODE                 ; codigo desconocido: se para el script

H_stopObjectCode:
        jp STOPCODE

H_breakHere:
        ld a,$FF
        ld (CURSLOT),a
        ret

H_jumpRelative:
        call PARAMSI
        db "j",0
        ld hl,(P0)
        xor a
        jp JUMPIF

; --- comparaciones: x = la variable, y = el parametro; saltan si NO se cumple
CMPXY:
        call PARAMSI
        db "Vwj",0
        ld hl,(P1)
        ld de,(P0)
        ret
CONDP2:
        ld hl,(P2)
        jp JUMPIF
CONDP1:
        ld hl,(P1)
        jp JUMPIF

H_isEqual:
        call CMPXY
        or a
        sbc hl,de
        ld a,0
        jr nz,CONDP2
        inc a
        jr CONDP2
H_isNotEqual:
        call CMPXY
        or a
        sbc hl,de
        ld a,0
        jr z,CONDP2
        inc a
        jr CONDP2
H_isLess:                           ; y < x
        call CMPXY
        call CPS16
        sbc a,a
        jr CONDP2
H_isGreaterEqual:                   ; y >= x
        call CMPXY
        call CPS16
        ccf
        sbc a,a
        jr CONDP2
H_isGreater:                        ; y > x  <=>  x < y
        call CMPXY
        ex de,hl
        call CPS16
        sbc a,a
        jr CONDP2
H_isLessEqual:                      ; y <= x  <=>  no (x < y)
        call CMPXY
        ex de,hl
        call CPS16
        ccf
        sbc a,a
        jr CONDP2

H_equalZero:
        call PARAMSI
        db "Vj",0
        ld hl,(P0)
        ld a,h
        or l
        ld a,0
        jr nz,CONDP1
        inc a
        jr CONDP1
H_notEqualZero:
        call PARAMSI
        db "Vj",0
        ld hl,(P0)
        ld a,h
        or l
        ld a,0
        jr z,CONDP1
        inc a
        jr CONDP1

; --- datos -------------------------------------------------------------------
H_move:
        call PARAMSI
        db "rw",0
        ld hl,(P0)
        jp SETRESULT

; HL = la variable de resultado, DE = el parametro
ARITHXY:
        call PARAMSI
        db "rw",0
        ld hl,(RESVAR)
        call READNUM
        ld de,(P0)
        ret
H_add:
        call ARITHXY
        add hl,de
        jp SETRESULT
H_subtract:
        call ARITHXY
        or a
        sbc hl,de
        jp SETRESULT
H_and:
        call ARITHXY
        ld a,h
        and d
        ld h,a
        ld a,l
        and e
        ld l,a
        jp SETRESULT
H_or:
        call ARITHXY
        ld a,h
        or d
        ld h,a
        ld a,l
        or e
        ld l,a
        jp SETRESULT
H_multiply:
        call ARITHXY
        call MULS16
        jp SETRESULT
H_divide:
        call ARITHXY
        ld a,d
        or e
        jp z,SETRESULT              ; entre 0: se queda igual
        ld b,d
        ld c,e
        call SEXT
        call DIVS32_16
        jp SETRESULT
H_increment:
        call PARAMSI
        db "r",0
        ld hl,(RESVAR)
        call READNUM
        inc hl
        jp SETRESULT
H_decrement:
        call PARAMSI
        db "r",0
        ld hl,(RESVAR)
        call READNUM
        dec hl
        jp SETRESULT

H_setVarRange:                      ; (en la capa OVU: se usa poco)
        ld hl,U_setVarRange
        jp OVUCALL

H_expression:
        call PARAMSI
        db "r",0
        ld hl,(RESVAR)
        ld (EXDST),hl               ; el destino se fija al empezar
        xor a
        ld (EXSP),a
.lp:    call VMFETCH
        cp $FF
        jr z,.end
        ld b,a
        and $1F
        cp 1
        jr nz,.op
        ld a,b
        ld (VMOP),a
        xor a
        ld (MASKI),a
        call MASKNEXT
        jr z,.dir
        call READVAR
        jr .push
.dir:   call VMFETCHW
.push:  call EXPUSH
        jr .lp
.op:    cp 6
        jr z,.nested
        ld c,a
        push bc
        call EXPOP                  ; y
        push hl
        call EXPOP                  ; x
        pop de
        pop bc
        ld a,c
        cp 2
        jr nz,.s
        add hl,de
        jr .push
.s:     cp 3
        jr nz,.m
        or a
        sbc hl,de
        jr .push
.m:     cp 4
        jr nz,.d
        call MULS16
        jr .push
.d:     ld a,d
        or e
        jr nz,.dv
        ld hl,0
        jr .push
.dv:    ld b,d
        ld c,e
        call SEXT
        call DIVS32_16
        jr .push
.nested:
        call VMFETCH                ; una instruccion dentro de la expresion
        ld (VMOP),a
        ld hl,(EXDST)
        push hl
        ld a,(EXSP)
        push af
        call DISPATCH
        pop af
        ld (EXSP),a
        pop hl
        ld (EXDST),hl
        call RESTOREIY
        ld hl,(VARS)
        jr .push
.end:   call EXPOP
        ex de,hl
        ld hl,(EXDST)
        jp WRITENUM

EXPUSH:
        ld a,(EXSP)
        cp 16
        ret nc
        ex de,hl
        ld l,a
        inc a
        ld (EXSP),a
        ld h,0
        add hl,hl
        ld bc,EXSTK
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        ret
EXPOP:
        ld a,(EXSP)
        or a
        jr z,.empty
        dec a
        ld (EXSP),a
        ld l,a
        ld h,0
        add hl,hl
        ld bc,EXSTK
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
.empty: ld hl,0
        ret

H_getRandomNr:
        call PARAMSI
        db "rb",0
        ld hl,(SEED)
        ld de,25173
        call MULU16
        ld de,13849
        add hl,de
        ld (SEED),hl
        ld a,(P0)
        inc a
        jr z,.full
        ld e,a
        ld d,h
        mul d,e
        ld l,d
        ld h,0
        jp SETRESULT
.full:  ld l,h
        ld h,0
        jp SETRESULT

; --- esperas y scripts --------------------------------------------------------
H_delay:
        call VMFETCH
        ld (iy+SL_DLY),a
        call VMFETCH
        ld (iy+SL_DLY+1),a
        call VMFETCH
        ld (iy+SL_DLY+2),a
PAUSE:
        ld (iy+SL_ST),SS_PAUSED
        ld a,$FF
        ld (CURSLOT),a
        ret
H_delayVariable:
        call PARAMSI
        db "V",0
        ld hl,(P0)
        ld (iy+SL_DLY),l
        ld (iy+SL_DLY+1),h
        ld a,h
        rla
        sbc a,a
        ld (iy+SL_DLY+2),a
        jr PAUSE

H_wait:
        call PARAMSI
        db "n",0
        ld a,(VMOP)
        and $1F
        cp 1
        jr nz,.w2
        call PARAMSI
        db "b",0
        ld hl,(P0)
        call ACTMOVING
        jr .chk
.w2:    cp 2
        jr nz,.w3
        ld hl,(VARS+2*VAR_HAVE_MSG)
        ld a,h
        or l
        jr .chk
.w3:    cp 3
        jr nz,.w4
        call CAMMOVING
        jr .chk
.w4:    ld hl,U_SENTBUSY
        call OVUCALL
.chk:   or a
        ret z
        call RESTOREIY              ; otra vez la misma instruccion
        ld hl,(VMSTART)
        ld (iy+SL_PC),l
        ld (iy+SL_PC+1),h
        xor a
        ld (FPTR+1),a
        ld a,$FF
        ld (CURSLOT),a
        ret

H_isScriptRunning:
        call PARAMSI
        db "rb",0
        ld hl,(P0)
        call RUNNING
        ld l,a
        ld h,0
        jp SETRESULT

H_startScript:
        ld a,(VMOP)
        ld (STFL),a
        call PARAMSI
        db "bv",0
        ld a,(STFL)
        and $20
        ld (SSFRES),a
        ld a,(STFL)
        and $40
        ld (SSREC),a
SCRP0:  ld hl,(P0)
        ld a,h
        or a
        ret nz
        ld a,l
        jp RUNSCRIPT

H_chainScript:                      ; (en la capa OVU: se usa poco)
        ld hl,U_chainScript
        jp OVUCALL

H_stopScript:
        call PARAMSI
        db "b",0
        ld hl,(P0)
        ld a,h
        or l
        jp z,STOPCODE
        jp STOPSCRIPT

H_freezeScripts:
        call PARAMSI
        db "b",0
        ld hl,(P0)
        ld a,h
        or l
        jp z,UNFREEZE
        jp FREEZE

; HL = CSDATA/CUTPTR + 2 * CSSP (DE = base)
CSAT:
        ld a,(CSSP)
        ld l,a
        ld h,0
        add hl,hl
        add hl,de
        ret

H_cutscene:                         ; (en la capa OVU: se usa poco)
        ld hl,U_cutscene
        jp OVUCALL
; cs_script y cs_ptr del nivel actual a 0
CSCLR:
        ld de,CUTPTR
        call CSAT
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        ld a,(CSSP)
        ld hl,CSSCR
        add hl,a
        ld (hl),0
        ret
; runScript(HL) con los ARGS que haya (si no es 0)
RUNVARGS:
        ld a,h
        or l
        ret z
        xor a
        ld (SSFRES),a
        ld (SSREC),a
        ld a,l
        jp RUNSCRIPT

H_endCutscene:                      ; (en la capa OVU: se usa poco)
        ld hl,U_endCutscene
        jp OVUCALL

H_override:                         ; (en la capa OVU: se usa poco)
        ld hl,U_override
        jp OVUCALL

H_startObject:
        call PARAMSI
        db "wbv",0
        ld hl,(P0)
        ld a,(P1)
        jp RUNOBJSCR

; Las instrucciones de la interfaz estan en la capa OVU
OVUCALL:
        ld a,OVU_PAGE
        jp OVCALL

H_stopObjectScript:
        call PARAMSI
        db "w",0
        ld hl,(P0)
        jp STOPOBJSCR

; --- objetos ------------------------------------------------------------------
H_setState:                         ; (en la capa OVU: tambien deja de ir encima)
        ld hl,U_setState
        jp OVUCALL

H_getObjectState:
        call PARAMSI
        db "rw",0
        ld hl,(P0)
        call GETSTATE
RESA:   ld l,a
        ld h,0
        jp SETRESULT

H_ifState:
        call PARAMSI
        db "wbj",0
        call STEQ
        jp CONDP2
H_ifNotState:
        call PARAMSI
        db "wbj",0
        call STEQ
        xor 1
        jp CONDP2
; A = 1 si el estado de P0 es P1
STEQ:
        ld hl,(P0)
        call GETSTATE
        ld l,a
        ld h,0
        ld de,(P1)
        or a
        sbc hl,de
        ld a,0
        ret nz
        inc a
        ret

H_drawObject:
        ld hl,U_drawObject
        jp OVUCALL

H_setOwnerOf:
        ld hl,U_setOwnerOf
        jp OVUCALL

H_getObjectOwner:
        call PARAMSI
        db "rw",0
        ld hl,(P0)
        call GETOWNER
        jp RESA

H_pickupObject:
        ld hl,U_pickupObject
        jp OVUCALL

H_setClass:                         ; (en la capa OVU: se usa poco)
        ld hl,U_setClass
        jp OVUCALL

H_ifClassOfIs:                      ; (en la capa OVU: se usa poco)
        ld hl,U_ifClassOfIs
        jp OVUCALL

H_findObject:                       ; (en la capa OVU: se usa poco)
        ld hl,U_findObject
        jp OVUCALL

H_getInventoryCount:
        ld hl,U_getInventoryCount
        jp OVUCALL

; --- habitacion ---------------------------------------------------------------
H_loadRoom:
        call PARAMSI
        db "b",0
        ld hl,0
        ld (SCOBJ),hl
        ld a,(P0)
        jp CHANGEROOM

H_loadRoomWithEgo:
        ld hl,K_loadRoomWithEgo
        jp OVKCALL

H_lights:
        call PARAMSI
        db "bBB",0
        ld a,(P2)
        or a
        ret nz
        ld hl,(P0)
        ld (VARS+2*VAR_CURRENT_LIGHTS),hl
        ret

H_roomOps:                          ; (en la capa OVU: se usa poco)
        ld hl,U_roomOps
        jp OVUCALL

H_matrixOps:                        ; (en la capa OVU: se usa poco)
        ld hl,U_matrixOps
        jp OVUCALL

; Formato del subcodigo A de la tabla HL (punteros; 0 = sin parametros)
SUBFMT:
        add a,a
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        or h
        ret z
        jp PARAMSF

; --- actores (en la capa OVK) --------------------------------------------------
H_putActor:
        ld hl,K_putActor
        jr OVKCALL
H_walkActorTo:
        ld hl,K_walkActorTo
        jr OVKCALL
H_walkActorToObject:
        ld hl,K_walkActorToObject
        jr OVKCALL
H_putActorAtObject:
        ld hl,K_putActorAtObject
        jr OVKCALL
H_walkActorToActor:
        ld hl,K_walkActorToActor
        jr OVKCALL
H_putActorInRoom:
        ld hl,K_putActorInRoom
        jr OVKCALL
H_faceActor:
        ld hl,K_faceActor
        jr OVKCALL
H_animateActor:
        ld hl,K_animateActor
        jr OVKCALL
H_actorOps:
        ld hl,K_actorOps
        jr OVKCALL
H_getActorX:
        ld hl,K_getActorX
        jr OVKCALL
H_getActorY:
        ld hl,K_getActorY
        jr OVKCALL
H_getActorRoom:
        ld hl,K_getActorRoom
        jr OVKCALL
H_getActorCostume:
        ld hl,K_getActorCostume
        jr OVKCALL
H_getActorElevation:
        ld hl,K_getActorElevation
        jr OVKCALL
H_getActorMoving:
        ld hl,K_getActorMoving
        jr OVKCALL
H_getActorFacing:
        ld hl,K_getActorFacing
        jr OVKCALL
H_getActorWalkBox:
        ld hl,K_getActorWalkBox
        jr OVKCALL
H_getActorWidth:
        ld hl,K_getActorWidth
        jr OVKCALL
H_getActorScale:
        ld hl,K_getActorScale
        jr OVKCALL
H_getAnimCounter:
        ld hl,K_getAnimCounter
        jr OVKCALL
H_isActorInBox:
        ld hl,K_isActorInBox
        jr OVKCALL
H_getDist:
        ld hl,K_getDist
        jr OVKCALL
H_getClosestObjActor:
        ld hl,K_getClosestObjActor
        jr OVKCALL
H_actorFromPos:
        ld hl,K_actorFromPos
OVKCALL:
        ld a,OVK_PAGE
        jp OVCALL

; resultado 0 (cosas que todavia no se calculan)
H_getStringWidth:
        call PARAMSI
        db "rb",0
        ld hl,0
        jp SETRESULT
H_getVerbEntrypoint:
        ld hl,U_getVerbEntrypoint
        jp OVUCALL
H_findInventory:
        ld hl,U_findInventory
        jp OVUCALL

; --- camara ---------------------------------------------------------------------
H_setCameraAt:
        call PARAMSI
        db "w",0
        ld hl,(P0)
        jp CAMAT
H_panCameraTo:
        call PARAMSI
        db "w",0
        ld hl,(P0)
        jp CAMPAN
H_actorFollowCamera:
        call PARAMSI
        db "b",0
        ld hl,(P0)
        ld a,h
        or a
        ret nz
        ld a,l
        call ACTOK
        ret nc
        call CAMFOLLOW
        jp RESTOREIY

; --- textos -----------------------------------------------------------------------
H_print:
        ld hl,U_print
        jp OVUCALL
H_printEgo:
        ld hl,U_printEgo
        jp OVUCALL
H_stringOps:
        ld hl,U_stringOps
        jp OVUCALL
H_setObjectName:
        ld hl,U_setObjectName
        jp OVUCALL

; --- lo que solo se decodifica --------------------------------------------------
H_startSound:
        call PARAMSI
        db "b",0
        ld hl,SN_STARTS
        jr OVACALL
H_startMusic:
        call PARAMSI
        db "b",0
        ld hl,SN_STARTM
        jr OVACALL
H_stopSound:
        call PARAMSI
        db "b",0
        ld hl,SN_STOP
        jr OVACALL
H_stopMusic:
        ld hl,SN_STOPALL
OVACALL:
        ld a,OVA_PAGE
        jp OVCALL
H_isSoundRunning:
        call PARAMSI
        db "rb",0
        ld hl,SN_RUNNING
        jr OVACALL
H_dummy:
H_endOverride:
H_beginOverride:
        ret
H_soundKludge:
        call PARAMSI
        db "v",0
        ld hl,SN_KLUDGE
        jr OVACALL
H_debug:
H_pickupObjectOld:
        call PARAMSI
        db "w",0
        ret
H_systemOps:
        call PARAMSI
        db "B",0
        ld a,(P0)
        cp 1
        jr nz,.n1
        ld (RESTARTREQ),a           ; 1: reiniciar (en el paso siguiente)
        ret
.n1:    cp 3                        ; 3: salir (reinicio del Next; en las pruebas, nada)
        ret nz
        ld a,(TMODE)
        or a
        ret nz
        nextreg $02,1
        ret
H_resourceRoutines:
        ld hl,U_resourceRoutines
        jp OVUCALL
H_doSentence:
        ld hl,U_doSentence
        jp OVUCALL
H_cursorCommand:
        ld hl,U_cursorCommand
        jp OVUCALL
H_verbOps:
        ld hl,U_verbOps
        jp OVUCALL
H_saveRestoreVerbs:
        ld hl,U_saveRestoreVerbs
        jp OVUCALL
H_drawBox:
        ld hl,U_drawBox
        jp OVUCALL
H_oldRoomEffect:
        call PARAMSI
        db "n",0
        ld a,(VMOP)
        and $1F
        cp 3
        ret nz
        call PARAMSI
        db "w",0
        ret

; Camara en movimiento: A = 1 si cur >> 3 != dest >> 3
CAMMOVING:
        ld hl,(CAM_CUR)
        call SHR3
        ex de,hl
        ld hl,(CAM_DEST)
        call SHR3
        or a
        sbc hl,de
        ld a,0
        ret z
        inc a
        ret
