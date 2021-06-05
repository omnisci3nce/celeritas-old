const std = @import("std");
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
// TODO: take allocators as arguments
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

pub const Mesh = struct {
    vbo: u32,
    vao: u32 = 0,
    ebo: u32,

    vertices: usize,
    indices: usize,

    pub fn create(vertices: []f32, indices: []u32) Mesh {
        // generate VBO
        var VBO: u32 = undefined;
        c.glGenBuffers(1, &VBO);
        // upload vertex data
        c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
        c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, vertices.len * @sizeOf(c.GLfloat)), vertices.ptr, c.GL_STATIC_DRAW);

        // generate VAO - vertex attribute object
        var VAO: u32 = undefined;
        c.glGenVertexArrays(1, &VAO);
        // setup attribute pointers
        const stride = 8 * @sizeOf(c.GLfloat);
        c.glBindVertexArray(VAO);
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, null);                // position
        c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @intToPtr(*const c_void, 3 * @sizeOf(c.GLfloat)));    // normal
        c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, stride, @intToPtr(*const c_void, 6 * @sizeOf(c.GLfloat)));    // tex coords
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);

        // generate EBO
        var EBO: u32 = undefined;
        c.glGenBuffers(1, &EBO);
        // upload index data
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, EBO);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, indices.len * @sizeOf(c.GLuint)), indices.ptr, c.GL_STATIC_DRAW);

        // log out some info
        std.debug.print("Mesh created.\n", .{});

        return Mesh{
            .vbo = VBO,
            .vao = VAO,
            .ebo = EBO,
            .vertices = vertices.len,
            .indices = indices.len
        };
    }
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

    pub fn create_from_file(vertex_path: []const u8, fragment_path: []const u8) !ShaderProgram {
        var vertex_file = try std.fs.cwd().openFile(vertex_path, .{});
        defer vertex_file.close();
        
        const vertex_source = try vertex_file.reader().readAllAlloc(
            c_allocator,
            10000,
        );
        defer c_allocator.free(vertex_source);

        var fragment_file = try std.fs.cwd().openFile(fragment_path, .{});
        defer fragment_file.close();
        
        const fragment_source = try fragment_file.reader().readAllAlloc(
            c_allocator,
            10000,
        );
        defer c_allocator.free(fragment_source);

        return ShaderProgram.create(vertex_source, fragment_source);
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