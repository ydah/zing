const std = @import("std");
const Database = @import("../core/database.zig").Database;
const theme_mod = @import("theme.zig");
const Theme = theme_mod.Theme;
const vaxis = @import("vaxis");
const matcher = @import("../core/matcher.zig");
const SearchBar = @import("widgets/searchbar.zig").SearchBar;
const PreviewPane = @import("widgets/preview.zig").PreviewPane;
const TreeView = @import("widgets/tree.zig").TreeView;
const TreeEntry = @import("widgets/tree.zig").TreeEntry;
const TreeNode = @import("widgets/tree.zig").TreeNode;

pub const Mode = enum {
    list,
    tree,
    stats,
};

pub const AppState = struct {
    mode: Mode = .list,
    searchbar: SearchBar,
    subdir_bar: SearchBar,
    subdir_mode: bool = false,
    subdir_base: ?[]u8 = null,
    results: []SearchResult,
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    last_input_ns: u64 = 0,
    last_search_ns: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) AppState {
        return .{
            .searchbar = SearchBar.init(allocator),
            .subdir_bar = SearchBar.init(allocator),
            .results = &.{},
        };
    }

    pub fn deinit(self: *AppState) void {
        self.searchbar.deinit();
        self.subdir_bar.deinit();
    }
};

pub const SearchResult = struct {
    path: []const u8,
    score: f64,
    match_positions: []usize,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    db: *Database,
    state: AppState,
    theme: Theme,
    preview: PreviewPane,
    tree: TreeView,
    accepted: bool = false,

    pub fn init(allocator: std.mem.Allocator, db: *Database) !App {
        return .{
            .allocator = allocator,
            .db = db,
            .state = AppState.init(allocator),
            .theme = try theme_mod.loadTheme(allocator, ""),
            .preview = .{},
            .tree = TreeView.init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.freeResults();
        self.preview.deinit(self.allocator);
        self.tree.deinit();
        if (self.state.subdir_base) |base| self.allocator.free(base);
        self.state.deinit();
    }

    pub fn run(self: *App) !?[]u8 {
        var tty_buffer: [4096]u8 = undefined;
        var tty = try vaxis.Tty.init(&tty_buffer);
        defer {
            vaxis.Tty.resetSignalHandler();
            tty.deinit();
        }

        var vx = try vaxis.init(self.allocator, .{});
        defer vx.deinit(self.allocator, tty.writer());

        try vx.enterAltScreen(tty.writer());
        defer vx.exitAltScreen(tty.writer()) catch {};
        try vx.setBracketedPaste(tty.writer(), true);

        const winsize = if (@hasField(@TypeOf(tty), "fd"))
            try vaxis.Tty.getWinsize(tty.fd)
        else
            vaxis.Winsize{ .rows = 40, .cols = 100, .x_pixel = 0, .y_pixel = 0 };
        try vx.resize(self.allocator, tty.writer(), winsize);

        var loop = vaxis.Loop(vaxis.Event){
            .tty = &tty,
            .vaxis = &vx,
        };
        try loop.init();
        try loop.start();
        defer loop.stop();

        self.state.last_input_ns = std.time.nanoTimestamp() - 200 * std.time.ns_per_ms;
        try self.updateSearch();

        var running = true;
        while (running) {
            var handled_event = false;
            while (loop.tryEvent()) |event| {
                handled_event = true;
                switch (event) {
                    .key_press => |key| {
                        if (try self.handleKeyEvent(key)) {
                            running = false;
                            break;
                        }
                    },
                    .winsize => |ws| {
                        try vx.resize(self.allocator, tty.writer(), ws);
                    },
                    else => {},
                }
            }

            try self.updateSearch();
            self.renderFrame(&vx, &tty);

            if (!handled_event) {
                std.time.sleep(16 * std.time.ns_per_ms);
            }
        }
        if (self.accepted) {
            if (self.selectedPath()) |path| {
                return try self.allocator.dupe(u8, path);
            }
        }
        return null;
    }

    pub fn handleKeyEvent(self: *App, key: vaxis.Key) !bool {
        const mods = key.mods;
        if (key.matches('q', .{})) return true;
        if (key.matches(vaxis.Key.escape, .{})) return true;

        if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
            if (self.state.mode == .tree) {
                self.tree.moveUp();
            } else {
                self.moveSelectionUp();
            }
        } else if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
            if (self.state.mode == .tree) {
                self.tree.moveDown();
            } else {
                self.moveSelectionDown();
            }
        } else if (key.matches(vaxis.Key.page_up, .{})) {
            if (self.state.mode == .tree) {
                self.tree.moveUp();
            } else {
                self.pageUp();
            }
        } else if (key.matches(vaxis.Key.page_down, .{})) {
            if (self.state.mode == .tree) {
                self.tree.moveDown();
            } else {
                self.pageDown();
            }
        } else if (key.matches(vaxis.Key.left, .{})) {
            if (self.state.mode == .tree) {
                self.tree.collapse();
            } else {
                if (mods.ctrl) {
                    self.state.searchbar.moveCursorWordLeft();
                } else {
                    self.state.searchbar.moveCursorLeft();
                }
            }
        } else if (key.matches(vaxis.Key.right, .{})) {
            if (self.state.mode == .tree) {
                self.tree.expand();
            } else {
                if (mods.ctrl) {
                    self.state.searchbar.moveCursorWordRight();
                } else {
                    self.state.searchbar.moveCursorRight();
                }
            }
        } else if (key.matches(vaxis.Key.backspace, .{})) {
            if (self.state.subdir_mode) {
                if (self.state.subdir_bar.cursor_pos == 0) {
                    self.exitSubdirMode();
                } else {
                    self.state.subdir_bar.deleteChar();
                }
            } else {
                self.state.searchbar.deleteChar();
            }
        } else if (key.matches(vaxis.Key.delete, .{})) {
            if (self.state.subdir_mode) {
                self.state.subdir_bar.deleteChar();
            } else {
                self.state.searchbar.deleteChar();
            }
        } else if (key.matchShortcut('u', .{ .ctrl = true })) {
            if (self.state.subdir_mode) {
                self.state.subdir_bar.clear();
            } else {
                self.state.searchbar.clear();
            }
        } else if (key.matchShortcut('w', .{ .ctrl = true })) {
            if (self.state.subdir_mode) {
                self.state.subdir_bar.deleteWord();
            } else {
                self.state.searchbar.deleteWord();
            }
        } else if (key.matchShortcut('t', .{ .ctrl = true }) or key.matches('\t', .{})) {
            self.state.mode = switch (self.state.mode) {
                .list => .tree,
                .tree => .stats,
                .stats => .list,
            };
        } else if (key.matches(vaxis.Key.enter, .{})) {
            self.accepted = true;
            return true;
        } else if (key.text) |text| {
            if (!mods.ctrl and !mods.alt) {
                if (std.mem.eql(u8, text, "/") and !self.state.subdir_mode) {
                    try self.enterSubdirMode();
                } else if (self.state.subdir_mode) {
                    self.state.subdir_bar.insertText(text);
                } else {
                    self.state.searchbar.insertText(text);
                }
            }
        }

        self.state.last_input_ns = std.time.nanoTimestamp();
        return false;
    }

    pub fn handleResize(self: *App, width: usize, height: usize) void {
        _ = self;
        _ = width;
        _ = height;
    }

    pub fn renderFrame(self: *App, vx: *vaxis.Vaxis, tty: *vaxis.Tty) void {
        const win = vx.window();
        win.clear();
        win.hideCursor();

        if (win.height == 0 or win.width == 0) return;

        const preview_height: u16 = if (win.height > 10) 5 else 3;
        const status_height: u16 = 1;
        if (win.height <= preview_height + status_height + 1) return;
        const list_height: u16 = win.height - preview_height - status_height - 1;
        const list_start_row: u16 = 1;
        const preview_start = list_start_row + list_height;

        self.renderSearchBar(win);
        self.renderResults(win.child(.{
            .x_off = 0,
            .y_off = @intCast(list_start_row),
            .width = win.width,
            .height = list_height,
        }));
        self.renderPreview(win.child(.{
            .x_off = 0,
            .y_off = @intCast(preview_start),
            .width = win.width,
            .height = preview_height,
        }));
        self.renderStatusBar(win.child(.{
            .x_off = 0,
            .y_off = @intCast(win.height - 1),
            .width = win.width,
            .height = 1,
        }));

        vx.render(tty.writer()) catch {};
    }

    pub fn renderSearchBar(self: *App, win: vaxis.Window) void {
        const prompt = if (self.state.subdir_mode)
            "📁 Subdir: "
        else
            self.state.searchbar.prompt;
        const query = if (self.state.subdir_mode)
            self.state.subdir_bar.getQuery()
        else
            self.state.searchbar.getQuery();
        var display = query;
        if (self.state.subdir_mode and self.state.subdir_base != null) {
            const crumbs = formatBreadcrumbs(self.allocator, self.state.subdir_base.?) catch null;
            if (crumbs) |crumbs_buf| {
                defer self.allocator.free(crumbs_buf);
                display = std.fmt.allocPrint(self.allocator, "{s} {s}", .{ crumbs_buf, query }) catch display;
            }
        }
        defer if (display.ptr != query.ptr) self.allocator.free(display);
        const segments = [_]vaxis.Segment{
            .{
                .text = prompt,
                .style = styleFromTheme(self.theme.primary, null, true),
            },
            .{
                .text = display,
                .style = styleFromTheme(self.theme.text_primary, null, false),
            },
        };
        _ = win.print(&segments, .{ .row_offset = 0, .col_offset = 0 });

        const cursor_col = cursorColumn(win, prompt, display, self.state.subdir_mode, self.state);
        win.showCursor(cursor_col, 0);
    }

    pub fn renderResults(self: *App, win: vaxis.Window) void {
        if (self.state.mode == .tree) {
            self.renderTree(win);
            return;
        }
        if (self.state.mode == .stats) {
            self.renderStats(win);
            return;
        }

        const height: usize = win.height;
        if (height == 0) return;
        const total = self.state.results.len;
        if (total == 0) return;

        var start = self.state.scroll_offset;
        if (self.state.selected_index < start) start = self.state.selected_index;
        if (self.state.selected_index >= start + height) {
            start = self.state.selected_index - height + 1;
        }
        self.state.scroll_offset = start;

        const end = @min(total, start + height);
        const max_score = self.maxScore();
        var row: u16 = 0;
        var idx = start;
        while (idx < end) : (idx += 1) {
            const entry = self.state.results[idx];
            const selected = idx == self.state.selected_index;
            const bg_color: ?theme_mod.Color = if (selected) self.theme.bg_highlight else null;
            const base_style = if (selected)
                styleFromTheme(self.theme.text_primary, bg_color, true)
            else
                styleFromTheme(self.theme.text_primary, null, false);
            const match_style = if (selected)
                styleFromTheme(self.theme.match_highlight, bg_color, true)
            else
                styleFromTheme(self.theme.match_highlight, null, true);

            var segments = std.ArrayList(vaxis.Segment).init(self.allocator);
            defer segments.deinit();
            appendHighlightedSegments(self.allocator, &segments, entry.path, entry.match_positions, base_style, match_style) catch {};

            const bar = scoreBar(self.allocator, entry.score, max_score, 10) catch "";
            defer if (bar.len > 0) self.allocator.free(bar);
            segments.append(.{ .text = "  ", .style = base_style }) catch {};
            segments.append(.{ .text = bar, .style = styleFromTheme(self.theme.score_bar, bg_color, false) }) catch {};

            const score_text = std.fmt.allocPrint(self.allocator, "  {d:.2}", .{entry.score}) catch "";
            defer if (score_text.len > 0) self.allocator.free(score_text);
            if (score_text.len > 0) {
                segments.append(.{ .text = score_text, .style = base_style }) catch {};
            }

            _ = win.print(segments.items, .{ .row_offset = row, .col_offset = 0, .wrap = .none });
            row += 1;
        }
    }

    pub fn renderPreview(self: *App, win: vaxis.Window) void {
        const selected = self.selectedPath() orelse return;
        if (self.preview.path == null or !std.mem.eql(u8, self.preview.path.?, selected)) {
            self.preview.loadDirectory(self.allocator, selected) catch {};
        }

        const header = std.fmt.allocPrint(self.allocator, "📁 Preview: {s}", .{selected}) catch return;
        defer self.allocator.free(header);
        const header_seg = vaxis.Segment{
            .text = header,
            .style = styleFromTheme(self.theme.secondary, null, true),
        };
        _ = win.print(&.{header_seg}, .{ .row_offset = 0, .col_offset = 0, .wrap = .none });

        const col_width: u16 = 24;
        const columns = @max(@as(u16, 1), win.width / col_width);
        var row: u16 = 1;
        var col: u16 = 0;
        for (self.preview.entries) |entry| {
            if (row >= win.height) break;
            const name = if (entry.kind == .directory)
                std.fmt.allocPrint(self.allocator, "{s}/", .{entry.name}) catch entry.name
            else
                entry.name;
            defer if (name.ptr != entry.name.ptr) self.allocator.free(name);
            const seg = vaxis.Segment{ .text = name, .style = styleFromTheme(self.theme.text_secondary, null, false) };
            _ = win.print(&.{seg}, .{ .row_offset = row, .col_offset = col * col_width, .wrap = .none });
            col += 1;
            if (col >= columns) {
                col = 0;
                row += 1;
            }
        }
    }

    pub fn renderStatusBar(self: *App, win: vaxis.Window) void {
        const text = switch (self.state.mode) {
            .list => "↑↓ Navigate  Tab Tree  Enter Select  / Subdirs  Esc Quit",
            .tree => "↑↓ Navigate  ←→ Collapse/Expand  Tab Stats  Esc Quit",
            .stats => "Tab Switch View  q Quit",
        };
        const seg = vaxis.Segment{ .text = text, .style = styleFromTheme(self.theme.text_muted, null, false) };
        _ = win.print(&.{seg}, .{ .row_offset = 0, .col_offset = 0, .wrap = .none });
    }

    pub fn updateSearch(self: *App) !void {
        const now = std.time.nanoTimestamp();
        if (self.state.last_input_ns == 0) return;
        if (now - self.state.last_input_ns < 100 * std.time.ns_per_ms) return;
        if (self.state.last_search_ns != 0 and self.state.last_search_ns >= self.state.last_input_ns) return;

        if (self.state.subdir_mode) {
            try self.updateSubdirSearch();
        } else {
            const query = self.state.searchbar.getQuery();
            const results = try self.db.search(self.allocator, query, 100);
            self.freeResults();
            self.state.results = try toSearchResults(self.allocator, results, query);
            self.state.selected_index = 0;
            self.state.scroll_offset = 0;
            try self.updateTree();
        }
        self.state.last_search_ns = now;
    }

    fn freeResults(self: *App) void {
        for (self.state.results) |result| {
            self.allocator.free(result.path);
            self.allocator.free(result.match_positions);
        }
        self.allocator.free(self.state.results);
        self.state.results = &.{};
    }

    fn updateTree(self: *App) !void {
        var entries = try self.allocator.alloc(TreeEntry, self.state.results.len);
        defer self.allocator.free(entries);
        for (self.state.results, 0..) |result, idx| {
            entries[idx] = .{ .path = result.path, .score = result.score };
        }
        try self.tree.buildTree(entries);
    }

    fn renderTree(self: *App, win: vaxis.Window) void {
        const nodes = self.tree.visibleList();
        defer self.allocator.free(nodes);
        const max_score = treeMaxScore(nodes);
        var row: u16 = 0;
        for (nodes) |node| {
            if (row >= win.height) break;
            const indent = std.mem.repeat(self.allocator, " ", node.depth * 2) catch "";
            defer if (indent.len > 0) self.allocator.free(indent);
            const has_children = node.children.len > 0;
            const expanded = has_children and self.tree.expanded.contains(node);
            const glyph = if (!has_children) " " else if (expanded) "▾" else "▸";
            const name = if (node.name.len == 0) "/" else node.name;
            const line = std.fmt.allocPrint(
                self.allocator,
                "{s}{s} {s}",
                .{ indent, glyph, name },
            ) catch "";
            defer if (line.len > 0) self.allocator.free(line);
            const selected = self.tree.selected == node;
            const style = if (selected)
                styleFromTheme(self.theme.text_primary, self.theme.bg_highlight, true)
            else
                styleFromTheme(self.theme.text_primary, null, false);
            var segments = std.ArrayList(vaxis.Segment).init(self.allocator);
            defer segments.deinit();
            segments.append(.{ .text = line, .style = style }) catch {};

            const bar = scoreBar(self.allocator, node.score, max_score, 8) catch "";
            defer if (bar.len > 0) self.allocator.free(bar);
            segments.append(.{ .text = "  ", .style = style }) catch {};
            segments.append(.{ .text = bar, .style = styleFromTheme(self.theme.score_bar, null, false) }) catch {};

            const score_text = std.fmt.allocPrint(self.allocator, "  {d:.1}", .{node.score}) catch "";
            defer if (score_text.len > 0) self.allocator.free(score_text);
            if (score_text.len > 0) {
                segments.append(.{ .text = score_text, .style = style }) catch {};
            }

            _ = win.print(segments.items, .{ .row_offset = row, .col_offset = 0, .wrap = .none });
            row += 1;
        }
    }

    fn renderStats(self: *App, win: vaxis.Window) void {
        const entries = self.db.getAll(self.allocator) catch return;
        defer freeEntries(self.allocator, entries);

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
                const days_ago = @as(i64, @intCast((now - entry.last_access) / day_seconds));
                if (days_ago >= 0 and days_ago < 7) {
                    const idx = @as(usize, @intCast(6 - days_ago));
                    activity[idx] += 1.0;
                }
            }
        }

        const spark = @import("widgets/sparkline.zig").renderSparkline(self.allocator, &activity) catch "";
        defer if (spark.len > 0) self.allocator.free(spark);

        const lines = [_][]const u8{
            std.fmt.allocPrint(self.allocator, "Total directories: {d}", .{entries.len}) catch "",
            std.fmt.allocPrint(self.allocator, "Total visits: {d}", .{total_visits}) catch "",
            std.fmt.allocPrint(self.allocator, "Unique today: {d}", .{unique_today}) catch "",
            std.fmt.allocPrint(self.allocator, "Activity: {s}", .{spark}) catch "",
        };
        defer {
            for (lines) |line| {
                if (line.len > 0) self.allocator.free(line);
            }
        }

        var row: u16 = 0;
        for (lines) |line| {
            if (row >= win.height) break;
            const seg = vaxis.Segment{ .text = line, .style = styleFromTheme(self.theme.text_secondary, null, false) };
            _ = win.print(&.{seg}, .{ .row_offset = row, .col_offset = 0, .wrap = .none });
            row += 1;
        }
    }

    fn selectedPath(self: *App) ?[]const u8 {
        if (self.state.results.len == 0) return null;
        if (self.state.selected_index >= self.state.results.len) return null;
        return self.state.results[self.state.selected_index].path;
    }

    fn moveSelectionUp(self: *App) void {
        if (self.state.selected_index == 0) return;
        self.state.selected_index -= 1;
    }

    fn moveSelectionDown(self: *App) void {
        if (self.state.selected_index + 1 >= self.state.results.len) return;
        self.state.selected_index += 1;
    }

    fn pageUp(self: *App) void {
        const delta = @min(self.state.selected_index, 10);
        self.state.selected_index -= delta;
    }

    fn pageDown(self: *App) void {
        const remaining = self.state.results.len - 1 - self.state.selected_index;
        const delta = @min(remaining, 10);
        self.state.selected_index += delta;
    }

    fn maxScore(self: *App) f64 {
        var max_score: f64 = 1.0;
        for (self.state.results) |entry| {
            if (entry.score > max_score) max_score = entry.score;
        }
        return max_score;
    }

    fn enterSubdirMode(self: *App) !void {
        var owned_base: ?[]u8 = null;
        const selected = self.selectedPath();
        const base = if (selected) |path| path else blk: {
            owned_base = try std.process.getCwdAlloc(self.allocator);
            break :blk owned_base.?;
        };
        if (self.state.subdir_base) |prev| self.allocator.free(prev);
        self.state.subdir_base = try self.allocator.dupe(u8, base);
        if (owned_base) |buf| self.allocator.free(buf);
        self.state.subdir_bar.clear();
        self.state.subdir_mode = true;
        self.state.last_input_ns = std.time.nanoTimestamp();
        try self.updateSubdirSearch();
    }

    fn exitSubdirMode(self: *App) void {
        self.state.subdir_mode = false;
        self.state.subdir_bar.clear();
        self.state.last_search_ns = 0;
        self.state.last_input_ns = std.time.nanoTimestamp() - 200 * std.time.ns_per_ms;
    }

    fn updateSubdirSearch(self: *App) !void {
        const base = self.state.subdir_base orelse return;
        const query = self.state.subdir_bar.getQuery();
        const results = try findSubdirs(self.allocator, base, query, 100);
        self.freeResults();
        self.state.results = results;
        self.state.selected_index = 0;
        self.state.scroll_offset = 0;
    }
};

fn toSearchResults(
    allocator: std.mem.Allocator,
    entries: []const @import("../core/database.zig").Entry,
    query: []const u8,
) ![]SearchResult {
    var results = try allocator.alloc(SearchResult, entries.len);
    for (entries, 0..) |entry, idx| {
        const match = if (query.len > 0) try matcher.fuzzyMatch(allocator, query, entry.path) else null;
        const positions = if (match) |m| m.positions else try allocator.alloc(usize, 0);
        results[idx] = .{
            .path = entry.path,
            .score = entry.score,
            .match_positions = positions,
        };
    }
    allocator.free(entries);
    return results;
}

fn styleFromTheme(fg: theme_mod.Color, bg: ?theme_mod.Color, bold: bool) vaxis.Style {
    return .{
        .fg = fg.toVaxis(),
        .bg = if (bg) |color| color.toVaxis() else .default,
        .bold = bold,
    };
}

fn freeEntries(allocator: std.mem.Allocator, entries: []const @import("../core/database.zig").Entry) void {
    for (entries) |entry| {
        allocator.free(entry.path);
    }
    allocator.free(entries);
}

fn findSubdirs(
    allocator: std.mem.Allocator,
    base: []const u8,
    query: []const u8,
    limit: usize,
) ![]SearchResult {
    var dir = std.fs.cwd().openDir(base, .{ .iterate = true }) catch return allocator.alloc(SearchResult, 0);
    defer dir.close();

    var matches = std.ArrayList(ScoredResult).init(allocator);
    defer matches.deinit();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (query.len == 0) {
            const path = try std.fs.path.join(allocator, &.{ base, entry.name });
            try matches.append(.{
                .result = .{ .path = path, .score = 0.0, .match_positions = try allocator.alloc(usize, 0) },
                .score = 0.0,
            });
            continue;
        }
        const match = try matcher.fuzzyMatch(allocator, query, entry.name);
        if (match) |m| {
            const path = try std.fs.path.join(allocator, &.{ base, entry.name });
            try matches.append(.{
                .result = .{ .path = path, .score = @floatFromInt(m.score), .match_positions = m.positions },
                .score = m.score,
            });
        }
    }

    std.sort.insertion(ScoredResult, matches.items, {}, scoredResultDesc);
    const count = @min(limit, matches.items.len);
    var results = try allocator.alloc(SearchResult, count);
    for (matches.items[0..count], 0..) |item, idx| {
        results[idx] = item.result;
    }
    for (matches.items[count..]) |item| {
        allocator.free(item.result.path);
        allocator.free(item.result.match_positions);
    }
    return results;
}

const ScoredResult = struct {
    result: SearchResult,
    score: i32,
};

fn scoredResultDesc(_: void, a: ScoredResult, b: ScoredResult) bool {
    return a.score > b.score;
}

fn formatBreadcrumbs(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    if (path.len == 0) return null;
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    var it = std.mem.split(u8, path, "/");
    while (it.next()) |part| {
        if (part.len == 0) continue;
        try parts.append(part);
    }
    if (parts.items.len == 0) return allocator.dupe(u8, "/");

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.appendSlice("/");
    for (parts.items, 0..) |part, idx| {
        if (idx > 0) try out.appendSlice(" > ");
        try out.appendSlice(part);
    }
    return out.toOwnedSlice();
}

fn appendHighlightedSegments(
    allocator: std.mem.Allocator,
    segments: *std.ArrayList(vaxis.Segment),
    text: []const u8,
    positions: []const usize,
    base_style: vaxis.Style,
    match_style: vaxis.Style,
) !void {
    var pos_idx: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const is_match = pos_idx < positions.len and positions[pos_idx] == i;
        const start = i;
        if (is_match) {
            i += 1;
            pos_idx += 1;
            try segments.append(.{ .text = text[start..i], .style = match_style });
        } else {
            while (i < text.len and !(pos_idx < positions.len and positions[pos_idx] == i)) {
                i += 1;
            }
            try segments.append(.{ .text = text[start..i], .style = base_style });
        }
    }
    _ = allocator;
}

fn scoreBar(allocator: std.mem.Allocator, score: f64, max_score: f64, width: usize) ![]u8 {
    if (width == 0) return allocator.alloc(u8, 0);
    const ratio = if (max_score == 0.0) 0.0 else score / max_score;
    const filled = @min(width, @as(usize, @intFromFloat(ratio * @as(f64, @floatFromInt(width)))));
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < width) : (i += 1) {
        if (i < filled) {
            try out.appendSlice("█");
        } else {
            try out.appendSlice(" ");
        }
    }
    return out.toOwnedSlice();
}

fn treeMaxScore(nodes: [](*TreeNode)) f64 {
    var max_score: f64 = 1.0;
    for (nodes) |node| {
        if (node.score > max_score) max_score = node.score;
    }
    return max_score;
}

fn cursorColumn(win: vaxis.Window, prompt: []const u8, display: []const u8, subdir_mode: bool, state: AppState) u16 {
    const prompt_width = textWidth(win, prompt);
    if (!subdir_mode) {
        const cursor_width = textWidth(win, display[0..@min(state.searchbar.cursor_pos, display.len)]);
        return clampCursor(win, prompt_width + cursor_width);
    }

    // Subdir mode: display may include breadcrumbs + space + query.
    const query = state.subdir_bar.getQuery();
    if (display.len == query.len) {
        const cursor_width = textWidth(win, display[0..@min(state.subdir_bar.cursor_pos, display.len)]);
        return clampCursor(win, prompt_width + cursor_width);
    }

    const query_prefix_len = @min(state.subdir_bar.cursor_pos, query.len);
    const prefix_len = if (display.len >= query.len) display.len - query.len else display.len;
    const total_len = @min(display.len, prefix_len + query_prefix_len);
    const cursor_width = textWidth(win, display[0..total_len]);
    return clampCursor(win, prompt_width + cursor_width);
}

fn clampCursor(win: vaxis.Window, col: u16) u16 {
    if (win.width == 0) return 0;
    return @min(col, win.width - 1);
}

fn textWidth(win: vaxis.Window, text: []const u8) u16 {
    var width: u16 = 0;
    var iter = vaxis.unicode.graphemeIterator(text);
    while (iter.next()) |g| {
        const bytes = g.bytes(text);
        width +|= win.gwidth(bytes);
    }
    return width;
}
