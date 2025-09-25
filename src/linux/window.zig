const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;

const Options = @import("../window.zig").Options;
const Context = @import("context.zig");
const Buffer = @import("buffer.zig");
const EventLoop = @import("../event.zig").EventLoop;
const Event = @import("../event.zig").Event;
const EventQueue = @import("../event.zig").EventQueue;

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

arena: std.heap.ArenaAllocator,
event_loop: *EventLoop,

configured: bool = false,
dirty: bool = false,

state: WindowState = .{},

color: u32 = 0xFF000000,
width: i32 = 0,
height: i32 = 0,

server_side_decorations: bool = false,

surface: *wl.Surface,
buffer: *Buffer,
desktop: Xdg,

pub fn init(allocator: std.mem.Allocator, event_loop: *EventLoop, options: Options) !*@This() {
    const self = try allocator.create(@This());
    errdefer allocator.destroy(self);

    self.arena = std.heap.ArenaAllocator.init(allocator);
    errdefer self.arena.deinit();

    self.event_loop = event_loop;
    self.color = switch (options.theme) {
        .dark, .system => 0xFF000000,
        .light => 0xFFFFFFFF,
    };
    self.width = @intCast(options.width orelse 640);
    self.height = @intCast(options.height orelse 480);

    self.desktop = .{};

    self.buffer = try Buffer.create(self.arena.allocator(), &event_loop.context, self.width, self.height);
    errdefer self.buffer.destroy();

    self.buffer.repaint(self.color);

    // Create Surface
    self.surface = try event_loop.context.compositor.createSurface();
    errdefer self.surface.destroy();

    // Create toplevel shell surface. Handles adding titlebar with buttons
    self.desktop.surface = try event_loop.context.base.getXdgSurface(self.surface);
    errdefer self.desktop.surface.destroy();
    self.desktop.top_level = try self.desktop.surface.getToplevel();
    errdefer self.desktop.top_level.destroy();

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

    self.buffer.present(self.surface);

    return self;
}

pub fn deinit(self: *@This()) void {
    self.surface.destroy();
    self.buffer.destroy();
    self.desktop.deinit();

    const parent = self.arena.child_allocator;
    self.arena.deinit();
    parent.destroy(self);
}

pub fn id(self: *const @This()) usize {
    return @intFromPtr(self.surface);
}

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

            if (self.configured and self.dirty) {
                self.event_loop.queue.append(.{
                    @intFromPtr(self.surface),
                    .{
                        .resize = .{
                            .width = @intCast(self.width),
                            .height = @intCast(self.height),
                        },
                    },
                }) catch {};
                if (Buffer.create(self.arena.allocator(), &self.event_loop.context, self.width, self.height)) |new_buf| {
                    new_buf.repaint(self.color);
                    new_buf.present(self.surface);
                    self.buffer.destroy();
                    self.buffer = new_buf;
                    self.dirty = false;
                } else |_| {}
            } else {
                self.configured = true;
            }
        },
    }
}

pub fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, self: *@This()) void {
    switch (event) {
        .configure => |cfg| {
            if (cfg.width != 0) self.width = cfg.width;
            if (cfg.height != 0) self.height = cfg.height;
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
            self.dirty = true;
        },
        .close => self.event_loop.queue.append(.{
            @intFromPtr(self.surface),
            Event.close,
        }) catch {},
    }
}
