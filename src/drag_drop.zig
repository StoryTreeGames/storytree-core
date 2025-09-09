const std = @import("std");
const builtin = @import("builtin");
const Point = @import("root.zig").Point;

pub const DropDataResolver = switch(builtin.target.os.tag) {
    .windows => @import("windows/drag_drop.zig").DropDataResolver,
    else => @compileError("unsupported platform")
};

pub const VirtualFile = switch(builtin.target.os.tag) {
    .windows => @import("windows/drag_drop.zig").VirtualFile,
    else => @compileError("unsupported platform")
};

pub const DropEffect = enum { none, move, copy, link, scroll };

pub const DragKeyState = struct {
    left: bool = false,
    middle: bool = false,
    right: bool = false,
    x1: bool = false,
    x2: bool = false,
    control: bool = false,
    shift: bool = false,
};

pub const DragDropContext = extern struct {
    enter: ?*anyopaque = null,
    over: ?*anyopaque = null,
    drop: ?*anyopaque = null, // TODO: Add way for user to process the data
    leave: ?*anyopaque = null,

    pub fn onEnter(self: *const @This(), state: ?*anyopaque, point: Point(u32), key_state: DragKeyState) DropEffect {
        if (self.enter) |c| {
            const callback: OnEnter = @ptrCast(@alignCast(c));
            return callback(state, point, key_state) catch .none;
        }
        return .none;
    }

    pub fn onOver(self: *const @This(), state: ?*anyopaque, point: Point(u32), key_state: DragKeyState) DropEffect {
        if (self.over) |c| {
            const callback: OnOver = @ptrCast(@alignCast(c));
            return callback(state, point, key_state) catch .none;
        }
        return .none;
    }

    pub fn onDrop(self: *const @This(), state: ?*anyopaque, point: Point(u32), key_state: DragKeyState, data: DropData) DropEffect {
        if (self.drop) |c| {
            const callback: OnDrop = @ptrCast(@alignCast(c));
            return callback(state, point, key_state, data) catch .none;
        }
        return .none;
    }

    pub fn onLeave(self: *const @This(), state: ?*anyopaque) void {
        if (self.leave) |c| {
            const callback: OnLeave = @ptrCast(@alignCast(c));
            callback(state) catch {};
        }
    }

    pub const OnEnter = *const fn (state: ?*anyopaque, point: Point(u32), key_state: DragKeyState) anyerror!DropEffect;
    pub const OnOver = *const fn (state: ?*anyopaque, point: Point(u32), key_state: DragKeyState) anyerror!DropEffect;
    pub const OnDrop = *const fn (state: ?*anyopaque, point: Point(u32), key_state: DragKeyState, data: DropData) anyerror!DropEffect;
    pub const OnLeave = *const fn (state: ?*anyopaque) anyerror!void;
};

pub fn Ref(T: type) type {
    return struct {
        __a: std.mem.Allocator,
        value: T,

        pub fn deinit(self: @This()) void {
            switch (@typeInfo(T)) {
                .pointer => |ptr| {
                    switch (@typeInfo(ptr.child)) {
                        .@"struct", .@"enum", .@"union", .@"opaque" => {
                            if (@hasDecl(ptr.child, "deinit")) {
                                if (ptr.size == .slice or ptr.size == .many) {
                                    for (self.value) |item| item.deinit(self.__a);
                                } else {
                                    self.value.deinit(self.__a);
                                }
                            }
                        },
                        else => {},
                    }

                    if (ptr.size == .one) {
                        self.__a.destroy(self.value);
                    } else if (ptr.size == .slice) {
                        self.__a.free(self.value);
                    }
                },
                else => {
                    if (@hasDecl(self.value, "deinit")) {
                        self.value.deinit(self.__a);
                    }
                },
            }
        }
    };
}

pub const DropData = struct {
    _state: ?*anyopaque,
    _allocator: std.mem.Allocator,
    mime_to_format: std.StringArrayHashMapUnmanaged(u16),

    pub fn init(allocator: std.mem.Allocator, instance: ?*anyopaque) @This() {
        if (instance) |data| {
            return .{
                ._allocator = allocator,
                ._state = instance,
                .mime_to_format = DropDataResolver.collectFormats(allocator, data) catch .empty,
            };
        } else {
            return .{
                ._allocator = allocator,
                ._state = instance,
                .mime_to_format = .empty,
            };
        }
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.mime_to_format.deinit(allocator);
    }

    pub fn contains(self: *const @This(), mime: []const u8) bool {
        return self.mime_to_format.contains(mime);
    }

    pub fn mime_types(self: *const @This()) []const []const u8 {
        return self.mime_to_format.keys();
    }

    pub fn streamBytes(self: *const @This(), mime: []const u8, writer: *std.io.Writer) void {
        if (self._state) |state| {
            DropDataResolver.streamBytes(
                writer,
                self._allocator,
                state,
                self.mime_to_format.get(mime) orelse 0,
            );
            writer.flush() catch {};
        }
    }

    pub fn getBytes(self: *const @This(), mime: []const u8) ?Ref([]const u8) {
        if (self._state) |state| {
            return DropDataResolver.getBytes(
                self._allocator,
                state,
                self.mime_to_format.get(mime) orelse 0,
            );
        }
        return null;
    }

    pub fn getText(self: *const @This()) ?Ref([]const u8) {
        if (self._state) |state| {
            return DropDataResolver.getText(self._allocator, state);
        }
        return null;
    }

    pub fn getVirtualFiles(self: *const @This()) ?Ref([]const VirtualFile) {
        if (self._state) |state| {
            return DropDataResolver.getVirtualFiles(self._allocator, state);
        }
        return null;
    }

    pub fn getUrlList(self: *const @This()) ?Ref([]const u8) {
        if (self._state) |state| {
            return DropDataResolver.getUrlList(self._allocator, state);
        }
        return null;
    }

    pub fn getHtml(self: *const @This()) ?Ref([]const u8) {
        if (self._state) |state| {
            return DropDataResolver.getHtml(self._allocator, state);
        }
        return null;
    }
};

pub const DropTarget = struct {
    allocator: std.mem.Allocator,
    context: DragDropContext,
    state: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator, context: Context) @This() {
        return .{
            .allocator = allocator,
            .context = .{
                .enter = @ptrCast(@constCast(context.enter)),
                .over = @ptrCast(@constCast(context.over)),
                .drop = @ptrCast(@constCast(context.drop)),
                .leave = @ptrCast(@constCast(context.leave)),
            },
        };
    }

    pub fn initWithState(allocator: std.mem.Allocator, context: Context, state: anytype) @This() {
        return .{ .allocator = allocator, .context = .{
            .enter = @ptrCast(@constCast(context.enter)),
            .over = @ptrCast(@constCast(context.over)),
            .drop = @ptrCast(@constCast(context.drop)),
            .leave = @ptrCast(@constCast(context.leave)),
        }, .state = @ptrCast(state) };
    }

    pub const Context = struct {
        enter: ?DragDropContext.OnEnter = null,
        over: ?DragDropContext.OnOver = null,
        drop: ?DragDropContext.OnDrop = null,
        leave: ?DragDropContext.OnLeave = null,
    };
};
