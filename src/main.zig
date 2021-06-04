const std = @import("std");
const warn = std.debug.warn;
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
const r = @import("rendering.zig");
const za = @import("zalgebra");
const mat4 = za.mat4;
const vec3 = za.vec3;
// TODO: move these imports into a common imports ?
const stdMath = std.math;
const cos = stdMath.cos;
const sin = stdMath.sin;
const PngImage = @import("png.zig").PngImage;

// TODO: handle window resizing
const width: i32 = 1024;
const height: i32 = 768;
var last_x: f64 = width / 2;
var last_y: f64 = height / 2;

var window: *c.GLFWwindow = undefined;


var yaw: f32 = -90.0;
var pitch: f32 = 0.0;

const cube_vertices = @import("cube.zig").vertices;

const light_pos = vec3.new(6.0, 1.0, 4.0);

const indices = [_]u32{  
    0, 1, 3, // first triangle
    1, 2, 3  // second triangle
};

var camera = r.Camera.create(
    vec3.new(0.5, 1.0, 3.0),
    vec3.new(0.0, 0.0, -1.0),
    vec3.new(0.0, 1.0, 0.0)
);

var delta_time: f64 = 0.0;
var last_frame: f64 = 0.0;

fn errorCallback(err: c_int, description: [*c]const u8) callconv(.C) void {
    panic("Error: {s}\n", .{description});
}

fn keyCallback(win: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (action == c.GLFW_PRESS) {
        switch (key) {
            c.GLFW_KEY_ESCAPE => c.glfwSetWindowShouldClose(win, c.GL_TRUE),
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
    c.glfwWindowHint(c.GLFW_COCOA_RETINA_FRAMEBUFFER, c.GL_FALSE);
    // TODO: Investigate what this does
    // c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, debug_gl.is_on);
    // c.glfwWindowHint(c.GLFW_SAMPLES, 4);                // 4x antialiasing

    window = c.glfwCreateWindow(width, height, "Hey tfrom a window!", null, null) orelse {
        panic("unable to create window\n", .{});
    };

    var framebufferHeight: i32  = undefined;
    var framebufferWidth: i32  = undefined;
    // c.glfwGetFramebufferSize(window, &framebufferWidth, &framebufferHeight);
    // c.glViewport(0, 0, framebufferWidth, framebufferHeight);

    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);  

    _ = c.glfwSetKeyCallback(window, keyCallback);
    _ = c.glfwSetCursorPosCallback(window, mouse_callback);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    return true;
}

pub fn main() !void {
    // create an allocator to use
    const alloc = std.heap.page_allocator;
    const memory = try alloc.alloc(u8, 100);
    defer alloc.free(memory);

    var initialised = init();
    c.glEnable(c.GL_DEPTH_TEST);  

    // TODO: move shaders to their own folder
    var vertex_file = try std.fs.cwd().openFile("src/cube.vert", .{});
    defer vertex_file.close();
    
    const vertex_source = try vertex_file.reader().readAllAlloc(
        alloc,
        10000,
    );
    defer alloc.free(vertex_source);

    var obj_fragment_file = try std.fs.cwd().openFile("src/cube.frag", .{});
    defer obj_fragment_file.close();
    
    const obj_fragment_source = try obj_fragment_file.reader().readAllAlloc(
        alloc,
        10000,
    );
    defer alloc.free(obj_fragment_source);

    var light_vertex_file = try std.fs.cwd().openFile("src/light.vert", .{});
    defer light_vertex_file.close();
    
    const light_vertex_source = try light_vertex_file.reader().readAllAlloc(
        alloc,
        10000,
    );
    defer alloc.free(light_vertex_source);

    var light_fragment_file = try std.fs.cwd().openFile("src/light.frag", .{});
    defer light_fragment_file.close();
    
    const light_fragment_source = try light_fragment_file.reader().readAllAlloc(
        alloc,
        10000,
    );
    defer alloc.free(light_fragment_source);

    const obj_shader = try r.ShaderProgram.create(vertex_source, obj_fragment_source);
    const light_shader = try r.ShaderProgram.create(light_vertex_source, light_fragment_source);

    var VBO: u32 = undefined; // vertex buffer object - send vertex data to vram
    var objectVAO: u32 = undefined; // vertex array object - save vertex attribute configurations 
    var lightVAO: u32 = undefined;

    // TODO: move to one time setup to a separate function

    c.glGenVertexArrays(1, &objectVAO);
    c.glGenBuffers(1, &VBO);
    // ---- Object VAO
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, cube_vertices.len * @sizeOf(c.GLfloat), @ptrCast(*const c_void, &cube_vertices[0]), c.GL_STATIC_DRAW);
    c.glBindVertexArray(objectVAO);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(c.GLfloat), null); // position
    c.glEnableVertexAttribArray(0);
    const normal_offset = @intToPtr(*const c_void, 3 * @sizeOf(c.GLfloat));
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(c.GLfloat), normal_offset);
    c.glEnableVertexAttribArray(1);

    // ---- Light VAO
    c.glGenVertexArrays(1, &lightVAO);
    c.glBindVertexArray(lightVAO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(c.GLfloat), null);
    c.glEnableVertexAttribArray(0);


    var nbFrames: i32 = 0;
    var last_time: f32 = 0.0;
    // ---- Render loop
    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        // camera
        var direction = vec3.new(0.0, 0.0, 0.0);
        direction.x = cos(za.to_radians(yaw)) * cos(za.to_radians(pitch));
        direction.y = sin(za.to_radians(pitch));
        direction.z = sin(za.to_radians(yaw)) * cos(za.to_radians(pitch));
        camera.front = vec3.norm(direction);        

        // ---- per-frame time logic
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

        // ---- input
        process_input(window);

        // ---- render
        c.glClearColor(0.1, 0.1, 0.1, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);

        // -- object
        c.glUseProgram(obj_shader.program_id);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "objectColor"), 1.0, 0.5, 0.31);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "lightColor"), 1.0, 1.0, 1.0);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "lightPos"), light_pos.x, light_pos.y, light_pos.z);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "viewPos"), camera.pos.x, camera.pos.y, camera.pos.z);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "material.ambient"), 1.0, 0.5, 0.31);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "material.diffuse"), 1.0, 0.5, 0.31);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "material.specular"), 0.5, 0.5, 0.5);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "material.shininess"), 32.0);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "light.ambient"), 0.2, 0.2, 0.2);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "light.diffuse"), 0.5, 0.5, 0.5);
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "light.specular"), 1.0, 1.0, 1.0);

        const view = mat4.look_at(camera.pos, vec3.add(camera.pos, camera.front), camera.up);
        const projection = mat4.perspective(45.0, (@intToFloat(f32,width) / @intToFloat(f32, height)), 0.1, 100.0);
        const viewLoc = c.glGetUniformLocation(obj_shader.program_id, "view");
        c.glUniformMatrix4fv(viewLoc, 1, c.GL_FALSE, view.get_data());
        const projectionLoc = c.glGetUniformLocation(obj_shader.program_id, "projection");
        c.glUniformMatrix4fv(projectionLoc, 1, c.GL_FALSE, projection.get_data());

        var model = mat4.identity();
        // model = model.scale(vec3.new(0.5, 0.5, 0.5));
        var modelLoc = c.glGetUniformLocation(obj_shader.program_id, "model");
        c.glUniformMatrix4fv(modelLoc, 1, c.GL_FALSE, model.get_data());

        c.glBindVertexArray(objectVAO);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 36);

        // -- light (lamp)
        c.glUseProgram(light_shader.program_id);
        c.glUniformMatrix4fv(c.glGetUniformLocation(light_shader.program_id, "projection"), 1, c.GL_FALSE, projection.get_data());
        c.glUniformMatrix4fv(c.glGetUniformLocation(light_shader.program_id, "view"), 1, c.GL_FALSE, view.get_data());
        model = mat4.identity();
        model = model.translate(light_pos);
        model = model.scale(vec3.new(0.2, 0.2, 0.2));
        c.glUniformMatrix4fv(c.glGetUniformLocation(light_shader.program_id, "model"), 1, c.GL_FALSE, model.get_data());

        // draw lamp
        c.glBindVertexArray(lightVAO);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 36);

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

}

fn process_input(win: ?*c.GLFWwindow) void {
    if (c.glfwGetKey(win, c.GLFW_KEY_ESCAPE) == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, 1);
    }

    const camera_speed = @floatCast(f32, 2.0 * delta_time);

    if (c.glfwGetKey(win, c.GLFW_KEY_W) == c.GLFW_PRESS) {
        camera.pos = vec3.add(camera.pos, camera.front.scale(camera_speed));
    }
    if (c.glfwGetKey(win, c.GLFW_KEY_S) == c.GLFW_PRESS) {
        camera.pos = vec3.sub(camera.pos, camera.front.scale(camera_speed));
    }
    if (c.glfwGetKey(win, c.GLFW_KEY_A) == c.GLFW_PRESS) {
        camera.pos = vec3.sub(camera.pos, vec3.scale(vec3.cross(camera.front, camera.up), camera_speed));
    }
    if (c.glfwGetKey(win, c.GLFW_KEY_D) == c.GLFW_PRESS) {
        camera.pos = vec3.add(camera.pos, vec3.scale(vec3.cross(camera.front, camera.up), camera_speed));
    }
}