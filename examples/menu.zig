const std = @import("std");

const core = @import("storytree-core");
const event = core.event;

const notif = core.notification;

const Window = @import("storytree-core").Window;
const EventLoop = event.EventLoop;
const Event = event.Event;
const id = core.menu.id;

pub const App = struct {
    allocator: std.mem.Allocator,
    watch: bool = false,

    pub fn handleEvent(self: *@This(), event_loop: *EventLoop, win: *Window, evt: Event) !void {
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
                    _ = try core.dialog.open(arena.allocator(), .{ .filters = &.{
                        .{ "Herb Guide (*.hgd)", "*.hgd" },
                        .{ "All types (*.*)", "*.*" },
                    }, .title = "Open Herb Guide" });
                },
                id("file::save-as") => {
                    _ = try core.dialog.save(arena.allocator(), .{
                        .file_name = "guide.hgd",
                        .filters = &.{
                            .{ "Herb Guide (*.hgd)", "*.hgd" },
                            .{ "All types (*.*)", "*.*" },
                        },
                        .title = "Save Herb",
                    });
                },
                else => {},
            },
            .theme => |theme| switch(theme) {
                .light => std.debug.print("Now using light theme\n", .{}),
                .dark => std.debug.print("Now using dark theme\n", .{}),
            },
            else => {},
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = try notif.Notification.send(allocator, null, "storytree-core-example-notif", .{
        .title = "Test Notification",
        .body = "Test notification from storytree core",
    });

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
        const data = event_loop.next();
        try app.handleEvent(&event_loop, data.window, data.event);
    }
}
