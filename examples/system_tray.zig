const std = @import("std");

const windows = @import("windows");
const win32 = windows.win32;

const shell = win32.ui.shell;
const windows_and_messaging = win32.ui.windows_and_messaging;

const core = @import("storytree-core");
const event = core.event;
const dialog = core.dialog;
const input = core.input;
const menu = core.menu;

const id = menu.id;

const Window = @import("storytree-core").Window;
const EventLoop = event.EventLoop;
const Event = event.Event;

pub fn handleEvent(event_loop: *EventLoop, window: *Window, evt: Event) !void {
    switch (evt) {
        .close => event_loop.closeWindow(window.id()),
        .system_tray => |e| {
            switch (e.item.id) {
                id("quit") => event_loop.closeWindow(window.id()),
                else => {}
            }
        },
        else => {},
    }
}

fn systrayOnClick(ev: *EventLoop, window: *Window) void {
    if (dialog.message(.yes_no, .{
        .title = "Quit",
        .message = "Are you sure you want to quit?",
        .owner = window.id(),
    }) == .yes) {
        ev.closeWindow(window.id());
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    const window = try event_loop.createWindow(.{ .title = "Drag & Drop", .width = 800, .height = 600, .icon = .{ .custom = "C:\\Users\\zboehm\\projects\\zig\\storytree-core\\examples\\assets\\images\\icon.ico" } });
    try window.setSystemTray("Some Tip", systrayOnClick, &.{.action("quit", "Quit")});

    while (event_loop.isActive()) {
        if (event_loop.poll()) |data| {
            try handleEvent(&event_loop, data.window, data.event);
        }
    }
}
