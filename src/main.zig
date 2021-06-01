const std = @import("std");
const warn = std.debug.warn;
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
const r = @import("rendering.zig");
const m = @import("maths.zig");
const p = @import("physics.zig");

const width: i32 = 1024;
const height: i32 = 768;
var window: *c.GLFWwindow = undefined;

const vertices = [_]f32{
    -0.5, -0.5, 0.0,
     0.5, -0.5, 0.0,
     0.0,  0.5, 0.0};

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
    var initialised = init();

    // TODO: move shader source to its own file
    const vertex_source : []const u8  =
    \\ #version 330 core
    \\ layout (location = 0) in vec3 aPos;
    \\ void main()
    \\ {
    \\  gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
    \\ }
    ;
    const vertex_source_ptr: [*]const u8 = vertex_source.ptr;
    const v_source_len = @intCast(c.GLint, vertex_source.len);

    const fragment_source : []const u8 =
    \\ #version 330 core
    \\ out vec4 FragColor;
    \\ void main()
    \\ {
    \\    FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
    \\ } 
    ;
    const fragment_source_ptr: [*]const u8 = fragment_source.ptr;
    const f_source_len = @intCast(c.GLint, fragment_source.len);

    var vertexShader: u32 = c.glCreateShader(c.GL_VERTEX_SHADER);
    c.glShaderSource(vertexShader, 1, &vertex_source_ptr, &v_source_len);
    c.glCompileShader(vertexShader);

    var ok: c.GLint = undefined;
    c.glGetShaderiv(vertexShader, c.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetShaderiv(vertexShader, c.GL_INFO_LOG_LENGTH, &error_size);

        const message = try c_allocator.alloc(u8, @intCast(usize, error_size));
        c.glGetShaderInfoLog(vertexShader, error_size, &error_size, message.ptr);
        panic("Error compiling {s} shader:\n{s}\n", .{ "vertex", message });
    }

    var fragmentShader: u32 = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    c.glShaderSource(fragmentShader, 1, &fragment_source_ptr, &f_source_len);
    c.glCompileShader(fragmentShader);

    c.glGetShaderiv(fragmentShader, c.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetShaderiv(fragmentShader, c.GL_INFO_LOG_LENGTH, &error_size);

        const message = try c_allocator.alloc(u8, @intCast(usize, error_size));
        c.glGetShaderInfoLog(fragmentShader, error_size, &error_size, message.ptr);
        panic("Error compiling {s} shader:\n{s}\n", .{ "fragment", message });
    }

    var shaderProgram: u32 = c.glCreateProgram();
    c.glAttachShader(shaderProgram, vertexShader);
    c.glAttachShader(shaderProgram, fragmentShader);
    c.glLinkProgram(shaderProgram);
    
    c.glGetProgramiv(shaderProgram, c.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetProgramiv(shaderProgram, c.GL_INFO_LOG_LENGTH, &error_size);

        const message = try c_allocator.alloc(u8, @intCast(usize, error_size));
        c.glGetProgramInfoLog(shaderProgram, error_size, &error_size, message.ptr);
        panic("Error linking program:\n{s}\n", .{ message });
    }

    var VBO: u32 = undefined; // vertex buffer object - send vertex data to vram
    var VAO: u32 = undefined; // vertex array object - save vertex attribute configurations 

    // TODO: move one time setup to a separate function
    c.glGenBuffers(1, &VBO);
    c.glGenVertexArrays(1, &VAO);
    c.glBindVertexArray(VAO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, 9 * @sizeOf(c.GLfloat), @ptrCast(*const c_void, &vertices[0]), c.GL_STATIC_DRAW);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 3 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(0);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        c.glClearColor(0.2, 0.3, 0.3, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        c.glUseProgram(shaderProgram);
        c.glBindVertexArray(VAO);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 3);

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

}