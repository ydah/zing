const std = @import("std");
const shell_init = @import("shell/init.zig");

pub const Command = enum {
    query,
    interactive,
    add,
    remove,
    list,
    stats,
    config,
    init,
    import_data,
    help,
    version,
};

pub const Format = enum {
    json,
    text,
};

pub const ImportSource = enum {
    zoxide,
    z,
    autojump,
};

pub const Shell = shell_init.Shell;

pub const Args = struct {
    command: Command,
    positional: [][]const u8,
    flags: Flags,

    pub const Flags = struct {
        help: bool = false,
        version: bool = false,
        no_tui: bool = false,
        threshold: ?f64 = null,
        limit: ?usize = null,
        format: ?Format = null,
        from: ?ImportSource = null,
        shell: ?Shell = null,
    };
};

pub const ParseError = error{
    OutOfMemory,
    MissingValue,
    InvalidValue,
    UnknownFlag,
    UnknownCommand,
};

pub fn parse(allocator: std.mem.Allocator, args: [][]const u8) ParseError!Args {
    var flags = Args.Flags{};
    var positional = std.array_list.Managed([]const u8).init(allocator);
    errdefer positional.deinit();

    if (args.len == 0) {
        const empty = try allocator.alloc([]const u8, 0);
        return Args{ .command = .interactive, .positional = empty, .flags = flags };
    }

    const cmd_name = std.fs.path.basename(args[0]);
    var command: Command = .interactive;
    var idx: usize = 1;

    if (std.mem.eql(u8, cmd_name, "zing")) {
        if (args.len > 1 and args[1].len > 0 and args[1][0] != '-') {
            command = try parseCommand(args[1]);
            idx = 2;
        } else {
            command = .interactive;
        }
    } else if (std.mem.eql(u8, cmd_name, "zi")) {
        command = .interactive;
    } else if (std.mem.eql(u8, cmd_name, "z")) {
        command = .query;
    } else {
        command = .query;
    }

    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (arg.len == 0) continue;

        if (std.mem.eql(u8, arg, "--")) {
            idx += 1;
            while (idx < args.len) : (idx += 1) {
                try positional.append(args[idx]);
            }
            break;
        }

        if (arg[0] != '-') {
            try positional.append(arg);
            continue;
        }

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            flags.help = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            flags.version = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-tui")) {
            flags.no_tui = true;
            continue;
        }

        if (try parseValueFlag("threshold", arg, args, &idx)) |value| {
            flags.threshold = try parseFloat(value);
            continue;
        }
        if (try parseValueFlag("limit", arg, args, &idx)) |value| {
            flags.limit = try parseUnsigned(value);
            continue;
        }
        if (try parseValueFlag("format", arg, args, &idx)) |value| {
            flags.format = try parseFormat(value);
            continue;
        }
        if (try parseValueFlag("from", arg, args, &idx)) |value| {
            flags.from = try parseImportSource(value);
            continue;
        }
        if (try parseValueFlag("shell", arg, args, &idx)) |value| {
            flags.shell = try parseShell(value);
            continue;
        }

        return error.UnknownFlag;
    }

    return Args{
        .command = command,
        .positional = try positional.toOwnedSlice(),
        .flags = flags,
    };
}

pub fn usage() []const u8 {
    return
        \\zing - modern directory jumper
        \\
        \\Usage:
        \\  zing [command] [options] [args...]
        \\  z <query>...
        \\  zi [query]
        \\
        \\Commands:
        \\  query, interactive, add, remove, list, stats, config, init, import, help, version
        \\
        \\Options:
        \\  -h, --help
        \\  -V, --version
        \\  --no-tui
        \\  --threshold=<n>
        \\  --limit=<n>
        \\  --format=<json|text>
        \\  --from=<zoxide|z|autojump>
        \\  --shell=<bash|zsh|fish>
        \\
    ;
}

fn parseCommand(arg: []const u8) ParseError!Command {
    if (std.mem.eql(u8, arg, "query")) return .query;
    if (std.mem.eql(u8, arg, "interactive")) return .interactive;
    if (std.mem.eql(u8, arg, "add")) return .add;
    if (std.mem.eql(u8, arg, "remove")) return .remove;
    if (std.mem.eql(u8, arg, "list")) return .list;
    if (std.mem.eql(u8, arg, "stats")) return .stats;
    if (std.mem.eql(u8, arg, "config")) return .config;
    if (std.mem.eql(u8, arg, "init")) return .init;
    if (std.mem.eql(u8, arg, "import") or std.mem.eql(u8, arg, "import_data")) return .import_data;
    if (std.mem.eql(u8, arg, "help")) return .help;
    if (std.mem.eql(u8, arg, "version")) return .version;
    return error.UnknownCommand;
}

fn parseValueFlag(
    comptime name: []const u8,
    arg: []const u8,
    args: [][]const u8,
    idx: *usize,
) ParseError!?[]const u8 {
    const prefix = "--" ++ name ++ "=";
    if (std.mem.startsWith(u8, arg, prefix)) {
        return arg[prefix.len..];
    }
    if (std.mem.eql(u8, arg, "--" ++ name)) {
        if (idx.* + 1 >= args.len) return error.MissingValue;
        idx.* += 1;
        return args[idx.*];
    }
    return null;
}

fn parseFloat(value: []const u8) ParseError!f64 {
    return std.fmt.parseFloat(f64, value) catch return error.InvalidValue;
}

fn parseUnsigned(value: []const u8) ParseError!usize {
    return std.fmt.parseInt(usize, value, 10) catch return error.InvalidValue;
}

fn parseFormat(value: []const u8) ParseError!Format {
    if (std.mem.eql(u8, value, "json")) return .json;
    if (std.mem.eql(u8, value, "text")) return .text;
    return error.InvalidValue;
}

fn parseImportSource(value: []const u8) ParseError!ImportSource {
    if (std.mem.eql(u8, value, "zoxide")) return .zoxide;
    if (std.mem.eql(u8, value, "z")) return .z;
    if (std.mem.eql(u8, value, "autojump")) return .autojump;
    return error.InvalidValue;
}

fn parseShell(value: []const u8) ParseError!Shell {
    if (std.mem.eql(u8, value, "bash")) return .bash;
    if (std.mem.eql(u8, value, "zsh")) return .zsh;
    if (std.mem.eql(u8, value, "fish")) return .fish;
    return error.InvalidValue;
}
