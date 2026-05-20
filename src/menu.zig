const std = @import("std");
const builtin = @import("builtin");

const Icon = @import("./icon.zig").Icon;
const EventLoop = @import("./event.zig").EventLoop;
const Window = @import("./window.zig").Window;

pub const Taskbar = @import("./windows/taskbar.zig");

pub const SystemTray = switch (builtin.target.os.tag) {
    .windows => @import("./windows/menu.zig").SystemTray,
    else => @compileError("unsupported platform"),
};

pub const SystemTrayEvent = union(enum) {
    click: enum { left, right },
    select: MenuEvent,
};

pub const SystemTrayOptions = struct {
    tip: ?[]const u8 = null,
    icon: Icon = .Default,
    menu: ?*Menu = null,
};

pub const Menu = switch (builtin.target.os.tag) {
    .windows => @import("./windows/menu.zig").Menu,
    else => @compileError("unsupported platform"),
};

pub const MenuEvent = switch(builtin.target.os.tag) {
    .windows => @import("./windows/menu.zig").MenuEvent,
    else => @compileError("unsupported platform"),
};

pub const MenuOptions = struct {
    items: []const Item,
};

pub const Checkable = struct {
    id: u32,
    label: []const u8,
    default: bool = false,

    pub fn radio(id: anytype, label: []const u8, default: bool) @This() {
        return .{
            .id = Id.of(id),
            .label = label,
            .default = default,
        };
    }
};

pub const SubMenu = struct {
    label: [:0]const u8,
    items: []const Item,
};

pub const Action = struct {
    id: u32,
    label: []const u8,
};

pub const Item = union(enum) {
    separator: void,
    action_item: Action,
    toggle_item: Checkable,
    menu_item: SubMenu,
    radio_group_item: []const Checkable,

    pub fn action(id: anytype, label: []const u8) @This() {
        return .{
            .action_item = .{
                .id = Id.of(id),
                .label = label,
            },
        };
    }

    pub fn toggle(id: anytype, label: []const u8, default: bool) @This() {
        return .{
            .toggle_item = .{
                .id = Id.of(id),
                .label = label,
                .default = default,
            },
        };
    }

    pub fn submenu(label: [:0]const u8, items: []const Item) @This() {
        return .{
            .menu_item = .{
                .label = label,
                .items = items,
            },
        };
    }

    pub fn group(radio_group: []const Checkable) @This() {
        return .{ .radio_group_item = radio_group };
    }
};

pub const Id = struct {
    pub fn of(kind: anytype) u32 {
        const info = @typeInfo(@TypeOf(kind));

        return switch (info) {
            .@"enum" => @intFromEnum(kind),
            .comptime_int => kind,
            .int => |inner| switch(inner.signedness) {
                .signed => @bitCast(@as(i32, @intCast(kind))),
                .unsigned => @intCast(kind),
            },
            // .@"" => @intFromEnum(kind),
            else => @panic("invalid menu item identifier type"),
        };
    }
};

pub const Info = struct {
    id: u32,
    main: *anyopaque,
    context: ?*anyopaque,
    payload: Payload,

    pub fn isAction(self: *const @This()) bool {
        return self.payload == .action;
    }

    pub fn isToggle(self: *const @This()) bool {
        return self.payload == .toggle;
    }

    pub fn isRadio(self: *const @This()) bool {
        return self.payload == .radio;
    }

    pub fn label(self: *const @This()) [:0]const u8 {
        return switch (self.payload) {
            .action => |a| a.label,
            .toggle => |a| a.label,
            .radio => |a| a.label,
        };
    }

    pub const Payload = union(enum) {
        action: struct {
            label: [:0]const u8
        },
        toggle: struct {
            label: [:0]const u8,
            state: bool,
        },
        radio: struct {
            group: std.meta.Tuple(&.{ usize, usize }),
            label: [:0]const u8,
        },
    };
};
