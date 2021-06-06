pub const EngineStats = struct {
    alive_time: u32,
    memory_allocated: u32
};

pub const FrameStats = struct {
    draw_calls: u32,
    triangle_count: u32,
    frame_time: u32
};