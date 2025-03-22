const util = @import("util.zig");

pub fn get_usec_raw() u32 {
    return util.get32(@ptrFromInt(0x20003004));
}

// in usec.  the lower 32-bits of the usec
// counter: if you investigate in the broadcom
// doc can see how to get the high 32-bits too.
pub fn get_usec() u32 {
    util.dev_barrier();
    const u: u32 = get_usec_raw();
    util.dev_barrier();
    return u;
}

pub fn delay_us(us: u32) void {
    const s: u32 = get_usec();
    while (true) {
        const e: u32 = get_usec();
        if ((e - s) >= us)
            return;
    }
}

// delay in milliseconds
pub fn delay_ms(ms: u32) void {
    delay_us(ms * 1000);
}

// delay in sec
pub fn delay_sec(ms: u32) void {
    delay_ms(ms * 1000);
}
