const util = @import("util.zig");
const gpio = @import("gpio.zig");

// GPIO pins for TX and RX
const GPIO_TX: u32 = 14;
const GPIO_RX: u32 = 15;

// Define the constants for the memory-mapped UART registers
const PROG_BASE: u32 = 0x20000000;
const AUX_BASE: u32 = PROG_BASE + 0x215000;

// Enumerate the register offsets from the AUX base
const AUX_IRQ: u32 = AUX_BASE + 0x00;
const AUX_ENABLES: u32 = AUX_BASE + 0x04; // Controls which of the 3 AUX devices is enabled
const AUX_MU_IO_REG: u32 = AUX_BASE + 0x40; // Data register for the mini UART
const AUX_MU_IER_REG: u32 = AUX_BASE + 0x44; // Interrupt enable
const AUX_MU_IIR_REG: u32 = AUX_BASE + 0x48; // Interrupt identify / FIFO control
const AUX_MU_LCR_REG: u32 = AUX_BASE + 0x4C; // Line control
const AUX_MU_MCR_REG: u32 = AUX_BASE + 0x50; // Modem control (not used)
const AUX_MU_LSR_REG: u32 = AUX_BASE + 0x54; // Line status
const AUX_MU_MSR_REG: u32 = AUX_BASE + 0x58; // Modem status (not used)
const AUX_MU_SCRATCH: u32 = AUX_BASE + 0x5C; // Scratch
const AUX_MU_CNTL_REG: u32 = AUX_BASE + 0x60; // Mini UART enable bits
const AUX_MU_STAT_REG: u32 = AUX_BASE + 0x64; // Extra status
const AUX_MU_BAUD_REG: u32 = AUX_BASE + 0x68; // Baud rate

/// Set GPIO pins to a specific function (ALT0-ALT5)
fn set_function(pin: u32, func: u32) void {
    if (pin >= 32 and pin != 47) return;

    const fsel_register = pin / 10;
    const fsel = pin % 10;
    const shift = fsel * 3;
    const shift_value: u5 = @intCast(shift);

    var current_sel = util.get32(@ptrFromInt(gpio.gpio_fsel0 + (fsel_register * 4)));
    current_sel &= ~(@as(u32, 0b111) << shift_value);
    current_sel |= (func << shift_value);
    util.put32(@ptrFromInt(gpio.gpio_fsel0 + (fsel_register * 4)), current_sel);
}

/// Initialize the UART with 8n1 115200 baud, no interrupts
pub fn init() void {
    util.dev_barrier();

    // Set GPIO 14 (TX) and 15 (RX) to function ALT5 (0b010)
    set_function(GPIO_TX, 0b010);
    set_function(GPIO_RX, 0b010);

    util.dev_barrier();

    // Enable the mini UART
    var aux_enables = util.get32(@ptrFromInt(AUX_ENABLES));
    aux_enables |= 1;
    util.put32(@ptrFromInt(AUX_ENABLES), aux_enables);

    util.dev_barrier();

    // Disable the transmitter and receiver
    util.put32(@ptrFromInt(AUX_MU_CNTL_REG), 0);

    // Disable interrupts
    util.put32(@ptrFromInt(AUX_MU_IER_REG), 0);

    // Clear FIFO queues (0b110)
    util.put32(@ptrFromInt(AUX_MU_IIR_REG), 0b110);

    // Set to 8-bit mode (0b11)
    util.put32(@ptrFromInt(AUX_MU_LCR_REG), 0b11);

    // Disable modem control
    util.put32(@ptrFromInt(AUX_MU_MCR_REG), 0);

    // Set the baud rate to 115200 (250000000/(8*115200) - 1 ≈ 270)
    util.put32(@ptrFromInt(AUX_MU_BAUD_REG), 270);

    // Enable the transmitter and receiver (0b11)
    util.put32(@ptrFromInt(AUX_MU_CNTL_REG), 0b11);

    util.dev_barrier();
}

/// Disable the UART after flushing all pending transmissions
pub fn disable() void {
    flush_tx();

    // Disable transmitter and receiver
    util.put32(@ptrFromInt(AUX_MU_CNTL_REG), 0);
    util.dev_barrier();

    // Disable the mini UART
    var val = util.get32(@ptrFromInt(AUX_ENABLES));
    val &= ~@as(u32, 1); // Clear bit 0
    util.put32(@ptrFromInt(AUX_ENABLES), val);
    util.dev_barrier();
}

/// Check if there is data available to read
pub fn has_data() bool {
    return (util.get32(@ptrFromInt(AUX_MU_LSR_REG)) & 0b01) != 0;
}

/// Read one byte from the UART, blocking until data is available
pub fn get8() u8 {
    // Wait until data is available
    while (!has_data()) {}

    // Read and return the data
    return @truncate(util.get32(@ptrFromInt(AUX_MU_IO_REG)));
}

/// Read one byte from the UART, non-blocking
/// Returns -1 if no data is available
pub fn get8_async() i32 {
    if (!has_data()) {
        return -1;
    }
    return @intCast(get8());
}

/// Check if the UART can accept a byte for transmission
pub fn can_put8() bool {
    return (util.get32(@ptrFromInt(AUX_MU_LSR_REG)) & 0b100000) != 0;
}

/// Send one byte through the UART, blocking until space is available
pub fn put8(c: u8) i32 {
    // Wait until the transmitter has space
    while (!can_put8()) {}

    // Send the byte
    util.put32(@ptrFromInt(AUX_MU_IO_REG), c);
    return 1;
}

/// Check if the transmitter is completely empty and idle
pub fn tx_is_empty() bool {
    return (util.get32(@ptrFromInt(AUX_MU_LSR_REG)) & 0b1000000) != 0;
}

/// Wait until all bytes have been transmitted
pub fn flush_tx() void {
    while (!tx_is_empty()) {
        // In the C code this calls rpi_wait()
    }
}

/// Put a character to UART
pub fn putk(c: u8) void {
    if (c == '\n') {
        _ = put8('\r');
    }
    _ = put8(c);
}

/// Put a string to UART
pub fn puts(s: []const u8) void {
    for (s) |c| {
        putk(c);
    }
}
