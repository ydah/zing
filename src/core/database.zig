const std = @import("std");
const sqlite = @import("sqlite");
const matcher = @import("matcher.zig");

pub const Entry = struct {
    path: []const u8,
    score: f64,
    last_access: i64,
    access_count: i64,
    created_at: i64,
};

pub const Database = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    conn: sqlite.Db,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Database {
        const resolved_path = if (path.len == 0)
            try defaultDbPath(allocator)
        else
            try allocator.dupe(u8, path);
        errdefer allocator.free(resolved_path);

        try ensureDbDir(resolved_path);

        var db = try sqlite.Db.init(.{
            .mode = sqlite.Db.Mode{ .File = resolved_path },
            .open_flags = .{
                .write = true,
                .create = true,
            },
            .threading_mode = .MultiThread,
        });
        errdefer db.deinit();

        var database = Database{
            .allocator = allocator,
            .path = resolved_path,
            .conn = db,
        };
        try database.initSchema();
        return database;
    }

    pub fn deinit(self: *Database) void {
        self.conn.deinit();
        self.allocator.free(self.path);
    }

    pub fn add(self: *Database, path: []const u8) !void {
        const now = std.time.timestamp();
        const query =
            \\INSERT INTO directories (path, score, last_access, access_count, created_at)
            \\VALUES (:path, 1.0, :last_access, 1, :created_at)
            \\ON CONFLICT(path) DO UPDATE SET
            \\  score = directories.score + 1.0,
            \\  last_access = excluded.last_access,
            \\  access_count = directories.access_count + 1
        ;
        try execWithRetry(&self.conn, query, .{ .path = path, .last_access = now, .created_at = now });
    }

    pub fn remove(self: *Database, path: []const u8) !void {
        const query = "DELETE FROM directories WHERE path = :path";
        try execWithRetry(&self.conn, query, .{ .path = path });
    }

    pub fn get(self: *Database, path: []const u8) !?Entry {
        const query =
            \\SELECT path, score, last_access, access_count, created_at
            \\FROM directories
            \\WHERE path = :path
        ;
        const Row = struct {
            path: []const u8,
            score: f64,
            last_access: i64,
            access_count: i64,
            created_at: i64,
        };
        const row = try oneAllocWithRetry(&self.conn, Row, self.allocator, query, .{ .path = path });
        if (row) |r| {
            return Entry{
                .path = r.path,
                .score = r.score,
                .last_access = r.last_access,
                .access_count = r.access_count,
                .created_at = r.created_at,
            };
        }
        return null;
    }

    pub fn getAll(self: *Database, allocator: std.mem.Allocator) ![]Entry {
        const query =
            \\SELECT path, score, last_access, access_count, created_at
            \\FROM directories
            \\ORDER BY score DESC
        ;
        const Row = struct {
            path: []const u8,
            score: f64,
            last_access: i64,
            access_count: i64,
            created_at: i64,
        };
        var attempts: u8 = 0;
        while (true) : (attempts += 1) {
            var stmt = self.conn.prepare(query) catch |err| {
                if (isBusy(err) and attempts < 5) {
                    std.time.sleep(50 * std.time.ns_per_ms);
                    continue;
                }
                return err;
            };
            defer stmt.deinit();

            const rows = stmt.all(Row, allocator, .{}, .{}) catch |err| {
                if (isBusy(err) and attempts < 5) {
                    std.time.sleep(50 * std.time.ns_per_ms);
                    continue;
                }
                return err;
            };

            var entries = try allocator.alloc(Entry, rows.len);
            for (rows, 0..) |row, idx| {
                entries[idx] = Entry{
                    .path = row.path,
                    .score = row.score,
                    .last_access = row.last_access,
                    .access_count = row.access_count,
                    .created_at = row.created_at,
                };
            }
            allocator.free(rows);
            return entries;
        }
    }

    pub fn search(self: *Database, allocator: std.mem.Allocator, query: []const u8, limit: usize) ![]Entry {
        const all = try self.getAll(allocator);
        if (query.len == 0) return all;
        defer allocator.free(all);

        var matches = std.ArrayList(ScoredEntry).init(allocator);
        defer matches.deinit();

        for (all) |entry| {
            const match = try matcher.fuzzyMatch(allocator, query, entry.path);
            if (match) |m| {
                try matches.append(.{
                    .entry = entry,
                    .score = entry.score + @as(f64, @floatFromInt(m.score)),
                });
                allocator.free(m.positions);
            } else {
                allocator.free(entry.path);
            }
        }

        std.sort.insertion(ScoredEntry, matches.items, {}, scoredEntryDesc);

        const count = @min(limit, matches.items.len);
        var result = try allocator.alloc(Entry, count);
        for (matches.items[0..count], 0..) |item, idx| {
            result[idx] = item.entry;
        }
        if (matches.items.len > count) {
            for (matches.items[count..]) |item| {
                allocator.free(item.entry.path);
            }
        }
        return result;
    }

    pub fn prune(self: *Database, min_score: f64) !void {
        const query = "DELETE FROM directories WHERE score <= :min_score";
        try execWithRetry(&self.conn, query, .{ .min_score = min_score });
    }

    pub fn beginTransaction(self: *Database) !void {
        try execWithRetry(&self.conn, "BEGIN", .{});
    }

    pub fn commit(self: *Database) !void {
        try execWithRetry(&self.conn, "COMMIT", .{});
    }

    pub fn rollback(self: *Database) !void {
        try execWithRetry(&self.conn, "ROLLBACK", .{});
    }

    fn initSchema(self: *Database) !void {
        const schema =
            \\CREATE TABLE IF NOT EXISTS directories (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  path TEXT NOT NULL UNIQUE,
            \\  score REAL NOT NULL DEFAULT 1.0,
            \\  last_access INTEGER NOT NULL,
            \\  access_count INTEGER NOT NULL DEFAULT 1,
            \\  created_at INTEGER NOT NULL
            \\);
            \\CREATE INDEX IF NOT EXISTS idx_directories_path ON directories(path);
            \\CREATE INDEX IF NOT EXISTS idx_directories_score ON directories(score DESC);
        ;
        try execWithRetry(&self.conn, schema, .{});
    }
};

const ScoredEntry = struct {
    entry: Entry,
    score: f64,
};

fn scoredEntryDesc(_: void, a: ScoredEntry, b: ScoredEntry) bool {
    return a.score > b.score;
}

fn defaultDbPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "ZING_DATA_DIR")) |data_dir| {
        defer allocator.free(data_dir);
        return try std.fs.path.join(allocator, &.{ data_dir, "zing.db" });
    } else |_| {}

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &.{ home, ".local", "share", "zing", "zing.db" });
}

fn ensureDbDir(db_path: []const u8) !void {
    const dir_path = std.fs.path.dirname(db_path) orelse return;
    try std.fs.cwd().makePath(dir_path);
}

fn isBusy(err: anyerror) bool {
    return err == error.SQLiteBusy or
        err == error.SQLiteBusyTimeout or
        err == error.SQLiteBusyRecovery or
        err == error.SQLiteBusySnapshot;
}

fn execWithRetry(db: *sqlite.Db, comptime query: []const u8, values: anytype) !void {
    var attempts: u8 = 0;
    while (true) : (attempts += 1) {
        db.exec(query, .{}, values) catch |err| {
            if (isBusy(err) and attempts < 5) {
                std.time.sleep(50 * std.time.ns_per_ms);
                continue;
            }
            return err;
        };
        return;
    }
}

fn oneAllocWithRetry(
    db: *sqlite.Db,
    comptime Row: type,
    allocator: std.mem.Allocator,
    comptime query: []const u8,
    values: anytype,
) !?Row {
    var attempts: u8 = 0;
    while (true) : (attempts += 1) {
        return db.oneAlloc(Row, allocator, query, .{}, values) catch |err| {
            if (isBusy(err) and attempts < 5) {
                std.time.sleep(50 * std.time.ns_per_ms);
                continue;
            }
            return err;
        };
    }
}

test "database path uses defaults" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const path = try defaultDbPath(allocator);
    defer allocator.free(path);
    try std.testing.expect(path.len > 0);
}
