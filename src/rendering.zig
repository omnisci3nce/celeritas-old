const std = @import("std");
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
// TODO: take allocators as arguments
const za = @import("zalgebra");
const mat4 = za.mat4;
const vec3 = za.vec3;
const PngImage = @import("png.zig").PngImage;
const cube_vertices = @import("cube.zig").vertices;
const FrameStats = @import("engine.zig").FrameStats;

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

pub const DirectionalLight = struct {
    direction: vec3,
    ambient_colour: vec3,
    diffuse_colour: vec3,
    specular_colour: vec3
};

pub const PointLight = struct {
    position: vec3,

    constant: f32,
    linear: f32,
    quadratic: f32,
    
    ambient: vec3,
    diffuse: vec3,
    specular: vec3
};

pub const SpotLight = struct {
    
};

pub const Material = struct {
    name: []const u8,
    ambient_texture: ?Texture  = null,
    diffuse_texture: ?Texture  = null,
    specular_texture: ?Texture = null,
    ambient_colour: vec3       = vec3.zero(),
    diffuse_colour: vec3       = vec3.zero(),
    specular_colour: vec3      = vec3.zero(),
    specular_exponent: f32     = 32.0,
    transparency: f32          = 1.0,

    pub fn print (m: Material) void { // debug print
        std.debug.print(
            \\ Material:
            \\  name: {s}
            \\  ambient colour: {any}
            \\  diffuse colour: {any}
            \\  specular colour: {any}
            \\  specular strength: {d}
            \\
        , .{m.name, m.ambient_colour, m.diffuse_colour, m.specular_colour, m.specular_exponent});
        if (m.diffuse_texture) |dtm| {
            std.debug.print("  diffuse texture map: {any} - {any}\n", .{ dtm.texture_id, dtm.loaded});
        }
    }
};

pub const Texture = struct {
    texture_id: u32,
    loaded: bool,

    pub fn create(text: []const u8) !Texture {
        var tex: Texture = undefined;
        const alloc = c_allocator; // TODO: CHANGE

        // const file = try std.fs.cwd().openFile(file_path, .{});
        // defer file.close();

        // const buffer = try file.reader().readAllAlloc(alloc, 1000000000); // TODO: take an allocator in. change max texture buffer size
        // defer alloc.free(buffer);

        var png = try PngImage.create(text);

        c.glGenTextures(1, &tex.texture_id);
        c.glBindTexture(c.GL_TEXTURE_2D, tex.texture_id);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR_MIPMAP_LINEAR);
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

        tex.loaded = true;

        std.debug.print("Created Texture: {d}\n", .{tex.texture_id});

        return tex;
    }

    // TODO: add cleanup function
};

pub const Mesh = struct {
    vbo: u32,
    vao: u32 = 0,
    ebo: ?u32,

    vertices: usize,
    indices: usize,

    // TODO: make indices option. if passed in make an ebo, otherwise just load vertices in (e.g. cube.zig)
    pub fn create(vertices: []f32, indices: ?[]u32) Mesh {
        // generate VBO
        var VBO: u32 = undefined;
        c.glGenBuffers(1, &VBO);
        // upload vertex data
        c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
        c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, vertices.len * @sizeOf(c.GLfloat)), vertices.ptr, c.GL_STATIC_DRAW);
        // std.debug.print("vertices = {any}\n", .{vertices.len / 8}); // 8 floats per geometry vertex
        // std.debug.print("vertices array {any}\n", .{vertices});
        // std.debug.print("indices array {any}\n", .{indices});
        // generate VAO - vertex attribute object
        var VAO: u32 = undefined;
        c.glGenVertexArrays(1, &VAO);
        // setup attribute pointers
        const stride = 8 * @sizeOf(c.GLfloat);
        c.glBindVertexArray(VAO);
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, null);                                                // position
        c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @intToPtr(*const c_void, 3 * @sizeOf(c.GLfloat)));    // normal
        c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, stride, @intToPtr(*const c_void, 6 * @sizeOf(c.GLfloat)));    // tex coords
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);

        // generate EBO
        var EBO: u32 = undefined;
        if (indices) |_indices| { // only do this if we provided indices to the constructor
            c.glGenBuffers(1, &EBO);
            // upload index data
            c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, EBO);
            c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, _indices.len * @sizeOf(c.GLuint)), _indices.ptr, c.GL_STATIC_DRAW);
            // std.debug.print("triangles = {any}\n", .{_indices.len / 3}); // 3 indices per triangle
        }

        // std.debug.print("Mesh created.\n", .{});

        return Mesh{
            .vbo = VBO,
            .vao = VAO,
            .ebo = if (indices != null) EBO else null,
            .vertices = vertices.len,
            .indices = if (indices != null) indices.?.len else 0
        };
    }

    pub fn draw(mesh: Mesh) void {
        c.glBindVertexArray(mesh.vao);
        if (mesh.ebo != null) {
            c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, mesh.indices), c.GL_UNSIGNED_INT, null);
        } else {
            c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(c_int, mesh.vertices / 8));
        }
    }
};

pub const Model = struct {
    meshes: []Mesh,
    materials: []Material,
    use_gamma_correction: bool,

    pub fn draw(m: Model) void {
        for (m.meshes) |mesh| {
            mesh.draw();
        } 
    }
};

pub const ShaderProgram = struct {
    program_id: c.GLuint,
    vertex_id: c.GLuint,
    fragment_id: c.GLuint,

    // TODO: accept an allocator
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

    pub fn setVec3(sp: ShaderProgram, name: []const u8, x: f32, y: f32, z: f32) void {
        const location = c.glGetUniformLocation(sp.program_id, name.ptr);
        c.glUniform3f(location, x, y, z);
    }

    pub fn setFloat(sp: ShaderProgram, name: []const u8, value: f32) void {
        const location = c.glGetUniformLocation(sp.program_id, name.ptr);
        c.glUniform1f(location, value);
    }

    pub fn setMat4(sp: ShaderProgram, name: []const u8, value: mat4) void {
        const location = c.glGetUniformLocation(sp.program_id, name.ptr);
        c.glUniformMatrix4fv(location, 1, c.GL_FALSE, value.get_data());
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

pub const Cube = struct {
    mesh: Mesh,
    shader: ShaderProgram,
    translation: vec3,
    rotation: vec3,
    scale: vec3,

    pub fn create(shader: ShaderProgram) !Cube {
        // load cube verts
        const verts = try c_allocator.alloc(f32, cube_vertices.len);
        defer c_allocator.free(verts);
        std.mem.copy(f32, verts, cube_vertices[0..]);
        const mesh = Mesh.create(verts, null);

        return Cube{
            .mesh = mesh,
            .shader = shader,
            .translation = vec3.one(),
            .rotation = vec3.one(),
            .scale = vec3.one()
        };
    }

    pub fn draw(cube: Cube, s: *FrameStats) void {
        c.glBindVertexArray(cube.mesh.vao);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 36); // cubes have 36 vertices
        s.drawcall_count += 1;
    }

    // TODO: pub fn destroy() void {}
};