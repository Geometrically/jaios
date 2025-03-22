const uart = @import("../uart.zig");
const fmt = @import("../fmt.zig");

pub fn run_example() void {
    // Example 1: Basic printing
    fmt.print("Hello from the RPi!\n");
    fmt.println("This line ends with a newline");

    // Example 2: Printing integers
    const count: u32 = 42;
    fmt.printf("Count: {}\n", .{count});

    // Example 3: Printing negative numbers
    const temperature: i16 = -5;
    fmt.printf("Temperature: {} degrees\n", .{temperature});

    // Example 4: Printing hexadecimal values
    const address: u32 = 0x20200000;
    fmt.printf("GPIO base address: 0x", .{});
    fmt.Writer.printHex(address);
    fmt.print("\n");

    // Example 5: Printing multiple values in a single format string
    const sensor_id: u8 = 3;
    const sensor_value: u16 = 1024;
    fmt.printf("Sensor {} reading: {}\n", .{ sensor_id, sensor_value });

    // Example 6: Printing boolean values
    const is_enabled: bool = true;
    fmt.printf("System enabled: {}\n", .{is_enabled});

    // Example 7: Printing pointers
    const memory_ptr: *u32 = @ptrFromInt(0xFFFF0000);
    fmt.printf("Memory location: {}\n", .{memory_ptr});

    // Example 8: Printing strings
    const message: []const u8 = "Status OK";
    fmt.printf("System message: {}\n", .{message});

    // Example 9: Multi-line status display
    fmt.println("==== System Status ====");
    fmt.printf("Version: {}\n", .{1});
    fmt.printf("Uptime: {} seconds\n", .{3600});
    fmt.printf("Memory used: {} bytes\n", .{8192});
    fmt.println("======================");

    // Example 10: Debug information
    const debug_mode = false;
    const error_code: u16 = 404;
    fmt.printf("Debug mode: {}, Error code: {}\n", .{ debug_mode, error_code });
}
