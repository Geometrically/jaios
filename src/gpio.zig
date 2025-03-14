const util = @import("util.zig");

pub const GPIO_BASE: u32 = 0x20200000;
pub const gpio_set0: u32 = GPIO_BASE + 0x1C;
pub const gpio_clr0: u32 = GPIO_BASE + 0x28;
pub const gpio_lev0: u32 = GPIO_BASE + 0x34;
pub const gpio_fsel0: u32 = GPIO_BASE + 0x00;

/// Set `pin` to be an output pin.
///
/// Only pins 0–31 and pin 47 are valid.
pub fn set_output(pin: u32) void {
    if (pin >= 32 and pin != 47) return;

    var fsel_register: u32 = 0;
    var fsel: u32 = 0;
    if (pin == 47) {
        fsel_register = pin / 32;
        fsel = pin % 32;
    } else {
        fsel_register = pin / 10;
        fsel = pin % 10;
    }

    // 3 bits per pin; 001 means output.
    const shift = fsel * 3;
    const shift_value: u5 = @intCast(shift);
    var current_sel = util.get32(@ptrFromInt(gpio_fsel0 + (fsel_register * 4)));
    current_sel &= ~(@as(u32, 0b111) << shift_value);
    current_sel |= (@as(u32, 1) << shift_value);
    util.put32(@ptrFromInt(gpio_fsel0 + (fsel_register * 4)), current_sel);
}

/// Set GPIO `pin` on.
pub fn set_on(pin: u32) void {
    if (pin >= 32 and pin != 47) return;
    const shift_value: u5 = @intCast(pin % 32);
    util.put32(@ptrFromInt(gpio_set0 + ((pin / 32) * 4)), (@as(u32, 1) << shift_value));
}

/// Set GPIO `pin` off.
pub fn set_off(pin: u32) void {
    if (pin >= 32 and pin != 47) return;
    const shift_value: u5 = @intCast(pin % 32);
    util.put32(@ptrFromInt(gpio_clr0 + ((pin / 32) * 4)), (@as(u32, 1) << shift_value));
}

/// Set GPIO `pin` to value `v` (where v ∈ {0,1}).
pub fn write(pin: u32, v: u32) void {
    if (v != 0) {
        set_on(pin);
    } else {
        set_off(pin);
    }
}

/// Set `pin` to be an input.
pub fn set_input(pin: u32) void {
    const fsel_register = pin / 10;
    const fsel = pin % 10;
    const shift = ((fsel + 1) * 3) - 3;
    var current_sel = util.get32(@ptrFromInt(gpio_fsel0 + (fsel_register * 4)));
    current_sel &= ~(0b111 << shift);
    util.put32(@ptrFromInt(gpio_fsel0 + (fsel_register * 4)), current_sel);
}

/// Return the value of `pin`.
///
/// Note: This translation uses the same arithmetic as the original C code.
pub fn read(pin: u32) i32 {
    const addr = gpio_lev0 + (((pin % 32) / 32) * 4);
    const pin_level = util.get32(@ptrFromInt(addr));
    return @intCast((pin_level >> pin) & 1);
}
