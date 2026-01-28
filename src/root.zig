const std = @import("std");
pub const window = @import("window.zig");
pub const cursor = @import("cursor.zig");
pub const icon = @import("icon.zig");
pub const input = @import("input.zig");
pub const event = @import("event.zig");
pub const menu = @import("menu.zig");
pub const drag_drop = @import("drag_drop.zig");

pub fn Point(By: type) type {
    return struct {
        x: By,
        y: By,
    };
}

pub fn Rect(By: type) type {
    return struct {
        x: By,
        y: By,
        width: By,
        height: By,

        pub fn right(self: @This()) By {
            return self.x +| self.width;
        }

        pub fn bottom(self: @This()) By {
            return self.y +| self.height;
        }
    };
}

pub const Color = packed struct(u32) {
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,
    alpha: u8 = 0,

    pub const white: @This() = .{ .red = 255, .green = 255, .blue = 255 };
};

pub const Font = struct {
    height: u16,
    width: u16,
    point_size: u32,
    color: Color,
    weight: u32,
    italic: bool,
    underline: bool,
    strikeout: bool,
    name: []const u8,
    // TODO: precisions, charset, quality, pitch and family, orientation, escapement

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};
