const std = @import("std");

pub const Vec3 = struct { x: f32, y: f32, z: f32 };
pub const Face = [3]u32;

pub const Model = struct {
    vertices: []Vec3,
    faces: []Face,
};

/// Parsea un .obj triangulado: lineas `v x y z` y `f a b c` (indices base 1,
/// tolera el formato `v/vt/vn`). Ignora todo lo demas.
pub fn parse(gpa: std.mem.Allocator, text: []const u8) !Model {
    var vertices: std.ArrayList(Vec3) = .empty;
    var faces: std.ArrayList(Face) = .empty;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len < 2) continue;
        var tok = std.mem.tokenizeAny(u8, line, " \t");
        const kind = tok.next().?;
        if (std.mem.eql(u8, kind, "v")) {
            const x = try std.fmt.parseFloat(f32, tok.next() orelse return error.BadVertex);
            const y = try std.fmt.parseFloat(f32, tok.next() orelse return error.BadVertex);
            const z = try std.fmt.parseFloat(f32, tok.next() orelse return error.BadVertex);
            try vertices.append(gpa, .{ .x = x, .y = y, .z = z });
        } else if (std.mem.eql(u8, kind, "f")) {
            var idx: [3]u32 = undefined;
            for (&idx) |*slot| {
                const t = tok.next() orelse return error.BadFace;
                const num = t[0 .. std.mem.indexOfScalar(u8, t, '/') orelse t.len];
                slot.* = (try std.fmt.parseInt(u32, num, 10)) - 1;
            }
            try faces.append(gpa, idx);
        }
    }
    return .{ .vertices = try vertices.toOwnedSlice(gpa), .faces = try faces.toOwnedSlice(gpa) };
}
