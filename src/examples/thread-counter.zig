const thread = @import("../threads/thread.zig");
const fmt = @import("../fmt.zig");
const timer = @import("../timer.zig");

/// Thread function that counts up to 5
fn thread_func(arg: *anyopaque) void {
    // Get thread ID from argument
    const id = @intFromPtr(arg);
    fmt.printf("Thread {} started\n", .{id});

    // Count from 0 to 4, yielding between each count
    for (0..5) |i| {
        fmt.printf("Thread {}: count {}\n", .{ id, i });
        timer.delay_ms(100);
        thread.rpi_yield();
    }

    fmt.printf("Thread {} completed\n", .{id});
    // No need to call rpi_exit() explicitly - thread will exit when function returns
}

/// Main example function
pub fn run_example() void {
    fmt.println("Counter threads example starting");

    // Create three threads with different IDs
    _ = thread.rpi_fork(thread_func, @ptrFromInt(1));
    _ = thread.rpi_fork(thread_func, @ptrFromInt(2));
    _ = thread.rpi_fork(thread_func, @ptrFromInt(3));

    // Start thread scheduler - will return when all threads have completed
    thread.rpi_thread_start();

    fmt.println("All threads completed");
}
