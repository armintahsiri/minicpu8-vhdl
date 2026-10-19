; pc_wrap.asm -- forward PC wrap at the top of the address space.
; jmp to 0xFD, then a taken BEQ at 0xFE computes (0xFF + 2) mod 256 = 0x01.
; Addresses 0x03..0xFC are NOP-filled by .org; 0xFF is HALT.
; Expected: r1=1, r2=31, pc=0x02.

        jmp   0xFD
        loadi r2, 31       ; 0x01: landing point after the wrap
        halt               ; 0x02
        .org  0xFD
        loadi r1, 1        ; 0xFD
        beq   r0, r0, 2    ; 0xFE: PC+1+2 = 0x01 (mod 256)
        halt               ; 0xFF
