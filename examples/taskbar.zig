const std = @import("std");
const zinit = @import("zinit");
const menu = zinit.menu;

const EventLoop = zinit.event.EventLoop;
const WindowEvent = zinit.event.WindowEvent;
const Window = zinit.window.Window;

const App = struct {
    io: std.Io,
    paths: *const Paths,
    taskbar: *menu.Taskbar = undefined,

    playing: std.atomic.Value(bool),

    pub fn onWindow(self: *@This(), el: *EventLoop, win: *Window, event: WindowEvent) !void {
        switch (event) {
            .close => el.closeWindow(win.id()),
            .menu => |me| switch (me.kind) {
                .taskbar => switch (me.target) {
                    0 => {
                        std.debug.print("Previous\n", .{});
                    },
                    1 => {
                        std.debug.print("Play/Pause\n", .{});
                        const playing = !self.playing.load(.seq_cst);
                        self.playing.store(playing, .seq_cst);
                        if (playing) {
                            std.debug.print("Set Icon To Pause\n", .{});
                            try self.taskbar.setIcon(1, .custom(self.paths.pause) );
                            try self.taskbar.setTooltip(1, "Pause");
                            try self.taskbar.setJumpList(self.io, .{
                                .tasks = &.{
                                    .{ .label = "Previous", .args = "--prev", .icon = self.paths.prev },
                                    .{ .label = "Pause", .args = "--pause", .icon = self.paths.pause },
                                    .{ .label = "Next", .args = "--next", .icon = self.paths.next },
                                },
                            });
                        } else {
                            std.debug.print("Set Icon To Play\n", .{});
                            try self.taskbar.setIcon(1, .custom(self.paths.play) );
                            try self.taskbar.setTooltip(1, "Play");
                            try self.taskbar.setProgress(.paused, 1, 0);
                            try self.taskbar.setJumpList(self.io, .{
                                .tasks = &.{
                                    .{ .label = "Previous", .args = "--prev", .icon = self.paths.prev },
                                    .{ .label = "Play", .args = "--play", .icon = self.paths.play },
                                    .{ .label = "Next", .args = "--next", .icon = self.paths.next },
                                },
                            });
                        }
                    },
                    2 => {
                        std.debug.print("Next\n", .{});
                    },
                    else => {}
                },
                else => {}
            },
            else => {},
        }
    }
};

pub const Paths = struct {
    arena: std.heap.ArenaAllocator,

    app: []const u8 = "",

    play: []const u8 = "",
    pause: []const u8 = "",
    prev: []const u8 = "",
    next: []const u8 = "",

    pub fn init(io: std.Io, allocator: std.mem.Allocator) !@This() {
        var instance = @This() {
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
        errdefer instance.deinit();
        const allo = instance.arena.allocator();

        const cwd = std.Io.Dir.cwd();

        instance.app = try cwd.realPathFileAlloc(io, "examples/assets/images/icon.ico", allo);

        instance.play = try cwd.realPathFileAlloc(io, "examples/assets/play.ico", allo);
        instance.pause = try cwd.realPathFileAlloc(io, "examples/assets/pause.ico", allo);
        instance.next = try cwd.realPathFileAlloc(io, "examples/assets/skip-next.ico", allo);
        instance.prev = try cwd.realPathFileAlloc(io, "examples/assets/skip-previous.ico", allo);

        return instance;
    }

    pub fn deinit(self: *const @This()) void {
        self.arena.deinit();
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(gpa);
    defer args.deinit();

    if (args.inner.end > 1) {
        var client = std.http.Client{ .allocator = gpa, .io = io };
        defer client.deinit();

        _ = args.next(); // skip exe filename
        while (args.next()) |arg| {
            var uri: []const u8 = "";
            if (match("--play", arg)) {
                uri = "http://127.0.0.1:34617/play";
            } else if (match("--pause", arg)) {
                uri = "http://127.0.0.1:34617/pause";
            } else if (match("--next", arg)) {
                uri = "http://127.0.0.1:34617/next";
            } else if (match("--prev", arg)) {
                uri = "http://127.0.0.1:34617/prev";
            } else {
                std.debug.print("Invalid argument: {s}\n", .{ arg });
                return;
            }

            var response_body = std.Io.Writer.Allocating.init(gpa);
            defer response_body.deinit();

            _ = try client.fetch(.{
                .method = .POST,
                .location = .{ .url = uri },
                .payload = "",
                .response_writer = &response_body.writer,
                .headers = .{
                    .content_type = .{ .override = "text/plain" },
                }
            });
        }
        return;
    }

    const paths = try Paths.init(io, gpa);
    defer paths.deinit();

    var event_loop = try EventLoop.init(io, gpa);
    defer event_loop.deinit();

    const window = try event_loop.createWindow(.{
        .icon = .custom(paths.app),
    });

    var app = App {
        .io = io,
        .paths = &paths,
        .playing = .init(false),
    };

    var taskbar = try menu.Taskbar.attach(gpa, window.id(), .{
        .state = @ptrCast(&app),
        .buttons = &.{
            menu.Taskbar.Button {
                .icon = .custom(paths.prev),
                .tooltip = "Prev"
            },
            menu.Taskbar.Button {
                .icon = .custom(paths.play),
                .tooltip = "Play",
            },
            menu.Taskbar.Button {
                .icon = .custom(paths.next),
                .tooltip = "Next",
            }
        }
    });
    defer taskbar.detach();

    app.taskbar = taskbar;

    try taskbar.markFullscreen(true);
    try taskbar.setJumpList(io, .{
        .tasks = &.{
            .{ .label = "Previous", .args = "--prev", .icon = paths.prev },
            .{ .label = "Play", .args = "--play", .icon = paths.play },
            .{ .label = "Next", .args = "--next", .icon = paths.next },
        },
    });

    _ = try std.Thread.spawn(.{}, progressWorker, .{ io, &app });
    _ = try std.Thread.spawn(.{}, serverWorker, .{ io, gpa, &app });

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            switch (e) {
                .window => |w| {
                    try app.onWindow(event_loop, w.target, w.event);
                },
                else => {}
            }
        }
    }
}

fn progressWorker(io: std.Io, app: *App) void {
    const total_seconds = ((60 * 2) + 38);

    var current: u64 = 0;

    while (true) {
        if (app.playing.load(.seq_cst)) {
            if (current >= total_seconds) current = 0;
            app.taskbar.setProgress(.normal, current, total_seconds) catch {};
            current += 1;
        }

        std.Io.sleep(io, .fromSeconds(1), .awake) catch {};
    }
}

fn serverWorker(io: std.Io, allocator: std.mem.Allocator, app: *App) void {
    const address = std.Io.net.IpAddress.parseIp4("127.0.0.1", 34617) catch return;
    var server = address.listen(io, .{}) catch return;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = arena.allocator();

    while (true) {
        const conn = server.accept(io) catch return;
        defer conn.socket.close(io);

        var in: [8192]u8 = undefined;
        var out: [8192]u8 = undefined;

        var conn_reader = conn.reader(io, &in);
        var conn_writer = conn.writer(io, &out);

        var http_server = std.http.Server.init(&conn_reader.interface, &conn_writer.interface);

        var request = http_server.receiveHead() catch return;

        switch (request.head.method) {
            .POST => {
                if (match("/play", request.head.target)) {
                    app.playing.store(true, .seq_cst);
                    app.taskbar.setIcon(1, .custom(app.paths.pause) ) catch {};
                    app.taskbar.setTooltip(1, "Pause") catch {};
                    app.taskbar.setJumpList(io, .{
                        .tasks = &.{
                            .{ .label = "Previous", .args = "--prev", .icon = app.paths.prev },
                            .{ .label = "Pause", .args = "--pause", .icon = app.paths.pause },
                            .{ .label = "Next", .args = "--next", .icon = app.paths.next },
                        },
                    }) catch {};
                    request.respond("ok", .{ .status = .ok }) catch return;
                } else if (match("/pause", request.head.target)) {
                    app.playing.store(false, .seq_cst);
                    app.taskbar.setIcon(1, .custom(app.paths.play) ) catch {};
                    app.taskbar.setTooltip(1, "Play") catch {};
                    app.taskbar.setProgress(.paused, 1, 1) catch {};
                    app.taskbar.setJumpList(io, .{
                        .tasks = &.{
                            .{ .label = "Previous", .args = "--prev", .icon = app.paths.prev },
                            .{ .label = "Play", .args = "--play", .icon = app.paths.play },
                            .{ .label = "Next", .args = "--next", .icon = app.paths.next },
                        },
                    }) catch {};
                    request.respond("ok", .{ .status = .ok }) catch return;
                } else if (match("/next", request.head.target)) {
                    std.debug.print("Next\n", .{});
                    request.respond("ok", .{ .status = .ok }) catch return;
                } else if (match("/prev", request.head.target)) {
                    std.debug.print("Previous\n", .{});
                    request.respond("ok", .{ .status = .ok }) catch return;
                } else {
                    std.debug.print("POST[404] Path Not Found: {s}\n", .{request.head.target});
                    request.respond("", .{ .status = .not_found }) catch return;
                }
            },
            else => {
                std.debug.print("{t}[405] Method Not ALlowed: {s}\n", .{request.head.method, request.head.target});
                request.respond("Method Not Allowed", .{ .status = .method_not_allowed }) catch return;
            }
        }
    }
}

/// Match the string to a pattern
fn match(pattern: []const u8, url: []const u8) bool {
    return std.mem.eql(u8, url, pattern);
}
