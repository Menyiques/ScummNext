; ===========================================================================
;  Actor: animaciones del costume y andar por las cajas. Traduccion de la
;  clase Actor de tools/model.py (el actor va en IX, y su direccion en ACTP).
; ===========================================================================

; --- estructura del actor (el mismo orden que Actor.pack() del modelo) -----
A_X     EQU 0
A_Y     EQU 2
A_FACE  EQU 4
A_TFACE EQU 6
A_BOX   EQU 8
A_MOV   EQU 9
A_FRAME EQU 10
A_DESTX EQU 11
A_DESTY EQU 13
A_DESTBOX EQU 15
A_DESTDIR EQU 16
A_CURBOX EQU 18
A_CURX  EQU 19
A_CURY  EQU 21
A_NEXTX EQU 23
A_NEXTY EQU 25
A_DXF   EQU 27
A_DYF   EQU 31
A_XFRAC EQU 35
A_YFRAC EQU 37
A_APROG EQU 39
A_ASPD  EQU 40
A_STOP  EQU 41
A_CURPOS EQU 43
A_START EQU 75
A_END   EQU 107
A_CFRAME EQU 139
A_SCALEX EQU 171
A_SCALEY EQU 172
A_PACKED EQU 173            ; (el actor solo del motor se compara hasta aqui)
A_SPX   EQU 173             ; velocidad al andar (speedx, speedy)
A_SPY   EQU 174
; lo de SCUMM de cada actor (Actor.pack() del modelo); pasan de +127: se leen
; con ACTOR+R_*, porque el actor con el que se trabaja esta siempre en ACTOR
R_NUM   EQU 175             ; su numero
R_ROOM  EQU 176             ; habitacion
R_COST  EQU 177             ; costume (0: ninguno)
R_VIS   EQU 178             ; visible
R_NINIT EQU 179             ; el costume necesita initFrame
R_FINIT EQU 180             ; fotogramas: init, andar, quieto, hablar, callar
R_FWALK EQU 181
R_FSTAND EQU 182
R_FTSTART EQU 183
R_FTSTOP EQU 184
R_ELEV  EQU 185             ; elevacion (2)
R_WIDTH EQU 187
R_TALKC EQU 188             ; color al hablar
R_BOXSC EQU 189             ; escala de su caja (2)
R_IGNB  EQU 191             ; no hace caso de las cajas
R_CLIP  EQU 192             ; plano Z fijo (0: el de su caja)
R_ACNT  EQU 193             ; animCounter (2)
R_TOP   EQU 195             ; lo que ocupa al dibujarse: arriba, abajo (2 + 2)
R_BOT   EQU 197
R_STR0  EQU 199             ; y las tiras de la habitacion ($FFFF: nada)
R_STR1  EQU 201
R_PAL   EQU 203             ; sus colores (32; $FF: los del costume)
R_SND   EQU 235             ; su sonido (actorOps 3)
R_SCNT  EQU 236             ; comandos de sonido ($78) desde playActorSounds
R_SIZE  EQU 237
A_SIZE  EQU R_SIZE

MF_NEW_LEG EQU 1
MF_IN_LEG EQU 2
MF_TURN EQU 4
MF_LAST_LEG EQU 8
CL_NEVERCLIP EQU 20         ; clases de los actores
CL_YFLIP EQU 29
CL_XFLIP EQU 30
CL_PLAYER EQU 31
CL_UNTOUCH EQU 32

; ---------------------------------------------------------------------------
; Costume: esta en paginas seguidas desde la de CMAPB (COST_PAGE, la del
; protagonista, u otra de la cache) y se lee por $E000 (MMU7). Las posiciones
; son desde el principio del bloque COST.

; HL = posicion -> HL = direccion en $E000-$FFFF (y MMU7 en su pagina)
CMAP:
        ld a,h
        rlca
        rlca
        rlca
        and 7
CMAPB:  add a,COST_PAGE             ; (COSTSEL cambia la primera pagina)
        ld (CPAGE),a
        call MAP7
        ld a,h
        and $1F
        or $E0
        ld h,a
        ret

; A = byte en la posicion HL (HL no cambia)
CBYTE:
        push hl
        call CMAP
        ld a,(hl)
        pop hl
        ret

; DE = palabra en la posicion HL (HL no cambia)
CWORD:
        push hl
        call CBYTE
        ld e,a
        inc hl
        call CBYTE
        ld d,a
        pop hl
        ret

; Lee la cabecera del costume (al cargarlo)
COSTHDR:
        ld hl,8
        call CBYTE
        ld (C_NANIM),a
        inc hl
        call CBYTE
        ld b,a
        and $80
        ld (C_NOMIR),a
        ld a,b
        and $7F
        ld (C_FMT),a
        ld c,16
        cp $58
        jr z,.n16
        ld c,32
.n16:   ld a,c
        ld (C_NCOL),a
        ld hl,10
        ld b,0
        add hl,bc                   ; 10 + ncolores
        call CWORD
        push hl
        ex de,hl
        inc hl
        inc hl
        ld (C_CMDS),hl              ; 2 + offset de los comandos
        pop hl
        inc hl
        inc hl
        ld (C_LIMBT),hl
        ld de,32
        add hl,de
        ld (C_ANIMT),hl
        ret

; ---------------------------------------------------------------------------
; Direcciones

; A = direccion antigua (0 oeste, 1 este, 2 sur, 3 norte) de HL (newDirToOldDir)
OLDDIR:
        ld de,71
        call CPU16
        jr c,.d3
        ld de,110
        call CPU16
        jr c,.d1
        ld de,252
        call CPU16
        jr c,.d2
        ld de,290
        call CPU16
        jr c,.d0
.d3:    ld a,3
        ret
.d1:    ld a,1
        ret
.d2:    ld a,2
        ret
.d0:    xor a
        ret

; carry si HL < DE sin signo (no cambia HL)
CPU16:
        push hl
        or a
        sbc hl,de
        pop hl
        ret


; DEHL = (HL) (32 bits)
LD32:
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        ret
; DEHL = |DEHL|
ABS32:
        bit 7,d
        ret z
        jp NEG32

; ---------------------------------------------------------------------------
; Animaciones del costume

; HL = &array[C] (DE = desplazamiento del array en el actor)
LIMBP:
        push ix
        pop hl
        add hl,de
        ld a,c
        add a,a
        add hl,a
        ret

; HL = 1 << C
BITC:
        ld hl,1
        ld a,c
        or a
        ret z
        ld b,a
.lp:    add hl,hl
        djnz .lp
        ret

RESETCOST:
        xor a
        ld (ix+A_STOP),a
        ld (ix+A_STOP+1),a
        push ix
        pop hl
        ld de,A_CURPOS
        add hl,de
        ld (hl),$FF
        ld d,h
        ld e,l
        inc de
        ld bc,127
        ldir
        ret

; costumeDecodeData: A = frame, UMASK = mascara de miembros
DECODE:
        ld (DFR),a
        ld l,(ix+A_FACE)
        ld h,(ix+A_FACE+1)
        call OLDDIR
        ld b,a
        ld a,(DFR)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        ld a,b
        add hl,a                    ; anim = dir + frame*4
        ld (DANIM),hl
        ld a,(C_NANIM)
        ld e,a
        ld d,0
        ex de,hl
        or a
        sbc hl,de                   ; num_anim - anim
        ret c
        ex de,hl
        add hl,hl
        ld de,(C_ANIMT)
        add hl,de
        call CWORD
        ld a,d
        or e
        ret z
        ld hl,2
        add hl,de                   ; r = base + offset
        call CWORD
        ld (DMASK),de
        inc hl
        inc hl
        ld (DR),hl
        ld c,0
.lp:    ld hl,(DMASK)
        ld a,h
        or l
        ret z
        bit 7,h
        jp z,.next
        ld hl,(DR)                  ; j
        call CWORD
        inc hl
        inc hl
        ld (DR),hl
        ld (DJ),de
        ld hl,(UMASK)
        bit 7,h
        jp z,.nouse
        ld a,d
        and e
        inc a
        jr nz,.notff
        ld de,A_CURPOS              ; j == $FFFF: oculta el miembro
        call LIMBP
        ld (hl),$FF
        inc hl
        ld (hl),$FF
        ld de,A_START
        call LIMBP
        ld (hl),0
        inc hl
        ld (hl),0
        call .setfr
        jp .next
.notff: ld hl,(DR)                  ; extra
        call CBYTE
        inc hl
        ld (DR),hl
        ld (DEXTRA),a
        ld hl,(C_CMDS)
        ld de,(DJ)
        add hl,de
        call CBYTE
        cp $7A
        jr nz,.n7a
        call BITC                   ; arranca el miembro
        ld a,l
        cpl
        and (ix+A_STOP)
        ld (ix+A_STOP),a
        ld a,h
        cpl
        and (ix+A_STOP+1)
        ld (ix+A_STOP+1),a
        jr .next
.n7a:   cp $79
        jr nz,.set
        call BITC                   ; para el miembro
        ld a,l
        or (ix+A_STOP)
        ld (ix+A_STOP),a
        ld a,h
        or (ix+A_STOP+1)
        ld (ix+A_STOP+1),a
        jr .next
.set:   ld de,A_START
        call LIMBP
        ld de,(DJ)
        ld (hl),e
        inc hl
        ld (hl),d
        ld a,(DEXTRA)
        and $7F
        ex de,hl
        add hl,a
        ex de,hl
        push de
        ld de,A_END
        call LIMBP
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ld de,A_CURPOS
        call LIMBP
        ld de,(DJ)
        ld a,(DEXTRA)
        and $80
        or d
        ld (hl),e
        inc hl
        ld (hl),a
        call .setfr
        jr .next
.nouse: ld a,d                      ; no se usa: salta el byte extra
        and e
        inc a
        jr z,.next
        ld hl,(DR)
        inc hl
        ld (DR),hl
.next:  inc c
        ld hl,(UMASK)
        add hl,hl
        ld (UMASK),hl
        ld hl,(DMASK)
        add hl,hl
        ld (DMASK),hl
        jp .lp
.setfr: ld de,A_CFRAME
        call LIMBP
        ld de,(DANIM)
        ld (hl),e
        inc hl
        ld (hl),d
        ret

; increaseAnim del miembro C. No cambia C.
INCANIM:
        ld de,A_CURPOS
        call LIMBP
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        and e
        inc a
        ret z                       ; $FFFF
        ld a,d
        and $80
        ld (IAHIGH),a
        res 7,d
        ld (IAI),de
        push de
        ld de,A_END
        call LIMBP
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (IAEND),de
        ld de,A_START
        call LIMBP
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (IASTART),de
        pop de
.lp:    ld a,(IAHIGH)
        or a
        jr nz,.high
        ld hl,(IAI)                 ; i >= end ? i = start : i + 1
        ld de,(IAEND)
        call CPU16
        jr c,.inc
        ld hl,(IASTART)
        ld (IAI),hl
        jr .cmd
.high:  ld hl,(IAI)                 ; i != end ? i + 1
        ld de,(IAEND)
        or a
        sbc hl,de
        jr z,.cmd
.inc:   ld hl,(IAI)
        inc hl
        ld (IAI),hl
.cmd:   ld hl,(C_CMDS)
        ld de,(IAI)
        add hl,de
        call CBYTE
        cp $7C
        jr nz,.n7c
        ld hl,(ACTOR+R_ACNT)
        inc hl
        ld (ACTOR+R_ACNT),hl
        jr .skip
.n7c:   cp $78
        jr nz,.store
        ld hl,ACTOR+R_SCNT          ; sonido: playActorSounds al final del paso
        inc (hl)
.skip:  ld hl,(IASTART)
        ld de,(IAEND)
        or a
        sbc hl,de
        jr nz,.lp
.store: ld de,A_CURPOS
        call LIMBP
        ld de,(IAI)
        ld a,(IAHIGH)
        or d
        ld (hl),e
        inc hl
        ld (hl),a
        ret

; animateCostume (los datos del costume se buscan solo si toca avanzar)
ANIMATE:
        ld a,(ACTOR+R_COST)
        or a
        ret z
        inc (ix+A_APROG)
        ld a,(ix+A_APROG)
        cp (ix+A_ASPD)
        ret c
        ld (ix+A_APROG),0
        call ACTCSEL
        ret c
        ld c,0
.lp:    push bc
        call INCANIM
        pop bc
        inc c
        ld a,c
        cp 16
        jr nz,.lp
        ret

; startAnimActor(A): $38..$3C son init, andar, quieto, hablar y callar; solo si
; esta en la habitacion y tiene costume
STARTANIM:
        cp $38
        jr c,.n
        cp $3D
        jr nc,.n
        sub $38
        ld hl,ACTOR+R_FINIT
        add hl,a
        ld a,(hl)
.n:     ld (SANF),a
        call ACTHERE
        ret nc
        ld a,(ACTOR+R_COST)
        or a
        ret z
        ld (ix+A_APROG),0
        ld hl,0
        ld (ACTOR+R_ACNT),hl
        ld a,(SANF)
        ld hl,ACTOR+R_FINIT
        cp (hl)
        call z,RESETCOST
        call ACTCSEL
        jr c,.nd
        ld hl,$FFFF
        ld (UMASK),hl
        ld a,(SANF)
        call DECODE
.nd:    ld a,(SANF)
        ld (ix+A_FRAME),a
        ret

; carry si el actor esta en la habitacion (el del motor solo, siempre)
ACTHERE:
        ld a,(VMON)
        or a
        scf
        ret z
        ld a,(CURROOM)
        or a
        ret z
        ld hl,ACTOR+R_ROOM
        cp (hl)
        scf
        ret z
        or a
        ret

; Los datos del costume del actor en CMAP (carry si no hay): el del protagonista
; (paginas 80-82) o uno de la cache de la habitacion (CCOST, en la capa OVU)
ACTCSEL:
        ld a,(VMON)
        or a
        jr z,.ego
        ld a,(ACTOR+R_COST)
        or a
        scf
        ret z
        ld hl,ECOST
        cp (hl)
        jr z,.ego
        ld (OVA),a
        ld hl,CCOST
        ld a,OVU_PAGE
        call OVCALLR
        ret c
        call COSTSEL
        or a
        ret
.ego:   ld a,COST_PAGE
        call COSTSEL
        or a
        ret

; HL = (HL + 360) mod 360 (HL entre -360 y 719)
MOD360:
        bit 7,h
        jr z,.p
        ld de,360
        add hl,de
.p:     ld de,360
        call CPU16
        ret c
        or a
        sbc hl,de
        ret

; setDirection(HL): sin cambiar la direccion no hace nada; los miembros que ya
; miraban hacia alli no se tocan
SETDIR:
        call MOD360
        ld e,(ix+A_FACE)
        ld d,(ix+A_FACE+1)
        push hl
        or a
        sbc hl,de
        pop hl
        ret z
        ld (ix+A_FACE),l
        ld (ix+A_FACE+1),h
        ld a,(ACTOR+R_COST)
        or a
        ret z
        push hl
        call ACTHERE
        pop hl
        ret nc
        call OLDDIR
        ld (SDNEW),a
        xor a
        ld (SDSEL),a                ; (el costume, la primera vez que haga falta)
        ld c,0
.lp:    ld de,A_CFRAME
        call LIMBP
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        and e
        inc a
        jr z,.next                  ; $FFFF
        ld a,e
        and 3
        ld b,a
        ld a,(SDNEW)
        cp b
        jr z,.next                  ; ya mira hacia alli
        srl d                       ; el frame: vald >> 2
        rr e
        srl d
        rr e
        ld a,e
        ld (SDFR),a
        ld a,(SDSEL)
        or a
        jr nz,.sel
        push bc
        call ACTCSEL
        pop bc
        jr c,.next
        ld a,1
        ld (SDSEL),a
.sel:   push bc
        call BITC                   ; usemask = $8000 >> C
        ld de,0
        ld b,16
.rev:   add hl,hl
        rr d
        rr e
        djnz .rev
        ld (UMASK),de
        ld a,(SDFR)
        call DECODE
        pop bc
.next:  inc c
        ld a,c
        cp 16
        jr nz,.lp
        ret

; turnToDirection(HL)
TURNTO:
        ld a,h
        and l
        inc a
        ret z                       ; -1
        ld (ix+A_MOV),MF_TURN
        ld (ix+A_TFACE),l
        ld (ix+A_TFACE+1),h
        ret

; remapDirection(RMD, UDW) -> HL (bit 10: girar paso a paso)
REMAP:
        ld a,(ACTOR+R_IGNB)
        or a
        jp nz,.free
        ld a,(ix+A_BOX)
        call BOXFLAGS
        ld (RMF),a
        ld a,(VMON)                 ; las clases de giro del actor (XFLIP: como la caja $08,
        or a                        ; YFLIP: como la $10)
        jr z,.nocl
        ld a,(ACTOR+R_NUM)
        ld l,a
        ld h,0
        push hl
        ld a,CL_XFLIP
        call GETCLASS
        pop hl
        or a
        jr z,.ny1
        ld a,(RMF)
        or $08
        ld (RMF),a
.ny1:   ld a,CL_YFLIP
        call GETCLASS
        or a
        jr z,.nocl
        ld a,(RMF)
        or $10
        ld (RMF),a
.nocl:
        push ix                     ; flipx = dxf > 0, flipy = dyf > 0
        pop hl
        ld de,A_DXF
        add hl,de
        call GT0
        ld (RMFX),a
        push ix
        pop hl
        ld de,A_DYF
        add hl,de
        call GT0
        ld (RMFY),a
        ld a,(RMF)
        bit 3,a
        jr z,.nx
        ld hl,360
        ld de,(RMD)
        or a
        sbc hl,de
        ld (RMD),hl
        ld a,(RMFX)
        xor 1
        ld (RMFX),a
.nx:    ld a,(RMF)
        bit 4,a
        jr z,.ny
        ld hl,180
        ld de,(RMD)
        or a
        sbc hl,de
        ld (RMD),hl
        ld a,(RMFY)
        xor 1
        ld (RMFY),a
.ny:    ld a,(RMF)
        and 7
        cp 1
        jr nz,.k2
        ld a,(UDW)
        or a
        jr z,.k1s
        ld a,(RMFX)
        or a
        ld hl,90
        ret nz
        ld hl,270
        ret
.k1s:   ld hl,(RMD)
        ld de,90
        or a
        sbc hl,de
        ld hl,90
        ret z
        ld hl,270
        ret
.k2:    cp 2
        jr nz,.k3
        ld a,(UDW)
        or a
        jr z,.k2s
        ld a,(RMFY)
        or a
        ld hl,180
        ret nz
        ld hl,0
        ret
.k2s:   ld hl,(RMD)
        ld a,h
        or l
        ret z
        ld hl,180
        ret
.k3:    cp 3
        ld hl,270
        ret z
        cp 4
        ld hl,90
        ret z
        cp 5
        ld hl,0
        ret z
        cp 6
        ld hl,180
        ret z
.free:  ld hl,(RMD)
        call MOD360
        set 2,h                     ; | 1024
        ret

; A = 1 si el valor de 32 bits en (HL) es > 0
GT0:
        inc hl
        inc hl
        inc hl
        bit 7,(hl)
        jr nz,.no
        ld a,(hl)
        dec hl
        or (hl)
        dec hl
        or (hl)
        dec hl
        or (hl)
        ret z
        ld a,1
        ret
.no:    xor a
        ret

; updateActorDirection(A = andando) -> HL (con la tabla de ScummVM)
UPDDIR:
        ld (UDW),a
        ld l,(ix+A_TFACE)
        ld h,(ix+A_TFACE+1)
        ld (RMD),hl
        call REMAP
        bit 2,h
        ret z
        res 2,h
        call OLDDIR
        ld (UDFROM),a               ; (aqui: hacia donde)
        ld l,(ix+A_FACE)
        ld h,(ix+A_FACE+1)
        call OLDDIR
        add a,a
        add a,a
        ld hl,UDFROM
        or (hl)
        ld hl,TURNTAB
        add hl,a
        ld a,(hl)
OLD2NEW:
        add a,a
        ld hl,O2N
        add hl,a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
TURNTAB: db 0, 2, 2, 3, 2, 1, 2, 3, 0, 1, 2, 1, 0, 1, 0, 3
O2N:    dw 270, 90, 180, 0

; ---------------------------------------------------------------------------
; Andar

; startWalkActor(SWX, SWY, direccion SWD)
STARTWALK:
        ld hl,(SWX)
        ld (AJX),hl
        ld hl,(SWY)
        ld (AJY),hl
        call ACTADJ
        ld (SWB),a
        call ACTHERE                ; fuera de la habitacion: alli, y mirando
        jr c,.here
        ld hl,(AJRX)
        ld (ix+A_X),l
        ld (ix+A_X+1),h
        ld hl,(AJRY)
        ld (ix+A_Y),l
        ld (ix+A_Y+1),h
        ld hl,(SWD)
        ld a,h
        and l
        inc a
        ret z
        ld (ix+A_FACE),l
        ld (ix+A_FACE+1),h
        ret
.here:  ld a,(ACTOR+R_IGNB)
        or a
        jr z,.boxes
        ld a,INVALID
        ld (SWB),a
        ld (ix+A_BOX),a
        jr .new
.boxes: ld hl,(AJRX)
        ld (PX),hl
        ld hl,(AJRY)
        ld (PY),hl
        ld a,(ix+A_DESTBOX)
        call INBOX
        jr nc,.again
        ld a,(ix+A_DESTBOX)
        ld (SWB),a
        jr .got
.again: ld hl,(AJRX)
        ld (AJX),hl
        ld hl,(AJRY)
        ld (AJY),hl
        call ACTADJ
        ld (SWB),a
.got:   ld a,(ix+A_MOV)             ; ya va ahi?
        or a
        jr z,.new
        ld l,(ix+A_DESTDIR)
        ld h,(ix+A_DESTDIR+1)
        ld de,(SWD)
        or a
        sbc hl,de
        jr nz,.new
        ld l,(ix+A_DESTX)
        ld h,(ix+A_DESTX+1)
        ld de,(AJRX)
        or a
        sbc hl,de
        jr nz,.new
        ld l,(ix+A_DESTY)
        ld h,(ix+A_DESTY+1)
        ld de,(AJRY)
        or a
        sbc hl,de
        ret z
.new:   ld l,(ix+A_X)               ; ya esta ahi? (si no mira hacia alli, girar)
        ld h,(ix+A_X+1)
        ld de,(AJRX)
        or a
        sbc hl,de
        jr nz,.go
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        ld de,(AJRY)
        or a
        sbc hl,de
        jr nz,.go
        ld hl,(SWD)
        ld e,(ix+A_FACE)
        ld d,(ix+A_FACE+1)
        push hl
        or a
        sbc hl,de
        pop hl
        ret z
        jp TURNTO
.go:    ld hl,(AJRX)
        ld (ix+A_DESTX),l
        ld (ix+A_DESTX+1),h
        ld hl,(AJRY)
        ld (ix+A_DESTY),l
        ld (ix+A_DESTY+1),h
        ld a,(SWB)
        ld (ix+A_DESTBOX),a
        ld hl,(SWD)
        ld (ix+A_DESTDIR),l
        ld (ix+A_DESTDIR+1),h
        ld a,(ix+A_BOX)
        ld (ix+A_CURBOX),a
        ld a,(ix+A_MOV)
        and MF_IN_LEG
        or MF_NEW_LEG
        ld (ix+A_MOV),a
        ret

; adjustXYToBeInBox del actor (AJX, AJY -> AJRX, AJRY, A = caja): sin cajas, tal
; cual; las cajas invisibles solo del jugador valen para quien no lo es
ACTADJ:
        ld a,(ACTOR+R_IGNB)
        or a
        jr z,.b
        ld hl,(AJX)
        ld (AJRX),hl
        ld hl,(AJY)
        ld (AJRY),hl
        ld a,INVALID
        ret
.b:     ld a,1
        ld (AJPLAY),a
        ld a,(VMON)
        or a
        jp z,ADJXY
        ld a,(ACTOR+R_NUM)
        ld l,a
        ld h,0
        ld a,CL_PLAYER
        call GETCLASS
        ld (AJPLAY),a
        jp ADJXY

; |(ix+o1) - (ix+o2)| en HL (o1, o2 en B, C)
ABSDIFF:
        push ix
        pop hl
        ld a,b
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        push de
        push ix
        pop hl
        ld a,c
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        pop hl
        or a
        sbc hl,de
        jp ABSHL

; actorWalkStep -> A = 1 si sigue (Z si ha terminado el tramo)
WALKSTEP:
        ld a,1
        call UPDDIR
        ld (WNF),hl
        ld a,(ix+A_MOV)
        and MF_IN_LEG
        jr z,.anim
        ld e,(ix+A_FACE)
        ld d,(ix+A_FACE+1)
        or a
        sbc hl,de
        jr z,.box
.anim:  ld a,(ix+A_FRAME)
        ld hl,ACTOR+R_FWALK
        cp (hl)
        jr nz,.start
        ld hl,(WNF)
        ld e,(ix+A_FACE)
        ld d,(ix+A_FACE+1)
        or a
        sbc hl,de
        jr z,.inleg
.start: ld hl,(WNF)
        call SETDIR
        ld a,(ACTOR+R_FWALK)
        call STARTANIM
.inleg: set 1,(ix+A_MOV)
.box:   ld a,(ix+A_BOX)
        cp (ix+A_CURBOX)
        jr z,.dist
        ld l,(ix+A_X)
        ld h,(ix+A_X+1)
        ld (PX),hl
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        ld (PY),hl
        ld a,(ix+A_CURBOX)
        call INBOX
        jr nc,.dist
        ld a,(ix+A_CURBOX)
        call SETBOX
.dist:  ld bc,A_NEXTX<<8|A_CURX
        call ABSDIFF
        ld (WDX),hl
        ld bc,A_NEXTY<<8|A_CURY
        call ABSDIFF
        ld (WDY),hl
        ld bc,A_X<<8|A_CURX         ; |x - cur.x| >= dist.x y |y - cur.y| >= dist.y ?
        call ABSDIFF
        ld de,(WDX)
        call CPU16
        jr c,.move
        ld bc,A_Y<<8|A_CURY
        call ABSDIFF
        ld de,(WDY)
        call CPU16
        jr c,.move
        jr .stop
.move:  call GETSCX
        ld (SASCALE),a
        ld bc,A_DXF<<8|A_XFRAC
        ld e,A_X
        call STEPAX
        call GETSCY
        ld (SASCALE),a
        ld bc,A_DYF<<8|A_YFRAC
        ld e,A_Y
        call STEPAX
        ld bc,A_X<<8|A_CURX         ; pasado: al punto
        call ABSDIFF
        ld de,(WDX)
        ex de,hl
        call CPU16                  ; dist.x < |x - cur.x| ?
        jr nc,.ny
        ld a,(ix+A_NEXTX)
        ld (ix+A_X),a
        ld a,(ix+A_NEXTX+1)
        ld (ix+A_X+1),a
.ny:    ld bc,A_Y<<8|A_CURY
        call ABSDIFF
        ld de,(WDY)
        ex de,hl
        call CPU16
        jr nc,.end
        ld a,(ix+A_NEXTY)
        ld (ix+A_Y),a
        ld a,(ix+A_NEXTY+1)
        ld (ix+A_Y+1),a
.end:   ld l,(ix+A_X)               ; en el punto: fin del tramo
        ld h,(ix+A_X+1)
        ld e,(ix+A_NEXTX)
        ld d,(ix+A_NEXTX+1)
        or a
        sbc hl,de
        jr nz,.go
        ld l,(ix+A_Y)
        ld h,(ix+A_Y+1)
        ld e,(ix+A_NEXTY)
        ld d,(ix+A_NEXTY+1)
        or a
        sbc hl,de
        jr z,.stop
.go:    ld a,1
        or a
        ret
.stop:  res 1,(ix+A_MOV)
        xor a
        ret

