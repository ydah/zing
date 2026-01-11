const std = @import("std");
const Database = @import("../core/database.zig").Database;
const theme_mod = @import("theme.zig");
const Theme = theme_mod.Theme;

pub const Mode = enum {
    list,
    tree,
    stats,
};

pub const AppState = struct {
    mode: Mode = .list,
    query: std.ArrayList(u8),
    results: []SearchResult,
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    last_input_ns: u64 = 0,
    last_search_ns: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) AppState {
        return .{
            .query = std.ArrayList(u8).init(allocator),
            .results = &.{},
        };
    }

    pub fn deinit(self: *AppState) void {
        self.query.deinit();
    }
};

pub const SearchResult = struct {
    path: []const u8,
    score: f64,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    db: *Database,
    state: AppState,
    theme: Theme,

    pub fn init(allocator: std.mem.Allocator, db: *Database) !App {
        return .{
            .allocator = allocator,
            .db = db,
            .state = AppState.init(allocator),
            .theme = try theme_mod.loadTheme(allocator, ""),
        };
    }

    pub fn deinit(self: *App) void {
        self.freeResults();
        self.state.deinit();
    }

    pub fn run(self: *App) !void {
        _ = self;
    }

    pub fn handleKeyEvent(self: *App, key: u32) bool {
        _ = key;
        self.state.last_input_ns = std.time.nanoTimestamp();
        return false;
    }

    pub fn handleResize(self: *App, width: usize, height: usize) void {
        _ = self;
        _ = width;
        _ = height;
    }

    pub fn render(self: *App) void {
        _ = self;
    }

    pub fn renderSearchBar(self: *App) void {
        _ = self;
    }

    pub fn renderResults(self: *App) void {
        _ = self;
    }

    pub fn renderPreview(self: *App) void {
        _ = self;
    }

    pub fn renderStatusBar(self: *App) void {
        _ = self;
    }

    pub fn updateSearch(self: *App) !void {
        const now = std.time.nanoTimestamp();
        if (self.state.last_input_ns == 0) return;
        if (now - self.state.last_input_ns < 100 * std.time.ns_per_ms) return;
        if (self.state.last_search_ns != 0 and self.state.last_search_ns >= self.state.last_input_ns) return;

        const query = self.state.query.items;
        const results = try self.db.search(self.allocator, query, 100);
        self.freeResults();
        self.state.results = try toSearchResults(self.allocator, results);
        self.state.last_search_ns = now;
    }

    fn freeResults(self: *App) void {
        for (self.state.results) |result| {
            self.allocator.free(result.path);
        }
        self.allocator.free(self.state.results);
        self.state.results = &.{};
    }
};

fn toSearchResults(allocator: std.mem.Allocator, entries: []const @import("../core/database.zig").Entry) ![]SearchResult {
    var results = try allocator.alloc(SearchResult, entries.len);
    for (entries, 0..) |entry, idx| {
        results[idx] = .{
            .path = entry.path,
            .score = entry.score,
        };
    }
    allocator.free(entries);
    return results;
}
