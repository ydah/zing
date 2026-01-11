const std = @import("std");
const Database = @import("database.zig").Database;

/// Supported import sources.
pub const ImportSource = enum {
    zoxide,
    z,
    autojump,
};

/// Result of an import operation.
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
    const data = readTextFile(allocator, file_path) catch |err| switch (err) {
        error.UnsupportedFormat => return importZoxideBinary(allocator, db, file_path),
        else => return err,
    };
    defer allocator.free(data);
    return importZoxideText(db, data);
}

fn importZoxideBinary(allocator: std.mem.Allocator, db: *Database, path: []const u8) !ImportResult {
    if (try runZoxideDump(allocator, path)) |dump| {
        defer allocator.free(dump);
        return importZoxideText(db, dump);
    }
    return error.UnsupportedFormat;
}

fn importZoxideText(db: *Database, data: []const u8) !ImportResult {
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

fn runZoxideDump(allocator: std.mem.Allocator, db_path: []const u8) !?[]u8 {
    var argv = [_][]const u8{ "zoxide", "query", "-ls" };
    var child = std.process.Child.init(&argv, allocator);
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    env_map.put("ZOXIDE_DB_PATH", db_path) catch {};
    env_map.put("ZOXIDE_DB", db_path) catch {};
    child.env_map = &env_map;
    const result = child.run() catch return null;
    defer allocator.free(result.stderr);
    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        // Retry without score flag.
        var argv2 = [_][]const u8{ "zoxide", "query", "-l" };
        var child2 = std.process.Child.init(&argv2, allocator);
        child2.env_map = &env_map;
        const result2 = child2.run() catch return null;
        defer allocator.free(result2.stderr);
        if (result2.term.Exited != 0) {
            allocator.free(result2.stdout);
            return null;
        }
        return result2.stdout;
    }
    return result.stdout;
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

test "import z format parses entries" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try tmp.dir.realpathAlloc(allocator, "z.txt");
    defer allocator.free(path);

    var file = try tmp.dir.createFile("z.txt", .{});
    defer file.close();
    try file.writeAll("/tmp|5|1700000000\n");

    var db = try Database.init(allocator, "");
    defer db.deinit();

    const res = try importZ(allocator, &db, path);
    try std.testing.expectEqual(@as(usize, 1), res.count);
}
