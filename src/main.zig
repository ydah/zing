const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const config_mod = @import("core/config.zig");
const Database = @import("core/database.zig").Database;
const import_mod = @import("core/import.zig");
const shell_init = @import("shell/init.zig");
const sparkline = @import("tui/widgets/sparkline.zig");

const CommandError = error{
    MissingArgument,
    InvalidArgument,
};

pub fn main() !void {
    setupSignals();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const argv_z = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv_z);
    const argv = try allocator.alloc([]const u8, argv_z.len);
    defer allocator.free(argv);
    for (argv_z, 0..) |arg, idx| {
        argv[idx] = arg;
    }

    const parsed = cli.parse(allocator, argv) catch |err| {
        std.log.err("invalid arguments: {s}", .{@errorName(err)});
        std.log.err("{s}", .{cli.usage()});
        return;
    };
    defer allocator.free(parsed.positional);

    if (parsed.flags.help or parsed.command == .help) {
        handleHelp();
        return;
    }
    if (parsed.flags.version or parsed.command == .version) {
        handleVersion();
        return;
    }

    switch (parsed.command) {
        .query => try withDb(allocator, parsed, handleQuery),
        .interactive => try withDb(allocator, parsed, handleInteractive),
        .add => try withDb(allocator, parsed, handleAdd),
        .remove => try withDb(allocator, parsed, handleRemove),
        .list => try withDb(allocator, parsed, handleList),
        .stats => try withDb(allocator, parsed, handleStats),
        .import_data => try withDb(allocator, parsed, handleImport),
        .config => try handleConfig(parsed),
        .init => try handleInit(parsed),
        .help, .version => {},
    }
}

fn stdoutWriter() std.fs.File.DeprecatedWriter {
    return std.fs.File.stdout().deprecatedWriter();
}

fn withDb(
    allocator: std.mem.Allocator,
    args: cli.Args,
    handler: fn (cli.Args, *Database) anyerror!void,
) !void {
    var db = try Database.init(allocator, "");
    defer db.deinit();
    handler(args, &db) catch |err| {
        reportError(err);
        return;
    };
}

fn handleQuery(args: cli.Args, db: *Database) !void {
    const parsed = try parseSubdirQuery(std.heap.page_allocator, args.positional);
    defer std.heap.page_allocator.free(parsed.query);
    if (parsed.sub_query) |sub_query| {
        defer std.heap.page_allocator.free(sub_query);
        try handleSubdirQuery(db, parsed.query, sub_query);
        return;
    }

    const limit = args.flags.limit orelse 1;
    const results = try db.search(std.heap.page_allocator, parsed.query, limit);
    defer freeEntries(std.heap.page_allocator, results);

    if (results.len == 0) return;
    try stdoutWriter().print("{s}\n", .{results[0].path});
}

fn handleInteractive(args: cli.Args, db: *Database) !void {
    var app = try @import("tui/app.zig").App.init(std.heap.page_allocator, db);
    defer app.deinit();

    if (args.positional.len > 0) {
        for (args.positional) |part| {
            app.state.searchbar.insertText(part);
            app.state.searchbar.insertChar(' ');
        }
    }

    const selected = try app.run();
    if (selected) |path| {
        defer std.heap.page_allocator.free(path);
        try stdoutWriter().print("{s}\n", .{path});
    }
}

fn handleAdd(args: cli.Args, db: *Database) !void {
    if (args.positional.len == 0) return CommandError.MissingArgument;
    try db.add(args.positional[0]);
}

fn handleRemove(args: cli.Args, db: *Database) !void {
    if (args.positional.len == 0) return CommandError.MissingArgument;
    try db.remove(args.positional[0]);
}

fn handleList(args: cli.Args, db: *Database) !void {
    const results = try db.getAll(std.heap.page_allocator);
    defer freeEntries(std.heap.page_allocator, results);

    const format = args.flags.format orelse .text;
    const limit = args.flags.limit orelse results.len;
    const threshold = args.flags.threshold;

    switch (format) {
        .text => {
            const out = stdoutWriter();
            var count: usize = 0;
            for (results) |entry| {
                if (threshold) |min_score| {
                    if (entry.score < min_score) continue;
                }
                if (count >= limit) break;
                try out.print("{d:.3}\t{s}\n", .{ entry.score, entry.path });
                count += 1;
            }
        },
        .json => {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            var buffer = std.array_list.Managed(u8).init(arena.allocator());
            try buffer.appendSlice("[");
            var first = true;
            var count: usize = 0;
            for (results) |entry| {
                if (threshold) |min_score| {
                    if (entry.score < min_score) continue;
                }
                if (count >= limit) break;
                if (!first) try buffer.appendSlice(",");
                first = false;
                try buffer.writer().print(
                    \\{{"path":"{s}","score":{d:.3},"last_access":{d},"access_count":{d},"created_at":{d}}}
                , .{ entry.path, entry.score, entry.last_access, entry.access_count, entry.created_at });
                count += 1;
            }
            try buffer.appendSlice("]\n");
            try stdoutWriter().writeAll(buffer.items);
        },
    }
}

fn handleStats(args: cli.Args, db: *Database) !void {
    _ = args;
    const entries = try db.getAll(std.heap.page_allocator);
    defer freeEntries(std.heap.page_allocator, entries);

    const now = std.time.timestamp();
    const day_seconds: i64 = 86400;
    const start_today = now - @mod(now, day_seconds);

    var total_visits: i64 = 0;
    var unique_today: usize = 0;
    var activity = [_]f64{0} ** 7;

    for (entries) |entry| {
        total_visits += entry.access_count;
        if (entry.last_access >= start_today) unique_today += 1;
        if (entry.last_access <= now) {
            const days_ago = @divTrunc(now - entry.last_access, day_seconds);
            if (days_ago >= 0 and days_ago < 7) {
                const idx = @as(usize, @intCast(6 - days_ago));
                activity[idx] += 1.0;
            }
        }
    }

    const spark = try sparkline.renderSparkline(std.heap.page_allocator, &activity);
    defer std.heap.page_allocator.free(spark);

    const out = stdoutWriter();
    try out.print("Total directories: {d}\n", .{entries.len});
    try out.print("Total visits: {d}\n", .{total_visits});
    try out.print("Unique today: {d}\n", .{unique_today});
    try out.print("Activity (7 days): {s}\n", .{spark});
}

fn handleConfig(args: cli.Args) !void {
    var cfg = try config_mod.Config.load(std.heap.page_allocator);
    defer cfg.deinit();

    if (args.positional.len == 0) {
        try cfg.writeTo(stdoutWriter());
        return;
    }
    if (std.mem.eql(u8, args.positional[0], "set")) {
        if (args.positional.len < 3) return CommandError.MissingArgument;
        try cfg.setValue(args.positional[1], args.positional[2]);
        try cfg.write();
        return;
    }
    return CommandError.InvalidArgument;
}

fn handleInit(args: cli.Args) !void {
    const shell = args.flags.shell orelse blk: {
        if (args.positional.len > 0) {
            break :blk parseShellName(args.positional[0]) orelse return CommandError.InvalidArgument;
        }
        break :blk cli.Shell.bash;
    };
    const script = shell_init.getInitScript(shell);
    try stdoutWriter().print("{s}", .{script});
}

fn handleImport(args: cli.Args, db: *Database) !void {
    const source = args.flags.from orelse return CommandError.MissingArgument;
    const path = if (args.positional.len > 0) args.positional[0] else null;
    const mapped = switch (source) {
        .zoxide => import_mod.ImportSource.zoxide,
        .z => import_mod.ImportSource.z,
        .autojump => import_mod.ImportSource.autojump,
    };
    const result = try import_mod.importData(std.heap.page_allocator, db, mapped, path);
    try stdoutWriter().print("imported {d} entries\n", .{result.count});
}

fn handleHelp() void {
    std.log.info("{s}", .{cli.usage()});
}

fn handleVersion() void {
    std.log.info("zing 0.0.0", .{});
}

fn joinArgs(allocator: std.mem.Allocator, parts: [][]const u8) ![]u8 {
    if (parts.len == 0) return try allocator.alloc(u8, 0);
    return std.mem.join(allocator, " ", parts);
}

fn freeEntries(allocator: std.mem.Allocator, entries: []const @import("core/database.zig").Entry) void {
    for (entries) |entry| {
        allocator.free(entry.path);
    }
    allocator.free(entries);
}

fn parseSubdirQuery(allocator: std.mem.Allocator, parts: [][]const u8) !struct {
    query: []u8,
    sub_query: ?[]u8,
} {
    var base = std.array_list.Managed([]const u8).init(allocator);
    defer base.deinit();
    var sub_query: ?[]u8 = null;
    for (parts) |part| {
        if (std.mem.startsWith(u8, part, "/")) {
            sub_query = try allocator.dupe(u8, part[1..]);
            break;
        }
        try base.append(part);
    }
    return .{
        .query = try std.mem.join(allocator, " ", base.items),
        .sub_query = sub_query,
    };
}

fn handleSubdirQuery(db: *Database, query: []const u8, sub_query: []const u8) !void {
    const results = try db.search(std.heap.page_allocator, query, 1);
    defer freeEntries(std.heap.page_allocator, results);
    if (results.len == 0) return;
    const base = results[0].path;
    if (sub_query.len == 0) {
        try stdoutWriter().print("{s}\n", .{base});
        return;
    }

    const best = try findBestSubdir(std.heap.page_allocator, base, sub_query);
    defer if (best) |p| std.heap.page_allocator.free(p);
    if (best) |path| {
        try stdoutWriter().print("{s}\n", .{path});
    }
}

fn findBestSubdir(allocator: std.mem.Allocator, base: []const u8, query: []const u8) !?[]u8 {
    var dir = std.fs.cwd().openDir(base, .{ .iterate = true }) catch return null;
    defer dir.close();

    var best_score: i32 = std.math.minInt(i32);
    var best_path: ?[]u8 = null;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        const match = try @import("core/matcher.zig").fuzzyMatch(allocator, query, entry.name);
        if (match) |m| {
            if (m.score > best_score) {
                if (best_path) |prev| allocator.free(prev);
                best_score = m.score;
                best_path = try std.fs.path.join(allocator, &.{ base, entry.name });
            }
            allocator.free(m.positions);
        }
    }
    return best_path;
}

fn parseShellName(name: []const u8) ?cli.Shell {
    if (std.mem.eql(u8, name, "bash")) return .bash;
    if (std.mem.eql(u8, name, "zsh")) return .zsh;
    if (std.mem.eql(u8, name, "fish")) return .fish;
    return null;
}

fn setupSignals() void {
    if (builtin.os.tag == .windows) return;
    const handler = struct {
        fn handle(_: c_int) callconv(.c) void {
            std.process.exit(0);
        }
    }.handle;

    var action = std.posix.Sigaction{
        .handler = .{ .handler = handler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &action, null);
    std.posix.sigaction(std.posix.SIG.TERM, &action, null);
}

fn reportError(err: anyerror) void {
    if (err == CommandError.MissingArgument) {
        std.log.err("missing argument", .{});
    } else if (err == CommandError.InvalidArgument) {
        std.log.err("invalid argument", .{});
    } else {
        std.log.err("{s}", .{@errorName(err)});
    }
    if (builtin.mode == .Debug) {
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    }
}
