; EXPERIMENT: hand-derived sync-RAM LOAD timing smoke program.
        loadi r1, 5
        addi  r5, r1, 0       ; establish flags, which LOAD must preserve
        store r1, [r0+0]
        load  r2, [r0+0]      ; synchronous RAM LOAD (+1 cycle)
        loadi r3, GPIO_OUT
        store r2, [r3+0]      ; STORE is not stalled
        load  r4, [r3+0]      ; MMIO read also waits (+1 cycle)
        loadi r6, CYCLE_COUNT_LO
        load  r7, [r0+CYCLE_COUNT_LO] ; samples count after first wait edge
        halt
.data 0x11, 0x22
