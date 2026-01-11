const std = @import("std");

pub const TreeNode = struct {
    path: []const u8,
    name: []const u8,
    score: f64,
    children: []TreeNode,
    parent: ?*TreeNode,
    depth: usize,
};

pub const TreeView = struct {
    root: ?*TreeNode = null,
    selected: ?*TreeNode = null,

    pub fn buildTree(allocator: std.mem.Allocator, entries: []TreeNode) !TreeNode {
        _ = allocator;
        _ = entries;
        return TreeNode{
            .path = "",
            .name = "",
            .score = 0.0,
            .children = &.{},
            .parent = null,
            .depth = 0,
        };
    }

    pub fn render(self: *TreeView) void {
        _ = self;
    }

    pub fn expand(self: *TreeView) void {
        _ = self;
    }

    pub fn collapse(self: *TreeView) void {
        _ = self;
    }

    pub fn toggle(self: *TreeView) void {
        _ = self;
    }

    pub fn moveUp(self: *TreeView) void {
        _ = self;
    }

    pub fn moveDown(self: *TreeView) void {
        _ = self;
    }

    pub fn moveParent(self: *TreeView) void {
        _ = self;
    }

    pub fn moveFirstChild(self: *TreeView) void {
        _ = self;
    }
};
