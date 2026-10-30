; ===========================================================================
;  Capa OVU (pagina OVU_PAGE, en $C000): instrucciones de la interfaz,
;  entrada, frases e inventario (tools/ui.py y tools/vm.py), y los actores en
;  sprites (World.draw_actors en tools/model.py)
;
;  Las rutinas U_xxx son los manejadores de instrucciones (los llama la
;  tabla VMTAB por OVUCALL): IY es la ranura en marcha. Lo que ejecuta scripts
;  va por SAFECALL (un script puede cambiar de habitacion y dejar otra pagina
;  en MMU6).
; ===========================================================================


; --- textos del script ----------------------------------------------------------------
; Copia el texto del script (hasta el 0, con sus escapes $FF) a BOUNCE
COPYSTR:
        ld hl,BOUNCE
        ld b,0                      ; cuantos (como mucho 255)
.lp:    call VMFETCH
        call .put
        or a
        ret z
        cp $FF
        jr nz,.lp
        call VMFETCH
        call .put
        cp 1
        jr z,.lp
        cp 2
        jr z,.lp
        cp 3
        jr z,.lp
        cp 8
        jr z,.lp
        call VMFETCH
        call .put
        call VMFETCH
        call .put
        jr .lp
.put:   ld c,a
        ld a,b
        cp 255
        ld a,c
        ret z
        ld (hl),a
        inc hl
        inc b
        ret
; Termina BOUNCE con un 0 (por si el texto era demasiado largo)
        ; (COPYSTR deja el 0 que lee; si se corta, BOUNCE+255 ya es 0)

; BC = largo de la cadena HL con su 0, con los escapes ($FF, codigo y, salvo 1, 2, 3
; y 8, dos bytes) enteros: un 0 dentro de un escape no la termina (resStrLen)
ESCLEN:
        ld bc,0
.lp:    ld a,(hl)
        inc hl
        inc bc
        or a
        ret z
        cp $FF
        jr nz,.lp
        ld a,(hl)
        inc hl
        inc bc
        cp 1
        jr z,.lp
        cp 2
        jr z,.lp
        cp 3
        jr z,.lp
        cp 8
        jr z,.lp
        inc hl
        inc hl
        inc bc
        inc bc
        jr .lp

; Copia la cadena HL (como mucho B bytes) a DE, terminada en 0 (loadPtrToResource)
ESCCPY:
        push hl
        push de
        push bc
        call ESCLEN
        pop hl                      ; H = maximo
        ld a,b
        or a
        jr nz,.cut
        ld a,h
        cp c
        jr nc,.all
.cut:   ld c,h                      ; sin su 0 dentro: B bytes y un 0
        ld b,0
        pop de
        pop hl
        ld a,c
        or a
        jr z,.z
        ldir
.z:     xor a
        ld (de),a
        ret
.all:   pop de                      ; entera, con su 0
        pop hl
        ldir
        ret

; --- el monton (pagina HEAPP) ------------------------------------------------------
; En $E000 la primera posicion libre (HTOP); desde $E002, bloques: tipo, numero,
; largo (2) y los datos. Tipo 0: libre. Cuando no cabe, se compacta.
; HL = la entrada (tipo C, numero A) de la tabla de punteros (MMU7 en UIP)
UHPSLOT:
        ld l,a
        ld h,0
        add hl,hl
        ld de,HP_VERB
        ld a,c
        cp 2
        jr c,.ok
        ld de,HP_STR
        jr z,.ok
        ld de,HP_NN
.ok:    add hl,de
        ld a,UIP
        jp MAP7
; HL = desplazamiento de los datos (tipo C, numero A) en el monton, Z si no hay
UHOFS:
        call UHPSLOT
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld a,h
        or l
        ret
; Libera los datos (tipo C, numero A)
UHFREE:
        call UHPSLOT
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        or e
        ret z
        ld (hl),0
        dec hl
        ld (hl),0
        ex de,hl
        ld de,$E000-4
        add hl,de
        ld a,HEAPP
        call MAP7
        ld (hl),0
        ret
; Datos nuevos de BC bytes (tipo en HAK, numero A): carry y HL = su desplazamiento
UHALLOC:
        ld (HAS),bc
        ld (HAI),a
        ld a,(HAK)
        ld c,a
        ld a,(HAI)
        call UHFREE
        call .fits
        jr c,.ok
        call UHCOMPACT
        call .fits
        ret nc
.ok:    ld a,HEAPP
        call MAP7
        ld hl,($E000)
        ld de,$E000
        add hl,de
        ld a,(HAK)
        ld (hl),a
        inc hl
        ld a,(HAI)
        ld (hl),a
        inc hl
        ld de,(HAS)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        push hl
        add hl,de
        ld de,$E000
        or a
        sbc hl,de
        ld ($E000),hl
        pop hl
        or a
        sbc hl,de
        ld (HAO),hl
        ld a,(HAK)
        ld c,a
        ld a,(HAI)
        call UHPSLOT
        ld de,(HAO)
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,(HAO)
        scf
        ret
.fits:  ld a,HEAPP                  ; carry si HTOP + 4 + largo <= 8192
        call MAP7
        ld hl,($E000)
        ld de,(HAS)
        add hl,de
        ret c
        ld de,4
        add hl,de
        ld de,8193
        jp CPU16
; Quita los huecos del monton
UHCOMPACT:
        ld a,HEAPP
        call MAP7
        ld hl,2
        ld (HCR),hl
        ld (HCW),hl
.lp:    ld a,HEAPP
        call MAP7
        ld hl,(HCR)
        ld de,($E000)
        call CPU16
        jr nc,.end
        ld de,$E000
        add hl,de
        ld a,(hl)
        ld (HCK),a
        inc hl
        ld a,(hl)
        ld (HCI),a
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld hl,4
        add hl,bc
        ld (HCL),hl
        ld a,(HCK)
        or a
        jr z,.skip
        ld hl,(HCR)                 ; el bloque baja a HCW
        ld de,(HCW)
        or a
        sbc hl,de
        jr z,.same
        ld hl,(HCR)
        ld de,$E000
        add hl,de
        push hl
        ld hl,(HCW)
        add hl,de
        ex de,hl
        pop hl
        ld bc,(HCL)
        ldir
.same:  ld a,(HCK)                  ; su puntero
        ld c,a
        ld a,(HCI)
        call UHPSLOT
        ld de,(HCW)
        inc de
        inc de
        inc de
        inc de
        ld (hl),e
        inc hl
        ld (hl),d
        ld hl,(HCW)
        ld de,(HCL)
        add hl,de
        ld (HCW),hl
.skip:  ld hl,(HCR)
        ld de,(HCL)
        add hl,de
        ld (HCR),hl
        jr .lp
.end:   ld hl,(HCW)
        ld ($E000),hl
        ret
; El texto de BOUNCE (con su 0) como datos (tipo C, numero A); carry si cabe
HSETSTR:
        ld (HAI),a
        ld a,c
        ld (HAK),a
        ld hl,BOUNCE
        call ESCLEN
        ld (HSL),bc
        ld a,(HAI)
        call UHALLOC
        ret nc
        ld de,$E000
        add hl,de
        ex de,hl
        ld a,HEAPP
        call MAP7
        ld hl,BOUNCE
        ld bc,(HSL)
        ldir
        scf
        ret

; --- verbos ------------------------------------------------------------------------
; A = ranura del verbo A con saveid B (0 si no hay)
VERBSLOT:
        ld c,a
        ld a,1
.lp:    ld (VSI),a
        push bc
        call UVSADDR
        pop bc
        ld a,(hl)
        cp c
        jr nz,.nx
        ld de,VS_SAVE
        add hl,de
        ld a,(hl)
        cp b
        jr nz,.nx
        ld a,(VSI)
        ret
.nx:    ld a,(VSI)
        inc a
        cp NUM_VERBS
        jr nz,.lp
        xor a
        ret
; HL = la ranura de verbo A en UIP (y MMU7 en UIP)
UVSADDR:
        ld e,a
        ld d,VSZ
        mul d,e
        ld hl,VSLOTS
        add hl,de
        ld a,UIP
        jp MAP7
; VOT = la ranura A; VOTS = A
VOLOAD:
        ld (VOTS),a
        call UVSADDR
        ld de,VOT
        ld bc,VSZ
        ldir
        ret
VOSTORE:
        ld a,(VOTS)
        call UVSADDR
        ex de,hl
        ld hl,VOT
        ld bc,VSZ
        ldir
        ret

; killVerb(A)
KILLVERB:
        or a
        ret z
        ld (KVS),a
        ld c,1
        call UHFREE
        ld a,(KVS)
        call UVSADDR
        push hl
        ld (hl),0                   ; verbid
        ld de,VS_MODE
        add hl,de
        ld (hl),0
        pop hl
        push hl
        ld de,VS_HASN
        add hl,de
        ld (hl),0
        pop hl
        ld de,VS_SAVE
        add hl,de
        ld a,(hl)
        or a
        jr nz,.sv
        xor a
        ld (DVMODE),a
        ld a,(KVS)
        OTCALL DRAWVERB
        xor a
        OTCALL VERBMOUSE
.sv:    ld a,(KVS)
        call UVSADDR
        ld de,VS_SAVE
        add hl,de
        ld (hl),0
        ret

U_verbOps:
        call PARAMSI
        db "b",0
        ld a,(P0)
        ld (VOV),a
        ld b,0
        call VERBSLOT
        call VOLOAD
        ld a,(VOV)
        ld (VOT+VS_ID),a
.lp:    call VMFETCH
        cp $FF
        jp z,.end
        ld (VMOP),a
        and $1F
        cp 1
        jr nz,.n2
        call PARAMSI                ; imagen de un objeto de esta habitacion
        db "w",0
        ld a,(VOTS)
        or a
        jr z,.lp
        ld a,(CURROOM)
        ld (VOT+VS_IROOM),a
        ld hl,(P0)
        ld (VOT+VS_IOBJ),hl
        ld a,1
        ld (VOT+VS_HASI),a
        ld (VOT+VS_TYPE),a
        jr .lp
.n2:    cp 2
        jr nz,.n3
        call COPYSTR                ; nombre
        call .name
        ld a,(VOTS)
        or a
        jr nz,.t0
        ld (VOT+VS_HASN),a          ; (la ranura 0 no se queda el nombre)
        ld c,1
        call UHFREE
.t0:    xor a
        ld (VOT+VS_TYPE),a
        ld (VOT+VS_IMGI),a
        ld (VOT+VS_IMGI+1),a
        jr .lp
.n3:    cp 3
        jr nz,.n4
        call .b1
        ld (VOT+VS_COL),a
        jr .lp
.n4:    cp 4
        jr nz,.n5
        call .b1
        ld (VOT+VS_HI),a
        jr .lp
.n5:    cp 5
        jr nz,.n6
        call PARAMSI
        db "ww",0
        ld hl,(P0)
        ld (VOT+VS_L),hl
        ld hl,(P1)
        ld (VOT+VS_T),hl
        jp .lp
.n6:    cp 6
        jr nz,.n7
        ld a,1
        ld (VOT+VS_MODE),a
        jp .lp
.n7:    cp 7
        jr nz,.n8
        xor a
        ld (VOT+VS_MODE),a
        jp .lp
.n8:    cp 8
        jr nz,.n9
        call VOSTORE
        ld a,(VOTS)
        call KILLVERB
        ld a,(VOTS)
        call VOLOAD
        jp .lp
.n9:    cp 9
        jr nz,.n16
        call VOSTORE                ; nuevo
        ld a,(VOV)
        ld b,0
        call VERBSLOT
        or a
        jr nz,.got
        ld a,1                      ; el primero libre (o el 99)
.free:  ld (VSI),a
        call UVSADDR
        ld a,(hl)
        or a
        ld a,(VSI)
        jr z,.got
        inc a
        cp NUM_VERBS
        jr nz,.free
        dec a
.got:   call VOLOAD
        ld a,(VOV)
        ld (VOT+VS_ID),a
        ld a,2
        ld (VOT+VS_COL),a
        xor a
        ld (VOT+VS_HI),a
        ld (VOT+VS_TYPE),a
        ld (VOT+VS_MODE),a
        ld (VOT+VS_SAVE),a
        ld (VOT+VS_KEY),a
        ld (VOT+VS_CEN),a
        ld (VOT+VS_IMGI),a
        ld (VOT+VS_IMGI+1),a
        ld a,8
        ld (VOT+VS_DIM),a
        ld a,(STAB+STSZ+ST_CS)      ; la fuente por defecto de la ranura 0
        ld (VOT+VS_CS),a
        jp .lp
.n16:   cp 16
        jr nz,.n17
        call .b1
        ld (VOT+VS_DIM),a
        jp .lp
.n17:   cp 17
        jr nz,.n18
        ld a,2
        ld (VOT+VS_MODE),a
        jp .lp
.n18:   cp 18
        jr nz,.n19
        call .b1
        ld (VOT+VS_KEY),a
        jp .lp
.n19:   cp 19
        jr nz,.n20
        ld a,1
        ld (VOT+VS_CEN),a
        jp .lp
.n20:   cp 20
        jr nz,.n22
        call PARAMSI                ; nombre desde una cadena
        db "w",0
        xor a
        ld (BOUNCE),a
        ld hl,(P0)
        ld a,h
        or a
        jr nz,.s0
        ld a,l
        or a
        jr z,.s0
        cp NUM_STR
        jr nc,.s0
        ld e,a
        ld hl,STRSZ
        add hl,a
        ld a,(hl)
        or a
        jr z,.s0
        ld b,a                      ; la cadena a BOUNCE (hasta su 0 o su largo)
        ld a,e
        ld c,2
        push bc
        call UHOFS
        pop bc
        jr z,.s0
        ld de,$E000
        add hl,de
        ld a,HEAPP
        call MAP7
        ld de,BOUNCE
        call ESCCPY
.s0:    call .name
        xor a
        ld (VOT+VS_TYPE),a
        ld (VOT+VS_IMGI),a
        ld (VOT+VS_IMGI+1),a
        jp .lp
.n22:   cp 22
        jr nz,.n23
        call PARAMSI                ; imagen de un objeto de otra habitacion
        db "wb",0
        ld a,(VOTS)
        or a
        jp z,.lp
        ld hl,(VOT+VS_IMGI)
        ld de,(P0)
        or a
        sbc hl,de
        jp z,.lp
        ld (VOT+VS_IMGI),de
        ld (VOT+VS_IOBJ),de
        ld a,(P1)
        ld (VOT+VS_IROOM),a
        ld a,1
        ld (VOT+VS_TYPE),a
        ld (VOT+VS_HASI),a
        jp .lp
.n23:   cp 23
        jp nz,.lp
        call .b1
        ld (VOT+VS_BK),a
        jp .lp
.end:   call VOSTORE
        xor a
        ld (DVMODE),a
        ld a,(VOTS)
        OTCALL DRAWVERB
        xor a
        OTCALL VERBMOUSE
        jp RESTOREIY
; un parametro byte del subcodigo
.b1:    call PARAMSI
        db "b",0
        ld a,(P0)
        ret
; el nombre de BOUNCE para la ranura VOTS
.name:  ld a,1
        ld (VOT+VS_HASN),a
        ld a,(VOTS)
        ld c,1
        jp HSETSTR

U_saveRestoreVerbs:
        call PARAMSI
        db "nbbb",0
        ld a,(P1)
        ld l,a
        ld h,0
        ld (SRA),hl
        ld a,(P2)
        ld l,a
        ld (SRB),hl
        ld a,(P3)
        ld (SRC),a
        ld a,(VMOP)
        and $1F
        cp 1
        jr z,.save
        cp 2
        jr z,.rest
        cp 3
        jp z,.del
        ret
.save:  call .done
        ret c
        ld a,(SRA)
        ld b,0
        call VERBSLOT
        or a
        jr z,.snx
        ld (SRS),a
        call UVSADDR
        ld de,VS_SAVE
        add hl,de
        ld a,(hl)
        or a
        jr nz,.snx
        ld a,(SRC)
        ld (hl),a
        xor a
        ld (DVMODE),a
        ld a,(SRS)
        OTCALL DRAWVERB
        xor a
        OTCALL VERBMOUSE
.snx:   ld hl,SRA
        inc (hl)
        jr .save
.rest:  call .done
        ret c
        ld a,(SRC)
        ld b,a
        ld a,(SRA)
        call VERBSLOT
        or a
        jr z,.rnx
        ld a,(SRA)
        ld b,0
        call VERBSLOT
        or a
        call nz,KILLVERB
        ld a,(SRC)
        ld b,a
        ld a,(SRA)
        call VERBSLOT
        ld (SRS),a
        call UVSADDR
        ld de,VS_SAVE
        add hl,de
        ld (hl),0
        xor a
        ld (DVMODE),a
        ld a,(SRS)
        OTCALL DRAWVERB
        xor a
        OTCALL VERBMOUSE
.rnx:   ld hl,SRA
        inc (hl)
        jr .rest
.del:   call .done
        ret c
        ld a,(SRC)
        ld b,a
        ld a,(SRA)
        call VERBSLOT
        or a
        call nz,KILLVERB
        ld hl,(SRA)
        inc hl
        ld (SRA),hl
        jr .del
; carry si a > b
.done:  ld hl,(SRB)
        ld de,(SRA)
        jp CPU16

; --- cursor ------------------------------------------------------------------------
U_cursorCommand:
        call PARAMSI
        db "n",0
        ld a,(VMOP)
        and $1F
        ld (CCK),a
        ld hl,CURFMT
        call SUBFMT
        ld a,(CCK)
        cp 1
        jr nz,.c2
        ld hl,1
        ld (CURSTATE),hl
        jp .vm
.c2:    cp 2
        jr nz,.c3
        ld hl,0
        ld (CURSTATE),hl
        jp .vm
.c3:    cp 3
        jr nz,.c4
        ld hl,1
        ld (USERPUT),hl
        jp .out
.c4:    cp 4
        jr nz,.c5
        ld hl,0
        ld (USERPUT),hl
        jp .out
.c5:    cp 5
        jr nz,.c6
        ld hl,(CURSTATE)
        inc hl
        ld (CURSTATE),hl
        jr .vm
.c6:    cp 6
        jr nz,.c7
        ld hl,(CURSTATE)
        dec hl
        ld (CURSTATE),hl
        jr .vm
.c7:    cp 7
        jr nz,.c8
        ld hl,(USERPUT)
        inc hl
        ld (USERPUT),hl
        jr .out
.c8:    cp 8
        jr nz,.c13
        ld hl,(USERPUT)
        dec hl
        ld (USERPUT),hl
        jr .out
.c13:   cp 13
        jr nz,.c14
        ld a,(P0)
        call INITCHARSET
        jr .out
.c14:   cp 14
        jr nz,.out
        ld a,(STAB+STABSZ+STSZ+ST_CS)   ; la fuente por defecto de la ranura 1
        and 7
        add a,a
        add a,a
        add a,a
        add a,a
        ld de,CHDATA
        add a,e
        ld e,a
        adc a,d
        sub e
        ld d,a
        ld hl,ARGS
        ld b,0
.tb:    ld a,b
        push hl
        ld hl,ARGN
        cp (hl)
        pop hl
        ld a,0
        jr nc,.z
        ld a,(hl)
.z:     inc hl
        inc hl
        ld (de),a
        push hl
        ld hl,TCMAP
        ld c,b
        ld b,0
        add hl,bc
        ld b,c
        ld (hl),a
        pop hl
        inc de
        inc b
        ld a,b
        cp 16
        jr nz,.tb
        jr .out
.vm:    xor a
        OTCALL VERBMOUSE
.out:   ld hl,(CURSTATE)
        ld (VARS+2*VAR_CURSORSTATE),hl
        ld hl,(USERPUT)
        ld (VARS+2*VAR_USERPUT),hl
        jp RESTOREIY

; La fuente A: sus colores de CHARS.DAT (loadCharset)
LOADCHARSET:
        or a
        ret z
        cp 8
        ret nc
        ld (LCN),a
        ld c,a                      ; la posicion en el indice
        add a,a
        add a,c
        ld l,a
        ld h,0
        ld a,CHARP
        call FARSET
        call FARGET
        ld e,a
        call FARGET
        ld d,a
        call FARGET
        cp $FF
        ret z
        ex de,hl                    ; A:HL + 6 + CHARP * 8192
        ld de,6
        add hl,de
        adc a,0
        ld c,a
        ld a,h
        add a,(CHARP & 7) << 5
        ld h,a
        ld a,c
        adc a,CHARP >> 3
        ld (FARP),hl
        ld (FARP+2),a
        ld a,(LCN)
        add a,a
        add a,a
        add a,a
        add a,a
        ld hl,CHDATA+1
        add hl,a
        ld b,15
.lp:    call FARGET
        ld (hl),a
        inc hl
        djnz .lp
        ld a,(LCN)
        ld hl,CHLOAD
        add hl,a
        ld (hl),1
        ret
; initCharset(A)
INITCHARSET:
        or a
        ret z
        cp 8
        ret nc
        ld (ICN),a
        ld hl,CHLOAD
        add hl,a
        ld a,(hl)
        or a
        ld a,(ICN)
        call z,LOADCHARSET
        ld a,(ICN)
        ld (STAB+STSZ+ST_CS),a              ; las dos por defecto
        ld (STAB+STABSZ+STSZ+ST_CS),a
        add a,a
        add a,a
        add a,a
        add a,a
        ld hl,CHDATA
        add hl,a
        ld de,TCMAP
        ld bc,16
        ldir
        ret

U_resourceRoutines:
        call VMFETCH
        ld (VMOP),a
        ld (RRK),a
        xor a
        ld (MASKI),a
        ld a,(VMOP)
        cp 17
        jp z,RESTOREIY
        call MASKNEXT
        jr z,.d1
        call READVAR
        ld a,l
        jr .r
.d1:    call VMFETCH
.r:     ld (RRV),a
        ld a,(RRK)
        and $3F
        cp 20
        jr nz,.n20
        ld a,1
        ld (MASKI),a
        call MASKNEXT
        call z,VMFETCHW
        call nz,READVAR
        jp RESTOREIY
.n20:   cp 18
        jp nz,RESTOREIY
        ld a,(RRV)
        call LOADCHARSET
        jp RESTOREIY

; --- textos -----------------------------------------------------------------------
U_print:
        call PARAMSI
        db "b",0
        ld a,(P0)
        jr PRINTGO
U_printEgo:
        ld a,(VARS+2*VAR_EGO)
; decodeParseString para el actor A
PRINTGO:
        ld (PRA),a
        ld b,0                      ; 252 -> 3, 253 -> 2, 254 -> 1, si no 0
        cp 252
        jr nz,.a1
        ld b,3
.a1:    cp 253
        jr nz,.a2
        ld b,2
.a2:    cp 254
        jr nz,.a3
        ld b,1
.a3:    ld a,b
        ld (PRS),a
        OTCALL STPTR                ; HL = ranura de texto
        ld (PRST),hl
        ex de,hl                    ; actual = por defecto
        ld hl,STSZ
        add hl,de
        ld bc,STSZ
        ldir
.lp:    call VMFETCH
        cp $FF
        jp z,.save
        ld (VMOP),a
        and $0F
        jr nz,.n1
        call PARAMSI                ; at
        db "ww",0
        ld hl,(PRST)
        ld de,(P0)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(P1)
        ld (hl),e
        inc hl
        ld (hl),d
        ld a,ST_OVH
        call .fld
        ld (hl),0
        jr .lp
.n1:    cp 1
        jr nz,.n2
        call PARAMSI                ; color
        db "b",0
        ld a,ST_COL
        call .fld
        ld a,(P0)
        ld (hl),a
        jr .lp
.n2:    cp 2
        jr nz,.n3
        call PARAMSI                ; clipped
        db "w",0
        ld a,ST_R
        call .fld
        ld de,(P0)
        ld (hl),e
        inc hl
        ld (hl),d
        jr .lp
.n3:    cp 3
        jr nz,.n4
        call PARAMSI                ; erase (no hace nada)
        db "ww",0
        jr .lp
.n4:    cp 4
        jr nz,.n6
        ld a,ST_CEN                 ; center
        call .fld
        ld (hl),1
        inc hl
        ld (hl),0
        jr .lp
.n6:    cp 6
        jr nz,.n7
        ld a,ST_CEN                 ; left
        call .fld
        ld (hl),0
        inc hl
        ld (hl),0
        jp .lp
.n7:    cp 7
        jr nz,.n8
        ld a,ST_OVH                 ; overhead
        call .fld
        ld (hl),1
        jp .lp
.n8:    cp 8
        jr nz,.n15
        call PARAMSI                ; voz (no hace nada)
        db "ww",0
        jp .lp
.n15:   cp 15
        jp nz,.lp
        call COPYSTR                ; el texto
        ld a,(PRS)
        or a
        jr nz,.sys
        ld a,(PRA)
        OTCALL ACTORTALK
        jp RESTOREIY
.sys:   cp 1
        jp nz,RESTOREIY
        ld hl,BOUNCE
        ld (FARP),hl
        xor a
        ld (FARP+2),a
        inc a
        OTCALL DRAWSTRING
        jp RESTOREIY
.save:  ld hl,(PRST)                ; por defecto = actual
        ld de,STSZ
        ex de,hl
        add hl,de
        ex de,hl
        ld bc,STSZ
        ldir
        jp RESTOREIY
; HL = campo A de la ranura de texto
.fld:   ld hl,(PRST)
        add hl,a
        ret

; --- cadenas -----------------------------------------------------------------------
U_stringOps:
        call PARAMSI
        db "n",0
        ld a,(VMOP)
        and $1F
        cp 1
        jr nz,.n2
        call PARAMSI                ; cargar
        db "b",0
        call COPYSTR
        ld a,(P0)
        cp NUM_STR
        jp nc,RESTOREIY
        ld hl,BOUNCE                ; largo + 1
        call ESCLEN
        ld b,c
        ld a,(P0)
        ld hl,STRSZ
        add hl,a
        ld (hl),b
        ld c,2
        call HSETSTR
        call nc,.nosz
        jp RESTOREIY
.n2:    cp 2
        jr nz,.n3
        call PARAMSI                ; copiar
        db "bb",0
        ld a,(P0)
        cp NUM_STR
        jp nc,RESTOREIY
        ld hl,STRSZ
        add hl,a
        ld (hl),0
        ld c,2
        call UHFREE
        ld a,(P1)
        cp NUM_STR
        jp nc,RESTOREIY
        ld hl,STRSZ
        add hl,a
        ld a,(hl)
        or a
        jp z,RESTOREIY
        ld b,a                      ; a BOUNCE hasta el primer 0 (o el tamano)
        ld a,(P1)
        ld c,2
        push bc
        call UHOFS
        pop bc
        jp z,RESTOREIY
        ld de,$E000
        add hl,de
        ld a,HEAPP
        call MAP7
        ld de,BOUNCE
        call ESCCPY
        ld hl,BOUNCE
        call ESCLEN
        ld b,c
        ld a,(P0)
        ld hl,STRSZ
        add hl,a
        ld (hl),b
        ld a,(P0)
        ld c,2
        call HSETSTR
        call nc,.nosz
        jp RESTOREIY
.n3:    cp 3
        jr nz,.n4
        call PARAMSI                ; poner un byte
        db "bbb",0
        call .at
        jp z,RESTOREIY
        ld a,(P2)
        ld (hl),a
        jp RESTOREIY
.n4:    cp 4
        jr nz,.n5
        call PARAMSI                ; leer un byte (la variable del resultado no ocupa P)
        db "rbb",0
        call .at
        ld l,(hl)
        ld h,0
        jr nz,.r
        ld hl,0
.r:     call SETRESULT
        jp RESTOREIY
.n5:    cp 5
        jp nz,RESTOREIY
        call PARAMSI                ; crear con ceros
        db "bb",0
        ld a,(P0)
        cp NUM_STR
        jp nc,RESTOREIY
        ld c,2
        call UHFREE
        ld a,(P0)
        ld hl,STRSZ
        add hl,a
        ld a,(P1)
        ld (hl),a
        or a
        jp z,RESTOREIY
        ld a,2
        ld (HAK),a
        ld a,(P1)
        ld c,a
        ld b,0
        ld a,(P0)
        call UHALLOC
        jp nc,.nosz
        ld de,$E000
        add hl,de
        ld a,HEAPP
        call MAP7
        ld a,(P1)
        ld b,a
.z:     ld (hl),0
        inc hl
        djnz .z
        jp RESTOREIY
; la cadena P0 se queda sin tamano (no cupo)
.nosz:  ld a,(P0)
        ld hl,STRSZ
        add hl,a
        ld (hl),0
        jp RESTOREIY
; HL = el byte P1 de la cadena P0; NZ si existe
.at:    ld a,(P0)
        cp NUM_STR
        jr nc,.no
        ld hl,STRSZ
        add hl,a
        ld a,(P1)
        cp (hl)
        jr nc,.no
        ld a,(P0)
        ld c,2
        call UHOFS
        ret z
        ld de,$E000
        add hl,de
        ld a,(P1)
        add hl,a
        ld a,HEAPP
        call MAP7
        or 1
        ret
.no:    xor a
        ret

; setObjectName
U_setObjectName:
        call PARAMSI
        db "w",0
        call COPYSTR
        ld hl,(P0)
        ld (SONO),hl
        ld a,UIP                    ; si ya tenia nombre nuevo, se quita
        call MAP7
        ld hl,NNOBJ
        ld b,0
.f:     ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,(SONO)
        or a
        sbc hl,de
        pop hl
        jr nz,.fn
        dec hl
        ld (hl),0
        dec hl
        ld (hl),0
        ld a,b
        ld c,3
        call UHFREE
        jr .free
.fn:    inc b
        ld a,b
        cp NUM_NN
        jr nz,.f
.free:  ld a,UIP                    ; el primer hueco
        call MAP7
        ld hl,NNOBJ
        ld b,0
.g:     ld a,(hl)
        inc hl
        or (hl)
        jr z,.got
        inc hl
        inc b
        ld a,b
        cp NUM_NN
        jr nz,.g
        jp RESTOREIY
.got:   ld de,(SONO)
        ld (hl),d
        dec hl
        ld (hl),e
        ld a,b
        ld c,3
        call HSETSTR
        xor a
        call RUNINVSCR
        jp RESTOREIY

; actorOps 13: el nombre del actor AOACT
U_ACTNAME:
        call COPYSTR
        ld hl,(AOACT)
        ld a,h
        or a
        jp nz,RESTOREIY
        ld a,l
        call ACTOK
        jp nc,RESTOREIY
        ld e,a                      ; ANAMES + 32 * actor, en UIP (31 letras y el 0)
        ld d,32
        mul d,e
        ld hl,ANAMES
        add hl,de
        ex de,hl
        ld a,UIP
        call MAP7
        ld hl,BOUNCE
        ld b,31
        call ESCCPY
        jp RESTOREIY

; --- frases -----------------------------------------------------------------------
U_doSentence:
        xor a
        ld (MASKI),a
        call MASKNEXT
        jr z,.dir
        call READVAR
        ld a,l
        jr .one
.dir:   call VMFETCH
        cp $FE
        jr z,.stop
.one:   ld (DSV),a
        call MASKNEXT
        jr z,.d2
        call READVAR
        jr .two
.d2:    call VMFETCHW
.two:   ld (DSAO),hl
        call MASKNEXT
        jr z,.d3
        call READVAR
        jr .three
.d3:    call VMFETCHW
.three: ld (DSBO),hl
        ld a,(SENTN)
        cp 6
        jp nc,RESTOREIY
        ld e,a
        ld d,7
        mul d,e
        ld hl,SENT
        add hl,de
        ld a,(DSV)
        ld (hl),a
        inc hl
        ld de,(DSAO)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(DSBO)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld a,d
        or e
        jr z,.np
        ld a,1
.np:    ld (hl),a                   ; preposicion
        inc hl
        ld (hl),0                   ; congelada
        ld hl,SENTN
        inc (hl)
        jp RESTOREIY
.stop:  xor a                       ; doSentence(254): se acaban las frases
        ld (SENTN),a
        ld hl,(VARS+2*VAR_SENTENCE_SCRIPT)
        call STOPSCRIPT
        ld hl,0
        ld (MOUSEKB),hl
        jp RESTOREIY

; carry si alguna ranura tiene el numero HL
INUSE:
        ld (IUN),hl
        xor a
.lp:    push af
        call SLOTPTR
        inc hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(IUN)
        or a
        sbc hl,de
        jr z,.yes
        pop af
        inc a
        cp NSLOTS
        jr nz,.lp
        or a
        ret
.yes:   pop af
        scf
        ret

; checkAndRunSentenceScript
U_CHECKSENT:
        ld hl,(VARS+2*VAR_SENTENCE_SCRIPT)
        ld (CSN),hl
        call INUSE
        jr nc,.free
        xor a                       ; en marcha y sin congelar: se espera
.lp:    push af
        call SLOTPTR
        push hl
        pop ix
        ld a,(ix+SL_ST)
        or a
        jr z,.nx
        ld a,(ix+SL_FCNT)
        or a
        jr nz,.nx
        ld l,(ix+SL_NUM)
        ld h,(ix+SL_NUM+1)
        ld de,(CSN)
        or a
        sbc hl,de
        jr nz,.nx
        pop af
        ld ix,ACTOR
        ret
.nx:    pop af
        inc a
        cp NSLOTS
        jr nz,.lp
        ld ix,ACTOR
.free:  ld a,(SENTN)
        or a
        ret z
        dec a
        ld e,a
        ld d,7
        mul d,e
        ld hl,SENT+6
        add hl,de
        ld a,(hl)
        or a
        ret nz                      ; congelada
        ld hl,SENTN
        dec (hl)
        ld hl,SENT
        add hl,de
        ld a,(hl)
        ld (ARGS),a
        xor a
        ld (ARGS+1),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (ARGS+2),de
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld (ARGS+4),bc
        ld a,(hl)                   ; preposicion y a == b: nada
        or a
        jr z,.run
        ex de,hl
        or a
        sbc hl,bc
        ret z
.run:   ld a,$FF
        ld (CURSLOT),a
        ld hl,(CSN)
        ld a,h
        or l
        ret z
        ld a,3
        ld (ARGN),a
        ld a,l
        jp RUNSCRARGS

; A = 1 si wait 4 tiene que esperar (frases o el script de frases)
U_SENTBUSY:
        ld hl,(VARS+2*VAR_SENTENCE_SCRIPT)
        ld a,(SENTN)
        or a
        jr z,.use
        dec a
        ld e,a
        ld d,7
        mul d,e
        ld ix,SENT+6
        add ix,de
        ld a,(ix+0)
        ld ix,ACTOR
        or a
        jr z,.yes
        call INUSE
        jr c,.yes
        xor a
        ret
.use:   call INUSE
        ld a,0
        ret nc
.yes:   ld a,1
        ret

; runScript(A) con ARGS / ARGN, por SAFECALL
RUNSCRARGS:
        ld (RSAA),a
        xor a
        ld (SSFRES),a
        ld (SSREC),a
        ld hl,.go
        jp SAFECALL
.go:    ld a,(RSAA)
        call RUNSCRIPT
        jp RESTOREIY

; El script de inventario con el argumento A
RUNINVSCR:
        ld hl,(VARS+2*VAR_INVENTORY_SCRIPT)
        ld e,a
        ld a,h
        or l
        ret z
        ld a,e
        ld (ARGS),a
        xor a
        ld (ARGS+1),a
        inc a
        ld (ARGN),a
        ld a,l
        jr RUNSCRARGS

; --- entrada ---------------------------------------------------------------------
; Raton en (UMX, UMY): sus variables
U_SETMOUSE:
        ld hl,(UMX)
        ld (VARS+2*VAR_MOUSE_X),hl
        OTCALL XSTART
        ld hl,(UMX)
        add hl,de
        ld (VARS+2*VAR_VIRT_MOUSE_X),hl
        ld hl,(UMY)
        ld (VARS+2*VAR_MOUSE_Y),hl
        ld (VARS+2*VAR_VIRT_MOUSE_Y),hl
        ret

; La tecla A (processKeyboard)
U_KEY:
        or a
        ret z
        ld c,a
        cp 27
        jr nz,.n1
        ld hl,(VARS+2*VAR_CUTSCENEEXIT_KEY)
        ld a,h
        or l
        jr z,.n1
        push hl
        call ABORTCS
        pop hl
        ld h,0
        ld (MOUSEKB),hl
        ret
.n1:    ld hl,(VARS+2*VAR_TALKSTOP_KEY)
        ld a,h
        or a
        jr nz,.n2
        ld a,l
        cp c
        jr nz,.n2
        ld hl,0
        ld (TALKD),hl
        ret
.n2:    ld l,c
        ld h,0
        ld (MOUSEKB),hl
        ret

; abortCutscene
ABORTCS:
        ld a,(CSSP)
        add a,a
        ld hl,CUTPTR
        add hl,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        or e
        ret z
        ld (hl),0
        dec hl
        ld (hl),0
        ld a,(CSSP)
        ld hl,CSSCR
        add hl,a
        ld a,(hl)
        push de
        call SLOTPTR
        push hl
        pop ix
        pop de
        ld a,(ix+SL_ST)             ; ranura muerta (un cambio de habitacion la paro):
        or a                        ; solo se olvida el override
        jr z,.o2
        ld (ix+SL_PC),e
        ld (ix+SL_PC+1),d
        xor a
        ld (FPTR+1),a
        ld (ix+SL_ST),SS_RUNNING
        ld (ix+SL_FCNT),0
        ld a,(ix+SL_CSO)
        or a
        jr z,.o
        dec (ix+SL_CSO)
.o:     ld ix,ACTOR
        ld hl,1
        ld (VARS+2*VAR_OVERRIDE),hl
        ret
.o2:    ld ix,ACTOR
        ret

; checkExecVerbs
U_CHECKEXEC:
        ld hl,(MOUSEKB)
        ld (CEST),hl
        ld hl,0
        ld (MOUSEKB),hl
        ld hl,(USERPUT)
        bit 7,h
        ret nz
        ld a,h
        or l
        ret z
        ld hl,(CEST)
        ld a,h
        or l
        ret z
        bit 7,h
        jr nz,.mouse
        ld a,1                      ; tecla: ¿es la de un verbo?
.k:     ld (CEI),a
        call UVSADDR
        ld a,(hl)
        or a
        jr z,.kn
        ld (CEV),a
        push hl
        pop de
        ld hl,VS_SAVE
        add hl,de
        ld a,(hl)
        or a
        jr nz,.kn
        ld hl,VS_MODE
        add hl,de
        ld a,(hl)
        cp 1
        jr nz,.kn
        ld hl,VS_KEY
        add hl,de
        ld a,(CEST)
        cp (hl)
        jr nz,.kn
        ld a,(CEST+1)
        or a
        jr nz,.kn
        ld a,(CEV)                  ; runInputScript(1, verbo, 1)
        ld l,a
        ld h,0
        ld de,1
        ld a,1
        jr RUNINPUT
.kn:    ld a,(CEI)
        inc a
        cp NUM_VERBS
        jr nz,.k
        ld hl,(CEST)                ; runInputScript(4, tecla, 1)
        ld de,1
        ld a,4
        jr RUNINPUT
.mouse: ld a,(CEST)
        ld (CECODE),a
        ld hl,(UMY)
        OTCALL FINDVS
        cp $FF
        ret z
        ld (CEVS),a
        OTCALL FINDVERB
        or a
        jr z,.scene
        call UVSADDR
        ld l,(hl)
        ld h,0
        ld a,(CECODE)
        ld e,a
        ld d,0
        ld a,1
        jr RUNINPUT
.scene: ld a,(CEVS)
        or a
        ld a,2
        jr z,.s
        dec a
.s:     ld hl,0
        push af
        ld a,(CECODE)
        ld e,a
        ld d,0
        pop af
; runInputScript(A = zona, HL = valor, DE = modo)
RUNINPUT:
        ld (ARGS+2),hl
        ld (ARGS+4),de
        ld (ARGS),a
        xor a
        ld (ARGS+1),a
        ld hl,(VARS+2*VAR_VERB_SCRIPT)
        ld a,h
        or l
        ret z
        ld a,3
        ld (ARGN),a
        ld a,l
        jp RUNSCRARGS

; --- inventario -------------------------------------------------------------------
; whereIsObject(HL): A = WIO_ROOM, WIO_INVENTORY o $FF
WHEREIS:
        ld (WIO),hl
        ld a,h
        or l
        jr z,.no
        call OBJOK
        jr nc,.no
        ld hl,(WIO)
        call GETOWNER
        cp 15
        jr z,.room
        ld hl,(WIO)
        OTCALL INVFIND
        jr nc,.no
        ld a,WIO_INVENTORY
        ret
.room:  ld hl,(WIO)
        call OBJINDEX
        cp $FF
        ret z
        ld a,WIO_ROOM
        ret
.no:    ld a,$FF
        ret

; El bloque VERB del objeto WIO en la habitacion: FARP, VBLEN, SSBASE y SSKIND; carry si hay
VBLOCK:
        ld hl,(WIO)
        call OBJINDEX
        call OBJPTR
        ld de,O_VERB
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        cp $FF
        ret z
        ld (SSBASE),de
        ld (SSBASE+2),a
        ld bc,O_VLEN-O_VERB-2
        add hl,bc
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld (VBLEN),bc
        ld a,1
        ld (SSKIND),a
        ex de,hl                    ; FARP = STRIP_PAGE * 8192 + lineal
        ld a,(SSBASE+2)
        ld c,a
        ld a,h
        add a,(STRIP_PAGE & 7) << 5
        ld h,a
        ld a,c
        adc a,STRIP_PAGE >> 3
        ld (FARP),hl
        ld (FARP+2),a
        scf
        ret
; Objeto del inventario: el largo de su bloque y el principio (la tabla) a BOUNCE,
; leidos de INVOBJ.DAT (BOUNCE: largo (2), y el bloque); carry si lo hay
INVTABLE:
        ld hl,(WIO)
        OTCALL INVREC
        ret nc
        ld hl,130
        ld (FRLEN),hl
        xor a
        ld (FRPAGE),a
        ld hl,BOUNCE
        ld (FRADDR),hl
        ld hl,INVOBJNAME
        OTCALL CFREAD
        ccf
        ret nc
        ld hl,(BOUNCE)
        ld (VBLEN),hl
        ld a,h
        or l
        ret z
        scf
        ret

; getVerbEntrypoint(HL = objeto, A = verbo) -> HL (0 si no hay)
VERBENTRY:
        ld (VEV),a
        call WHEREIS
        cp $FF
        jr z,.zero
        ld (WHERE),a
        cp WIO_INVENTORY
        jr z,.inv
        call VBLOCK
        jr nc,.zero
        ld hl,(FARP)                ; la tabla, tras la cabecera de 8 bytes
        ld de,8
        add hl,de
        ld (FARP),hl
        jr nc,.lp
        ld hl,FARP+2
        inc (hl)
        jr .lp
.inv:   call INVTABLE
        jr nc,.zero
        ld hl,BOUNCE+2+8            ; la tabla, en BOUNCE
        ld (FARP),hl
        xor a
        ld (FARP+2),a
.lp:    call FARGET
        or a
        jr z,.zero
        ld b,a
        call FARGET
        ld l,a
        call FARGET
        ld h,a
        ld a,b
        cp $FF
        ret z
        ld a,(VEV)
        cp b
        ret z
        jr .lp
.zero:  ld hl,0
        ret

U_getVerbEntrypoint:
        call PARAMSI
        db "rww",0
        ld hl,(P0)
        ld a,(P1)
        call VERBENTRY
        call SETRESULT
        jp RESTOREIY

; startObject: objeto ROO, verbo ROV, argumentos ARGS
U_RUNOBJ:
        ld hl,(ROO)
        ld a,h
        or l
        ret z
        call STOPOBJSCR
        ld hl,(ROO)
        ld a,(ROV)
        call VERBENTRY
        ld a,h
        or l
        ret z
        ld (SSPC),hl
        ld hl,(ROO)
        ld (SSNUM),hl
        ld a,(WHERE)
        ld (SSWH),a
        cp WIO_INVENTORY
        jr z,.inv
        call VBLOCK
        jr .go0
.inv:   call CODELOAD               ; el bloque, a un hueco de la pagina INVP
        ret nc
.go0:   ld hl,(VBLEN)
        ld (SSLEN),hl
        xor a
        ld (SSFRES),a
        ld (SSREC),a
        ld hl,.go
        jp SAFECALL
.go:    call RESTOREIY
        ld ix,ACTOR
        call STARTSLOT
        jp RESTOREIY

; El bloque VERB del objeto del inventario WIO a un hueco libre (CODEBUF0 o 1) de
; la pagina INVP: SSBASE, SSKIND = 2; carry si cabe
CODELOAD:
        ld hl,CODEBUF0-$E000
        call .used
        ld de,1024
        jr nc,.free
        ld hl,CODEBUF1-$E000
        call .used
        ld de,CODEMAX1
        ccf
        ret nc
.free:  ld (CBUF),hl
        ld hl,(VBLEN)
        inc de
        call CPU16                  ; largo <= el hueco
        ret nc
        ld (FRLEN),hl
        ld hl,(WIO)
        OTCALL INVREC
        ret nc
        ld hl,(FROFF)               ; el bloque, tras su largo
        inc hl
        inc hl
        ld (FROFF),hl
        ld a,INVP
        ld (FRPAGE),a
        ld hl,(CBUF)
        ld de,$E000
        add hl,de
        ld (FRADDR),hl
        ld hl,INVOBJNAME
        OTCALL CFREAD
        ccf
        ret nc
        ld hl,(CBUF)
        ld (SSBASE),hl
        xor a
        ld (SSBASE+2),a
        ld a,2
        ld (SSKIND),a
        scf
        ret
; carry si una ranura viva tiene codigo del inventario en el hueco HL
.used:  push hl
        xor a
.ul:    push af
        call SLOTPTR
        push hl
        pop ix
        ld a,(ix+SL_ST)
        or a
        jr z,.un
        ld a,(ix+SL_KIND)
        cp 2
        jr nz,.un
        ld e,(ix+SL_BASE)
        ld d,(ix+SL_BASE+1)
        pop af
        pop hl
        push hl
        push af
        or a
        sbc hl,de
        jr nz,.un
        pop af
        pop hl
        ld ix,ACTOR
        scf
        ret
.un:    pop af
        inc a
        cp NSLOTS
        jr nz,.ul
        pop hl
        ld ix,ACTOR
        or a
        ret

; A = cuantos objetos del inventario son del dueno A
INVCOUNT:
        ld (ICO),a
        ld a,UIP
        call MAP7
        ld hl,INVOBJ
        ld b,NUM_INV
        ld c,0
.lp:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr z,.nx
        push hl
        push bc
        ex de,hl
        call GETOWNER
        pop bc
        ld hl,ICO
        cp (hl)
        jr nz,.n2
        inc c
.n2:    ld a,UIP
        call MAP7
        pop hl
.nx:    djnz .lp
        ld a,c
        ret

U_getInventoryCount:
        call PARAMSI
        db "rb",0
        ld a,(P0)
        call INVCOUNT
        ld l,a
        ld h,0
        call SETRESULT
        jp RESTOREIY

U_findInventory:
        call PARAMSI
        db "rbb",0
        ld a,1
        ld (FIC),a
        ld a,UIP
        call MAP7
        ld hl,INVOBJ
        ld b,NUM_INV
.lp:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr z,.nx
        push hl
        push bc
        push de
        ex de,hl
        call GETOWNER
        pop de
        pop bc
        ld hl,P0
        cp (hl)
        jr nz,.n2
        ld a,(P1)
        ld hl,FIC
        cp (hl)
        jr z,.got
        inc (hl)
.n2:    ld a,UIP
        call MAP7
        pop hl
.nx:    djnz .lp
        ld de,0
        jr .r
.got:   pop hl
.r:     ex de,hl
        call SETRESULT
        jp RESTOREIY

; pickupObject: el objeto entra en la lista del inventario (si esta en la habitacion;
; sus verbos, su codigo y su nombre se leen de INVOBJ.DAT cuando hacen falta)
ADDINV:
        ld (AIO),hl
        call OBJINDEX
        cp $FF
        ret z
        ld a,UIP
        call MAP7
        ld hl,INVOBJ
        ld b,NUM_INV
.f:     ld a,(hl)
        inc hl
        or (hl)
        jr z,.got
        inc hl
        djnz .f
        ret
.got:   ld de,(AIO)
        ld (hl),d
        dec hl
        ld (hl),e
        ret

U_pickupObject:
        call PARAMSI
        db "wb",0
        ld hl,(P0)
        call ADDINV
        ld hl,(P0)
        ld a,(VARS+2*VAR_EGO)
        call PUTOWNER
        ld hl,(P0)
        ld a,32
        ld b,1
        call PUTCLASS
        ld hl,(P0)                  ; (y deja de ir encima)
        call ZTOPCLR
        ld a,1
        jr z,.ps
        call PUTSTATEF
        jr .pd
.ps:    call PUTSTATE
.pd:    ld a,1
        call RUNINVSCR
        jp RESTOREIY

; El objeto HL sale de la lista del inventario (clearOwnerOf); la lista, sin huecos
CLEAROWNER:
        ld (COO),hl
        ld a,UIP
        call MAP7
        ld hl,INVOBJ
        ld de,INVOBJ
        ld b,NUM_INV
.lp:    ld c,(hl)                   ; c = bajo
        inc hl
        ld a,(hl)                   ; a = alto
        inc hl
        push hl
        ld h,a
        ld l,c
        or c
        jr z,.skip                  ; hueco
        push de
        ld de,(COO)
        or a
        sbc hl,de
        add hl,de
        pop de
        jr z,.skip                  ; el que sale
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ex de,hl
.skip:  pop hl
        djnz .lp
.z:     ld hl,INVOBJ+2*NUM_INV      ; el resto, a 0
        or a
        sbc hl,de
        ret z
        xor a
        ld (de),a
        inc de
        jr .z

U_setOwnerOf:
        call PARAMSI
        db "wb",0
        ld hl,(P0)
        call OBJOK
        jr nc,.inv
        ld a,(P1)
        or a
        jr nz,.put
        ld hl,(P0)
        call STOPOBJSCR
        ld hl,(P0)
        call GETOWNER
        cp 15
        jr z,.put
        ld hl,(P0)
        call CLEAROWNER
.put:   ld hl,(P0)
        ld a,(P1)
        call PUTOWNER
.inv:   xor a
        call RUNINVSCR
        jp RESTOREIY

; --- dibujar ------------------------------------------------------------------------
U_drawBox:
        call PARAMSI
        db "wwnwwb",0
        ld hl,(P1)                  ; y
        OTCALL FINDVS
        cp $FF
        jp z,RESTOREIY
        ld (PXVS),a
        ld hl,(P0)                  ; x <= x2, y <= y2
        ld de,(P3)
        call CPS16
        jr c,.x
        ld (P0),de
        ld (P3),hl
.x:     ld hl,(P1)
        ld de,(P4)
        call CPS16
        jr c,.y
        ld (P1),de
        ld (P4),hl
.y:     ld a,(PXVS)
        OTCALL VSTOP
        ld (DBT),hl
        ld hl,(P0)
        ld (FX0),hl
        ld hl,(P3)
        inc hl
        ld (FX1),hl
        ld de,(DBT)
        ld hl,(P1)
        or a
        sbc hl,de
        ld (FY0),hl
        ld hl,(P4)
        inc hl
        or a
        sbc hl,de
        ld (FY1),hl
        ld a,(P5)
        OTCALL FILLVS
        OTCALL L2DONE
        jp RESTOREIY

; setScreen(b, h): solo cuenta h (b es 0 en Monkey Island)
U_SETSCREEN:
        ld hl,(P1)
        bit 7,h
        jr z,.p
        ld hl,0
.p:     ld de,200
        call CPS16
        jr c,.ok
        ex de,hl
.ok:    ld a,l
        ld (MAINH),a
        ld a,1                      ; los verbos, en negro
        ld (PXVS),a
        ld hl,0
        ld (FX0),hl
        ld (FY0),hl
        ld hl,320
        ld (FX1),hl
        ld hl,200
        ld (FY1),hl
        xor a
        OTCALL FILLVS
        OTCALL L2DONE
        OTCALL VFLUSH               ; (ya: lo que habia debajo no puede esperar al
        OTCALL TMCLRALL             ; final del paso, que puede ser una carga)
        xor a
        ld (HASMASK),a
        ld (MASKV),a
        ld (VRECTV),a
        ld a,(CURROOM)
        or a
        ret z
        di
        call FULLDRAW
        ei
        OTCALL L2DONE
        ret

; Las fichas de los actores, a 0 (VMINIT)
U_CASTCLR:
        ld a,CAST_PAGE
        call MAP7
        ld hl,$E000
        ld de,$E001
        ld bc,$1FFF
        ld (hl),0
        ldir
        ret

; A = costume -> A = su primera pagina; carry si no hay (World.costume_for). Uno
; nuevo se carga detras del ultimo de la cache, si cabe antes de CAST_PAGE; si no
; cabe o no esta, se apunta que no hay.
CCOST:
        ld (CCOSTN),a
        ld hl,ECOST
        cp (hl)
        ld a,COST_PAGE
        ret z                       ; el del protagonista
        ld a,(CCN)
        or a
        jr z,.new
        ld b,a
        ld hl,CCNUM
        ld de,CCPG
        ld a,(CCOSTN)
.f:     cp (hl)
        jr nz,.fn
        ld a,(de)                   ; ya esta
        jp .got2
.fn:    inc hl
        inc de
        djnz .f
.new:   ld a,(CCN)
        cp COST_CACHE
        ccf
        ret c                       ; la cache esta llena
        ld a,(CCOSTN)               ; la cabecera: el tamano, big endian en 4-7
        ld c,'C'
        call MKNAME
        ld hl,0
        ld (FROFF),hl
        ld (FROFF+2),hl
        ld hl,8
        ld (FRLEN),hl
        ld a,CAST_PAGE
        ld (FRPAGE),a
        ld hl,CHDR
        ld (FRADDR),hl
        ld hl,NAMEBUF
        call FILEREAD
        ld b,$FF
        jr c,.add
        ld a,CAST_PAGE
        call MAP7
        ld a,(CHDR+4)
        or a
        jr nz,.add
        ld hl,(CHDR+6)              ; A:H:L = tamano + 8191
        ld a,l
        ld l,h
        ld h,a
        ld de,8191
        add hl,de
        ld a,(CHDR+5)
        adc a,0
        cp 32
        jr nc,.add
        add a,a                     ; paginas = (tamano + 8191) >> 13
        add a,a
        add a,a
        ld c,a
        ld a,h
        rlca
        rlca
        rlca
        and 7
        or c
        ld c,a
        ld a,(CCNEXT)
        add a,c
        jr c,.add
        cp CAST_PAGE+1
        jr nc,.add                  ; no cabe
        ld a,(CCNEXT)
        ld b,c
        ld hl,NAMEBUF
        push af
        push bc
        call LOADPAGES
        pop bc
        pop de                      ; D = su primera pagina
        ld b,$FF
        jr c,.add
        ld a,d
        ld b,a
        add a,c
        ld (CCNEXT),a
.add:   ld a,(CCN)                  ; (CCOSTN, B) a la cache
        ld e,a
        ld d,0
        ld hl,CCNUM
        add hl,de
        ld a,(CCOSTN)
        ld (hl),a
        ld hl,CCPG
        add hl,de
        ld (hl),b
        ld a,e
        inc a
        ld (CCN),a
        ld a,b
.got2:  cp $FF
        ccf
        ret

CHDR    EQU $FF00                   ; (en CAST_PAGE) la cabecera de un costume
CCNUM:  ds COST_CACHE               ; la cache: numero de costume
CCPG:   ds COST_CACHE               ; y su primera pagina ($FF: no hay)
CCOSTN: db 0


; (CLEARDIRTY) Sin tiras apuntadas (al cargar una habitacion)
U_CLEARDIRTY:
        ld hl,DIRTY
        ld b,33                     ; DIRTY, DIRTYF y STALE
.lp:    ld (hl),0
        inc hl
        djnz .lp
        ld hl,ZOBTOP                ; ninguno encima (ZOBTOP y ZTOPN)
        ld b,33
.lt:    ld (hl),0
        inc hl
        djnz .lt
        ld a,(NOBJ)                 ; los objetos que son padres de otro: bit 7 de O_DIR
        or a
        jr z,.k3
        ld b,a
        ld hl,(OBJT)
        ld de,O_DIR
        add hl,de
        push bc
        push hl
.k0:    res 7,(hl)
        add hl,O_SIZE
        djnz .k0
        pop hl
        pop bc
.k1:    push hl
        dec hl                      ; (O_PAR, dos antes de O_DIR)
        dec hl
        ld a,(hl)
        or a
        jr z,.k2
        ld hl,NOBJ                  ; (padre en la lista)
        cp (hl)
        jr z,.k4
        jr nc,.k2
.k4:    dec a
        call OBJPTR
        ld de,O_DIR
        add hl,de
        set 7,(hl)
.k2:    pop hl
        add hl,O_SIZE
        djnz .k1
.k3:    call ZIVCLR                 ; nada sabido de sus imagenes
        call ZON                    ; la x y el ancho de cada objeto (ZOBXO, ZOBWO)
        ld a,(NOBJ)
        or a
        jr z,.zx
        ld b,a
        ld c,0
.zo:    ld a,c
        call OBJPTR
        ld de,O_X
        add hl,de
        ld e,(hl)
        inc hl
        inc hl
        ld d,(hl)                   ; (O_W, dos despues)
        call ZWEFF
        ld l,c
        ld h,($6000+ZOBXO)>>8
        ld (hl),e
        inc h
        ld (hl),d
        inc c
        djnz .zo
.zx:    call ZBMBUILD               ; el mapa de los objetos de cada tira
        ld hl,$6000+ZOBID           ; el indice de cada objeto (OBJINDEX): el primero
        ld (hl),$FF                 ; con ese numero
        ld de,$6000+ZOBID+1
        ld bc,NOBJMAX-1
        ldir
        ld a,(NOBJ)
        or a
        jr z,.zy
        ld b,a
.zi:    ld a,b
        dec a
        push bc
        call OBJPTR
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,-NOBJMAX
        add hl,de
        jr c,.zn
        ld hl,$6000+ZOBID
        add hl,de
        pop bc
        push bc
        ld a,b
        dec a
        ld (hl),a
.zn:    pop bc
        djnz .zi
.zy:    ld hl,$6000+ZYMNO           ; ninguna fila en ninguna tira
        ld b,128
.cz:    ld (hl),$FF
        set 7,l
        ld (hl),0
        res 7,l
        inc l
        djnz .cz
        jp ZUNMAP

U_findObject:
        call PARAMSI
        db "rww",0
        ld hl,(P0)
        ld de,(P1)
        call FINDOBJ
        jp SETRESULT

; findObject(HL = x, DE = y) -> HL = numero del objeto (0 si no hay)
FINDOBJ:
        ld (FOX),hl
        ld (FOY),de
        ld a,(CURROOM)
        or a
        jp z,.none
        xor a
        ld (FOK),a
        ld a,h                      ; con 0 <= X < 2048, solo los de su tira X / 8 (la
        and $F8                     ; tabla ZOBXO, ZOBWO, como RECOMPOSER); FOF = 0
        ld (FOF),a
        jr nz,.lp0
        ld a,l
        srl h
        rra
        srl h
        rra
        srl h
        rra
        ld (FOS),a
        jp .scan
.lp0:   ld a,(FOK)
.lp:    ld hl,NOBJ
        cp (hl)
        jp nc,.none
        ld (FOK),a
        call OBJPTR
        push hl
        pop iy
        ld l,(iy+0)
        ld h,(iy+1)
        ld a,h
        or l
        jp z,.next
        ld a,32                     ; intocable?
        push iy
        call GETCLASS
        pop iy
        or a
        jp nz,.next
        ld (FOO),iy                 ; el objeto k
        ld b,16
.ch:    ld c,(iy+O_PST)
        ld a,(iy+O_PAR)
        or a
        jr z,.rect
        ld hl,NOBJ
        cp (hl)
        jr z,.in
        jr nc,.next
.in:    dec a
        push bc
        call OBJPTR
        pop bc
        push hl
        pop iy
        call OSTATE
        and $0F
        cp c
        jr nz,.next
        djnz .ch
        jr .next
.rect:  ld iy,(FOO)
        ld a,(iy+O_X)               ; 8x <= X < 8(x + ancho)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ex de,hl
        ld hl,(FOX)
        call CPS16
        jr c,.next
        ld a,(iy+O_X)
        add a,(iy+O_W)
        ld l,a
        ld a,0
        adc a,0
        ld h,a
        add hl,hl
        add hl,hl
        add hl,hl
        ex de,hl
        ld hl,(FOX)
        call CPS16
        jr nc,.next
        ld e,(iy+O_Y)               ; y <= Y < y + alto
        ld d,0
        ld hl,(FOY)
        call CPS16
        jr c,.next
        ld a,(iy+O_Y)
        add a,(iy+O_H)
        ld e,a
        ld a,0
        adc a,0
        ld d,a
        ld hl,(FOY)
        call CPS16
        jr nc,.next
        ld l,(iy+0)
        ld h,(iy+1)
        jp RESTOREIY
.next:  ld a,(FOK)
        inc a
        ld (FOK),a
        ld a,(FOF)
        or a
        jp nz,.lp0
.scan:  call ZON                    ; el siguiente desde FOK en la tira FOS
        ld a,(FOK)
        ld l,a
        ld a,(NOBJ)
        sub l
        jr z,.sn
        ld b,a
        ld a,(FOS)
        ld c,a
        ld h,($6000+ZOBXO)>>8
.sl:    ld a,c
        sub (hl)
        inc h
        cp (hl)
        dec h
        jr c,.cand
        inc l
        djnz .sl
.sn:    call ZUNMAP
        jr .none
.cand:  ld a,l
        ld (FOK),a
        call ZUNMAP
        ld a,(FOK)
        jp .lp
.none:  ld hl,0
        jp RESTOREIY
FOS:    db 0                        ; (FINDOBJ) la tira de X
FOF:    db 0                        ; y 0 si se mira con la tabla
FOX:    dw 0
FOY:    dw 0
FOK:    db 0
FOO:    dw 0

; o5_drawObject: el objeto P0 (con setXY, alli) en el estado DOST, y los demas de su
; mismo rectangulo, a 0. El mismo no pasa por 0: si ya estaba en DOST, nada que
; rehacer (los scripts lo dibujan una y otra vez).
U_drawObject:
        call PARAMSI
        db "wn",0
        ld hl,(P0)
        ld (DOOBJ),hl
        ld hl,1
        ld (DOST),hl
        ld a,(VMOP)
        and $1F
        cp 1
        jr nz,.s2
        call PARAMSI
        db "ww",0
        jr .go
.s2:    cp 2
        jr nz,.go
        call PARAMSI
        db "w",0
        ld hl,(P0)
        ld (DOST),hl
.go:    ld hl,(DOOBJ)
        call OBJINDEX
        cp $FF
        ret z
        ld c,a
        ld (DOSLF),a
        call U_SETXY                ; (setXY: se mueve)
        call OBJPTR                 ; el rectangulo del objeto
        ld de,O_X
        add hl,de
        ld de,DORECT
        ld bc,4
        ldir
        ld hl,$6000+ZOBXO           ; los de su misma x (la tabla ZOBXO), uno a uno
.lp:    ld a,(NOBJ)                 ; (OBJINDEX: hay alguno)
        sub l
        jr z,.self
        ld c,a
        ld b,0
        call ZON
        ld a,(DORECT)
        cpir
        push hl
        push af
        call ZUNMAP
        pop af
        jr nz,.end
        ld a,l
        dec a
        ld (DOK),a
        call OBJPTR
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr z,.next
        inc hl                      ; (la x ya es la misma)
        ld a,(DORECT+1)
        cp (hl)
        jr nz,.next
        inc hl
        ld a,(DORECT+2)
        cp (hl)
        jr nz,.next
        inc hl
        ld a,(DORECT+3)
        cp (hl)
        jr nz,.next
        ld hl,(DOOBJ)               ; (el mismo, despues)
        or a
        sbc hl,de
        jr z,.next
        ex de,hl
        ld a,(DOK)
        ld b,a
        xor a
        call .put
.next:  pop hl
        jr .lp
.end:   pop hl
.self:  ld a,(DOSLF)                ; el va encima (en SCUMM, a la cola de dibujo): si no
        call ZTOPON                 ; iba, se rehace aunque no cambie de estado
        ld hl,(DOOBJ)
        ld a,(DOSLF)
        ld b,a
        ld a,(DOST)
        jr z,.put
        ld c,a
        call OBJOK
        ret nc
        push hl
        ld de,OBJST
        add hl,de
        ld (hl),c
        pop hl
        jr .rd
; el estado A para el objeto HL, que es el de indice B (PUTSTATE sin buscarlo)
.put:   ld c,a
        call OBJOK
        ret nc
        push hl
        ld de,OBJST
        add hl,de
        ld a,(hl)
        ld (hl),c
        pop hl
        cp c
        ret z
.rd:    ld a,b
        call REDRAWOBJ
        ld ix,ACTOR
        jp RESTOREIY

; o5_setState: y el objeto deja de ir encima (SCUMM lo rehace con el orden de los
; indices); si iba, se rehace aunque no cambie de estado
U_setState:
        call PARAMSI
        db "wb",0
        ld hl,(P0)
        call ZTOPCLR
        ld a,(P1)
        jp z,PUTSTATE
; el estado A para el objeto HL, y se rehace aunque sea el mismo
PUTSTATEF:
        ld c,a
        call OBJOK
        ret nc
        push hl
        ld de,OBJST
        add hl,de
        ld (hl),c
        pop hl
        jp PSREDRAW

; El objeto HL (si esta en la habitacion) deja de ir encima; nz si iba (no cambia HL)
ZTOPCLR:
        push hl
        ld a,(CURROOM)
        or a
        jr z,.no
        call OBJINDEX
        cp $FF
        jr z,.no
        call ZTOPAD
        ld c,a
        and (hl)
        jr z,.no
        ld a,c
        cpl
        and (hl)
        ld (hl),a
        ld hl,ZTOPN
        dec (hl)
        pop hl
        or $FF
        ret
.no:    pop hl
        xor a
        ret

; El objeto de indice A va encima; nz si no iba
ZTOPON: call ZTOPAD
        ld c,a
        and (hl)
        jr nz,.ya
        ld a,(hl)
        or c
        ld (hl),a
        ld hl,ZTOPN
        inc (hl)
        or $FF
        ret
.ya:    xor a
        ret
DOSLF:  db 0

; (U_SETXY) La x y el ancho del objeto A, otra vez a ZOBXO y ZOBWO (los que mira RECOMPOSER)
ZOBSET: push af
        call OBJPTR
        ld de,O_X
        add hl,de
        ld e,(hl)
        inc hl
        inc hl
        ld d,(hl)                   ; (O_W, dos despues)
        call ZWEFF
        call ZON
        pop af
        push af
        push de
        ld c,0                      ; (del mapa de sus tiras con la x de antes, fuera)
        ld hl,ZBMOK
        bit 0,(hl)
        call nz,ZBMOBJ
        pop de
        pop af
        push af
        ld l,a
        ld h,($6000+ZOBXO)>>8
        ld (hl),e
        inc h
        ld (hl),d
        ld c,1                      ; (y con la de ahora, dentro)
        ld hl,ZBMOK
        bit 0,(hl)
        call nz,ZBMOBJ
        call ZUNMAP
        pop af
        ret

; (ZSCR por $6000) El mapa de los objetos de cada tira (ZOBBM, 8 bytes por tira, bit
; k = el objeto k), si caben: hasta 64 objetos y 96 tiras (ZBMOK; si no, RECOMPOSER
; los mira todos)
ZBMBUILD:
        xor a
        ld (ZBMOK),a
        ld a,(NOBJ)
        cp 65
        ret nc
        ld a,(RNS)
        cp 97
        ret nc
        ld hl,$6000+ZOBBM
        ld de,$6000+ZOBBM+1
        ld bc,8*96-1
        ld (hl),0
        ldir
        ld a,(NOBJ)
        or a
        jr z,.ok
        ld b,a
.k:     ld a,b
        dec a
        push bc
        ld c,1
        call ZBMOBJ
        pop bc
        djnz .k
.ok:    ld a,1
        ld (ZBMOK),a
        ret

; (ZSCR por $6000) El objeto A en el mapa de sus tiras (ZOBXO, ZOBWO): C = 1 lo pone,
; 0 lo quita
ZBMOBJ: ld (ZBK),a
        ld l,a
        ld h,($6000+ZOBXO)>>8
        ld e,(hl)                   ; x
        inc h
        ld b,(hl)                   ; ancho
        ld a,b
        or a
        ret z
        ld a,(ZBK)
        and 7
        ld hl,BITMASKS
        add hl,a
        ld d,(hl)                   ; su bit
        ld a,(ZBK)
        rrca
        rrca
        rrca
        and 31
        ld (ZBB),a                  ; y su byte
.s:     ld a,e
        ld hl,RNS
        cp (hl)
        ret nc
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(ZBB)
        add hl,a
        push de
        ld de,$6000+ZOBBM
        add hl,de
        pop de
        ld a,c
        or a
        ld a,d
        jr z,.cl
        or (hl)
        ld (hl),a
        jr .n
.cl:    cpl
        and (hl)
        ld (hl),a
.n:     inc e
        djnz .s
        ret
ZBK:    db 0
ZBB:    db 0
; drawObject setXY (subcodigo 1; x = P0, y = P1, en unidades de 8): el objeto de
; indice C va alli, y su punto de llegada con el; se apuntan sus tiras de antes y las
; de ahora (o5_drawObject). Devuelve A = C (el indice).
U_SETXY:
        ld a,(VMOP)
        and $1F
        cp 1
        ld a,c
        ret nz
        ld hl,(P0)                  ; (x = 255: no se mueve)
        ld de,255
        or a
        sbc hl,de
        ld a,c
        ret z
        push af
        call OBJPTR                 ; (en el mismo sitio: nada que rehacer)
        ld de,O_X
        add hl,de
        ld a,(P0)
        cp (hl)
        jr nz,.mv
        inc hl
        ld a,(P1)
        add a,a
        add a,a
        add a,a
        cp (hl)
        jr nz,.mv
        pop af
        ret
.mv:    pop af
        push af
        call REDRAWOBJ              ; las tiras de donde estaba
        pop af
        push af
        call OBJPTR
        push hl
        ld de,O_X
        add hl,de
        ld e,(hl)                   ; E = x de antes, D = y de antes
        ld a,(P0)
        ld (hl),a
        inc hl
        ld d,(hl)
        ld a,(P1)
        add a,a
        add a,a
        add a,a
        ld (hl),a
        pop hl
        push de
        ld de,O_WX                  ; llegada x += x * 8 - x de antes * 8
        add hl,de
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld bc,(P0)
        call .x8
        add hl,bc
        pop de                      ; (DE = &llegada x)
        pop bc                      ; C = x de antes, B = y de antes
        push bc
        ld b,0
        call .x8
        or a
        sbc hl,bc
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl                      ; llegada y += y * 8 - y de antes
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld bc,(P1)
        call .x8
        add hl,bc
        pop de
        pop bc
        ld c,b
        ld b,0
        or a
        sbc hl,bc
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        pop af
        push af
        call ZOBSET                 ; (su x, en la tabla de RECOMPOSER)
        call REDRAWOBJ              ; y las de donde esta
        ld ix,ACTOR
        call RESTOREIY
        pop af
        ret
.x8:    sla c                       ; BC *= 8
        rl b
        sla c
        rl b
        sla c
        rl b
        ret

; La pagina UIP a 0 y los indices de las imagenes de verbo y de los objetos del
; inventario (lo que falte se queda en 0: no hay)
LOADIDX:
        ld a,UIP
        call MAP7
        ld hl,$E000
        ld de,$E001
        ld bc,$1FFF
        ld (hl),0
        ldir
        ld hl,0
        ld (FROFF),hl
        ld (FROFF+2),hl
        ld hl,2+8*VIDX_MAX
        ld (FRLEN),hl
        ld a,UIP
        ld (FRPAGE),a
        ld hl,VIDX
        ld (FRADDR),hl
        ld hl,VIMGNAME
        call FILEREAD
        ld a,UIP                    ; no mas de VIDX_MAX
        call MAP7
        ld hl,(VIDX)
        ld de,VIDX_MAX+1
        call CPU16
        jr c,.v
        ld hl,VIDX_MAX
        ld (VIDX),hl
.v:     ld hl,0
        ld (FROFF),hl
        ld (FROFF+2),hl
        ld hl,2+2*NOBJMAX
        ld (FRLEN),hl
        ld hl,IIDX
        ld (FRADDR),hl
        ld hl,INVOBJNAME
        call FILEREAD
        ld a,UIP
        call MAP7
        ld hl,(IIDX)
        ld de,NOBJMAX+1
        call CPU16
        ret c
        ld hl,0                     ; demasiados objetos: sin inventario
        ld (IIDX),hl
        ret

; --- instrucciones que se usan poco (desde el banco 0) ---------------------------
U_cutscene:
        call PARAMSI
        db "v",0
        inc (iy+SL_CSO)
        ld a,(CSSP)
        cp 5
        jr nc,.n
        inc a
        ld (CSSP),a
.n:     ld bc,0
        ld a,(ARGN)
        or a
        jr z,.d
        ld bc,(ARGS)
.d:     ld de,CSDATA
        call CSAT
        ld (hl),c
        inc hl
        ld (hl),b
        call CSCLR
        ld a,(CURSLOT)
        ld (CSIDX),a
        ld hl,(VARS+2*VAR_CUTSCENE_START_SCRIPT)
        call RUNVARGS
        ld a,$FF
        ld (CSIDX),a
        ret

U_endCutscene:
        ld a,(iy+SL_CSO)
        or a
        jr z,.c1
        dec (iy+SL_CSO)
.c1:    ld de,CSDATA                ; argumentos: el dato de este nivel
        call CSAT
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (ARGS),hl
        ld a,1
        ld (ARGN),a
        ld hl,0
        ld (VARS+2*VAR_OVERRIDE),hl
        ld de,CUTPTR
        call CSAT
        ld a,(hl)
        inc hl
        or (hl)
        jr z,.c2
        ld a,(iy+SL_CSO)
        or a
        jr z,.c2
        dec (iy+SL_CSO)
.c2:    call CSCLR
        ld a,(CSSP)
        or a
        jr z,.c3
        dec a
        ld (CSSP),a
.c3:    ld hl,(VARS+2*VAR_CUTSCENE_END_SCRIPT)
        jp RUNVARGS

U_chainScript:
        call PARAMSI
        db "bv",0
        ld a,(iy+SL_FRES)
        ld (SSFRES),a
        ld a,(iy+SL_REC)
        ld (SSREC),a
        xor a
        ld (iy+SL_ST),a
        ld (iy+SL_NUM),a
        ld (iy+SL_NUM+1),a
        ld a,$FF
        ld (CURSLOT),a
        jp SCRP0

U_setVarRange:
        call PARAMSI
        db "r",0
        call VMFETCH
        ld b,a                      ; cuantas (0 = 256)
        ld hl,(RESVAR)
        ld (SVRN),hl
.lp:    ld a,(VMOP)
        bit 7,a
        jr z,.byte
        call VMFETCHW
        jr .st
.byte:  call VMFETCH
        ld l,a
        ld h,0
.st:    ex de,hl
        ld hl,(SVRN)
        push bc
        call WRITENUM
        pop bc
        ld hl,(SVRN)
        inc hl
        ld (SVRN),hl
        djnz .lp
        ret

U_setClass:
        call PARAMSI
        db "w",0
        ld hl,(P0)
        ld (CLSOBJ),hl
.lp:    call VMFETCH
        cp $FF
        ret z
        ld (VMOP),a
        xor a
        ld (MASKI),a
        call MASKNEXT
        jr z,.dir
        call READVAR
        jr .got
.dir:   call VMFETCHW
.got:   ld a,l
        or a
        jr nz,.put
        ld hl,(CLSOBJ)              ; clase 0: las borra todas
        call CLRCLASSES
        jr .lp
.put:   ld b,a
        and $80
        ld c,a
        ld a,b
        ld b,c
        ld hl,(CLSOBJ)
        call PUTCLASS
        jr .lp

U_ifClassOfIs:
        call PARAMSI
        db "w",0
        ld hl,(P0)
        ld (CLSOBJ),hl
        ld a,1
        ld (CLSC),a
.lp:    call VMFETCH
        cp $FF
        jr z,.end
        ld (VMOP),a
        xor a
        ld (MASKI),a
        call MASKNEXT
        jr z,.dir
        call READVAR
        jr .got
.dir:   call VMFETCHW
.got:   ld a,l
        ld (CLSN),a
        ld hl,(CLSOBJ)
        call GETCLASS
        ld b,a
        ld a,(CLSN)
        and $80
        jr z,.off
        ld a,b                      ; con $80: tiene que tenerla
        or a
        jr nz,.lp
        jr .fail
.off:   ld a,b                      ; sin $80: no tiene que tenerla
        or a
        jr z,.lp
.fail:  xor a
        ld (CLSC),a
        jr .lp
.end:   call PARAMSI
        db "j",0
        ld a,(CLSC)
        ld hl,(P0)
        jp JUMPIF

U_override:
        call VMFETCH
        or a
        jr z,.end
        call VMFETCH                ; el salto que se salta
        call VMFETCHW
        ld de,CUTPTR
        call CSAT
        ld de,(VMSTART)
        inc de
        inc de
        ld (hl),e
        inc hl
        ld (hl),d
        ld a,(CSSP)
        ld hl,CSSCR
        add hl,a
        ld a,(CURSLOT)
        ld (hl),a
        jr .ov
.end:   call CSCLR
.ov:    ld hl,0
        ld (VARS+2*VAR_OVERRIDE),hl
        ret

U_matrixOps:
        call PARAMSI
        db "n",0
        ld a,(VMOP)
        and $1F
        ld (MATK),a
        ld hl,MATFMT
        call SUBFMT
        ld a,(MATK)
        cp 1
        jr nz,.s
        ld hl,(P0)
        ld de,(P1)
        jp SETBOXFLAGS
.s:     cp 4
        jr z,.m
        ret nc
        ld hl,(P0)
        ld de,(P1)
        jp SETBOXSCALE
.m:     ld hl,F_BOXMATRIX           ; createBoxMatrix (capa OVF)
        ld a,OVF_PAGE
        jp OVCALL

U_roomOps:
        call PARAMSI
        db "n",0
        ld a,(VMOP)
        and $1F
        ld (ROSUB),a                ; (la n de dentro de 4 y 11 cambia VMOP)
        ld hl,ROOMFMT
        call SUBFMT
        ld a,(ROSUB)
        cp 3
        jr nz,.n3
        jp U_SETSCREEN
.n3:    cp 1
        jr z,.s1
        ld hl,F_ROOMOPS             ; 4, 5, 6, 8, 10 y 11: paleta y pantalla (OVF)
        ld a,OVF_PAGE
        jp OVCALL
.s1:
        ld hl,(P0)                  ; limites de la camara
        call .lim
        ld (VARS+2*VAR_CAMERA_MIN_X),hl
        ld hl,(P1)
        call .lim
        ld (VARS+2*VAR_CAMERA_MAX_X),hl
        ret
; HL = max(HL, 160) y despues min(HL, RW - 160) (o5_roomOps: _roomWidth)
.lim:   ld de,160
        call CPS16
        jr nc,.l1
        ex de,hl
.l1:    push hl
        ld hl,(RW)
        ld de,-160
        add hl,de
        pop de
        call CPS16                  ; RW - 160 < valor ?
        ret c
        ex de,hl
        ret

OVU_END:
        ASSERT OVU_END <= $E000, la capa OVU no cabe
