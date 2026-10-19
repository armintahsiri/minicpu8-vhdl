; r0_guard.asm -- R0 stays hardwired to zero for ALU, LOAD and CALL paths.
; Expected: r0=0, RAM[3]=0, RAM[16]=0x5A, RAM[20]=link to after the call.

        .data 16, 0x5A
        loadi r1, 16
        load  r0, [r1+0]   ; LOAD to R0 must be ignored
        addi  r0, r0, 7    ; ADDI to R0 must be ignored
        store r0, [r0+3]   ; writes 0 to RAM[3]
        call  sub          ; CALL writes R7, never R0
        halt

sub:    load  r0, [r1+0]   ; ignored again
        ret
