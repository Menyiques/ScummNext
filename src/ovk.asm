; ===========================================================================
;  Capa OVK (pagina OVK_PAGE, en $C000): los actores de la maquina virtual
;  (actor.cpp de ScummVM 2.8, como model.Actor y World)
;
;  Cada actor (1-12) tiene su ficha de R_SIZE bytes en CAST_PAGE; con el que
;  se trabaja se copia a ACTOR (ACTLOAD) y vuelve a su ficha al cambiar de
;  actor o al final del paso (ACTSYNC). Aqui: sus instrucciones, ponerlos,
;  quitarlos y ensenarlos, andar todos y dibujarlos. Lo que puede llevar a
;  otro actor (scripts, hablar, cambiar de habitacion) va seguido de KRELOAD.
; ===========================================================================

; El actor (P0) & $FF (o A) a ACTOR: carry si es uno de verdad (KN = su numero)
KACT:
        ld a,(P0)
KACTA:
        call ACTOK
        ret nc
        ld (KN),a
        call ACTLOAD
        scf
        ret
; Otra vez el actor KN en ACTOR
KRELOAD:
        ld a,(KN)
        jp ACTLOAD
; El protagonista (si es un actor) a ACTOR
KEGO:
        ld a,(VARS+2*VAR_EGO+1)
        or a
        ret nz
        ld a,(VARS+2*VAR_EGO)
        jr KACTA

; Z si el que habla es KN
KTALKING:
        ld a,(KN)
        ld hl,VARS+2*VAR_TALK_ACTOR
        cp (hl)
        ret
KSTOPTALK:
        ld hl,STOPTALK
        ld a,OVT_PAGE
        call OVCALL
        call RESTOREIY
        jr KRELOAD

; --- ponerlo, ensenarlo, quitarlo ----------------------------------------------
; putActor(KPX, KPY, KPR)
KPUT:
        ld ix,ACTOR
        ld a,(ACTOR+R_VIS)          ; si se va el que habla, se calla
        or a
        jr z,.nt
        ld a,(KPR)
        ld hl,CURROOM
        cp (hl)
        jr z,.nt
        call KTALKING
        call z,KSTOPTALK
.nt:    ld hl,(KPX)
        ld (ix+A_X),l
        ld (ix+A_X+1),h
        ld hl,(KPY)
        ld (ix+A_Y),l
        ld (ix+A_Y+1),h
        ld a,(KPR)
        ld (ACTOR+R_ROOM),a
        ld hl,(VARS+2*VAR_EGO)      ; el protagonista ya esta colocado
        ld a,h
        or a
        jr nz,.ne
        ld a,(KN)
        cp l
        jr nz,.ne
        ld a,1
        ld (EGOPOS),a
.ne:    ld a,(ACTOR+R_VIS)
        or a
        jr z,.inv
        call ACTHERE
        jr nc,KHIDE
        ld a,(ix+A_MOV)
        or a
        jr z,KADJPOS
        ld (ix+A_MOV),0
        ld a,(ACTOR+R_FSTAND)
        call STARTANIM
        jr KADJPOS
.inv:   call ACTHERE
        ret nc
; showActor
KSHOW:
        ld ix,ACTOR
        ld a,(CURROOM)
        or a
        ret z
        ld a,(ACTOR+R_VIS)
        or a
        ret nz
        call KADJPOS
        ld a,(ACTOR+R_NINIT)
        or a
        jr z,.n
        ld a,(ACTOR+R_FINIT)
        call STARTANIM
        xor a
        ld (ACTOR+R_NINIT),a
.n:     ld (ix+A_MOV),0
        ld a,1
        ld (ACTOR+R_VIS),a
        ret
; hideActor
KHIDE:
        ld ix,ACTOR
        ld a,(ACTOR+R_VIS)
        or a
        ret z
        ld a,(ix+A_MOV)
        or a
        jr z,.n
        ld (ix+A_MOV),0
        ld a,(ACTOR+R_FSTAND)
        call STARTANIM
.n:     xor a
        ld (ACTOR+R_VIS),a
        ld (ACTOR+R_SCNT),a
        ret
; adjustActorPos: a la caja mas cercana, quieto (y si la caja lo pide, girando)
KADJPOS:
        ld ix,ACTOR
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        ld (AJX),hl
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        ld (AJY),hl
        call ACTADJ
        ld hl,(AJRX)
        ld (ix+A_X),l
        ld (ix+A_X+1),h
        ld hl,(AJRY)
        ld (ix+A_Y),l
        ld (ix+A_Y+1),h
        ld (ix+A_DESTBOX),a
        call SETBOX
        ld (ix+A_DESTX),$FF
        ld (ix+A_DESTX+1),$FF
        ld (ix+A_MOV),0
        ld hl,ACTOR+R_SCNT
        ld (hl),0
        cp INVALID
        ret z
        call BOXFLAGS
        and 7
        ret z
        ld l,(ix+A_FACE)
        ld h,(ix+A_FACE+1)
        jp TURNTO

; setActorCostume(A)
KSETCOST:
        ld (KC),a
        ld a,1
        ld (ACTOR+R_NINIT),a
        ld a,(ACTOR+R_VIS)
        or a
        jr z,.inv
        call KHIDE
        call RESETCOST
        ld a,(KC)
        ld (ACTOR+R_COST),a
        call KSHOW
        jr .pal
.inv:   ld a,(KC)
        ld (ACTOR+R_COST),a
        call RESETCOST
.pal:   ld hl,ACTOR+R_PAL
        ld b,32
.p:     ld (hl),$FF
        inc hl
        djnz .p
        ret

; faceToObject(HL)
KFACE:
        push hl
        call ACTHERE
        pop hl
        ret nc
        call KOAXY
        ret nc
        ld ix,ACTOR
        ld e,(ix+A_X)
        ld d,(ix+A_X+1)
        ex de,hl
        call CPS16                  ; x del actor < x del otro: a la derecha
        ld hl,90
        jp c,TURNTO
        ld hl,270
        jp TURNTO

; animateActor(A): 252-255 parar, 248-251 mirar ya, 244-247 girar; el resto, una animacion
KANIMATE:
        ld (KC),a
        and 3
        call OLD2NEW
        ld a,(KC)
        cp 252
        jr nc,.stop
        cp 248
        jr nc,.dir
        cp 244
        jp c,STARTANIM
        push hl
        call ACTHERE
        pop hl
        ret nc
        jp TURNTO
.stop:  call ACTHERE
        ret nc
        ld a,(ACTOR+R_FSTAND)
        call STARTANIM
        ld (ix+A_MOV),0
        ret
.dir:   push hl
        call ACTHERE
        pop hl
        jr nc,.sd
        ld a,(ix+A_MOV)
        and ~MF_TURN
        ld (ix+A_MOV),a
.sd:    jp SETDIR

; --- donde estan las cosas ---------------------------------------------------------
; whereIsObject(HL): carry si esta (en la habitacion o en el inventario)
KWHERE:
        ld (OVHL),hl
        ld hl,WHEREIS
        ld a,OVU_PAGE
        call OVCALLR
        cp $FF
        ret

; getObjectXYPos sin direccion (HL = objeto): carry, HL = x, DE = y
KOBJXY:
        ld a,(CURROOM)
        or a
        ret z
        jp OBJWALK
; y con ella: KDIR = hacia donde se mira al llegar
KOBJXYD:
        ld (KOO),hl
        ld a,(CURROOM)
        or a
        ret z
        call OBJINDEX
        cp $FF
        ret z
        call OBJPTR
        ld de,O_DIR
        add hl,de
        ld a,(hl)
        and 3
        call OLD2NEW
        ld (KDIR),hl
        ld hl,(KOO)
        jp OBJWALK

; getObjectOrActorXY(HL): carry, HL = x, DE = y
KOAXY:
        ld a,h
        or a
        jr nz,.obj
        ld a,l
        cp NACT
        jr nc,.obj
.act:   ld (KOA),a                  ; un actor: si esta en la habitacion
        call INROOM
        ret nc
        ld a,(KOA)
        ld l,a
        ld h,0
        call ACTXY
        scf
        ret
.obj:   ld (KOO),hl
        call KWHERE
        ret nc
        cp WIO_INVENTORY
        jr nz,.room
        ld hl,(KOO)                 ; en el inventario: donde este su dueno
        call GETOWNER
        jr .act
.room:  ld hl,(KOO)
        jr KOBJXY

; A = HL si es un actor (0 si no)
KISACT:
        ld a,h
        or a
        ld a,0
        ret nz
        ld a,l
        call ACTOK
        ret c
        xor a
        ret

; getObjActToObjActDist(HL, DE) -> HL
KDIST:
        ld (KDA),hl
        ld (KDB),de
        call KISACT
        ld (KAA),a
        ld hl,(KDB)
        call KISACT
        ld (KAB),a
        or a                        ; dos actores en la misma habitacion, que no es
        jr z,.p                     ; esta: 0
        ld a,(KAA)
        or a
        jr z,.p
        ld e,R_ROOM
        call ACTRD
        ld a,l
        or a
        jr z,.p
        ld (KRA),a
        ld a,(KAB)
        ld e,R_ROOM
        call ACTRD
        ld a,(KRA)
        cp l
        jr nz,.p
        ld a,(KAA)
        call INROOM
        jr c,.p
        ld hl,0
        ret
.p:     ld hl,(KDA)
        call KOAXY
        jr nc,.ff
        ld (KDPX),hl
        ld (KDPY),de
        ld hl,(KDB)
        call KOAXY
        jr nc,.ff
        ld (AJX),hl
        ld (AJY),de
        ld a,(KAB)                  ; de un actor a un objeto: el punto, en su caja
        or a
        jr nz,.d
        ld a,(KAA)
        or a
        jr z,.d
        call ACTLOAD
        call ACTADJ
        ld hl,(AJRX)
        ld (AJX),hl
        ld hl,(AJRY)
        ld (AJY),hl
.d:     ld hl,(KDPY)                ; max(|y - y2|, |x - x2|)
        ld de,(AJY)
        or a
        sbc hl,de
        call ABSHL
        push hl
        ld hl,(KDPX)
        ld de,(AJX)
        or a
        sbc hl,de
        call ABSHL
        pop de
        call CPU16
        ret nc
        ex de,hl
        ret
.ff:    ld hl,$FF
        ret

; HL = DE / 255 (DE <= 65025)
DIV255:
        ld l,d
        ld h,0
        add hl,de
        inc hl
        ld l,h
        ld h,0
        ret

; --- instrucciones ------------------------------------------------------------------
K_putActor:
        call PARAMSI
        db "bww",0
        call KACT
        jp nc,RESTOREIY
        ld hl,(P1)
        ld (KPX),hl
        ld hl,(P2)
        ld (KPY),hl
KPUTHERE:                           ; en la habitacion en la que esta
        ld a,(ACTOR+R_ROOM)
        ld (KPR),a
        call KPUT
        jp RESTOREIY

K_walkActorTo:
        call PARAMSI
        db "bww",0
        call KACT
        jp nc,RESTOREIY
        ld hl,(P1)
        ld de,(P2)
        ld bc,-1
; startWalkActor(HL, DE, direccion BC)
KWALKTO:
        ld (SWX),hl
        ld (SWY),de
        ld (SWD),bc
        ld ix,ACTOR
        call STARTWALK
        jp RESTOREIY

K_walkActorToObject:
        call PARAMSI
        db "bw",0
        call KACT
        jp nc,RESTOREIY
        ld hl,(P1)
        call KWHERE
        jp nc,RESTOREIY
        ld hl,(P1)
        call KOBJXYD
        jp nc,RESTOREIY
        ld bc,(KDIR)
        jr KWALKTO

K_putActorAtObject:
        call PARAMSI
        db "bw",0
        call KACT
        jp nc,RESTOREIY
        ld hl,(P1)
        call KWHERE
        jr nc,.def
        ld hl,(P1)
        call KOBJXY
        jr c,.at
.def:   ld hl,240
        ld de,120
.at:    ld (KPX),hl
        ld (KPY),de
        jp KPUTHERE

K_walkActorToActor:
        call PARAMSI
        db "bbB",0
        ld a,(P1)
        call INROOM
        jp nc,RESTOREIY
        call KACT
        jp nc,RESTOREIY
        call ACTHERE
        jp nc,RESTOREIY
        ld a,(P1)
        ld e,A_X
        call ACTRD
        ld (KDPX),hl
        ld a,(P1)
        ld e,A_Y
        call ACTRD
        ld (KDPY),hl
        ld a,(P2)                   ; la distancia: 255 = la de los dos anchos
        ld l,a
        ld h,0
        cp $FF
        jr nz,.d
        ld a,(P1)
        ld e,A_SCALEX
        call ACTRD
        ld a,(P1)
        push hl
        ld e,R_WIDTH
        call ACTRD
        pop de
        ld d,l
        mul d,e
        call DIV255
        srl h
        rr l
        push hl
        ld a,(ACTOR+A_SCALEX)
        ld e,a
        ld a,(ACTOR+R_WIDTH)
        ld d,a
        mul d,e
        call DIV255
        pop de
        add hl,de
.d:     ex de,hl                    ; x = x2 + dist si x2 < x; si no, x2 - dist
        ld hl,(KDPX)
        push de
        ld e,(ix+A_X)
        ld d,(ix+A_X+1)
        call CPS16
        pop de
        jr c,.add
        or a
        sbc hl,de
        jr .w
.add:   add hl,de
.w:     ld de,(KDPY)
        ld bc,-1
        jp KWALKTO

K_putActorInRoom:
        call PARAMSI
        db "bb",0
        call KACT
        jp nc,RESTOREIY
        ld a,(ACTOR+R_VIS)          ; si se va el que habla, se calla
        or a
        jr z,.nt
        ld a,(P1)
        ld hl,CURROOM
        cp (hl)
        jr z,.nt
        call KTALKING
        call z,KSTOPTALK
.nt:    ld a,(P1)
        ld (ACTOR+R_ROOM),a
        or a
        jp nz,RESTOREIY
        ld hl,0                     ; a la habitacion 0: putActor(0, 0, 0)
        ld (KPX),hl
        ld (KPY),hl
        jp KPUTHERE

K_faceActor:
        call PARAMSI
        db "bw",0
        call KACT
        jp nc,RESTOREIY
        ld hl,(P1)
        call KFACE
        jp RESTOREIY

K_animateActor:
        call PARAMSI
        db "bb",0
        call KACT
        jp nc,RESTOREIY
        ld a,(P1)
        call KANIMATE
        jp RESTOREIY

K_actorOps:
        call PARAMSI
        db "b",0
        ld hl,(P0)
        ld (AOACT),hl
.lp:    call RESTOREIY
        call VMFETCH
        cp $FF
        ret z
        ld (VMOP),a
        and $1F
        ld (AOK),a
        cp 13
        jr nz,.fmt
        ld hl,U_ACTNAME             ; el nombre (en la capa OVU)
        ld a,OVU_PAGE
        call OVCALL
        jr .lp
.fmt:   ld hl,ACTFMT
        call SUBFMT
        ld a,(AOACT)
        call KACTA
        jr nc,.lp
        call KAOP
        jr .lp

; Un subcodigo de actorOps (AOK) con P0, P1
KAOP:
        ld a,(AOK)
        ld hl,(P0)
        ld de,(P1)
        cp 1
        jr nz,.n1
        ld a,l
        jp KSETCOST
.n1:    cp 2
        jr nz,.n2
        ld a,l
        jp SETSPEED
.n2:    cp 3
        jr nz,.n3
        ld a,l
        ld (ACTOR+R_SND),a
        ret
.n3:    cp 4
        jr nz,.n4
        ld a,l
        ld (ACTOR+R_FWALK),a
        ret
.n4:    cp 5
        jr nz,.n5
        ld a,l
        ld (ACTOR+R_FTSTART),a
        ld a,e
        ld (ACTOR+R_FTSTOP),a
        ret
.n5:    cp 6
        jr nz,.n6
        ld a,l
        ld (ACTOR+R_FSTAND),a
        ret
.n6:    cp 8
        jr nz,.n8
        call INITACT0               ; initActor(0), sin clases
        ld a,(KN)
        ld l,a
        ld h,0
        jp CLRCLASSES
.n8:    cp 9
        jr nz,.n9
        ld (ACTOR+R_ELEV),hl
        ret
.n9:    cp 10
        jr nz,.n10
        ld hl,ACTOR+R_FINIT
        ld a,1
        ld b,5
.fr:    ld (hl),a
        inc hl
        inc a
        djnz .fr
        ret
.n10:   cp 11
        jr nz,.n11
        ld a,l
        cp 32
        ret nc
        ld hl,ACTOR+R_PAL
        add hl,a
        ld (hl),e
        ret
.n11:   cp 12
        jr nz,.n12
        ld a,l
        ld (ACTOR+R_TALKC),a
        ret
.n12:   cp 14
        jr nz,.n14
        ld a,l
        ld (ACTOR+R_FINIT),a
        ret
.n14:   cp 16
        jr nz,.n16
        ld a,l
        ld (ACTOR+R_WIDTH),a
        ret
.n16:   cp 17
        jr nz,.n17
        ld h,0
        ld (ACTOR+R_BOXSC),hl
        ld a,l
        ld (ACTOR+A_SCALEX),a
        ld a,e
        ld (ACTOR+A_SCALEY),a
        ret
.n17:   cp 18
        jr nz,.n18
        xor a
        ld (ACTOR+R_CLIP),a
        ret
.n18:   cp 19
        jr nz,.n19
        ld a,l
        ld (ACTOR+R_CLIP),a
        ret
.n19:   cp 20
        jr z,.ign
        cp 21
        jr nz,.n21
.ign:   sub 21                      ; 20: no hace caso de las cajas; 21: si
        and 1
        ld (ACTOR+R_IGNB),a
        xor a
        ld (ACTOR+R_CLIP),a
        call ACTHERE
        ret nc
        ld ix,ACTOR
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        ld (KPX),hl
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        ld (KPY),hl
        ld a,(ACTOR+R_ROOM)
        ld (KPR),a
        jp KPUT
.n21:   cp 22
        ret nz
        ld a,l
        ld (ix+A_ASPD),a
        ld (ix+A_APROG),0
        ret

; --- lo que preguntan los scripts ------------------------------------------------
; HL = el campo E del actor (P0) & $FF (0 si no es un actor)
KGET:
        ld a,(P0)
        call ACTOK
        jp c,ACTRD
        ld hl,0
        ret
KRES8:  call KGET
        ld h,0
        jr KRES
KRES16: call KGET
KRES:   call RESTOREIY
        jp SETRESULT

K_getActorRoom:
        call PARAMSI
        db "rb",0
        ld e,R_ROOM
        jr KRES8
K_getActorCostume:
        call PARAMSI
        db "rb",0
        ld e,R_COST
        jr KRES8
K_getActorMoving:
        call PARAMSI
        db "rb",0
        ld e,A_MOV
        jr KRES8
K_getActorWalkBox:
        call PARAMSI
        db "rb",0
        ld e,A_BOX
        jr KRES8
K_getActorWidth:
        call PARAMSI
        db "rb",0
        ld e,R_WIDTH
        jr KRES8
K_getActorScale:
        call PARAMSI
        db "rb",0
        ld e,A_SCALEX
        jr KRES8
K_getActorElevation:
        call PARAMSI
        db "rb",0
        ld e,R_ELEV
        jr KRES16
K_getAnimCounter:
        call PARAMSI
        db "rb",0
        ld e,R_ACNT
        jr KRES16
K_getActorFacing:
        call PARAMSI
        db "rb",0
        ld e,A_FACE
        call KGET
        call OLDDIR
        ld l,a
        ld h,0
        jr KRES

K_getActorX:
        call PARAMSI
        db "rw",0
        call KOBJXYV
        jr KRES
K_getActorY:
        call PARAMSI
        db "rw",0
        call KOBJXYV
        ex de,hl
        jr KRES
; getObjX / getObjY de P0: HL = x, DE = y (0 si < 1, -1 si no esta)
KOBJXYV:
        ld hl,(P0)
        bit 7,h
        jr nz,.z
        ld a,h
        or l
        jr z,.z
        ld a,h
        or a
        jr nz,.obj
        ld a,l
        cp NACT
        jp c,ACTXY
.obj:   call KWHERE
        jr nc,.m1
        ld hl,(P0)
        call KOAXY
        ret c
.m1:    ld hl,-1
        ld d,h
        ld e,l
        ret
.z:     ld hl,0
        ld d,h
        ld e,l
        ret

K_getDist:
        call PARAMSI
        db "rww",0
        ld hl,(P0)
        ld de,(P1)
        call KDIST
        jp KRES

K_getClosestObjActor:
        call PARAMSI
        db "rw",0
        ld hl,$FF
        ld (KBEST),hl
        ld (KBD),hl
        ld hl,(VARS+2*VAR_ACTOR_RANGE_MAX)
.lp:    ld (KOBJ),hl
        ex de,hl
        ld hl,(P0)
        call KDIST
        ld de,(KBD)
        call CPS16
        jr nc,.n
        ld (KBD),hl
        ld hl,(KOBJ)
        ld (KBEST),hl
.n:     ld hl,(KOBJ)
        dec hl
        ld de,(VARS+2*VAR_ACTOR_RANGE_MIN)
        call CPS16
        jr nc,.lp
        ld hl,(KBEST)
        jp KRES

; getActorFromPos: el primer actor dibujado en esa tira y entre su arriba y abajo
K_actorFromPos:
        call PARAMSI
        db "rww",0
        ld hl,0
        ld a,(CURROOM)
        or a
        jp z,KRES
        ld hl,(P0)
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ld (KS),hl
        ld a,1
.lp:    ld (KI),a
        ld e,R_STR0
        call ACTRD
        ld a,h
        and l
        inc a
        jr z,.n
        ex de,hl
        ld hl,(KS)
        call CPS16                  ; tira < strip0: no
        jr c,.n
        ld a,(KI)
        ld e,R_STR1
        call ACTRD
        ld de,(KS)
        call CPS16                  ; strip1 < tira: no
        jr c,.n
        ld a,(KI)
        ld l,a
        ld h,0
        ld a,CL_UNTOUCH
        call GETCLASS
        or a
        jr nz,.n
        ld a,(KI)
        ld e,R_TOP
        call ACTRD
        ex de,hl
        ld hl,(P1)
        call CPS16                  ; y < arriba: no
        jr c,.n
        ld a,(KI)
        ld e,R_BOT
        call ACTRD
        ld de,(P1)
        call CPS16                  ; abajo < y: no
        jr c,.n
        ld a,(KI)
        ld l,a
        ld h,0
        jp KRES
.n:     ld a,(KI)
        inc a
        cp NACT
        jr nz,.lp
        ld hl,0
        jp KRES

K_isActorInBox:
        call PARAMSI
        db "bbj",0
        xor a
        ld (KC),a
        ld a,(CURROOM)
        or a
        jr z,.r
        ld a,(P0)
        call ACTOK
        jr nc,.r
        push af
        ld e,A_X
        call ACTRD
        ld (PX),hl
        pop af
        ld e,A_Y
        call ACTRD
        ld (PY),hl
        ld a,(P1)
        call INBOX
        sbc a,a
        and 1
        ld (KC),a
.r:     call RESTOREIY
        ld a,(KC)
        jp CONDP2

; --- cambiar de habitacion ------------------------------------------------------------
K_loadRoomWithEgo:
        call PARAMSI
        db "wbWW",0
        call KEGO
        jp nc,RESTOREIY
        ld hl,(P2)                  ; (en la pila: x, y y el actor)
        push hl
        ld hl,(P3)
        push hl
        ld a,(KN)
        push af
        ld hl,(P0)
        ld (VARS+2*VAR_WALKTO_OBJ),hl
        ld (SCOBJ),hl
        ld a,(P1)                   ; putActor(x, y, habitacion)
        ld (KPR),a
        ld ix,ACTOR
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        ld (KPX),hl
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        ld (KPY),hl
        call KPUT
        xor a
        ld (EGOPOS),a
        ld a,(ACTOR+R_ROOM)         ; (cargar la habitacion deja otra pagina en MMU6)
        ld hl,CHANGEROOM
        call SAFECALL
        ld hl,0
        ld (VARS+2*VAR_WALKTO_OBJ),hl
        pop af
        pop de
        pop hl
        ld (KLX),hl
        ld (KLY),de
        call KACTA
        ld a,(CURROOM)
        or a
        jp z,RESTOREIY
        ld ix,ACTOR                 ; la camara, donde el protagonista, y siguiendole
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        ld (CAM_CUR),hl
        ld (CAM_DEST),hl
        ld a,(KN)
        push af
        ld hl,CAMFOLLOWS            ; (tambien puede cambiar de habitacion)
        call SAFECALL
        call RESTOREIY
        pop af
        call KACTA
        ld hl,(KLX)                 ; x = -1: no anda
        ld a,h
        and l
        inc a
        jp z,RESTOREIY
        ld de,(KLY)
        ld bc,-1
        jp KWALKTO

; startScene: todos los actores, ocultos
K_HIDEALL:
        ld a,1
.lp:    ld (KI),a
        ld e,R_VIS
        call ACTRD
        ld a,l
        or a
        jr z,.n
        ld a,(KI)
        call ACTLOAD
        call KHIDE
.n:     ld a,(KI)
        inc a
        cp NACT
        jr nz,.lp
        ret

; showActors: los de la habitacion, a la vista
K_SHOWALL:
        ld a,1
.lp:    ld (KI),a
        call INROOM
        jr nc,.n
        ld a,(KI)
        call ACTLOAD
        call KSHOW
.n:     ld a,(KI)
        inc a
        cp NACT
        jr nz,.lp
        ret

; loadRoomWithEgo (desde startScene): el protagonista en el objeto HL de la
; habitacion A, mirando al reves que el objeto (K_EGOATOBJ) o sin girarse
K_EGOATOBJ:
        ld c,1
        jr KEAO
K_EGOATOBJ2:
        ld c,0
KEAO:   ld (KPR),a
        ld a,c
        ld (KC),a
        push hl
        call KEGO
        pop hl
        ret nc
        call KOBJXYD
        ret nc
        ld (KPX),hl
        ld (KPY),de
        call KPUT
        call KRELOAD
        ld a,(KC)
        or a
        jr z,.nd
        ld hl,(KDIR)
        ld de,180
        add hl,de
        call SETDIR
.nd:    ld (ix+A_MOV),0
        ret

; --- andar y dibujarlos -------------------------------------------------------------------
; walkActors: los de la habitacion, por orden
K_WALKALL:
        ld a,1
.lp:    ld (KI),a
        call INROOM
        jr nc,.n
        ld a,(KI)
        call ACTLOAD
        call WALK
.n:     ld a,(KI)
        inc a
        cp NACT
        jr nz,.lp
        ret

; processActors (model.World.draw_actors): los actores de la habitacion,
; ordenados por y como SCUMM y compuestos de delante atras (COMPOSE les da
; los sprites de numero mas alto a los primeros), cada uno con el banco de
; paleta de su numero y su elevacion; despues de dibujarse, se animan. Los
; que no estan se quedan sin tiras (para actorFromPos).
K_CASTDRAW:
        ld a,(SHMMU7)               ; desplazamiento suave (capa SM): de momento nadie
        push af                     ; se ha movido; lo que dura el paso y si la
        ld a,SM_PAGE                ; habitacion es ancha (la franja)
        call MAP7
        ld hl,SMPDX
        ld (hl),0
        ld de,SMPDX+1
        ld bc,2*NSPR_ACTOR-1
        ldir
        ld a,(TICKV)
        ld (SMPTICK),a
        ld hl,(RW)
        ld de,321
        or a
        sbc hl,de
        sbc a,a
        inc a
        ld (SMPBAND),a
        pop af
        call MAP7
        ld a,(SKIPDRAW)             ; sin pintar: los sprites de antes, movidos con
        or a                        ; la camara
        jr z,.hide
        call KSHIFT
        jr .h
.hide:  call HIDEACT
        ld hl,(LEFT)
        ld (LDRAWN),hl
.h:
        xor a                       ; la lista: (y, actor) de los que estan aqui
        ld (CLN),a
        inc a
.ls:    ld (CACT),a
        call INROOM
        jr nc,.out
        ld a,(CACT)
        ld e,A_Y
        call ACTRD
        ex de,hl
        ld a,(CLN)
        call CLREC
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld a,(CACT)
        ld (hl),a
        ld hl,CLN
        inc (hl)
        jr .ln
.out:   ld a,(CACT)
        ld hl,KMV                   ; (ya no se sabe donde se pinto)
        add hl,a
        ld (hl),0
        ld a,(CACT)
        ld e,R_STR0
        ld hl,$FFFF
        call ACTWR
        ld a,(CACT)
        ld e,R_STR1
        ld hl,$FFFF
        call ACTWR
.ln:    ld a,(CACT)
        inc a
        cp NACT
        jr nz,.ls
        ; el orden de processActors: para cada i, para cada j, si y[i] < y[j], se cambian
        xor a
.si:    ld (CSI),a
        xor a
.sj:    ld (CSJ),a
        ld a,(CSJ)
        call CLREC
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,(CSI)
        call CLREC
        push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call CPS16                  ; y[i] < y[j] ?
        pop hl
        jr nc,.ns
        push hl
        ld a,(CSJ)
        call CLREC
        pop de
        ld b,3
.sw:    ld a,(de)
        ld c,(hl)
        ld (hl),a
        ld a,c
        ld (de),a
        inc hl
        inc de
        djnz .sw
.ns:    ld a,(CLN)
        ld b,a
        ld a,(CSJ)
        inc a
        cp b
        jr c,.sj
        ld a,(CSI)
        inc a
        cp b
        jr c,.si
        ; de delante (la y mas alta, al final de la lista) atras
        ld a,(CLN)
.dl:    or a
        jp z,ACTSYNC
        dec a
        ld (CLK),a
        call CLREC
        inc hl
        inc hl
        ld a,(hl)
        call CASTONE
        ld a,(CLK)
        jr .dl

; Los sprites de los actores, movidos lo que se ha movido la camara desde que se
; pintaron (en los pasos que no se pintan)
KSHIFT:
        ld hl,(LDRAWN)
        ld de,(LEFT)
        ld (LDRAWN),de
        or a
        sbc hl,de
        ld a,h
        or l
        ret z
        ld (KSD),hl
        ld hl,ATTRBUF
        ld b,NSPR_ACTOR
.lp:    push bc
        push hl
        ld a,(hl)                   ; x (9 bits: el alto, en el bit 0 del byte 2)
        inc hl
        inc hl
        ld c,(hl)
        inc hl
        bit 7,(hl)                  ; (solo los que se ven)
        jr z,.n
        ld l,a
        ld a,c
        and 1
        ld h,a
        ld de,(KSD)
        add hl,de
        ld a,h
        and 1
        ld d,a
        ld e,l
        pop hl
        push hl
        ld (hl),e
        inc hl
        inc hl
        ld a,c
        and $FE
        or d
        ld (hl),a
.n:     pop hl
        ld de,5
        add hl,de
        pop bc
        djnz .lp
        ret

; --- los dibujos guardados ---------------------------------------------------------
; Una cola en KPN paginas (las 24 desde ACACHE_PAGE y las 10 desde KP2_PAGE; la 223 es
; SPRB_PAGE): cada
; dibujo, seguido (nunca entre dos paginas): el actor, la firma (lo que decide como
; sale), cuantos tiles, donde va cada uno (TLIST) y los tiles. El indice KCDIR tiene los
; KDMAX ultimos (pagina, posicion, actor, suma de la firma), del mas viejo (KDHEAD) al
; mas nuevo; el que se guarda pisa a los mas viejos. Asi un actor que repite sus
; dibujos (los piratas del bar) casi nunca se pinta.
KPN      EQU 34
KP2_PAGE EQU 213
        ASSERT KP2_PAGE + KPN - 24 <= SPRB_PAGE
KDMAX    EQU 128
KE_SIG   EQU 1
KE_N     EQU KE_SIG+KSIGLEN
KE_TL    EQU KE_N+1

; Ninguno guardado (VMINIT), y los sellos de las tiras a 0
K_CACHECLR:
        ld a,(SHMMU7)
        push af
        ld a,ZSCR_PAGE
        call MAP7
        ld hl,$E000+ZGENO
        ld (hl),0
        ld de,$E000+ZGENO+1
        ld bc,2+256-1
        ldir
        pop af
        call MAP7
        xor a
        ld (KDHEAD),a
        ld (KDCNT),a
        ld (KPPG),a
        ld h,a
        ld l,a
        ld (KPOFF),hl
        ret

; (desde COMPOSE) Carry si el actor no se ve (BMINX..BMAXX fuera de [LEFT, LEFT +
; 320)): no se pinta. Si se ve, las tiras que tapa (R_STR0..R_STR1) que cambiaron
; fuera de la vista (STALE), al dia: sus planos Z hacen falta para taparlo
K_ZFRESH:
        ld hl,(BMAXX)
        ld de,(LEFT)
        call CPS16
        ret c                       ; todo a la izquierda
        ld hl,(LEFT)
        ld de,320
        add hl,de
        ex de,hl
        ld hl,(BMINX)
        call CPS16
        ccf
        ret c                       ; todo a la derecha
        ld a,(ACTOR+R_STR0)
        ld c,a
        ld a,(ACTOR+R_STR1)
        ld b,a
        ld a,(RNS)
        dec a
        cp b
        jr nc,.lp
        ld b,a
.lp:    ld a,b
        cp c
        jr c,.end
        push bc
        ld a,c
        call FRESH
        pop bc
        inc c
        jr .lp
.end:   or a
        ret

; DE = el sello mas reciente de las tiras que tapa el actor (R_STR0..R_STR1): cambia
; si cambian sus planos Z (no cambia HL)
KZMAX:  push hl
        ld a,(SHMMU7)
        push af
        ld a,ZSCR_PAGE
        call MAP7
        ld de,0
        ld a,(ACTOR+R_STR0)
        ld c,a
        ld a,(ACTOR+R_STR1)
        ld b,a
        ld a,(RNS)
        dec a
        cp b
        jr nc,.lp
        ld b,a
.lp:    ld a,b
        cp c
        jr c,.end
        push bc
        ld l,c
        ld h,0
        add hl,hl
        ld bc,$E000+ZSTO
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call CPU16
        jr c,.nm
        ex de,hl
.nm:    pop bc
        inc c
        jr .lp
.end:   pop af
        call MAP7
        pop hl
        ret

; HL = KHT + 8 * actor + (suma de la firma and 7): el sitio en el indice del ultimo
; dibujo de este actor con esa suma (no cambia BC ni DE)
KHTPTR: ld a,(CABANK)
        and 15
        add a,a
        add a,a
        add a,a
        ld l,a
        ld a,(KHASH)
        and 7
        or l
        ld hl,KHT
        add hl,a
        ret

; A = la pagina de la pagina logica A de la cola
KPHYS:  cp 24
        jr nc,.h
        add a,ACACHE_PAGE
        ret
.h:     add a,KP2_PAGE-24
        ret

; HL = la entrada A del indice (KCDIR + 5 * ((KDHEAD + A) mod KDMAX))
KDENT:  ld hl,KDHEAD
        add a,(hl)
        and KDMAX-1
        ld e,a
        ld d,5
        mul d,e
        ld hl,KCDIR
        add hl,de
        ret

; (desde COMPOSE, con el lienzo ya repartido) Si el dibujo del actor CABANK ya esta
; guardado: sus tiles a SPRBUF, sus atributos y carry. Deja la firma en KSIG.
K_CACHEUSE:
        ld hl,KSIG                  ; la firma
        ld a,(ACTOR+R_COST)
        ld (hl),a
        inc hl
        ld a,(CMAPB+1)              ; (su primera pagina)
        ld (hl),a
        inc hl
        ex de,hl
        ld hl,CCODES                ; lo que pinta cada miembro (aunque la animacion
        ld bc,16                    ; vaya por otro sitio, si es el mismo dibujo vale)
        ldir
        ex de,hl
        ld a,(CMIR)
        ld (hl),a
        inc hl
        ld a,(CSC)
        ld (hl),a
        inc hl
        ld a,(CZB)
        ld (hl),a
        inc hl
        push hl
        call KFREE                  ; nz: el dibujo (sin el plano) no depende de donde esta
        ld (KUSEF),a
        ld b,a                      ; con plano Z, sin posicion = se ha movido: si la vez
        ld a,(CZB)                  ; anterior no, se guarda tambien recortado y con su
        or a                        ; posicion (KSAVEPOS: seguramente se queda quieto, como
        jr nz,.zb                   ; las nubes de la presentacion)
        ld b,a
.zb:    ld a,(CACT)
        ld hl,KPMV
        add hl,a
        ld a,(hl)
        ld (hl),b
        cpl
        and b
        ld (KSAVP),a
        ld a,(KUSEF)
        or a                        ; (Z: con posicion)
        pop hl
        jr z,.pos
        ld de,$8000                 ; (x e y que no pueden ser, sin elevacion)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld de,(CGEN)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),a                   ; (ni sello: el plano no tapa nada)
        inc hl
        ld (hl),a
        inc hl
        jr .c8
.pos:   ld de,(ACTOR+A_X)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(ACTOR+A_Y)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(CELEV)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(CGEN)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        call KZMAX                  ; y el sello de las tiras que tapa
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
.c8:
        ld a,(C8)
        ld (hl),a
        inc hl
        ld a,(CTW)
        ld (hl),a
        inc hl
        ld a,(CTH)
        ld (hl),a
        ld hl,KSIG                  ; su suma
        ld b,KSIGLEN
        xor a
.hs:    add a,(hl)
        inc hl
        djnz .hs
        ld (KHASH),a
        ld a,(SHMMU7)
        ld (KCM7),a
        call KHTPTR                 ; primero el ultimo de este actor con la misma suma
        ld a,(KDHEAD)               ; (si sigue en el indice)
        ld b,a
        ld a,(hl)
        sub b
        and KDMAX-1
        ld hl,KDCNT
        cp (hl)
        jr nc,.all
        ld (KK),a
        ld a,1
        ld (KFST),a
        jr .chk
.all:   xor a                       ; si no, todos, del mas nuevo al mas viejo
        ld (KFST),a
        ld a,(KDCNT)
.lk:    or a                        ; (A = los que quedan: de A - 1 a 0, con un puntero
        jp z,.no                    ; al actor de cada uno; D = cuantos hasta el
        ld b,a                      ; principio de KCDIR)
        dec a
        ld hl,KDHEAD
        add a,(hl)
        and KDMAX-1
        ld e,a
        inc a
        ld (KFD),a
        ld d,5
        mul d,e
        ld hl,KCDIR+3
        add hl,de
        ld a,(KFD)
        ld d,a
        ld a,(CABANK)
        ld c,a
        ld a,(KHASH)
        ld e,a
.fs:    ld a,(hl)
        cp c
        jr z,.fa
.fn:    dec d
        jr z,.fw
        add hl,-5
        djnz .fs
        jp .no
.fw:    ld hl,KCDIR+3+5*(KDMAX-1)
        ld d,KDMAX
        djnz .fs
        jp .no
.fa:    inc hl                      ; (el actor; y la suma?)
        ld a,(hl)
        dec hl
        cp e
        jr nz,.fn
        ld a,b                      ; la entrada B - 1, entera
        dec a
        ld (KK),a
.chk:   ld a,(KK)
        call KDENT
        push hl
        inc hl
        inc hl
        inc hl
        ld a,(CABANK)
        cp (hl)
        jp nz,.nx
        inc hl
        ld a,(KHASH)
        cp (hl)
        jp nz,.nx
        pop hl
        push hl
        ld a,(hl)
        call KPHYS
        call MAP7
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,$E000+KE_SIG
        add hl,de
        ld de,KSIG
        ld b,KSIGLEN
.cm:    ld a,(de)
        cp (hl)
        jp nz,.nx
        inc hl
        inc de
        djnz .cm
        pop de
        push hl                     ; (la proxima vez, este primero)
        ld a,(KDHEAD)
        ld hl,KK
        add a,(hl)
        and KDMAX-1
        ld e,a
        call KHTPTR
        ld (hl),e
        pop hl
        ld a,(hl)                   ; el mismo: cuantos tiles y donde va cada uno
        ld (KCN),a
        inc hl
        ld c,a
        ld b,0
        or a
        jr z,.t0
        ld de,KCTL
        ldir
.t0:    push hl                     ; (los tiles)
        ld hl,(CSTART)              ; el hueco hasta el lienzo, a 0
        ld de,(SPRUSED)
        or a
        sbc hl,de
        jr z,.ng
        ld b,h
        ld c,l
        ld hl,SPRBUF
        add hl,de
        ld (hl),0
        ld d,h
        ld e,l
        inc de
        dec bc
        ld a,b
        or c
        jr z,.ng
        ldir
.ng:    ld de,(CSTART)              ; los tiles, detras de los anteriores
        ld hl,SPRBUF
        add hl,de
        ex de,hl
        pop hl
        call KCLEN
        call KFAST
        ld a,(KDCNT)                ; si ya esta en el cuarto mas viejo de la cola, otra
        srl a                       ; vez al final (lo que se usa no se pierde: las
        srl a                       ; nubes de la presentacion, que guardan uno nuevo
        ld b,a                      ; cada vez que se mueven, echaban el suyo)
        ld a,(KK)
        cp b
        jr nc,.fr
        ld a,(KCN)
        ld hl,KCTL
        call KRESAVE
.fr:    ld a,(KUSEF)                ; (sin el plano: lo que tapa, ahora)
        or a
        jr z,.nm
        ld a,(KCN)
        ld hl,KCTL
        call KZMASK
        ld (KCN),a
        ld a,(KSAVP)
        or a
        jr z,.nm
        ld a,(KCN)
        ld hl,KCTL
        call KSAVEPOS
.nm:    ld a,(KCN)                  ; (y lo que tapa el texto)
        ld hl,KCTL
        call KTXMASK
        ld (KCN),a
        call KCLEN
        xor a                       ; y sus atributos (TATTR, como en PACKTILES)
.at:    ld (PN),a
        ld hl,KCN
        cp (hl)
        jr z,.ok
        ld hl,KCTL
        add hl,a
        ld a,(hl)
        and $0F
        ld (PTX),a
        ld a,(hl)
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld (PTY),a
        call TATTR
        ld a,(PN)
        inc a
        jr .at
.ok:    ld hl,(CSTART)
        ld de,(KCLENV)
        add hl,de
        ld (SPRUSED),hl
        ld a,(KCN)
        ld hl,SPRK
        add a,(hl)
        ld (hl),a
        ld a,(KCM7)
        call MAP7
        scf
        ret
.nx:    pop hl
        ld a,(KFST)                 ; (no era el de la misma suma: todos)
        or a
        jr z,.nx1
        xor a
        ld (KFST),a
        ld a,(KDCNT)
        jp .lk
.nx1:   ld a,(KK)
        jp .lk
.no:    ld a,(KCM7)
        call MAP7
        ld a,(KUSEF)                ; sin posicion: se pinta sin el plano (y asi se
        or a                        ; guarda); K_CACHESAVE recorta despues
        jr z,.nz
        ld a,(CZB)
        or a
        jr z,.nz
        ld (KCZB),a
        xor a
        ld (CZB),a
        inc a
        ld (KUNM),a
.nz:    or a
        ret

; (desde COMPOSE, despues de PACKTILES: PN tiles desde CSTART) a la cola, con la
; firma que dejo K_CACHEUSE
K_CACHESAVE:
        call KCSAVE
        ld a,(PN)
        ld (KPN0),a
        ld b,a
        ld a,(KUNM)                 ; pintado sin el plano: ahora lo que tapa
        or a
        ld a,b
        jr z,.tx
        xor a
        ld (KUNM),a
        ld a,(KCZB)
        ld (CZB),a
        ld a,(PN)
        ld hl,TLIST
        call KZMASK
        push af
        ld a,(KSAVP)
        or a
        jr z,.ns
        pop af
        push af
        ld hl,TLIST
        call KSAVEPOS
.ns:    pop af
.tx:    ld hl,TLIST                 ; y lo que tapa el texto (lo guardado va sin eso)
        call KTXMASK
        ld hl,KPN0
        cp (hl)
        ret z                       ; (no se ha quedado vacio ninguno: todo igual)
        ld (KZMV),a
        ld a,(SPRK)                 ; los atributos otra vez: SPRK, el de antes del actor
        sub (hl)
        ld (SPRK),a
        xor a
.ra:    ld hl,KZMV
        cp (hl)
        jr z,.hd
        ld (PN),a
        ld hl,TLIST
        add hl,a
        ld a,(hl)
        and $0F
        ld (PTX),a
        ld a,(hl)
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld (PTY),a
        call TATTR
        ld a,(PN)
        inc a
        jr .ra
.hd:    ld hl,KPN0                  ; y los sprites que sobran, escondidos
        cp (hl)
        jr z,.fin
        ld (PN),a
        ld hl,SPRK
        add a,(hl)
        cpl
        add a,NSPR_ACTOR
        ld e,a
        ld d,5
        mul d,e
        ld hl,ATTRBUF
        add hl,de
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),$40
        inc hl
        ld (hl),a
        ld a,(PN)
        inc a
        jr .hd
.fin:   ld a,(KZMV)
        ld (PN),a
        ld hl,SPRK
        add a,(hl)
        ld (hl),a
        ld a,(KZMV)
        ld l,a
        ld h,0
        call TSIZE
        ld de,(CSTART)
        add hl,de
        ld (SPRUSED),hl
        ret

; Los A tiles recortados (su lista en HL; los tiles desde CSTART) a la cola tambien con
; posicion: la firma de K_CACHEUSE, pero con x, y, elevacion y el sello de las tiras
KSAVEPOS:
        ld (PN),a                   ; (KCSAVE: PN tiles y su lista en TLIST)
        ld c,a
        ld b,0
        or a
        jr z,.l
        ld de,TLIST
        ldir
.l:     ld hl,KSIG+21
        ld de,(ACTOR+A_X)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(ACTOR+A_Y)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(CELEV)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(CGEN)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        call KZMAX
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,KSIG                  ; su suma
        ld b,KSIGLEN
        xor a
.hs:    add a,(hl)
        inc hl
        djnz .hs
        ld (KHASH),a
        ld a,(KCM7)                 ; (KCSAVE la cambia; la de antes de mirar la cola)
        push af
        call KCSAVE
        pop af
        ld (KCM7),a
        ret

; Los A tiles (su lista en HL; los tiles desde CSTART) a la cola otra vez, con la
; misma firma
KRESAVE:
        ld (PN),a                   ; (KCSAVE: PN tiles y su lista en TLIST)
        ld c,a
        ld b,0
        or a
        jr z,.s
        ld de,TLIST
        ldir
.s:     ld a,(KCM7)                 ; (KCSAVE la cambia; la de antes de mirar la cola)
        push af
        call KCSAVE
        pop af
        ld (KCM7),a
        ret

; (lo de K_CACHESAVE) A la cola, con la firma que dejo K_CACHEUSE
KCSAVE:
        ld a,(SHMMU7)
        ld (KCM7),a
        ld a,(PN)
        ld (KCN),a
        call KCLEN                  ; lo que ocupa: KE_TL + PN + los tiles
        ld hl,KE_TL
        add hl,bc
        ld a,(PN)
        add hl,a
        ld (KSZ),hl
        ld de,$2001                 ; (mas de una pagina: no se guarda)
        call CPU16
        ret nc
        ld de,(KPOFF)               ; si no cabe en lo que queda de la pagina, a la
        add hl,de                   ; siguiente (lo que quede de las viejas en esta
        ld de,$2001                 ; se olvida: la cola, en orden)
        call CPU16
        jr c,.ev
.vp:    call .head                  ; (las viejas que quedan por delante en esta pagina)
        jr nc,.np
        call .pop
        jr .vp
.np:    ld a,(KPPG)
        inc a
        cp KPN
        jr c,.p1
        xor a
.p1:    ld (KPPG),a
        ld hl,0
        ld (KPOFF),hl
.ev:    ld a,(KDCNT)                ; lo que se va a pisar: el mas viejo, mientras
        cp KDMAX                    ; este en esta pagina entre donde empieza y donde
        jr z,.ep                    ; acaba este (o si el indice esta lleno)
        call .head
        jr nc,.put
        push hl
        ld hl,(KPOFF)
        ld de,(KSZ)
        add hl,de
        ex de,hl
        pop hl                      ; HL = donde empieza el viejo, DE = donde acaba este
        call CPU16
        jr nc,.put
.ep:    call .pop
        jr .ev
.put:   ld a,(KDHEAD)               ; (su sitio en el indice: el primero que se mira
        ld hl,KDCNT                 ; la proxima vez con esta suma)
        add a,(hl)
        and KDMAX-1
        ld e,a
        call KHTPTR
        ld (hl),e
        ld a,(KPPG)
        call KPHYS
        call MAP7
        ld hl,(KPOFF)
        ld de,$E000
        add hl,de
        ld a,(CABANK)
        ld (hl),a
        inc hl
        ex de,hl
        ld hl,KSIG
        ld bc,KSIGLEN
        ldir
        ld a,(PN)
        ld (de),a
        inc de
        ld c,a
        ld b,0
        or a
        jr z,.t0
        ld hl,TLIST
        ldir
.t0:    ld hl,(CSTART)              ; los tiles
        ld bc,SPRBUF
        add hl,bc
        ld bc,(KCLENV)
        call KFAST
        ld a,(KDCNT)                ; al indice, el ultimo
        call KDENT
        ld a,(KPPG)
        ld (hl),a
        inc hl
        ld de,(KPOFF)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld a,(CABANK)
        ld (hl),a
        inc hl
        ld a,(KHASH)
        ld (hl),a
        ld hl,KDCNT
        inc (hl)
        ld hl,(KPOFF)
        ld de,(KSZ)
        add hl,de
        ld (KPOFF),hl
        ld a,(KCM7)
        jp MAP7
; carry si el mas viejo del indice esta en esta pagina, en KPOFF o detras (es de la
; vuelta anterior: lo de delante de KPOFF es de esta); HL = donde empieza
.head:  ld a,(KDCNT)
        or a
        ret z
        xor a
        call KDENT
        ld a,(KPPG)
        cp (hl)
        jr nz,.hn
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld de,(KPOFF)
        call CPU16                  ; empieza antes de KPOFF: de esta vuelta
        ccf
        ret
.hn:    or a
        ret
; (el mas viejo del indice, fuera)
.pop:   ld a,(KDHEAD)
        inc a
        and KDMAX-1
        ld (KDHEAD),a
        ld hl,KDCNT
        dec (hl)
        ret

; KCLENV = BC = KCN tiles, en bytes (no cambia DE ni HL)
KCLEN:
        push de
        push hl
        ld a,(KCN)
        ld l,a
        ld h,0
        call TSIZE
        ld (KCLENV),hl
        ld b,h
        ld c,l
        pop hl
        pop de
        ret

; BC bytes de HL a DE (como LDIR: HL y DE avanzan, BC = 0). Desde 64 bytes, por el
; DMA (unas tres veces mas deprisa que LDI en el Next), a trozos de 256 con las
; interrupciones cortadas (la de linea tambien usa el DMA): el CTC (la musica), que no
; para el DMA (NR $CD a 0), espera menos de una muestra. Con ellas ya cortadas, LDIR.
KFAST:  ld a,b
        or a
        jr nz,.big
        ld a,c
        cp 64
        jr nc,.big
        or a
        ret z
.ld:    ldir                        ; (pocos, o con las interrupciones cortadas)
        ret
.big:   ld a,i                      ; P/V = IFF2
        jp po,.ld
.lp:    ld a,b
        or a
        jr z,.last
        push bc
        ld bc,256
        call .dma
        pop bc
        dec b
        jr .lp
.last:  ld a,c                      ; lo que queda (menos de 256)
        or a
        ret z
        cp 32
        jr c,.ld
        call .dma
        ld bc,0
        ret
.dma:   ld (KDSRC),hl               ; BC (1..256) bytes de HL a DE; los dos avanzan
        ld (KDDST),de
        ld (KDLEN),bc
        add hl,bc
        ex de,hl
        add hl,bc
        ex de,hl
        push hl
        push de
        ld hl,KDPROG
        ld bc,KDPLEN*256+$6B
        di
        otir
        ei
        pop de
        pop hl
        ret
KDPROG: db $83                      ; para el DMA
        db %01111101                ; WR0: de A a B, direccion y longitud
KDSRC:  dw 0
KDLEN:  dw 0
        db %01010100                ; WR1: A es memoria y avanza
        db %00000010
        db %01010000                ; WR2: B es memoria y avanza
        db %00000010
        db %10101101                ; WR4: continuo, direccion de B
KDDST:  dw 0
        db %10000010                ; WR5
        db $CF                      ; carga
        db $87                      ; en marcha
KDPLEN  EQU $-KDPROG

; (K_CACHEUSE) nz si el dibujo, sin el plano Z, no depende de donde esta el actor: su
; caja cabe en alto en la habitacion (no pierde filas; el lienzo va desde la caja). Lo
; que tapa el plano se quita despues (KZMASK).
KFREE:  ld hl,(BMINY)
        bit 7,h
        jr nz,.no
        ld hl,(BMAXY)
        ld de,(RH)
        call CPS16
        jr nc,.no
        ld a,(CZB)                  ; con plano Z y en el mismo sitio que la vez anterior
        or a                        ; (aunque no se viera): con posicion (se guarda ya
        jr z,.yes                   ; recortado y sale tal cual, sin recortar cada paso)
        ld a,(CACT)
        add a,a
        ld hl,KMX
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(ACTOR+A_X)
        or a
        sbc hl,de
        jr nz,.yes
        ld a,(CACT)
        add a,a
        ld hl,KMY
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(ACTOR+A_Y)
        ld bc,(CELEV)
        or a
        sbc hl,bc
        or a
        sbc hl,de
        jr z,.no
.yes:   ld a,1
        or a
        ret
.no:    xor a
        ret

; (KSMOOTH) nz si el plano CZB tapa algo en la caja del dibujo (BMINX..BMAXX,
; BMINY..BMAXY) o en la de antes de moverse HL = dx, DE = dy
KZSWEPT:
        push de
        ld de,(BMINX)
        ld bc,(BMAXX)
        call .rng
        ld (KZX0),de
        ld (KZX1),bc
        pop hl
        ld de,(BMINY)
        ld bc,(BMAXY)
        call .rng
        ld (KZY0),de
        ld (KZY1),bc
        jp KZSCAN
; [DE, BC] y lo mismo d = HL antes: d > 0, DE -= d; d < 0, BC -= d
.rng:   bit 7,h
        jr nz,.neg
        ex de,hl
        or a
        sbc hl,de
        ex de,hl
        ret
.neg:   push hl
        ld h,b
        ld l,c
        pop bc
        or a
        sbc hl,bc
        ld b,h
        ld c,l
        ret

; Z si el plano CZB de las tiras de trabajo no tiene nada en x [KZX0, KZX1] e y
; [KZY0, KZY1] (de la habitacion: se recortan a ella); nz si algo. MMU7, como estaba.
KZSCAN:
        call KZCLIP
        jp c,.none
        ld a,(KZX0)                 ; de la primera, los pixeles desde x0
        and 7
        ld b,a
        ld a,$FF
        jr z,.m0
.ml0:   srl a
        djnz .ml0
.m0:    ld (KZMK0),a
        ld a,(KZX1)                 ; de la ultima, hasta x1
        and 7
        xor 7
        ld b,a
        ld a,$FF
        jr z,.m1
.ml1:   add a,a
        djnz .ml1
.m1:    ld (KZMK1),a
        ld a,(SHMMU7)
        ld (KZM7),a
.st:    ld a,(KZS)                  ; la tira: su pagina y donde esta (por $C000)
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,(STRIPT)
        add hl,de
        ld a,(hl)
        add a,STRIP_PAGE
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        call MAP7                   ; (aqui, por $E000)
        ld hl,(CZOFF)
        add hl,de
        ld de,$2000
        add hl,de
        ld a,(KZY0)
        add hl,a
        ld a,(KZN)
        ld b,a
        xor a
.or:    or (hl)
        inc hl
        djnz .or
        ld c,a
        ld a,(KZS)
        ld hl,KZS0
        cp (hl)
        jr nz,.n0
        ld a,(KZMK0)
        and c
        ld c,a
.n0:    ld a,(KZS)
        ld hl,KZS1
        cp (hl)
        jr nz,.n1
        ld a,(KZMK1)
        and c
        ld c,a
.n1:    ld a,c
        or a
        jr nz,.got
        ld a,(KZS)
        ld hl,KZS1
        cp (hl)
        jr z,.end
        inc a
        ld (KZS),a
        jr .st
.got:   ld a,(KZM7)
        call MAP7
        or $FF                      ; (nz: tapa algo)
        ret
.end:   ld a,(KZM7)
        call MAP7
.none:  xor a                       ; (z: nada)
        ret
; (KZSCAN, KZMASK) La caja [KZX0, KZX1] x [KZY0, KZY1], dentro de la habitacion; sus
; filas (KZN) y tiras (KZS0, KZS1); carry si no queda nada
KZCLIP:
        ld hl,(KZX0)
        call .lo0
        ld (KZX0),hl
        ld hl,(KZY0)
        call .lo0
        ld (KZY0),hl
        ld hl,(RW)
        ld de,(KZX1)
        call .hi
        ld (KZX1),hl
        ld hl,(RH)
        ld de,(KZY1)
        call .hi
        ld (KZY1),hl
        ld de,(KZY0)                ; (y1 < y0 o x1 < x0: nada)
        call CPS16
        ret c
        ld hl,(KZX1)
        ld de,(KZX0)
        call CPS16
        ret c
        ld a,(KZY1)                 ; filas
        ld hl,KZY0
        sub (hl)
        inc a
        ld (KZN),a
        ld hl,(KZX0)                ; tiras [KZS0, KZS1]
        call SHR3
        ld a,l
        ld (KZS0),a
        ld (KZS),a
        ld hl,(KZX1)
        call SHR3
        ld a,l
        ld (KZS1),a
        or a
        ret
.lo0:   bit 7,h                     ; HL = max(HL, 0)
        ret z
        ld hl,0
        ret
.hi:    dec hl                      ; HL = min(DE, HL - 1)
        ex de,hl
        call CPS16
        ret c
        ex de,hl
        ret


; Quita lo que tapa el plano CZB de los A tiles juntados (desde CBT; donde va cada uno,
; en la lista HL: ty * 16 + tx) y despues los que se quedan vacios (los demas, juntos y
; en orden; la lista tambien). A = los que quedan.
KZMASK: ld (KMN),a
        ld (KMLST),hl
        ld b,a
        ld a,(CZB)
        or a
        jp z,.same
        ld a,b
        or a
        jp z,.same
        call KTMAPB
        ld hl,(BMINX)               ; la caja del dibujo, dentro de la habitacion
        ld (KZX0),hl
        ld hl,(BMAXX)
        ld (KZX1),hl
        ld hl,(BMINY)
        ld (KZY0),hl
        ld hl,(BMAXY)
        ld (KZY1),hl
        call KZCLIP
        jp c,.same
        call KZALL                  ; lo tapa todo: ningun tile
        jr nz,.part
        xor a
        ret
.part:  ld a,(SHMMU7)
        ld (KZM7),a
        ld a,(KZS0)
        ld (KZS),a
.st:    ld a,(KZS)                  ; la tira: su plano por $E000
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,(STRIPT)
        add hl,de
        ld a,(hl)
        add a,STRIP_PAGE
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        call MAP7
        ld hl,(CZOFF)
        add hl,de
        ld de,$2000
        add hl,de
        ld a,(KZY0)
        add hl,a
        ld (KMZP),hl
        ld a,(KZS)                  ; x del lienzo de su primer pixel: 8 * tira - BMINX
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,(BMINX)
        or a
        sbc hl,de
        ld (KMXS),hl
        ld a,(KZY0)
        ld (KMRY),a
        ld a,(KZN)
        ld (KMR),a
        ld a,(C8)                   ; 4 bits y la tira (x de -7 a CW16 - 1) en el
        or a                        ; lienzo: KZSTRIP
        jr nz,.row
        ld hl,(KMXS)
        ld a,h
        or a
        jr z,.xp
        inc a
        jr nz,.row
        ld a,l
        cp $F9
        jr c,.row
        jr .ks
.xp:    ld a,(CW16)
        dec a
        cp l
        jr c,.row
.ks:    call KZSTRIP
        jr .nxs
.row:   ld hl,(KMZP)
        ld a,(hl)
        inc hl
        ld (KMZP),hl
        or a
        jr z,.nrow
        ld (KMB),a
        ld a,(KMRY)                  ; y del lienzo
        ld hl,BMINY
        sub (hl)
        ld (KMCY),a
        ld hl,(KMXS)                ; los 8 dentro del lienzo: por tramos de tapados
        ld a,h
        or a
        jr nz,.bits
        ld a,(CW16)
        sub 8
        jr c,.bits
        cp l
        jr c,.bits
        ld a,(KMB)
        call KMBYTE
        jr .nrow
.bits:  ld b,0
.bit:   ld a,(KMB)                  ; (bit 7: el primer pixel de la tira)
        add a,a
        ld (KMB),a
        jr nc,.nb
        push bc
        ld hl,(KMXS)
        ld a,b
        add hl,a
        bit 7,h
        jr nz,.skip
        ld a,h
        or a
        jr nz,.skip
        ld a,(CW16)
        ld c,a
        ld a,l
        cp c
        jr nc,.skip
        call KMCLR
.skip:  pop bc
.nb:    inc b
        ld a,(KMB)
        or a
        jr nz,.bit
.nrow:  ld hl,KMRY
        inc (hl)
        ld hl,KMR
        dec (hl)
        jr nz,.row
.nxs:   ld a,(KZS)
        ld hl,KZS1
        cp (hl)
        jr z,.done
        inc a
        ld (KZS),a
        jp .st
.done:  ld a,(KZM7)
        call MAP7
        jp KZPACK
.same:  ld a,(KMN)
        ret

; (KZMASK) La tira (KMZP, KMRY, KMR filas) en un lienzo de 4 bits, con sus 8 pixeles
; desde x = KMXS (de -7 a CW16 - 1): fila a fila, con la direccion de la fila sabida (la
; de los dos tiles, A desde la columna x y B detras, una vez por fila de tiles; lo de
; fuera del lienzo, en un tile que no esta)
KZSTRIP:
        ld a,(KMXS)
        and $0F
        ld (KZXO),a                 ; s: la columna en el tile A
        ld b,a
        ld a,16
        sub b
        cp 8
        jr c,.na
        ld a,8
.na:    ld (KZNA),a                 ; los de A: min(8, 16 - s); los de B, el resto
        ld b,a
        ld a,8
        sub b
        ld (KZNB),a
        ld a,(KMXS)
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld (KZTX),a                 ; (15: x < 0)
        ld a,(KMRY)
        ld hl,BMINY
        sub (hl)
        ld (KMCY),a
        ld a,$FF
        ld (KZTR),a
        ld de,(KMZP)
.lp:    ld a,(de)                   ; los bits de la fila (bit 7: x)
        inc de
        or a
        jp z,.next
        ld c,a
        ld a,(KMCY)                 ; su fila de tiles
        and $F0
        ld hl,KZTR
        cp (hl)
        call nz,KZTROW
        ld a,(KMCY)                 ; la fila en el tile * 8
        and $0F
        add a,a
        add a,a
        add a,a
        ld (KZRO),a
        ld hl,(KZRA)
        ld a,h
        or l
        jr z,.noa                   ; (el tile A no esta)
        ld a,(KZRO)
        add hl,a
        ld a,(KZNB)
        or a
        jr nz,.two
        ld a,c                      ; en un tile
        inc a
        jr nz,.pa
        ld a,(KZXO)                 ; los 8: de golpe
        rrca
        jr c,.odd
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        jr .next
.odd:   ld a,(hl)                   ; (empieza en uno de la derecha)
        and $F0
        ld (hl),a
        inc hl
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld a,(hl)
        and $0F
        ld (hl),a
        jr .next
.pa:    ld b,8                      ; algunos
        call .pix
        jr .next
.two:   ld a,(KZNA)                 ; entre dos: los de A
        ld b,a
        ld a,c
        inc a
        jr nz,.tpa
        ld a,(KZXO)                 ; (todos: los de A y los de B, de golpe)
        ld c,a
        call KMRUN.k4
        ld hl,(KZRB)
        ld a,h
        or l
        jr z,.next
        ld a,(KZRO)
        add hl,a
        ld a,(KZNB)
        ld b,a
        ld c,0
        call KMRUN.k4
        jr .next
.tpa:   call .pix
        jr .b
.noa:   ld a,(KZNB)                 ; (sin A: los suyos, fuera de C)
        or a
        jr z,.next
        ld a,(KZNA)
        ld b,a
.sh:    sla c
        djnz .sh
        jr z,.next
.b:     ld hl,(KZRB)                ; y los de B, desde su columna 0
        ld a,h
        or l
        jr z,.next
        ld a,(KZRO)
        add hl,a
        ld a,(KZNB)
        ld b,a
        call KZPIXE
.next:  ld hl,KMCY
        inc (hl)
        ld hl,KMR
        dec (hl)
        jp nz,.lp
        ret
.pix:   ld a,(KZXO)                 ; B de C desde la columna s (en HL)
        rrca
        jp c,KZPIXO
        jp KZPIXE

; (KZSTRIP) Otra fila de tiles (A = su y * 16, en KZTR por HL): KZRA = la direccion de la
; fila 0 del tile A en la columna s, KZRB = la del tile B (si hace falta); 0 si no esta
; (o se sale del lienzo)
KZTROW: ld (hl),a
        rrca
        ld b,a                      ; (y * 8)
        ld a,(KZTX)
        cp 8
        ld hl,0
        jr nc,.a
        add a,b
        ld hl,KTMAP
        add hl,a
        ld a,(hl)
        ld hl,0
        cp $FF
        jr z,.a
        call TILEADDR               ; (no cambia BC ni DE)
        ld a,(KZXO)
        srl a
        add hl,a
.a:     ld (KZRA),hl
        ld a,(KZNB)
        or a
        ret z
        ld a,(KZTX)
        inc a
        and $0F
        cp 8
        ld hl,0
        jr nc,.b
        add a,b
        ld hl,KTMAP
        add hl,a
        ld a,(hl)
        ld hl,0
        cp $FF
        jr z,.b
        call TILEADDR
.b:     ld (KZRB),hl
        ret

; (KZSTRIP) B pixeles de C (bit 7 el primero; C sale corrido B bits) desde la mitad de
; la derecha (KZPIXO) o de la izquierda (KZPIXE) de (HL), fuera los tapados
KZPIXO: sla c
        jr nc,.o
        ld a,(hl)
        and $F0
        ld (hl),a
.o:     inc hl
        dec b
        ret z
KZPIXE:
.lp:    ld a,b
        cp 2
        jr c,.last
        ld a,c
        and $C0
        jr z,.n
        cp $C0
        jr z,.both
        cp $80
        ld a,(hl)
        jr nz,.r
        and $0F                     ; (el de la izquierda)
        jr .w
.r:     and $F0                     ; (el de la derecha)
.w:     ld (hl),a
        jr .n
.both:  ld (hl),0
.n:     inc hl
        sla c
        sla c
        ret z                       ; (ya no quedan tapados)
        dec b
        djnz .lp
        ret
.last:  or a
        ret z
        sla c
        ret nc
        ld a,(hl)
        and $0F
        ld (hl),a
        ret

; (KZMASK) Los pixeles tapados de A (bit 7: el de x = L del lienzo; los 8 dentro) en la
; fila KMCY, fuera: cada tramo de seguidos de una vez
KMBYTE: ld e,l
.sk:    or a                        ; (sin tapados: nada)
        ret z
        add a,a                     ; los de delante sin tapar
        jr c,.run
        inc e
        jr .sk
.run:   ld b,1                      ; un tramo: cuantos seguidos
.rl:    add a,a
        jr nc,.re
        inc b
        jr .rl
.re:    push af
        ld c,b
        ld a,e
        add a,c
        ld (KMNX),a                 ; (donde sigue: detras del tramo y el 0)
        call KMRUNX
        ld a,(KMNX)
        inc a
        ld e,a
        pop af
        jr .sk

; B pixeles desde x = E (del lienzo), en uno o dos tiles (cortado por su borde)
KMRUNX: ld a,e
        and $0F
        ld c,a
        ld a,16
        sub c                       ; los que quedan en su tile
        cp b
        jr nc,KMRUN
        ld c,a
        ld a,b
        sub c
        push af
        ld b,c
        push de
        push bc
        call KMRUN
        pop bc
        pop de
        ld a,e
        add a,b
        ld e,a
        pop af
        ld b,a

; B pixeles desde x = E (del lienzo, en el mismo tile) en la fila KMCY, fuera (como
; KMCLR, pero de una vez; nada si el tile ya no esta)
KMRUN:  ld a,(KMCY)
        and $F0
        rrca
        ld c,a
        ld a,e
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a,c
        ld hl,KTMAP
        add hl,a
        ld a,(hl)
        cp $FF
        ret z
        call TILEADDR               ; (no cambia BC ni DE)
        ld a,(KMCY)
        and $0F
        ld d,a
        ld a,(C8)
        or a
        jr nz,.p8
        ld a,d                      ; 4 bits: fila * 8 + x / 2 (el izquierdo, arriba)
        add a,a
        add a,a
        add a,a
        ld d,a
        ld a,e
        and $0F
        ld c,a
        srl a
        add a,d
        add hl,a
.k4:    bit 0,c                     ; (KMRUN.k4: B desde (HL), la columna C) empieza en uno de la derecha
        jr z,.ev
        ld a,(hl)
        and $F0
        ld (hl),a
        inc hl
        dec b
        ret z
.ev:    ld a,b                      ; los pares enteros
        srl a
        jr z,.last
.pr:    ld (hl),0
        inc hl
        dec a
        jr nz,.pr
.last:  bit 0,b                     ; y uno de la izquierda al final
        ret z
        ld a,(hl)
        and $0F
        ld (hl),a
        ret
.p8:    ld a,d                      ; 8 bits: fila * 16 + x
        add a,a
        add a,a
        add a,a
        add a,a
        ld d,a
        ld a,e
        and $0F
        add a,d
        add hl,a
        xor a
.p8l:   ld (hl),a
        inc hl
        djnz .p8l
        ret

; (KZMASK, KTXMASK) KTMAP[ty * 8 + tx]: cual de los KMN tiles de la lista KMLST es, o $FF
KTMAPB: ld hl,KTMAP
        ld b,64
.c0:    ld (hl),$FF
        inc hl
        djnz .c0
        ld hl,(KMLST)
        ld c,0
.c1:    ld a,(hl)
        ld e,a
        and $0F
        ld d,a
        ld a,e
        and $F0
        rrca
        add a,d
        push hl
        ld hl,KTMAP
        add hl,a
        ld (hl),c
        pop hl
        inc hl
        inc c
        ld a,(KMN)
        cp c
        jr nz,.c1
        ret

; Quita de los A tiles juntados (como KZMASK; la lista HL) los pixeles del texto con
; mascara (la capa del texto, TMASK_PAGE: byte (columna de Layer 2 >> 3) * 200 + fila,
; bit columna & 7) que hay en MASKR, dentro de la vista y de la caja del dibujo; y
; despues los tiles que se quedan vacios. A = los que quedan. Asi el texto, en Layer 2
; debajo de los sprites, sale encima del actor, como en SCUMM. KTXHIT: alguno tapado.
KTXMASK:
        ld (KMN),a
        ld (KMLST),hl
        or a
        ret z
        ld a,(MASKV)
        or a
        jp z,.same
        ld hl,(BMINX)               ; x: de max(BMINX, MASKR x0, LEFT)
        ld de,(MASKR)
        call .max
        ld de,(LEFT)
        call .max
        ld (KZX0),hl
        ld hl,(MASKR+4)             ; a min(BMAXX, MASKR x1 - 1, LEFT + 319)
        dec hl
        ld de,(BMAXX)
        call .min
        push hl
        ld hl,(LEFT)
        ld de,319
        add hl,de
        ex de,hl
        pop hl
        call .min
        ld (KZX1),hl
        ld hl,(BMINY)               ; y: de max(BMINY, MASKR y0)
        ld de,(MASKR+2)
        call .max
        ld (KZY0),hl
        ld hl,(MASKR+6)             ; a min(BMAXY, MASKR y1 - 1, 199)
        dec hl
        ld de,(BMAXY)
        call .min
        ld de,199
        call .min
        ld (KZY1),hl
        call KZCLIP                 ; (y dentro de la habitacion)
        jp c,.same
        call KTMAPB
        ld a,(SHMMU7)
        ld (KZM7),a
        ld a,TMASK_PAGE
        call MAP7
.st:    ld a,(KZS)                  ; la tira: su columna del anillo de Layer 2
.m40:   cp 40
        jr c,.r
        sub 40
        jr .m40
.r:     ld d,a
        ld e,200
        mul d,e
        ld hl,$E000
        add hl,de
        ld a,(KZY0)
        add hl,a
        ld (KMZP),hl
        ld c,$FF                    ; los bits que cuentan: en la primera, desde x0;
        ld a,(KZS)                  ; en la ultima, hasta x1 (bit 0: el primer pixel)
        ld hl,KZS0
        cp (hl)
        jr nz,.a1
        ld a,(KZX0)
        and 7
        jr z,.a1
        ld b,a
.a0:    sla c
        djnz .a0
.a1:    ld a,(KZS)
        ld hl,KZS1
        cp (hl)
        jr nz,.a3
        ld a,(KZX1)
        and 7
        xor 7
        jr z,.a3
        ld b,a
        ld a,$FF
.a2:    srl a
        djnz .a2
        and c
        ld c,a
.a3:    ld a,c
        ld (KMK),a
        ld a,(KZS)                  ; x del lienzo de su primer pixel: 8 * tira - BMINX
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,(BMINX)
        or a
        sbc hl,de
        ld (KMXS),hl
        ld a,(KZY0)
        ld (KMRY),a
        ld a,(KZN)
        ld (KMR),a
.row:   ld hl,(KMZP)
        ld a,(KMK)
        and (hl)
        inc hl
        ld (KMZP),hl
        jr z,.nrow
        ld (KMB),a
        ld a,1
        ld (KTXHIT),a
        ld a,(KMRY)                 ; y del lienzo
        ld hl,BMINY
        sub (hl)
        ld (KMCY),a
        ld b,0
.bit:   ld a,(KMB)
        srl a
        ld (KMB),a
        jr nc,.nb
        push bc
        ld hl,(KMXS)
        ld a,b
        add hl,a
        bit 7,h
        jr nz,.skip
        ld a,h
        or a
        jr nz,.skip
        ld a,(CW16)
        ld c,a
        ld a,l
        cp c
        jr nc,.skip
        call KMCLR
.skip:  pop bc
.nb:    inc b
        ld a,(KMB)
        or a
        jr nz,.bit
.nrow:  ld hl,KMRY
        inc (hl)
        ld hl,KMR
        dec (hl)
        jr nz,.row
        ld a,(KZS)
        ld hl,KZS1
        cp (hl)
        jr z,.done
        inc a
        ld (KZS),a
        jp .st
.done:  ld a,(KZM7)
        call MAP7
        jp KZPACK
.same:  ld a,(KMN)
        ret
.max:   call CPS16                  ; HL = max(HL, DE), con signo
        ret nc
        ex de,hl
        ret
.min:   call CPS16                  ; HL = min(HL, DE), con signo
        ret c
        ex de,hl
        ret

; (KZMASK, despues de KZCLIP) z si el plano tapa toda la caja del dibujo (que tiene que
; estar entera en la habitacion, tambien en ancho)
KZALL:  ld hl,(BMINX)
        ld de,(KZX0)
        or a
        sbc hl,de
        ret nz
        ld hl,(BMAXX)
        ld de,(KZX1)
        or a
        sbc hl,de
        ret nz
        ld a,(KZX0)                 ; de la primera tira, los de antes de x0 no cuentan
        and 7
        ld b,a
        ld a,$FF
        jr z,.m0
.ml0:   srl a
        djnz .ml0
.m0:    cpl
        ld (KZMK0),a
        ld a,(KZX1)                 ; y de la ultima, los de despues de x1
        and 7
        xor 7
        ld b,a
        ld a,$FF
        jr z,.m1
.ml1:   add a,a
        djnz .ml1
.m1:    cpl
        ld (KZMK1),a
        ld a,(SHMMU7)
        ld (KZM7),a
        ld a,(KZS0)
        ld (KZS),a
.st:    ld a,(KZS)
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,(STRIPT)
        add hl,de
        ld a,(hl)
        add a,STRIP_PAGE
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        call MAP7
        ld hl,(CZOFF)
        add hl,de
        ld de,$2000
        add hl,de
        ld a,(KZY0)
        add hl,a
        ld a,(KZN)
        ld b,a
        ld a,$FF
.an:    and (hl)
        inc hl
        djnz .an
        ld c,a
        ld a,(KZS)
        ld hl,KZS0
        cp (hl)
        jr nz,.n0
        ld a,(KZMK0)
        or c
        ld c,a
.n0:    ld a,(KZS)
        ld hl,KZS1
        cp (hl)
        jr nz,.n1
        ld a,(KZMK1)
        or c
        ld c,a
.n1:    ld a,c
        inc a
        jr nz,.no                   ; alguno sin tapar
        ld a,(KZS)
        ld hl,KZS1
        cp (hl)
        jr z,.yes
        inc a
        ld (KZS),a
        jr .st
.yes:   ld a,(KZM7)
        call MAP7
        xor a
        ret
.no:    ld a,(KZM7)
        call MAP7
        or $FF
        ret

; (KZMASK) El pixel (L, KMCY) del lienzo, a 0 (si su tile esta)
KMCLR:  ld a,(KMCY)
        and $F0
        rrca
        ld b,a
        ld a,l
        rrca
        rrca
        rrca
        rrca
        and $0F
        add a,b
        ld e,l
        ld hl,KTMAP
        add hl,a
        ld a,(hl)
        cp $FF
        ret z
        call TILEADDR
        ld a,(KMCY)
        and $0F
        ld d,a
        ld a,(C8)
        or a
        jr nz,.p8
        ld a,d                      ; 4 bits: fila * 8 + x / 2 (el izquierdo, arriba)
        add a,a
        add a,a
        add a,a
        ld d,a
        ld a,e
        and $0F
        srl a
        add a,d
        add hl,a
        bit 0,e
        ld a,$0F
        jr z,.lft
        ld a,$F0
.lft:   and (hl)
        ld (hl),a
        ret
.p8:    ld a,d                      ; 8 bits: fila * 16 + x
        add a,a
        add a,a
        add a,a
        add a,a
        ld d,a
        ld a,e
        and $0F
        add a,d
        add hl,a
        ld (hl),0
        ret

; (KZMASK) Fuera los tiles vacios de los KMN de la lista KMLST. A = los que quedan
KZPACK: xor a
        ld (KPI),a
        ld (KPJ),a
.lp:    ld a,(KPI)
        ld hl,KMN
        cp (hl)
        jr z,.end
        call TILEADDR
        push hl
        ld a,(C8)                   ; (de 8 en 8: en cuanto hay algo, no esta vacio)
        or a
        ld b,16
        jr z,.b
        ld b,32
.b:     xor a
.or:    or (hl)
        inc l
        or (hl)
        inc l
        or (hl)
        inc l
        or (hl)
        inc l
        or (hl)
        inc l
        or (hl)
        inc l
        or (hl)
        inc l
        or (hl)
        jr nz,.full
        inc l
        djnz .or
.full:  pop hl
        or a
        jr z,.nx                    ; vacio: fuera
        ld a,(KPJ)
        ld b,a
        ld a,(KPI)
        cp b
        jr z,.k
        push hl                     ; a su sitio nuevo
        ld a,b
        call TILEADDR
        ex de,hl
        pop hl
        ld bc,128
        ld a,(C8)
        or a
        jr z,.cp
        ld bc,256
.cp:    ldir
        ld hl,(KMLST)               ; y en la lista
        ld a,(KPI)
        add hl,a
        ld c,(hl)
        ld hl,(KMLST)
        ld a,(KPJ)
        add hl,a
        ld (hl),c
.k:     ld hl,KPJ
        inc (hl)
.nx:    ld hl,KPI
        inc (hl)
        jr .lp
.end:   ld a,(KPJ)
        ret

; carry si HL < BC (sin signo)
CPU16BC:
        push hl
        or a
        sbc hl,bc
        pop hl
        ret

; HL = CLIST + 3 * A
CLREC:
        ld l,a
        add a,a
        add a,l
        ld hl,CLIST
        add hl,a
        ret

; El actor A: lo compone (si tiene costume) y lo anima
CASTONE:
        IFDEF PROF
        ld hl,(PACT)
        inc hl
        ld (PACT),hl
        ENDIF
        ld (CACT),a
        call ACTLOAD
        ld a,(ACTOR+R_COST)
        or a
        ret z
        ld a,(CACT)
        ld (CABANK),a
        ld hl,(ACTOR+R_ELEV)
        ld (CELEV),hl
        call ACTCSEL
        jr c,.none
        ld a,(SPRK)
        ld (KSP0),a
        call K_COMP
        call KSMOOTH
        ld ix,ACTOR
        jp ANIMATE
.none:  ld hl,$FFFF                 ; su costume no esta: no se dibuja
        ld (ACTOR+R_STR0),hl
        ld (ACTOR+R_STR1),hl
        jp ANIMATE

; COMPOSE con los tiles en su pagina: los de 4 bits en SPR_PAGE (huecos 0-31) y los de
; 8 (costumes de 32 colores) en SPRB_PAGE (huecos 32-62). Para el de 8 bits, SPRB_PAGE en
; $6000 y SPRUSED con lo suyo mientras se compone. Entre los dos, no mas de NSPR_ACTOR
; sprites: SPRUSED / 128 + SPRUSD8 / 256 <= 64 (SPRLIM)
K_COMP:
        xor a                       ; (KTXMASK: las letras no le tapan nada, de momento)
        ld (KTXHIT),a
        ld a,(C_NCOL)
        cp 32
        jr z,.k8
        ld hl,(SPRUSD8)             ; 4 bits: SPRLIM = SPR_BYTES - SPRUSD8 / 2
        srl h
        rr l
        ex de,hl
        ld hl,SPR_BYTES
        or a
        sbc hl,de
        ld (SPRLIM),hl
        ld hl,COMPOSE
        jp SAFECALL
.k8:    ld hl,(SPRUSED)             ; 8 bits: SPRLIM = min(SPR8_BYTES, 2 * (SPR_BYTES -
        ex de,hl                    ; SPRUSED))
        ld hl,SPR_BYTES
        or a
        sbc hl,de
        add hl,hl
        ld de,SPR8_BYTES
        call CPU16
        jr c,.lim
        ex de,hl
.lim:   ld (SPRLIM),hl
        call .swap
        ld a,SPRB_PAGE
        call .map
        ld hl,COMPOSE
        call SAFECALL
        push af
        call .swap
        ld a,SPR_PAGE
        call .map
        pop af
        ret
.swap:  ld hl,(SPRUSED)
        ld de,(SPRUSD8)
        ld (SPRUSED),de
        ld (SPRUSD8),hl
        ret
.map:   ld (SPRCUR),a
        ld (AUM3),a                 ; (AUM3 primero: es la que deja el CTC)
        nextreg $53,a
        ret

; (desplazamiento suave) Lo que se ha movido el actor CACT desde que se pinto la
; ultima vez (sin saltos de mas de 31), para sus sprites de este paso: los de
; 64 - SPRK a 63 - KSP0 (capa SM)
KSMOOTH:
        ld a,(SKIPDRAW)
        or a
        ret nz
        ld hl,(ACTOR+A_X)
        ld (KNX),hl
        ld hl,(ACTOR+A_Y)
        ld de,(CELEV)
        or a
        sbc hl,de
        ld (KNY),hl
        ld a,(SPRK)
        ld hl,KSP0
        sub (hl)
        ld (KCNT),a
        ld a,(CACT)
        ld hl,KMV
        add hl,a
        ld b,(hl)
        ld a,(KCNT)                 ; pintado: valido para el paso siguiente
        or a
        jr z,.nv
        ld a,1
.nv:    ld (hl),a
        xor a
        ld (KDXV),a
        ld (KDYV),a
        ld a,(CACT)
        add a,a
        ld hl,KMX
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        push hl
        ld hl,(KNX)
        or a
        sbc hl,de                   ; dx
        ex de,hl
        pop hl
        push de
        ld de,(KNX)
        ld (hl),d
        dec hl
        ld (hl),e
        ld a,(CACT)
        add a,a
        ld hl,KMY
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        push hl
        ld hl,(KNY)
        or a
        sbc hl,de                   ; dy
        ex de,hl
        pop hl
        push de
        ld de,(KNY)
        ld (hl),d
        dec hl
        ld (hl),e
        pop de                      ; DE = dy, (pila) = dx
        pop hl
        ld a,b
        or a
        jr z,.put                   ; no se pinto: de golpe
        call .small
        jr nc,.put
        ex de,hl
        call .small
        ex de,hl
        jr nc,.put
        ld a,(KTXHIT)               ; con letras encima, de golpe (entre pasos sus huecos
        or a                        ; se verian movidos)
        jr nz,.put
        ld a,(CZB)                  ; con plano Z, si tapa algo de lo que ha barrido:
        or a                        ; de golpe (entre pasos se veria movido sobre lo que
        jr z,.zok                   ; el plano tapa)
        push hl
        push de
        call KZSWEPT
        pop de
        pop hl
        jr nz,.put
.zok:   ld a,l
        ld (KDXV),a
        ld a,e
        ld (KDYV),a
.put:   ld a,(KCNT)
        or a
        ret z
        ld a,(SHMMU7)
        push af
        ld a,SM_PAGE
        call MAP7
        ld a,(SPRK)                 ; desde 64 - SPRK
        ld b,a
        ld a,64
        sub b
        push af
        ld hl,SMPDX
        add hl,a
        ld a,(KCNT)
        ld b,a
        ld a,(KDXV)
.fx:    ld (hl),a
        inc hl
        djnz .fx
        pop af
        ld hl,SMPDY
        add hl,a
        ld a,(KCNT)
        ld b,a
        ld a,(KDYV)
.fy:    ld (hl),a
        inc hl
        djnz .fy
        pop af
        jp MAP7
; carry si -32 < HL < 32
.small: ld a,l
        add a,32
        ld c,a
        ld a,h
        adc a,0
        ret nz
        ld a,c
        cp 64
        ret

; --- al hablar ---------------------------------------------------------------------------
; runActorTalkScript(talkStartFrame / talkStopFrame) del actor A
K_TALKSTART:
        ld c,R_FTSTART
        jr KTALK
K_TALKSTOP:
        ld c,R_FTSTOP
KTALK:  push bc
        call KACTA
        pop bc
        ret nc
        ld hl,(VARS+2*VAR_TALK_ACTOR)
        ld a,h
        or l
        ret z
        call ACTHERE
        ret nc
        ld hl,ACTOR
        ld b,0
        add hl,bc
        ld a,(hl)
        ld ix,ACTOR
        cp (ix+A_FRAME)
        ret z
        jp STARTANIM
; startAnimActor(L) del actor A (el codigo 9 de un texto)
K_ESCANIM:
        push hl
        call KACTA
        pop hl
        ret nc
        ld a,l
        jp STARTANIM

; ---------------------------------------------------------------------------
; Variables
KN:     db 0
KSD:    dw 0
KSIGLEN EQU 34
KSP0:   db 0                        ; (desplazamiento suave) SPRK antes del actor
KZX0:   dw 0                        ; (KZSCAN) la caja que se mira
KZX1:   dw 0
KZY0:   dw 0
KZY1:   dw 0
KZN:    db 0                        ; filas
KZS:    db 0                        ; la tira que se mira
KZS0:   db 0                        ; la primera y la ultima
KZS1:   db 0
KZMK0:  db 0                        ; sus pixeles
KZMK1:  db 0
KZM7:   db 0                        ; MMU7 de antes
KUSEF:  db 0                        ; la firma de este dibujo va sin posicion
KSAVP:  db 0                        ; y se guarda tambien con posicion (KSAVEPOS)
KPMV:   ds 13                       ; por actor: la vez anterior se habia movido (con plano)
KUNM:   db 0                        ; pintado sin el plano (K_CACHESAVE recorta)
KCZB:   db 0                        ; (y su plano)
KPN0:   db 0                        ; (K_CACHESAVE) tiles antes de recortar
KZMV:   db 0                        ; y despues
KMN:    db 0                        ; (KZMASK) tiles
KMLST:  dw 0                        ; su lista
KMZP:   dw 0                        ; el plano de la tira, en la fila
KMXS:   dw 0                        ; x del lienzo del primer pixel de la tira
KMRY:   db 0                        ; fila (de la habitacion)
KMR:    db 0                        ; filas que quedan
KMB:    db 0                        ; bits de la fila
KMCY:   db 0                        ; y del lienzo
KMNX:   db 0                        ; (KMBYTE) x de detras del tramo
KZXO:   db 0                        ; (KZSTRIP) x en el tile
KZTX:   db 0                        ; columna de tiles
KZTR:   db 0                        ; fila de tiles de KZRB (* 16)
KZRA:   dw 0                        ; fila 0 del tile A en la columna s, o 0
KZRB:   dw 0                        ; fila 0 del tile B, o 0
KZNA:   db 0                        ; pixeles de la tira en A
KZNB:   db 0                        ; y en B
KZRO:   db 0                        ; la fila en el tile * 8
KMK:    db 0                        ; (KTXMASK) los bits de la tira que cuentan
KTXHIT: db 0                        ; (KTXMASK) las letras le han tapado algo al actor
KPI:    db 0                        ; (KZPACK)
KPJ:    db 0
KTMAP:  ds 64                       ; tile de cada sitio del lienzo, o $FF
KCNT:   db 0                        ; sus sprites
KNX:    dw 0                        ; donde esta ahora (x, y - elevacion)
KNY:    dw 0
KDXV:   db 0                        ; lo que se ha movido
KDYV:   db 0
KMX:    ds 2*13                     ; por actor: donde se pinto la ultima vez
KMY:    ds 2*13
KMV:    ds 13                       ; (si vale)
KSIG:   ds KSIGLEN                  ; la firma del dibujo que se esta haciendo
KCM7:   db 0
KHASH:  db 0                        ; suma de la firma
KK:     db 0
KSZ:    dw 0                        ; lo que ocupa el que se guarda
KDHEAD: db 0                        ; la cola de dibujos: el mas viejo del indice
KDCNT:  db 0                        ; cuantos
KPPG:   db 0                        ; donde va el siguiente (pagina logica, posicion)
KPOFF:  dw 0
KCDIR:  ds 5*KDMAX                  ; el indice
KCN:    db 0
KCLENV: dw 0
KCTL:   ds 64
KC:     db 0
KI:     db 0
KPX:    dw 0
KPY:    dw 0
KPR:    db 0
KDIR:   dw 0
KOO:    dw 0
KOA:    db 0
KDA:    dw 0
KDB:    dw 0
KAA:    db 0
KAB:    db 0
KRA:    db 0
KDPX:   dw 0
KDPY:   dw 0
KBEST:  dw 0
KBD:    dw 0
KOBJ:   dw 0
KS:     dw 0
KLX:    dw 0
KLY:    dw 0
CACT:   db 0
CLN:    db 0
CLK:    db 0
CSI:    db 0
CSJ:    db 0
CLIST:  ds 3*12                     ; (y, actor) de los actores de la habitacion
KHT:    ds 16*8                     ; (KHTPTR)
KFST:   db 0                        ; (K_CACHEUSE) mirando el de la misma suma
KFD:    db 0

OVK_END:
        ASSERT OVK_END <= $E000, la capa OVK no cabe
