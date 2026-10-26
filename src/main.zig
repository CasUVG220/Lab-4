const std = @import("std");

const canvas_mod = @import("canvas.zig");
const obj = @import("obj.zig");
const png = @import("png.zig");

const Canvas = canvas_mod.Canvas;
const Point = canvas_mod.Point;

const WIDTH: u32 = 800;
const HEIGHT: u32 = 800;
const BLACK = canvas_mod.RGB{ .r = 0, .g = 0, .b = 0 };
const WHITE = canvas_mod.RGB{ .r = 255, .g = 255, .b = 255 };

/// Proyeccion ortografica: escala el modelo (centrado en su bounding box en
/// X/Y) para que quepa en el lienzo con un margen. Y se invierte porque el
/// eje Y de la imagen crece hacia abajo.
fn project(v: obj.Vec3, cx: f32, cy: f32, scale: f32) Point {
    const px = (v.x - cx) * scale + @as(f32, WIDTH) / 2;
    const py = -(v.y - cy) * scale + @as(f32, HEIGHT) / 2;
    return .{ .x = @intFromFloat(@round(px)), .y = @intFromFloat(@round(py)) };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(gpa);
    const path = if (args.len > 1) args[1] else "model.obj";

    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024 * 1024));
    const model = try obj.parse(gpa, text);

    // Bounding box en X/Y.
    var min_x: f32 = std.math.inf(f32);
    var min_y: f32 = std.math.inf(f32);
    var max_x: f32 = -std.math.inf(f32);
    var max_y: f32 = -std.math.inf(f32);
    for (model.vertices) |v| {
        min_x = @min(min_x, v.x);
        max_x = @max(max_x, v.x);
        min_y = @min(min_y, v.y);
        max_y = @max(max_y, v.y);
    }
    const margin: f32 = 40;
    const scale = @min(
        (@as(f32, WIDTH) - 2 * margin) / (max_x - min_x),
        (@as(f32, HEIGHT) - 2 * margin) / (max_y - min_y),
    );
    const cx = (min_x + max_x) / 2;
    const cy = (min_y + max_y) / 2;

    var canvas = try Canvas.init(gpa, WIDTH, HEIGHT, BLACK);

    // Wireframe: tres aristas por cara triangular.
    for (model.faces) |f| {
        const a = project(model.vertices[f[0]], cx, cy, scale);
        const b = project(model.vertices[f[1]], cx, cy, scale);
        const c = project(model.vertices[f[2]], cx, cy, scale);
        canvas.drawLine(a, b, WHITE);
        canvas.drawLine(b, c, WHITE);
        canvas.drawLine(c, a, WHITE);
    }

    try png.writePng(gpa, io, "out.png", WIDTH, HEIGHT, canvas.pixels);
    std.log.info("{s}: {d} vertices, {d} caras -> out.png", .{ path, model.vertices.len, model.faces.len });
}
