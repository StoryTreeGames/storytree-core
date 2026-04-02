pub const Cursor = union(enum) {
    symbol: Symbol,
    resource: struct {
        /// Path to the image file
        path: []const u8,
        /// The width of the cursor.
        width: i32 = 0,
        /// The height of the cursor.
        height: i32 = 0,
    },

    pub fn custom(path: []const u8, width: i32, height: i32) @This() {
        return .{
            .resource = .{
                .path = path,
                .width = width,
                .height = height,
            },
        };
    }

    pub const Default: @This() = .{ .symbol = .default };
    pub const Pointer: @This() = .{ .symbol = .pointer };
    pub const Crosshair: @This() = .{ .symbol = .crosshair };
    pub const Text: @This() = .{ .symbol = .text };
    pub const VerticalText: @This() = .{ .symbol = .vertical_text };
    pub const NotAllowed: @This() = .{ .symbol = .not_allowed };
    pub const NoDrop: @This() = .{ .symbol = .no_drop };
    pub const Grab: @This() = .{ .symbol = .grab };
    pub const Grabbing: @This() = .{ .symbol = .grabbing };
    pub const AllScroll: @This() = .{ .symbol = .all_scroll };
    pub const Move: @This() = .{ .symbol = .move };
    pub const EResize: @This() = .{ .symbol = .e_resize };
    pub const WResize: @This() = .{ .symbol = .w_resize };
    pub const EWResize: @This() = .{ .symbol = .ew_resize };
    pub const ColResize: @This() = .{ .symbol = .col_resize };
    pub const NResize: @This() = .{ .symbol = .n_resize };
    pub const SResize: @This() = .{ .symbol = .s_resize };
    pub const NSResize: @This() = .{ .symbol = .ns_resize };
    pub const RowResize: @This() = .{ .symbol = .row_resize };
    pub const NEResize: @This() = .{ .symbol = .ne_resize };
    pub const SWResize: @This() = .{ .symbol = .sw_resize };
    pub const NESWResize: @This() = .{ .symbol = .nesw_resize };
    pub const NWResize: @This() = .{ .symbol = .nw_resize };
    pub const SEResize: @This() = .{ .symbol = .se_resize };
    pub const NWSEResize: @This() = .{ .symbol = .nwse_resize };
    pub const Wait: @This() = .{ .symbol = .wait };
    pub const Help: @This() = .{ .symbol = .help };
    pub const Progress: @This() = .{ .symbol = .progress };
    pub const ContextMenu: @This() = .{ .symbol = .context_menu };
    pub const Cell: @This() = .{ .symbol = .cell };
    pub const Alias: @This() = .{ .symbol = .alias };
    pub const Copy: @This() = .{ .symbol = .copy };
    pub const ZoomIn: @This() = .{ .symbol = .zoom_in };
    pub const ZoomOut: @This() = .{ .symbol = .zoom_out };
};

pub const Symbol = enum(u8) {
    default,
    context_menu,
    help,
    pointer,
    progress,
    wait,
    cell,
    crosshair,
    text,
    vertical_text,
    alias,
    copy,
    move,
    no_drop,
    not_allowed,
    grab,
    grabbing,
    e_resize,
    n_resize,
    ne_resize,
    nw_resize,
    s_resize,
    se_resize,
    sw_resize,
    w_resize,
    ew_resize,
    ns_resize,
    nesw_resize,
    nwse_resize,
    col_resize,
    row_resize,
    all_scroll,
    zoom_in,
    zoom_out,
};

const impl = switch (@import("builtin").os.tag) {
    .windows => @import("windows/cursor.zig"),
    else => @compileError("platform not supported"),
};

pub const showCursor = impl.showCursor;
pub const clipCursor = impl.clipCursor;
pub const getCursorPos = impl.getCursorPos;
pub const getMouseButton = impl.getKeyState;
