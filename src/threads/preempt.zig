const std = @import("std");
const util = @import("../util.zig");
const fmt = @import("../fmt.zig");
const uart = @import("../uart.zig");
const thread = @import("thread.zig");
const interrupt = @import("../interrupts/interrupt.zig");
const timer_interrupts = @import("../interrupts/timer-interrupts.zig");
const alloc = @import("../memory/alloc.zig");

/// Thread states for preemptive threading
pub const ThreadState = enum {
    READY,
    RUNNING,
    BLOCKED,
    TERMINATED,
};

/// Extended thread structure for preemptive scheduling
pub const PreemptiveThread = struct {
    base: thread.rpi_thread_t,
    state: ThreadState = .READY,
    time_slice: u32 = 0,
    priority: u32 = 1,
};

/// Global preemptive scheduler state
pub const PreemptiveScheduler = struct {
    initialized: bool = false,
    preemption_enabled: bool = false,
    time_slice_ms: u32 = 10, // Default time slice in milliseconds
    current_thread_time: u32 = 0,
    idle_thread: ?*PreemptiveThread = null,
};

var scheduler = PreemptiveScheduler{};

// Static variable for idle thread - explicitly initialized to avoid null issues
var idle_thread_data: u32 = 0xDEAD;

/// Convert regular thread to preemptive thread
fn to_preemptive(t: *thread.rpi_thread_t) *PreemptiveThread {
    return @ptrCast(@alignCast(t));
}

/// Get the current preemptive thread
fn current_preemptive_thread() ?*PreemptiveThread {
    if (thread.rpi_cur_thread()) |t| {
        return to_preemptive(t);
    }
    return null;
}

/// Timer interrupt callback for preemptive scheduling
fn timer_tick() void {
    if (!scheduler.preemption_enabled) return;

    // Increment time counter
    scheduler.current_thread_time += 1;

    // If time slice has expired, force a thread switch
    if (scheduler.current_thread_time >= scheduler.time_slice_ms) {
        scheduler.current_thread_time = 0;

        // Force a yield from the interrupt handler
        // This will be executed after returning from the interrupt
        schedule_next_thread();
    }
}

/// Switch to the next thread based on scheduling policy
fn schedule_next_thread() void {
    if (current_preemptive_thread()) |current| {
        // Only switch if thread is still in RUNNING state
        // (it might have changed state during execution)
        if (current.state == .RUNNING) {
            current.state = .READY;
            thread.rpi_yield();
        }
    }
}

/// Idle thread function - runs when no other threads are ready
fn idle_thread_fn(arg: *anyopaque) void {
    _ = arg; // Unused
    fmt.println("Idle thread running");
    while (true) {
        // Low-power wait or simply yield the CPU
        util.dev_barrier();
        thread.rpi_yield();
    }
}

/// Initialize the preemptive scheduler
pub fn init(time_slice_ms: u32) void {
    if (scheduler.initialized) return;

    fmt.println("Initializing preemptive scheduler...");

    // Initialize memory allocation system first
    alloc.kmalloc_init();

    // Set up time slice
    scheduler.time_slice_ms = time_slice_ms;

    // Initialize timer interrupts
    timer_interrupts.init();

    // Register our timer tick function
    _ = timer_interrupts.add_timer(1, // Start after 1 ms
        1, // Run every 1 ms
        timer_tick);

    fmt.println("Creating idle thread...");

    // Create idle thread using our static data as the argument
    const idle_thread_ptr = thread.rpi_fork(&idle_thread_fn, &idle_thread_data) orelse {
        fmt.println("Failed to create idle thread!");
        return;
    };

    fmt.println("Idle thread created successfully");

    // Convert and initialize idle thread
    scheduler.idle_thread = to_preemptive(idle_thread_ptr);

    // Mark scheduler as initialized
    scheduler.initialized = true;
    fmt.printf("Preemptive scheduler initialized with {} ms time slice\n", .{time_slice_ms});
}

/// Start preemptive scheduling
pub fn start() void {
    if (!scheduler.initialized) {
        fmt.println("Error: Must call init() before start()");
        return;
    }

    fmt.println("Starting preemptive scheduler...");

    // Enable preemption
    scheduler.preemption_enabled = true;

    // Enable CPU interrupts globally
    interrupt.enable_interrupts();

    // Start the threading system
    thread.rpi_thread_start();

    // When we return, disable preemption
    scheduler.preemption_enabled = false;
    interrupt.disable_interrupts();
}

/// Create a new preemptive thread
pub fn create_thread(code: *const fn (*anyopaque) void, arg: *anyopaque, priority: u32) ?*PreemptiveThread {
    // Create base thread
    const base_thread = thread.rpi_fork(code, arg) orelse return null;

    // Convert to preemptive thread
    const preempt_thread = to_preemptive(base_thread);

    // Initialize preemptive properties
    preempt_thread.state = .READY;
    preempt_thread.priority = priority;
    preempt_thread.time_slice = scheduler.time_slice_ms;

    return preempt_thread;
}

/// Sleep the current thread for a given number of milliseconds
pub fn sleep_ms(ms: u32) void {
    if (ms == 0) return;

    if (current_preemptive_thread()) |current| {
        // Create a timer to wake us up
        const wake_timer_id = timer_interrupts.add_timer(ms, 0, // One-shot timer
            null // No callback needed
        );

        if (wake_timer_id == 0) {
            fmt.println("Failed to create sleep timer");
            return;
        }

        // Block the thread until the timer expires
        current.state = .BLOCKED;

        // Yield to allow other threads to run
        thread.rpi_yield();

        // When we're back, mark as running
        current.state = .RUNNING;
    }
}

/// Pre-yield hook - called before each yield in the base threading system
pub fn before_yield(t: *thread.rpi_thread_t) void {
    const preempt_t = to_preemptive(t);
    preempt_t.state = .READY;
}

/// Post-yield hook - called after a thread is selected to run
pub fn after_yield(t: *thread.rpi_thread_t) void {
    const preempt_t = to_preemptive(t);
    preempt_t.state = .RUNNING;
    scheduler.current_thread_time = 0;
}
