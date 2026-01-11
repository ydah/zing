pub const ListItem = struct {
    path: []const u8,
    score: f64,
    match_positions: []usize,
};

pub const ListView = struct {
    items: []ListItem,
    selected: usize = 0,
    scroll_offset: usize = 0,
    height: usize = 0,

    pub fn render(self: *ListView) void {
        _ = self;
    }

    pub fn moveUp(self: *ListView) void {
        _ = self;
    }

    pub fn moveDown(self: *ListView) void {
        _ = self;
    }

    pub fn pageUp(self: *ListView) void {
        _ = self;
    }

    pub fn pageDown(self: *ListView) void {
        _ = self;
    }

    pub fn home(self: *ListView) void {
        _ = self;
    }

    pub fn end(self: *ListView) void {
        _ = self;
    }
};
