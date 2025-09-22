const std = @import("std");

const core = @import("storytree-core");
const event = core.event;
const input = core.input;

const Window = @import("storytree-core").Window;
const EventLoop = event.EventLoop;
const Event = event.Event;

const State = struct {
    allocator: std.mem.Allocator,
    cursor: core.cursor.Cursor = .Default,
    pos: enum { tl, tr, bl, br } = .tl,
    fullscreen: bool = false,

    pub fn handleEvent(self: *@This(), event_loop: *EventLoop, window: *Window, evt: Event) !void {
        switch (evt) {
            .close => {
                if (core.dialog.message(.yes_no, .{ .icon = .warning, .title = "Exit", .message = "Are you sure you want to exit the application?" }) == .yes) {
                    event_loop.closeWindow(window.id());
                }
            },
            .key_input => |key_event| {
                std.debug.print("{any}\n", .{ key_event.key });
                if (key_event.matches(.f11, .{})) {
                    window.setFullScreen(!self.fullscreen);
                    self.fullscreen = !self.fullscreen;
                }

                if (key_event.matches('b', .{})) {
                    std.debug.print("[SPACE]: {any}\n", .{input.getKeyDown(' ')});
                    std.debug.print("[LEFT CLICK]: {any}\n", .{core.cursor.getMouseButton(.left)});
                }

                if (key_event.matches(.tab, .{ .shift = false })) {
                    self.cursor = .{ .icon = @enumFromInt(@as(u8, (@intFromEnum(self.cursor.icon)) +| 1) % 33) };

                    const title = try std.fmt.allocPrint(self.allocator, "Cursor ({s})", .{@tagName(self.cursor.icon)});
                    defer self.allocator.free(title);
                    try window.setTitle(title);

                    try window.setCursor(self.cursor);
                }

                if (key_event.matches(.tab, .{ .shift = true })) {
                    var new_cursor = @as(i8, @bitCast(@as(u8, (@intFromEnum(self.cursor.icon))))) - 1;
                    if (new_cursor < 0) {
                        new_cursor = @as(i8, @bitCast(@as(u8, (@intFromEnum(core.cursor.CursorType.zoom_in))))) + new_cursor + 1;
                    }
                    self.cursor = .{ .icon = @enumFromInt(new_cursor) };

                    const title = try std.fmt.allocPrint(self.allocator, "Cursor ({s})", .{@tagName(self.cursor.icon)});
                    defer self.allocator.free(title);
                    try window.setTitle(title);
                    try window.setCursor(self.cursor);
                }

                if (key_event.matches(.right, .{})) {
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

    var state: State = .{ .allocator = allocator };

    const title = try std.fmt.allocPrint(allocator, "Cursor ({s})", .{@tagName(state.cursor.icon)});
    _ = try event_loop.createWindow(.{ .title = title, .width = 800, .height = 600, .icon = .{ .custom = "examples\\assets\\icon.ico" } });
    allocator.free(title);

    while (event_loop.isActive()) {
        const data = event_loop.next();
        try state.handleEvent(&event_loop, data.window, data.event);
    }
}
