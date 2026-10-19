; fibonacci.asm : print the Fibonacci numbers that fit in 8 bits as decimal
; Output: "0 1 1 2 3 5 8 13 21 34 55 89 144 233\n"
;
; print_u8 (R1 -> decimal text, no leading zeros) calls putc, so it must save
; and restore the single-level R7 link in RAM[5] (the documented convention).
; putc polls UART_STATUS, then writes R6 to UART_TX.
;
; RAM map:
;   0 space, 1 newline, 2 a, 3 b, 5 saved R7, 6 printed-flag,
;   8 ASCII '0', 9 constant 100
        .data 0, 32, 10, 0, 1, 0, 0, 0, 0, 48, 100

main:
        load  r1, [r0+2]            ; F0 = 0
        call  print_u8
        load  r6, [r0+0]            ; space
        call  putc
loop:   load  r1, [r0+3]            ; print b (1,1,2,...)
        call  print_u8
        load  r6, [r0+0]            ; space
        call  putc
        load  r1, [r0+2]            ; a
        load  r2, [r0+3]            ; b
        add   r3, r1, r2            ; next = a + b
        bcs   done                  ; next does not fit in 8 bits
        store r2, [r0+2]            ; a = b
        store r3, [r0+3]            ; b = next
        jmp   loop
done:   load  r6, [r0+1]            ; newline
        call  putc
wait:   load  r4, [r0+UART_STATUS]  ; wait for the final byte
        cmp   r4, r0
        bnz   wait
        halt

; ---------------------------------------------------------------------------
; print_u8: print R1 (0..255) as unsigned decimal without leading zeros.
; Clobbers R1,R2,R3,R5,R6; preserves R7 via RAM[5]. R4 is clobbered by putc.
; Uses unsigned comparisons (BCC) because values above 127 are "negative"
; in a signed BLT comparison.
; ---------------------------------------------------------------------------
print_u8:
        store r7, [r0+5]            ; save caller link
        loadi r6, 0
        store r6, [r0+6]            ; no digit printed yet
        load  r2, [r0+9]            ; 100
        loadi r3, 0
h_loop: cmp   r1, r2
        bcc   h_end
        sub   r1, r1, r2
        addi  r3, r3, 1
        jmp   h_loop
h_end:  cmp   r3, r0
        bz    tens
        load  r5, [r0+8]            ; '0'
        add   r3, r3, r5
        mov   r6, r3
        call  putc
        loadi r6, 1
        store r6, [r0+6]            ; a leading digit was printed
tens:   loadi r2, 10
        loadi r3, 0
t_loop: cmp   r1, r2
        bcc   t_end
        sub   r1, r1, r2
        addi  r3, r3, 1
        jmp   t_loop
t_end:  load  r6, [r0+6]
        cmp   r6, r0
        bnz   print_tens            ; print tens after a hundreds digit
        cmp   r3, r0
        bz    units                 ; suppress a leading zero
print_tens:
        load  r5, [r0+8]
        add   r3, r3, r5
        mov   r6, r3
        call  putc
        loadi r6, 1
        store r6, [r0+6]
units:  load  r5, [r0+8]
        add   r1, r1, r5
        mov   r6, r1
        call  putc
        load  r7, [r0+5]            ; restore caller link
        ret

; ---------------------------------------------------------------------------
; putc: send R6 over the UART, polling for a free transmitter first.
; Clobbers R4 only; does not touch R7.
; ---------------------------------------------------------------------------
putc:
putc_wait:
        load  r4, [r0+UART_STATUS]
        cmp   r4, r0
        bnz   putc_wait
        store r6, [r0+UART_TX]
        ret
