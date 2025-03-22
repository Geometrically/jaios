const std = @import("std");
const fmt = @import("../fmt.zig");
const uart = @import("../uart.zig");
const timer = @import("../timer.zig");
const thread = @import("../threads/thread.zig");
const preempt = @import("../threads/preempt.zig");
const gpio = @import("../gpio.zig");

// LED pins for visual feedback
const LED_PIN1: u32 = 17;

// Shared counter between threads
var shared_counter: u32 = 0;

// Long-running CPU-intensive thread that will be preempted
fn compute_thread(arg: *anyopaque) void {
    const thread_id = @intFromPtr(arg);
    fmt.printfln("Compute thread {} starting\n", .{thread_id});

    // Set up an LED for visual feedback
    gpio.set_output(LED_PIN1);

    for (0..5) |i| {
        // Simulate CPU-intensive work without yielding
        var sum: u32 = 0;
        for (0..1000000) |j| {
            sum +%= @intCast(j);
        }

        // Toggle LED to show we're still running
        if (i % 2 == 0) {
            gpio.set_on(LED_PIN1);
        } else {
            gpio.set_off(LED_PIN1);
        }

        // Update shared counter
        shared_counter += 1;

        fmt.printfln("Compute {} iteration {} complete, counter = {}\n", .{ thread_id, i, shared_counter });
    }

    fmt.printfln("Compute thread {} finished\n", .{thread_id});

    // Turn off LED when done
    gpio.set_off(LED_PIN1);
}

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

pub fn run_example() void {
    fmt.println("Starting preemptive threading example...");

    // Initialize the preemptive scheduler with 50ms time slices
    preempt.init(50);

    // Register the preemption hooks with the base thread system
    thread.register_preemption_hooks(preempt.before_yield, preempt.after_yield);

    // Create compute-bound thread (higher priority)
    _ = preempt.create_thread(&compute_thread, @ptrFromInt(1), 2);

    _ = preempt.create_thread(&thread_func, @ptrFromInt(2), 1);

    // Start the preemptive scheduler
    preempt.start();

    fmt.println("All threads completed!");
}
