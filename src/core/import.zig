const std = @import("std");
const Database = @import("database.zig").Database;

pub const ImportSource = enum {
    zoxide,
    z,
    autojump,
};

pub const ImportResult = struct {
    count: usize,
};

pub fn importData(allocator: std.mem.Allocator, db: *Database, source: ImportSource, path: ?[]const u8) !ImportResult {
    return switch (source) {
        .zoxide => importZoxide(allocator, db, path),
        .z => importZ(allocator, db, path),
        .autojump => importAutojump(allocator, db, path),
    };
}

fn importZoxide(allocator: std.mem.Allocator, db: *Database, path: ?[]const u8) !ImportResult {
    const file_path = if (path) |p| try allocator.dupe(u8, p) else try defaultZoxidePath(allocator);
    defer allocator.free(file_path);
    const data = try readTextFile(allocator, file_path);
    defer allocator.free(data);

    var count: usize = 0;
    var it = std.mem.split(u8, data, "\n");
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        var fields = std.mem.split(u8, trimmed, "\t");
        const path_field = fields.next() orelse continue;
        const score_field = fields.next() orelse continue;
        const time_field = fields.next() orelse "";
        const score = std.fmt.parseFloat(f64, score_field) catch continue;
        const last_access = if (time_field.len > 0)
            std.fmt.parseInt(i64, time_field, 10) catch std.time.timestamp()
        else
            std.time.timestamp();
        const access_count = @max(@as(i64, 1), @as(i64, @intFromFloat(score)));
        try db.mergeImport(path_field, score, last_access, access_count);
        count += 1;
    }
    return .{ .count = count };
}

fn importZ(allocator: std.mem.Allocator, db: *Database, path: ?[]const u8) !ImportResult {
    const file_path = if (path) |p| try allocator.dupe(u8, p) else try defaultZPath(allocator);
    defer allocator.free(file_path);
    const data = try readTextFile(allocator, file_path);
    defer allocator.free(data);

    var count: usize = 0;
    var it = std.mem.split(u8, data, "\n");
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        var fields = std.mem.split(u8, trimmed, "|");
        const path_field = fields.next() orelse continue;
        const rank_field = fields.next() orelse continue;
        const time_field = fields.next() orelse "";
        const score = std.fmt.parseFloat(f64, rank_field) catch continue;
        const last_access = if (time_field.len > 0)
            std.fmt.parseInt(i64, time_field, 10) catch std.time.timestamp()
        else
            std.time.timestamp();
        const access_count = @max(@as(i64, 1), @as(i64, @intFromFloat(score)));
        try db.mergeImport(path_field, score, last_access, access_count);
        count += 1;
    }
    return .{ .count = count };
}

fn importAutojump(allocator: std.mem.Allocator, db: *Database, path: ?[]const u8) !ImportResult {
    const file_path = if (path) |p| try allocator.dupe(u8, p) else try defaultAutojumpPath(allocator);
    defer allocator.free(file_path);
    const data = try readTextFile(allocator, file_path);
    defer allocator.free(data);

    var count: usize = 0;
    var it = std.mem.split(u8, data, "\n");
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        var fields = std.mem.split(u8, trimmed, "\t");
        const weight_field = fields.next() orelse continue;
        const path_field = fields.next() orelse continue;
        const score = std.fmt.parseFloat(f64, weight_field) catch continue;
        const access_count = @max(@as(i64, 1), @as(i64, @intFromFloat(score)));
        try db.mergeImport(path_field, score, std.time.timestamp(), access_count);
        count += 1;
    }
    return .{ .count = count };
}

fn readTextFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 8 * 1024 * 1024);
    if (std.mem.indexOfScalar(u8, data, 0)) |_| {
        return error.UnsupportedFormat;
    }
    return data;
}

fn defaultZoxidePath(allocator: std.mem.Allocator) ![]u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".local", "share", "zoxide", "db.zo" });
}

fn defaultZPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".z" });
}

fn defaultAutojumpPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".local", "share", "autojump", "autojump.txt" });
}
