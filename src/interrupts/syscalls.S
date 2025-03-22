.globl syscall_hello
syscall_hello:
    @ we are already at system level: running this will trash
    @ the lr, so we need to save it.
    push {lr}
    swi 1
    pop {lr}
    bx lr
