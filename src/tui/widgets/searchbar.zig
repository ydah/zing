const std = @import("std");

pub const SearchBar = struct {
    query: std.ArrayList(u8),
    cursor_pos: usize = 0,
    prompt: []const u8 = "🔍 Search: ",

    pub fn init(allocator: std.mem.Allocator) SearchBar {
        return .{ .query = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *SearchBar) void {
        self.query.deinit();
    }

    pub fn insertChar(self: *SearchBar, c: u8) void {
        _ = self.query.insert(self.cursor_pos, c) catch return;
        self.cursor_pos += 1;
    }

    pub fn deleteChar(self: *SearchBar) void {
        if (self.cursor_pos == 0) return;
        const start = prevCodepointStart(self.query.items, self.cursor_pos);
        self.query.replaceRange(start, self.cursor_pos - start, &.{}) catch return;
        self.cursor_pos = start;
    }

    pub fn deleteWord(self: *SearchBar) void {
        if (self.cursor_pos == 0) return;
        var start = prevCodepointStart(self.query.items, self.cursor_pos);
        while (start > 0 and isSeparator(self.query.items[start - 1])) {
            start = prevCodepointStart(self.query.items, start);
        }
        while (start > 0 and !isSeparator(self.query.items[start - 1])) {
            start = prevCodepointStart(self.query.items, start);
        }
        self.query.replaceRange(start, self.cursor_pos - start, &.{}) catch return;
        self.cursor_pos = start;
    }

    pub fn clear(self: *SearchBar) void {
        self.query.clearRetainingCapacity();
        self.cursor_pos = 0;
    }

    pub fn moveCursorLeft(self: *SearchBar) void {
        if (self.cursor_pos == 0) return;
        self.cursor_pos = prevCodepointStart(self.query.items, self.cursor_pos);
    }

    pub fn moveCursorRight(self: *SearchBar) void {
        if (self.cursor_pos >= self.query.items.len) return;
        self.cursor_pos = nextCodepointStart(self.query.items, self.cursor_pos);
    }

    pub fn moveCursorWordLeft(self: *SearchBar) void {
        if (self.cursor_pos == 0) return;
        var pos = prevCodepointStart(self.query.items, self.cursor_pos);
        while (pos > 0 and isSeparator(self.query.items[pos])) {
            pos = prevCodepointStart(self.query.items, pos);
        }
        while (pos > 0 and !isSeparator(self.query.items[pos])) {
            pos = prevCodepointStart(self.query.items, pos);
        }
        self.cursor_pos = pos;
    }

    pub fn moveCursorWordRight(self: *SearchBar) void {
        if (self.cursor_pos >= self.query.items.len) return;
        var pos = self.cursor_pos;
        while (pos < self.query.items.len and !isSeparator(self.query.items[pos])) {
            pos = nextCodepointStart(self.query.items, pos);
        }
        while (pos < self.query.items.len and isSeparator(self.query.items[pos])) {
            pos = nextCodepointStart(self.query.items, pos);
        }
        self.cursor_pos = pos;
    }

    pub fn render(self: *SearchBar) void {
        _ = self;
    }

    pub fn getQuery(self: *SearchBar) []const u8 {
        return self.query.items;
    }
};

fn isSeparator(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '/' or byte == '_' or byte == '-' or byte == '.';
}

fn prevCodepointStart(bytes: []const u8, index: usize) usize {
    if (index == 0) return 0;
    var i = index - 1;
    while (i > 0 and isContinuation(bytes[i])) {
        i -= 1;
    }
    return i;
}

fn nextCodepointStart(bytes: []const u8, index: usize) usize {
    if (index >= bytes.len) return bytes.len;
    const seq_len = std.unicode.utf8ByteSequenceLength(bytes[index]) catch 1;
    return @min(bytes.len, index + seq_len);
}

fn isContinuation(byte: u8) bool {
    return (byte & 0b1100_0000) == 0b1000_0000;
}
