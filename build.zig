const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libvaxis_dep = b.dependency("libvaxis", .{});
    const sqlite_dep = b.dependency("sqlite-zig", .{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vaxis", .module = libvaxis_dep.module("vaxis") },
            .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zing",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    const all_module = b.addModule("zing_all", .{
        .root_source_file = b.path("src/all.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vaxis", .module = libvaxis_dep.module("vaxis") },
            .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
        },
    });
    const all_tests = b.addTest(.{ .root_module = all_module });
    const run_all_tests = b.addRunArtifact(all_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_all_tests.step);
}
