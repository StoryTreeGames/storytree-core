const std = @import("std");
const wam = @import("windows").win32.ui.windows_and_messaging;
const Symbol = @import("../icon.zig").Symbol;

const HICON = wam.HICON;
const DestroyIcon = wam.DestroyIcon;

/// Helper (Windows): Make an int resource referencing the name of the resource.
///
/// - @param `offset` The offset into the collection of resource names
///
/// @returns Name of the resource
fn makeIntResourceW(comptime value: usize) [*:0]align(1) const u16 {
    return @ptrFromInt(value);
}

pub fn iconToResource(icon: Symbol) [*:0]align(1) const u16 {
    return switch (icon) {
        .default => wam.IDI_APPLICATION,
        .@"error" => makeIntResourceW(wam.IDI_ERROR),
        .question => wam.IDI_QUESTION,
        .warning => makeIntResourceW(wam.IDI_WARNING),
        .information => makeIntResourceW(wam.IDI_INFORMATION),
        .security => wam.IDI_SHIELD,
    };
}

pub const Icon = union(enum) {
    system: ?HICON,
    resource: ?HICON,

    pub fn handle(self: *const @This()) ?HICON {
        return switch (self.*) {
            .system => |h| h,
            .resource => |h| h,
        };
    }

    pub fn init(allocator: std.mem.Allocator, ico: @import("../icon.zig").Icon) !@This() {
        switch (ico) {
            .symbol => |i| return .{ .system = wam.LoadIconW(null, iconToResource(i)) },
            .resource => |c| {
                const path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, c);
                defer allocator.free(path);

                return .{
                    .resource = @ptrCast(wam.LoadImageW(
                        null,
                        path.ptr,
                        wam.IMAGE_ICON,
                        0,
                        0,
                        wam.IMAGE_FLAGS{
                            .DEFAULTSIZE = 1,
                            .LOADFROMFILE = 1,
                            .SHARED = 1,
                            .LOADTRANSPARENT = 1,
                        },
                    )),
                };
            },
        }
    }

    pub fn deinit(self: *const @This()) void {
        switch (self.*) {
            .resource => |h| _ = DestroyIcon(h),
            else =>{}
        }
    }
};
