; ===========================================================================
;  Maquina virtual de SCUMM v5 (tools/vm.py hace lo mismo y sirve de modelo)
;
;  IY = ranura en marcha (CURSL). Los operandos se leen con PARAMSI y una
;  cadena de formato detras de la llamada:
;    b / w  byte / palabra directos, o variable si lo dice su bit de parametro
;    B / W  byte / palabra directos siempre
;    V      variable (su valor)          r  variable de resultado (RESVAR)
;    n      subcodigo (cambia las mascaras)   s  texto (STRLEN)
;    v      lista de argumentos (ARGS)    j  salto (destino)
;  Los valores quedan en P0, P1... (16 bits).
; ===========================================================================

; --- leer el codigo -----------------------------------------------------------
; A = siguiente byte del script de la ranura IY (avanza el pc; no cambia nada mas).
; FPTR: donde esta (por $E000, en la pagina .pg+1) el byte del pc; H = 0 si no se
; sabe (lo olvidan SETCUR y quien cambie el pc: JUMPIF, STARTSLOT...). Al pasar de
; $FFFF se queda en 0: la pagina siguiente, otra vez por .slow.
VMFETCH:
        push hl
        ld hl,(FPTR)
        ld a,h
        or a
        jr z,.slow
        ld a,(SHMMU7)
.pg:    cp 0                        ; (la pagina, la pone .slow)
        jr nz,.map
.rd:    ld a,(hl)
        inc hl
        ld (FPTR),hl
        inc (iy+SL_PC)
        jr z,.hi
        pop hl
        ret
.hi:    inc (iy+SL_PC+1)
        pop hl
        ret
.map:   ld a,(.pg+1)
        call MAP7
        jr .rd
.slow:  push de
        ld l,(iy+SL_PC)
        ld h,(iy+SL_PC+1)
        ld e,(iy+SL_BASE)
        ld d,(iy+SL_BASE+1)
        add hl,de
        ld a,(iy+SL_BASE+2)
        adc a,0                     ; A:HL = posicion lineal
        ld e,a                      ; D = su pagina de 8 KB, cambiada de orden: los bits
        ld a,h                      ; 13-15 arriba, 16-20 abajo
        and $E0
        or e
        ld d,a
        ld a,h                      ; HL, por $E000
        and $1F
        or $E0
        ld h,a
        ld a,(LPKEY)                ; la misma que la vez anterior?
        cp d
        jr nz,.lin
        ld a,(LPKIND)
        cp (iy+SL_KIND)
        jr nz,.lin
        ld a,(LPPHYS)
.ph:    ld (.pg+1),a
        call MAP7
        pop de
        jr .rd
.lin:   ld a,d                      ; la pagina fisica: la lineal en el espacio de la
        ld (LPKEY),a                ; ranura (IY+SL_KIND)
        and $1F
        add a,a
        add a,a
        add a,a
        ld e,a
        ld a,d
        rlca
        rlca
        rlca
        and 7
        or e
        ld e,a                      ; E = pagina lineal
        ld a,(iy+SL_KIND)
        ld (LPKIND),a
        cp 2
        ld a,e
        jr z,.inv
        jr nc,.room
        ld a,(iy+SL_KIND)
        or a
        ld a,e
        jr nz,.room
        push hl                     ; 0: scripts globales (SPAGES)
        ld hl,SPAGES
        add hl,a
        ld a,(hl)
        pop hl
        jr .st
.inv:   add a,INVP
        jr .st
.room:  add a,STRIP_PAGE
.st:    ld (LPPHYS),a
        jr .ph
LPKEY:  db 0                        ; (VMFETCH) la ultima pagina lineal,
LPKIND: db $FF                      ; su clase ($FF: ninguna)
LPPHYS: db 0                        ; y su pagina fisica
FPTR:   dw 0

; HL = palabra del script
VMFETCHW:
        call VMFETCH
        ld l,a
        call VMFETCH
        ld h,a
        ret

; HL = numero de variable (con el indice ya sumado si lleva el bit $2000)
GETVARNUM:
        call VMFETCHW
        bit 5,h
        ret z
        push hl
        call VMFETCHW
        bit 5,h
        jr z,.lit
        res 5,h
        call READNUM
        jr .add
.lit:   ld a,h
        and $0F
        ld h,a
.add:   ex de,hl
        pop hl
        add hl,de
        res 5,h
        ret

; HL = valor de la variable HL (0 si no existe). No cambia DE ni BC.
READNUM:
        push de
        ld a,h
        and $F0
        jr nz,.notg
        ld de,NVARS
        call CPU16
        jr nc,.zero
        add hl,hl
        ld de,VARS
        add hl,de
.rd:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        pop de
        ret
.notg:  bit 7,h
        jr z,.notb
        res 7,h
        call BITADDR
        jr nc,.zero
        and (hl)
        ld hl,0
        jr z,.b0
        inc l
.b0:    pop de
        ret
.notb:  bit 6,h
        jr z,.zero
        call LOCADDR
        jr c,.rd
.zero:  ld hl,0
        pop de
        ret

; HL = n de bit -> HL = byte, A = mascara; nc si se sale. Cambia DE.
BITADDR:
        ld a,l
        and 7
        ld (BITTMP),a
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld a,h
        or a
        jr nz,.no                   ; >= 2048 bits
        ld de,BITS
        add hl,de
        push hl
        ld a,(BITTMP)
        ld hl,BITMASKS
        add hl,a
        ld a,(hl)
        pop hl
        scf
        ret
.no:    or a
        ret


; HL = variable local (con $4000) -> HL = direccion; nc si no hay
LOCADDR:
        ld a,h
        and $0F
        ld h,a
        ld de,NLOCALS
        call CPU16
        ret nc
        ld a,(CURSLOT)
        cp $FF
        jr z,.no
        add hl,hl
        ld de,SL_LOC
        add hl,de
        ld de,(CURSL)
        add hl,de
        scf
        ret
.no:    or a
        ret

; Variable HL = DE
WRITENUM:
        ld a,h
        and $F0
        jr nz,.notg
        push de
        ld de,NVARS
        call CPU16
        pop de
        ret nc
        add hl,hl
        push de
        ld de,VARS
        add hl,de
        pop de
.wr:    ld (hl),e
        inc hl
        ld (hl),d
        ret
.notg:  bit 7,h
        jr z,.notb
        res 7,h
        push de
        call BITADDR
        pop de
        ret nc
        ld c,a                      ; mascara
        ld a,d
        or e
        ld a,c
        jr z,.clr
        or (hl)
        ld (hl),a
        ret
.clr:   cpl
        and (hl)
        ld (hl),a
        ret
.notb:  bit 6,h
        ret z
        push de
        call LOCADDR
        pop de
        jr c,.wr
        ret

; HL = valor de una variable leida del script
READVAR:
        call GETVARNUM
        jp READNUM

; --- operandos ----------------------------------------------------------------
PARAMSI:
        ex (sp),hl
        push de
        push bc
        call PARAMSF
        pop bc
        pop de
        ex (sp),hl
        ret

; HL = formato. Deja HL tras el 0.
PARAMSF:
        xor a
        ld (PIDX),a
        ld (MASKI),a
.lp:    ld a,(hl)
        inc hl
        or a
        ret z
        push hl
        cp 'b'
        jr z,.b
        cp 'w'
        jr z,.w
        cp 'B'
        jr z,.bd
        cp 'W'
        jr z,.wd
        cp 'V'
        jr z,.v
        cp 'r'
        jr z,.r
        cp 'n'
        jr z,.n
        cp 's'
        jr z,.s
        cp 'v'
        jr z,.va
        cp 'j'
        jr z,.j
        pop hl
        jr .lp
.b:     call MASKNEXT
        jr z,.bd
        call READVAR
        jr .st
.bd:    call VMFETCH
        ld l,a
        ld h,0
        jr .st
.w:     call MASKNEXT
        jr z,.wd
        call READVAR
        jr .st
.wd:    call VMFETCHW
        jr .st
.v:     call READVAR
        jr .st
.r:     call GETVARNUM
        ld (RESVAR),hl
        pop hl
        jr .lp
.n:     call VMFETCH
        ld (VMOP),a
        ld l,a
        ld h,0
        xor a
        ld (MASKI),a
        jr .st
.s:     call SKIPSTR
        pop hl
        jr .lp
.va:    call VARARG
        pop hl
        jr .lp
.j:     call VMFETCHW               ; destino = pc + desplazamiento
        ld e,(iy+SL_PC)
        ld d,(iy+SL_PC+1)
        add hl,de
.st:    ex de,hl                    ; P[PIDX] = DE
        ld a,(PIDX)
        ld l,a
        inc a
        ld (PIDX),a
        ld h,0
        add hl,hl
        ld bc,P0
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        pop hl
        jp .lp

; Z si el siguiente parametro es directo (bit de VMOP para MASKI apagado)
MASKNEXT:
        ld a,(MASKI)
        ld e,a
        inc a
        ld (MASKI),a
        ld a,$80
        inc e
.sh:    dec e
        jr z,.ok
        srl a
        jr .sh
.ok:    ld e,a
        ld a,(VMOP)
        and e
        ret

; Salta un texto: STRLEN = bytes antes del 0
SKIPSTR:
        ld hl,0
.lp:    call VMFETCH
        or a
        jr z,.end
        inc hl
        cp $FF
        jr nz,.lp
        call VMFETCH
        inc hl
        cp 1
        jr z,.lp
        cp 2
        jr z,.lp
        cp 3
        jr z,.lp
        cp 8
        jr z,.lp
        call VMFETCH
        call VMFETCH
        inc hl
        inc hl
        jr .lp
.end:   ld (STRLEN),hl
        ret

; Lista de argumentos -> ARGS / ARGN (como mucho NLOCALS)
VARARG:
        xor a
        ld (ARGN),a
.lp:    call VMFETCH
        cp $FF
        ret z
        ld (VMOP),a
        and $80
        jr z,.dir
        call READVAR
        jr .st
.dir:   call VMFETCHW
.st:    ld a,(ARGN)
        cp NLOCALS
        jr nc,.lp
        ex de,hl
        ld l,a
        inc a
        ld (ARGN),a
        ld h,0
        add hl,hl
        ld bc,ARGS
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        jr .lp

; Si A = 0 (no se cumple), el pc salta a HL
JUMPIF:
        or a
        ret nz
        ld (iy+SL_PC),l
        ld (iy+SL_PC+1),h
        ld (FPTR+1),a               ; (A = 0: VMFETCH ya no sabe donde esta)
        ret

; resultado = HL
SETRESULT:
        ex de,hl
        ld hl,(RESVAR)
        jp WRITENUM

; --- ranuras --------------------------------------------------------------------
; HL = ranura A
SLOTPTR:
        ld e,a
        ld d,SLOTSZ
        mul d,e
        ld hl,SLOTS
        add hl,de
        ret

; Ranura en marcha = A ($FF: ninguna)
SETCUR:
        ld (CURSLOT),a
        push af
        xor a
        ld (FPTR+1),a               ; (otra ranura: VMFETCH no sabe donde esta)
        pop af
        cp $FF
        ret z
        call SLOTPTR
        ld (CURSL),hl
        push hl
        pop iy
        ret

; A = ranura libre (1..) o $FF
FREESLOT:
        ld a,1
.lp:    cp NSLOTS
        jr nc,.none
        push af
        call SLOTPTR
        ld a,(hl)
        or a
        jr z,.got
        pop af
        inc a
        jr .lp
.got:   pop af
        ret
.none:  ld a,$FF
        ret

; Ejecuta la ranura en marcha hasta que suelte (o 20000 instrucciones)
EXECUTE:
        ld hl,0
        ld (EXECN),hl
.lp:    ld a,(CURSLOT)
        cp $FF
        ret z
        ld iy,(CURSL)
        ld l,(iy+SL_PC)
        ld h,(iy+SL_PC+1)
        ld e,(iy+SL_LEN)
        ld d,(iy+SL_LEN+1)
        call CPU16
        jr c,.ok
        call STOPCODE
        jr .lp
.ok:    ld (VMSTART),hl
        call VMFETCH
        ld (VMOP),a
        call DISPATCH
        ld hl,(EXECN)
        inc hl
        ld (EXECN),hl
        ld de,20000
        call CPU16
        jr c,.lp
        ld a,(CURSLOT)
        cp $FF
        jr z,.lp
        call STOPCODE
        jr .lp

; Llama al manejador de la instruccion VMOP (con -DVMTRACE, la apunta en la traza
; de $3D00: para buscar fallos en el emulador; cuesta tiempo en cada instruccion)
TRACEP  EQU $3D00
TRACEB  EQU $3D02
TRACEN  EQU 25
TRACESZ EQU 7
; detras de la traza (solo datos: la DivMMC salta si se lee codigo por $3Dxx)
DIRTY   EQU TRACEB+TRACESZ*TRACEN   ; tiras apuntadas en este paso, una por bit (128)
DIRTYF  EQU DIRTY+16                ; alguna
STALE   EQU DIRTYF+1                ; tiras con los pixeles atrasados (fuera de la vista)
TICKV   EQU STALE+16                ; imagenes por paso (modo normal, VMTICK)
DELTAV  EQU TICKV+1                 ; jiffies por paso (2 bytes: el alto, 0)
VMIN    EQU DELTAV+2                ; filas de la pantalla de verbos pintadas en B en
VMAX    EQU VMIN+1                  ; este paso (VFLUSH las pasa a la vista)
VDIRECT EQU VMAX+1                  ; 1: los verbos, directamente en la que se ve (menu)
RCY0    EQU VDIRECT+3               ; filas que rehace RECOMPOSER: [RCY0, RCY1)
RCY1    EQU RCY0+1
RCALL   EQU RCY1+1                  ; (APPLY) columnas opacas en todas las filas
ZOBTOP  EQU RCALL+1                 ; los objetos de la habitacion que van encima (los de
                                    ; drawObject, la cola de dibujo de SCUMM): un bit cada uno
ZTOPN   EQU ZOBTOP+32               ; cuantos
RCPASS  EQU ZTOPN+1                 ; (RECOMPOSER) 0: los demas; 1: los de encima
        ASSERT RCPASS < $3E00, la traza no cabe
        ASSERT (ZOBTOP & $FF) + 31 <= $FF
DISPATCH:
        IFDEF VMTRACE
        ld hl,(TRACEP)
        ld de,TRACEB
        call CPU16
        jr c,.t0
        ld de,TRACEB+TRACESZ*TRACEN
        call CPU16
        jr c,.t1
.t0:    ld hl,TRACEB
.t1:    ld a,(VMOP)
        ld (hl),a
        inc hl
        ld de,(VMSTART)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld a,(iy+SL_NUM)
        ld (hl),a
        inc hl
        ld a,(CURSLOT)
        ld (hl),a
        inc hl
        ex de,hl
        ld hl,0
        add hl,sp
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (TRACEP),hl
        ENDIF
        ld a,(VMOP)
        ld l,a
        ld h,0
        add hl,hl
        ld de,VMTAB
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

; stopObjectCode
STOPCODE:
        ld a,(CURSLOT)
        cp $FF
        ret z
        ld iy,(CURSL)
        xor a
        ld (iy+SL_ST),a
        ld (iy+SL_NUM),a
        ld (iy+SL_NUM+1),a
        ld a,$FF
        ld (CURSLOT),a
        ret

; Todas las ranuras en marcha, una vez
RUNALL:
        ld a,$FF
        ld (CURSLOT),a
        xor a
.lp:    push af
        call SLOTPTR
        ld a,(hl)
        cp SS_RUNNING
        jr nz,.next
        pop af
        push af
        call SETCUR
        call EXECUTE
.next:  pop af
        inc a
        cp NSLOTS
        jr nz,.lp
        ld a,$FF
        ld (CURSLOT),a
        ret

; Ejecuta la ranura A anidada y vuelve a la que la llamo si sigue viva
RUNNESTED:
        ld c,a
        ld a,(NESTN)
        cp MAXNEST
        ret nc
        ld l,a                      ; NEST + 4 * NESTN
        ld h,0
        add hl,hl
        add hl,hl
        ld de,NEST
        add hl,de
        ld a,(CURSLOT)
        cp $FF
        jr nz,.cur
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ld (hl),$FF
        inc hl
        ld (hl),$FF
        jr .push
.cur:   ld iy,(CURSL)
        ld a,(iy+SL_NUM)
        ld (hl),a
        inc hl
        ld a,(iy+SL_NUM+1)
        ld (hl),a
        inc hl
        ld a,(iy+SL_WH)
        ld (hl),a
        inc hl
        ld a,(CURSLOT)
        ld (hl),a
.push:  ld hl,NESTN
        inc (hl)
        ld a,c
        call SETCUR
        ld hl,(EXECN)
        push hl
        ld a,(SHMMU6)               ; MMU6 como estaba: el script puede cambiar de
        push af                     ; habitacion (LOADROOM y FLUSHOBJ dejan otra
        call EXECUTE                ; pagina) y quien lo llamo puede estar en una capa
        pop af
        ld (SHMMU6),a
        nextreg $56,a
        pop hl
        ld (EXECN),hl
        ld hl,NESTN
        dec (hl)
        ld l,(hl)                   ; la entrada que se guardo
        ld h,0
        add hl,hl
        add hl,hl
        ld de,NEST
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr z,.none
        ld a,d                      ; $FF: la anularon
        or a
        jr nz,.chk
        ld a,e
        cp $FF
        jr z,.none
.chk:   ld b,(hl)                   ; donde
        inc hl
        ld a,(hl)                   ; ranura
        ld (NRSL),a
        push de
        call SLOTPTR
        push hl
        pop iy
        pop de
        ld a,(iy+SL_NUM)
        cp e
        jr nz,.none
        ld a,(iy+SL_NUM+1)
        cp d
        jr nz,.none
        ld a,(iy+SL_WH)
        cp b
        jr nz,.none
        ld a,(iy+SL_ST)
        or a
        jr z,.none
        ld a,(iy+SL_FCNT)
        or a
        jr nz,.none
        ld a,(NRSL)
        jp SETCUR
.none:  ld a,$FF
        ld (CURSLOT),a
        ret

; Arranca una ranura con SSNUM, SSWH, SSKIND, SSBASE, SSPC, SSLEN, SSFRES,
; SSREC y los argumentos ARGS/ARGN, y la ejecuta anidada
STARTSLOT:
        call FREESLOT
        cp $FF
        ret z
        ld (SSI),a
        call SLOTPTR
        push hl
        pop ix                      ; (IX: solo aqui)
        ld (ix+SL_ST),SS_RUNNING
        ld a,(SSWH)
        ld (ix+SL_WH),a
        ld hl,(SSNUM)
        ld (ix+SL_NUM),l
        ld (ix+SL_NUM+1),h
        ld hl,(SSBASE)
        ld (ix+SL_BASE),l
        ld (ix+SL_BASE+1),h
        ld a,(SSBASE+2)
        ld (ix+SL_BASE+2),a
        ld a,(SSKIND)
        ld (ix+SL_KIND),a
        ld hl,(SSPC)
        ld (ix+SL_PC),l
        ld (ix+SL_PC+1),h
        ld hl,FPTR+1
        ld (hl),0
        ld hl,(SSLEN)
        ld (ix+SL_LEN),l
        ld (ix+SL_LEN+1),h
        ld a,(SSFRES)
        ld (ix+SL_FRES),a
        ld a,(SSREC)
        ld (ix+SL_REC),a
        xor a
        ld (ix+SL_FCNT),a
        ld (ix+SL_CSO),a
        ld (ix+SL_DLY),a
        ld (ix+SL_DLY+1),a
        ld (ix+SL_DLY+2),a
        push ix                     ; locales: los argumentos y ceros
        pop hl
        ld de,SL_LOC
        add hl,de
        push hl
        ld (hl),0
        ld d,h
        ld e,l
        inc de
        ld bc,2*NLOCALS-1
        ldir
        pop de
        ld a,(ARGN)
        or a
        jr z,.run
        add a,a
        ld c,a
        ld b,0
        ld hl,ARGS
        ldir
.run:   ld ix,ACTOR
        ld a,(SSI)
        jp RUNNESTED

; runScript(A = script) con SSFRES, SSREC y ARGS
RUNSCRIPT:
        or a
        ret z
        ld (RSN),a
        ld a,(SSREC)
        or a
        jr nz,.go
        ld a,(RSN)
        ld l,a
        ld h,0
        call STOPSCRIPT
.go:    ld a,(RSN)
        ld l,a
        ld h,0
        ld (SSNUM),hl
        cp NUMGLOBAL
        jr nc,.local
        ; global: indice en SCRIPTS.DAT (5 bytes por script)
        ld e,a
        ld d,5
        mul d,e
        ex de,hl
        xor a
        ld (SSKIND),a
        call GREAD3                 ; A:HL = posicion, DE = longitud
        cp $FF
        ret z
        ld (SSBASE),hl
        ld (SSBASE+2),a
        ld (SSLEN),de
        ld a,WIO_GLOBAL
        jr .start
.local: call LOCALSCR
        ret nc
        ld a,1
        ld (SSKIND),a
        ld a,WIO_LOCAL
.start: ld (SSWH),a
        ld hl,0
        ld (SSPC),hl
        jp STARTSLOT

; Indice de scripts globales: HL = posicion (< 8K) -> A:HL = posicion lineal,
; DE = longitud (A = $FF si no esta: las posiciones de verdad son < 128 KB)
GREAD3:
        ld a,(SPAGES)
        call MAP7
        ld a,h
        or $E0
        ld h,a
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ex de,hl
        ld d,b
        ld e,c
        ret


; Script local RSN en la habitacion: SSBASE, SSLEN; carry si esta
LOCALSCR:
        ld a,(CURROOM)
        or a
        ret z
        ld a,(META+586)
        or a
        ret z
        ld b,a
        ld hl,(META+587)
        ld de,META
        add hl,de
.lp:    ld a,(RSN)
        cp (hl)
        jr z,.got
        ld de,6
        add hl,de
        djnz .lp
        or a
        ret
.got:   inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld (SSBASE),de
        ld (SSBASE+2),a
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (SSLEN),de
        scf
        ret

; stopScript(HL)
STOPSCRIPT:
        ld a,h
        or l
        ret z
        ld (STN),hl
        ld c,WIO_GLOBAL
        ld b,WIO_LOCAL
        jr STOPWHERE
; stopObjectScript(HL)
STOPOBJSCR:
        ld a,h
        or l
        ret z
        ld (STN),hl
        ld c,WIO_ROOM
        ld b,WIO_INVENTORY
; Para las ranuras con numero STN y donde C o B, y anula su entrada en NEST
STOPWHERE:
        ld a,b
        ld (STW2),a
        ld a,c
        ld (STW1),a
        xor a
.lp:    push af
        call SLOTPTR
        push hl
        pop ix
        ld a,(ix+SL_ST)
        or a
        jr z,.next
        call STMATCH
        jr nz,.next
        xor a
        ld (ix+SL_ST),a
        ld (ix+SL_NUM),a
        ld (ix+SL_NUM+1),a
        pop af
        push af
        ld hl,CURSLOT
        cp (hl)
        jr nz,.next
        ld (hl),$FF
.next:  pop af
        inc a
        cp NSLOTS
        jr nz,.lp
        ld a,(NESTN)
        or a
        jr z,.done
        ld b,a
        ld ix,NEST
.nl:    call STMATCH
        jr nz,.nn
        ld (ix+0),$FF
        ld (ix+1),0
        ld (ix+2),$FF
        ld (ix+3),$FF
.nn:    inc ix
        inc ix
        inc ix
        inc ix
        djnz .nl
.done:  ld ix,ACTOR
        ret
; Z si (ix+0..1) == STN y (ix+SL_WH o ix+2) es STW1 o STW2.
; (Las ranuras tienen numero en +2 y donde en +1; NEST, numero en +0 y donde en +2.)
STMATCH:
        push ix
        pop hl
        ld de,SLOTS
        or a
        sbc hl,de
        jr c,.nest
        ld de,NSLOTS*SLOTSZ
        call CPU16
        jr nc,.nest
        ld e,(ix+SL_NUM)
        ld d,(ix+SL_NUM+1)
        ld a,(ix+SL_WH)
        jr .cmp
.nest:  ld e,(ix+0)
        ld d,(ix+1)
        ld a,(ix+2)
.cmp:   ld hl,STW1
        cp (hl)
        jr z,.w
        ld hl,STW2
        cp (hl)
        ret nz
.w:     ld hl,(STN)
        or a
        sbc hl,de
        ret

; Mata los scripts de la habitacion (los de objetos y los locales)
KILLROOM:
        xor a
.lp:    push af
        call SLOTPTR
        push hl
        pop ix
        ld a,(ix+SL_ST)
        or a
        jr z,.next
        ld a,(ix+SL_WH)
        cp WIO_ROOM
        jr z,.kill
        cp WIO_LOCAL
        jr nz,.next
.kill:  xor a
        ld (ix+SL_CSO),a
        ld (ix+SL_ST),a
        ld (ix+SL_NUM),a
        ld (ix+SL_NUM+1),a
.next:  pop af
        inc a
        cp NSLOTS
        jr nz,.lp
        ld ix,ACTOR
        ret

; Scripts de salida y de entrada de la habitacion
RUNEXIT:
        ld hl,(VARS+2*VAR_EXIT_SCRIPT)
        call RUNVARSCR
        ld hl,META+581
        ld de,ROOM_EXIT
        call ROOMSCR
        ld hl,(VARS+2*VAR_EXIT_SCRIPT2)
        jr RUNVARSCR
RUNENTRY:
        ld hl,(VARS+2*VAR_ENTRY_SCRIPT)
        call RUNVARSCR
        ld hl,META+576
        ld de,ROOM_ENTRY
        call ROOMSCR
        ld hl,(VARS+2*VAR_ENTRY_SCRIPT2)
; runScript(HL) sin argumentos si no es 0
RUNVARSCR:
        ld a,h
        or l
        ret z
        xor a
        ld (ARGN),a
        ld (SSFRES),a
        ld (SSREC),a
        ld a,l
        jp RUNSCRIPT
; El script de la habitacion en (HL) (posicion y longitud) con numero DE
ROOMSCR:
        ld a,(CURROOM)
        or a
        ret z
        ld (SSNUM),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        cp $FF
        jr nz,.ok
        ld b,a
        ld a,d
        and e
        inc a
        ld a,b
        ret z
.ok:    ld (SSBASE),de
        ld (SSBASE+2),a
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (SSLEN),de
        xor a
        ld (ARGN),a
        ld (SSFRES),a
        ld (SSREC),a
        ld hl,0
        ld (SSPC),hl
        ld a,1
        ld (SSKIND),a
        ld a,WIO_ROOM
        ld (SSWH),a
        jp STARTSLOT

; startObject: objeto HL, verbo A, argumentos ARGS (en la capa OVU)
RUNOBJSCR:
        ld (ROV),a
        ld (ROO),hl
        ld hl,U_RUNOBJ
        ld a,OVU_PAGE
        jp OVCALL
; IY = la ranura en marcha (si hay)
RESTOREIY:
        ld a,(CURSLOT)
        cp $FF
        ret z
        ld iy,(CURSL)
        ret

; Congela los demas scripts (HL = bandera; los resistentes solo con >= $80)
FREEZE:
        ld (FRF16),hl
        xor a
.lp:    push af
        ld hl,CURSLOT
        cp (hl)
        jr z,.next
        call SLOTPTR
        push hl
        pop ix
        ld a,(ix+SL_ST)
        or a
        jr z,.next
        ld a,(ix+SL_FRES)
        or a
        jr z,.fr
        ld a,(FRF16+1)              ; resistente: solo con bandera >= $80
        bit 7,a
        jr nz,.next
        or a
        jr nz,.fr
        ld a,(FRF16)
        cp $80
        jr c,.next
.fr:    set 7,(ix+SL_ST)
        inc (ix+SL_FCNT)
.next:  pop af
        inc a
        cp NSLOTS
        jr nz,.lp
        ld a,(CSIDX)
        cp $FF
        jr z,.done
        call SLOTPTR
        push hl
        pop ix
        res 7,(ix+SL_ST)
        ld (ix+SL_FCNT),0
.done:  ld ix,ACTOR
        ret
UNFREEZE:
        xor a
.lp:    push af
        call SLOTPTR
        push hl
        pop ix
        bit 7,(ix+SL_ST)
        jr z,.next
        dec (ix+SL_FCNT)
        jr nz,.next
        res 7,(ix+SL_ST)
.next:  pop af
        inc a
        cp NSLOTS
        jr nz,.lp
        ld ix,ACTOR
        ret

; --- cada paso -------------------------------------------------------------
VMTICK:
        ld hl,SN_TICK               ; relojes y esperas (capa OVA)
        ld a,OVA_PAGE
        call OVCALL
        ld ix,ACTOR
        ret

; --- objetos -----------------------------------------------------------------
; A = estado del objeto HL (0 si no existe)
GETSTATE:
        call OBJOK
        ld a,0
        ret nc
        ld de,OBJST
        add hl,de
        ld a,(hl)
        ret
; carry si 0 <= HL < NOBJG
OBJOK:
        bit 7,h
        ret nz
        push de
        ld de,(NOBJG)
        call CPS16
        pop de
        ret
; estado A para el objeto HL (y se rehace si esta en la habitacion)
PUTSTATE:
        ld c,a
        call OBJOK
        ret nc
        push hl
        ld de,OBJST
        add hl,de
        ld a,(hl)
        ld (hl),c
        pop hl
        cp c                        ; el mismo de antes: se ve igual (drawObject los pone
        ret z                       ; una y otra vez), nada que rehacer
PSREDRAW:                           ; (el objeto HL se rehace si esta en la habitacion)
        ld a,(CURROOM)
        or a
        ret z
        call OBJINDEX
        cp $FF
        ret z
        call REDRAWOBJ
        ld ix,ACTOR
        jp RESTOREIY

; A = dueno del objeto HL
GETOWNER:
        call OBJOK
        ld a,0
        ret nc
        ld de,OBJOWN
        add hl,de
        ld a,(hl)
        ret
PUTOWNER:
        ld c,a
        call OBJOK
        ret nc
        ld de,OBJOWN
        add hl,de
        ld (hl),c
        ret

; Clases: 4 bytes por objeto en CLASS_PAGE (por $E000)
; HL = objeto, A = clase -> HL = byte, A = mascara; nc si no vale
CLASSADDR:
        and $7F
        jr z,.no
        cp 33
        jr nc,.no
        dec a
        ld c,a
        call OBJOK
        ret nc
        add hl,hl
        add hl,hl
        ld a,c
        rrca
        rrca
        rrca
        and 3
        add hl,a
        ld de,$E000
        add hl,de
        ld a,CLASS_PAGE
        call MAP7
        ld a,c
        and 7
        ld de,BITMASKS
        add a,e
        ld e,a
        adc a,d
        sub e
        ld d,a
        ld a,(de)
        scf
        ret
.no:    or a
        ret
; A = 1 si el objeto HL tiene la clase A
GETCLASS:
        call CLASSADDR
        jr nc,.z
        and (hl)
        ret z
        ld a,1
        ret
.z:     xor a
        ret
; clase A del objeto HL: activa si B != 0
PUTCLASS:
        push bc
        call CLASSADDR
        pop bc
        ret nc
        ld c,a
        ld a,b
        or a
        ld a,c
        jr z,.clr
        or (hl)
        ld (hl),a
        ret
.clr:   cpl
        and (hl)
        ld (hl),a
        ret
; todas las clases del objeto HL a 0
CLRCLASSES:
        call OBJOK
        ret nc
        add hl,hl
        add hl,hl
        ld de,$E000
        add hl,de
        ld a,CLASS_PAGE
        call MAP7
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ret

; textos: duran 60 jiffies + 3 por byte
SAY:
        ld hl,(STRLEN)
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,60
        add hl,de
        ld (TALKDLY),hl
        ld hl,$FF
        ld (VARS+2*VAR_HAVE_MSG),hl
        ret

; A = 1 si el script HL esta en marcha (global o local)
RUNNING:
        ld (STN),hl
        ld a,WIO_GLOBAL
        ld (STW1),a
        ld a,WIO_LOCAL
        ld (STW2),a
        xor a
.lp:    push af
        call SLOTPTR
        push hl
        pop ix
        ld a,(ix+SL_ST)
        or a
        jr z,.next
        call STMATCH
        jr nz,.next
        pop af
        ld ix,ACTOR
        ld a,1
        ret
.next:  pop af
        inc a
        cp NSLOTS
        jr nz,.lp
        ld ix,ACTOR
        xor a
        ret

; loadRoom desde un script: si el script es de la habitacion, muere
CHANGEROOM:
        ld (CRR),a
        ld a,(CURSLOT)
        cp $FF
        jr z,.sv
        ld iy,(CURSL)
        ld a,(iy+SL_WH)
        cp WIO_ROOM
        jr z,.kill
        cp WIO_LOCAL
        jr nz,.sv
.kill:  ld a,$FF
        ld (CURSLOT),a
.sv:    ld a,(CURSLOT)
        ld (CRSAVED),a
        ld a,(CRR)
        call STARTSCENE
        ld a,(CRSAVED)
        cp $FF
        jr z,.none
        call SLOTPTR
        ld a,(hl)
        or a
        jr z,.none
        ld a,(CRSAVED)
        jp SETCUR
.none:  ld a,$FF
        ld (CURSLOT),a
        ret

        INCLUDE "vmops.asm"
