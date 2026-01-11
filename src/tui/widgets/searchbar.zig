const std = @import("std");

pub const SearchBar = struct {
    query: std.ArrayList(u8),
    cursor_pos: usize = 0,
    prompt: []const u8 = "Search: ",

    pub fn init(allocator: std.mem.Allocator) SearchBar {
        return .{ .query = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *SearchBar) void {
        self.query.deinit();
    }

    pub fn insertChar(self: *SearchBar, c: u8) void {
        _ = self;
        _ = c;
    }

    pub fn deleteChar(self: *SearchBar) void {
        _ = self;
    }

    pub fn deleteWord(self: *SearchBar) void {
        _ = self;
    }

    pub fn clear(self: *SearchBar) void {
        _ = self;
    }

    pub fn moveCursorLeft(self: *SearchBar) void {
        _ = self;
    }

    pub fn moveCursorRight(self: *SearchBar) void {
        _ = self;
    }

    pub fn moveCursorWordLeft(self: *SearchBar) void {
        _ = self;
    }

    pub fn moveCursorWordRight(self: *SearchBar) void {
        _ = self;
    }

    pub fn render(self: *SearchBar) void {
        _ = self;
    }

    pub fn getQuery(self: *SearchBar) []const u8 {
        return self.query.items;
    }
};
