const std = @import("std");

const zinit = @import("zinit");
const menu = zinit.menu;

const Window = zinit.window.Window;
const event = zinit.event;
const EventLoop = event.EventLoop;
const UserEvent = event.UserEvent;
const WindowEvent = event.WindowEvent;

const App = struct {
    context_menu: *menu.Menu,
    window_menu: *menu.Menu,

    systray: *menu.SystemTray,

    pub fn handleMenu(el: *EventLoop, w: *Window, selected: MenuEvent) void {
        switch (selected) {
            .quit => el.closeWindow(w.id()),
            .toggle_visible => switch(w.visibility()) {
                .hidden => w.show(),
                else => w.hide(),
            },
            else => {}
        }
    }

    pub fn handleEvent(self: *const @This(), event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
        switch (evt) {
            .close => {
                event_loop.closeWindow(window.id());
            },
            .mouse => |mi| {
                if (mi.button == .right) {
                    if (self.context_menu.popupAtCursor(window.id())) |e| {
                        e.select();
                        const selected: MenuEvent = @enumFromInt(e.info.id);
                        @This().handleMenu(event_loop, window, selected);
                    }
                }
            },
            .menu => |me| switch (me.kind) {
                .window => if (self.window_menu.transform(me.target)) |e| {
                    e.select();
                    @This().handleMenu(event_loop, window, e.into(MenuEvent));
                },
                else => {}
            },
            else => {},
        }
    }

    pub fn handleUserEvent(event_loop: *EventLoop, evt: UserEvent) void {
        switch (evt.id) {
            SystrayUserEvent.ID => switch (evt.into(SystrayUserEvent)) {
                .quit => event_loop.closeAll(),
                .click => std.debug.print("Systray Clicked\n", .{}),
            },
            else => {}
        }
    }
};

const SystemTrayHandler = struct  {
    allocator: std.mem.Allocator,
    event_loop: *EventLoop,
    pub fn handler(self: *@This(), systray: *const menu.SystemTray, evt: menu.SystemTrayEvent) void {
        switch (evt) {
            .click => |ce| switch (ce) {
                .left => self.event_loop.push(SystrayUserEvent.ID, SystrayUserEvent.click) catch {},
                .right => {
                    var arena = std.heap.ArenaAllocator.init(self.allocator);
                    defer arena.deinit();
                    const allocator = arena.allocator();

                    var menu_items: std.ArrayList(menu.Item) = .empty;
                    for (self.event_loop.windows.values(), 0..) |window, i| {
                        const idx = i + 1;
                        const offset = 100 * idx;
                        const label: [:0]const u8 = std.unicode.utf16LeToUtf8AllocZ(allocator, window.title[0..]) catch "Window X";

                        // Need to allocate so the stack doesn't change it's value
                        // on each iteration causing bad data to occur
                        const items = allocator.alloc(menu.Item, 3) catch continue;
                        items[0] = .action(
                            offset + @intFromEnum(MenuEvent.toggle_visible),
                            if (window.visibility() == .hidden) "Show" else "Hide"
                        );
                        items[1] = .separator;
                        items[2] = .action(offset + @intFromEnum(MenuEvent.quit), "Close");
                        menu_items.append(allocator, .submenu(label, items)) catch continue;
                    }
                    menu_items.append(allocator, .action(MenuEvent.quit, "Quit")) catch {};

                    const dynamic_menu = menu.Menu.init(allocator, .{
                        .items = menu_items.items
                    }) catch return;
                    defer dynamic_menu.deinit();

                    if (systray.popover(dynamic_menu)) |me| {
                        // Window specific event
                        if (@divFloor(me.info.id, 100) > 0) {
                            const wid = @as(usize, @intCast(@divFloor(me.info.id, 100))) -| 1;
                            const window = self.event_loop.windows.values()[wid];
                            const id: MenuEvent = @enumFromInt(me.info.id % 100);
                            App.handleMenu(self.event_loop, window, id);
                        } else if (me.into(MenuEvent) == .quit) {
                            self.event_loop.closeAll();
                        }
                    }
                }
            },
            else => {
                // `.select` is never an option since `menu` was never assigned to the systray
            }
        }
    }
};

const MenuEvent = enum(u32) {
    toggle_visible,
    watch,
    quit,

    color_green,
    color_red,
    color_blue,
    color_black,
};

const SystrayEvent = enum(u32) {
    quit
};

const SystrayUserEvent = enum(u32) {
    pub const ID = 1;

    click,
    quit,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var event_loop = try EventLoop.init(io, gpa);
    defer event_loop.deinit();

    const path = try std.Io.Dir.cwd().realPathFileAlloc(io, "examples/assets/images/icon.ico", gpa);
    defer gpa.free(path);

    const window1 = try event_loop.createWindow(.{
        .title = "Window 1",
        .icon = .custom(path),
        // System tray requires a window. However we can hide it so that only the
        // system tray icon is visible.
        .show = .restore,
        .transparency = .blur,
    });

    const window2 = try event_loop.createWindow(.{
        .title = "Window 2",
        .icon = .custom(path),
        // System tray requires a window. However we can hide it so that only the
        // system tray icon is visible.
        .show = .restore,
        .transparency = .vibrant,
    });

    const shared_window_menu = try menu.Menu.init(gpa, .{
        .items = &.{
            .submenu("Window", &.{
                .action(MenuEvent.toggle_visible, "&Toggle Visible"),
                .toggle(MenuEvent.watch, "&Copy\tCtrl+C", false),
                .separator,
                .action(MenuEvent.quit, "&Quit\tAlt+F4"),
            }),
            .submenu("Color", &.{
                .group(&.{
                    .radio(MenuEvent.color_green, "Green", false),
                    .radio(MenuEvent.color_red, "Red", true),
                    .radio(MenuEvent.color_blue, "Blue", false),
                    .radio(MenuEvent.color_black, "Black", false),
                }),
            })
        }
    });
    defer shared_window_menu.deinit();

    try shared_window_menu.attach(window1.id());
    defer shared_window_menu.detach(window1.id());

    try shared_window_menu.attach(window2.id());
    defer shared_window_menu.detach(window2.id());

    const context_menu = try menu.Menu.init(gpa, .{
        .items = &.{
            .action(MenuEvent.toggle_visible, "Toggle Visible"),
            .toggle(MenuEvent.watch, "Watch\tCtrl+W", false),
            .separator,
            .submenu("Color", &.{
                .group(&.{
                    .radio(MenuEvent.color_green, "Green", false),
                    .radio(MenuEvent.color_red, "Red", true),
                    .radio(MenuEvent.color_blue, "Blue", false),
                    .radio(MenuEvent.color_black, "Black", false),
                })
            }),
            .separator,
            .action(MenuEvent.quit, "Quit"),
        },
    });
    defer context_menu.deinit();

    const systray_menu = try menu.Menu.init(gpa, .{
        .items = &.{
            .action(SystrayEvent.quit, "Quit"),
        },
    });
    defer systray_menu.deinit();
    const systray = try menu.SystemTray.initWithHandler(
        gpa,
        .{
            .tip = "Zig System Tray",
            // .menu = systray_menu,
            .icon = .custom(path),
        },
        SystemTrayHandler { .event_loop = event_loop, .allocator = gpa },
    );
    defer systray.deinit();

    const app = App {
        .context_menu = context_menu,
        .window_menu = shared_window_menu,
        .systray = systray,
    };

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            switch (e) {
                .window => |w| {
                    try app.handleEvent(event_loop, e.window.target, w.event);
                },
                .user => |u| {
                    App.handleUserEvent(event_loop, u);
                },
                else => {}
            }
        }
    }
}
