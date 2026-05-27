// Undocumented win32 API use references:
//  winit: https://github.com/rust-windowing/winit/blob/master/winit-win32/src/dark_mode.rs#L119
//  win32-darkmode: https://github.com/ysc3839/win32-darkmode
//
//  Alternatively something like the line can be used with Windows Runtime UISettings
//  to listen to theme changes and set the theme
//
//  DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &FALSE, @sizeOf(BOOL));
//
//  Inspiration behind dark mode menus:
//    - https://github.com/tauri-apps/muda/pull/98/changes#diff-f40403bb1554dce5086709ec214c7103ad8b20df339b84ad3bde150d875cc4f5
//  Inspiration behind handling window transparency:
//    - https://github.com/tauri-apps/window-vibrancy/blob/dev/src/windows.rs#L224

const std = @import("std");

const windows = @import("windows");
const win32 = windows.win32;

const zig = windows.win32.zig;
const windows_and_messaging = windows.win32.ui.windows_and_messaging;
const library_loader = win32.system.library_loader;
const dwm = win32.graphics.dwm;

const DWMWINDOWATTRIBUTE = win32.graphics.dwm.DWMWINDOWATTRIBUTE;

const UISettings = windows.UI.ViewManagement.UISettings;
const HWND = win32.foundation.HWND;

const util = @import("util.zig");
const Theme = @import("../window.zig").Theme;
const Color = @import("../root.zig").Color;

const DARK_WINDOW_THEME = std.unicode.utf8ToUtf16LeStringLiteral("DarkMode_Explorer");
const LIGHT_WINDOW_THEME = std.unicode.utf8ToUtf16LeStringLiteral("");

const PreferredAppMode = enum(u32) {
    Default,
    AllowDark,
    ForceDark,
    ForceLight,
    Max
};

pub fn tryTheme(hwnd: HWND, theme: ?Theme, refresh_title_bar: bool) Theme {
    const is_dark_mode = if (theme) |t| t == .dark else shouldUseDarkMode();
    if (
        win32.ui.controls.SetWindowTheme(hwnd, if (is_dark_mode) DARK_WINDOW_THEME else LIGHT_WINDOW_THEME, null) == 0
        and setWindowDarkMode(hwnd, is_dark_mode)
    ) {
        if (refresh_title_bar) refreshTitlebarThemeColor(hwnd);
        return if (is_dark_mode) .dark else .light;
    }

    return .light;
}
fn setWindowDarkMode(hwnd: HWND, is_dark_mode: bool) bool {
    var bigbool = if (is_dark_mode) zig.TRUE else zig.FALSE;
    return dwm.DwmSetWindowAttribute(
        hwnd,
        dwm.DWMWA_USE_IMMERSIVE_DARK_MODE,
        &bigbool,
        @sizeOf(win32.foundation.BOOL)
    ) == 0;
}

fn refreshTitlebarThemeColor(hwnd: HWND) void {
    if (win32.ui.input.keyboard_and_mouse.GetActiveWindow() == hwnd) {
        _ = windows_and_messaging.DefWindowProcW(hwnd, windows_and_messaging.WM_NCACTIVATE, 0, 0);
        _ = windows_and_messaging.DefWindowProcW(hwnd, windows_and_messaging.WM_NCACTIVATE, 1, 0);
    } else {
        _ = windows_and_messaging.DefWindowProcW(hwnd, windows_and_messaging.WM_NCACTIVATE, 1, 0);
        _ = windows_and_messaging.DefWindowProcW(hwnd, windows_and_messaging.WM_NCACTIVATE, 0, 0);
    }
}

fn shouldUseDarkMode() bool {
    return shouldAppsUseDarkMode() and !isHighContrast();
}

var SetPreferredAppMode: ?*const fn(mode: PreferredAppMode) callconv(.winapi) bool = null;
pub fn setPreferredAppMode(mode: PreferredAppMode) bool {
    if (SetPreferredAppMode) |callback| {
        return callback(mode);
    } else {
        const dll_name = std.unicode.utf8ToUtf16LeStringLiteral("uxtheme.dll");
        const uxtheme = library_loader.LoadLibraryExW(dll_name, null, .{}) orelse return false;
        defer _ = library_loader.FreeLibrary(uxtheme);

        const func_ptr = library_loader.GetProcAddress(uxtheme, @ptrFromInt(135)) orelse return false;
        SetPreferredAppMode = @ptrCast(func_ptr);

        return SetPreferredAppMode.?(mode);
    }
}

var ShouldAppsUseDarkMode: ?*const fn() callconv(.winapi) bool = null;
fn shouldAppsUseDarkMode() bool {
    if (ShouldAppsUseDarkMode) |callback| {
        return callback();
    } else {
        const dll_name = std.unicode.utf8ToUtf16LeStringLiteral("uxtheme.dll");
        const uxtheme = library_loader.LoadLibraryExW(dll_name, null, .{}) orelse return false;
        defer _ = library_loader.FreeLibrary(uxtheme);

        const func_ptr = library_loader.GetProcAddress(uxtheme, @ptrFromInt(132)) orelse return false;
        ShouldAppsUseDarkMode = @ptrCast(func_ptr);

        return ShouldAppsUseDarkMode.?();
    }
}

fn isHighContrast() bool {
    const HIGHCONTRASTA = win32.ui.accessibility.HIGHCONTRASTA;
    var hc = HIGHCONTRASTA { .cbSize=0, .dwFlags=.{}, .lpszDefaultScheme=null };

    const ok = windows_and_messaging.SystemParametersInfoA(
        windows_and_messaging.SPI_GETHIGHCONTRAST,
        @sizeOf(HIGHCONTRASTA),
        @ptrCast(&hc),
        .{},
    );

    return ok == zig.TRUE and hc.dwFlags.HIGHCONTRASTON == 1;
}

pub fn applyLegacyBlur(hwnd: HWND) void {
    var rc: win32.foundation.RECT = undefined;
    _ = win32.ui.windows_and_messaging.GetClientRect(hwnd, &rc);

    const menuH = if (win32.ui.windows_and_messaging.GetMenu(hwnd)) |_|
        win32.ui.windows_and_messaging.GetSystemMetrics(win32.ui.windows_and_messaging.SM_CYMENU)
    else
        0;

    const rgn = win32.graphics.gdi.CreateRectRgn(rc.left, rc.top + menuH, rc.right, rc.bottom + menuH);

    var bb = win32.graphics.dwm.DWM_BLURBEHIND{ .dwFlags = win32.graphics.dwm.DWM_BB_ENABLE | win32.graphics.dwm.DWM_BB_BLURREGION, .fEnable = win32.zig.TRUE, .hRgnBlur = rgn, .fTransitionOnMaximized = win32.zig.FALSE };
    _ = win32.graphics.dwm.DwmEnableBlurBehindWindow(hwnd, &bb);
    _ = win32.graphics.gdi.DeleteObject(rgn);
}
pub fn disableLegacyBlur(hwnd: HWND) void {
    var bb = win32.graphics.dwm.DWM_BLURBEHIND{ .dwFlags = win32.graphics.dwm.DWM_BB_ENABLE, .fEnable = win32.zig.FALSE, .hRgnBlur = null, .fTransitionOnMaximized = win32.zig.FALSE };
    _ = win32.graphics.dwm.DwmEnableBlurBehindWindow(hwnd, &bb);
}

pub const DWMWA_MICA_EFFECT: i32 = 1029;
pub const DWMWA_SYSTEMBACKDROP_TYPE: i32 = 38;

pub const DWM_SYSTEMBACKDROP_TYPE = enum(c_int) {
    /// Let the system decide based on heuristics
    AUTO = 0,
    /// Do not draw any system backdrop
    NONE = 1,
    /// Mica effect (designed for long-lived main windows)
    MAINWINDOW = 2,
    /// Acrylic effect (designed for menus or transient popups)
    TRANSIENTWINDOW = 3,
    /// Mica Alt effect (designed for windows with tabbed titles)
    TABBEDWINDOW = 4,
};
pub fn applySystemBackdrop(hwnd: HWND, kind: DWM_SYSTEMBACKDROP_TYPE) void {
    var backdrop = kind;
    _ = win32.graphics.dwm.DwmSetWindowAttribute(hwnd, @enumFromInt(38), &backdrop, @sizeOf(DWMWINDOWATTRIBUTE));
}
pub fn clearSystemBackdrop(hwnd: HWND) void {
    _ = util.DwmSetWindowAttribute(hwnd, @enumFromInt(38), &1, @sizeOf(DWMWINDOWATTRIBUTE));
}

const WINDOWCOMPOSITIONATTRIB = enum(c_int) {
    ACCENT_POLICY = 0x13,
    _
};
const WINDOWCOMPOSITIONATTRIBDATA = extern struct {
    Attrib: WINDOWCOMPOSITIONATTRIB,
    pvData: *anyopaque,
    cbData: usize,
};

const ACCENT_POLICY = extern struct {
    AccentState: ACCENT_STATE,
    AccentFlags: u32,
    GradientColor: u32,
    AnimationId: u32,
};
const ACCENT_STATE = enum(c_int) {
    DISABLED = 0,
    ENABLE_BLURBEHIND = 3,
    ENABLE_ACRYLICBLURBEHIND = 4,
};

const SetWindowCompositionAttributeFn = *const fn(hwnd: HWND, data: *WINDOWCOMPOSITIONATTRIBDATA) bool;
var SetWindowCompositionAttribute: ?SetWindowCompositionAttributeFn = null;
fn setWindowCompositionAttribute(hwnd: HWND, accent_state: ACCENT_STATE, color: ?Color) !void {
    if (SetWindowCompositionAttribute == null) {
        const dll_name = std.unicode.utf8ToUtf16LeStringLiteral("user32.dll");
        const user32 = library_loader.LoadLibraryExW(dll_name, null, .{}) orelse return error.User32LibraryDynLoadFailure;
        defer _ = library_loader.FreeLibrary(user32);

        const func_ptr = library_loader.GetProcAddress(user32, "SetWindowCompositionAttribute") orelse return error.User32LibraryDynLoadFailure;
        SetWindowCompositionAttribute = @as(SetWindowCompositionAttributeFn, @ptrCast(func_ptr));
    }

    var c = color orelse Color{};
    const acrylic = accent_state == .ENABLE_ACRYLICBLURBEHIND;
    // Acrylic mode doesn't like 0 for alpha
    if (acrylic and c.alpha == 0) {
        c.alpha = 1;
    }

    var policy = ACCENT_POLICY {
        .AccentState = accent_state,
        .AccentFlags = if (acrylic) 0 else 2,
        .GradientColor = @bitCast(c),
        .AnimationId = 0,
    };

    var data = WINDOWCOMPOSITIONATTRIBDATA {
        .Attrib = .ACCENT_POLICY,
        .pvData = @ptrCast(&policy),
        .cbData = @sizeOf(ACCENT_POLICY)
    };

    _ = SetWindowCompositionAttribute.?(hwnd, &data);
}

/// Only available on Windows 10 v1809 or newer and Windows 11.
pub fn applyBlur(hwnd: HWND) !void {
    if (util.isBackdroptypeSupported()) {
        applySystemBackdrop(hwnd, .TRANSIENTWINDOW);
    } else if (util.isSWCASupported()) {
        try setWindowCompositionAttribute(hwnd, .ENABLE_ACRYLICBLURBEHIND, null);
    } else {
        return error.WindowsVersionNotSupported;
    }
}
pub fn clearBlur(hwnd: HWND) !void {
    if (util.isBackdroptypeSupported()) {
        clearSystemBackdrop(hwnd);
    } else if (util.isSWCASupported()) {
        try setWindowCompositionAttribute(hwnd, .DISABLED, null);
    } else {
        return error.WindowsVersionNotSupported;
    }
}

/// Only available on Windows 11
pub fn applyMica(hwnd: HWND) !void {
    if (util.isBackdroptypeSupported()) {
        applySystemBackdrop(hwnd, .MAINWINDOW);
    } else if (util.isUndocumentedMicaSupported()) {
        _ = util.DwmSetWindowAttribute(hwnd, DWMWA_MICA_EFFECT, &1, @sizeOf(win32.graphics.dwm.DWMWINDOWATTRIBUTE));
    } else {
        return error.WindowsVersionNotSupported;
    }
}
pub fn clearMica(hwnd: HWND) !void {
    if (util.isBackdroptypeSupported()) {
        clearSystemBackdrop(hwnd);
    } else if (util.isUndocumentedMicaSupported()) {
        _ = util.DwmSetWindowAttribute(hwnd, DWMWA_MICA_EFFECT, &0, @sizeOf(win32.graphics.dwm.DWMWINDOWATTRIBUTE));
    } else {
        return error.WindowsVersionNotSupported;
    }
}

/// Only available on Windows 11
pub fn applyAltMica(hwnd: HWND) !void {
    if (util.isBackdroptypeSupported()) {
        applySystemBackdrop(hwnd, .TABBEDWINDOW);
    } else {
        return error.WindowsVersionNotSupported;
    }
}
pub fn clearAltMica(hwnd: HWND) !void {
    if (util.isBackdroptypeSupported()) {
        clearSystemBackdrop(hwnd);
    } else {
        return error.WindowsVersionNotSupported;
    }
}
