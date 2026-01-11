const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b };
    }
};

pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    underline: bool = false,
    italic: bool = false,
};

pub const Theme = struct {
    primary: Color,
    secondary: Color,
    accent: Color,
    bg_primary: Color,
    bg_secondary: Color,
    bg_highlight: Color,
    text_primary: Color,
    text_secondary: Color,
    text_muted: Color,
    match_highlight: Color,
    score_bar: Color,
    border: Color,

    pub const default = Theme{
        .primary = Color.rgb(97, 175, 239),
        .secondary = Color.rgb(152, 195, 121),
        .accent = Color.rgb(224, 108, 117),
        .bg_primary = Color.rgb(40, 44, 52),
        .bg_secondary = Color.rgb(50, 55, 65),
        .bg_highlight = Color.rgb(60, 65, 75),
        .text_primary = Color.rgb(171, 178, 191),
        .text_secondary = Color.rgb(130, 137, 151),
        .text_muted = Color.rgb(92, 99, 112),
        .match_highlight = Color.rgb(229, 192, 123),
        .score_bar = Color.rgb(97, 175, 239),
        .border = Color.rgb(92, 99, 112),
    };

    pub const nord = default;
    pub const dracula = default;
    pub const gruvbox = default;
};

pub fn loadTheme(allocator: std.mem.Allocator, name: []const u8) !Theme {
    _ = allocator;
    _ = name;
    return Theme.default;
}

pub fn applyStyle() void {}
