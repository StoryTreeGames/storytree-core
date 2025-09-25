const std = @import("std");
const Rect = @import("root.zig").Rect;

const Icon = @import("icon.zig").Icon;
const Cursor = @import("cursor.zig").Cursor;
const EventLoop = @import("event.zig").EventLoop;
const MenuItem = @import("menu.zig").Item;
const DropTarget = @import("drag_drop.zig").DropTarget;

pub const Impl = switch (@import("builtin").os.tag) {
    .windows => @import("windows/window.zig"),
    else => @compileError("platform not supported"),
};

pub const Theme = enum {
    light,
    dark,
    system,

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

pub const Options = struct {
    title: []const u8 = "",
    x: ?u32 = null,
    y: ?u32 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    icon: Icon = .Default,
    cursor: Cursor = .Default,
    resizable: bool = true,
    theme: Theme = .system,
    show: Visibility = .restore,
};

pub const Window = switch (@import("builtin").target.os.tag) {
    .windows => @import("windows/window.zig"),
    .linux => @import("linux/window.zig"),
    else => @compileError("unsupported platform"),
};

pub fn id(self: *const @This()) usize {
    return self.impl.id();
}

/// Returns the pointers to the parent and
/// the target
///
/// # Parent
/// - Windows: HINSTANCE
/// - Linux: Display
///
/// # Target
/// - Windows: HWND
/// - Linux: Surface
pub fn handles(self: *const @This()) Handles {
    return self.impl.handles();
}

pub fn visibility(self: *const @This()) Visibility {
    return self.impl.visibility();
}

/// Show the window
pub fn show(self: *const @This()) void {
    self.impl.show();
}

/// Hide the window
pub fn hide(self: *const @This()) void {
    self.impl.hide();
}

/// Minimize the window
pub fn minimize(self: *const @This()) void {
    self.impl.minimize();
}

/// Maximize the window
pub fn maximize(self: *const @This()) void {
    self.impl.maximize();
}

/// Restore the window to its default windowed state
pub fn restore(self: *const @This()) void {
    self.impl.restore();
}

/// Get the windows configured theme
pub fn getTheme(self: *@This()) Theme {
    return self.impl.getTheme();
}

/// Get the windows current theme
pub fn getCurrentTheme(self: *@This()) Theme {
    return self.impl.getCurrentTheme();
}

/// Set or Unset the current window to be full screen.
///
/// + **true**: It will take up the entire screen of the current monitor where
///   the window is located if it is fullscreen.
/// + **false**: The window's styles, size, and position are restored and if
///   the window was maximized before fullscreen, it will go back to being
///   maximized.
pub fn setFullScreen(self: *@This(), state: bool) void {
    try self.impl.setFullScreen(state);
}

/// Set window title
pub fn setTitle(self: *@This(), title: []const u8) !void {
    try self.impl.setTitle(self.arena.allocator(), title);
}

/// Set window icon
pub fn setIcon(self: *@This(), new_icon: Icon) !void {
    try self.impl.setIcon(self.arena.allocator(), new_icon);
}

/// Set window cursor
pub fn setCursor(self: *@This(), new_cursor: Cursor) !void {
    try self.impl.setCursor(self.arena.allocator(), new_cursor);
}

/// Set the cursors position relative to the window
pub fn setCursorPos(self: *@This(), x: u32, y: u32) void {
    self.impl.setCursorPos(@intCast(x), @intCast(y));
}

/// Get whether the mouse is captured by the current window
pub fn getCapture(self: *@This()) bool {
    self.impl.getCapture();
}

/// Get the current bounds of the window
pub fn getWindowRect(self: *@This()) Rect(u32) {
    return self.impl.getWindowRect();
}

/// Get the current area that is used for rendering
pub fn getClientRect(self: *@This()) Rect(u32) {
    return self.impl.getClientRect();
}

/// Set the mouse to be captured by the window, or release it from the window
pub fn setCapture(self: *@This(), state: bool) void {
    self.impl.setCapture(state);
}

/// Set or replace the window's menu bar
pub fn setMenu(self: *@This(), menu: ?[]const MenuItem) !void {
    try self.impl.setMenu(self.arena.allocator(), menu);
}

/// Set or replace the window's system tray icon and menu
pub fn setSystemTray(
    self: *@This(),
    tip: []const u8,
    onclick: ?*const fn (ev: *EventLoop, window: *@This()) void,
    menu: ?[]const MenuItem,
) !void {
    try self.impl.setSystemTray(self.arena.allocator(), tip, onclick, menu);
}

/// Set the window's configured theme
pub fn setTheme(self: *@This(), theme: Theme) void {
    self.impl.setTheme(theme);
}

pub fn setDragDrop(self: *@This(), context: DropTarget.Context) !void {
    try self.impl.setDragDrop(self.arena.allocator(), context);
}
