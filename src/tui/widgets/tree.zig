const std = @import("std");

pub const TreeEntry = struct {
    path: []const u8,
    score: f64,
};

pub const TreeNode = struct {
    path: []const u8,
    name: []const u8,
    score: f64,
    children: [](*TreeNode),
    parent: ?*TreeNode,
    depth: usize,
};

pub const TreeView = struct {
    allocator: std.mem.Allocator,
    root: ?*TreeNode = null,
    selected: ?*TreeNode = null,
    expanded: std.AutoHashMap(*TreeNode, void),

    pub fn init(allocator: std.mem.Allocator) TreeView {
        return .{
            .allocator = allocator,
            .expanded = std.AutoHashMap(*TreeNode, void).init(allocator),
        };
    }

    pub fn deinit(self: *TreeView) void {
        if (self.root) |root| {
            freeNode(self.allocator, root);
        }
        self.expanded.deinit();
    }

    pub fn buildTree(self: *TreeView, entries: []const TreeEntry) !void {
        if (self.root) |root| {
            freeNode(self.allocator, root);
        }
        self.expanded.clearRetainingCapacity();

        const root = try self.allocator.create(TreeNode);
        root.* = .{
            .path = try self.allocator.dupe(u8, ""),
            .name = try self.allocator.dupe(u8, ""),
            .score = 0.0,
            .children = &.{},
            .parent = null,
            .depth = 0,
        };

        for (entries) |entry| {
            var current: *TreeNode = root;
            var it = std.mem.splitScalar(u8, entry.path, '/');
            while (it.next()) |part| {
                if (part.len == 0) continue;
                var child_ptr = findChild(current, part);
                if (child_ptr == null) {
                    const child_path = try joinPath(self.allocator, current.path, part);
                    const child_node = try self.allocator.create(TreeNode);
                    child_node.* = .{
                        .path = child_path,
                        .name = try self.allocator.dupe(u8, part),
                        .score = 0.0,
                        .children = &.{},
                        .parent = current,
                        .depth = current.depth + 1,
                    };
                    try appendChild(self.allocator, current, child_node);
                    child_ptr = child_node;
                }
                current = child_ptr.?;
            }
            current.score += entry.score;
        }

        propagateScores(root);
        self.root = root;
        self.selected = root;
        try self.expanded.put(self.selected.?, {});
    }

    pub fn render(self: *TreeView) void {
        _ = self;
    }

    pub fn expand(self: *TreeView) void {
        if (self.selected) |node| {
            _ = self.expanded.put(node, {}) catch {};
        }
    }

    pub fn collapse(self: *TreeView) void {
        if (self.selected) |node| {
            _ = self.expanded.remove(node);
        }
    }

    pub fn toggle(self: *TreeView) void {
        if (self.selected) |node| {
            if (self.expanded.contains(node)) {
                _ = self.expanded.remove(node);
            } else {
                _ = self.expanded.put(node, {}) catch {};
            }
        }
    }

    pub fn moveUp(self: *TreeView) void {
        const visible = self.visibleNodes() catch return;
        defer self.allocator.free(visible);
        const selected = self.selected orelse return;
        const idx = indexOf(visible, selected) orelse return;
        if (idx == 0) return;
        self.selected = visible[idx - 1];
    }

    pub fn moveDown(self: *TreeView) void {
        const visible = self.visibleNodes() catch return;
        defer self.allocator.free(visible);
        const selected = self.selected orelse return;
        const idx = indexOf(visible, selected) orelse return;
        if (idx + 1 >= visible.len) return;
        self.selected = visible[idx + 1];
    }

    pub fn moveParent(self: *TreeView) void {
        if (self.selected) |node| {
            if (node.parent) |parent| self.selected = parent;
        }
    }

    pub fn moveFirstChild(self: *TreeView) void {
        if (self.selected) |node| {
            if (node.children.len > 0) self.selected = &node.children[0];
        }
    }

    pub fn visibleList(self: *TreeView) ![](*TreeNode) {
        return self.visibleNodes();
    }

    fn visibleNodes(self: *TreeView) ![](*TreeNode) {
        var nodes = std.array_list.Managed(*TreeNode).init(self.allocator);
        defer nodes.deinit();
        if (self.root) |root| {
            collectVisible(&nodes, self.expanded, root);
        }
        if (nodes.items.len == 0) {
            return try self.allocator.alloc(*TreeNode, 0);
        }
        return try nodes.toOwnedSlice();
    }
};

fn collectVisible(list: *std.array_list.Managed(*TreeNode), expanded: std.AutoHashMap(*TreeNode, void), node: *TreeNode) void {
    _ = list.append(node) catch return;
    if (!expanded.contains(node)) return;
    for (node.children) |child| {
        collectVisible(list, expanded, child);
    }
}

fn indexOf(nodes: [](*TreeNode), target: *TreeNode) ?usize {
    for (nodes, 0..) |node, idx| {
        if (node == target) return idx;
    }
    return null;
}

fn appendChild(allocator: std.mem.Allocator, parent: *TreeNode, child: *TreeNode) !void {
    var list = std.array_list.Managed(*TreeNode).init(allocator);
    defer list.deinit();
    try list.appendSlice(parent.children);
    try list.append(child);
    if (parent.children.len > 0) {
        allocator.free(parent.children);
    }
    parent.children = try list.toOwnedSlice();
}

fn findChild(parent: *TreeNode, name: []const u8) ?*TreeNode {
    for (parent.children) |child| {
        if (std.mem.eql(u8, child.name, name)) return child;
    }
    return null;
}

fn joinPath(allocator: std.mem.Allocator, base: []const u8, part: []const u8) ![]u8 {
    if (base.len == 0) return allocator.dupe(u8, part);
    return std.fs.path.join(allocator, &.{ base, part });
}

fn propagateScores(node: *TreeNode) void {
    for (node.children) |child| {
        propagateScores(child);
        node.score += child.score;
    }
}

fn freeNode(allocator: std.mem.Allocator, node: *TreeNode) void {
    for (node.children) |child| {
        freeNode(allocator, child);
    }
    allocator.free(node.path);
    allocator.free(node.name);
    if (node.children.len > 0) {
        allocator.free(node.children);
    }
    allocator.destroy(node);
}
