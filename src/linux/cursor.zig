const Shape = @import("wayland").client.wp.CursorShapeDeviceV1.Shape;
const CursorType = @import("../cursor.zig").CursorType;

pub fn cursorToShape(cursor: CursorType) Shape {
    const intermediate: c_int = @intFromEnum(cursor);
    return @enumFromInt(intermediate);
}

pub fn cursorToName(cursor: CursorType) []const [*:0]const u8 {
    return switch (cursor) {
        .default => &.{ "left_ptr", "default", "arrow" },
        .context_menu => &.{ "context-menu", "menu", "left_ptr" },
        .help => &.{ "help", "left_ptr_help", "question_arrow", "left_ptr" },
        .pointer => &.{ "hand2", "pointer", "hand1", "left_ptr" }, // “link”
        .progress => &.{ "left_ptr_watch", "progress", "watch", "wait", "left_ptr" },
        .wait => &.{ "wait", "watch", "progress" },

        .cell => &.{ "cell", "plus", "crosshair" },
        .crosshair => &.{"crosshair"}, // ---
        .text => &.{ "text", "xterm" },
        .vertical_text => &.{ "vertical-text", "vertical_text", "xterm" },

        .alias => &.{ "alias", "link", "hand2" },
        .copy => &.{ "copy", "dnd-copy", "plus" }, // ---
        .move => &.{ "move", "fleur" }, // ---
        .no_drop => &.{ "no-drop", "forbidden", "circle", "not-allowed" }, // ---
        .not_allowed => &.{ "not-allowed", "forbidden", "circle" }, // ---
        .grab => &.{ "grab", "openhand", "hand1" },
        .grabbing => &.{ "grabbing", "closedhand", "hand2" },

        // Edge resizes (single-edge)
        .e_resize => &.{ "right_side", "ew-resize", "sb_h_double_arrow" },
        .w_resize => &.{ "left_side", "ew-resize", "sb_h_double_arrow" },
        .n_resize => &.{ "top_side", "ns-resize", "sb_v_double_arrow" },
        .s_resize => &.{ "bottom_side", "ns-resize", "sb_v_double_arrow" },

        // Corners (diagonals)
        .ne_resize => &.{ "top_right_corner", "nesw-resize" },
        .nw_resize => &.{ "top_left_corner", "nwse-resize" },
        .se_resize => &.{ "bottom_right_corner", "nwse-resize" },
        .sw_resize => &.{ "bottom_left_corner", "nesw-resize" },

        // Double-arrow styles (column/row & generic)
        .ew_resize => &.{ "ew-resize", "sb_h_double_arrow" },
        .ns_resize => &.{ "ns-resize", "sb_v_double_arrow" },
        .nesw_resize => &.{ "nesw-resize", "top_right_corner", "bottom_left_corner" },
        .nwse_resize => &.{ "nwse-resize", "top_left_corner", "bottom_right_corner" },
        .col_resize => &.{ "col-resize", "sb_h_double_arrow", "ew-resize" },
        .row_resize => &.{ "row-resize", "sb_v_double_arrow", "ns-resize" },

        .all_scroll => &.{ "all-scroll", "fleur", "move" },
        .zoom_in => &.{ "zoom-in", "left_ptr" },
        .zoom_out => &.{ "zoom-out", "left_ptr" },
    };
}
