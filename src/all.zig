const std = @import("std");

pub const cli = @import("cli.zig");
pub const core_database = @import("core/database.zig");
pub const core_frecency = @import("core/frecency.zig");
pub const core_matcher = @import("core/matcher.zig");
pub const core_path = @import("core/path.zig");
pub const tui_app = @import("tui/app.zig");
pub const tui_theme = @import("tui/theme.zig");
pub const tui_render = @import("tui/render.zig");
pub const tui_list = @import("tui/widgets/list.zig");
pub const tui_searchbar = @import("tui/widgets/searchbar.zig");
pub const tui_preview = @import("tui/widgets/preview.zig");
pub const tui_tree = @import("tui/widgets/tree.zig");
pub const tui_statusbar = @import("tui/widgets/statusbar.zig");
pub const tui_sparkline = @import("tui/widgets/sparkline.zig");
pub const shell_init = @import("shell/init.zig");
pub const shell_bash = @import("shell/bash.zig");
pub const shell_zsh = @import("shell/zsh.zig");
pub const shell_fish = @import("shell/fish.zig");

test "all modules compile" {
    try std.testing.expect(true);
}
