const util = @import("../util.zig");
const uart = @import("../uart.zig");
const fmt = @import("../fmt.zig");
const timer = @import("../timer.zig");
const interrupt = @import("interrupt.zig");

pub const MAX_TIMERS: usize = 16;

pub const SoftwareTimer = struct {
    expiry: u64, // When this timer expires (in system ticks)
    period: u64, // For periodic timers (0 for one-shot)
    callback: ?*const fn () void, // Function to call on expiry (optional)
    active: bool,
    id: u32, // Timer identifier
};

// Timer pool
var timers: [MAX_TIMERS]SoftwareTimer = undefined;
var next_timer_id: u32 = 1; // Counter for assigning unique IDs
var current_tick: u64 = 0; // Current system tick

// Initialize the timer system
pub fn init() void {
    interrupt.init();
    interrupt.enable_interrupts();
    interrupt.timer_init(16, 0x1000);

    uart.puts("Initializing software timer system\n");

    for (0..MAX_TIMERS) |i| {
        timers[i].active = false;
        timers[i].callback = null;
        timers[i].id = 0;
    }
}

// Add a new software timer
// Returns timer ID or 0 if no slots available
pub fn add_timer(delay_time_ms: u32, period_ms: u32, callback: ?*const fn () void) u32 {
    current_tick = timer.get_usec();

    // Find a free timer slot
    for (0..MAX_TIMERS) |i| {
        if (!timers[i].active) {
            // Convert ms to timer ticks
            const delay_ticks = delay_time_ms * 1000;
            const period_ticks = period_ms * 1000;

            // Configure the timer
            timers[i].expiry = current_tick + delay_ticks;
            timers[i].period = period_ticks;
            timers[i].callback = callback;
            timers[i].active = true;
            timers[i].id = next_timer_id;
            next_timer_id += 1;

            return timers[i].id;
        }
    }

    // No free slots
    uart.puts("ERROR: No free timer slots available!\n");
    return 0;
}

// Cancel a software timer by ID
pub fn cancel_timer(id: u32) bool {
    for (0..MAX_TIMERS) |i| {
        if (timers[i].active and timers[i].id == id) {
            timers[i].active = false;
            return true;
        }
    }
    return false;
}

// Called from the interrupt handler
pub fn check_timers() void {
    // Update the current tick
    current_tick = timer.get_usec();

    for (0..MAX_TIMERS) |i| {
        if (timers[i].active and current_tick >= timers[i].expiry) {
            // Call the timer callback if it exists
            if (timers[i].callback) |callback| {
                callback();
            }

            // Reset periodic timers
            if (timers[i].period > 0) {
                timers[i].expiry = current_tick + timers[i].period;
            } else {
                timers[i].active = false;
            }
        }
    }
}
