const kam = @import("windows").win32.ui.input.keyboard_and_mouse;
const VirtualKey = @import("../input.zig").VirtualKey;

const xkbcommon = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-keysyms.h");
});

pub fn virtualKeyToCode(virtual_key: VirtualKey) i32 {
    return switch (virtual_key) {
        .left_shift => xkbcommon.XKB_KEY_Shift_L,
        .right_shift => xkbcommon.XKB_KEY_Shift_R,
        .left_control => xkbcommon.XKB_KEY_Control_L,
        .right_control => xkbcommon.XKB_KEY_Control_R,
        .left_alt => xkbcommon.XKB_KEY_Alt_L,
        .right_alt => xkbcommon.XKB_KEY_Alt_R,
        .left_super => xkbcommon.XKB_KEY_Super_L,
        .right_super => xkbcommon.XKB_KEY_Super_R,

        .backspace => xkbcommon.XKB_KEY_BackSpace,
        .tab => xkbcommon.XKB_KEY_Tab,
        .@"return" => xkbcommon.XKB_KEY_Return,
        .pause => xkbcommon.XKB_KEY_Pause,
        .caps_lock => xkbcommon.XKB_KEY_Caps_Lock,
        .escape => xkbcommon.XKB_KEY_Escape,
        .insert => xkbcommon.XKB_KEY_Insert,
        .delete => xkbcommon.XKB_KEY_Delete,
        .home => xkbcommon.XKB_KEY_Home,
        .end => xkbcommon.XKB_KEY_End,
        .page_up => xkbcommon.XKB_KEY_Page_Up,
        .page_down => xkbcommon.XKB_KEY_Page_Down,

        .clear => xkbcommon.XKB_KEY_Clear,
        .select => xkbcommon.XKB_KEY_Select,
        .snapshot => xkbcommon.XKB_KEY_Print,
        .print => xkbcommon.XKB_KEY_Print,
        .execute => xkbcommon.XKB_KEY_Execute,
        .help => xkbcommon.XKB_KEY_Help,
        .apps => xkbcommon.XKB_KEY_Menu,

        .left => xkbcommon.XKB_KEY_Left,
        .up => xkbcommon.XKB_KEY_Up,
        .right => xkbcommon.XKB_KEY_Right,
        .down => xkbcommon.XKB_KEY_Down,

        .f1 => xkbcommon.XKB_KEY_F1,
        .f2 => xkbcommon.XKB_KEY_F2,
        .f3 => xkbcommon.XKB_KEY_F3,
        .f4 => xkbcommon.XKB_KEY_F4,
        .f5 => xkbcommon.XKB_KEY_F5,
        .f6 => xkbcommon.XKB_KEY_F6,
        .f7 => xkbcommon.XKB_KEY_F7,
        .f8 => xkbcommon.XKB_KEY_F8,
        .f9 => xkbcommon.XKB_KEY_F9,
        .f10 => xkbcommon.XKB_KEY_F10,
        .f11 => xkbcommon.XKB_KEY_F11,
        .f12 => xkbcommon.XKB_KEY_F12,
        .f13 => xkbcommon.XKB_KEY_F13,
        .f14 => xkbcommon.XKB_KEY_F14,
        .f15 => xkbcommon.XKB_KEY_F15,
        .f16 => xkbcommon.XKB_KEY_F16,
        .f17 => xkbcommon.XKB_KEY_F17,
        .f18 => xkbcommon.XKB_KEY_F18,
        .f19 => xkbcommon.XKB_KEY_F19,
        .f20 => xkbcommon.XKB_KEY_F20,
        .f21 => xkbcommon.XKB_KEY_F21,
        .f22 => xkbcommon.XKB_KEY_F22,
        .f23 => xkbcommon.XKB_KEY_F23,
        .f24 => xkbcommon.XKB_KEY_F24,

        .numpad0 => xkbcommon.XKB_KEY_KP_0,
        .numpad1 => xkbcommon.XKB_KEY_KP_1,
        .numpad2 => xkbcommon.XKB_KEY_KP_2,
        .numpad3 => xkbcommon.XKB_KEY_KP_3,
        .numpad4 => xkbcommon.XKB_KEY_KP_4,
        .numpad5 => xkbcommon.XKB_KEY_KP_5,
        .numpad6 => xkbcommon.XKB_KEY_KP_6,
        .numpad7 => xkbcommon.XKB_KEY_KP_7,
        .numpad8 => xkbcommon.XKB_KEY_KP_8,
        .numpad9 => xkbcommon.XKB_KEY_KP_9,
        .multiply => xkbcommon.XKB_KEY_KP_Multiply,
        .add => xkbcommon.XKB_KEY_KP_Add,
        .separator => xkbcommon.XKB_KEY_KP_Separator,
        .subtract => xkbcommon.XKB_KEY_KP_Subtract,
        .decimal => xkbcommon.XKB_KEY_KP_Decimal,
        .divide => xkbcommon.XKB_KEY_KP_Divide,
        .@"return" => xkbcommon.XKB_KEY_KP_Enter,

        .num_lock => xkbcommon.XKB_KEY_Num_Lock,
        .scroll_lock => xkbcommon.XKB_KEY_Scroll_Lock,
        .caps_lock => xkbcommon.XKB_KEY_Caps_Lock,

        .convert => xkbcommon.XKB_KEY_Henkan,
        .nonconvert => xkbcommon.XKB_KEY_Muhenkan,
        .kanji => xkbcommon.XKB_KEY_Kanji,
        .hangul => xkbcommon.XKB_KEY_Hangul,
        .hanja => xkbcommon.XKB_KEY_Hangul_Hanja,
        .kana => xkbcommon.XKB_KEY_Kana_Shift,
        .compose => xkbcommon.XKB_KEY_Multi_key,

        .browser_back => xkbcommon.XKB_KEY_XF86Back,
        .browser_forward => xkbcommon.XKB_KEY_XF86Forward,
        .browser_refresh => xkbcommon.XKB_KEY_XF86Refresh,
        .browser_stop => xkbcommon.XKB_KEY_XF86Stop,
        .browser_search => xkbcommon.XKB_KEY_XF86Search,
        .browser_favorites => xkbcommon.XKB_KEY_XF86Favorites,
        .browser_home => xkbcommon.XKB_KEY_XF86HomePage,

        .volume_mute => xkbcommon.XKB_KEY_XF86AudioMute,
        .volume_down => xkbcommon.XKB_KEY_XF86AudioLowerVolume,
        .volume_up => xkbcommon.XKB_KEY_XF86AudioRaiseVolume,

        .media_next_track => xkbcommon.XKB_KEY_XF86AudioNext,
        .media_prev_track => xkbcommon.XKB_KEY_XF86AudioPrev,
        .media_stop => xkbcommon.XKB_KEY_XF86AudioStop,
        .media_play_pause => xkbcommon.XKB_KEY_XF86AudioPlay,

        .launch_mail => xkbcommon.XKB_KEY_XF86Mail,
        .launch_media_select => xkbcommon.XKB_KEY_XF86AudioMedia,
        .launch_app1 => xkbcommon.XKB_KEY_XF86Launch1,
        .launch_app2 => xkbcommon.XKB_KEY_XF86Launch2,
        .sleep => xkbcommon.XKB_KEY_XF86Sleep,
        .oem_102 => 0,
    };
}

pub fn codeToVirtualKey(code: u32, keycode: u32) ?VirtualKey {
    if (keycode == 86) return .oem_102;
    return switch (code) {
        xkbcommon.XKB_KEY_Shift_L => .left_shift,
        xkbcommon.XKB_KEY_Shift_R => .right_shift,
        xkbcommon.XKB_KEY_Control_L => .left_control,
        xkbcommon.XKB_KEY_Control_R => .right_control,
        xkbcommon.XKB_KEY_Alt_L => .left_alt,
        xkbcommon.XKB_KEY_Alt_R => .right_alt,
        xkbcommon.XKB_KEY_Super_L, xkbcommon.XKB_KEY_Meta_L => .left_super,
        xkbcommon.XKB_KEY_Super_R, xkbcommon.XKB_KEY_Meta_R => .right_super,

        xkbcommon.XKB_KEY_BackSpace => .backspace,
        xkbcommon.XKB_KEY_Tab => .tab,
        xkbcommon.XKB_KEY_Return => .@"return",
        xkbcommon.XKB_KEY_Pause => .pause,
        xkbcommon.XKB_KEY_Escape => .escape,
        xkbcommon.XKB_KEY_Insert => .insert,
        xkbcommon.XKB_KEY_Delete => .delete,
        xkbcommon.XKB_KEY_Home => .home,
        xkbcommon.XKB_KEY_End => .end,
        xkbcommon.XKB_KEY_Page_Up => .page_up,
        xkbcommon.XKB_KEY_Page_Down => .page_down,

        xkbcommon.XKB_KEY_Clear => .clear,
        xkbcommon.XKB_KEY_Select => .select,
        xkbcommon.XKB_KEY_Print => .snapshot,
        // xkbcommon.XKB_KEY_Print => .print,
        xkbcommon.XKB_KEY_Execute => .execute,
        xkbcommon.XKB_KEY_Help => .help,
        xkbcommon.XKB_KEY_Menu => .apps,

        xkbcommon.XKB_KEY_Left => .left,
        xkbcommon.XKB_KEY_Up => .up,
        xkbcommon.XKB_KEY_Right => .right,
        xkbcommon.XKB_KEY_Down => .down,

        xkbcommon.XKB_KEY_F1 => .f1,
        xkbcommon.XKB_KEY_F2 => .f2,
        xkbcommon.XKB_KEY_F3 => .f3,
        xkbcommon.XKB_KEY_F4 => .f4,
        xkbcommon.XKB_KEY_F5 => .f5,
        xkbcommon.XKB_KEY_F6 => .f6,
        xkbcommon.XKB_KEY_F7 => .f7,
        xkbcommon.XKB_KEY_F8 => .f8,
        xkbcommon.XKB_KEY_F9 => .f9,
        xkbcommon.XKB_KEY_F10 => .f10,
        xkbcommon.XKB_KEY_F11 => .f11,
        xkbcommon.XKB_KEY_F12 => .f12,
        xkbcommon.XKB_KEY_F13 => .f13,
        xkbcommon.XKB_KEY_F14 => .f14,
        xkbcommon.XKB_KEY_F15 => .f15,
        xkbcommon.XKB_KEY_F16 => .f16,
        xkbcommon.XKB_KEY_F17 => .f17,
        xkbcommon.XKB_KEY_F18 => .f18,
        xkbcommon.XKB_KEY_F19 => .f19,
        xkbcommon.XKB_KEY_F20 => .f20,
        xkbcommon.XKB_KEY_F21 => .f21,
        xkbcommon.XKB_KEY_F22 => .f22,
        xkbcommon.XKB_KEY_F23 => .f23,
        xkbcommon.XKB_KEY_F24 => .f24,

        xkbcommon.XKB_KEY_KP_0 => .numpad0,
        xkbcommon.XKB_KEY_KP_1 => .numpad1,
        xkbcommon.XKB_KEY_KP_2 => .numpad2,
        xkbcommon.XKB_KEY_KP_3 => .numpad3,
        xkbcommon.XKB_KEY_KP_4 => .numpad4,
        xkbcommon.XKB_KEY_KP_5 => .numpad5,
        xkbcommon.XKB_KEY_KP_6 => .numpad6,
        xkbcommon.XKB_KEY_KP_7 => .numpad7,
        xkbcommon.XKB_KEY_KP_8 => .numpad8,
        xkbcommon.XKB_KEY_KP_9 => .numpad9,
        xkbcommon.XKB_KEY_KP_Multiply => .multiply,
        xkbcommon.XKB_KEY_KP_Add => .add,
        xkbcommon.XKB_KEY_KP_Separator => .separator,
        xkbcommon.XKB_KEY_KP_Subtract => .subtract,
        xkbcommon.XKB_KEY_KP_Decimal => .decimal,
        xkbcommon.XKB_KEY_KP_Divide => .divide,
        xkbcommon.XKB_KEY_KP_Enter => .@"return",

        xkbcommon.XKB_KEY_Num_Lock => .num_lock,
        xkbcommon.XKB_KEY_Scroll_Lock => .scroll_lock,
        xkbcommon.XKB_KEY_Caps_Lock => .caps_lock,

        xkbcommon.XKB_KEY_Henkan => .convert,
        xkbcommon.XKB_KEY_Muhenkan => .nonconvert,
        xkbcommon.XKB_KEY_Zenkaku_Hankaku, xkbcommon.XKB_KEY_Kanji => .kanji,
        xkbcommon.XKB_KEY_Hangul => .hangul,
        xkbcommon.XKB_KEY_Hangul_Hanja => .hanja,
        xkbcommon.XKB_KEY_Kana_Shift, xkbcommon.XKB_KEY_Hiragana, xkbcommon.XKB_KEY_Katakana => .kana,
        // xkbcommon.XKB_KEY_Multi_key => .compose,

        xkbcommon.XKB_KEY_XF86Back => .browser_back,
        xkbcommon.XKB_KEY_XF86Forward => .browser_forward,
        xkbcommon.XKB_KEY_XF86Refresh => .browser_refresh,
        xkbcommon.XKB_KEY_XF86Stop => .browser_stop,
        xkbcommon.XKB_KEY_XF86Search => .browser_search,
        xkbcommon.XKB_KEY_XF86Favorites => .browser_favorites,
        xkbcommon.XKB_KEY_XF86HomePage => .browser_home,

        xkbcommon.XKB_KEY_XF86AudioMute => .volume_mute,
        xkbcommon.XKB_KEY_XF86AudioLowerVolume => .volume_down,
        xkbcommon.XKB_KEY_XF86AudioRaiseVolume => .volume_up,

        xkbcommon.XKB_KEY_XF86AudioNext => .media_next_track,
        xkbcommon.XKB_KEY_XF86AudioPrev => .media_prev_track,
        xkbcommon.XKB_KEY_XF86AudioStop => .media_stop,
        xkbcommon.XKB_KEY_XF86AudioPlay, xkbcommon.XKB_KEY_XF86AudioPause => .media_play_pause,

        xkbcommon.XKB_KEY_XF86Mail => .launch_mail,
        xkbcommon.XKB_KEY_XF86AudioMedia => .launch_media_select,
        xkbcommon.XKB_KEY_XF86Launch1 => .launch_app1,
        xkbcommon.XKB_KEY_XF86Launch2 => .launch_app2,
        xkbcommon.XKB_KEY_XF86Sleep => .sleep,
        else => null,
    };
}

// /// Get whether the key is down
// pub fn getKeyState(key: anytype) bool {
//     const KEY = @TypeOf(key);
//     var value = switch (KEY) {
//         u8, u21, u32, comptime_int => @as(i32, @bitCast(@as(u32, @intCast(key)))),
//         VirtualKey, @Type(.enum_literal) => virtualKeyToCode(key),
//         else => @compileError("expected char or virtual key"),
//     };

//     if (key >= 97 and key <= 122) {
//         value = value - 32;
//     }

//     return (kam.GetKeyState(value) & 0x80) != 0;
// }

// /// Get whether the key has been set since the last
// /// call to this function
// pub fn getAsyncKeyState(key: anytype) bool {
//     const KEY = @TypeOf(key);
//     var value = switch (KEY) {
//         u8, u21, u32, comptime_int => @as(i32, @bitCast(@as(u32, @intCast(key)))),
//         VirtualKey, @Type(.enum_literal) => virtualKeyToCode(key),
//         else => @compileError("expected char or virtual key"),
//     };

//     if (key >= 97 and key <= 122) {
//         value = value - 32;
//     }

//     return (kam.GetAsyncKeyState(value) & 0x01) != 0;
// }
