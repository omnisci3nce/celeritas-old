const std = @import("std");
const warn = std.debug.warn;
const panic = std.debug.panic;
const c = @import("c.zig");
const c_allocator = @import("std").heap.c_allocator;
const r = @import("rendering.zig");
const za = @import("zalgebra");
const mat4 = za.Mat4;
const vec3 = za.Vec3;
const stdMath = std.math;
const cos = stdMath.cos;
const sin = stdMath.sin;
const obj_loader = @import("loaders/obj.zig");
const Mesh = r.Mesh;
const Cube = r.Cube;
const plane = @import("plane.zig");
const engine = @import("engine.zig");

const width: i32 = 800;
const height: i32 = 600;
var last_x: f64 = width / 2;
var last_y: f64 = height / 2;

var window: *c.GLFWwindow = undefined;

var yaw: f32 = -90.0;
var pitch: f32 = 0.0;

const cube_vertices = @import("cube.zig").vertices;
const cube_positions = @import("cube.zig").positions;

const light_pos = vec3.new(1.2, 1.0, 2.0);

var camera = r.Camera.create(vec3.new(0.0, 0.0, 3.0), vec3.new(0.0, 0.0, -1.0), vec3.new(0.0, 1.0, 0.0));

var delta_time: f64 = 0.0;
var last_frame: f64 = 0.0;

fn init() bool {
    _ = c.glfwSetErrorCallback(error_callback);

    if (c.glfwInit() == c.GL_FALSE) {
        std.debug.print("Failed to initialize GLFW\n", .{});
        return false;
    }
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    // c.glfwWindowHint(c.GLFW_COCOA_RETINA_FRAMEBUFFER, c.GL_FALSE);
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

    _ = init();
    var stats = engine.FrameStats{ .drawcall_count = 0, .shader_switch_count = 0, .triangle_count = 0, .frame_time = 0 };

    // ---- meshes
    // TODO: abstract load_obj and openFile + defer into single line functions
    // const asset_model = try obj_loader.load_obj("assets/backpack/backpack.obj");
    // std.debug.print("Num materials: {d}\n", .{asset_model.meshes.len});

    // var container_file = try std.fs.cwd().openFile("assets/container2.png", .{});
    // defer container_file.close();

    // const container_src = try container_file.reader().readAllAlloc(
    //     c_allocator,
    //     100000000,
    // );
    // defer c_allocator.free(container_src);

    var wood_file = try std.fs.cwd().openFile("assets/wood.png", .{});
    defer wood_file.close();
    const wood_src = try wood_file.reader().readAllAlloc(
        c_allocator,
        100000000,
    );
    defer c_allocator.free(wood_src);

    // var container_file2 = try std.fs.cwd().openFile("assets/container2_specular.png", .{});
    // defer container_file2.close();

    // const container_src2 = try container_file2.reader().readAllAlloc(
    //     c_allocator,
    //     100000000,
    // );
    // defer c_allocator.free(container_src2);

    // ---- shaders
    const simple_depth_shader = try r.ShaderProgram.create_from_file("shaders/3.1.1.shadow_mapping_depth.vs", "shaders/3.1.1.shadow_mapping_depth.fs");
    const debug_depth_quad = try r.ShaderProgram.create_from_file("shaders/3.1.1.debug_quad.vs", "shaders/3.1.1.debug_quad.fs");
    const shader = try r.ShaderProgram.create_from_file("shaders/3.1.2.shadow_mapping.vs", "shaders/3.1.2.shadow_mapping.fs");

    // ---- textures
    // std.debug.print("Loading diffuse container png\n", .{});
    // var diffuse = try r.Texture.create(container_src);
    // std.debug.print("Loading specular container png\n", .{});
    // var specular = try r.Texture.create(container_src2);

    var woodTexture = try r.Texture.create(wood_src);

    const cube = try Cube.create(simple_depth_shader);
    // const floor = try Cube.create(simple_depth_shader);

    // Floor - plane
    var planeVAO: u32 = undefined;
    var planeVBO: u32 = undefined;
    c.glGenVertexArrays(1, &planeVAO);
    c.glGenBuffers(1, &planeVBO);
    c.glBindVertexArray(planeVAO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, planeVBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, plane.vertices.len * @sizeOf(c.GLfloat)), &plane.vertices, c.GL_STATIC_DRAW);
    const stride = 8 * @sizeOf(c.GLfloat);
    c.glBindVertexArray(planeVAO);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, stride, null); // position
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, stride, @intToPtr(*anyopaque, 3 * @sizeOf(c.GLfloat))); // normal
    c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, stride, @intToPtr(*anyopaque, 6 * @sizeOf(c.GLfloat))); // tex coords
    c.glEnableVertexAttribArray(0);
    c.glEnableVertexAttribArray(1);
    c.glEnableVertexAttribArray(2);
    c.glBindVertexArray(0);

    // Quad
    const quadVertices = [_]f32{
        // positions        // texture Coords
        -1.0, 1.0,  0.0, 0.0, 1.0,
        -1.0, -1.0, 0.0, 0.0, 0.0,
        1.0,  1.0,  0.0, 1.0, 1.0,
        1.0,  -1.0, 0.0, 1.0, 0.0,
    };
    // setup quad VAO
    var quadVAO: u32 = undefined;
    var quadVBO: u32 = undefined;
    c.glGenVertexArrays(1, &quadVAO);
    c.glGenBuffers(1, &quadVBO);
    c.glBindVertexArray(quadVAO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, quadVBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, quadVertices.len * @sizeOf(c.GLfloat)), &quadVertices, c.GL_STATIC_DRAW);
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(c.GLfloat), null);
    c.glEnableVertexAttribArray(1);
    c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(c.GLfloat), @intToPtr(*anyopaque, 3 * @sizeOf(c.GLfloat)));

    // Shader configuration
    c.glUseProgram(shader.program_id);
    shader.setInt("diffuseTexture", 0);
    shader.setInt("shadowMap", 1);
    c.glUseProgram(debug_depth_quad.program_id);
    shader.setInt("depthMap", 0);

    // ---- lights
    {
        // const sun = r.DirectionalLight{
        //     .direction = vec3.new(0.3, -1.0, 0.0),
        //     .ambient_colour = vec3.new(0.2, 0.2, 0.2),
        //     .diffuse_colour = vec3.new(0.6, 0.6, 0.6),
        //     .specular_colour = vec3.new(0.5, 0.5, 0.5)
        // };

        // const point_light_positions = [4]vec3{
        //     vec3.new(1.5, 1.0, -4.0),
        //     vec3.new(2.3, -0.3, -2.0),
        //     vec3.new(-4.0, 2.0, -8.0),
        //     vec3.new(0.0, -1.0, -3.0),
        // };

        // var point_lights: [4]r.PointLight = undefined;
        // // create point lights
        // var i: usize = 0;
        // while (i < 4) {
        //     point_lights[i] = r.PointLight{
        //         .position = point_light_positions[i],
        //         .constant = 1.0,
        //         .linear = 0.2,
        //         .quadratic = 0.064,
        //         .ambient = vec3.new(0.05, 0.05, 0.05),
        //         .diffuse = vec3.new(0.8, 0.8, 0.8),
        //         .specular = vec3.new(1.0, 1.0, 1.0)
        //     };
        //     i += 1;
        // }
        // std.debug.assert(i == 4);
    }
    var lightPos = vec3.new(-2.0, 4.0, -1.0);

    var nbFrames: i32 = 0;
    var last_time: f32 = 0.0;

    var mesh_index: usize = 0;

    // ---- Shadow map setup
    var depthMapFBO: u32 = undefined;
    c.glGenFramebuffers(1, &depthMapFBO);

    // Create 2D texture to use as frame buffers depth buffer
    const shadow_width = 1024;
    const shadow_height = 1024;

    var depthMap: u32 = undefined;
    c.glGenTextures(1, &depthMap);
    c.glBindTexture(c.GL_TEXTURE_2D, depthMap);
    c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_DEPTH_COMPONENT, shadow_width, shadow_height, 0, c.GL_DEPTH_COMPONENT, c.GL_FLOAT, null);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);

    // Attach depth texture as framebuffers depth buffer
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, depthMapFBO);
    c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, depthMap, 0);
    c.glDrawBuffer(c.GL_NONE);
    c.glReadBuffer(c.GL_NONE);
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

    // ---- Render loop
    while (c.glfwWindowShouldClose(window) == c.GL_FALSE) {
        stats.drawcall_count = 0; // reset frame stats

        // camera
        var x = cos(za.toRadians(yaw)) * cos(za.toRadians(pitch));
        var y = sin(za.toRadians(pitch));
        var z = sin(za.toRadians(yaw)) * cos(za.toRadians(pitch));
        var direction = vec3.new(x, y, z);
        camera.front = vec3.norm(direction);

        // ---- per-frame time logic
        const currentFrame = c.glfwGetTime();
        delta_time = currentFrame - last_frame;
        last_frame = currentFrame;

        nbFrames += 1;
        if (currentFrame - last_time >= 2.0) {
            // std.debug.print("{d} ms/frame \n", .{ 1000.0 / @intToFloat(f32, nbFrames)});
            nbFrames = 0;
            last_time += 1.0;
            mesh_index += 1;
        }

        // ---- input
        process_input(window);

        // ---- render

        // 1. first render depth of scene to depth map
        const near_plane = 1.0;
        const far_plane = 7.5;
        const lightProjection = mat4.orthographic(-10.0, 10.0, -10.0, 10.0, near_plane, far_plane);
        const lightView = mat4.lookAt(lightPos, vec3.new(0.0, 0.0, 0.0), vec3.new(0.0, 1.0, 0.0));
        const lightSpaceMatrix = mat4.mult(lightProjection, lightView);
        // render scene from lights point of view
        c.glUseProgram(simple_depth_shader.program_id);
        simple_depth_shader.setMat4("lightSpaceMatrix", lightSpaceMatrix);

        c.glViewport(0, 0, shadow_width, shadow_height);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, depthMapFBO);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);

        c.glActiveTexture(c.GL_TEXTURE_2D);
        c.glBindTexture(c.GL_TEXTURE_2D, woodTexture.texture_id);

        c.glCullFace(c.GL_FRONT);

        // floor
        var model = mat4.identity();
        simple_depth_shader.setMat4("model", model);
        c.glBindVertexArray(planeVAO);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
        //cubes
        model = mat4.identity().scale(vec3.new(0.5, 0.5, 0.5)).translate(vec3.new(0.0, 1.5, 0.0));
        simple_depth_shader.setMat4("model", model);
        cube.draw(&stats);
        //
        model = mat4.identity().scale(vec3.new(0.5, 0.5, 0.5)).translate(vec3.new(2.0, 0.0, 1.0));
        simple_depth_shader.setMat4("model", model);
        cube.draw(&stats);
        //
        model = mat4.identity().scale(vec3.new(0.25, 0.25, 0.25)).translate(vec3.new(1.0, 0.0, 1.0));
        simple_depth_shader.setMat4("model", model);
        cube.draw(&stats);

        c.glCullFace(c.GL_BACK);

        // reset viewport
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        c.glViewport(0, 0, width, height);
        c.glClearColor(0.1, 0.1, 0.1, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);

        // 2. render scene as normal with shadow mapping (using depth map)
        c.glUseProgram(shader.program_id);
        // view/projection transformations
        const projection = mat4.perspective(45.0, (@intToFloat(f32,width) / @intToFloat(f32, height)), 0.1, 100.0);
        const view = mat4.lookAt(camera.pos, vec3.add(camera.pos, camera.front), camera.up);
        shader.setMat4("projection", projection);
        shader.setMat4("view", view);
        // set light uniforms
        shader.setVec3("viewPos", camera.pos.x(), camera.pos.y(), camera.pos.z());
        shader.setVec3("lightPos", lightPos.x(), lightPos.y(), lightPos.z());
        shader.setMat4("lightSpaceMatrix", lightSpaceMatrix);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, woodTexture.texture_id);
        c.glActiveTexture(c.GL_TEXTURE1);
        c.glBindTexture(c.GL_TEXTURE_2D, depthMap);

        // floor
        model = mat4.identity();
        shader.setMat4("model", model);
        c.glBindVertexArray(planeVAO);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
        //cubes
        model = mat4.identity().scale(vec3.new(0.5, 0.5, 0.5)).translate(vec3.new(0.0, 1.5, 0.0));
        shader.setMat4("model", model);
        cube.draw(&stats);
        // 
        model = mat4.identity().scale(vec3.new(0.5, 0.5, 0.5)).translate(vec3.new(2.0, 0.0, 1.0));
        shader.setMat4("model", model);
        cube.draw(&stats);
        // 
        model = mat4.identity().scale(vec3.new(0.25, 0.25, 0.25)).translate(vec3.new(1.0, 0.0, 1.0));
        shader.setMat4("model", model);
        cube.draw(&stats);


        // --- debug
        // c.glUseProgram(debug_depth_quad.program_id);
        // debug_depth_quad.setFloat("near_plane", near_plane);
        // debug_depth_quad.setFloat("far_plane", far_plane);
        // c.glActiveTexture(c.GL_TEXTURE0);
        // c.glBindTexture(c.GL_TEXTURE_2D, depthMap);
        // c.glBindVertexArray(quadVAO);
        // c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
        // c.glBindVertexArray(0);


        // c.glPolygonMode(c.GL_FRONT_AND_BACK, c.GL_LINE );

        {
            // render cubes
            // c.glUseProgram(lighting_shader.program_id);
            // lighting_shader.setMat4("view", view);
            // lighting_shader.setMat4("projection", projection);

            // lighting_shader.setFloat("material.shininess", 32.0);

            // // directional light - "sun"
            // lighting_shader.setVec3("dirLight.direction", sun.direction.x(), sun.direction.y(), sun.direction.z());
            // lighting_shader.setVec3("dirLight.ambient", 0.2, 0.2, 0.2);
            // lighting_shader.setVec3("dirLight.diffuse", 0.6, 0.6, 0.6);
            // lighting_shader.setVec3("dirLight.specular", 0.5, 0.5, 0.5);

            // // point lights 1-4
            // lighting_shader.setVec3("pointLights[0].position", point_light_positions[0].x(), point_light_positions[0].y(), point_light_positions[0].z());
            // lighting_shader.setVec3("pointLights[0].ambient", point_lights[0].ambient.x(), point_lights[0].ambient.y(), point_lights[0].ambient.z());
            // lighting_shader.setVec3("pointLights[0].diffuse", point_lights[0].diffuse.x(), point_lights[0].diffuse.y(), point_lights[0].diffuse.z());
            // lighting_shader.setVec3("pointLights[0].specular", point_lights[0].specular.x(), point_lights[0].specular.y(), point_lights[0].specular.z());
            // lighting_shader.setFloat("pointLights[0].constant", point_lights[0].constant);
            // lighting_shader.setFloat("pointLights[0].linear", point_lights[0].linear);
            // lighting_shader.setFloat("pointLights[0].quadratic", point_lights[0].quadratic);

            // lighting_shader.setVec3("pointLights[1].position", point_light_positions[1].x(), point_light_positions[1].y(), point_light_positions[1].z());
            // lighting_shader.setVec3("pointLights[1].ambient", point_lights[1].ambient.x(), point_lights[1].ambient.y(), point_lights[1].ambient.z());
            // lighting_shader.setVec3("pointLights[1].diffuse", point_lights[1].diffuse.x(), point_lights[1].diffuse.y(), point_lights[1].diffuse.z());
            // lighting_shader.setVec3("pointLights[1].specular", point_lights[1].specular.x(), point_lights[1].specular.y(), point_lights[1].specular.z());
            // lighting_shader.setFloat("pointLights[1].constant", point_lights[1].constant);
            // lighting_shader.setFloat("pointLights[1].linear", point_lights[1].linear);
            // lighting_shader.setFloat("pointLights[1].quadratic", point_lights[1].quadratic);

            // lighting_shader.setVec3("pointLights[2].position", point_light_positions[2].x(), point_light_positions[2].y(), point_light_positions[2].z());
            // lighting_shader.setVec3("pointLights[2].ambient", point_lights[2].ambient.x(), point_lights[2].ambient.y(), point_lights[2].ambient.z());
            // lighting_shader.setVec3("pointLights[2].diffuse", point_lights[2].diffuse.x(), point_lights[2].diffuse.y(), point_lights[2].diffuse.z());
            // lighting_shader.setVec3("pointLights[2].specular", point_lights[2].specular.x(), point_lights[2].specular.y(), point_lights[2].specular.z());
            // lighting_shader.setFloat("pointLights[2].constant", point_lights[2].constant);
            // lighting_shader.setFloat("pointLights[2].linear", point_lights[2].linear);
            // lighting_shader.setFloat("pointLights[2].quadratic", point_lights[2].quadratic);

            // lighting_shader.setVec3("pointLights[3].position", point_light_positions[3].x(), point_light_positions[3].y(), point_light_positions[3].z());
            // lighting_shader.setVec3("pointLights[3].ambient", point_lights[3].ambient.x(), point_lights[3].ambient.y(), point_lights[3].ambient.z());
            // lighting_shader.setVec3("pointLights[3].diffuse", point_lights[3].diffuse.x(), point_lights[3].diffuse.y(), point_lights[3].diffuse.z());
            // lighting_shader.setVec3("pointLights[3].specular", point_lights[3].specular.x(), point_lights[3].specular.y(), point_lights[3].specular.z());
            // lighting_shader.setFloat("pointLights[3].constant", point_lights[3].constant);
            // lighting_shader.setFloat("pointLights[3].linear", point_lights[3].linear);
            // lighting_shader.setFloat("pointLights[3].quadratic", point_lights[3].quadratic);

            // // bind diffuse map
            // c.glActiveTexture(c.GL_TEXTURE0);
            // c.glUniform1i(c.glGetUniformLocation(lighting_shader.program_id, "material.diffuse"), 0);
            // c.glBindTexture(c.GL_TEXTURE_2D, diffuse.texture_id);
            // c.glActiveTexture(c.GL_TEXTURE1);
            // c.glUniform1i(c.glGetUniformLocation(lighting_shader.program_id, "material.specular"), 1);
            // c.glBindTexture(c.GL_TEXTURE_2D, specular.texture_id);
        }

        {
            // // middle cube
            // model = mat4.identity().translate(vec3.new(1.0, -1.0, -4.0));
            // lighting_shader.setMat4("model", model);
            // cube.draw(&stats);

            // // wall cube
            // model = mat4.identity().scale(vec3.new(5.0, 3.0, 1.0)).translate(vec3.new(1.0, 0.0, -8.5));
            // lighting_shader.setMat4("model", model);
            // cube.draw(&stats);

            // // wall cube 2
            // model = mat4.identity();
            // model = model.scale(vec3.new(1.0, 3.0, 4.0));
            // model = model.rotate(0, vec3.new(1.0, 0.0, 0.0));
            // model = model.rotate(90, vec3.new(0.0, 1.0, 0.0));
            // model = model.rotate(0, vec3.new(0.0, 0.0, 1.0));
            // model = model.translate(vec3.new(4.0, 0.0, -6.0));
            // lighting_shader.setMat4("model", model);
            // cube.draw(&stats);

            // backpack
            // model = mat4.identity();
            // model = model.scale(vec3.new(0.1, 0.1, 0.1));
            // model = model.rotate(180, vec3.new(0.0, 1.0, 0.0));
            // model = model.translate(vec3.new(0.0, 2.0, 0.0));
            // lighting_shader.setMat4("model", model);
            // asset_model.draw(lighting_shader.program_id);

            // render lights
            // c.glUseProgram(light_cube_shader.program_id);
            // var l_i: usize = 0;
            // while (l_i < 4) {
            //     model = mat4.identity();
            //     model = model.scale(vec3.new(0.2, 0.2, 0.2));
            //     model = model.translate(point_light_positions[l_i]);
            //     light_cube_shader.setMat4("view", view);
            //     light_cube_shader.setMat4("projection", projection);
            //     light_cube_shader.setMat4("model", model);
            //     cube.draw(&stats);
            //     l_i += 1;
            // }

            // stats.print_drawcalls();
        }

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
    _ = err;
    panic("Error: {s}\n", .{description});
}
fn key_callback(win: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    _ = scancode;
    _ = mods;
    if (action == c.GLFW_PRESS) {
        switch (key) {
            c.GLFW_KEY_ESCAPE => c.glfwSetWindowShouldClose(win, c.GL_TRUE),
            else => {},
        }
    }
    return;
}

fn mouse_callback(win: ?*c.GLFWwindow, x_pos: f64, y_pos: f64) callconv(.C) void {
    _ = win;
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
        pitch = 89.0;
    if (pitch < -89.0)
        pitch = -89.0;
}
