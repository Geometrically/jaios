const util = @import("util.zig");
const uart = @import("uart.zig");
const fmt = @import("fmt.zig");
const builtin = @import("builtin");

pub extern var __code_start__: *align(4) u32;
pub extern var __code_end__: *align(4) u32;

pub extern var __data_start__: *align(4) u32;
pub extern var __data_end__: *align(4) u32;

pub extern var __bss_start__: *align(4) u32;
pub extern var __bss_end__: *align(4) u32;

pub extern var __prog_end__: *align(4) u32;
pub extern var __heap_start__: *align(4) u32;

pub export fn notmain() void {
    const example = @import("examples/interrupts.zig");
    example.run_example();
}

pub export fn _cstart() void {
    var bss_ptr = @intFromPtr(&__bss_start__);
    const bss_end = @intFromPtr(&__bss_end__);

    // Zero out BSS section
    while (bss_ptr < bss_end) : (bss_ptr += @sizeOf(u32)) {
        const ptr: *volatile u32 = @ptrFromInt(bss_ptr);
        ptr.* = 0;
    }

    uart.init();

    util.cycle_cnt_init();

    notmain();

    util.clean_reboot();
}

const std = @import("std");

pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    const panic_addr = if (ret_addr) |addr| addr else @returnAddress();
    fmt.printfln("PANIC {}: {} {}", .{ panic_addr, msg, stack_trace });
    util.clean_reboot();
    unreachable;
}
