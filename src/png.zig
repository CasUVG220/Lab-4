const std = @import("std");
const Io = std.Io;

fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| {
        crc ^= byte;
        var k: usize = 0;
        while (k < 8) : (k += 1) {
            const mask: u32 = if (crc & 1 != 0) 0xFFFFFFFF else 0;
            crc = (crc >> 1) ^ (0xEDB88320 & mask);
        }
    }
    return crc ^ 0xFFFFFFFF;
}

fn adler32(data: []const u8) u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    const MOD: u32 = 65521;
    for (data) |byte| {
        a = (a + byte) % MOD;
        b = (b + a) % MOD;
    }
    return (b << 16) | a;
}

fn putU32BE(list: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u32) !void {
    try list.append(gpa, @intCast((v >> 24) & 0xFF));
    try list.append(gpa, @intCast((v >> 16) & 0xFF));
    try list.append(gpa, @intCast((v >> 8) & 0xFF));
    try list.append(gpa, @intCast(v & 0xFF));
}

fn putChunk(list: *std.ArrayList(u8), gpa: std.mem.Allocator, chunk_type: []const u8, data: []const u8) !void {
    try putU32BE(list, gpa, @intCast(data.len));

    var body = try std.ArrayList(u8).initCapacity(gpa, chunk_type.len + data.len);
    defer body.deinit(gpa);
    try body.appendSlice(gpa, chunk_type);
    try body.appendSlice(gpa, data);

    try list.appendSlice(gpa, body.items);
    try putU32BE(list, gpa, crc32(body.items));
}

/// Codifica una imagen RGB de 8 bits como PNG, usando bloques "stored"
/// (sin compresion) dentro del stream zlib del chunk IDAT. Implementado
/// sin dependencias externas: solo std.
pub fn writePng(
    gpa: std.mem.Allocator,
    io: Io,
    path: []const u8,
    width: u32,
    height: u32,
    pixels: []const u8,
) !void {
    const stride: usize = @as(usize, width) * 3;
    const raw_len: usize = @as(usize, height) * (1 + stride);
    const raw = try gpa.alloc(u8, raw_len);
    defer gpa.free(raw);

    var ri: usize = 0;
    var row: u32 = 0;
    while (row < height) : (row += 1) {
        raw[ri] = 0; // filter type: None
        ri += 1;
        const src_off = @as(usize, row) * stride;
        @memcpy(raw[ri .. ri + stride], pixels[src_off .. src_off + stride]);
        ri += stride;
    }

    var zbuf: std.ArrayList(u8) = .empty;
    defer zbuf.deinit(gpa);
    try zbuf.append(gpa, 0x78);
    try zbuf.append(gpa, 0x9C);

    const max_block: usize = 65535;
    var offset: usize = 0;
    while (true) {
        const remaining = raw_len - offset;
        const block_len = @min(remaining, max_block);
        const is_last = (offset + block_len) == raw_len;

        try zbuf.append(gpa, if (is_last) 1 else 0);
        const len16: u16 = @intCast(block_len);
        const nlen16: u16 = ~len16;
        try zbuf.append(gpa, @intCast(len16 & 0xFF));
        try zbuf.append(gpa, @intCast((len16 >> 8) & 0xFF));
        try zbuf.append(gpa, @intCast(nlen16 & 0xFF));
        try zbuf.append(gpa, @intCast((nlen16 >> 8) & 0xFF));
        try zbuf.appendSlice(gpa, raw[offset .. offset + block_len]);

        offset += block_len;
        if (is_last) break;
    }
    try putU32BE(&zbuf, gpa, adler32(raw));

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, &[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 });

    var ihdr: [13]u8 = undefined;
    ihdr[0] = @intCast((width >> 24) & 0xFF);
    ihdr[1] = @intCast((width >> 16) & 0xFF);
    ihdr[2] = @intCast((width >> 8) & 0xFF);
    ihdr[3] = @intCast(width & 0xFF);
    ihdr[4] = @intCast((height >> 24) & 0xFF);
    ihdr[5] = @intCast((height >> 16) & 0xFF);
    ihdr[6] = @intCast((height >> 8) & 0xFF);
    ihdr[7] = @intCast(height & 0xFF);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 2; // color type: truecolor (RGB)
    ihdr[10] = 0; // compression method
    ihdr[11] = 0; // filter method
    ihdr[12] = 0; // interlace method

    try putChunk(&out, gpa, "IHDR", &ihdr);
    try putChunk(&out, gpa, "IDAT", zbuf.items);
    try putChunk(&out, gpa, "IEND", &[_]u8{});

    const file = try Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, out.items);
}
