.globl rpi_cswitch
rpi_cswitch:
    push {r4-r11, lr}
    str sp, [r0]

    mov sp, r1

    pop {r4-r11, lr}
    bx lr

.globl rpi_init_trampoline
rpi_init_trampoline:
    mov r0, r5
    blx r4
    bl rpi_exit
    bx lr
