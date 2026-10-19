; hello.asm : print a fixed string over the UART (Phase 3 demo)
; The string lives in data RAM (0..17); each byte is loaded and sent with a
; polling loop on UART_STATUS (bit0 = tx_busy). LOAD does not modify flags,
; so the status byte is explicitly CMP'ed against R0 before BNZ.
        .data 0, 72, 101, 108, 108, 111, 44, 32, 77, 105, 110, 105, 67, 80, 85, 45, 56, 33, 10

        loadi r1, 0                 ; string pointer
        loadi r2, 18                ; string length
        loadi r5, UART_STATUS
        loadi r6, UART_TX
loop:   load  r3, [r1+0]            ; next character
wait:   load  r4, [r5+0]            ; tx_busy?
        cmp   r4, r0
        bnz   wait
        store r3, [r6+0]            ; transmit character
        addi  r1, r1, 1
        bne   r1, r2, loop          ; BEQ/BNE compare two registers
wait2:  load  r4, [r5+0]            ; wait for the last byte to finish
        cmp   r4, r0
        bnz   wait2
        halt
