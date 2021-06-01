const c = @import("c.zig");

const Camera = struct {
    // position
}

pub const ShaderProgram = struct {
    program_id: c.GLuint,
    vertex_id: c.GLuint,
    fragment_id: c.GLuint,

    // pub fn create() {}
    // pub fn destroy() {}
}

fn initGLShader() !c.GLuint {}