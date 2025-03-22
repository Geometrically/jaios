.equ MODE_USR, 0x10
.equ MODE_FIQ, 0x11
.equ MODE_IRQ, 0x12
.equ MODE_SVC, 0x13
.equ MODE_ABT, 0x17
.equ MODE_UND, 0x1B
.equ MODE_SYS, 0x1F

// Define interrupt stack locations
.equ INT_STACK_ADDR, 0x8000000  // Main interrupt stack
.equ STACK_SIZE, 0x1000         // 4KB for each stack

.globl enable_interrupts
enable_interrupts:
    mrs r0,cpsr         @ move cpsr to r0
    bic r0,r0,#(1<<7)	@ clear 7th bit.
    msr cpsr_c,r0		@ move r0 back to PSR
    bx lr		        @ return.

.globl disable_interrupts
disable_interrupts:
    mrs r0,cpsr
    orr r0,r0,#(1<<7)	@ set 7th bit
    msr cpsr_c,r0
    bx lr

.globl _interrupt_table
.globl _interrupt_table_end
_interrupt_table:
    @ Q: why can we copy these ldr jumps and have
    @ them work the same?
    ldr pc, _reset_asm
    ldr pc, _undefined_instruction_asm
    ldr pc, _software_interrupt_asm
    ldr pc, _prefetch_abort_asm
    ldr pc, _data_abort_asm
    ldr pc, _reset_asm
    ldr pc, _interrupt_asm
fast_interrupt_asm:
    sub   lr, lr, #4 @First instr of FIQ handler
    push  {lr}
    push  {r0-r12}
    mov   r0, lr              @ Pass old pc
    bl    fast_interrupt_vector    @ C function
    pop   {r0-r12}
    ldm   sp!, {pc}^

_reset_asm:                   .word reset_asm
_undefined_instruction_asm:   .word undefined_instruction_asm
_software_interrupt_asm:      .word software_interrupt_asm
_prefetch_abort_asm:          .word prefetch_abort_asm
_data_abort_asm:              .word data_abort_asm
_interrupt_asm:               .word interrupt_asm
_interrupt_table_end:

@ only handler that should run since we
@ only enable general interrupts
interrupt_asm:
  @ NOTE:
  @  - each mode has its own <sp> that persists when
  @    we switch out of the mode (i.e., will be the same
  @    when switch back).
  @  - <INT_STACK_ADDR> is a physical address we reserve
  @   for exception stacks today.  we don't do recursive
  @   exception/interupts so one stack is enough.
  mov sp, #INT_STACK_ADDR
  sub   lr, lr, #4

  push  {r0-r12,lr}         @ XXX: pushing too many
                            @ registers: only need caller
                            @ saved.

  mov   r0, lr              @ Pass old pc as arg 0
  bl    interrupt_vector    @ C function: expects C
                            @ calling conventions.

  pop   {r0-r12,lr} 	    @ pop integer registers, must match push

  @ return from interrupt handler: will re-enable general ints.
  @ Q: what happens if you do "mov" instead?
  @ Q: what other instructions could we use?
  movs    pc, lr        @ 1: moves <spsr> into <cpsr>
                        @ 2. moves <lr> into the <pc> of that
                        @    mode.

reset_asm:
    @ Q: if we delete this instruction what happens?
    mov sp, #INT_STACK_ADDR
    @ Q: is <4> correct?  how to tell?
    sub   r0, lr, #4
    bl    reset_vector

@ note: we compile this <.S> file with gcc
@ so that we can use C macro's to clean up.
@ note the use of semi-colons!
#define unexpected(fn, offset)      \
    mov sp, #INT_STACK_ADDR;        \
    sub   r0, lr, #(offset);        \
    bl    fn

software_interrupt_asm:
    @ runs at system level (p.a2-5): assumes we have a sp
    @
    @ you're going to call:
    @    int syscall_vector(unsigned pc, uint32_t r0) {
    @
    @   1 save regs as with interrupt vector
    @   2 figure out the lr offset you need to correct.
    @   3 mov the original r0 into r1 (so it's the second
    @     parameter to <syscall_vector>)
    @   4 mov the pointer to the syscall inst into r0
    @     (so its the first parameter to <syscall_vector>)
    @   5 call ,syscall_vector>
    @   6 restore regs: must be identical to what got pushed
    @     at step (1)
    @   - return from the exception (look at interrupt_asm)
    push  {r1-r12,lr}         @ XXX: pushing too many
                                @ registers: only need caller
                                @ saved.
    sub   lr, lr, #4

    mov   r1, r0
    mov   r0, lr              @ Pass old pc as arg 0

    bl    syscall_vector    @ C function: expects C
                                @ calling conventions.

    pop   {r1-r12,lr} 	    @ pop integer registers
                                @ this MUST MATCH the push.
                                @ very common mistake.

    movs pc, lr

@ Q: what are the right offsets for the following?
undefined_instruction_asm:
    unexpected(undefined_instruction_vector,4)
prefetch_abort_asm:
    unexpected(prefetch_abort_vector,4)
data_abort_asm:
    unexpected(data_abort_vector,4)
