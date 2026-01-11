pub const Shell = enum {
    bash,
    zsh,
    fish,
};

pub fn getInitScript(shell: Shell) []const u8 {
    _ = shell;
    return "";
}
