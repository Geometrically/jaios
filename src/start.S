@ linker hack so we can force this file in the first portion of
@ the linked binary.
.section ".text.boot"

@ this is where we start.  if you look in any '.list' file, you
@ better see code at the first addresses (in our case: starting
@ at 0x8000).
.extern rpi_reboot
.globl _start
_start:

    @ force the mode to be SUPER.
    mov r0,  0x13
    orr r0,r0,#(1<<7)    @ disable interrupts.
    msr cpsr, r0

    mov r1, #0; @ Prefetch flush!!!
    mcr p15, 0, r1, c7, c5, 4

    mov sp, 0x8000000 @ initialize stack pointer
    mov fp, #0          @ clear frame pointer reg.  don't think needed.
    @ bl notmain        @ we could jump right to notmain
    bl _cstart          @ call our code to do initialization.
    bl rpi_reboot       @ if they return just reboot.

.globl _switch_to_user
_switch_to_user:
    @ force the mode to be USER.
    mrs	r3, CPSR
    bic	r3, r3, #31, 0
    orr	r3, r3, #16, 0
    msr	CPSR_fc, r3

    bx lr
