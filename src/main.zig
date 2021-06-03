const std = @import("std");
const warn = std.debug.warn;
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
const r = @import("rendering.zig");
const m = @import("zlm");
const p = @import("physics.zig");
const za = @import("zalgebra");
const mat4 = za.mat4;
const vec3 = za.vec3;
// TODO: move these imports into a common imports ?
const stdMath = std.math;
const cos = stdMath.cos;
const sin = stdMath.sin;
const PngImage = @import("png.zig").PngImage;

const width: i32 = 1024;
const height: i32 = 768;
var window: *c.GLFWwindow = undefined;

var last_x: f64 = 512.0;
var last_y: f64 = 384.0;

var yaw: f32 = -90.0;
var pitch: f32 = 0.0;

const cube_vertices = @import("cube.zig").vertices;

const vertices = [_]f32{
    // positions          // texture coords
     0.5,  0.5, 0.0,      1.0, 1.0,   // top right
     0.5, -0.5, 0.0,      1.0, 0.0,   // bottom right
    -0.5, -0.5, 0.0,      0.0, 0.0,   // bottom left
    -0.5,  0.5, 0.0,      0.0, 1.0    // top left 
};

const indices = [_]u32{  
    0, 1, 3, // first triangle
    1, 2, 3  // second triangle
};

var camera = r.Camera.create(
    vec3.new(0.0, 0.0, 3.0),
    vec3.new(0.0, 0.0, -1.0),
    vec3.new(0.0, 1.0, 0.0)
);

var delta_time: f64 = 0.0;
var last_frame: f64 = 0.0;

fn errorCallback(err: c_int, description: [*c]const u8) callconv(.C) void {
    panic("Error: {s}\n", .{description});
}

fn keyCallback(win: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const camera_speed = @floatCast(f32, 5.0 * delta_time);
    if (action == c.GLFW_PRESS) {
        switch (key) {
            c.GLFW_KEY_ESCAPE => c.glfwSetWindowShouldClose(win, c.GL_TRUE),
            c.GLFW_KEY_W => camera.pos = vec3.add(camera.pos, camera.front.scale(camera_speed)),
            c.GLFW_KEY_S => camera.pos = vec3.sub(camera.pos, camera.front.scale(camera_speed)),
            c.GLFW_KEY_A => {
                camera.pos = vec3.sub(camera.pos, vec3.scale(vec3.cross(camera.front, camera.up), camera_speed));
            },
            c.GLFW_KEY_D => {
                camera.pos = vec3.add(camera.pos, vec3.scale(vec3.cross(camera.front, camera.up), camera_speed));
            },
            else => {}
        }
    }
    return;
}

fn mouse_callback(win: ?*c.GLFWwindow, x_pos: f64, y_pos: f64) callconv(.C) void {
    var x_offset = x_pos - last_x;
    var y_offset = last_y - y_pos;
    last_x = x_pos;
    last_y = y_pos;

    const sensitivity = 0.1;
    x_offset = x_offset * sensitivity;
    y_offset = y_offset * sensitivity;

    yaw += @floatCast(f32, x_offset);
    pitch += @floatCast(f32, y_offset);

    if (pitch > 89.0)
        pitch =  89.0;
    if (pitch < -89.0)
        pitch = -89.0;
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
    // c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);

    window = c.glfwCreateWindow(width, height, "Hey tfrom a window!", null, null) orelse {
        panic("unable to create window\n", .{});
    };

    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);  

    _ = c.glfwSetKeyCallback(window, keyCallback);
    _ = c.glfwSetCursorPosCallback(window, mouse_callback);

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
    c.glEnable(c.GL_DEPTH_TEST);  


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
    // var EBO: u32 = undefined; // element buffer object - store indices for indexed drawing

    // TODO: move to one time setup to a separate function
    c.glGenVertexArrays(1, &VAO);
    c.glGenBuffers(1, &VBO);
    // c.glGenBuffers(1, &EBO);
    c.glBindVertexArray(VAO);

    // load vertices
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, cube_vertices.len * @sizeOf(c.GLfloat), @ptrCast(*const c_void, &cube_vertices[0]), c.GL_STATIC_DRAW);
    // load indices
    // c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, EBO);
    // c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, 6 * @sizeOf(c.GLint), @ptrCast(*const c_void, &indices[0]), c.GL_STATIC_DRAW);

    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(c.GLfloat), null); // position
    c.glEnableVertexAttribArray(0);

    const tex_offset = @intToPtr(*const c_void, 3 * @sizeOf(c.GLfloat));
    c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(c.GLfloat), tex_offset); // texture coord
    c.glEnableVertexAttribArray(1);

    var nbFrames: i32 = 0;
    var last_time: f32 = 0.0;
    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        const currentFrame = c.glfwGetTime();
        delta_time = currentFrame - last_frame;
        last_frame = currentFrame;

        // TODO: refactor variable names
        nbFrames += 1;
        if ( currentFrame - last_time >= 1.0 ){
            std.debug.print("{d} ms/frame \n", .{ 1000.0 / @intToFloat(f32, nbFrames)});
            nbFrames = 0;
            last_time += 1.0;
        }

        c.glClearColor(0.2, 0.3, 0.3, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);

        c.glBindTexture(c.GL_TEXTURE_2D, texture);

        var trans = mat4.identity();
        trans = trans.translate(vec3.new(0.5, 0.5, 0.0));
        trans = trans.rotate(@floatCast(f32, c.glfwGetTime()) * 5.0, vec3.new(0.0, 0.0, 1.0));
        trans = trans.scale(vec3.new(0.5, 0.5, 0.5));

        var model = mat4.identity();
        model = model.rotate(-55.0, vec3.new(1.0, 0.0, 0.0));
        model = model.rotate(@floatCast(f32, c.glfwGetTime()) * 9.0, vec3.new(0.0, 0.0, 1.0));

        // camera
        var direction = vec3.new(0.0, 0.0, 0.0);
        direction.x = cos(za.to_radians(yaw)) * cos(za.to_radians(pitch));
        direction.y = sin(za.to_radians(pitch));
        direction.z = sin(za.to_radians(yaw)) * cos(za.to_radians(pitch));
        camera.front = vec3.norm(direction);

        const view = mat4.look_at(camera.pos, vec3.add(camera.pos, camera.front), camera.up);

        var projection = mat4.perspective(45.0, 1024.0 / 768.0, 0.1, 100.0);

        c.glUseProgram(shader.program_id);

        const transformLoc = c.glGetUniformLocation(shader.program_id, "transform");
        c.glUniformMatrix4fv(transformLoc, 1, c.GL_FALSE, trans.get_data());
        const modelLoc = c.glGetUniformLocation(shader.program_id, "model");
        c.glUniformMatrix4fv(modelLoc, 1, c.GL_FALSE, model.get_data());
        const viewLoc = c.glGetUniformLocation(shader.program_id, "view");
        c.glUniformMatrix4fv(viewLoc, 1, c.GL_FALSE, view.get_data());
        const projectionLoc = c.glGetUniformLocation(shader.program_id, "projection");
        c.glUniformMatrix4fv(projectionLoc, 1, c.GL_FALSE, projection.get_data());


        c.glBindVertexArray(VAO);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 36);

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

}