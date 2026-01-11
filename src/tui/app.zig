const std = @import("std");
const Database = @import("../core/database.zig").Database;
const Theme = @import("theme.zig").Theme;

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
    db: *Database,
    state: AppState,
    theme: Theme,

    pub fn init(allocator: std.mem.Allocator, db: *Database) !App {
        return .{
            .db = db,
            .state = AppState.init(allocator),
            .theme = Theme.default,
        };
    }

    pub fn deinit(self: *App) void {
        self.state.deinit();
    }

    pub fn run(self: *App) !void {
        _ = self;
    }

    pub fn handleKeyEvent(self: *App, key: u32) bool {
        _ = self;
        _ = key;
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
        _ = self;
    }
};
