const std = @import("std");
const allocator = @import("std").heap.c_allocator;
const za = @import("zalgebra");
const vec2 = za.vec2;
const vec3 = za.vec3;
const SplitIterator = std.mem.SplitIterator;
const Mesh = @import("../rendering.zig").Mesh;
const Model = @import("../rendering.zig").Model;

const Position = struct {

};

const FaceElement = struct {
    position_idx: u32,
    texture_idx: u32,
    normal_idx: u32
};

// if v -> append a vertex (x, y, z)
// if vn -> append vertex normals
// if vt -> 
// if f -> append 3 vertex indices

const Object = struct {
    name: []const u8,
    faces_from: usize,
    faces_to: usize,
    vertex_count: u32,
    material: []const u8,
    smoothing: bool,
    material_index: ?usize
};

const Mtl = struct {
    name: []const u8,
    ambient: vec3 = vec3.zero(),
    diffuse: vec3 = vec3.zero(),
    specular: vec3 = vec3.zero(),
    diffuse_map: ?[]const u8 = null,
    specular_map: ?[]const u8 = null,
    specular_strength: f32 = 32.0,

    fn print (m: Mtl) void { // debug print
        std.debug.print(
            \\ Material:
            \\  name: {s}
            \\  specular strength: {d}
            \\
        , .{m.name, m.specular_strength});
    }
};

pub fn load_obj(file_path: []const u8) !Model {
    std.debug.print("Begin load OBJ to Mesh.\n", .{});
    var tmp_positions  = std.ArrayList(vec3).init(allocator);           // positions
    var tmp_normals   = std.ArrayList(vec3).init(allocator);            // normals
    var tmp_texcoords = std.ArrayList(vec2).init(allocator);            // texture coords
    var tmp_faces  = std.ArrayList(FaceElement).init(allocator);        // face elements
    var tmp_meshes = std.ArrayList(Mesh).init(allocator);

    // TODO: materials
    // var tmp_materials = std.ArrayList(Mtl).init(allocator);

    // load the file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const reader = file.reader();
    const text = try reader.readAllAlloc(allocator, std.math.maxInt(u64)); // read whole thing into memory
    defer allocator.free(text);
    
    var lines = std.mem.split(text, "\n"); // get each line

    var position_offset: usize = 0;
    var normal_offset: usize = 0;
    var texcoord_offset: usize = 0;
    var face_offset: usize = 0;

    var object_name_b = try allocator.alloc(u8, 1024); // TODO: not using name at the moment
    var first_object = true;
    // read each line by line
    while (lines.next()) |line| {
        var line_items = std.mem.split(line, " ");
        const line_header = line_items.next().?; // read first character
        
        if (std.mem.eql(u8, line_header, "v")) {
            const pos = try parse_vertex(line);
            try tmp_positions.append(pos);
        } else if (std.mem.eql(u8, line_header, "vn")) {
            try parse_normal(&tmp_normals, line);
        } else if (std.mem.eql(u8, line_header, "vt")) {
            try parse_texture_coords(&tmp_texcoords, line);
        } else if (std.mem.eql(u8, line_header, "f")) {
            try parse_face(&tmp_faces, line);
        } else if (std.mem.eql(u8, line_header, "mtllib")) {
            // try load_material_lib(&tmp_materials, line);
        } else if (std.mem.eql(u8, line_header, "o")) {
            // first 'o' doesnt create an object
            if (!first_object) {
                const mesh = try create_submesh(&tmp_positions, &tmp_normals, &tmp_faces, position_offset, face_offset);
                try tmp_meshes.append(mesh);
                std.debug.print("Submesh {s} stats: {d} vertices - {d} normals - {d} faces \n", .{
                    object_name_b,
                    tmp_positions.items.len - position_offset,
                    tmp_normals.items.len - normal_offset,
                    tmp_faces.items.len - face_offset
                });
                position_offset = tmp_positions.items.len;
                normal_offset = tmp_normals.items.len;
                face_offset = tmp_faces.items.len;
            }
            first_object = false;
            const object_name = try parse_object(line); // set current object name
            std.mem.set(u8, object_name_b, 0);
            std.mem.copy(u8, object_name_b, object_name);

        } else {} // ignore
        // TODO: handle material
    }

    // last mesh or if one wasnt created
    if (tmp_positions.items.len > 0 and tmp_faces.items.len != face_offset) {
        const mesh = try create_submesh(&tmp_positions, &tmp_normals, &tmp_faces, position_offset, face_offset);
        try tmp_meshes.append(mesh);
    }

    std.debug.print("Num sub-meshes: {d}\n", .{tmp_meshes.items.len});

    return Model{
        .meshes = tmp_meshes.toOwnedSlice(),
        .use_gamma_correction = false
    };
}

// A vertex is specified via a line starting with the letter v. That is followed by (x,y,z[,w]) coordinates. W is optional and defaults to 1.0.
fn parse_vertex(line: []const u8) !vec3 {
    var line_items = std.mem.split(line, " ");
    _ = line_items.next(); // skip line header
    const x = try std.fmt.parseFloat(f32, line_items.next().?);
    const y = try std.fmt.parseFloat(f32, line_items.next().?);
    const z = try std.fmt.parseFloat(f32, line_items.next().?);
    return vec3.new(x, y, z);
}

fn parse_normal(normal_array: *std.ArrayList(vec3), line: []const u8) !void {
    var line_items = std.mem.split(line, " ");
    _ = line_items.next(); // skip line header
    const x = try std.fmt.parseFloat(f32, line_items.next().?);
    const y = try std.fmt.parseFloat(f32, line_items.next().?);
    const z = try std.fmt.parseFloat(f32, line_items.next().?);
    try normal_array.append(vec3.new(x, y, z));
}

fn parse_texture_coords (tex_coords_array: *std.ArrayList(vec2), line: []const u8) !void {
    // TODO
}

fn parse_face(elements_array: *std.ArrayList(FaceElement), line: []const u8) !void {
    var line_items = std.mem.split(line, " ");
    _ = line_items.next(); // skip line header

    var v_i: u32 = 0;
    while (v_i < 3) {
        var vert = line_items.next().?;
        var vert_parts = std.mem.split(vert, "/");
        var v_vertex_idx = vert_parts.next();
        var v_texture_idx = vert_parts.next();
        var v_normal_idx = vert_parts.next();
        
        try elements_array.append(.{
            .position_idx  = if (v_vertex_idx != null) ((std.fmt.parseUnsigned(u32, v_vertex_idx.?, 10) catch 1) - 1) else 0, // indexed from 1 not zero
            .texture_idx = if (v_texture_idx != null) ((std.fmt.parseUnsigned(u32, v_texture_idx.?, 10) catch 1) - 1) else 0,
            .normal_idx  = if (v_normal_idx != null) ((std.fmt.parseUnsigned(u32, v_normal_idx.?, 10) catch 1) - 1) else 0,
        });

        v_i += 1;
    }
}

fn parse_object(line: []const u8) ![]const u8 {
    var line_items = std.mem.split(line, " ");
    _ = line_items.next(); // skip line header
    var name = line_items.next().?;

    return name;
}

// var tmp_positions  = std.ArrayList(vec3).init(allocator);           // positions
//     var tmp_normals   = std.ArrayList(vec3).init(allocator);            // normals
//     var tmp_texcoords = std.ArrayList(vec2).init(allocator);            // texture coords
//     var tmp_faces  = std.ArrayList(FaceElement).init(allocator);        // face elements
//     var tmp_meshes = std.ArrayList(Mesh).init(allocator);

fn create_submesh(
    tmp_positions: *std.ArrayList(vec3),
    tmp_normals:   *std.ArrayList(vec3),
    tmp_faces:     *std.ArrayList(FaceElement),
    position_offset: usize,
    face_offset: usize
) !Mesh {
    // position offset to current position len - allocate for vertex array
    var vertices_buffer = try allocator.alloc(f32, (tmp_positions.items.len - position_offset) * 8);
    // faces offset to current faces len - allocate for indices array
    var indices_buffer = try allocator.alloc(u32, (tmp_faces.items.len - face_offset) );
    // push vertices (pos, norm, tex)
    // push indices (subtract each offset from each position/normal/t to get correct index into array)
    var num_faces = tmp_faces.items.len - face_offset;
    var i: usize = 0;
    while (i < num_faces) {
        const face = tmp_faces.items[face_offset + i];
        const v = face.position_idx;
        const pos = tmp_positions.items[face.position_idx];
        const norm = if (face.normal_idx == 0) vec3.zero() else tmp_normals.items[face.normal_idx];
        const relative_pos_i = v - position_offset;
        // std.debug.print("{any}\n", .{relative_pos_i});
        vertices_buffer[relative_pos_i * 8] = pos.x;
        vertices_buffer[relative_pos_i * 8 + 1] = pos.y;
        vertices_buffer[relative_pos_i * 8 + 2] = pos.z;

        indices_buffer[i] = @intCast(u32, relative_pos_i);

        i+= 1;
    }

    // std.debug.print("vertex array length: {any}\n", .{vertices_buffer.len});
    // std.debug.print("index array length: {any}\n", .{indices_buffer.len});

    // create mesh
    // update variables

    return Mesh.create(
        vertices_buffer,
        indices_buffer
    );
}

// fn create_object()

pub fn load_material_lib(materials_array: *std.ArrayList(Mtl), line: []const u8) !void {
    var line_items = std.mem.split(line, " ");
    _ = line_items.next(); // skip line header
    var path = line_items.next().?;

    // load the file
    const file = try std.fs.cwd().openFile("assets/backpack/backpack.mtl", .{});
    defer file.close();

    const reader = file.reader();
    const text = try reader.readAllAlloc(allocator, std.math.maxInt(u64)); // read whole thing into memory
    defer allocator.free(text);
    // get each line
    var mtl_lines = std.mem.split(text, "\n");


    var current_mtl: usize = 0;
    while (mtl_lines.next()) |m_line| {
        var m_line_items = std.mem.split(m_line, " ");
        const m_line_header = m_line_items.next().?;
        
        if (std.mem.eql(u8, m_line_header, "newmtl")) {
            const name = m_line_items.next().?;
            const new_mtl = Mtl{ .name = name };
            try materials_array.append(new_mtl);
            // std.debug.print("newmtl {s}\n", .{ materials_array.items[current_mtl].name });

            if (materials_array.items.len > 1) {
                current_mtl += 1; // only increment after first material has been set
            }

        } else if (std.mem.eql(u8, m_line_header, "Ka")) {
            // Ambient colour
        } else if (std.mem.eql(u8, m_line_header, "Kd")) {
            // Diffuse colour
        } else if (std.mem.eql(u8, m_line_header, "Ks")) {
            // Specular colour
        } else if (std.mem.eql(u8, m_line_header, "Ns")) {
            // Specular exponent
            const ns = try std.fmt.parseFloat(f32, m_line_items.next().?);
            materials_array.items[current_mtl].specular_strength = ns;
        }
    }

    materials_array.items[current_mtl].print();
    // std.debug.print("I read the .mtl file!\n", .{});
}



// Tests

const builtin = @import("builtin");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;


test "builtin.is_test" {
    expect(builtin.is_test);
}


// unit tests

// test each parse command

test "parse_vertex - regular vertex" {
    const v = try parse_vertex("v 1.0 1.0 1.0");
    expectEqual(vec3.is_eq(v, vec3.new(1.0, 1.0, 1.0)), true);
}

test "parse_vertex - negative numbers" {
    const v = try parse_vertex("v -3.0 -99.0 1.0");
    expectEqual(vec3.is_eq(v, vec3.new(-3.0, -99.0, 1.0)), true);
}

// integrations tests

// test with a cube

test "load_obj - cube" {
    // const model = try load_obj(cube_obj);

    // expect(model.meshes.items[0].num_vertices == 8);
    // expect(model.meshes.items[0].num_indices  == 36);
    // expect(model.total_triangles == 12);
    // expect(model.materials.items.len == 0);
}

// test with a multi object model


// arrange

const cube_obj =  \\g cube
\\v 0.0 0.0 0.0
\\v 0.0 0.0 1.0
\\v 0.0 1.0 0.0
\\v 0.0 1.0 1.0
\\v 1.0 0.0 0.0
\\v 1.0 0.0 1.0
\\v 1.0 1.0 0.0
\\v 1.0 1.0 1.0
\\vn 0.0 0.0 1.0
\\vn 0.0 0.0 -1.0
\\vn 0.0 1.0 0.0
\\vn 0.0 -1.0 0.0
\\vn 1.0 0.0 0.0
\\vn -1.0 0.0 0.0
\\f 1//2 7//2 5//2
\\f 1//2 3//2 7//2 
\\f 1//6 4//6 3//6 
\\f 1//6 2//6 4//6 
\\f 3//3 8//3 7//3 
\\f 3//3 4//3 8//3 
\\f 5//5 7//5 8//5 
\\f 5//5 8//5 6//5 
\\f 1//4 5//4 6//4 
\\f 1//4 6//4 2//4 
\\f 2//1 6//1 8//1 
\\f 2//1 8//1 4//1
;