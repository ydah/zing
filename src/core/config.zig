const std = @import("std");

/// Application configuration loaded from TOML and defaults.
pub const Config = struct {
    arena: std.heap.ArenaAllocator,
    general: General,
    scoring: Scoring,
    matching: Matching,
    tui: Tui,
    exclude: Exclude,

    pub fn load(allocator: std.mem.Allocator) !Config {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const alloc = arena.allocator();

        var cfg = Config{
            .arena = arena,
            .general = General{
                .data_dir = try alloc.dupe(u8, "~/.local/share/zing"),
                .cmd_alias = try alloc.dupe(u8, "z"),
                .interactive_alias = try alloc.dupe(u8, "zi"),
            },
            .scoring = Scoring{
                .half_life = 604800.0,
                .match_weight = 1.0,
                .max_score = 1000.0,
                .min_score = 0.01,
            },
            .matching = Matching{
                .case_sensitivity = try alloc.dupe(u8, "smart"),
                .search_type = try alloc.dupe(u8, "fuzzy"),
            },
            .tui = Tui{
                .theme = try alloc.dupe(u8, "default"),
                .show_preview = true,
                .show_score_bar = true,
                .highlight_matches = true,
            },
            .exclude = Exclude{
                .patterns = &.{},
            },
        };

        const config_path = try defaultConfigPath(alloc);
        if (try readConfigFile(alloc, config_path)) |file_data| {
            defer alloc.free(file_data);
            applyToml(&cfg, file_data);
        }

        return cfg;
    }

    pub fn deinit(self: *Config) void {
        self.arena.deinit();
    }

    pub fn write(self: *Config) !void {
        const allocator = self.arena.child_allocator;
        const path = try defaultConfigPath(allocator);
        defer allocator.free(path);

        const dir = std.fs.path.dirname(path) orelse ".";
        try std.fs.cwd().makePath(dir);

        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();

        try self.writeTo(file.deprecatedWriter());
    }

    pub fn writeTo(self: *Config, writer: anytype) !void {
        try writer.print(
            \\[general]
            \\data_dir = "{s}"
            \\cmd_alias = "{s}"
            \\interactive_alias = "{s}"
            \\
            \\[scoring]
            \\half_life = {d}
            \\match_weight = {d}
            \\max_score = {d}
            \\min_score = {d}
            \\
            \\[matching]
            \\case_sensitivity = "{s}"
            \\search_type = "{s}"
            \\
            \\[tui]
            \\theme = "{s}"
            \\show_preview = {s}
            \\show_score_bar = {s}
            \\highlight_matches = {s}
            \\
        , .{
            self.general.data_dir,
            self.general.cmd_alias,
            self.general.interactive_alias,
            self.scoring.half_life,
            self.scoring.match_weight,
            self.scoring.max_score,
            self.scoring.min_score,
            self.matching.case_sensitivity,
            self.matching.search_type,
            self.tui.theme,
            boolLiteral(self.tui.show_preview),
            boolLiteral(self.tui.show_score_bar),
            boolLiteral(self.tui.highlight_matches),
        });

        try writer.writeAll("[exclude]\npatterns = [");
        for (self.exclude.patterns, 0..) |pattern, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{pattern});
        }
        try writer.writeAll("]\n");
    }

    pub fn setValue(self: *Config, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "general.data_dir")) {
            self.general.data_dir = try self.dupe(value);
        } else if (std.mem.eql(u8, key, "general.cmd_alias")) {
            self.general.cmd_alias = try self.dupe(value);
        } else if (std.mem.eql(u8, key, "general.interactive_alias")) {
            self.general.interactive_alias = try self.dupe(value);
        } else if (std.mem.eql(u8, key, "scoring.half_life")) {
            self.scoring.half_life = try parseFloat(value);
        } else if (std.mem.eql(u8, key, "scoring.match_weight")) {
            self.scoring.match_weight = try parseFloat(value);
        } else if (std.mem.eql(u8, key, "scoring.max_score")) {
            self.scoring.max_score = try parseFloat(value);
        } else if (std.mem.eql(u8, key, "scoring.min_score")) {
            self.scoring.min_score = try parseFloat(value);
        } else if (std.mem.eql(u8, key, "matching.case_sensitivity")) {
            self.matching.case_sensitivity = try self.dupe(value);
        } else if (std.mem.eql(u8, key, "matching.search_type")) {
            self.matching.search_type = try self.dupe(value);
        } else if (std.mem.eql(u8, key, "tui.theme")) {
            self.tui.theme = try self.dupe(value);
        } else if (std.mem.eql(u8, key, "tui.show_preview")) {
            self.tui.show_preview = try parseBool(value);
        } else if (std.mem.eql(u8, key, "tui.show_score_bar")) {
            self.tui.show_score_bar = try parseBool(value);
        } else if (std.mem.eql(u8, key, "tui.highlight_matches")) {
            self.tui.highlight_matches = try parseBool(value);
        } else {
            return error.InvalidKey;
        }
    }

    fn dupe(self: *Config, value: []const u8) ![]const u8 {
        return self.arena.allocator().dupe(u8, value);
    }
};

/// General settings.
pub const General = struct {
    data_dir: []const u8,
    cmd_alias: []const u8,
    interactive_alias: []const u8,
};

/// Scoring configuration for frecency and matching weight.
pub const Scoring = struct {
    half_life: f64,
    match_weight: f64,
    max_score: f64,
    min_score: f64,
};

/// Matching behavior settings.
pub const Matching = struct {
    case_sensitivity: []const u8,
    search_type: []const u8,
};

/// TUI display settings.
pub const Tui = struct {
    theme: []const u8,
    show_preview: bool,
    show_score_bar: bool,
    highlight_matches: bool,
};

/// Exclusion patterns.
pub const Exclude = struct {
    patterns: [][]const u8,
};

fn defaultConfigPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "ZING_CONFIG")) |path| {
        return path;
    } else |_| {}
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".config", "zing", "config.toml" });
}

fn readConfigFile(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    var file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();
    return try file.readToEndAlloc(allocator, 64 * 1024);
}

fn applyToml(cfg: *Config, data: []const u8) void {
    var section: []const u8 = "";
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        var trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
            section = trimmed[1 .. trimmed.len - 1];
            continue;
        }
        const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
        const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
        if (std.mem.eql(u8, section, "exclude") and std.mem.eql(u8, key, "patterns")) {
            if (parseStringArray(cfg.arena.allocator(), value)) |patterns| {
                cfg.exclude.patterns = patterns;
            }
            continue;
        }

        const full_key = if (section.len == 0)
            key
        else
            std.mem.join(cfg.arena.allocator(), ".", &.{ section, key }) catch continue;
        if (full_key.len == 0) continue;
        _ = cfg.setValue(full_key, stripQuotes(value)) catch {};
    }
}

fn parseStringArray(allocator: std.mem.Allocator, value: []const u8) ?[][]const u8 {
    var trimmed = std.mem.trim(u8, value, " \t");
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return null;
    trimmed = trimmed[1 .. trimmed.len - 1];
    var list = std.array_list.Managed([]const u8).init(allocator);
    errdefer list.deinit();
    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |item| {
        const part = stripQuotes(std.mem.trim(u8, item, " \t"));
        if (part.len == 0) continue;
        list.append(allocator.dupe(u8, part) catch continue) catch {};
    }
    return list.toOwnedSlice() catch null;
}

fn stripQuotes(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn parseFloat(value: []const u8) !f64 {
    return std.fmt.parseFloat(f64, value) catch return error.InvalidValue;
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidValue;
}

fn boolLiteral(value: bool) []const u8 {
    return if (value) "true" else "false";
}

test "config setValue updates fields" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cfg = try Config.load(allocator);
    defer cfg.deinit();

    try cfg.setValue("general.data_dir", "/tmp/zing");
    try cfg.setValue("scoring.half_life", "42");
    try cfg.setValue("tui.show_preview", "false");

    try std.testing.expect(std.mem.eql(u8, cfg.general.data_dir, "/tmp/zing"));
    try std.testing.expectEqual(@as(f64, 42.0), cfg.scoring.half_life);
    try std.testing.expectEqual(false, cfg.tui.show_preview);
}

test "config parse string array" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const patterns = parseStringArray(allocator, "[\"a\", \"b\"]") orelse return error.TestExpectedEqual;
    defer allocator.free(patterns);
    for (patterns) |p| allocator.free(p);

    try std.testing.expectEqual(@as(usize, 2), patterns.len);
    try std.testing.expect(std.mem.eql(u8, patterns[0], "a"));
    try std.testing.expect(std.mem.eql(u8, patterns[1], "b"));
}
