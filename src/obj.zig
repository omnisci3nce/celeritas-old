const std = @import("std");
const allocator = @import("std").heap.c_allocator;
const za = @import("zalgebra");
const vec2 = za.vec2;
const vec3 = za.vec3;

const Vertex = struct {
    position: vec3,
    normal: vec3,
    tex_coords: vec2
};

const Texture = struct {
    id: u32,
    tex_type: []const u8
};

const Element = struct {
    pos_idx: usize,
    tex_idx: usize,
    normal_idx: usize
};

pub fn load_obj(file_path: []const u8) ![]f32 {
    var tmp_vertices = std.ArrayList(vec3).init(allocator);
    var tmp_uvs = std.ArrayList(vec2).init(allocator);
    var tmp_normals = std.ArrayList(vec3).init(allocator);
    var elements  = std.ArrayList(Element).init(allocator);


    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const reader = file.reader();

    var buf = try allocator.alloc(u8, 1024); // max line size
    defer allocator.free(buf);

    var index: u32 = 0;
    while (true) {
        var line = try reader.readUntilDelimiterOrEof(buf, '\n');
        // std.debug.print("line {any}\n", .{ line });
        index += 1;
        if (line == null) break;

        // Parse the line, copy any needed bytes due to shared buffer
        var split = std.mem.split(line.?, " "); // split line into discrete things delimited by spaces
        // if (split != null) {
        // }
        const command = split.next().?;
        if (std.mem.eql(u8, command, "v")) {
            // std.debug.print("Vertex position found \n", .{});
            // x y z of vertex comes after line header
            const x_str = split.next().?;
            const y_str = split.next().?;
            const z_str = split.next().?;
            // std.debug.print("{any}\n", .{x_str});
            const x = try std.fmt.parseFloat(f32, x_str);
            const y = try std.fmt.parseFloat(f32, y_str);
            const z = try std.fmt.parseFloat(f32, z_str);
            const pos = vec3.new(x, y, z);
            std.debug.print("vertex pos: {any}\n", .{ pos });
            try tmp_vertices.append(pos);
        } else if (std.mem.eql(u8, command, "vt")) {
            const x_str = split.next().?;
            const y_str = split.next().?;
            const x = try std.fmt.parseFloat(f32, x_str);
            const y = try std.fmt.parseFloat(f32, y_str);
            try tmp_uvs.append(vec2.new(x, y));
        } else if (std.mem.eql(u8, command, "vn")) {
            const x_str = split.next().?;
            const y_str = split.next().?;
            const z_str = split.next().?;
            const x = try std.fmt.parseFloat(f32, x_str);
            const y = try std.fmt.parseFloat(f32, y_str);
            const z = try std.fmt.parseFloat(f32, z_str);
            try tmp_normals.append(vec3.new(x, y, z));
        } else if (std.mem.eql(u8, command, "f")) { // face
            while (true) {
                if (split.next()) |vertex| {
                    var faceSplit = std.mem.split(vertex, "/");
                    var posIdx = try std.fmt.parseInt(i32, faceSplit.next().?, 10);
                    const texIdxStr = faceSplit.next().?;
                    var texIdx = if (texIdxStr.len == 0) 0 else try std.fmt.parseInt(i32, texIdxStr, 10);
                    const normalIdxStr = faceSplit.next();
                    var normalIdx = if (normalIdxStr) |str| try std.fmt.parseInt(i32, str, 10) else 0;
                    if (normalIdx < 1) {
                        normalIdx = 1; // TODO
                    }
                    if (texIdx < 1) {
                        texIdx = 1; // TODO
                    }
                    if (posIdx < 1) {
                        posIdx = 1; // TODO
                    }
                    try elements.append(.{
                        .pos_idx = @intCast(usize, posIdx-1),
                        .tex_idx = @intCast(usize, texIdx-1),
                        .normal_idx = @intCast(usize, normalIdx-1),
                    });
                } else {
                    break;
                }
            }
        }
    }
    var final = try allocator.alloc(f32, elements.items.len*8);
    defer allocator.free(final);
    var i: usize = 0;
    for (elements.items) |f| {
        const v = tmp_vertices.items[f.pos_idx];
        const t = if (tmp_uvs.items.len == 0) vec2.zero() else tmp_uvs.items[f.tex_idx];
        const n = if (tmp_normals.items.len == 0) vec3.zero() else tmp_normals.items[f.normal_idx];
        // position
        final[i] = v.x;
        final[i+1] = v.y;
        final[i+2] = v.z;
        // normal
        final[i+3] = n.x;
        final[i+4] = n.y;
        final[i+5] = n.z;
        // texture coordinate
        final[i+6] = t.x;
        final[i+7] = t.y;
        i = i + 8;
    }
    // std.debug.print("{any} \n ", .{final});
    return final;
}