const uart = @import("uart.zig");

const STACK_ADDR = 0x8000000;
const STACK_ADDR2 = 0x7000000;

const INT_STACK_ADDR = 0x9000000;
const INT_STACK_ADDR2 = 0xA000000;

const FREE_MB = 0x6000000;
const HIGHEST_USED_ADDR = INT_STACK_ADDR;

const CYC_PER_USEC = 700;
const PI_MHz = 700 * 1000 * 1000;

inline fn cycles_to_nanosec(c: u64) u64 {
    return (c * 142857) / 100000;
}

inline fn usec_to_cycles(usec: u64) u64 {
    return usec * CYC_PER_USEC;
}

pub fn delay_ms(ms: u32) void {
    const delay_cycles = usec_to_cycles(ms * 1000);
    var i: u32 = 0;
    while (i < delay_cycles) : (i += 1) {}
}

pub fn put32(addr: *volatile u32, value: u32) void {
    addr.* = value;
}

pub fn get32(addr: *volatile u32) u32 {
    return addr.*;
}

pub export fn at_user_level() bool {
    var cpsr: u32 = undefined;
    asm volatile ("mrs %[cpsr], CPSR"
        : [cpsr] "=r" (cpsr),
    );
    return (cpsr & 0x1F) == 0x10; // User mode is 0x10
}

pub export fn rpi_reboot() void {
    delay_ms(1);

    if (at_user_level()) {
        uart.puts("Switching to supervisor mode...\n");
        _switch_to_user();
    }

    const PM_RSTC = 0x2010001c;
    const PM_WDOG = 0x20100024;
    const PM_PASSWORD = 0x5a000000;
    const PM_RSTC_WRCFG_FULL_RESET = 0x00000020;

    put32(@ptrFromInt(PM_WDOG), PM_PASSWORD | 1);
    put32(@ptrFromInt(PM_RSTC), PM_PASSWORD | PM_RSTC_WRCFG_FULL_RESET);

    while (true) {}
}

pub export fn clean_reboot() void {
    uart.puts("DONE!!!\n");
    uart.flush_tx();
    delay_ms(1);
    rpi_reboot();
}

pub extern fn _switch_to_user() void;

pub inline fn cycle_cnt_init() void {
    const in: u32 = 1;
    asm volatile ("mcr p15, 0, %[in], c15, c12, 0"
        :
        : [in] "r" (in),
    );
}

pub extern fn dev_barrier() void;
pub extern fn dmb() void;
pub extern fn dsb() void;
