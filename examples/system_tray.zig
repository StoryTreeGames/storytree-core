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

const Window = core.window.Window;
const EventLoop = event.EventLoop;
const WindowEvent = event.WindowEvent;

pub fn handleEvent(event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
    switch (evt) {
        .close => event_loop.closeWindow(window.id()),
        .system_tray => |e| {
            switch (e.item.id) {
                id("quit") => event_loop.closeWindow(window.id()),
                id("toggle-window") => {
                    switch (window.visibility()) {
                        .restore, .fullscreen, .maximize => window.hide(),
                        else => window.restore(),
                    }
                },
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

    const path = try std.fs.cwd().realpathAlloc(allocator, "examples/assets/images/icon.ico");
    defer allocator.free(path);

    const window = try event_loop.createWindow(.{
        .icon = .{ .custom = path },
        // System tray requires a window. However we can hide it so that only the
        // system tray icon is visible.
        .show = .hidden
    });

    try window.setSystemTray("Some Tip", systrayOnClick, &.{
        .action("toggle-window", "Toggle Window"),
        .separator,
        .action("quit", "Quit"),
    });

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            if (e == .window) {
                try handleEvent(event_loop, e.window.target, e.window.event);
            }
        }
    }
}
