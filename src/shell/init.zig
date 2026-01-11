pub const Shell = enum {
    bash,
    zsh,
    fish,
};

pub fn getInitScript(shell: Shell) []const u8 {
    return switch (shell) {
        .bash => @import("bash.zig").script(),
        .zsh => @import("zsh.zig").script(),
        .fish => @import("fish.zig").script(),
    };
}
