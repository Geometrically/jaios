const util = @import("../util.zig");
const gpio = @import("../gpio.zig");
const uart = @import("../uart.zig");
const fmt = @import("../fmt.zig");
const timer_interrupts = @import("timer-interrupts.zig");

// BCM2835 Interrupt Controller Registers (Based on documented addresses)
pub const INT_BASE: u32 = 0x2000B000;

// IRQ basic pending register
pub const IRQ_BASIC_PENDING: u32 = INT_BASE + 0x200;
pub const IRQ_PENDING_1: u32 = INT_BASE + 0x204;
pub const IRQ_PENDING_2: u32 = INT_BASE + 0x208;

// IRQ enable registers
pub const IRQ_ENABLE_1: u32 = INT_BASE + 0x210;
pub const IRQ_ENABLE_2: u32 = INT_BASE + 0x214;
pub const IRQ_ENABLE_BASIC: u32 = INT_BASE + 0x218;

// IRQ disable registers
pub const IRQ_DISABLE_1: u32 = INT_BASE + 0x21C;
pub const IRQ_DISABLE_2: u32 = INT_BASE + 0x220;
pub const IRQ_DISABLE_BASIC: u32 = INT_BASE + 0x224;

// Bit positions in IRQ_BASIC_PENDING/ENABLE/DISABLE
pub const IRQ_TIMER_BIT: u32 = 0;
pub const IRQ_MAILBOX_BIT: u32 = 1;
pub const IRQ_DOORBELL0_BIT: u32 = 2;
pub const IRQ_DOORBELL1_BIT: u32 = 3;
pub const IRQ_GPU0_HALTED_BIT: u32 = 4;
pub const IRQ_GPU1_HALTED_BIT: u32 = 5;
pub const IRQ_ILLEGAL_ACCESS_TYPE1_BIT: u32 = 6;
pub const IRQ_ILLEGAL_ACCESS_TYPE0_BIT: u32 = 7;

// ARM Timer Registers (as documented in the BCM2835 ARM Peripherals manual)
pub const TIMER_BASE: u32 = 0x2000B000;
pub const TIMER_LOAD: u32 = TIMER_BASE + 0x400;
pub const TIMER_VALUE: u32 = TIMER_BASE + 0x404;
pub const TIMER_CONTROL: u32 = TIMER_BASE + 0x408;
pub const TIMER_IRQ_CLEAR: u32 = TIMER_BASE + 0x40C;
pub const TIMER_RAW_IRQ: u32 = TIMER_BASE + 0x410;
pub const TIMER_MASKED_IRQ: u32 = TIMER_BASE + 0x414;
pub const TIMER_RELOAD: u32 = TIMER_BASE + 0x418;
pub const TIMER_PREDIV: u32 = TIMER_BASE + 0x41C;
pub const TIMER_FREE_COUNTER: u32 = TIMER_BASE + 0x420;

// Timer control register bits
pub const TIMER_CTRL_32BIT: u32 = 1 << 1;
pub const TIMER_CTRL_PRESCALE_1: u32 = 0 << 2;
pub const TIMER_CTRL_PRESCALE_16: u32 = 1 << 2;
pub const TIMER_CTRL_PRESCALE_256: u32 = 2 << 2;
pub const TIMER_CTRL_ENABLE_INT: u32 = 1 << 5;
pub const TIMER_CTRL_ENABLE: u32 = 1 << 7;
pub const TIMER_CTRL_HALT_DEBUG: u32 = 1 << 8;
pub const TIMER_CTRL_FREE_ENABLE: u32 = 1 << 9;

pub const ARM_TIMER_IRQ: u32 = 1 << 0;

pub extern fn disable_interrupts() void;
pub extern fn enable_interrupts() void;
pub extern fn syscall_hello() void;

extern const _interrupt_table: u32;
extern const _interrupt_table_end: u32;

pub var interrupts_init: bool = false;

pub fn init() void {
    if (interrupts_init) {
        return;
    }

    uart.puts("about to install interrupt handlers \n");

    disable_interrupts();

    fmt.printfln("addrs: start {} end {}", .{ @intFromPtr(&_interrupt_table), @intFromPtr(&_interrupt_table_end) });

    util.put32(@ptrFromInt(IRQ_DISABLE_1), 0xffffffff);
    util.put32(@ptrFromInt(IRQ_DISABLE_2), 0xffffffff);

    util.dev_barrier();

    // A2-16: first interrupt code address at <0> (reset)
    var dst: [*]allowzero volatile u32 = @ptrFromInt(0);

    // copy the handlers to <dst>
    const n: u32 = @intFromPtr(&_interrupt_table_end) - @intFromPtr(&_interrupt_table);

    const src: [*]volatile u32 = @ptrCast(@constCast(&_interrupt_table));
    const words = n / @sizeOf(u32);
    var i: u32 = 0;
    while (i < words) : (i += 1) {
        dst[i] = src[i];
    }

    interrupts_init = true;
}

pub fn timer_init(prescale: u32, ncycles: u32) void {
    uart.puts("setting up timer interrupts!\n");

    // assume we don't know what was happening before.
    util.dev_barrier();

    // bcm p 116
    // write a 1 to enable the timer inerrupt ,
    // "all other bits are unaffected"
    util.put32(@ptrFromInt(IRQ_ENABLE_BASIC), ARM_TIMER_IRQ);

    // dev barrier b/c the ARM timer is a different device
    // than the interrupt controller.
    util.dev_barrier();

    // Timer frequency = Clk/256 * Load
    //   - so smaller <Load> = = more frequent.
    util.put32(@ptrFromInt(TIMER_LOAD), ncycles);

    var v: u32 = 0;
    switch (prescale) {
        1 => v = TIMER_CTRL_PRESCALE_1,
        16 => v = TIMER_CTRL_PRESCALE_16,
        256 => v = TIMER_CTRL_PRESCALE_256,
        else => util.panic("invalid prescales for timer"),
    }

    util.put32(@ptrFromInt(TIMER_CONTROL), TIMER_CTRL_32BIT | TIMER_CTRL_ENABLE | TIMER_CTRL_ENABLE_INT | v);

    util.dev_barrier();
}

pub export fn fast_interrupt_vector(pc: usize) void {
    fmt.printfln("fast interrupt {}", .{pc});
    util.panic("fast interrupt unhandled!");
}

pub export fn syscall_vector(pc: usize, r0: usize) void {
    const instr: *u32 = @ptrFromInt(pc);
    const mask: u32 = (1 << 24) - 1;
    const sys_num = instr.* & mask;

    fmt.printfln("syscall_vector num {} pc {} r0 {}", .{ sys_num, pc, r0 });
}

pub export fn reset_vector(pc: usize) void {
    fmt.printfln("fast interrupt {}", .{pc});
    util.panic("fast interrupt vector unhandled!");
}

pub export fn undefined_instruction_vector(pc: usize) void {
    fmt.printfln("undefined instr {}", .{pc});
    util.panic("undefined_instruction_vector unhandled!");
}

pub export fn prefetch_abort_vector(pc: usize) void {
    fmt.printfln("prefetch abort {}", .{pc});
    util.panic("prefetch_abort_vector unhandled!");
}

pub export fn data_abort_vector(pc: usize) void {
    fmt.printfln("data abort {}", .{pc});
    util.panic("data_abort_vector unhandled!");
}

pub export fn interrupt_vector() void {
    util.dev_barrier();

    var pending: u32 = 0;
    pending = util.get32(@ptrFromInt(IRQ_BASIC_PENDING));

    if ((pending & ARM_TIMER_IRQ) != 0) {
        util.put32(@ptrFromInt(TIMER_IRQ_CLEAR), 1);
        util.dev_barrier();
        timer_interrupts.check_timers();
        util.dev_barrier();
    }
}
