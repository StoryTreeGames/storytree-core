const std = @import("std");

const zinit = @import("zinit");
const event = zinit.event;

const Window = zinit.window.Window;
const EventLoop = event.EventLoop;
const Event = event.Event;
const WindowEvent = event.WindowEvent;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var event_loop = try EventLoop.init(io, gpa);
    defer event_loop.deinit();

    var state = State.init(gpa);
    defer state.deinit();

    // Custom debug output of window
    const window = try event_loop.createWindow(.{
        .title = "Hello, world",
        .width = 800,
        .height = 600,
        .icon = .custom("examples\\assets\\icon.ico"), // Doesn't work yet in linux
        .cursor = .Progress,
    });
    window.show();

    while (event_loop.isActive()) {
        try event_loop.wait();

        while (event_loop.pop()) |evt| {
            switch (evt) {
                .window => |we| {
                    try state.handleEvent(event_loop, we.target, we.event);
                },
                else => {},
            }
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

    pub fn handleEvent(self: *@This(), event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
        switch (evt) {
            .close => {
                std.debug.print("Closing Window\n", .{});
                event_loop.closeWindow(window.id());
            },
            .resize => |resize| {
                try self.platform.resize(self.allocator, event_loop, window, resize);
            },
            .key => |key_event| {
                if (key_event.matches('q', .{})) {
                    event_loop.closeWindow(window.id());
                }
            },
            else => {},
        }
    }
};
