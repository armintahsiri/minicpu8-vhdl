; Hardware bring-up: GPIO counter plus a periodic three-byte UART heartbeat.
.data 16, 79, 75, 10
main:
        loadi r1, GPIO_OUT
        loadi r2, UART_TX
        loadi r3, 0
        loadi r4, 16
        loadi r5, UART_STATUS
        loadi r6, 16

loop:
        store r3, [r1+0]
        addi r3, r3, 1
        subi r4, r4, 1
        bnz loop
        loadi r4, 16

        load r7, [r6+0]
        store r7, [r2+0]      ; O
poll_o:
        load r7, [r5+0]
        cmp r7, r0
        bnz poll_o

        load r7, [r6+1]
        store r7, [r2+0]      ; K
poll_k:
        load r7, [r5+0]
        cmp r7, r0
        bnz poll_k

        load r7, [r6+2]
        store r7, [r2+0]      ; newline
poll_n:
        load r7, [r5+0]
        cmp r7, r0
        bnz poll_n
        jmp loop
