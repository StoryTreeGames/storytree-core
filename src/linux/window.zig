const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;

const Options = @import("../window.zig").Options;
const Handles = @import("../window.zig").Handles;
const Visibility = @import("../window.zig").Visibility;
const Context = @import("context.zig");
const EventLoop = @import("../event.zig").EventLoop;
const Event = @import("../event.zig").Event;
const EventQueue = @import("../event.zig").EventQueue;

const Rect = @import("../root.zig").Rect;

const WindowState = packed struct(u4) {
    maximized: bool = false,
    fullscreen: bool = false,
    resizing: bool = false,
    activated: bool = false,
};

const Deco = struct {
    server: *bool,
    fn listener(_: *zxdg.ToplevelDecorationV1, event: zxdg.ToplevelDecorationV1.Event, server: *bool) void {
        switch (event) {
            .configure => |cfg| {
                server.* = cfg.mode == .server_side;
            },
        }
    }
};

title: ?[*:0]u8 = null,
width: i32 = 0,
height: i32 = 0,

state: WindowState = .{},

configured: bool = false,
dirty: ?struct { width: i32, height: i32 } = null,
shown: bool = false,
server_side_decorations: bool = false,

arena: std.heap.ArenaAllocator,
event_loop: *EventLoop,

surface: *wl.Surface = undefined,
desktop: Xdg = .{},

pub fn init(allocator: std.mem.Allocator, event_loop: *EventLoop, options: Options) !*@This() {
    const self = try allocator.create(@This());
    errdefer allocator.destroy(self);

    self.* = .{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .event_loop = event_loop,
    };
    errdefer self.arena.deinit();

    self.event_loop = event_loop;
    self.width = @intCast(options.width orelse 640);
    self.height = @intCast(options.height orelse 480);

    self.desktop = .{};

    // Create Surface
    self.surface = try event_loop.context.compositor.createSurface();
    errdefer self.surface.destroy();

    // Create toplevel shell surface. Handles adding titlebar with buttons
    self.desktop.surface = try event_loop.context.base.getXdgSurface(self.surface);
    errdefer self.desktop.surface.destroy();
    self.desktop.top_level = try self.desktop.surface.getToplevel();
    errdefer self.desktop.top_level.destroy();

    if (options.title.len > 0) {
        self.title = try self.arena.allocator().allocSentinel(u8, options.title.len, 0);
        @memcpy(self.title.?, options.title);
        self.desktop.top_level.setTitle(self.title.?);
    }

    errdefer if (self.desktop.deco) |o| o.destroy();

    if (event_loop.context.deco_mng) |dm| {
        self.desktop.deco = try dm.getToplevelDecoration(self.desktop.top_level);
        self.desktop.deco.?.setListener(*bool, Deco.listener, &self.server_side_decorations);
        self.desktop.deco.?.setMode(.server_side);
    }

    self.desktop.surface.setListener(*@This(), xdgSurfaceListener, self);
    self.desktop.top_level.setListener(*@This(), xdgToplevelListener, self);

    self.surface.commit();
    if (event_loop.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    return self;
}

pub fn deinit(self: *@This()) void {
    self.surface.destroy();
    self.desktop.deinit();

    const parent = self.arena.child_allocator;
    self.arena.deinit();
    parent.destroy(self);
}

pub fn id(self: *const @This()) usize {
    return @intFromPtr(self.surface);
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
    return .{
        .parent = @ptrCast(self.event_loop.display),
        .target = @ptrCast(self.surface),
    };
}

/// Can set the icon with pixels for different sizes
///
/// Or can set it with a `.desktop` file with the `[Desktop Entry]` section
/// and the `Icon=com.example.MyApp` entry. This will tell the compositor to
/// look for an icon at `/usr/share/icons/<size>/apps/com.example.MyApp.png`.
/// This is how most apps choose to set the icon.
///
/// Newer wayland protocals allow for per window icons with name lookups or
/// with buffers of pixels. This library uses buffers of pixels and loads in the
/// image to try to make the API platform agnostic.
pub fn setIcon(self: *@This()) void {
    _ = self;
    // Currently not implemented and is just a noop for compatibility with other
    // platforms. The user should opt to use `.desktop` files instead where possible

    // In the future this function may implement the xdg_toplevel_icon_manager_v1
    // protocal to set custom icons for every window.
}

/// Set window title
pub fn setTitle(self: *@This(), title: []const u8) !void {
    const allocator = self.arena.allocator();

    if (self.title) |t| allocator.free(t);

    self.title = try allocator.allocSentinel(u8, title.len, 0);
    @memcpy(self.title.?, title);

    self.desktop.top_level.setTitle(self.title.?);
}

/// Show the window if hidden
pub fn show(self: *@This()) void {
    _ = self;
}

/// Hide the window if shown
pub fn hide(self: *@This()) void {
    _ = self;
}

/// Minimize the window
pub fn minimize(self: *const @This()) void {
    self.desktop.top_level.setMinimized();
}

/// Maximize the window
pub fn maximize(self: *const @This()) void {
    self.desktop.top_level.setMaximized();
}

/// Restore the window to its default windowed state
pub fn restore(self: *const @This()) void {
    if (self.state.maximized) self.desktop.top_level.unsetMaximized();
    if (self.state.fullscreen) self.desktop.top_level.unsetFullscreen();
}

/// Set the current window to be full screen.
pub fn fullscreen(self: *@This()) void {
    self.desktop.top_level.setFullscreen(null);
}

pub fn visibility(self: *const @This()) Visibility {
    if (self.state.fullscreen) return .fullscreen;
    if (self.state.maximized) return .maximize;
    if (!self.shown) return .hidden;
    return .restore;
}

/// Get the current area that is used for rendering
pub fn getClientRect(self: *@This()) Rect(u32) {
    return .{
        .x = 0,
        .y = 0,
        .width = @intCast(self.width),
        .height = @intCast(self.height),
    };
}

// /// Get the windows configured theme
// pub fn getTheme(self: *@This()) Theme {
//     return self.impl.getTheme();
// }

// /// Get the windows current theme
// pub fn getCurrentTheme(self: *@This()) Theme {
//     return self.impl.getCurrentTheme();
// }

// /// Set window cursor
// pub fn setCursor(self: *@This(), new_cursor: Cursor) !void {
//     try self.impl.setCursor(self.arena.allocator(), new_cursor);
// }

// /// Set the cursors position relative to the window
// pub fn setCursorPos(self: *@This(), x: u32, y: u32) void {
//     self.impl.setCursorPos(@intCast(x), @intCast(y));
// }

// /// Get whether the mouse is captured by the current window
// pub fn getCapture(self: *@This()) bool {
//     self.impl.getCapture();
// }

// /// Set the mouse to be captured by the window, or release it from the window
// pub fn setCapture(self: *@This(), state: bool) void {
//     self.impl.setCapture(state);
// }

// /// Set or replace the window's menu bar
// pub fn setMenu(self: *@This(), menu: ?[]const MenuItem) !void {
//     try self.impl.setMenu(self.arena.allocator(), menu);
// }

// /// Set or replace the window's system tray icon and menu
// pub fn setSystemTray(
//     self: *@This(),
//     tip: []const u8,
//     onclick: ?*const fn (ev: *EventLoop, window: *@This()) void,
//     menu: ?[]const MenuItem,
// ) !void {
//     try self.impl.setSystemTray(self.arena.allocator(), tip, onclick, menu);
// }

// /// Set the window's configured theme
// pub fn setTheme(self: *@This(), theme: Theme) void {
//     self.impl.setTheme(theme);
// }

// pub fn setDragDrop(self: *@This(), context: DropTarget.Context) !void {
//     try self.impl.setDragDrop(self.arena.allocator(), context);
// }

const Xdg = struct {
    surface: *xdg.Surface = undefined,
    top_level: *xdg.Toplevel = undefined,
    deco: ?*zxdg.ToplevelDecorationV1 = null,

    pub fn deinit(self: *@This()) void {
        self.surface.destroy();
        self.top_level.destroy();
        if (self.deco) |o| o.destroy();
    }
};

pub fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, self: *@This()) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);

            // How to get window???
            self.surface.commit();

            if (self.configured) {
                if (self.dirty) |dirty| {
                    const w = if (dirty.width > 0) dirty.width else self.width;
                    const h = if (dirty.height > 0) dirty.height else self.height;
                    self.event_loop.queue.append(.{
                        @intFromPtr(self.surface),
                        .{
                            .resize = .{
                                .width = @intCast(w),
                                .height = @intCast(h),
                            },
                        },
                    }) catch {};

                    self.width = w;
                    self.height = h;
                    self.dirty = null;
                }
            } else {
                self.configured = true;
                self.event_loop.queue.append(.{
                    @intFromPtr(self.surface),
                    .{
                        .resize = .{
                            .width = @intCast(self.width),
                            .height = @intCast(self.height),
                        },
                    },
                }) catch {};
            }
        },
    }
}

pub fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, self: *@This()) void {
    switch (event) {
        .configure => |cfg| {
            if (cfg.width != 0 or cfg.height != 0) {
                self.dirty = .{
                    .width = if (cfg.width == 0) self.width else cfg.width,
                    .height = if (cfg.height == 0) self.height else cfg.height,
                };
            }

            self.state = .{};
            for (cfg.states.slice(xdg.Toplevel.State)) |state| {
                switch (state) {
                    .fullscreen => self.state.fullscreen = true,
                    .maximized => self.state.maximized = true,
                    .activated => self.state.activated = true,
                    .resizing => self.state.resizing = true,
                    else => {},
                }
            }
        },
        .close => self.event_loop.queue.append(.{
            @intFromPtr(self.surface),
            Event.close,
        }) catch {},
    }
}
