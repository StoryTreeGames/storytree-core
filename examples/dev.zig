const std = @import("std");
const common = @import("common.zig");
const TargetTag = @import("builtin").target.os.tag;

const zinit = @import("zinit");
const event = zinit.event;
const input = zinit.input;
const cursor = zinit.cursor;

const Window = zinit.window.Window;
const EventLoop = event.EventLoop;
const WindowEvent = event.WindowEvent;

const State = struct {
    allocator: std.mem.Allocator,
    cursor: zinit.cursor.Cursor = .Default,
    pos: enum { tl, tr, bl, br } = .tl,
    fullscreen: bool = false,

    playing: bool = false,
    progress: u64 = 0,

    pub fn handleEvent(self: *@This(), event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
        switch (evt) {
            .close => event_loop.closeWindow(window.id()),
            .key => |key_event| {
                std.debug.print("{any}\n", .{key_event.key});
                if (key_event.matches(.f11, .{})) {
                    if (self.fullscreen) window.restore() else try window.fullscreen();
                    self.fullscreen = !self.fullscreen;
                }

                if (key_event.matches('b', .{})) {
                    std.debug.print("[SPACE]: {any}\n", .{input.getKeyDown(' ')});
                    std.debug.print("[LEFT CLICK]: {any}\n", .{zinit.cursor.getMouseButton(.left)});
                }

                if (key_event.matches(.tab, .{ .shift = false })) {
                    self.cursor = .{ .symbol = @enumFromInt(@as(u8, (@intFromEnum(self.cursor.symbol)) +| 1) % 33) };

                    const title = try std.fmt.allocPrint(self.allocator, "Cursor ({s})", .{@tagName(self.cursor.symbol)});
                    defer self.allocator.free(title);
                    try window.setTitle(title);

                    try window.setCursor(self.cursor);
                }

                if (key_event.matches(.tab, .{ .shift = true })) {
                    var new_cursor = @as(i8, @bitCast(@as(u8, (@intFromEnum(self.cursor.symbol))))) - 1;
                    if (new_cursor < 0) {
                        new_cursor = @as(i8, @bitCast(@as(u8, (@intFromEnum(zinit.cursor.Symbol.zoom_in))))) + new_cursor + 1;
                    }
                    self.cursor = .{ .symbol = @enumFromInt(new_cursor) };

                    const title = try std.fmt.allocPrint(self.allocator, "Cursor ({s})", .{@tagName(self.cursor.symbol)});
                    defer self.allocator.free(title);
                    try window.setTitle(title);
                    try window.setCursor(self.cursor);
                }

                if (key_event.matches(.right, .{})) {
                    self.progress = @min(100, self.progress +| 10);

                    const client = window.getClientRect();
                    switch (self.pos) {
                        .tl, .tr => {
                            window.setCursorPos(client.width -| 1, 0);
                            self.pos = .tr;
                        },
                        .bl, .br => {
                            window.setCursorPos(client.width -| 1, client.height -| 1);
                            self.pos = .br;
                        },
                    }
                }

                if (key_event.matches(.left, .{})) {
                    self.progress -|= 10;
                    const client = window.getClientRect();
                    switch (self.pos) {
                        .tl, .tr => {
                            window.setCursorPos(0, 0);
                            self.pos = .tl;
                        },
                        .bl, .br => {
                            window.setCursorPos(0, client.height -| 1);
                            self.pos = .bl;
                        },
                    }
                }

                if (key_event.matches(.up, .{})) {
                    const client = window.getClientRect();
                    switch (self.pos) {
                        .br, .tr => {
                            window.setCursorPos(client.width -| 1, 0);
                            self.pos = .tr;
                        },
                        .bl, .tl => {
                            window.setCursorPos(0, 0);
                            self.pos = .tl;
                        },
                    }
                }

                if (key_event.matches(.down, .{})) {
                    const client = window.getClientRect();
                    switch (self.pos) {
                        .br, .tr => {
                            window.setCursorPos(client.width -| 1, client.height -| 1);
                            self.pos = .br;
                        },
                        .bl, .tl => {
                            window.setCursorPos(0, client.height -| 1);
                            self.pos = .bl;
                        },
                    }
                }
            },
            else => {},
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const event_loop = try EventLoop.init(io, gpa);
    defer event_loop.deinit();

    try event_loop.setAppId("zinit.dev.example");

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

    var state: State = .{ .allocator = gpa };

    const title = try std.fmt.allocPrint(gpa, "Cursor ({s})", .{@tagName(state.cursor.symbol)});
    defer gpa.free(title);
    _ = try event_loop.createWindow(.{
        .title = title,
        .width = 800,
        .height = 600,
        .icon = .custom("assets\\icon.ico"),
    });

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            std.debug.print("{any}\n", .{e});
            if (e == .window) {
                try state.handleEvent(event_loop, e.window.target, e.window.event);
            }
        }
    }
}
