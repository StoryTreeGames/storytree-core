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

    // Custom debug output of window
    std.debug.print(
        \\Controls:
        \\  <tab>: Toggle forwards through cursor icons
        \\  <shift+tab>: Toggle backwards through cursor icons
        \\  <left>: Cursor to left corner
        \\  <right>: Cursor to right corner
        \\  <up>: Cursor to top corner
        \\  <down>: Cursor to bottom corner
        \\
    , .{});

    _ = try event_loop.createWindow(.{
        .title = "Hello, world",
        .width = 800,
        .height = 600,
        .icon = .{ .custom = "examples\\assets\\icon.ico" },
    });

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.queue.pop()) |evt| {
            std.debug.print("{any}\n", .{evt});
        }
    }
}
