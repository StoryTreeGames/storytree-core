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
    allocator: std.mem.Allocator,
    icons: []const []const u8,
    cursor: core.cursor.Cursor = .Default,
    pos: enum { tl, tr, bl, br } = .tl,
    fullscreen: bool = false,

    playing: bool = false,
    progress: u64 = 0,

    pub fn handleEvent(self: *@This(), event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
        switch (evt) {
            .close => {
                if (core.dialog.message(.yes_no, .{ .icon = .warning, .title = "Exit", .message = "Are you sure you want to exit the application?" }) == .yes) {
                    event_loop.closeWindow(window.id());
                }
            },
            .thumb => |thumb| {
                // The windows thumb bar buttons have IDs equal to the index they were defined
                // when calling `window.setThumbBar([]ThumbBar.Button)`
                switch (thumb) {
                    // Prev
                    0 => {
                        std.debug.print("Previous\n", .{});
                    },
                    // Play/Pause
                    1 => {
                        std.debug.print("Play/Pause\n", .{});
                        self.playing = !self.playing;
                        if (self.playing) {
                            std.debug.print("Set Icon To Pause\n", .{});
                            try window.taskbar.updateIcon(1, .{ .custom = self.icons[2] });
                            try window.taskbar.updateTooltip(1, "Pause");
                        } else {
                            std.debug.print("Set Icon To Play\n", .{});
                            try window.taskbar.updateIcon(1, .{ .custom = self.icons[1] });
                            try window.taskbar.updateTooltip(1, "Play");
                        }
                    },
                    // Next
                    2 => {
                        std.debug.print("Next\n", .{});
                    },
                    else => {},
                }
            },
            .key_input => |key_event| {
                std.debug.print("{any}\n", .{key_event.key});
                if (key_event.matches(' ', .{}) and TargetTag == .windows) {
                    try window.setJumpList(.{
                        .recent = true,
                        .frequent = true,
                        .tasks = &.{.{ .label = "Play", .args = "--play" }},
                        .categories = &.{
                            .{
                                .label = "Custom",
                                .items = &.{
                                    .{ .link = .{ .label = "Play", .args = "--play", .icon = "assets/play.ico" } },
                                },
                            },
                        },
                    });
                }
                if (key_event.matches(.f11, .{})) {
                    if (self.fullscreen) window.restore() else try window.fullscreen();
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
                    self.progress = @min(100, self.progress +| 10);
                    if (TargetTag == .windows) {
                        try window.setTaskbarProgress(
                            if (self.progress == 100) .ERROR else .NORMAL,
                            self.progress,
                            100,
                        );
                    }

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
                    if (TargetTag == .windows) {
                        try window.setTaskbarProgress(
                            if (self.progress == 0) .INDETERMINATE else .NORMAL,
                            self.progress,
                            100,
                        );
                    }
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

    const event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    try event_loop.setAppId("com.storytree.core");

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

    // const prev_icon = try common.relativeFile(allocator, "assets/skip-previous.ico");
    // const play_icon = try common.relativeFile(allocator, "assets/play.ico");
    // const pause_icon = try common.relativeFile(allocator, "assets/pause.ico");
    // const next_icon = try common.relativeFile(allocator, "assets/skip-next.ico");
    //
    // defer allocator.free(prev_icon);
    // defer allocator.free(play_icon);
    // defer allocator.free(pause_icon);
    // defer allocator.free(next_icon);

    const prev_icon = "assets/skip-previous.ico";
    const play_icon = "assets/play.ico";
    const pause_icon = "assets/pause.ico";
    const next_icon = "assets/skip-next.ico";

    var state: State = .{ .icons = &.{
        prev_icon,
        play_icon,
        pause_icon,
        next_icon,
    }, .allocator = allocator };

    const title = try std.fmt.allocPrint(allocator, "Cursor ({s})", .{@tagName(state.cursor.icon)});
    defer allocator.free(title);
    const win = try event_loop.createWindow(.{
        .title = title,
        .width = 800,
        .height = 600,
        .icon = .{ .custom = "assets\\icon.ico" },
    });

    if (TargetTag == .windows) {
        try win.setThumbBar(&.{ .{
            .icon = .{ .custom = prev_icon },
            .tooltip = "Prev",
            .dismiss_on_click = true,
        }, .{
            .icon = .{ .custom = play_icon },
            .tooltip = "Play",
            .dismiss_on_click = true,
        }, .{
            .icon = .{ .custom = next_icon },
            .tooltip = "Next",
            .dismiss_on_click = true,
        } });

        try win.setJumpList(.{
            .recent = true,
            .frequent = true,
            .tasks = &.{.{ .label = "Play", .args = "--play" }},
            .categories = &.{
                .{
                    .label = "Custom",
                    .items = &.{
                        .{ .link = .{ .label = "Play", .args = "--play", .icon = "assets/play.ico" } },
                    },
                },
            },
        });
    }

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            if (e == .window) {
                try state.handleEvent(event_loop, e.window.target, e.window.event);
            }
        }
    }
}
