; ===========================================================================
;  Medidas (solo con -DPROF), por muestreo: PMARK n apunta en PCUR por donde va
;  el programa y la interrupcion de linea (50 por segundo) suma 1 en PSAMP[PCUR].
;  PSAMP[n] = imagenes que se han pasado despues de la marca n (16 de 16 bits).
;  Ademas, por si acaso: rachas del RLE, pixeles pintados sin escala, tramos y
;  bytes de lienzo borrados (32 bits).
; ===========================================================================
; (desde la interrupcion de linea)
PSAMPLE:
        ld a,(PCUR)
        add a,a
        ld hl,PSAMP
        add hl,a
        inc (hl)
        ret nz
        inc hl
        inc (hl)
        ret

PCUR:   db 0
PSAMP:  ds 32
PACT:   ds 4
PSTEPS: ds 4
