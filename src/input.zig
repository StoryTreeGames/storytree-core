const impl = switch (@import("builtin").os.tag) {
    .windows => @import("windows/input.zig"),
    else => @compileError("platform not supported"),
};

pub const Key = union(enum) {
    virtual: VirtualKey,
    char: [4]u8,

    /// Character code points are u16 code points and there can potentially be 2
    /// unicode code points for a single character. This means there is a max
    /// size of up to around 4 bytes allocated for a single character.
    ///
    /// This method automatically converts to u8 and gives the exact length byte array
    /// that represents the given character
    pub fn getChar(self: @This()) ?[]u8 {
        for (self.char, 0..) |c, i| {
            if (c == 0) {
                return self.char[0..i];
            }
        }
        return self.char[0..];
    }
};

/// Keyboard key to keycode mapping
pub const VirtualKey = enum(u32) {
    /// backspace key
    backspace,
    /// tab key
    tab,
    /// clear key
    clear,
    /// enter key
    @"return",
    /// shift key
    shift,
    /// left shift key
    left_shift,
    /// right shift key
    right_shift,
    /// ctrl key
    control,
    /// left ctrl key
    left_control,
    /// right ctrl key
    right_control,
    /// alt key
    alt,
    /// left alt key
    left_alt,
    /// right alt key
    right_alt,
    /// left windows key
    left_super,
    /// right windows key
    right_super,
    /// caps lock key
    caps_lock,
    /// num lock key
    num_lock,
    /// scroll lock key
    scroll_lock,
    /// pause key
    pause,
    /// ime kana mode
    kana,
    /// ime hangul mode
    hangul,
    /// ime junja mode
    junja,
    /// ime final mode
    final,
    /// ime hanja mode
    hanja,
    /// ime kanji mode
    kanji,
    /// esc key
    escape,
    /// ime convert
    convert,
    /// ime nonconvert
    nonconvert,
    /// ime accept
    accept,
    /// ime mode change request
    modechange,
    /// page up key
    page_up,
    /// page down key
    page_down,
    /// end key
    end,
    /// home key
    home,
    /// left arrow key
    left,
    /// up arrow key
    up,
    /// right arrow key
    right,
    /// down arrow key
    down,
    /// select key
    select,
    /// print key
    print,
    /// execute key
    execute,
    /// print screen key
    snapshot,
    /// ins key
    insert,
    /// del key
    delete,
    /// help key
    help,
    /// applications key
    apps,
    /// computer sleep key
    sleep,
    /// numeric keypad 0 key
    numpad0,
    /// numeric keypad 1 key
    numpad1,
    /// numeric keypad 2 key
    numpad2,
    /// numeric keypad 3 key
    numpad3,
    /// numeric keypad 4 key
    numpad4,
    /// numeric keypad 5 key
    numpad5,
    /// numeric keypad 6 key
    numpad6,
    /// numeric keypad 7 key
    numpad7,
    /// numeric keypad 8 key
    numpad8,
    /// numeric keypad 9 key
    numpad9,
    /// multiply key
    multiply,
    /// add key
    add,
    /// separator key
    separator,
    /// subtract key
    subtract,
    /// decimal key
    decimal,
    /// divide key
    divide,
    /// f1 key
    f1,
    /// f2 key
    f2,
    /// f3 key
    f3,
    /// f4 key
    f4,
    /// f5 key
    f5,
    /// f6 key
    f6,
    /// f7 key
    f7,
    /// f8 key
    f8,
    /// f9 key
    f9,
    /// f10 key
    f10,
    /// f11 key
    f11,
    /// f12 key
    f12,
    /// f13 key
    f13,
    /// f14 key
    f14,
    /// f15 key
    f15,
    /// f16 key
    f16,
    /// f17 key
    f17,
    /// f18 key
    f18,
    /// f19 key
    f19,
    /// f20 key
    f20,
    /// f21 key
    f21,
    /// f22 key
    f22,
    /// f23 key
    f23,
    /// f24 key
    f24,
    /// browser back key
    browser_back,
    /// browser forward key
    browser_forward,
    /// browser refresh key
    browser_refresh,
    /// browser stop key
    browser_stop,
    /// browser search key
    browser_search,
    /// browser favorites key
    browser_favorites,
    /// browser start and home key
    browser_home,
    /// volume mute key
    volume_mute,
    /// volume down key
    volume_down,
    /// volume up key
    volume_up,
    /// next track key
    media_next_track,
    /// previous track key
    media_prev_track,
    /// stop media key
    media_stop,
    /// play/pause media key
    media_play_pause,
    /// start mail key
    launch_mail,
    /// select media key
    launch_media_select,
    /// start application 1 key
    launch_app1,
    /// start application 2 key
    launch_app2,
    /// the <> keys on the us standard keyboard, or the \\| key on the non-us 102-key keyboard
    oem_102,
    unknown,
};

pub const MouseButton = enum(u32) {
    /// The left mouse button.
    left,
    /// The middle mouse button.
    middle,
    /// The right mouse button.
    right,
    /// The first X button.
    x1,
    /// The second X button.
    x2,
    unknown,
};

/// Get whether the key is down
pub const getKeyDown = impl.getKeyState;
/// Get whether the key is up
pub fn getKeyUp(key: anytype) bool {
    return !impl.getKeyState(key);
}
