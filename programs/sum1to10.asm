; sum1to10.asm -- compute r1 = 1 + 2 + ... + 10 = 55, then halt
; (assembled into sum1to10_rom.vhd by tools/assembler.py)
; Uses ADDI for the loop increment (ISA v2).

        loadi r1, 0        ; r1 = sum = 0
        loadi r2, 1        ; r2 = i = 1
        loadi r3, 11       ; r3 = loop exit value (loop while i != 11)
loop:   add   r1, r1, r2   ; sum += i
        addi  r2, r2, 1    ; i++
        bne   r2, r3, loop ; until i == 11
        halt
