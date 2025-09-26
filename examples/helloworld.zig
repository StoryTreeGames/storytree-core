const std = @import("std");

const core = @import("storytree-core");
const event = core.event;

const Window = core.window.Window;
const EventLoop = event.EventLoop;
const Event = event.Event;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    var state = State.init(allocator);
    defer state.deinit();

    // Custom debug output of window
    const window = try event_loop.createWindow(.{
        .title = "Hello, world",
        .width = 800,
        .height = 600,
        .icon = .{ .custom = "examples\\assets\\icon.ico" },
    });
    window.show();

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |evt| {
            try state.handleEvent(event_loop, evt.window, evt.event);
        }
    }
}

const State = struct {
    allocator: std.mem.Allocator,

    platform: @import("mixins.zig").Platform = .{},

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        self.platform.deinit();
    }

    pub fn handleEvent(self: *@This(), event_loop: *EventLoop, window: *Window, evt: Event) !void {
        switch (evt) {
            .close => event_loop.closeWindow(window.id()),
            .resize => |resize| {
                try self.platform.resize(self.allocator, event_loop, window, resize);
            },
            .key_input => |key_event| {
                if (key_event.matches('q', .{})) {
                    event_loop.closeWindow(window.id());
                }
            },
            else => {},
        }
    }
};
