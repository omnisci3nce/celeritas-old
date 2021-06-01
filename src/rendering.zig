const std = @import("std");
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;

const Camera = struct {
    // position
};

pub const ShaderProgram = struct {
    program_id: c.GLuint,
    vertex_id: c.GLuint,
    fragment_id: c.GLuint,

    // take strings of shaders
    pub fn create(vertex_source: []const u8, fragment_source: []const u8) !ShaderProgram {
        var sp: ShaderProgram = undefined;
        sp.vertex_id = try initGLShader(vertex_source, c.GL_VERTEX_SHADER);
        sp.fragment_id = try initGLShader(fragment_source, c.GL_FRAGMENT_SHADER);

        sp.program_id = c.glCreateProgram();
        c.glAttachShader(sp.program_id, sp.vertex_id);
        c.glAttachShader(sp.program_id, sp.fragment_id);
        c.glLinkProgram(sp.program_id);
        return sp;
    }
    // pub fn destroy() {}
};

fn initGLShader(source: []const u8, kind: c.GLenum) !c.GLuint {
    const shader_id = c.glCreateShader(kind);
    const source_ptr: [*]const u8 = source.ptr;
    const source_len = @intCast(c.GLint, source.len);

    c.glShaderSource(shader_id, 1, &source_ptr, &source_len);
    c.glCompileShader(shader_id);

    // error checking
    var ok: c.GLint = undefined;
    c.glGetShaderiv(shader_id, c.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetShaderiv(shader_id, c.GL_INFO_LOG_LENGTH, &error_size);

        // TODO: make calling code pass allocator down
        const message = try c_allocator.alloc(u8, @intCast(usize, error_size));
        c.glGetShaderInfoLog(shader_id, error_size, &error_size, message.ptr);
        panic("Error compiling {s} shader:\n{s}\n", .{ "", message });
    }
    return shader_id;
}