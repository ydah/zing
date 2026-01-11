const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const Database = @import("core/database.zig").Database;
const shell_init = @import("shell/init.zig");

const CommandError = error{
    MissingArgument,
    InvalidArgument,
};

pub fn main() !void {
    setupSignals();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

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
    const query = try joinArgs(std.heap.page_allocator, args.positional);
    defer std.heap.page_allocator.free(query);

    const limit = args.flags.limit orelse 1;
    const results = try db.search(std.heap.page_allocator, query, limit);
    defer freeEntries(std.heap.page_allocator, results);

    if (results.len == 0) return;
    try std.io.getStdOut().writer().print("{s}\n", .{results[0].path});
}

fn handleInteractive(args: cli.Args, db: *Database) !void {
    _ = args;
    _ = db;
    std.log.warn("interactive mode is not implemented yet", .{});
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
            const out = std.io.getStdOut().writer();
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
            var buffer = std.ArrayList(u8).init(arena.allocator());
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
            try std.io.getStdOut().writeAll(buffer.items);
        },
    }
}

fn handleStats(args: cli.Args, db: *Database) !void {
    _ = args;
    _ = db;
    std.log.warn("stats mode is not implemented yet", .{});
}

fn handleConfig(args: cli.Args) !void {
    _ = args;
    std.log.warn("config command is not implemented yet", .{});
}

fn handleInit(args: cli.Args) !void {
    const shell = args.flags.shell orelse blk: {
        if (args.positional.len > 0) {
            break :blk parseShellName(args.positional[0]) orelse return CommandError.InvalidArgument;
        }
        break :blk cli.Shell.bash;
    };
    const script = shell_init.getInitScript(shell);
    try std.io.getStdOut().writer().print("{s}", .{script});
}

fn handleImport(args: cli.Args, db: *Database) !void {
    _ = args;
    _ = db;
    std.log.warn("import command is not implemented yet", .{});
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

fn parseShellName(name: []const u8) ?cli.Shell {
    if (std.mem.eql(u8, name, "bash")) return .bash;
    if (std.mem.eql(u8, name, "zsh")) return .zsh;
    if (std.mem.eql(u8, name, "fish")) return .fish;
    return null;
}

fn setupSignals() void {
    if (builtin.os.tag == .windows) return;
    const handler = struct {
        fn handle(_: c_int) callconv(.C) void {
            std.process.exit(0);
        }
    }.handle;

    var action = std.posix.Sigaction{
        .handler = .{ .handler = handler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    _ = std.posix.sigaction(std.posix.SIG.INT, &action, null) catch {};
    _ = std.posix.sigaction(std.posix.SIG.TERM, &action, null) catch {};
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
