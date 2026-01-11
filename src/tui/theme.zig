const std = @import("std");
const vaxis = @import("vaxis");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn fromHex(hex: u24) Color {
        return .{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        };
    }

    pub fn toVaxis(self: Color) vaxis.Color {
        return .{ .rgb = .{ self.r, self.g, self.b } };
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

    pub const nord = Theme{
        .primary = Color.fromHex(0x88C0D0),
        .secondary = Color.fromHex(0xA3BE8C),
        .accent = Color.fromHex(0xBF616A),
        .bg_primary = Color.fromHex(0x2E3440),
        .bg_secondary = Color.fromHex(0x3B4252),
        .bg_highlight = Color.fromHex(0x434C5E),
        .text_primary = Color.fromHex(0xD8DEE9),
        .text_secondary = Color.fromHex(0xB0B7C3),
        .text_muted = Color.fromHex(0x8F97A5),
        .match_highlight = Color.fromHex(0xEBCB8B),
        .score_bar = Color.fromHex(0x88C0D0),
        .border = Color.fromHex(0x4C566A),
    };

    pub const dracula = Theme{
        .primary = Color.fromHex(0x8BE9FD),
        .secondary = Color.fromHex(0x50FA7B),
        .accent = Color.fromHex(0xFF5555),
        .bg_primary = Color.fromHex(0x282A36),
        .bg_secondary = Color.fromHex(0x343746),
        .bg_highlight = Color.fromHex(0x3C3F50),
        .text_primary = Color.fromHex(0xF8F8F2),
        .text_secondary = Color.fromHex(0xCFCFCA),
        .text_muted = Color.fromHex(0x9A9AA3),
        .match_highlight = Color.fromHex(0xF1FA8C),
        .score_bar = Color.fromHex(0x8BE9FD),
        .border = Color.fromHex(0x44475A),
    };

    pub const gruvbox = Theme{
        .primary = Color.fromHex(0x83A598),
        .secondary = Color.fromHex(0xB8BB26),
        .accent = Color.fromHex(0xFB4934),
        .bg_primary = Color.fromHex(0x282828),
        .bg_secondary = Color.fromHex(0x3C3836),
        .bg_highlight = Color.fromHex(0x504945),
        .text_primary = Color.fromHex(0xEBDBB2),
        .text_secondary = Color.fromHex(0xD5C4A1),
        .text_muted = Color.fromHex(0xA89984),
        .match_highlight = Color.fromHex(0xFABD2F),
        .score_bar = Color.fromHex(0x83A598),
        .border = Color.fromHex(0x665C54),
    };
};

pub fn loadTheme(allocator: std.mem.Allocator, name: []const u8) !Theme {
    if (name.len > 0) {
        return resolveTheme(name);
    }

    if (std.process.getEnvVarOwned(allocator, "ZING_CONFIG")) |config_path| {
        defer allocator.free(config_path);
        if (try readThemeFromFile(allocator, config_path)) |theme_name| {
            defer allocator.free(theme_name);
            return resolveTheme(theme_name);
        }
    } else |_| {}

    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return Theme.default;
    defer allocator.free(home);
    const config_path = try std.fs.path.join(allocator, &.{ home, ".config", "zing", "config.toml" });
    defer allocator.free(config_path);
    if (try readThemeFromFile(allocator, config_path)) |theme_name| {
        defer allocator.free(theme_name);
        return resolveTheme(theme_name);
    }
    return Theme.default;
}

pub fn applyStyle(cell: *vaxis.Cell, style: Style) void {
    if (style.fg) |fg| cell.fg = fg.toVaxis();
    if (style.bg) |bg| cell.bg = bg.toVaxis();
    cell.bold = style.bold;
    cell.underline = style.underline;
    cell.italic = style.italic;
}

fn resolveTheme(name: []const u8) Theme {
    if (std.mem.eql(u8, name, "nord")) return Theme.nord;
    if (std.mem.eql(u8, name, "dracula")) return Theme.dracula;
    if (std.mem.eql(u8, name, "gruvbox")) return Theme.gruvbox;
    return Theme.default;
}

fn readThemeFromFile(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    var file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(data);

    if (findKeyValue(data, "theme")) |value| {
        return @as(?[]u8, try allocator.dupe(u8, value));
    }
    return null;
}

fn findKeyValue(data: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (!std.mem.containsAtLeast(u8, trimmed, 1, key)) continue;
        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const left = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        if (!std.mem.eql(u8, left, key)) continue;
        var right = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        if (right.len >= 2 and right[0] == '"' and right[right.len - 1] == '"') {
            right = right[1 .. right.len - 1];
        }
        return right;
    }
    return null;
}
