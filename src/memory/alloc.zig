var heap_start: usize = 0x00800000;
var heap_end: usize = 0x00900000;
var heap_ptr: usize = undefined; // Current allocation position

/// Initialize the heap
pub fn kmalloc_init() void {
    heap_ptr = heap_start;
}

/// Basic kmalloc implementation - allocates memory of given size
/// Returns null on failure
pub fn kmalloc(size: usize) ?*anyopaque {
    if (size == 0) return null;

    // Round up to 4-byte alignment for ARM
    const aligned_size = (size + 3) & ~@as(usize, 3);

    if (heap_ptr + aligned_size > heap_end) {
        return null; // Out of memory
    }

    const ptr = heap_ptr;
    heap_ptr += aligned_size;

    return @ptrFromInt(ptr);
}

/// Allocates memory with a specified alignment
/// Returns null on failure
pub fn kmalloc_aligned(size: usize, alignment: usize) ?*anyopaque {
    if (size == 0) return null;
    if (alignment == 0) return null;
    if ((alignment & (alignment - 1)) != 0) return null; // Not a power of 2

    // Calculate how much extra space we need for alignment
    const mask = alignment - 1;
    const padding = alignment; // Worst case padding

    // Allocate enough space for the data plus padding for alignment
    const unaligned_ptr = @intFromPtr(kmalloc(size + padding) orelse return null);

    // Calculate aligned address
    const aligned_ptr = (unaligned_ptr + mask) & ~mask;

    return @ptrFromInt(aligned_ptr);
}

pub fn kfree(_: *anyopaque) void {
    // TODO allow free of memory
}
