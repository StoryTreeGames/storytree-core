const std = @import("std");
const core = @import("storytree-core");

const EventLoop = core.event.EventLoop;
const SizeEvent = core.event.SizeEvent;
const Window = core.window.Window;

// used for adding platform specific state
pub const Platform = switch (@import("builtin").target.os.tag) {
    .linux => struct {
        const Buffer = @import("buffer.zig");

        buffer: ?*Buffer = null,

        pub fn resize(self: *@This(), allocator: std.mem.Allocator, event_loop: *EventLoop, window: *Window, r: SizeEvent) !void {
            try Buffer.resize(allocator, &self.buffer, window.surface, event_loop, r);
        }

        pub fn deinit(self: *@This()) void {
            if (self.buffer) |b| b.deinit();
        }
    },
    else => struct {
        pub fn resize(_: *@This(), _: *EventLoop, _: *Window, _: SizeEvent) !void {}
        pub fn deinit(_: *@This()) void {}
    },
};
