pub const Cursor = union(enum) {
    icon: CursorType,
    custom: struct {
        /// Path to the image file
        path: []const u8,
        /// The width of the cursor.
        width: i32 = 0,
        /// The height of the cursor.
        height: i32 = 0,
    },

    pub const Default: @This() = .{ .icon = .default };
    pub const Pointer: @This() = .{ .icon = .pointer };
    pub const Crosshair: @This() = .{ .icon = .crosshair };
    pub const Text: @This() = .{ .icon = .text };
    pub const VerticalText: @This() = .{ .icon = .vertical_text };
    pub const NotAllowed: @This() = .{ .icon = .not_allowed };
    pub const NoDrop: @This() = .{ .icon = .no_drop };
    pub const Grab: @This() = .{ .icon = .grab };
    pub const Grabbing: @This() = .{ .icon = .grabbing };
    pub const AllScroll: @This() = .{ .icon = .all_scroll };
    pub const Move: @This() = .{ .icon = .move };
    pub const EResize: @This() = .{ .icon = .e_resize };
    pub const WResize: @This() = .{ .icon = .w_resize };
    pub const EWResize: @This() = .{ .icon = .ew_resize };
    pub const ColResize: @This() = .{ .icon = .col_resize };
    pub const NResize: @This() = .{ .icon = .n_resize };
    pub const SResize: @This() = .{ .icon = .s_resize };
    pub const NSResize: @This() = .{ .icon = .ns_resize };
    pub const RowResize: @This() = .{ .icon = .row_resize };
    pub const NEResize: @This() = .{ .icon = .ne_resize };
    pub const SWResize: @This() = .{ .icon = .sw_resize };
    pub const NESWResize: @This() = .{ .icon = .nesw_resize };
    pub const NWResize: @This() = .{ .icon = .nw_resize };
    pub const SEResize: @This() = .{ .icon = .se_resize };
    pub const NWSEResize: @This() = .{ .icon = .nwse_resize };
    pub const Wait: @This() = .{ .icon = .wait };
    pub const Help: @This() = .{ .icon = .help };
    pub const Progress: @This() = .{ .icon = .progress };
    pub const ContextMenu: @This() = .{ .icon = .context_menu };
    pub const Cell: @This() = .{ .icon = .cell };
    pub const Alias: @This() = .{ .icon = .alias };
    pub const Copy: @This() = .{ .icon = .copy };
    pub const ZoomIn: @This() = .{ .icon = .zoom_in };
    pub const ZoomOut: @This() = .{ .icon = .zoom_out };
};

pub const CursorType = enum(u8) {
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
