const std = @import("std");

pub fn renderSparkline(allocator: std.mem.Allocator, values: []const f64) ![]u8 {
    if (values.len == 0) return allocator.alloc(u8, 0);
    var min_val = values[0];
    var max_val = values[0];
    for (values) |v| {
        min_val = @min(min_val, v);
        max_val = @max(max_val, v);
    }
    const range = max_val - min_val;
    const bars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    for (values) |v| {
        const norm = if (range == 0.0) 1.0 else (v - min_val) / range;
        const idx = @min(@as(usize, @intFromFloat(norm * 7.0)), 7);
        try out.appendSlice(bars[idx]);
    }
    return out.toOwnedSlice();
}
