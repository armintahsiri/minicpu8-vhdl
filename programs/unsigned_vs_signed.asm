; unsigned_vs_signed.asm -- the same bits compare differently as unsigned
; and signed.  0xFE is 254 unsigned and -2 signed, vs 0x01.
;   BLO: 254 < 1  -> false (not taken)
;   BHS: 254 >= 1 -> true
;   BLT: -2 < 1   -> true
;   BGE: -2 >= 1  -> false
; Expected: r3=2 (unsigned >=), r4=3 (signed <).

        loadi r1, -2       ; 0xFE
        loadi r2, 1

        cmp   r1, r2
        blo   unsigned_less
        bhs   unsigned_ge
        loadi r3, 0
        jmp   signed_part
unsigned_less:
        loadi r3, 1
        jmp   signed_part
unsigned_ge:
        loadi r3, 2

signed_part:
        cmp   r1, r2
        blt   signed_less
        bge   signed_ge
        loadi r4, 0
        jmp   done
signed_less:
        loadi r4, 3
        jmp   done
signed_ge:
        loadi r4, 4
done:   halt
