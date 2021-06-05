const std = @import("std");
const allocator = @import("std").heap.c_allocator;
const za = @import("zalgebra");
const vec2 = za.vec2;
const vec3 = za.vec3;
const SplitIterator = std.mem.SplitIterator;

pub const Mesh = struct {
    vertices: []f32,
    indices: []u32
};

// Simplest case - teapot.obj
pub fn load_obj(file_path: []const u8) !Mesh {
    var tmp_vertices = std.ArrayList(f32).init(allocator);
    var tmp_vertex_indices  = std.ArrayList(u32).init(allocator);
    // defer tmp_vertices.deinit();
    // defer tmp_vertex_indices.deinit();

    // load the file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const reader = file.reader();
    const text = try reader.readAllAlloc(allocator, std.math.maxInt(u64)); // read whole thing into memory
    defer allocator.free(text);
    var lines = std.mem.split(text, "\n");

    // read each line by line
    while (lines.next()) |line| {
        // read first character
        var line_items = std.mem.split(line, " ");
        const line_header = line_items.next().?;
        // std.debug.print("{any}\n", .{line_items});
        if (std.mem.eql(u8, line_header, "v")) {
            const x = try std.fmt.parseFloat(f32, line_items.next().?);
            const y = try std.fmt.parseFloat(f32, line_items.next().?);
            const z = try std.fmt.parseFloat(f32, line_items.next().?);
            // std.debug.print("{any}/{any}/{any}\n", .{x, y, z});
            try tmp_vertices.append(x);
            try tmp_vertices.append(y);
            try tmp_vertices.append(z);
        } else if (std.mem.eql(u8, line_header, "f")) {
            const v1 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
            const v2 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
            const v3 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
            // std.debug.print("{any}/{any}/{any}\n", .{v1, v2, v3});
            try tmp_vertex_indices.append(v1 - 1);
            try tmp_vertex_indices.append(v2 - 1);
            try tmp_vertex_indices.append(v3 - 1);
        }
        // if v -> append a vertex (x, y, z)
        // if f -> append 3 vertex indices
        // switch(line_header) {
        //     'v' => {        // vertex
                // std.debug.print("vertex!\n", .{});
                
            // },
            // 'f' => {        // face
                // const v1 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
                // const v2 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
                // const v3 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
                // try tmp_vertex_indices.append(v1);
                // try tmp_vertex_indices.append(v2);
                // try tmp_vertex_indices.append(v3);
        //     },
        //     else => {},     // ignore
        // }
    }

    // return as a Mesh struct
    return Mesh{
        .vertices = tmp_vertices.toOwnedSlice(), // get rid of indexing for now for simplicity
        .indices = tmp_vertex_indices.toOwnedSlice()
    };
}

// fn load_file(file_path: []const u8) !SplitIterator {
//     const file = try std.fs.cwd().openFile(file_path, .{});
//     defer file.close();

//     const reader = file.reader();
//     const text = try reader.readAllAlloc(allocator, std.math.maxInt(u64)); // read whole thing into memory
//     defer allocator.free(text);
//     const lines_split = std.mem.split(text, "\n");

//     return lines_split;
// }