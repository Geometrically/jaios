const std = @import("std");
const util = @import("../util.zig");
const uart = @import("../uart.zig");
const fmt = @import("../fmt.zig");
const alloc = @import("../memory/alloc.zig");

/// Constants for thread stack size
pub const THREAD_MAXSTACK: usize = 1024 * 8 / 4;

/// Register offset definitions for context switching
pub const R4_OFFSET: usize = 0;
pub const R5_OFFSET: usize = 1;
pub const R6_OFFSET: usize = 2;
pub const R7_OFFSET: usize = 3;
pub const R8_OFFSET: usize = 4;
pub const R9_OFFSET: usize = 5;
pub const R10_OFFSET: usize = 6;
pub const R11_OFFSET: usize = 7;
pub const LR_OFFSET: usize = 8;

/// Thread structure
pub const rpi_thread_t = struct {
    saved_sp: ?[*]u32 = null,
    next: ?*rpi_thread_t = null,
    tid: u32 = 0,
    fn_ptr: ?*const fn (*anyopaque) void = null,
    arg: ?*anyopaque = null,
    stack: [THREAD_MAXSTACK]u32 = undefined,
};

/// Queue implementation for thread management
pub const Q_t = struct {
    head: ?*rpi_thread_t = null,
    tail: ?*rpi_thread_t = null,

    pub fn init() Q_t {
        return Q_t{};
    }

    pub fn empty(self: *const Q_t) bool {
        return self.head == null;
    }

    pub fn append(self: *Q_t, thread: *rpi_thread_t) void {
        thread.next = null;
        if (self.tail) |tail| {
            tail.next = thread;
        } else {
            self.head = thread;
        }
        self.tail = thread;
    }

    pub fn push(self: *Q_t, thread: *rpi_thread_t) void {
        thread.next = self.head;
        self.head = thread;
        if (self.tail == null) {
            self.tail = thread;
        }
    }

    pub fn pop(self: *Q_t) ?*rpi_thread_t {
        if (self.head) |head| {
            self.head = head.next;
            if (self.head == null) {
                self.tail = null;
            }
            head.next = null;
            return head;
        }
        return null;
    }
};

/// Global thread system state
pub const ThreadSystem = struct {
    runq: Q_t = Q_t{},
    freeq: Q_t = Q_t{},
    cur_thread: ?*rpi_thread_t = null,
    scheduler_thread: ?*rpi_thread_t = null,
    tid: u32 = 1,
    nalloced: u32 = 0,
};

/// Singleton instance of the thread system
var g_thread_system = ThreadSystem{};

/// Debugging and tracing
fn th_trace(comptime fmt_str: []const u8, args: anytype) void {
    fmt.printf(fmt_str, args);
}

/// External assembly functions for context switching
extern fn rpi_cswitch(old_sp_save: *?[*]u32, new_sp: [*]u32) void;
extern fn rpi_init_trampoline() void;

/// Thread allocation from the pool or via kmalloc
fn th_alloc() ?*rpi_thread_t {
    var t = g_thread_system.freeq.pop();

    if (t == null) {
        const aligned_ptr = alloc.kmalloc_aligned(@sizeOf(rpi_thread_t), 8) orelse return null;
        t = @ptrCast(@alignCast(aligned_ptr));
        g_thread_system.nalloced += 1;
    }

    t.?.tid = g_thread_system.tid;
    g_thread_system.tid += 1;

    return t;
}

/// Return a thread to the free pool
fn th_free(thread: *rpi_thread_t) void {
    g_thread_system.freeq.push(thread);
}

/// Return pointer to the current thread
pub fn rpi_cur_thread() ?*rpi_thread_t {
    std.debug.assert(g_thread_system.cur_thread != null);
    return g_thread_system.cur_thread;
}

/// Create a new thread
pub fn rpi_fork(code: *const fn (*anyopaque) void, arg: *anyopaque) ?*rpi_thread_t {
    var t = th_alloc() orelse return null;

    t.fn_ptr = code;
    t.arg = arg;

    // Setup stack for context switching - stack grows down
    // Use pointer casting to get a [*]u32 slice
    const stack_idx = THREAD_MAXSTACK - 9;
    t.saved_sp = t.stack[stack_idx..].ptr;

    // Setup registers for trampoline
    t.saved_sp.?[R4_OFFSET] = @intFromPtr(code); // r4
    t.saved_sp.?[R5_OFFSET] = @intFromPtr(arg); // r5
    t.saved_sp.?[LR_OFFSET] = @intFromPtr(&rpi_init_trampoline); // lr

    th_trace("rpi_fork: tid={}, code=[{}], arg=[{}], saved_sp=[{}]\n", .{ t.tid, code, arg, t.saved_sp });

    g_thread_system.runq.append(t);
    return t;
}

/// Exit current thread
pub export fn rpi_exit(_: i32) void {
    var old_thread = g_thread_system.cur_thread.?;

    if (!g_thread_system.runq.empty()) {
        const t = g_thread_system.runq.pop().?;
        g_thread_system.cur_thread = t;
    } else {
        g_thread_system.cur_thread = g_thread_system.scheduler_thread;
        th_trace("done running threads, back to scheduler\n", .{});
    }

    rpi_cswitch(&old_thread.saved_sp, g_thread_system.cur_thread.?.saved_sp.?);
    th_free(old_thread);
}

/// Yield the current thread
pub fn rpi_yield() void {
    if (g_thread_system.runq.empty()) {
        return;
    }

    var old_thread = g_thread_system.cur_thread.?;

    // Call before_yield hook if registered
    if (preemption_hooks.before_yield) |hook| {
        hook(old_thread);
    }

    g_thread_system.runq.append(old_thread);

    const t = g_thread_system.runq.pop().?;
    g_thread_system.cur_thread = t;

    // Call after_yield hook if registered
    if (preemption_hooks.after_yield) |hook| {
        hook(t);
    }

    th_trace("switching from tid={} to tid={}\n", .{ old_thread.tid, t.tid });
    rpi_cswitch(&old_thread.saved_sp, g_thread_system.cur_thread.?.saved_sp.?);
}

/// Start the thread system
pub fn rpi_thread_start() void {
    // Initialize memory allocator if needed
    alloc.kmalloc_init();

    th_trace("starting threads!\n", .{});

    if (g_thread_system.runq.empty()) {
        th_trace("done with all threads, returning\n", .{});
        return;
    }

    if (g_thread_system.scheduler_thread == null) {
        g_thread_system.scheduler_thread = th_alloc();
    }

    if (g_thread_system.cur_thread == null) {
        g_thread_system.cur_thread = g_thread_system.scheduler_thread;
    }

    var old_thread = g_thread_system.cur_thread.?;
    const t = g_thread_system.runq.pop().?;
    g_thread_system.cur_thread = t;

    rpi_cswitch(&old_thread.saved_sp, t.saved_sp.?);

    th_trace("done with all threads, returning\n", .{});
}

/// Get the current thread's ID
pub fn rpi_tid() u32 {
    const t = rpi_cur_thread() orelse @panic("rpi_threads not running");
    return t.tid;
}

var preemption_hooks = struct {
    before_yield: ?*const fn (*rpi_thread_t) void = null,
    after_yield: ?*const fn (*rpi_thread_t) void = null,
}{};

pub fn register_preemption_hooks(before_yield: ?*const fn (*rpi_thread_t) void, after_yield: ?*const fn (*rpi_thread_t) void) void {
    preemption_hooks.before_yield = before_yield;
    preemption_hooks.after_yield = after_yield;
}
