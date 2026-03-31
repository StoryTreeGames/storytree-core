const std = @import("std");

const dialog = @import("dialog");
const zinit = @import("zinit");
const event = zinit.event;

const notif = zinit.notification;

const Window = zinit.window.Window;
const EventLoop = event.EventLoop;
const Event = event.Event;
const WindowEvent = event.WindowEvent;
const id = zinit.menu.id;

pub const App = struct {
    allocator: std.mem.Allocator,
    watch: bool = false,

    pub fn handleEvent(self: *@This(), event_loop: *EventLoop, win: *Window, evt: WindowEvent) !void {
        // making it easier to deinitialize the memory allocated for open and save dialogs
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        switch (evt) {
            .close => event_loop.closeWindow(win.id()),
            .menu => |menu| switch (menu.item.id) {
                id("quit") => event_loop.closeWindow(win.id()),
                id("file::watch") => {
                    self.watch = !self.watch;
                    menu.toggle(self.watch);
                },
                id("file::open") => {
                    _ = dialog.open(arena.allocator(), .{ .filters = &.{
                        .{ "Herb Guide (*.hgd)", "*.hgd" },
                        .{ "All types (*.*)", "*.*" },
                    }, .title = "Open Herb Guide" }) catch {};
                },
                id("file::save-as") => {
                    _ = dialog.save(arena.allocator(), .{
                        .file_name = "guide.hgd",
                        .filters = &.{
                            .{ "Herb Guide (*.hgd)", "*.hgd" },
                            .{ "All types (*.*)", "*.*" },
                        },
                        .title = "Save Herb",
                    }) catch {};
                },
                else => {},
            },
            else => {},
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App{ .allocator = allocator };

    var event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    const win = try event_loop.createWindow(.{ .width = 800, .height = 600 });
    try win.setMenu(&.{
        .submenu("File", &.{
            .action("file::open", "Open"),
            .action("file::save", "Save"),
            .action("file::save-as", "Save As"),
            .separator,
            .toggle("file::watch", "Watch", app.watch),
        }),
        .action("quit", "Quit"),
    });

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            switch (e) {
                .window => |we| {
                    try app.handleEvent(event_loop, we.target, we.event);
                },
                .theme => |theme| switch (theme) {
                    .light => std.debug.print("Now using light theme\n", .{}),
                    .dark => std.debug.print("Now using dark theme\n", .{}),
                },
                else => {},
            }
        }
    }
}
