const std = @import("std");

pub const FrecencyConfig = struct {
    half_life_seconds: f64 = 604800.0,
    max_score: f64 = 1000.0,
    min_score: f64 = 0.01,

    pub fn lambda(self: FrecencyConfig) f64 {
        if (self.half_life_seconds <= 0.0) return 0.0;
        return std.math.ln(2.0) / self.half_life_seconds;
    }
};

pub const FrecencyEntry = struct {
    path: []const u8,
    score: f64,
    last_access: i64,

    pub fn updateScore(self: *FrecencyEntry, config: FrecencyConfig, now: i64) void {
        const decay = calcDecay(config, self.last_access, now);
        const updated = self.score * decay + 1.0;
        if (!std.math.isFinite(updated)) {
            self.score = config.max_score;
        } else {
            self.score = @min(updated, config.max_score);
        }
        self.last_access = now;
    }

    pub fn currentScore(self: FrecencyEntry, config: FrecencyConfig, now: i64) f64 {
        const decay = calcDecay(config, self.last_access, now);
        const value = self.score * decay;
        if (!std.math.isFinite(value)) return config.max_score;
        return value;
    }
};

fn calcDecay(config: FrecencyConfig, last_access: i64, now: i64) f64 {
    if (now <= last_access) return 1.0;
    const delta_t: f64 = @floatFromInt(now - last_access);
    const lambda = config.lambda();
    if (lambda <= 0.0) return 1.0;
    return std.math.exp(-lambda * delta_t);
}

test "frecency update score adds visit and clamps" {
    var entry = FrecencyEntry{
        .path = "/tmp",
        .score = 0.0,
        .last_access = 0,
    };
    const config = FrecencyConfig{ .max_score = 2.0 };
    entry.updateScore(config, 0);
    try std.testing.expectEqual(@as(f64, 1.0), entry.score);

    entry.updateScore(config, 0);
    try std.testing.expectEqual(@as(f64, 2.0), entry.score);
}

test "frecency decay halves over half-life" {
    const config = FrecencyConfig{ .half_life_seconds = 100.0 };
    var entry = FrecencyEntry{
        .path = "/tmp",
        .score = 10.0,
        .last_access = 0,
    };
    const decayed = entry.currentScore(config, 100);
    try std.testing.expect(std.math.approxEqAbs(f64, decayed, 5.0, 0.05));
}

test "frecency update uses decay" {
    const config = FrecencyConfig{ .half_life_seconds = 100.0 };
    var entry = FrecencyEntry{
        .path = "/tmp",
        .score = 10.0,
        .last_access = 0,
    };
    entry.updateScore(config, 100);
    try std.testing.expect(std.math.approxEqAbs(f64, entry.score, 6.0, 0.06));
}
