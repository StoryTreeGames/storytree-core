const std = @import("std");

const windows = @import("windows");

const zinit = @import("zinit");
const event = zinit.event;
const input = zinit.input;
const drag_drop = zinit.drag_drop;

const Window = zinit.window.Window;
const EventLoop = event.EventLoop;
const WindowEvent = event.WindowEvent;

const DragKeyState = drag_drop.DragKeyState;
const DropEffect = drag_drop.DropEffect;
const DropData = drag_drop.DropData;

pub fn handleEvent(event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
    switch (evt) {
        .close => event_loop.closeWindow(window.id()),
        .key_input => |key_event| {
            std.debug.print("{any}\n", .{key_event.key});
        },
        else => {},
    }
}

fn onDrag(state: ?*anyopaque, point: zinit.Point(u32), key_state: DragKeyState) !DropEffect {
    _ = state;
    _ = point;

    if (key_state.control and key_state.shift) return .link;
    if (key_state.shift) return .move;
    return .copy;
}

fn onDrop(state: ?*anyopaque, point: zinit.Point(u32), key_state: DragKeyState, data: DropData) !DropEffect {
    _ = state;
    _ = point;

    for (data.mime_types()) |mime| {
        std.debug.print("{s}\n", .{mime});
    }

    if (data.contains("text/uri-list")) {
        const stdout = std.fs.File.stdout();
        var buffer: [1024]u8 = undefined;
        var writer = stdout.writer(&buffer);

        std.debug.print("[URL List]\n", .{});
        data.streamBytes("text/uri-list", &writer.interface);
    } else if (data.contains("application/x-virtual-files")) {
        if (data.getVirtualFiles()) |virtual_files| {
            const stdout = std.fs.File.stdout();
            var buffer: [1024]u8 = undefined;
            var writer = stdout.writer(&buffer);

            for (virtual_files.value) |vf| {
                std.debug.print("{d}. {s}\n", .{ vf.index, vf.name });
                vf.stream(&writer.interface) catch |err| {
                    std.debug.print("[error] {any}", .{err});
                };
                writer.interface.writeByte('\n') catch {};
                writer.interface.flush() catch {};
            }
        }
    } else if (data.contains("text/html")) {
        const stdout = std.fs.File.stdout();
        var buffer: [1024]u8 = undefined;
        var writer = stdout.writer(&buffer);

        std.debug.print("----- HTML -----\n", .{});
        data.streamBytes("text/html", &writer.interface);
        std.debug.print("\n", .{});
        std.debug.print("----- TEXT -----\n", .{});
        data.streamBytes("text/plain", &writer.interface);
    } else if (data.contains("text/plain")) {
        if (data.getText()) |text| {
            defer text.deinit();
            std.debug.print("[TEXT] {s}\n", .{text.value});
        }
    }

    if (key_state.control and key_state.shift) return .link;
    if (key_state.shift) return .move;
    return .copy;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    const window = try event_loop.createWindow(.{
        .title = "Drag & Drop",
        .width = 800,
        .height = 600,
    });
    try window.setDragDrop(.{
        .enter = onDrag,
        .over = onDrag,
        .drop = onDrop,
    });

    while (event_loop.isActive()) {
        // Collect all events currently in OS event buffer
        try event_loop.wait();
        // Remove the first event from the collected event buffer
        while (event_loop.pop()) |e| {
            if (e == .window) {
                try handleEvent(event_loop, e.window.target, e.window.event);
            }
        }
    }
}
