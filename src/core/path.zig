const std = @import("std");

pub fn normalize(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    _ = allocator;
    _ = path;
    return error.NotImplemented;
}

pub fn isAbsolute(path: []const u8) bool {
    _ = path;
    return false;
}

test "path placeholder" {
    try std.testing.expect(true);
}
