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
    show_hidden: bool = false,

    pub fn loadDirectory(self: *PreviewPane, allocator: std.mem.Allocator, path: []const u8) !void {
        self.deinit(allocator);

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        defer dir.close();

        var entries_list = std.ArrayList(DirEntry).init(allocator);
        defer entries_list.deinit();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (!self.show_hidden and entry.name.len > 0 and entry.name[0] == '.') continue;
            const name = try allocator.dupe(u8, entry.name);
            try entries_list.append(.{
                .name = name,
                .kind = kindFromEntry(entry.kind),
            });
        }

        std.sort.insertion(DirEntry, entries_list.items, {}, dirEntryLessThan);
        self.entries = try entries_list.toOwnedSlice();
        self.path = try allocator.dupe(u8, path);
        self.scroll_offset = 0;
    }

    pub fn render(self: *PreviewPane) void {
        _ = self;
    }

    pub fn deinit(self: *PreviewPane, allocator: std.mem.Allocator) void {
        if (self.path) |p| allocator.free(p);
        for (self.entries) |entry| {
            allocator.free(entry.name);
        }
        allocator.free(self.entries);
        self.path = null;
        self.entries = &.{};
    }
};

fn kindFromEntry(kind: std.fs.Dir.Entry.Kind) Kind {
    return switch (kind) {
        .file => .file,
        .directory => .directory,
        .sym_link => .symlink,
        else => .other,
    };
}

fn dirEntryLessThan(_: void, lhs: DirEntry, rhs: DirEntry) bool {
    if (lhs.kind == .directory and rhs.kind != .directory) return true;
    if (lhs.kind != .directory and rhs.kind == .directory) return false;
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}
