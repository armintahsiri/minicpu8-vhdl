; find_max.asm -- signed maximum of an array containing negative numbers.
; Uses CMP + BLT (signed less-than). Data at RAM[16..20], result in RAM[21].
; Expected: r1=127, r2=21, RAM[21]=127.

        .data 16, -5, -20, -3, -100, 127

        loadi r2, 16       ; r2 = pointer
        loadi r3, 5        ; r3 = count
        load  r1, [r2+0]   ; max = array[0] = -5
        addi  r2, r2, 1
        subi  r3, r3, 1
loop:   load  r5, [r2+0]   ; r5 = next value
        cmp   r5, r1       ; compare value with max
        blt   skip         ; if value < max (signed), keep max
        mov   r1, r5       ; max = value (MOV is ADD rd,rs,r0)
skip:   addi  r2, r2, 1
        subi  r3, r3, 1
        bnz   loop
        store r1, [r2+0]   ; RAM[21] = 127
        halt
