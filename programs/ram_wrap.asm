; Effective data-memory address wraps modulo 256.
loadi r1, -1
loadi r2, 5
store r2, [r1+1]   ; 0xFF + 1 -> RAM[0]
load r3, [r1+1]
halt
