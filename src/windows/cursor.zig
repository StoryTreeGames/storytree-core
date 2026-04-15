const win32 = @import("windows").win32;

const wam = win32.ui.windows_and_messaging;
const kam = win32.ui.input.keyboard_and_mouse;
const zig = win32.zig;
const Symbol = @import("../cursor.zig").Symbol;
const Rect = @import("../root.zig").Rect;
const Point = @import("../root.zig").Point;
const util = @import("util.zig");
const input = @import("../input.zig");

pub fn cursorToResource(cursor: Symbol) [*:0]align(1) const u16 {
    return switch (cursor) {
        .default => wam.IDC_ARROW,
        .pointer => wam.IDC_HAND,
        .crosshair => wam.IDC_CROSS,
        .text => wam.IDC_IBEAM,
        .vertical_text => wam.IDC_IBEAM,
        .not_allowed => wam.IDC_NO,
        .no_drop => wam.IDC_NO,
        .grab => wam.IDC_SIZEALL,
        .grabbing => wam.IDC_SIZEALL,
        .all_scroll => wam.IDC_SIZEALL,
        .move => wam.IDC_SIZEALL,
        .e_resize => wam.IDC_SIZEWE,
        .w_resize => wam.IDC_SIZEWE,
        .ew_resize => wam.IDC_SIZEWE,
        .col_resize => wam.IDC_SIZEWE,
        .n_resize => wam.IDC_SIZENS,
        .s_resize => wam.IDC_SIZENS,
        .ns_resize => wam.IDC_SIZENS,
        .row_resize => wam.IDC_SIZENS,
        .ne_resize => wam.IDC_SIZENESW,
        .sw_resize => wam.IDC_SIZENESW,
        .nesw_resize => wam.IDC_SIZENESW,
        .nw_resize => wam.IDC_SIZENWSE,
        .se_resize => wam.IDC_SIZENWSE,
        .nwse_resize => wam.IDC_SIZENWSE,
        .wait => wam.IDC_WAIT,
        .help => wam.IDC_HELP,
        .progress => wam.IDC_APPSTARTING,

        // All default to IDC_ARROW
        .context_menu => wam.IDC_ARROW,
        .cell => wam.IDC_ARROW,
        .alias => wam.IDC_ARROW,
        .copy => wam.IDC_ARROW,
        .zoom_in => wam.IDC_ARROW,
        .zoom_out => wam.IDC_ARROW,
    };
}

/// Show or hide the cursor
pub fn showCursor(state: bool) void {
    _ = wam.ShowCursor(if (state) zig.TRUE else zig.FALSE);
}

/// Restrict the cursor to the bounds of the provided Rect. If the bounds is null
/// it will remove any restriction on the cursors movement.
pub fn clipCursor(bounds: ?Rect(u32)) void {
    _ = wam.ClipCursor(if (bounds) |b| .{
        .left = @bitCast(b.x),
        .top = @bitCast(b.y),
        .right = @bitCast(b.x + b.width),
        .bottom = @bitCast(b.y + b.height),
    } else null);
}

/// Get the cursor position in screen coordinates
pub fn getCursorPos() Point(u32) {
    var point: util.POINT = undefined;
    _ = wam.GetCursorPos(&point);
    return .{
        .x = @bitCast(point.x),
        .y = @bitCast(point.y),
    };
}

/// Set the cursor position relative to the screen
pub fn setCursorPos(x: i32, y: i32) void {
    _ = wam.SetCursorPos(x, y);
}

/// Get whether the mouse button is down
pub fn getKeyState(mouse_button: input.MouseButton) bool {
    const value: u16 = switch (mouse_button) {
        .left => @intFromEnum(kam.VK_LBUTTON),
        .right => @intFromEnum(kam.VK_RBUTTON),
        .middle => @intFromEnum(kam.VK_MBUTTON),
        .x1 => @intFromEnum(kam.VK_XBUTTON1),
        .x2 => @intFromEnum(kam.VK_XBUTTON2),
        .unknown => 0,
    };

    if (value == 0) return false;

    return (@as(u16, @bitCast(kam.GetAsyncKeyState(value))) & 0x8000) != 0;
}
