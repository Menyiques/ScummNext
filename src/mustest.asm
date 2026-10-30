; ===========================================================================
;  Prueba de la musica al cargar habitaciones (tools/mustest.py: se ensambla con
;  -DMTBUILD y se mira en CSpect, que emula las interrupciones del CTC): la pista 2
;  del juego de prueba en bucle y 12 habitaciones cargadas seguidas (blanco al
;  empezar, azul mientras carga, cian despues de cada una, sin ver la habitacion);
;  en cada imagen se cuentan las muestras que han sonado. Al final la pantalla se
;  queda de un color: verde si siempre sonaron (mas de 100 por imagen), rojo si
;  no, amarillo si el anillo se quedo vacio. Despues de las cargas, 100 imagenes
;  rehaciendo todas las tiras (FLUSHOBJ). Con -DMTDI, FLUSHOBJ va sin
;  interrupciones, como antes (debe salir rojo).
; ===========================================================================
; (MUSTEST y MTWAIT estan en mtpage.asm, en la pagina MT_PAGE)

; (desde la interrupcion de linea) las muestras de esta imagen
MTFRAME:
        ld a,(MTON)
        or a
        ret z
        ld hl,(MTCNT)
        ld de,(MTLAST)
        ld (MTLAST),hl
        or a
        sbc hl,de
        ld de,100
        or a
        sbc hl,de
        ret nc
        ld hl,(MTSTALL)
        inc hl
        ld (MTSTALL),hl
        ret

MTON:   db 0
MTSN:   dw 0                        ; (-DMTSFX) muestras de los efectos: canal 1 (CTC 0)
MTSN2:  dw 0                        ; y canal 2 (CTC 2)
MTCNT:  dw 0
MTLAST: dw 0
MTSTALL: dw 0
