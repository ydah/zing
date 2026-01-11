const std = @import("std");

pub const Kind = enum {
    file,
    directory,
    symlink,
    other,
};

pub const DirEntry = struct {
    name: []const u8,
    kind: Kind,
};

pub const PreviewPane = struct {
    path: ?[]const u8 = null,
    entries: []DirEntry = &.{},
    scroll_offset: usize = 0,

    pub fn loadDirectory(self: *PreviewPane, allocator: std.mem.Allocator, path: []const u8) !void {
        _ = self;
        _ = allocator;
        _ = path;
    }

    pub fn render(self: *PreviewPane) void {
        _ = self;
    }
};
