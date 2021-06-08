const std = @import("std");
const warn = std.debug.warn;
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
const r = @import("rendering.zig");
const za = @import("zalgebra");
const mat4 = za.mat4;
const vec3 = za.vec3;
const stdMath = std.math;
const cos = stdMath.cos;
const sin = stdMath.sin;
const PngImage = @import("png.zig").PngImage;
const obj_loader = @import("loaders/obj.zig");
const Mesh = r.Mesh;
const Cube = r.Cube;
const engine = @import("engine.zig");

// TODO: handle window resizing
const width: i32 = 1024;
const height: i32 = 768;
var last_x: f64 = width / 2;
var last_y: f64 = height / 2;

var window: *c.GLFWwindow = undefined;

var yaw: f32 = -90.0;
var pitch: f32 = 0.0;

const cube_vertices = @import("cube.zig").vertices;
const cube_positions = @import("cube.zig").positions;
// positions of the point lights
const pointLightPositions = [_]vec3 {
    vec3.new( 0.7,  0.2,  2.0),
    vec3.new( 2.3, -3.3, -4.0),
    vec3.new(-4.0,  2.0, -12.0),
    vec3.new( 0.0,  0.0, -3.0)
};

const light_pos = vec3.new(1.2, 1.0, 2.0);

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

// TODO: set up logging and log levels
// refer to this https://github.com/ziglang/zig/blob/master/lib/std/log.zig

fn init() bool {
    _ = c.glfwSetErrorCallback(error_callback);

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

    window = c.glfwCreateWindow(width, height, "Celeritas - demo", null, null) orelse {
        panic("unable to create window\n", .{});
    };

    // c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);  

    _ = c.glfwSetKeyCallback(window, key_callback);
    _ = c.glfwSetCursorPosCallback(window, mouse_callback);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    c.glEnable(c.GL_DEPTH_TEST);  

    return true;
}

pub fn main() !void {
    // create an allocator to use
    const alloc = std.heap.page_allocator;
    const memory = try alloc.alloc(u8, 100);
    defer alloc.free(memory);

    var initialised = init();
    var stats = engine.FrameStats{
        .draw_calls = 0,
        .triangle_count = 0,
        .frame_time = 0
    };

    // ---- meshes
    const asset_model = try obj_loader.load_obj("assets/backpack/backpack.obj");
    // std.debug.print("meshes: {d}\n", .{asset_model.meshes.len});
    // const asset_model = try obj_loader.load_obj("assets/teddy.obj");

    // const num_vertices = @intCast(c_int, asset_model.meshes[0].vertices);
    // const num_indices = @intCast(c_int, asset_model.meshes[0].indices);
    // std.debug.print("\nvertex attrs: {d}\n", .{mesh.vertices});
    // std.debug.print("vertices: {d}\n", .{mesh.vertices / 8});
    // std.debug.print("indices: {d}\n", .{mesh.indices});
    // std.debug.print("triangles: {d}\n", .{mesh.indices / 3});

    // ---- shaders    
    const obj_shader = try r.ShaderProgram.create_from_file("shaders/lit_object.vert", "shaders/lit_object.frag");
    const light_shader = try r.ShaderProgram.create_from_file("shaders/lamp.vert", "shaders/lamp.frag");
    const teddy_shader = try r.ShaderProgram.create_from_file("shaders/teddy.vert", "shaders/teddy.frag");
    
    // ---- textures
    const diffuse = try r.Texture.create("assets/container2.png");
    const specular = try r.Texture.create("assets/container2_specular.png");

    // ---- setup vertex data and attributes
    var VBO: u32 = undefined; // vertex buffer object - send vertex data to vram
    var VBO2: u32 = undefined;
    var objectVAO: u32 = undefined;
    var lightVAO: u32 = undefined;

    // const cube1 = try Cube.create(teddy_shader);

    // TODO: move to one time setup to a separate function
    c.glGenVertexArrays(1, &objectVAO);
    c.glGenBuffers(1, &VBO);
    // ---- Object VAO
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, cube_vertices.len * @sizeOf(c.GLfloat), @ptrCast(*const c_void, &cube_vertices[0]), c.GL_STATIC_DRAW);
    c.glBindVertexArray(objectVAO);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), null); // position
    c.glEnableVertexAttribArray(0);
    const normal_offset = @intToPtr(*const c_void, 3 * @sizeOf(c.GLfloat));
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), normal_offset);
    c.glEnableVertexAttribArray(1);
    const tex_offset = @intToPtr(*const c_void, 6 * @sizeOf(c.GLfloat));
    c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), tex_offset); // texture coord
    c.glEnableVertexAttribArray(2);


    var nbFrames: i32 = 0;
    var last_time: f32 = 0.0;

    var mesh_index: usize = 0;
    // ---- Render loop
    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        stats.draw_calls = 0; // reset frame stats

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

        nbFrames += 1;
        if ( currentFrame - last_time >= 2.0 ){
            std.debug.print("{d} ms/frame \n", .{ 1000.0 / @intToFloat(f32, nbFrames)});
            nbFrames = 0;
            last_time += 1.0;
            mesh_index += 1;
        }

        // ---- input
        process_input(window);

        // ---- render
        c.glClearColor(0.1, 0.1, 0.1, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);

        c.glPolygonMode(c.GL_FRONT_AND_BACK, c.GL_LINE );

        // view/projection transformations
        const projection = mat4.perspective(45.0, (@intToFloat(f32,width) / @intToFloat(f32, height)), 0.1, 100.0);
        const view = mat4.look_at(camera.pos, vec3.add(camera.pos, camera.front), camera.up);

        // render a cube
        c.glUseProgram(teddy_shader.program_id);
        var model = mat4.identity();
        // model = model.scale(cube1.scale); 
        // model = model.translate(cube1.translation);
        teddy_shader.setMat4("model", model);
        teddy_shader.setMat4("view", view);
        teddy_shader.setMat4("projection", projection);
        // cube1.draw(&stats);

        // render a teddy
        c.glUseProgram(teddy_shader.program_id);
        model = mat4.identity();
        model = model.scale(vec3.new(0.7, 0.7, 0.7));
        // model = model.translate(vec3.new(1.0, 1.0, 4.0));
        teddy_shader.setMat4("model", model);
        teddy_shader.setMat4("view", view);
        teddy_shader.setMat4("projection", projection);
        asset_model.meshes[mesh_index].draw();
        

        // glfw: swap buffers and poll IO events (keys pressed/released, mouse moved etc.)
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

// callbacks
fn error_callback(err: c_int, description: [*c]const u8) callconv(.C) void {
    panic("Error: {s}\n", .{description});
}
fn key_callback(win: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
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