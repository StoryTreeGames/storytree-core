const std = @import("std");
const common = @import("common.zig");
const TargetTag = @import("builtin").target.os.tag;

const zinit = @import("zinit");
const event = zinit.event;
const input = zinit.input;

const Window = zinit.window.Window;
const EventLoop = event.EventLoop;
const WindowEvent = event.WindowEvent;
const DeviceEvent = event.DeviceEvent;

const State = struct {
    pub fn handleEvent(event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
        switch (evt) {
            .close => event_loop.closeWindow(window.id()),
            // .move => {
            //     std.debug.print("MOUSE MOVE\n", .{});
            // },
            .enter => std.debug.print("Mouse Enter\n", .{}),
            .leave => std.debug.print("Mouse Leave\n", .{}),
            else => {},
        }
    }

    pub fn handleDeviceEvent(id: usize, evt: DeviceEvent) void {
        _ = id;
        switch (evt) {
            .mouse_delta => |md| {
                std.debug.print("raw mouse input: dx={{{d}}} dy={{{d}}}\n", .{ md.x, md.y });
            },
            else => {}
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const event_loop = try EventLoop.init(io, gpa);
    defer event_loop.deinit();

    try event_loop.setAppId("zinit.raw_input.example");

    _ = try event_loop.createWindow(.{
        .title = "Raw Input",
        .width = 800,
        .height = 600,
    });

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            switch (e) {
                .window => |we| {
                    try State.handleEvent(event_loop, we.target, we.event);
                },
                .device => |de| {
                    State.handleDeviceEvent(de.id, de.event);
                },
                else => {}
            }
        }
    }
}
