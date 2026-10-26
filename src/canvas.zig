const std = @import("std");

pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const Point = struct {
    x: i32,
    y: i32,
};

pub const Canvas = struct {
    width: u32,
    height: u32,
    pixels: []u8, // RGB triplets, row-major, len == width * height * 3

    pub fn init(gpa: std.mem.Allocator, width: u32, height: u32, bg: RGB) !Canvas {
        const pixels = try gpa.alloc(u8, @as(usize, width) * @as(usize, height) * 3);
        var i: usize = 0;
        while (i < pixels.len) : (i += 3) {
            pixels[i] = bg.r;
            pixels[i + 1] = bg.g;
            pixels[i + 2] = bg.b;
        }
        return .{ .width = width, .height = height, .pixels = pixels };
    }

    pub fn setPixel(self: *Canvas, x: i32, y: i32, color: RGB) void {
        if (x < 0 or y < 0) return;
        if (x >= @as(i32, @intCast(self.width)) or y >= @as(i32, @intCast(self.height))) return;
        const idx = (@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))) * 3;
        self.pixels[idx] = color.r;
        self.pixels[idx + 1] = color.g;
        self.pixels[idx + 2] = color.b;
    }

    /// Rellena uno o mas contornos (subpoligonos) usando el algoritmo de
    /// scanline con regla even-odd. Pasar un contorno exterior y uno o mas
    /// contornos interiores (agujeros) en el mismo llamado hace que las
    /// zonas cubiertas por un numero par de contornos queden sin pintar.
    pub fn fillPolygons(self: *Canvas, subpolys: []const []const Point, color: RGB) void {
        var ymin: i32 = std.math.maxInt(i32);
        var ymax: i32 = std.math.minInt(i32);
        for (subpolys) |poly| {
            for (poly) |p| {
                if (p.y < ymin) ymin = p.y;
                if (p.y > ymax) ymax = p.y;
            }
        }
        if (subpolys.len == 0) return;
        if (ymin < 0) ymin = 0;
        const max_y: i32 = @as(i32, @intCast(self.height)) - 1;
        if (ymax > max_y) ymax = max_y;

        var xs_buf: [512]f64 = undefined;

        var y = ymin;
        while (y <= ymax) : (y += 1) {
            var count: usize = 0;
            const scan: f64 = @as(f64, @floatFromInt(y)) + 0.5;

            for (subpolys) |poly| {
                const n = poly.len;
                var i: usize = 0;
                while (i < n) : (i += 1) {
                    const a = poly[i];
                    const b = poly[(i + 1) % n];
                    const ay: f64 = @floatFromInt(a.y);
                    const by: f64 = @floatFromInt(b.y);
                    if (ay == by) continue;

                    const y0 = @min(ay, by);
                    const y1 = @max(ay, by);
                    if (scan < y0 or scan >= y1) continue;

                    const ax: f64 = @floatFromInt(a.x);
                    const bx: f64 = @floatFromInt(b.x);
                    const t = (scan - ay) / (by - ay);
                    xs_buf[count] = ax + t * (bx - ax);
                    count += 1;
                }
            }

            const xs = xs_buf[0..count];
            std.mem.sort(f64, xs, {}, std.sort.asc(f64));

            var i: usize = 0;
            while (i + 1 < xs.len) : (i += 2) {
                const xl = xs[i];
                const xr = xs[i + 1];
                var xi: i32 = @intFromFloat(@ceil(xl - 0.5));
                const xend: i32 = @intFromFloat(@floor(xr - 0.5));
                while (xi <= xend) : (xi += 1) {
                    self.setPixel(xi, y, color);
                }
            }
        }
    }

    pub fn drawLine(self: *Canvas, p0: Point, p1: Point, color: RGB) void {
        var x0 = p0.x;
        var y0 = p0.y;
        const x1 = p1.x;
        const y1 = p1.y;

        const dx: i32 = if (x1 >= x0) x1 - x0 else x0 - x1;
        const dy: i32 = if (y1 >= y0) -(y1 - y0) else -(y0 - y1);
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;

        while (true) {
            self.setPixel(x0, y0, color);
            if (x0 == x1 and y0 == y1) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    pub fn strokePolygon(self: *Canvas, points: []const Point, color: RGB) void {
        const n = points.len;
        if (n < 2) return;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            self.drawLine(points[i], points[(i + 1) % n], color);
        }
    }
};
