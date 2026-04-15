const std = @import("std");
const Tag = std.Target.Os.Tag;
const builtin = @import("builtin");

const NAME = "zinit";
const EXAMPLES = "examples";

const examples = [_]Example{
    .{ .name = "helloworld", .path = EXAMPLES ++ "/helloworld.zig" },
    .{ .name = "raw_input", .path = EXAMPLES ++ "/raw_input.zig" },
    .{ .name = "dev", .path = EXAMPLES ++ "/dev.zig" },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule(NAME, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    var deps: std.ArrayList(std.Build.Module.Import) = .empty;
    defer deps.deinit(b.allocator);

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
            const windows_zig = b.dependency("windows", .{});

            // Note: To build exe so a console window doesn't appear
            // Add this to any exe build: `exe.subsystem = .Windows;`
            module.addImport("windows", windows_zig.module("windows"));
            try deps.append(b.allocator, .{ .name = "windows", .module = windows_zig.module("windows") });
        },
        .linux => {
            const Scanner = @import("wayland").Scanner;

            module.linkSystemLibrary("wayland-client", .{});
            module.linkSystemLibrary("wayland-cursor", .{});
            // TODO: Remove this in favor of https://codeberg.org/ifreund/zig-xkbcommon when
            //        is updated to zig v0.15.1
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

    inline for (examples) |example| {
        addExample(
            b,
            target,
            optimize,
            example,
            deps.items,
            builtin.target.os.tag == .linux,
            &.{
                .{ "wayland-client", .linux },
            },
            &assets_dir.step,
        );
    }
}

const Example = struct {
    name: []const u8,
    path: []const u8,
};

pub fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime example: Example,
    imports: []const std.Build.Module.Import,
    link_lib_c: bool,
    system_libraries: []const std.meta.Tuple(&.{ []const u8, Tag }),
    assets_dir: *std.Build.Step,
) void {
    const exe = b.addExecutable(.{ .name = example.name, .root_module = b.createModule(.{
        .root_source_file = b.path(example.path),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    }) });

    exe.addWin32ResourceFile(.{ .file = b.path("app.rc") });

    exe.step.dependOn(assets_dir);

    b.installArtifact(exe);

    if (link_lib_c) exe.linkLibC();
    for (system_libraries) |library| {
        if (library[1] == builtin.target.os.tag) {
            exe.linkSystemLibrary(library[0]);
        }
    }

    const ecmd = b.addRunArtifact(exe);
    ecmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        ecmd.addArgs(args);
    }

    const estep = b.step("run-" ++ example.name, "Run example " ++ example.name);
    estep.dependOn(&ecmd.step);
}
