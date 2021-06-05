const std = @import("std");
const allocator = @import("std").heap.c_allocator;
const za = @import("zalgebra");
const vec2 = za.vec2;
const vec3 = za.vec3;
const SplitIterator = std.mem.SplitIterator;
const Mesh = @import("rendering.zig").Mesh;

// pub const Mesh = struct {
//     vertices: []f32,
//     indices: []u32
// };

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

        // if v -> append a vertex (x, y, z)
        // if f -> append 3 vertex indices
        switch(line_header[0]) {
            'v' => {        // vertex
                // std.debug.print("vertex!\n", .{});
                const x = try std.fmt.parseFloat(f32, line_items.next().?);
                const y = try std.fmt.parseFloat(f32, line_items.next().?);
                const z = try std.fmt.parseFloat(f32, line_items.next().?);
                try tmp_vertices.append(x);
                try tmp_vertices.append(y);
                try tmp_vertices.append(z);
                // Below: fill in normals and textures so indices work properly, will add OBJ normal and texture support later
                try tmp_vertices.append(0.0);
                try tmp_vertices.append(0.0);
                try tmp_vertices.append(0.0);
                try tmp_vertices.append(0.0);
                try tmp_vertices.append(0.0);
            },
            'f' => {        // face
                const v1 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
                const v2 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
                const v3 = try std.fmt.parseUnsigned(u32, line_items.next().?, 10);
                try tmp_vertex_indices.append(v1 - 1); // uses indexing from one so subtract one for array access
                try tmp_vertex_indices.append(v2 - 1);
                try tmp_vertex_indices.append(v3 - 1);
            },
            else => {},     // ignore
        }
    }

    // return as a Mesh struct
    return Mesh.create(
        tmp_vertices.toOwnedSlice(), // get rid of indexing for now for simplicity
        tmp_vertex_indices.toOwnedSlice()
    );
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