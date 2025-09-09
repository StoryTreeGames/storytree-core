const std = @import("std");
const Tag = std.Target.Os.Tag;
const builtin = @import("builtin");

const NAME = "storytree-core";
const EXAMPLES = "examples";

const examples = [_]Example{
    .{ .name = "dev", .path = EXAMPLES ++ "/dev.zig" },
    .{ .name = "wgpu", .path = EXAMPLES ++ "/wgpu/main.zig" },
    .{ .name = "dialog", .path = EXAMPLES ++ "/dialog.zig" },
    .{ .name = "window_menu", .path = EXAMPLES ++ "/menu.zig" },
    .{ .name = "linux", .path = EXAMPLES ++ "/linux.zig" },
    .{ .name = "notification", .path = EXAMPLES ++ "/notification.zig" },
    .{ .name = "drag_drop", .path = EXAMPLES ++ "/drag_drop.zig" },
    .{ .name = "system_tray", .path = EXAMPLES ++ "/system_tray.zig" },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule(NAME, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });


    var deps: @import("std").ArrayList(ModuleMap) = .empty;
    defer deps.deinit(b.allocator);

    const uuid = b.dependency("uuid", .{});
    const wgpu_native = b.dependency("wgpu_native_zig", .{});

    try deps.append(b.allocator, .{ NAME, module });
    try deps.append(b.allocator, .{ "uuid", uuid.module("uuid") });
    try deps.append(b.allocator, .{ "wgpu", wgpu_native.module("wgpu") });

    module.addImport("uuid", uuid.module("uuid"));
    switch (builtin.target.os.tag) {
        .windows => {
            const windows_zig = b.lazyDependency("windows", .{});

            // Note: To build exe so a console window doesn't appear
            // Add this to any exe build: `exe.subsystem = .Windows;`
            module.addImport("windows", windows_zig.?.module("windows"));
            try deps.append(b.allocator, .{ "windows", windows_zig.?.module("windows") });
        },
        .linux => {
            const Scanner = @import("wayland").Scanner;

            module.linkSystemLibrary("wayland-client", .{});

            const scanner = Scanner.create(b, .{});
            const wayland = b.createModule(.{ .root_source_file = scanner.result });

            scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
            scanner.generate("wl_compositor", 1);
            scanner.generate("wl_shm", 1);
            scanner.generate("xdg_wm_base", 1);

            module.addImport("wayland", wayland);
            try deps.append(b.allocator, .{ "wayland", wayland });
        },
        else => {}
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
        );
    }
}

const ModuleMap = std.meta.Tuple(&[_]type{ []const u8, ?*std.Build.Module });
const Example = struct {
    name: []const u8,
    path: []const u8,
};

pub fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime example: Example,
    modules: []const ModuleMap,
    link_lib_c: bool,
    system_libraries: []const std.meta.Tuple(&.{ []const u8, Tag }),
) void {
    const exe_module = b.createModule(.{
        .root_source_file = b.path(example.path),
        .target = target,
        .optimize = optimize,
    });

    for (modules) |module| {
        if (module[1]) |mod| {
            exe_module.addImport(module[0], mod);
        }
    }

    const exe = b.addExecutable(.{ .name = example.name, .root_module = exe_module });

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

    const estep = b.step("example-" ++ example.name, "Run example-" ++ example.name);
    estep.dependOn(&ecmd.step);
}
