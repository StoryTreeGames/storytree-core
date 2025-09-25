const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;

const Buffer = @import("buffer.zig");
const Window = @import("window.zig");
const WindowOptions = @import("../window.zig").Options;
const EventQueue = @import("../event.zig").EventQueue;
const Context = @import("context.zig");
const WindowEvent = @import("../event.zig").WindowEvent;

arena: std.heap.ArenaAllocator,

queue: EventQueue,
windows: std.AutoArrayHashMapUnmanaged(usize, *Window),

display: *wl.Display,
registry: *wl.Registry,
context: Context,

pub fn init(allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    errdefer allocator.destroy(self);

    self.arena = std.heap.ArenaAllocator.init(allocator);
    self.queue = .{ .allocator = self.arena.allocator() };
    self.windows = .empty;

    self.display = try wl.Display.connect(null);
    errdefer self.display.disconnect();

    self.registry = try self.display.getRegistry();
    errdefer self.registry.destroy();

    self.context = try Context.init(self);

    return self;
}

pub fn deinit(self: *@This()) void {
    const parent = self.arena.child_allocator;
    const allocator = self.arena.allocator();
    for (self.windows.values()) |window| {
        window.deinit();
    }
    self.windows.deinit(allocator);
    self.queue.deinit();

    self.context.deinit();
    self.registry.destroy();
    self.display.disconnect();

    self.arena.deinit();
    parent.destroy(self);
}

pub fn setAppId(self: *const @This(), app_id: []const u8) !void {
    for (self.windows.values()) |window| {
        const buff = try self.arena.allocator().allocSentinel(u8, app_id.len, 0);
        @memcpy(buff, app_id);
        buff[app_id.len] = 0;
        window.impl.xdg.top_level.setAppId(buff.ptr);
    }
}

pub fn createWindow(self: *@This(), opts: WindowOptions) !*Window {
    const allocator = self.arena.allocator();

    const win = try Window.init(allocator, self, opts);
    try self.windows.put(allocator, win.id(), win);

    return win;
}

pub fn closeWindow(self: *@This(), id: usize) void {
    if (self.windows.get(id)) |win| {
        win.deinit();
        _ = self.windows.swapRemove(id);
    }
}

pub fn isActive(self: *const @This()) bool {
    return self.windows.count() > 0;
}

pub fn wait(self: *@This()) !void {
    if (self.display.dispatch() != .SUCCESS) return error.DisplayDispatch;
}

pub fn poll(self: *@This()) !void {
    while (!self.display.prepareRead()) {
        if (self.display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
    }

    var watch: i16 = std.posix.POLL.IN;
    if (self.display.flush() != .SUCCESS) {
        watch |= std.posix.POLL.OUT;
    }

    var pollfd = [_]std.posix.pollfd{.{ .fd = self.display.getFd(), .events = watch, .revents = 0 }};
    if (try std.posix.poll(&pollfd, 0) > 0) {
        if ((pollfd[0].revents & std.posix.POLL.IN) != 0) {
            if (self.display.readEvents() != .SUCCESS) return error.DisplayReadEvents;
            if (self.display.flush() != .SUCCESS) return error.DisplayFlush;
            if (self.display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
        }
    } else {
        self.display.cancelRead();
    }
}

pub fn pop(self: *@This()) ?WindowEvent {
    while (self.queue.pop()) |data| {
        if (self.windows.get(data[0])) |win| {
            return .{ .window = win, .event = data[1] };
        }
    }
    return null;
}
