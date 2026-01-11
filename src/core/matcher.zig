const std = @import("std");

pub const MatchResult = struct {
    score: i32,
    positions: []usize,
};

pub fn fuzzyMatch(
    allocator: std.mem.Allocator,
    query: []const u8,
    target: []const u8,
) !?MatchResult {
    if (query.len == 0) {
        return MatchResult{ .score = 0, .positions = &.{} };
    }
    if (target.len == 0) return null;

    const smart_case = hasUpper(query);
    const query_cmp = if (smart_case) query else try toLowerAlloc(allocator, query);
    defer if (!smart_case) allocator.free(query_cmp);

    const target_cmp = if (smart_case) target else try toLowerAlloc(allocator, target);
    defer if (!smart_case) allocator.free(target_cmp);

    var positions = std.ArrayList(usize).init(allocator);
    defer positions.deinit();

    var score: i32 = 0;
    var query_idx: usize = 0;
    var prev_match_idx: ?usize = null;

    for (target_cmp, 0..) |ch, target_idx| {
        if (query_idx >= query_cmp.len) break;

        if (ch == query_cmp[query_idx]) {
            try positions.append(target_idx);
            score += 16;

            if (prev_match_idx) |prev| {
                if (target_idx == prev + 1) {
                    score += 8;
                }
            }

            if (target_idx == 0 or isBoundary(target[target_idx - 1]) or std.ascii.isUpper(target[target_idx])) {
                score += 12;
            }

            if (target_idx == 0 or target[target_idx - 1] == '/') {
                score += 16;
            }

            prev_match_idx = target_idx;
            query_idx += 1;
        } else if (prev_match_idx != null) {
            score -= 3;
        }
    }

    if (query_idx < query_cmp.len) return null;

    return MatchResult{
        .score = score,
        .positions = try positions.toOwnedSlice(),
    };
}

pub fn isBoundary(c: u8) bool {
    return c == '/' or c == '_' or c == '-' or c == '.' or std.ascii.isUpper(c);
}

pub fn toLowerAlloc(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var buf = try allocator.alloc(u8, str.len);
    for (str, 0..) |ch, idx| {
        buf[idx] = std.ascii.toLower(ch);
    }
    return buf;
}

fn hasUpper(str: []const u8) bool {
    for (str) |ch| {
        if (std.ascii.isUpper(ch)) return true;
    }
    return false;
}

test "fuzzy match basic" {
    const result = try fuzzyMatch(std.testing.allocator, "pro", "~/projects/webapp");
    try std.testing.expect(result != null);
    const match = result.?;
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 4 }, match.positions);
}

test "fuzzy match boundary bonus" {
    const result = try fuzzyMatch(std.testing.allocator, "w", "foo_web");
    try std.testing.expect(result != null);
    const match = result.?;
    try std.testing.expectEqual(@as(i32, 28), match.score);
    try std.testing.expectEqualSlices(usize, &.{4}, match.positions);
}

test "fuzzy match mismatch returns null" {
    const result = try fuzzyMatch(std.testing.allocator, "abc", "ab");
    try std.testing.expect(result == null);
}

test "fuzzy match positions are correct" {
    const result = try fuzzyMatch(std.testing.allocator, "prj", "projects");
    try std.testing.expect(result != null);
    const match = result.?;
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3 }, match.positions);
}

test "fuzzy match smart case" {
    const result = try fuzzyMatch(std.testing.allocator, "Pro", "projects");
    try std.testing.expect(result == null);
}
