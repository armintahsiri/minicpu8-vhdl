; call_ret.asm -- CALL/RET subroutine called twice, plus a nested call that
; saves/restores R7 in data RAM (there is no hardware stack).
;   mul   : shift-and-add 8-bit multiply (r3 = r1 * r2)
;   square: calls mul(r1, r1); saves its own link in RAM[20]
; Expected: RAM[16]=15, RAM[17]=42, RAM[18]=81, RAM[20]=10, r7=10.

main:   loadi r1, 3
        loadi r2, 5
        call  mul          ; 3 * 5 = 15
        store r3, [r0+16]
        loadi r1, 7
        loadi r2, 6
        call  mul          ; 7 * 6 = 42
        store r3, [r0+17]
        loadi r1, 9
        call  square       ; 9 * 9 = 81 (nested CALL)
        store r3, [r0+18]
        halt

mul:    loadi r3, 0
        loadi r4, 8        ; 8 bits
        loadi r6, 1        ; bit mask
mulloop:and   r5, r2, r6
        bz    noadd
        add   r3, r3, r1
noadd:  shl   r1, r1
        shr   r2, r2
        subi  r4, r4, 1
        bnz   mulloop
        ret

square: store r7, [r0+20]  ; save the caller's link (R7)
        mov   r2, r1       ; b = a
        call  mul          ; overwrites R7 with the return address in square
        load  r6, [r0+20]  ; restore the saved link
        mov   r7, r6
        ret
