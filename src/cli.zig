const std = @import("std");

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

pub const Shell = enum {
    bash,
    zsh,
    fish,
};

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

pub const ParseError = error{NotImplemented};

pub fn parse(allocator: std.mem.Allocator, args: [][]const u8) ParseError!Args {
    _ = allocator;
    _ = args;
    return error.NotImplemented;
}
