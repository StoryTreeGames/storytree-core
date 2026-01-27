const std = @import("std");
const common = @import("common.zig");
const TargetTag = @import("builtin").target.os.tag;

const core = @import("storytree-core");
const event = core.event;
const input = core.input;

const Window = core.window.Window;
const EventLoop = event.EventLoop;
const WindowEvent = event.WindowEvent;

const State = struct {
    pub fn handleEvent(event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
        switch (evt) {
            .close => event_loop.closeWindow(window.id()),
            .raw_input => |raw| {
                std.debug.print("raw input: dx={{{d}}} dy={{{d}}}\n", .{ raw.x, raw.y });
            },
            else => {},
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    try event_loop.setAppId("com.storytree.core");

    // Custom debug output of window
    std.debug.print(
        \\When minimized taskbar status turns red (error):
        \\  - When opened, a modal pops up with a funny message
        \\
    , .{});

    const win = try event_loop.createWindow(.{
        .title = "Please Don't Minimize Me :'(",
        .width = 800,
        .height = 600,
    });
    try event_loop.enableRawMouseInput(win.id(), false);
    defer event_loop.disableRawMouseInput();

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            if (e == .window) {
                try State.handleEvent(event_loop, e.window.target, e.window.event);
            }
        }
    }
}
