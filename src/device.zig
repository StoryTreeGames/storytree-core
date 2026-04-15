const std = @import("std");

pub const Device = union(enum) {
    mouse: Mouse,
    keyboard: Keyboard,
    gamepad: Gamepad,

    pub fn id(self: *const @This()) usize {
        return switch (self.*) {
            .mouse => |m| m.id,
            .keyboard => |k| k.id,
            .gamepad => |g| g.id,
        };
    }
};

pub const Mouse = struct {
    id: usize,

    x: i32 = 0,
    y: i32 = 0,

    window: ?usize = null,

    buttons: MouseButtons = .{},
};

pub const MouseButtons = packed struct(u32) {
    left: bool = false,
    middle: bool = false,
    right: bool = false,
    /// 1-29 xbuttons which are anything other than
    /// left, middle, and right mouse buttons
    xbutton: XButtons(29) = .{},
};

fn XButtons(comptime count: usize) type {
    var fields: [count]std.builtin.Type.StructField = undefined;

    inline for (0..count) |i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("x{d}", .{ i + 1 }),
            .type = bool,
            .default_value = false,
            .alignment = 0,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .@"packed",
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        }
    });
}

pub const Keyboard = struct {
    id: usize,

    // TODO: Add keyboard specific state
};

pub const Gamepad = struct {
    id: usize,

    // TODO: Add gamepad specific state
};
