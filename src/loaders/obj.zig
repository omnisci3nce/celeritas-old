const std = @import("std");
const allocator = @import("std").heap.c_allocator;
const za = @import("zalgebra");
const vec2 = za.vec2;
const vec3 = za.vec3;
const SplitIterator = std.mem.SplitIterator;
const Mesh = @import("../rendering.zig").Mesh;
const Model = @import("../rendering.zig").Model;

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

    fn print (m: Mtl) void {
        std.debug.print(
            \\ Material:
            \\  name: {s}
            \\  specular strength: {d}
            \\
        , .{m.name, m.specular_strength});
    }
};

pub fn load_obj(file_path: []const u8) !Mesh {
    std.debug.print("Begin load OBJ to Mesh.\n", .{});
    var tmp_vertices  = std.ArrayList(vec3).init(allocator);            // positions
    var tmp_normals   = std.ArrayList(vec3).init(allocator);            // normals
    var tmp_texcoords = std.ArrayList(vec2).init(allocator);            // texture coords
    var tmp_elements  = std.ArrayList(FaceElement).init(allocator);     // face elements
    var tmp_objects   = std.ArrayList(Object).init(allocator);          // "objects" submeshes
    var tmp_materials = std.ArrayList(Mtl).init(allocator);

    // load the file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const reader = file.reader();
    const text = try reader.readAllAlloc(allocator, std.math.maxInt(u64)); // read whole thing into memory
    defer allocator.free(text);
    // get each line
    var lines = std.mem.split(text, "\n");


    var current_obj: u32 = 0;
    var l_i: u32 = 0;
    // read each line by line
    while (lines.next()) |line| {
        // read first character
        var line_items = std.mem.split(line, " ");
        const line_header = line_items.next().?;
        
        if (std.mem.eql(u8, line_header, "v")) {
            try parse_vertex(&tmp_vertices, line);
        } else if (std.mem.eql(u8, line_header, "vn")) {
            try parse_normal(&tmp_normals, line);
        } else if (std.mem.eql(u8, line_header, "vt")) {
            try parse_texture_coords(&tmp_texcoords, line);
        } else if (std.mem.eql(u8, line_header, "f")) {
            try parse_face(&tmp_elements, line);
        } else if (std.mem.eql(u8, line_header, "mtllib")) {
            // std.debug.print("use a material lib!\n", .{});
            try load_material_lib(&tmp_materials, line);
        } else if (std.mem.eql(u8, line_header, "o")) {
            if (tmp_objects.items.len > 0) {
                tmp_objects.items[current_obj-1].faces_to = tmp_elements.items.len;
                // std.debug.print("previous object faces: {d} - {d}\n", .{
                //     @intCast(u32, tmp_objects.items[current_obj-1].faces_from),
                //     @intCast(u32, tmp_objects.items[current_obj-1].faces_to)});
            }
            try parse_object(&tmp_objects, line, tmp_elements.items.len);
            // std.debug.print("Found object {d}: \"{s}\"\n", .{current_obj, tmp_objects.items[current_obj].name});
            current_obj += 1;


        } else {} // ignore
        // TODO: handle material
        // TODO: handle multiple meshes to make up one model

        l_i += 1;
    }

    // debug info
    // std.debug.print("vertices: {d}\n", .{tmp_vertices.items.len});
    // std.debug.print("tex coords: {d}\n", .{tmp_texcoords.items.len});
    // std.debug.print("normals: {d}\n", .{tmp_normals.items.len});
    // std.debug.print("face elements: {d}\n", .{tmp_elements.items.len});
    // std.debug.print("faces: {d}\n", .{@intToFloat(f32, tmp_elements.items.len) / 3.0});

    // merge all vertices
    var output_buffer = try allocator.alloc(f32, tmp_vertices.items.len * 8); // 3 pos, 3 norm, 2 tex
    var output_idx_buffer = try allocator.alloc(u32, tmp_elements.items.len); // num triangles
    var i: u32 = 0;
    var j: u32 = 0;
    for (tmp_elements.items) |face| { // TODO: dont write out every single vertex. (?)
        // std.debug.print("posotion index: {d}\n", .{face.position_idx});
        var v = face.position_idx;
        // std.debug.print("v: {d}\n", .{v});
        // std.debug.print("face: {any}\n", .{face});
        const pos = tmp_vertices.items[face.position_idx];
        // const norm = tmp_normals.items[face.normal_idx];
        // const tex = if (face.texture_idx == 0) vec2.zero() else tmp_texcoords.items[face.texture_idx];
        const norm = if (face.normal_idx == 0) vec3.zero() else tmp_normals.items[face.normal_idx];

        // // position
        output_buffer[v*8] = pos.x;
        output_buffer[v*8 + 1] = pos.y;
        output_buffer[v*8 + 2] = pos.z;
        // // normal
        output_buffer[v*8 + 3] = norm.x;
        output_buffer[v*8 + 4] = norm.y;
        output_buffer[v*8 + 5] = norm.z;
        // // texture coords
        // output_buffer[i+6] = tex.x;
        // output_buffer[i+7] = tex.y;

        output_idx_buffer[j] = v;

        i = i + 8;
        j = j + 1; // one face at a time
    }

    // std.debug.print("Finish load OBJ to Mesh.\n", .{});
    // std.debug.print("{any}\n", .{output_buffer});
    // std.debug.print("{any}\n", .{output_idx_buffer});

    // return as a Mesh struct
    return Mesh.create(
        output_buffer, // get rid of indexing for now for simplicity
        output_idx_buffer
    );
}

// A vertex is specified via a line starting with the letter v. That is followed by (x,y,z[,w]) coordinates. W is optional and defaults to 1.0.
fn parse_vertex(vertex_array: *std.ArrayList(vec3), line: []const u8) !void {
    var line_items = std.mem.split(line, " ");
    _ = line_items.next(); // skip line header
    const x = try std.fmt.parseFloat(f32, line_items.next().?);
    const y = try std.fmt.parseFloat(f32, line_items.next().?);
    const z = try std.fmt.parseFloat(f32, line_items.next().?);
    try vertex_array.append(vec3.new(x, y, z));
}

// TODO:

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
        
        // std.debug.print("face: vertex: {s}, tex: {s}, normal: {s}\n", .{v_vertex_idx, v_texture_idx, v_normal_idx});

        try elements_array.append(.{
            .position_idx  = if (v_vertex_idx != null) ((std.fmt.parseUnsigned(u32, v_vertex_idx.?, 10) catch 1) - 1) else 0, // indexed from 1 not zero
            .texture_idx = if (v_texture_idx != null) ((std.fmt.parseUnsigned(u32, v_texture_idx.?, 10) catch 1) - 1) else 0,
            .normal_idx  = if (v_normal_idx != null) ((std.fmt.parseUnsigned(u32, v_normal_idx.?, 10) catch 1) - 1) else 0,
        });

        v_i += 1;
    }
}

fn parse_object(objects_array: *std.ArrayList(Object), line: []const u8, faces_len: usize) !void {
    var line_items = std.mem.split(line, " ");
    _ = line_items.next(); // skip line header
    var name = line_items.next().?;

    const obj = Object{
        .name = name,
        .faces_from = faces_len,
        .faces_to = 0,
        .material = "",
        .smoothing = false,
        .material_index = null
    };
    try objects_array.append(obj);
}

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