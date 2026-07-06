const std = @import("std");
const Rect = @import("root.zig").Rect;

const Icon = @import("icon.zig").Icon;
const Cursor = @import("cursor.zig").Cursor;
const EventLoop = @import("event.zig").EventLoop;

pub const Impl = switch (@import("builtin").os.tag) {
    .windows => @import("windows/window.zig"),
    else => @compileError("platform not supported"),
};

pub const Theme = enum {
    light,
    dark,

    pub fn isLight(self: *const @This()) bool {
        return self.* == .light;
    }

    pub fn isDark(self: *const @This()) bool {
        return self.* == .dark;
    }
};

/// Collection of usefull handles that are usually needed
/// for rendering libraries like WGPU, Vulkan, Metal, etc.
pub const Handles = struct {
    /// - Windows: HINSTANCE
    /// - Linux: Display
    parent: *anyopaque,
    /// - Windows: HWND
    /// - Linux: Surface
    target: *anyopaque,
};

pub const Visibility = enum { maximize, minimize, restore, fullscreen, hidden };

pub const Transparency = enum {
    /// Windows: acrylic
    /// MacOS: Vibrancy
    blur,
    /// Windows: Mica
    /// MacOS: Vibrancy
    vibrant
};

pub const Options = struct {
    title: []const u8 = "",
    width: ?u32 = null,
    height: ?u32 = null,
    show: Visibility = .restore,

    cursor: Cursor = .Default,

    // Linux does not have reactive theme, this will be added at a later date with DBus support.
    theme: ?Theme = null,

    // Currently only supported on windows. All other platforms are NOOP
    transparency: ?Transparency = null,

    /// Has no affect on linux.
    ///
    /// Linux implementation will be done at a later date.
    icon: Icon = .Default,

    // Has no affect on linux
    x: ?u32 = null,
    y: ?u32 = null,
    resizable: bool = true,
};

pub const Window = switch (@import("builtin").target.os.tag) {
    .windows => @import("windows/window.zig"),
    .linux => @import("linux/wayland/window.zig"),
    else => @compileError("unsupported platform"),
};
