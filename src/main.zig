const std = @import("std");
const warn = std.debug.warn;
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
const r = @import("rendering.zig");
const m = @import("maths.zig");
const p = @import("physics.zig");
const stdMath = std.math;
const PngImage = @import("png.zig").PngImage;

const width: i32 = 1024;
const height: i32 = 768;
var window: *c.GLFWwindow = undefined;

const vertices = [_]f32{
    // positions          // colors           // texture coords
     0.5,  0.5, 0.0,   1.0, 0.0, 0.0,   1.0, 1.0,   // top right
     0.5, -0.5, 0.0,   0.0, 1.0, 0.0,   1.0, 0.0,   // bottom right
    -0.5, -0.5, 0.0,   0.0, 0.0, 1.0,   0.0, 0.0,   // bottom left
    -0.5,  0.5, 0.0,   1.0, 1.0, 0.0,   0.0, 1.0    // top left 
};

const indices = [_]u32{  
    0, 1, 3, // first triangle
    1, 2, 3  // second triangle
};

fn errorCallback(err: c_int, description: [*c]const u8) callconv(.C) void {
    panic("Error: {s}\n", .{description});
}

fn keyCallback(win: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (action != c.GLFW_PRESS) return;

    switch (key) {
        c.GLFW_KEY_ESCAPE => c.glfwSetWindowShouldClose(win, c.GL_TRUE),
        else => {},
    }
}

fn perspectiveGL(fovY: f64, aspect: f64, zNear: f64, zFar: f64) void {
    const fH = std.math.tan(fovY / 360 * std.math.pi) * zNear;
    const fW = fH * aspect;
    c.glFrustum(-fW, fW, -fH, fH, zNear, zFar);
}

fn init_gl() void {
    c.glClearColor(0.8, 0.8, 0.8, 1.0);
}

fn init() bool {
    _ = c.glfwSetErrorCallback(errorCallback);

    if (c.glfwInit() == c.GL_FALSE) {
        warn("Failed to initialize GLFW\n", .{});
        return false;
    }
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    // TODO: Investigate what this does
    // c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, debug_gl.is_on);
    // c.glfwWindowHint(c.GLFW_SAMPLES, 4);                // 4x antialiasing

    window = c.glfwCreateWindow(width, height, "Hey tfrom a window!", null, null) orelse {
        panic("unable to create window\n", .{});
    };

    _ = c.glfwSetKeyCallback(window, keyCallback);
    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    init_gl();
    return true;
}

pub fn main() !void {
    // create an allocator to use
    const alloc = std.heap.page_allocator;
    const memory = try alloc.alloc(u8, 100);
    defer alloc.free(memory);

    var initialised = init();

    var vertex_file = try std.fs.cwd().openFile("src/base.vert", .{});
    defer vertex_file.close();
    
    const vertex_source = try vertex_file.reader().readAllAlloc(
        alloc,
        10000,
    );
    defer alloc.free(vertex_source);

    var fragment_file = try std.fs.cwd().openFile("src/base.frag", .{});
    defer fragment_file.close();
    
    const fragment_source = try fragment_file.reader().readAllAlloc(
        alloc,
        10000,
    );
    defer alloc.free(fragment_source);

    const tex_file = try std.fs.cwd().openFile("src/wall.png", .{});
    const tex_buffer = try tex_file.reader().readAllAlloc(
        alloc,
        1000000,
    );
    defer alloc.free(tex_buffer);
    var tex_png = try PngImage.create(tex_buffer);
    var texture: u32 = undefined;
    c.glGenTextures(1, &texture);
    c.glBindTexture(c.GL_TEXTURE_2D, texture);

    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA,
        @intCast(c_int, tex_png.width),
        @intCast(c_int, tex_png.height),
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        @ptrCast(*c_void, &tex_png.raw[0]),
    );
    c.glGenerateMipmap(c.GL_TEXTURE_2D);

    const shader = try r.ShaderProgram.create(vertex_source, fragment_source);

    var VBO: u32 = undefined; // vertex buffer object - send vertex data to vram
    var VAO: u32 = undefined; // vertex array object - save vertex attribute configurations 
    var EBO: u32 = undefined;

    // TODO: move to one time setup to a separate function
    c.glGenVertexArrays(1, &VAO);
    c.glGenBuffers(1, &VBO);
    c.glGenBuffers(1, &EBO);
    c.glBindVertexArray(VAO);

    // load vertices
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, 8 * 4 * @sizeOf(c.GLfloat), @ptrCast(*const c_void, &vertices[0]), c.GL_STATIC_DRAW);
    // load indices
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, EBO);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, 6 * @sizeOf(c.GLint), @ptrCast(*const c_void, &indices[0]), c.GL_STATIC_DRAW);

    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), null); // position
    c.glEnableVertexAttribArray(0);
    const color_offset = @intToPtr(*const c_void, 3 * @sizeOf(c.GLfloat));
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), color_offset); // color
    c.glEnableVertexAttribArray(1);

    const tex_offset = @intToPtr(*const c_void, 6 * @sizeOf(c.GLfloat));
    c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), tex_offset); // texture coord
    c.glEnableVertexAttribArray(2);

    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        c.glClearColor(0.2, 0.3, 0.3, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        c.glBindTexture(c.GL_TEXTURE_2D, texture);
        c.glUseProgram(shader.program_id);
        c.glBindVertexArray(VAO);
        c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

}