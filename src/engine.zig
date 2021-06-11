const std = @import("std");

pub const EngineStats = struct {
    alive_time: u32,
    memory_allocated: u32
};

pub const FrameStats = struct {
    drawcall_count: u32,
    shader_switch_count: u32,
    triangle_count: u32,
    frame_time: u32,

    pub fn print_drawcalls(stats: FrameStats) void {
        std.debug.print("Drawcalls: {d}\n", .{stats.drawcall_count});
    }
};