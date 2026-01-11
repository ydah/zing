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
        if (self.selected == 0) return;
        self.selected -= 1;
        self.ensureVisible();
    }

    pub fn moveDown(self: *ListView) void {
        if (self.items.len == 0) return;
        if (self.selected + 1 >= self.items.len) return;
        self.selected += 1;
        self.ensureVisible();
    }

    pub fn pageUp(self: *ListView) void {
        if (self.height == 0) return;
        if (self.selected == 0) return;
        const delta = @min(self.selected, self.height);
        self.selected -= delta;
        self.ensureVisible();
    }

    pub fn pageDown(self: *ListView) void {
        if (self.height == 0 or self.items.len == 0) return;
        const remaining = self.items.len - 1 - self.selected;
        const delta = @min(remaining, self.height);
        self.selected += delta;
        self.ensureVisible();
    }

    pub fn home(self: *ListView) void {
        if (self.items.len == 0) return;
        self.selected = 0;
        self.ensureVisible();
    }

    pub fn end(self: *ListView) void {
        if (self.items.len == 0) return;
        self.selected = self.items.len - 1;
        self.ensureVisible();
    }

    fn ensureVisible(self: *ListView) void {
        if (self.height == 0) return;
        if (self.selected < self.scroll_offset) {
            self.scroll_offset = self.selected;
            return;
        }
        const last_visible = self.scroll_offset + self.height - 1;
        if (self.selected > last_visible) {
            self.scroll_offset = self.selected - (self.height - 1);
        }
    }
};
