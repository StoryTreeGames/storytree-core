const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;

const Window = @import("window.zig");
const WindowOptions = @import("../../window.zig").Options;
const EventQueue = @import("../../event.zig").EventQueue;
const Event = @import("../../event.zig").Event;
const Context = @import("context.zig");

arena: std.heap.ArenaAllocator,

is_exit: bool,
windows: std.AutoArrayHashMapUnmanaged(usize, *Window),
queue: EventQueue,

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

pub fn closeAll(self: *@This()) void {
    if (self.windows.values()) |win| {
        win.deinit();
    }
    self.windows.clearAndFree(self.arena.allocator());
}

pub fn closeWindow(self: *@This(), id: usize) void {
    if (self.windows.get(id)) |win| {
        win.deinit();
        _ = self.windows.swapRemove(id);
    }
}

pub fn enableRawMouseInput(self: *@This(), window_id: usize, capture_unfocused: bool) !void {
    _ = self;
    _ = window_id;
    _ = capture_unfocused;
    @panic("TODO: Unimplemented");
}

pub fn disableRawMouseInput(self: *@This()) void {
    _ = self;
    @panic("TODO: Unimplemented");
}

pub fn exit(self: *@This()) void {
    self.is_exit = true;
}

pub fn isActive(self: *const @This()) bool {
    return !self.is_exit and self.windows.count() > 0;
}

pub fn wait(self: *@This()) !void {
    while (!self.display.prepareRead()) {
        if (self.display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
    }

    var watch: i16 = std.posix.POLL.IN;
    if (self.display.flush() != .SUCCESS) {
        watch |= std.posix.POLL.OUT;
    }

    // NOTE: make into ArrayList where [0] is display fd and [1] is uevent hotplug for adding and removing devices.
    //  All other indexes are the connected devices
    var pollfd = [_]std.posix.pollfd{.{ .fd = self.display.getFd(), .events = watch, .revents = 0 }};

    const n = try std.posix.poll(&pollfd, -1);
    if (n <= 0) {
        self.display.cancelRead();
        return;
    }

    if ((pollfd[0].revents & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) {
        if (self.display.readEvents() != .SUCCESS) return error.DisplayReadEvents;
        if (self.display.flush() != .SUCCESS) return error.DisplayFlush;
        if (self.display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
    } else {
        self.display.cancelRead();
    }
}

pub fn poll(self: *@This()) !void {
    while (!self.display.prepareRead()) {
        if (self.display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
    }

    var watch: i16 = std.posix.POLL.IN;
    if (self.display.flush() != .SUCCESS) {
        watch |= std.posix.POLL.OUT;
    }

    // NOTE: make into ArrayList where [0] is display fd and [1] is uevent hotplug for adding and removing devices.
    //  All other indexes are the connected devices
    var pollfd = [_]std.posix.pollfd{.{ .fd = self.display.getFd(), .events = watch, .revents = 0 }};

    // NOTE: use -1 to block until event
    const n = try std.posix.poll(&pollfd, 0);
    if (n <= 0) {
        self.display.cancelRead();
        return;
    }

    if ((pollfd[0].revents & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR)) != 0) {
        if (self.display.readEvents() != .SUCCESS) return error.DisplayReadEvents;
        if (self.display.flush() != .SUCCESS) return error.DisplayFlush;
        if (self.display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
    } else {
        self.display.cancelRead();
    }
}

pub fn push(self: *@This(), id: u32, comptime payload: anytype) !void {
    try self.queue.append(.{ .user = .{
        .id = id,
        .payload = switch (@typeInfo(@TypeOf(payload))) {
            .@"enum" => @intFromEnum(payload),
            .comptime_int => payload,
            .int => |i| switch (i.signedness) {
                .signed => @bitCast(@as(i32, @intCast(payload))),
                .unsigned => @intCast(payload)
            },
            else => @compileError("unsupported payload type"),
        }
    }});
}

pub fn clear(self: *@This()) void {
    self.queue.clear();
}

pub fn pop(self: *@This()) ?Event {
    switch (self.queue.pop() orelse return null) {
        .theme => |theme| return .{ .theme = theme },
        .destroy => |key| if (self.windows.fetchSwapRemove(key)) |window| {
            window.value.deinit();
        },
        .user => |u| return .{ .user = u },
        .window => |we| if (self.windows.get(we.target)) |window| {
            return .{
                .window = .{
                    .target = window,
                    .event = we.event,
                },
            };
        },
    }
    return null;
}
