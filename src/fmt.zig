const uart = @import("uart.zig");

/// A minimal formatter for embedded systems
pub const Writer = struct {
    /// Print an integer in decimal format
    pub fn printInt(value: anytype) void {
        if (@TypeOf(value) == comptime_int) {
            printIntImpl(value);
            return;
        }

        // Handle negative numbers
        if (@typeInfo(@TypeOf(value)).Int.signedness == .signed and value < 0) {
            uart.putk('-');
            printIntImpl(@as(u64, @intCast(-value)));
        } else {
            printIntImpl(@as(u64, @intCast(value)));
        }
    }

    fn printIntImpl(value: u64) void {
        // Special case for 0
        if (value == 0) {
            uart.putk('0');
            return;
        }

        // Convert the number to digits
        var buf: [20]u8 = undefined; // Enough for 64-bit integers
        var len: usize = 0;

        var val = value;
        while (val > 0) {
            buf[len] = @as(u8, @intCast(val % 10)) + '0';
            val /= 10;
            len += 1;
        }

        // Print in reverse order
        var i: usize = len;
        while (i > 0) {
            i -= 1;
            uart.putk(buf[i]);
        }
    }

    /// Print a hexadecimal number
    pub fn printHex(value: anytype) void {
        const digits = "0123456789ABCDEF";

        // For zero special case
        if (value == 0) {
            uart.putk('0');
            return;
        }

        // Handle conversion to unsigned without std
        const T = @TypeOf(value);
        const unsigned_value = if (@typeInfo(T).Int.signedness == .signed)
            @as(@Type(.{ .Int = .{ .signedness = .unsigned, .bits = @typeInfo(T).Int.bits } }), @bitCast(value))
        else
            value;

        // Convert to hex digits
        var buf: [16]u8 = undefined; // Enough for 64-bit integers in hex
        var len: usize = 0;

        var val = unsigned_value;
        while (val > 0 and len < buf.len) {
            buf[len] = digits[val & 0xF];
            val >>= 4;
            len += 1;
        }

        // Print in reverse order
        var i: usize = len;
        while (i > 0) {
            i -= 1;
            uart.putk(buf[i]);
        }
    }

    /// Print a string
    pub fn printStr(str: []const u8) void {
        uart.puts(str);
    }

    /// Print a boolean value
    pub fn printBool(value: bool) void {
        if (value) {
            printStr("true");
        } else {
            printStr("false");
        }
    }

    /// Print a string followed by a newline
    pub fn println(str: []const u8) void {
        printStr(str);
        uart.puts("\n");
    }
};

// Top-level convenience functions
pub fn print(str: []const u8) void {
    Writer.printStr(str);
}

pub fn println(str: []const u8) void {
    Writer.println(str);
}

// Simple printf implementation for basic formats
pub fn printf(comptime fmt: []const u8, args: anytype) void {
    if (args.len == 0) {
        // No arguments, just print the string
        print(fmt);
        return;
    }

    // Define a format segment struct for our compile-time analysis
    const FormatSegment = union(enum) {
        text: []const u8,
        arg_index: usize,
    };

    // Parse the format string at compile time
    const segments = comptime blk: {
        var result: []const FormatSegment = &[_]FormatSegment{};
        var i: usize = 0;
        var start: usize = 0;
        var arg_idx: usize = 0;

        while (i < fmt.len) {
            if (fmt[i] == '{' and i + 1 < fmt.len and fmt[i + 1] == '}') {
                // Add text segment
                if (i > start) {
                    result = result ++ &[_]FormatSegment{.{ .text = fmt[start..i] }};
                }

                // Add argument placeholder
                result = result ++ &[_]FormatSegment{.{ .arg_index = arg_idx }};
                arg_idx += 1;

                i += 2; // Skip {}
                start = i;
            } else {
                i += 1;
            }
        }

        // Add remaining text
        if (start < fmt.len) {
            result = result ++ &[_]FormatSegment{.{ .text = fmt[start..fmt.len] }};
        }

        break :blk result;
    };

    // Now print each segment at runtime
    inline for (segments) |segment| {
        switch (segment) {
            .text => |text| Writer.printStr(text),
            .arg_index => |idx| {
                const arg = args[idx];
                switch (@TypeOf(arg)) {
                    []const u8, [:0]const u8 => Writer.printStr(arg),
                    bool => Writer.printBool(arg),
                    else => switch (@typeInfo(@TypeOf(arg))) {
                        .Int, .ComptimeInt => Writer.printInt(arg),
                        .Float, .ComptimeFloat => Writer.printStr("<float>"), // Placeholder
                        .Pointer => if (@typeInfo(@TypeOf(arg)).Pointer.size == .Slice and
                            @typeInfo(@TypeOf(arg)).Pointer.child == u8)
                        {
                            Writer.printStr(arg);
                        } else {
                            Writer.printStr("0x");
                            Writer.printHex(@intFromPtr(arg));
                        },
                        else => Writer.printStr("<unknown>"),
                    },
                }
            },
        }
    }
}

pub fn printfln(comptime fmt: []const u8, args: anytype) void {
    printf(fmt, args);
    uart.puts("\n");
}
