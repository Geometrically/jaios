const uart = @import("../uart.zig");
const util = @import("../util.zig");
// const fmt = @import("../fmt.zig");
const interrupts = @import("../interrupts/interrupt.zig");
const timer = @import("../timer.zig");

pub fn run_example() void {
    interrupts.init();
    uart.puts("gonna enable ints globally! \n");
    interrupts.enable_interrupts();

    interrupts.syscall_hello();

    uart.puts("done enable ints globally! \n");
}
