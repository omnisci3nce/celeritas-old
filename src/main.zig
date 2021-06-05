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
const obj_loader = @import("obj.zig");
const Mesh = obj_loader.Mesh;

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

    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);  

    _ = c.glfwSetKeyCallback(window, key_callback);
    _ = c.glfwSetCursorPosCallback(window, mouse_callback);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    c.glEnable(c.GL_DEPTH_TEST);  

    return true;
}

pub fn main() !void {
    const mesh = try obj_loader.load_obj("assets/teddy.obj");
    const num_vertices = @intCast(c_int, mesh.vertices.len);
    const num_indices = @intCast(c_int, mesh.indices.len);
    std.debug.print("vertices: {d}\n", .{num_vertices});
    std.debug.print("indices: {d}\n", .{num_indices});

    // create an allocator to use
    const alloc = std.heap.page_allocator;
    const memory = try alloc.alloc(u8, 100);
    defer alloc.free(memory);

    var initialised = init();

    // ---- shaders    
    const obj_shader = try r.ShaderProgram.create_from_file("shaders/lit_object.vert", "shaders/lit_object.frag");
    const light_shader = try r.ShaderProgram.create_from_file("shaders/lamp.vert", "shaders/lamp.frag");
    
    // ---- textures
    const diffuse = try r.Texture.create("assets/container2.png");
    const specular = try r.Texture.create("assets/container2_specular.png");

    // ---- setup vertex data and attributes
    var VBO: u32 = undefined; // vertex buffer object - send vertex data to vram
    var VBO2: u32 = undefined;
    var objectVAO: u32 = undefined; // vertex array object - save vertex attribute configurations 
    var lightVAO: u32 = undefined;

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

    // ---- Light VAO
    var EBO: u32 = undefined;
    c.glGenBuffers(1, &EBO);
    c.glGenBuffers(1, &VBO2);
    c.glGenVertexArrays(1, &lightVAO);
    c.glBindVertexArray(lightVAO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO2);
    c.glBufferData(c.GL_ARRAY_BUFFER, num_vertices * @sizeOf(c.GLfloat), @ptrCast(*const c_void, &mesh.vertices[0]), c.GL_STATIC_DRAW);
    // c.glPolygonMode(c.GL_FRONT_AND_BACK, c.GL_LINE );
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, EBO);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, mesh.indices.len * @sizeOf(c.GLuint)), mesh.indices.ptr, c.GL_STATIC_DRAW);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 3 * @sizeOf(c.GLfloat), null);
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
            // std.debug.print("{d} ms/frame \n", .{ 1000.0 / @intToFloat(f32, nbFrames)});
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
        c.glUniform3f(c.glGetUniformLocation(obj_shader.program_id, "viewPos"), camera.pos.x, camera.pos.y, camera.pos.z);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "material.shininess"), 32.0);
        
        // directional light
        obj_shader.setVec3("dirLight.direction", -0.2, -1.0, -0.3);
        obj_shader.setVec3("dirLight.ambient", 0.05, 0.05, 0.05);
        obj_shader.setVec3("dirLight.diffuse", 0.4, 0.4, 0.4);
        obj_shader.setVec3("dirLight.specular", 0.5, 0.5, 0.5);
        // point light 1
        obj_shader.setVec3("pointLights[0].position", pointLightPositions[0].x, pointLightPositions[0].y, pointLightPositions[0].z);
        obj_shader.setVec3("pointLights[0].ambient", 0.05, 0.05, 0.05);
        obj_shader.setVec3("pointLights[0].diffuse", 0.8, 0.8, 0.8);
        obj_shader.setVec3("pointLights[0].specular", 1.0, 1.0, 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[0].constant"), 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[0].linear"), 0.09);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[0].quadratic"), 0.032);
        // point light 2
        obj_shader.setVec3("pointLights[1].position", pointLightPositions[1].x, pointLightPositions[1].y, pointLightPositions[1].z);
        obj_shader.setVec3("pointLights[1].ambient", 0.05, 0.05, 0.05);
        obj_shader.setVec3("pointLights[1].diffuse", 0.8, 0.8, 0.8);
        obj_shader.setVec3("pointLights[1].specular", 1.0, 1.0, 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[1].constant"), 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[1].linear"), 0.09);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[1].quadratic"), 0.032);
        // point light 3
        obj_shader.setVec3("pointLights[2].position", pointLightPositions[2].x, pointLightPositions[2].y, pointLightPositions[2].z);
        obj_shader.setVec3("pointLights[2].ambient", 0.05, 0.05, 0.05);
        obj_shader.setVec3("pointLights[2].diffuse", 0.8, 0.8, 0.8);
        obj_shader.setVec3("pointLights[2].specular", 1.0, 1.0, 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[2].constant"), 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[2].linear"), 0.09);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[2].quadratic"), 0.032);
        // point light 4
        obj_shader.setVec3("pointLights[3].position", pointLightPositions[3].x, pointLightPositions[3].y, pointLightPositions[3].z);
        obj_shader.setVec3("pointLights[3].ambient", 0.05, 0.05, 0.05);
        obj_shader.setVec3("pointLights[3].diffuse", 0.8, 0.8, 0.8);
        obj_shader.setVec3("pointLights[3].specular", 1.0, 1.0, 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[3].constant"), 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[4].linear"), 0.09);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "pointLights[4].quadratic"), 0.032);
        // spotlight
        obj_shader.setVec3("spotLight.position", camera.pos.x,camera.pos.y,camera.pos.z);
        obj_shader.setVec3("spotLight.direction", camera.front.x, camera.front.y, camera.front.z);
        obj_shader.setVec3("spotLight.ambient", 0.0, 0.0, 0.0);
        obj_shader.setVec3("spotLight.diffuse", 1.0, 1.0, 1.0);
        obj_shader.setVec3("spotLight.specular", 1.0, 1.0, 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "spotLight.constant"), 1.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "spotLight.linear"), 0.09);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "spotLight.quadratic"), 0.032);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "spotLight.cutOff"), 12.0);
        c.glUniform1f(c.glGetUniformLocation(obj_shader.program_id, "spotLight.outerCutOff"), 15.0);

        // view/projection transformations
        const view = mat4.look_at(camera.pos, vec3.add(camera.pos, camera.front), camera.up);
        const projection = mat4.perspective(45.0, (@intToFloat(f32,width) / @intToFloat(f32, height)), 0.1, 100.0);
        const viewLoc = c.glGetUniformLocation(obj_shader.program_id, "view");
        c.glUniformMatrix4fv(viewLoc, 1, c.GL_FALSE, view.get_data());
        const projectionLoc = c.glGetUniformLocation(obj_shader.program_id, "projection");
        c.glUniformMatrix4fv(projectionLoc, 1, c.GL_FALSE, projection.get_data());
        // world transformation
        var model = mat4.identity();
        var modelLoc = c.glGetUniformLocation(obj_shader.program_id, "model");
        c.glUniformMatrix4fv(modelLoc, 1, c.GL_FALSE, model.get_data());
        // diffuse map
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, diffuse.texture_id);
        // specular map
        c.glActiveTexture(c.GL_TEXTURE1);
        c.glBindTexture(c.GL_TEXTURE_2D, specular.texture_id); 
        // render objects
        c.glBindVertexArray(objectVAO);
        // TODO: for loop
        var i: u8 = 0;
        while (i < 10) {
            model = mat4.identity();
            model = model.translate(cube_positions[i]);
            // TODO: rotations
            modelLoc = c.glGetUniformLocation(obj_shader.program_id, "model");
            c.glUniformMatrix4fv(modelLoc, 1, c.GL_FALSE, model.get_data());
            c.glDrawArrays(c.GL_TRIANGLES, 0, 36);
            i += 1;
        }

        // -- lights 
        
        c.glUseProgram(light_shader.program_id);
        // uniforms
        c.glUniformMatrix4fv(c.glGetUniformLocation(light_shader.program_id, "projection"), 1, c.GL_FALSE, projection.get_data());
        c.glUniformMatrix4fv(c.glGetUniformLocation(light_shader.program_id, "view"), 1, c.GL_FALSE, view.get_data());
        model = mat4.identity();
        model = model.scale(vec3.new(0.02, 0.02, 0.02));
        model = model.translate(vec3.new(0.0, 0.0, -2.0));
        modelLoc = c.glGetUniformLocation(light_shader.program_id, "model");
        c.glUniformMatrix4fv(modelLoc, 1, c.GL_FALSE, model.get_data());
        // send my data
        
        // draw
        c.glBindVertexArray(lightVAO);
        c.glDrawElements(c.GL_TRIANGLES, num_indices, c.GL_UNSIGNED_INT, null);


        // c.glDrawArrays(c.GL_TRIANGLES, 0, verts.len / 8);
        // i = 0;
        // while (i < 4) { // 4 lamps
        //     model = mat4.identity();
        //     model = model.scale(vec3.new(0.2, 0.2, 0.2));
        //     model = model.translate(pointLightPositions[i]);
        //     modelLoc = c.glGetUniformLocation(light_shader.program_id, "model");
        //     c.glUniformMatrix4fv(modelLoc, 1, c.GL_FALSE, model.get_data());
        //     // draw lamp
        //     c.glDrawArrays(c.GL_TRIANGLES, 0, 36);
        //     i += 1;
        // }

        // -- backpack
        // update data
        // c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
        // c.glBufferData(c.GL_ARRAY_BUFFER, verts.len * @sizeOf(c.GLfloat), @ptrCast(*const c_void, &verts[0]), c.GL_STATIC_DRAW);

        // c.glUseProgram(light_shader.program_id);

        // c.glDrawArrays(c.GL_TRIANGLES, 0, 36);

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