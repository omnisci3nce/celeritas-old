const std = @import("std");
const vec3 = @import("zalgebra").vec3;
const c_allocator = @import("std").heap.c_allocator;

// colours

pub const lightBlue50 = hexToRGB(0xF0F9FF);
pub const lightBlue100 = hexToRGB(0xE0F2FE);
pub const lightBlue200 = hexToRGB(0xBAE6FD);
pub const lightBlue300 = hexToRGB(0x7DD3FC);
pub const lightBlue400 = hexToRGB(0x38BDF8);
pub const lightBlue500 = hexToRGB(0x0EA5E9);
pub const lightBlue600 = hexToRGB(0x0284C7);
pub const lightBlue700 = hexToRGB(0x0369A1);
pub const lightBlue800 = hexToRGB(0x075985);
pub const lightBlue900 = hexToRGB(0x0C4A6E);

pub fn hexToRGB (input: u32) u32 {
    const r = ((input >> 16) & 0xFF) / 255.0;
    const g = ((input >> 8) & 0xFF) / 255.0;
    const b = (input & 0xFF) / 255.0;
    return vec3.new(r, g, b);
}

pub fn read_from_file(path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const bytes = try file.reader().readAllAlloc(
        c_allocator,
        100000000,
    );
    
    return bytes;
}