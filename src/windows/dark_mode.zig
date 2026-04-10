// Undocumented win32 API use references:
//  winit: https://github.com/rust-windowing/winit/blob/master/winit-win32/src/dark_mode.rs#L119
//  win32-darkmode: https://github.com/ysc3839/win32-darkmode
//
//  Alternatively something like the line can be used with Windows Runtime UISettings
//  to listen to theme changes and set the theme
//
//  DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &FALSE, @sizeOf(BOOL));

const std = @import("std");

const windows = @import("windows");
const win32 = windows.win32;

const zig = windows.win32.zig;
const windows_and_messaging = windows.win32.ui.windows_and_messaging;
const dwm = win32.graphics.dwm;

const UISettings = windows.UI.ViewManagement.UISettings;
const HWND = win32.foundation.HWND;

const util = @import("util.zig");
const Theme = @import("../window.zig").Theme;

const DARK_WINDOW_THEME = std.unicode.utf8ToUtf16LeStringLiteral("DarkMode_Explorer");
const LIGHT_WINDOW_THEME = std.unicode.utf8ToUtf16LeStringLiteral("");

pub fn tryTheme(hwnd: HWND, theme: ?Theme, refresh_title_bar: bool) Theme {
    const is_dark_mode = if (theme) |t| t == .dark else shouldUseDarkMode();
    if (
        win32.ui.controls.SetWindowTheme(hwnd, if (is_dark_mode) DARK_WINDOW_THEME else LIGHT_WINDOW_THEME, null) == 0
        and SetWindowDarkMode(hwnd, is_dark_mode)
    ) {
        if (refresh_title_bar) refreshTitlebarThemeColor(hwnd);
        return if (is_dark_mode) .dark else .light;
    }

    return .light;
}
fn SetWindowDarkMode(hwnd: HWND, is_dark_mode: bool) bool {
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

var ShouldAppsUseDarkMode: ?*const fn() callconv(.winapi) bool = null;
fn shouldAppsUseDarkMode() bool {
    if (ShouldAppsUseDarkMode) |callback| {
        return callback();
    } else {
        const dll_name = std.unicode.utf8ToUtf16LeStringLiteral("uxtheme.dll");
        const uxtheme = std.os.windows.kernel32.LoadLibraryW(dll_name) orelse return false;
        defer _ = std.os.windows.kernel32.FreeLibrary(uxtheme);

        const func_ptr = std.os.windows.kernel32.GetProcAddress(uxtheme, @ptrFromInt(132)) orelse return false;
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
