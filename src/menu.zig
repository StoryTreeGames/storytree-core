const std = @import("std");

pub const Checkable = struct {
    id: u32,
    label: []const u8,
    default: bool = false,

    pub fn radio(identifier: []const u8, label: []const u8, default: bool) @This() {
        return .{
            .id = Id.init(identifier).value,
            .label = label,
            .default = default,
        };
    }
};

pub const Menu = struct {
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
    menu_item: Menu,
    radio_group_item: []const Checkable,

    pub fn action(identifier: []const u8, label: []const u8) @This() {
        return .{
            .action_item = .{
                .id = Id.init(identifier).value,
                .label = label,
            },
        };
    }

    pub fn toggle(identifier: []const u8, label: []const u8, default: bool) @This() {
        return .{
            .toggle_item = .{
                .id = Id.init(identifier).value,
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

pub const Id = packed struct(u32) {
    value: u32,

    pub fn of(comptime hash: []const u8) u32 {
        return id(hash);
    }

    pub fn init(hash: []const u8) @This() {
        return .{ .value = @truncate(std.hash.Wyhash.hash(0, hash)) };
    }
};

pub fn id(comptime hash: []const u8) u32 {
    return @truncate(std.hash.Wyhash.hash(0, hash));
}

pub const Info = struct {
    id: u32,
    menu: *anyopaque,
    payload: Payload,

    pub const Payload = union(enum) {
        action: struct { label: [:0]const u8 },
        toggle: struct { label: [:0]const u8 },
        radio: struct {
            group: std.meta.Tuple(&.{ usize, usize }),
            label: [:0]const u8,
        },
    };
};
