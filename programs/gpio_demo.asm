; gpio_demo.asm : read GPIO_IN, invert it, write to GPIO_OUT and read back
; The two NOPs give the two-flop GPIO_IN synchronizer time to propagate after
; reset before the first READ; the demo testbench drives GPIO_IN = 0xA5.
        nop
        nop
        load  r1, [r0+GPIO_IN]      ; synchronized switches
        not   r2, r1
        store r2, [r0+GPIO_OUT]     ; LEDs
        load  r3, [r0+GPIO_OUT]     ; readback
        halt
