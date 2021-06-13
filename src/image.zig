// Inspired by https://github.com/andrewrk/tetris

const c = @import("c.zig");
const std = @import("std");

pub const Image = struct {
    width: u32,
    height: u32,
    channels: u32,
    pitch: u32,
    raw: []u8,

    pub fn destroy(pi: *Image) void {
        c.stbi_image_free(pi.raw.ptr);
    }

    pub fn create(compressed_bytes: []const u8) !Image {
        var pi: Image = undefined;

        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels: c_int = undefined;

        if (c.stbi_is_16_bit_from_memory(compressed_bytes.ptr, @intCast(c_int, compressed_bytes.len)) != 0) {
            return error.InvalidFormat;
        }
        const bits_per_channel = 8;

        // c.stbi_set_flip_vertically_on_load(1);
        const image_data = c.stbi_load_from_memory(compressed_bytes.ptr, @intCast(c_int, compressed_bytes.len), &width, &height, &channels, 0);
        pi.width = @intCast(u32, width);
        pi.height = @intCast(u32, height);
        pi.channels = @intCast(u32, channels);

        if (image_data == null) return error.NoMem;

        pi.pitch = pi.width * bits_per_channel * pi.channels / 8;
        pi.raw = image_data[0 .. pi.height * pi.pitch];

        return pi;
    }
};