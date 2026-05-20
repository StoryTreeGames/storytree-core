const std = @import("std");
const windows = @import("windows");

const win32 = windows.win32;
const ole = win32.system.ole;
const foundation = win32.foundation;
const windows_and_messaging = win32.ui.windows_and_messaging;
const keyboard_and_mouse = win32.ui.input.keyboard_and_mouse;
const library_loader = win32.system.library_loader;
const gdi = win32.graphics.gdi;
const zig = win32.zig;
const shell = win32.ui.shell;
const dwm = win32.graphics.dwm;

const NIM_ADD = shell.NIM_ADD;
const NIM_MODIFY = shell.NIM_MODIFY;
const NIM_DELETE = shell.NIM_DELETE;
const NIM_SETVERSION = shell.NIM_SETVERSION;
const NOTIFYICONDATAW = shell.NOTIFYICONDATAW;
const HICON = windows_and_messaging.HICON;
const HCURSOR = windows_and_messaging.HCURSOR;
const HWND = foundation.HWND;
const DestroyIcon = windows_and_messaging.DestroyIcon;
const DestroyCursor = windows_and_messaging.DestroyCursor;
const Shell_NotifyIconW = shell.Shell_NotifyIconW;

const csr = @import("../cursor.zig");
const ico = @import("../icon.zig");
const Rect = @import("../root.zig").Rect;
const Win = @import("../window.zig");
const dark_mode = @import("dark_mode.zig");
const util = @import("util.zig");
const EventLoop = @import("../event.zig").EventLoop;
const Cursor = @import("cursor.zig").Cursor;
const cursorToResource = @import("cursor.zig").cursorToResource;
const Icon = @import("icon.zig").Icon;
const iconToResource = @import("icon.zig").iconToResource;

arena: std.heap.ArenaAllocator,

title: [:0]const u16 = undefined,
class: [:0]const u16 = undefined,

handle: foundation.HWND = undefined,
instance: ?foundation.HINSTANCE = null,

icon: Icon = .{ .system = null },
cursor: Cursor = .{ .system = null },

theme: Win.Theme = .light,
preferred_theme: ?Win.Theme = null,
acrylic: bool = false,

fullscreen_state: ?struct {
    client: util.RECT,
    style: windows_and_messaging.WINDOW_STYLE,
    ex_style: windows_and_messaging.WINDOW_EX_STYLE,
    state: windows_and_messaging.SHOW_WINDOW_CMD,
} = null,

mouse_over: bool = false,

pub fn init(
    allocator: std.mem.Allocator,
    event_loop: *EventLoop,
    options: Win.Options,
) !*@This() {
    const win = try allocator.create(@This());
    errdefer allocator.destroy(win);

    win.* = .{
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
    const allo = win.arena.allocator();

    win.title = try util.utf8ToUtf16Alloc(allo, options.title);
    errdefer allo.free(win.title);
    win.class = try util.createUIDClass(event_loop.io, allo);
    errdefer allo.free(win.class);

    win.instance = library_loader.GetModuleHandleW(null);
    const wnd_class = windows_and_messaging.WNDCLASSW{
        .lpszClassName = win.class.ptr,

        .style = windows_and_messaging.WNDCLASS_STYLES{ .HREDRAW = 1, .VREDRAW = 1 },
        .cbClsExtra = 0,
        .cbWndExtra = 0,

        .hIcon = null,
        .hCursor = null,
        .hbrBackground = gdi.GetStockObject(if (options.acrylic) gdi.HOLLOW_BRUSH else gdi.WHITE_BRUSH),
        .lpszMenuName = null,

        .hInstance = win.instance,
        .lpfnWndProc = wndProc, // wndProc,
    };

    const result = windows_and_messaging.RegisterClassW(&wnd_class);

    if (result == 0) {
        return error.SystemCreateWindow;
    }

    const window_style = windows_and_messaging.WINDOW_STYLE{
        .TABSTOP = 1,
        .GROUP = 1,
        .THICKFRAME = @intFromBool(options.resizable),
        .SYSMENU = 1,
        .DLGFRAME = 1,
        .BORDER = 1,
        // Show window after it is created
        // .MINIMIZE = @intFromBool(options.show == .minimize),
        // .MAXIMIZE = @intFromBool(options.show == .maximize),
    };

    win.handle = windows_and_messaging.CreateWindowExW(
        windows_and_messaging.WINDOW_EX_STYLE{ .COMPOSITED = 1 },
        win.class.ptr,
        win.title.ptr,
        window_style, // style
        if (options.x) |x| @intCast(x) else windows_and_messaging.CW_USEDEFAULT,
        if (options.y) |y| @intCast(y) else windows_and_messaging.CW_USEDEFAULT, // initial position
        if (options.width) |width| @intCast(width) else windows_and_messaging.CW_USEDEFAULT,
        if (options.height) |height| @intCast(height) else windows_and_messaging.CW_USEDEFAULT, // initial size
        null, // Parent
        null, // Menu
        win.instance,
        @ptrCast(event_loop), // WM_CREATE lpParam
    ) orelse return error.SystemCreateWindow;

    win.preferred_theme = options.theme;
    win.setTheme(options.theme);

    if (options.acrylic) {
        win.acrylic = true;

        const DWM_SYSTEMBACKDROP_TYPE = enum (i32) {
            AUTO = 0,
            NONE = 1,
            MAINWINDOW = 2,      // Mica
            TRANSIENTWINDOW = 3, // Acrylic
            TABBEDWINDOW = 4     // Mica Alt
        };
        var backdrop = DWM_SYSTEMBACKDROP_TYPE.TRANSIENTWINDOW;
        _ = dwm.DwmSetWindowAttribute(win.handle, @enumFromInt(38), &backdrop, @sizeOf(DWM_SYSTEMBACKDROP_TYPE));

        util.applyLegacyBlur(win.handle);
        _ = gdi.InvalidateRect(win.handle, null, zig.FALSE);
    }

    _ = windows_and_messaging.ShowWindow(win.handle, switch (options.show) {
        .hidden => windows_and_messaging.SW_HIDE,
        .minimize => windows_and_messaging.SW_MINIMIZE,
        .maximize => windows_and_messaging.SW_MAXIMIZE,
        else => windows_and_messaging.SW_SHOWDEFAULT,
    });
    _ = gdi.UpdateWindow(win.handle);

    try win.setCursor(options.cursor);
    try win.setIcon(options.icon);

    if (options.show == .fullscreen) {
        win.fullscreen() catch {};
    }

    return win;
}

pub fn deinit(self: *@This()) void {
    _ = windows_and_messaging.DestroyWindow(self.handle);

    self.icon.deinit();
    self.cursor.deinit();

    // Unregister the class
    _ = windows_and_messaging.UnregisterClassW(self.class, self.instance);

    const parent = self.arena.child_allocator;
    self.arena.deinit();
    parent.destroy(self);
}

pub fn id(self: *const @This()) usize {
    return @intFromPtr(self.handle);
}

/// Returns the pointers to the parent (HINSTANCE) and
/// the target (HWND)
pub fn handles(self: *const @This()) Win.Handles {
    return .{
        .parent = @ptrCast(self.instance.?),
        .target = @ptrCast(self.handle),
    };
}

pub fn bringToTop(self: *const @This()) void {
    // Attempt to bring window to the top if it is rendered below other windows
    _ = windows_and_messaging.SetWindowPos(self.handle, null, 0, 0, 0, 0, .{ .NOMOVE = 1, .NOSIZE = 1 });
    _ = windows_and_messaging.SetForegroundWindow(self.handle);
    _ = windows_and_messaging.BringWindowToTop(self.handle);
}

pub fn visibility(self: *const @This()) Win.Visibility {
    if (self.fullscreen_state != null) return .fullscreen;

    var placement: windows_and_messaging.WINDOWPLACEMENT = undefined;
    placement.length = @sizeOf(windows_and_messaging.WINDOWPLACEMENT);

    if (windows_and_messaging.GetWindowPlacement(self.handle, &placement) != 0) {
        if (windows_and_messaging.IsWindowVisible(self.handle) == 0) return .hidden;
        if (placement.showCmd == windows_and_messaging.SW_MINIMIZE) return .minimize;
        if (placement.showCmd == windows_and_messaging.SW_MAXIMIZE) return .maximize;
        if (placement.showCmd == windows_and_messaging.SW_SHOWDEFAULT) return .restore;
    }

    return .restore;
}

pub fn show(self: *const @This()) void {
    showWindow(self.handle, .restore);
}

pub fn hide(self: *const @This()) void {
    showWindow(self.handle, .hidden);
}

/// Minimize the window
pub fn minimize(self: *const @This()) void {
    showWindow(self.handle, .minimize);
}

/// Maximize the window
pub fn maximize(self: *const @This()) void {
    showWindow(self.handle, .maximize);
}

/// Restore the window to its default windowed state
pub fn restore(self: *@This()) void {
    if (self.fullscreen_state) |old| {
        _ = windows_and_messaging.SetWindowLongW(self.handle, windows_and_messaging.GWL_STYLE, @bitCast(old.style));
        _ = windows_and_messaging.SetWindowLongW(self.handle, windows_and_messaging.GWL_EXSTYLE, @bitCast(old.ex_style));

        _ = windows_and_messaging.SetWindowPos(
            self.handle,
            null,
            old.client.left,
            old.client.top,
            old.client.right - old.client.left,
            old.client.bottom - old.client.top,
            windows_and_messaging.SET_WINDOW_POS_FLAGS{ .NOZORDER = 1, .NOACTIVATE = 1, .DRAWFRAME = 1 },
        );

        if (old.state == windows_and_messaging.SW_MAXIMIZE) {
            _ = windows_and_messaging.ShowWindow(self.handle, windows_and_messaging.SW_MAXIMIZE);
        }

        self.fullscreen_state = null;
    } else {
        showWindow(self.handle, .restore);
    }
}

/// Get the windows current rect (bounding box)
pub fn getRect(self: *const @This()) Rect(u32) {
    var rect = foundation.RECT{ .left = 0, .top = 0, .right = 0, .bottom = 0 };

    _ = windows_and_messaging.GetClientRect(self.handle, &rect);
    return .{
        .x = @intCast(rect.left),
        .y = @intCast(rect.top),
        .width = @intCast(rect.right -| rect.left),
        .height = @intCast(rect.bottom -| rect.top),
    };
}

/// Set window title
pub fn setTitle(self: *@This(), title: []const u8) !void {
    const allocator = self.arena.allocator();

    allocator.free(self.title);
    self.title = try util.utf8ToUtf16Alloc(allocator, title);
    _ = windows_and_messaging.SetWindowTextW(self.handle, self.title);
}

/// Set window icon
pub fn setIcon(self: *@This(), new_icon: ico.Icon) !void {
    const allocator = self.arena.allocator();

    self.icon.deinit();
    self.icon = try Icon.init(allocator, new_icon);

    // Send message to window to now render new icon
    _ = windows_and_messaging.SendMessageW(
        self.handle,
        windows_and_messaging.WM_SETICON,
        windows_and_messaging.ICON_SMALL,
        @intCast(@as(usize, @intFromPtr(self.icon.handle()))),
    );
    _ = windows_and_messaging.SendMessageW(
        self.handle,
        windows_and_messaging.WM_SETICON,
        windows_and_messaging.ICON_BIG,
        @intCast(@as(usize, @intFromPtr(self.icon.handle()))),
    );
}

/// Set window cursor
pub fn setCursor(self: *@This(), shape: ?csr.Cursor) !void {
    const allocator = self.arena.allocator();

    self.cursor.deinit();

    // Assign new cursor value/memory
    if (shape) |cs| {
        switch (cs) {
            .symbol => |i| self.cursor = .{ .system = windows_and_messaging.LoadCursorW(null, cursorToResource(i)) },
            .resource => |c| {
                const path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, c.path);
                defer allocator.free(path);

                self.cursor = .{
                    .resource = @ptrCast(windows_and_messaging.LoadImageW(
                        null,
                        path.ptr,
                        windows_and_messaging.IMAGE_ICON,
                        c.width,
                        c.height,
                        windows_and_messaging.IMAGE_FLAGS{
                            .DEFAULTSIZE = 1,
                            .LOADFROMFILE = 1,
                            .SHARED = 1,
                            .LOADTRANSPARENT = 1,
                        },
                    )),
                };
            },
        }
    } else {
        self.cursor = .{ .system = null };
    }

    // If the mouse is focused on the current window
    // update the cursor to the new value
    const currHandle = windows_and_messaging.GetForegroundWindow();
    if (currHandle) |hwnd| {
        if (hwnd == self.handle) {
            // Get HCURSOR pointer from icon
            _ = windows_and_messaging.SetCursor(self.cursor.handle());
        }
    }
}

/// Set the cursors position relative to the window
pub fn setCursorPos(self: *@This(), x: u32, y: u32) void {
    var point = foundation.POINT{
        .x = @intCast(x),
        .y = @intCast(y),
    };
    _ = gdi.ClientToScreen(self.handle, &point);
    _ = windows_and_messaging.SetCursorPos(point.x, point.y);
}

/// Get whether the mouse is captured by the current window
pub fn getCapture(self: *@This()) bool {
    if (keyboard_and_mouse.GetCapture(self.handle)) |target| {
        return target == self.handle;
    }
    return false;
}

/// Set the mouse to be captured by the window, or release it from the window
pub fn setCapture(self: *@This(), state: bool) void {
    if (state) {
        _ = keyboard_and_mouse.SetCapture(self.handle);
    } else {
        _ = keyboard_and_mouse.ReleaseCapture();
    }
}

/// Set or Unset the current window to be full screen.
pub fn fullscreen(self: *@This()) !void {
    if (self.fullscreen_state != null) return;

    var style: windows_and_messaging.WINDOW_STYLE = @bitCast(windows_and_messaging.GetWindowLongW(self.handle, windows_and_messaging.GWL_STYLE));
    var ex_style: windows_and_messaging.WINDOW_EX_STYLE = @bitCast(windows_and_messaging.GetWindowLongW(self.handle, windows_and_messaging.GWL_EXSTYLE));

    var rect: util.RECT = undefined;
    _ = windows_and_messaging.GetWindowRect(self.handle, &rect);

    var placement: windows_and_messaging.WINDOWPLACEMENT = undefined;
    placement.length = @sizeOf(windows_and_messaging.WINDOWPLACEMENT);
    _ = windows_and_messaging.GetWindowPlacement(self.handle, &placement);

    self.fullscreen_state = .{ .client = rect, .style = style, .ex_style = ex_style, .state = placement.showCmd };

    style.THICKFRAME = 0;
    style.DLGFRAME = 0;
    style.BORDER = 0;

    ex_style.DLGMODALFRAME = 0;
    ex_style.WINDOWEDGE = 0;
    ex_style.CLIENTEDGE = 0;
    ex_style.STATICEDGE = 0;

    _ = windows_and_messaging.ShowWindow(self.handle, windows_and_messaging.SW_RESTORE);
    _ = windows_and_messaging.SetWindowLongW(self.handle, windows_and_messaging.GWL_STYLE, @bitCast(style));
    _ = windows_and_messaging.SetWindowLongW(self.handle, windows_and_messaging.GWL_EXSTYLE, @bitCast(ex_style));
    var info: gdi.MONITORINFO = undefined;
    info.cbSize = @sizeOf(gdi.MONITORINFO);
    if (gdi.GetMonitorInfoW(gdi.MonitorFromWindow(self.handle, gdi.MONITOR_DEFAULTTONEAREST), &info) == zig.TRUE) {
        _ = windows_and_messaging.SetWindowPos(
            self.handle,
            windows_and_messaging.HWND_TOPMOST,
            info.rcMonitor.left,
            info.rcMonitor.top,
            info.rcMonitor.right - info.rcMonitor.left,
            info.rcMonitor.bottom - info.rcMonitor.top,
            windows_and_messaging.SET_WINDOW_POS_FLAGS{ .NOZORDER = 1, .NOACTIVATE = 1, .DRAWFRAME = 1 },
        );
    }
}

/// Get the current area that is used for rendering
pub fn getClientRect(self: *@This()) Rect(u32) {
    var area: util.RECT = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 };
    _ = windows_and_messaging.GetClientRect(self.handle, &area);

    const menuH = if (win32.ui.windows_and_messaging.GetMenu(self.handle)) |_|
        win32.ui.windows_and_messaging.GetSystemMetrics(win32.ui.windows_and_messaging.SM_CYMENU)
    else
        0;

    return .{
        .x = @as(u32, @bitCast(area.left)),
        .y = @as(u32, @bitCast(area.top + menuH)),
        .width = @as(u32, @bitCast(area.right - area.left)),
        .height = @as(u32, @bitCast(area.bottom - area.top)),
    };
}

pub fn setTheme(self: *@This(), theme: ?Win.Theme) void {
    if (theme == self.theme) return;
    self.theme = dark_mode.tryTheme(self.handle, theme, false);
}

pub fn getTheme(self: *@This()) Win.Theme {
    return self.theme;
}

fn showWindow(hwnd: ?foundation.HWND, state: Win.Visibility) void {
    if (hwnd) |h| {
        _ = windows_and_messaging.ShowWindow(h, switch (state) {
            .maximize => windows_and_messaging.SW_SHOWMAXIMIZED,
            .minimize => windows_and_messaging.SW_SHOWMINIMIZED,
            .restore => windows_and_messaging.SW_RESTORE,
            .hidden => windows_and_messaging.SW_HIDE,
            else => return,
        });
        _ = gdi.UpdateWindow(h);
    }
}

fn wndProc(
    hwnd: foundation.HWND,
    uMsg: u32,
    wparam: foundation.WPARAM,
    lparam: foundation.LPARAM,
) callconv(.winapi) foundation.LRESULT {
    if (uMsg == windows_and_messaging.WM_CREATE) {
        // Get CREATESTRUCTW pointer from lparam
        const lpptr: usize = @intCast(lparam);
        const create_struct: *windows_and_messaging.CREATESTRUCTA = @ptrFromInt(lpptr);

        // If lpCreateParams exists then assign window data/state
        if (create_struct.lpCreateParams) |create_params| {
            // Cast from anyopaque to an expected EventLoop
            // this includes casting the pointer alignment
            const event_loop: *EventLoop = @ptrCast(@alignCast(create_params));

            if (event_loop.windows.get(@intFromPtr(hwnd))) |win| {
                if (win.acrylic) {
                    util.applyLegacyBlur(hwnd);
                    _ = gdi.InvalidateRect(hwnd, null, zig.FALSE);
                }
            }

            // Cast pointer to isize for setting data
            const long_ptr: usize = @intFromPtr(event_loop);
            const ptr: isize = @intCast(long_ptr);
            _ = windows_and_messaging.SetWindowLongPtrW(hwnd, windows_and_messaging.GWLP_USERDATA, ptr);
        }
    } else {
        // Get window state/data pointer
        const ptr = windows_and_messaging.GetWindowLongPtrW(hwnd, windows_and_messaging.GWLP_USERDATA);
        // Cast int to optional EventLoop pointer
        const lptr: usize = @intCast(ptr);
        const event_loop: ?*EventLoop = @ptrFromInt(lptr);

        if (event_loop) |loop| {
            // TODO: Return failure
            if (!loop.handleEvent(.{ hwnd, uMsg, wparam, lparam })) {
                return windows_and_messaging.DefWindowProcW(hwnd, uMsg, wparam, lparam);
            }
        } else {
            switch (uMsg) {
                windows_and_messaging.WM_DESTROY => {
                    windows_and_messaging.PostQuitMessage(0);
                },
                else => return windows_and_messaging.DefWindowProcW(hwnd, uMsg, wparam, lparam),
            }
        }
    }

    return 0;
}
