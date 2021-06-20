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
    // c.glfwWindowHint(c.GLFW_COCOA_RETINA_FRAMEBUFFER, c.GL_FALSE);
    // TODO: Investigate what this does
    // c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, debug_gl.is_on);
    // c.glfwWindowHint(c.GLFW_SAMPLES, 4);                // 4x antialiasing

    window = c.glfwCreateWindow(width, height, "Celeritas - demo", null, null) orelse {
        panic("unable to create window\n", .{});
    };

    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);  

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
        .drawcall_count = 0,
        .shader_switch_count = 0,
        .triangle_count = 0,
        .frame_time = 0
    };

    // ---- meshes
    const asset_model = try obj_loader.load_obj("assets/backpack/backpack.obj");
    std.debug.print("Num materials: {d}\n", .{asset_model.meshes.len});

    var container_file = try std.fs.cwd().openFile("assets/container2.png", .{});
    defer container_file.close();
    
    const container_src = try container_file.reader().readAllAlloc(
        c_allocator,
        100000000,
    );
    defer c_allocator.free(container_src);

    var container_file2 = try std.fs.cwd().openFile("assets/container2_specular.png", .{});
    defer container_file2.close();
    
    const container_src2 = try container_file2.reader().readAllAlloc(
        c_allocator,
        100000000,
    );
    defer c_allocator.free(container_src2);

    // ---- shaders    
    const lighting_shader = try r.ShaderProgram.create_from_file("shaders/basic_lighting.vert", "shaders/basic_lighting.frag");
    const light_cube_shader = try r.ShaderProgram.create_from_file("shaders/light_cube.vert", "shaders/light_cube.frag");
    

    // ---- textures
    std.debug.print("Loading diffuse container png\n", .{});
    var diffuse = try r.Texture.create(container_src);
    std.debug.print("Loading specular container png\n", .{});
    var specular = try r.Texture.create(container_src2);

    const cube = try Cube.create(light_cube_shader);

    // ---- lights
    const sun = r.DirectionalLight{
        .direction = vec3.new(0.3, -1.0, 0.0),
        .ambient_colour = vec3.new(0.2, 0.2, 0.2),
        .diffuse_colour = vec3.new(0.6, 0.6, 0.6),
        .specular_colour = vec3.new(0.5, 0.5, 0.5)
    };
    
    const point_light_positions = [4]vec3{
        vec3.new(1.5, 1.0, -4.0),
        vec3.new(2.3, -0.3, -2.0),
        vec3.new(-4.0, 2.0, -8.0),
        vec3.new(0.0, -1.0, -3.0),
    };

    var point_lights: [4]r.PointLight = undefined;
    // create point lights
    var i: usize = 0;
    while (i < 4) {
        point_lights[i] = r.PointLight{ 
            .position = point_light_positions[i],
            .constant = 1.0,
            .linear = 0.2,
            .quadratic = 0.064,
            .ambient = vec3.new(0.05, 0.05, 0.05),
            .diffuse = vec3.new(0.8, 0.8, 0.8),
            .specular = vec3.new(1.0, 1.0, 1.0)
        };
        i += 1;
    }
    std.debug.assert(i == 4);

    var nbFrames: i32 = 0;
    var last_time: f32 = 0.0;

    var mesh_index: usize = 0;
    // ---- Render loop
    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        stats.drawcall_count = 0; // reset frame stats

        
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
            // std.debug.print("{d} ms/frame \n", .{ 1000.0 / @intToFloat(f32, nbFrames)});
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

        // c.glPolygonMode(c.GL_FRONT_AND_BACK, c.GL_LINE );

        // view/projection transformations
        const projection = mat4.perspective(45.0, (@intToFloat(f32,width) / @intToFloat(f32, height)), 0.1, 100.0);
        const view = mat4.look_at(camera.pos, vec3.add(camera.pos, camera.front), camera.up);

        // render cubes
        c.glUseProgram(lighting_shader.program_id);
        lighting_shader.setMat4("view", view);
        lighting_shader.setMat4("projection", projection);

        lighting_shader.setVec3("viewPos", camera.pos.x, camera.pos.y, camera.pos.z);
        lighting_shader.setFloat("material.shininess", 32.0);

        // directional light - "sun"
        lighting_shader.setVec3("dirLight.direction", sun.direction.x, sun.direction.y, sun.direction.z);
        lighting_shader.setVec3("dirLight.ambient", 0.2, 0.2, 0.2);
        lighting_shader.setVec3("dirLight.diffuse", 0.6, 0.6, 0.6);
        lighting_shader.setVec3("dirLight.specular", 0.5, 0.5, 0.5);

        // point lights 1-4
        lighting_shader.setVec3("pointLights[0].position", point_light_positions[0].x, point_light_positions[0].y, point_light_positions[0].z);
        lighting_shader.setVec3("pointLights[0].ambient", point_lights[0].ambient.x, point_lights[0].ambient.y, point_lights[0].ambient.z);
        lighting_shader.setVec3("pointLights[0].diffuse", point_lights[0].diffuse.x, point_lights[0].diffuse.y, point_lights[0].diffuse.z);
        lighting_shader.setVec3("pointLights[0].specular", point_lights[0].specular.x, point_lights[0].specular.y, point_lights[0].specular.z);
        lighting_shader.setFloat("pointLights[0].constant", point_lights[0].constant);
        lighting_shader.setFloat("pointLights[0].linear", point_lights[0].linear);
        lighting_shader.setFloat("pointLights[0].quadratic", point_lights[0].quadratic);

        lighting_shader.setVec3("pointLights[1].position", point_light_positions[1].x, point_light_positions[1].y, point_light_positions[1].z);
        lighting_shader.setVec3("pointLights[1].ambient", point_lights[1].ambient.x, point_lights[1].ambient.y, point_lights[1].ambient.z);
        lighting_shader.setVec3("pointLights[1].diffuse", point_lights[1].diffuse.x, point_lights[1].diffuse.y, point_lights[1].diffuse.z);
        lighting_shader.setVec3("pointLights[1].specular", point_lights[1].specular.x, point_lights[1].specular.y, point_lights[1].specular.z);
        lighting_shader.setFloat("pointLights[1].constant", point_lights[1].constant);
        lighting_shader.setFloat("pointLights[1].linear", point_lights[1].linear);
        lighting_shader.setFloat("pointLights[1].quadratic", point_lights[1].quadratic);

        lighting_shader.setVec3("pointLights[2].position", point_light_positions[2].x, point_light_positions[2].y, point_light_positions[2].z);
        lighting_shader.setVec3("pointLights[2].ambient", point_lights[2].ambient.x, point_lights[2].ambient.y, point_lights[2].ambient.z);
        lighting_shader.setVec3("pointLights[2].diffuse", point_lights[2].diffuse.x, point_lights[2].diffuse.y, point_lights[2].diffuse.z);
        lighting_shader.setVec3("pointLights[2].specular", point_lights[2].specular.x, point_lights[2].specular.y, point_lights[2].specular.z);
        lighting_shader.setFloat("pointLights[2].constant", point_lights[2].constant);
        lighting_shader.setFloat("pointLights[2].linear", point_lights[2].linear);
        lighting_shader.setFloat("pointLights[2].quadratic", point_lights[2].quadratic);

        lighting_shader.setVec3("pointLights[3].position", point_light_positions[3].x, point_light_positions[3].y, point_light_positions[3].z);
        lighting_shader.setVec3("pointLights[3].ambient", point_lights[3].ambient.x, point_lights[3].ambient.y, point_lights[3].ambient.z);
        lighting_shader.setVec3("pointLights[3].diffuse", point_lights[3].diffuse.x, point_lights[3].diffuse.y, point_lights[3].diffuse.z);
        lighting_shader.setVec3("pointLights[3].specular", point_lights[3].specular.x, point_lights[3].specular.y, point_lights[3].specular.z);
        lighting_shader.setFloat("pointLights[3].constant", point_lights[3].constant);
        lighting_shader.setFloat("pointLights[3].linear", point_lights[3].linear);
        lighting_shader.setFloat("pointLights[3].quadratic", point_lights[3].quadratic);

        // bind diffuse map
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glUniform1i(c.glGetUniformLocation(lighting_shader.program_id, "material.diffuse"), 0); 
        c.glBindTexture(c.GL_TEXTURE_2D, diffuse.texture_id);
        c.glActiveTexture(c.GL_TEXTURE1);
        c.glUniform1i(c.glGetUniformLocation(lighting_shader.program_id, "material.specular"), 1); 
        c.glBindTexture(c.GL_TEXTURE_2D, specular.texture_id);

        // floor
        var model = mat4.identity().scale(vec3.new(8.0, 1.0, 8.0)).translate(vec3.new(1.0, -2.0, -4.0));
        lighting_shader.setMat4("model", model);
        cube.draw(&stats);

        // middle cube
        model = mat4.identity().translate(vec3.new(1.0, -1.0, -4.0));
        lighting_shader.setMat4("model", model);
        cube.draw(&stats);

        // wall cube
        model = mat4.identity().scale(vec3.new(5.0, 3.0, 1.0)).translate(vec3.new(1.0, 0.0, -8.5));
        lighting_shader.setMat4("model", model);
        cube.draw(&stats);

        // wall cube 2
        model = mat4.identity();
        model = model.scale(vec3.new(1.0, 3.0, 4.0));
        model = model.rotate(0, vec3.new(1.0, 0.0, 0.0));
        model = model.rotate(90, vec3.new(0.0, 1.0, 0.0));
        model = model.rotate(0, vec3.new(0.0, 0.0, 1.0));
        model = model.translate(vec3.new(4.0, 0.0, -6.0));
        lighting_shader.setMat4("model", model);
        cube.draw(&stats);

        // backpack
        model = mat4.identity();
        model = model.scale(vec3.new(0.1, 0.1, 0.1));
        model = model.rotate(180, vec3.new(0.0, 1.0, 0.0));
        model = model.translate(vec3.new(0.0, 2.0, 0.0));
        lighting_shader.setMat4("model", model);
        asset_model.draw(lighting_shader.program_id);

        // render lights
        c.glUseProgram(light_cube_shader.program_id);
        var l_i: usize = 0;
        while (l_i < 4) {
            model = mat4.identity();
            model = model.scale(vec3.new(0.2, 0.2, 0.2));
            model = model.translate(point_light_positions[l_i]);
            light_cube_shader.setMat4("view", view);
            light_cube_shader.setMat4("projection", projection);
            light_cube_shader.setMat4("model", model);
            cube.draw(&stats);
            l_i += 1;
        }

        // stats.print_drawcalls();

        // glfw: swap buffers and poll IO events (keys pressed/released, mouse moved etc.)
        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }
}

fn process_input(win: ?*c.GLFWwindow) void {
    if (c.glfwGetKey(win, c.GLFW_KEY_ESCAPE) == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, 1);
    }

    const camera_speed = @floatCast(f32, 4.0 * delta_time);

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