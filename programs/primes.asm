; primes.asm : print every prime below 256 as decimal
; Output: "2 3 5 7 11 ... 251\n" (54 primes).
;
; Trial division by every d from 2 up to n-1. Divisibility is tested with
; repeated subtraction (there is no DIV instruction); values are unsigned, so
; the loops use BCC/BCS rather than signed BLT. print_u8/putc are the same
; CALL/RET routines used by fibonacci.asm; print_u8 saves R7 in RAM[5].
;
; RAM map: 0 space, 1 newline, 2 n, 3 d, 5 saved R7, 6 printed-flag,
;          8 ASCII '0', 9 constant 100
        .data 0, 32, 10, 2, 0, 0, 0, 0, 0, 48, 100

main:
next_n: load  r1, [r0+2]            ; n
        loadi r2, 2
        store r2, [r0+3]            ; d = 2
test_d: load  r2, [r0+3]            ; d
        load  r1, [r0+2]            ; n
        cmp   r2, r1
        bcs   prime                 ; d >= n: no divisor found
        ; remainder = n; subtract d until remainder < d
        load  r4, [r0+2]
mod_loop:
        cmp   r4, r2
        bcc   mod_done
        sub   r4, r4, r2
        jmp   mod_loop
mod_done:
        cmp   r4, r0
        bz    not_prime             ; n divisible by d
        addi  r2, r2, 1             ; try the next divisor
        store r2, [r0+3]
        jmp   test_d
prime:  load  r1, [r0+2]
        call  print_u8
        load  r6, [r0+0]            ; space
        call  putc
not_prime:
        load  r1, [r0+2]
        addi  r1, r1, 1
        bcs   done                  ; 255 + 1 wrapped: all n processed
        store r1, [r0+2]
        jmp   next_n
done:   load  r6, [r0+1]            ; newline
        call  putc
wait:   load  r4, [r0+UART_STATUS]
        cmp   r4, r0
        bnz   wait
        halt

; ---------------------------------------------------------------------------
; print_u8: print R1 (0..255) as unsigned decimal without leading zeros.
; Clobbers R1,R2,R3,R5,R6; preserves R7 via RAM[5].
; ---------------------------------------------------------------------------
print_u8:
        store r7, [r0+5]
        loadi r6, 0
        store r6, [r0+6]
        load  r2, [r0+9]            ; 100
        loadi r3, 0
h_loop: cmp   r1, r2
        bcc   h_end
        sub   r1, r1, r2
        addi  r3, r3, 1
        jmp   h_loop
h_end:  cmp   r3, r0
        bz    tens
        load  r5, [r0+8]
        add   r3, r3, r5
        mov   r6, r3
        call  putc
        loadi r6, 1
        store r6, [r0+6]
tens:   loadi r2, 10
        loadi r3, 0
t_loop: cmp   r1, r2
        bcc   t_end
        sub   r1, r1, r2
        addi  r3, r3, 1
        jmp   t_loop
t_end:  load  r6, [r0+6]
        cmp   r6, r0
        bnz   print_tens
        cmp   r3, r0
        bz    units
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
        load  r7, [r0+5]
        ret

; ---------------------------------------------------------------------------
; putc: poll UART_STATUS, then send R6 to UART_TX. Clobbers R4 only.
; ---------------------------------------------------------------------------
putc:
putc_wait:
        load  r4, [r0+UART_STATUS]
        cmp   r4, r0
        bnz   putc_wait
        store r6, [r0+UART_TX]
        ret
