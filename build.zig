const std = @import("std");
const Tag = std.Target.Os.Tag;
const builtin = @import("builtin");

const ez = @import("example_zig");

const NAME = "zinit";
const EXAMPLES = "examples";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var deps: std.ArrayList(std.Build.Module.Import) = .empty;
    defer deps.deinit(b.allocator);

    const translate_wayland_cursor = b.addTranslateC(.{
        .root_source_file = b.path("src/cursor.h"),
        .target = target,
        .optimize = optimize,
    });

    const translate_xkbcommon = b.addTranslateC(.{
        .root_source_file = b.path("src/keyboard.h"),
        .target = target,
        .optimize = optimize,
    });

    const module = b.addModule(NAME, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const uuid = b.dependency("uuid", .{});

    try deps.append(b.allocator, .{ .name = NAME, .module = module });
    try deps.append(b.allocator, .{ .name = "uuid", .module = uuid.module("uuid") });

    var assets_dir = b.addInstallDirectory(.{
        .source_dir = b.path("examples/assets"),
        .install_dir = .bin,
        .install_subdir = "assets",
    });

    module.addImport("uuid", uuid.module("uuid"));
    switch (builtin.target.os.tag) {
        .windows => {
            if (b.lazyDependency("windows", .{ .target = target, .optimize = optimize })) |windows| {
                const windows_mod = windows.module("windows");
                // Note: To build exe so a console window doesn't appear
                // Add this to any exe build: `exe.subsystem = .Windows;`
                module.addImport("windows", windows_mod);
                try deps.append(b.allocator, .{ .name = "windows", .module = windows_mod });
            }
        },
        .linux => {
            const Scanner = @import("wayland").Scanner;

            module.linkSystemLibrary("wayland-client", .{});
            module.linkSystemLibrary("wayland-cursor", .{});
            module.linkSystemLibrary("xkbcommon", .{});
            module.linkSystemLibrary("dbus-1", .{});

            module.addIncludePath(.{ .cwd_relative = "/usr/include/dbus-1.0" });
            module.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/dbus-1.0/include" });

            const scanner = Scanner.create(b, .{});
            const wayland = b.createModule(.{ .root_source_file = scanner.result });

            // Stable
            scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
            scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");

            // Staging
            scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");

            // Unstable
            scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");

            scanner.generate("wl_compositor", 1);
            scanner.generate("wl_shm", 1);
            scanner.generate("wl_output", 1);
            scanner.generate("xdg_wm_base", 1);
            scanner.generate("zxdg_decoration_manager_v1", 1);
            scanner.generate("wp_cursor_shape_manager_v1", 1);

            scanner.generate("wl_seat", 1);

            module.addImport("wayland", wayland);
            try deps.append(b.allocator, .{ .name = "wayland", .module = wayland });

            const xkbcommon = translate_xkbcommon.createModule();
            const wayland_cursor = translate_wayland_cursor.createModule();

            module.addImport("xkbcommon", xkbcommon);
            module.addImport("wayland_cursor", wayland_cursor);

            try deps.append(b.allocator, .{ .name = "xkbcommon", .module = xkbcommon });
            try deps.append(b.allocator, .{ .name = "wayland_cursor", .module = wayland_cursor });
        },
        else => {},
    }

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_unit_tests = b.addTest(.{ .root_module = test_module });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    inline for (.{
        .{ .name = "helloworld", .path = EXAMPLES ++ "/helloworld.zig" },
        .{ .name = "raw_input", .path = EXAMPLES ++ "/raw_input.zig" },
        .{ .name = "dev", .path = EXAMPLES ++ "/dev.zig" },
    }) |example| {
        try ez.addExample(b, .{ 
            .name = example.name,
            .path = example.path,
            .target = target,
            .optimize = optimize,
            .imports = deps.items,
            .lib_c = builtin.target.os.tag == .linux,
            .libraries = &.{
                .{ .name = "wayland-client", .platform = .linux, .mode = .static },
            },
            .assets_dir = &assets_dir.step
        });
    }
}
