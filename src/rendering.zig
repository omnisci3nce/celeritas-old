const std = @import("std");
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
const za = @import("zalgebra");
const mat4 = za.mat4;
const vec3 = za.vec3;
const PngImage = @import("png.zig").PngImage;

pub const Camera = struct {
    pos: vec3,
    front: vec3,
    up: vec3,

    pub fn create(pos: vec3, front: vec3, up: vec3) Camera {
        var cam: Camera = undefined;
        cam.pos = pos;
        cam.front = front;
        cam.up = up;
        return cam;
    }
};

pub const Material = struct {
    ambient: vec3,
    diffuse: vec3,
    specular: vec3,
    shininess: float,
    pub fn create(ambient: vec3, diffuse: vec3, specular: vec3, shininess: float) Material {
        return Material{
            .ambient = ambient,
            .diffuse = diffuse,
            .specular = specular,
            .shininess = shininess,
        };
    }
};

pub const Texture = struct {
    texture_id: u32,
    loaded: bool,

    pub fn create(file_path: []const u8) !Texture {
        var tex: Texture = undefined;
        const alloc = c_allocator; // TODO: CHANGE

        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const buffer = try file.reader().readAllAlloc(alloc, 1000000); // TODO: take an allocator in. change max texture buffer size
        defer alloc.free(buffer);

        var png = try PngImage.create(buffer);

        c.glGenTextures(1, &tex.texture_id);
        c.glBindTexture(c.GL_TEXTURE_2D, tex.texture_id);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);

        // actually load the texture
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(c_int, png.width),
            @intCast(c_int, png.height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            @ptrCast(*c_void, &png.raw[0]),
        );
        c.glGenerateMipmap(c.GL_TEXTURE_2D);

        return tex;
    }

    // TODO: add cleanup function
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
    pub fn setVec3(sp: ShaderProgram, name: []const u8, x: f32, y: f32, z: f32) void {
        const location = c.glGetUniformLocation(sp.program_id, name.ptr);
        c.glUniform3f(location, x, y, z);
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