; shift_branch.asm -- exercises SHL/SHR/XOR, BEQ taken (skipping an
; instruction), LOADI of a negative constant, and flag behavior.
; Expected final state: r2=12 r3=6 r4=10 r5=13 r6=0, flags ZNCV=0000.

        loadi r1, 3        ; r1 = 3
        shl   r2, r1       ; r2 = 6
        shl   r2, r2       ; r2 = 12
        shr   r3, r2       ; r3 = 6
        xor   r4, r2, r3   ; r4 = 12 ^ 6 = 10
        add   r5, r4, r1   ; r5 = 13, flags ZNCV = 0000
        loadi r6, 0        ; r6 = 0 (must stay 0: the loadi below is skipped)
        beq   r5, r5, skip ; always taken: r5 == r5
        loadi r6, -1       ; skipped (would set r6 = 0xFF)
skip:   halt
