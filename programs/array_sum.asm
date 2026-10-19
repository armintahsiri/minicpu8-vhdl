; array_sum.asm -- sum an array initialized in data RAM, then store the sum.
; Data lives at RAM[16..25]; the result is written to RAM[26].
; Expected: r1=55, r2=26, r3=0, RAM[26]=55.

        .data 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

        loadi r2, 16       ; r2 = pointer = &array[0]
        loadi r3, 10       ; r3 = count
        loadi r1, 0        ; r1 = sum
loop:   load  r5, [r2+0]   ; r5 = *r2
        add   r1, r1, r5   ; sum += *r2
        addi  r2, r2, 1    ; r2++
        subi  r3, r3, 1    ; r3--
        bnz   loop     ; while count != 0
        store r1, [r2+0]   ; RAM[26] = sum (r2 is now 26)
        halt
