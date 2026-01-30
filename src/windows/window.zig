// TODO: Do owner drawn menu bar so that the background and text colors can match the caption/title bar

const std = @import("std");

const TaskBar = @import("taskbar.zig");

const Rect = @import("../root.zig").Rect;

const dnd = @import("../drag_drop.zig");
const dnd_win = @import("drag_drop.zig");

const _menu = @import("../menu.zig");
const MenuInfo = _menu.Info;
const MenuItem = _menu.Item;
const MenuCheckable = _menu.Checkable;
const MenuAction = _menu.Action;

const windows = @import("windows");
const win32 = windows.win32;

const UISettings = windows.UI.ViewManagement.UISettings;

const ole = win32.system.ole;
const foundation = win32.foundation;
const windows_and_messaging = win32.ui.windows_and_messaging;
const keyboard_and_mouse = win32.ui.input.keyboard_and_mouse;
const library_loader = win32.system.library_loader;
const gdi = win32.graphics.gdi;
const zig = win32.zig;
const shell = win32.ui.shell;
const dwm = win32.graphics.dwm;

const util = @import("util.zig");
const cursorToResource = @import("cursor.zig").cursorToResource;
const iconToResource = @import("icon.zig").iconToResource;

const ico = @import("../icon.zig");
const csr = @import("../cursor.zig");
const IconType = ico.IconType;
const CursorType = @import("../cursor.zig").CursorType;
const Win = @import("../window.zig");
const EventLoop = @import("../event.zig").EventLoop;

const DestroyIcon = windows_and_messaging.DestroyIcon;
const DestroyCursor = windows_and_messaging.DestroyCursor;
const DestroyMenu = windows_and_messaging.DestroyMenu;

const Shell_NotifyIconW = shell.Shell_NotifyIconW;
const NIM_ADD = shell.NIM_ADD;
const NIM_MODIFY = shell.NIM_MODIFY;
const NIM_DELETE = shell.NIM_DELETE;
const NIM_SETVERSION = shell.NIM_SETVERSION;
const NOTIFYICON_VERSION_4 = shell.NOTIFYICON_VERSION_4;

const NOTIFYICONDATAW = shell.NOTIFYICONDATAW;
const HICON = windows_and_messaging.HICON;
const HCURSOR = windows_and_messaging.HCURSOR;
const HWND = foundation.HWND;
const HMENU = windows_and_messaging.HMENU;

const ID_TRAY = 1001;

const Icon = union(enum) {
    icon: IconType,
    custom: HICON,
};

const Cursor = union(enum) {
    icon: CursorType,
    custom: struct {
        handle: HCURSOR,
        width: i32,
        height: i32,
    },
};

pub const MenuContext = struct {
    allocator: std.mem.Allocator,
    count: *usize,
    current: HMENU,
    menus: *std.ArrayListUnmanaged(HMENU),
    itemToMenu: *std.AutoArrayHashMapUnmanaged(usize, MenuInfo),

    pub fn sub(self: *@This(), inner: HMENU) @This() {
        return .{
            .allocator = self.allocator,
            .count = self.count,
            .menus = self.menus,
            .itemToMenu = self.itemToMenu,
            .current = inner,
        };
    }

    pub fn appendSeparator(self: *@This()) !void {
        if (windows_and_messaging.AppendMenuA(self.current, windows_and_messaging.MF_SEPARATOR, 0, null) == 0) {
            return error.AppendMenuSeparator;
        }
    }

    pub fn appendAction(self: *@This(), action: MenuAction) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, action.label.len, 0);
        @memcpy(label, action.label);
        try self.itemToMenu.put(self.allocator, self.count.*, .{
            .id = action.id,
            .menu = @ptrCast(self.current),
            .payload = .{ .action = .{ .label = label } },
        });
        if (windows_and_messaging.AppendMenuA(self.current, windows_and_messaging.MF_STRING, self.count.*, label.ptr) == 0) {
            return error.AppendMenuAction;
        }
    }

    pub fn appendToggle(self: *@This(), checkable: MenuCheckable) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, checkable.label.len, 0);
        @memcpy(label, checkable.label);
        try self.itemToMenu.put(self.allocator, self.count.*, .{
            .id = checkable.id,
            .menu = @ptrCast(self.current),
            .payload = .{
                .toggle = .{ .label = label },
            },
        });
        if (windows_and_messaging.AppendMenuA(
            self.current,
            if (checkable.default) windows_and_messaging.MF_CHECKED else windows_and_messaging.MF_UNCHECKED,
            self.count.*,
            label.ptr,
        ) == 0) {
            return error.AppendMenuToggle;
        }
    }

    pub fn appendRadioGroup(self: *@This(), items: []const MenuCheckable) !void {
        const start = self.count.* + 1;
        const end = start + items.len;

        for (items) |item| {
            try self.appendRadioItem(item, start, end);
        }
    }

    pub fn appendRadioItem(self: *@This(), checkable: MenuCheckable, start: usize, end: usize) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, checkable.label.len, 0);
        @memcpy(label, checkable.label);
        try self.itemToMenu.put(self.allocator, self.count.*, .{
            .id = checkable.id,
            .menu = @ptrCast(self.current),
            .payload = .{
                .radio = .{
                    .group = .{ start, end },
                    .label = label,
                },
            },
        });
        if (windows_and_messaging.AppendMenuA(
            self.current,
            if (checkable.default) windows_and_messaging.MF_CHECKED else windows_and_messaging.MF_UNCHECKED,
            self.count.*,
            label.ptr,
        ) == 0) {
            return error.AppendMenuRadioItem;
        }
    }

    pub fn appendMenu(self: *@This(), items: []const MenuItem) !void {
        for (items) |item| {
            switch (item) {
                .separator => try self.appendSeparator(),
                .action_item => |action| try self.appendAction(action),
                .toggle_item => |toggle| try self.appendToggle(toggle),
                .radio_group_item => |group| try self.appendRadioGroup(group),
                .menu_item => |subMenu| {
                    const innerMenu = windows_and_messaging.CreatePopupMenu().?;
                    try self.menus.append(self.allocator, innerMenu);
                    if (windows_and_messaging.AppendMenuA(
                        self.current,
                        windows_and_messaging.MF_POPUP,
                        @intFromPtr(innerMenu),
                        subMenu.label.ptr,
                    ) == 0) {
                        return error.AppendMenuSubmenu;
                    }

                    var inner = self.sub(innerMenu);
                    try inner.appendMenu(subMenu.items);
                },
            }
        }
    }
};

arena: std.heap.ArenaAllocator,

title: [:0]const u16 = undefined,
class: [:0]const u16 = undefined,

handle: foundation.HWND = undefined,
instance: ?foundation.HINSTANCE = null,

// TODO: Destroy the custom icon and cursor
icon: Icon = .{ .icon = .default },
cursor: Cursor = .{ .icon = .default },

theme: Win.Theme = .system,
current_theme: Win.Theme = .dark,

menus: std.ArrayListUnmanaged(HMENU) = .empty,
item_to_menubar: std.AutoArrayHashMapUnmanaged(usize, MenuInfo) = .empty,

system_tray: ?struct {
    tip: [:0]const u16,
    popup: ?HMENU = null,
    onclick: ?SystemTrayOnClick = null,
} = null,
systray_menus: std.ArrayListUnmanaged(HMENU) = .empty,
item_to_systray: std.AutoArrayHashMapUnmanaged(usize, MenuInfo) = .empty,

fullscreen_state: ?struct {
    client: util.RECT,
    style: windows_and_messaging.WINDOW_STYLE,
    ex_style: windows_and_messaging.WINDOW_EX_STYLE,
    state: windows_and_messaging.SHOW_WINDOW_CMD,
} = null,

drag_drop: ?dnd.DropTarget = null,
drag_drop_handler: ?*dnd_win.DropTargetHandler = null,

taskbar: TaskBar = undefined,

/// Reference to the event loops UISettings instance
ui_settings: *UISettings,

/// Create a new window
///
/// - @param `allocator` Allocates the wide strings for the window. Must live longer than the window
/// - @param `event_loop` Event handler and driver for the window
/// - @param `options` Options on how the window should look and behave when it is created
///
/// @returns `Window` An instance of a window. Contains methods to manipulate the window.
pub fn init(
    allocator: std.mem.Allocator,
    event_loop: *EventLoop,
    options: Win.Options,
) !*@This() {
    const win = try allocator.create(@This());
    errdefer allocator.destroy(win);

    win.* = .{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .ui_settings = event_loop.ui_settings,
    };
    const allo = win.arena.allocator();

    win.title = try util.utf8ToUtf16Alloc(allo, options.title);
    errdefer allo.free(win.title);
    win.class = try util.createUIDClass(allo);
    errdefer allo.free(win.class);

    win.instance = library_loader.GetModuleHandleW(null);
    const wnd_class = windows_and_messaging.WNDCLASSW{
        .lpszClassName = win.class.ptr,

        .style = windows_and_messaging.WNDCLASS_STYLES{ .HREDRAW = 1, .VREDRAW = 1 },
        .cbClsExtra = 0,
        .cbWndExtra = 0,

        .hIcon = null,
        .hCursor = null,
        .hbrBackground = gdi.GetStockObject(gdi.WHITE_BRUSH),
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
        windows_and_messaging.WINDOW_EX_STYLE{},
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

    var value: foundation.BOOL = zig.TRUE;
    win.current_theme = .dark;
    switch (options.theme) {
        .light => {
            value = zig.FALSE;
            win.current_theme = .light;
        },
        .system => if (util.isLight(try win.ui_settings.GetColorValue(.Foreground))) {
            win.current_theme = .light;
            value = zig.FALSE;
        } else {},
        else => {},
    }

    _ = dwm.DwmSetWindowAttribute(win.handle, dwm.DWMWA_USE_IMMERSIVE_DARK_MODE, &value, @sizeOf(foundation.BOOL));
    _ = windows_and_messaging.ShowWindow(win.handle, switch (options.show) {
        .hidden => windows_and_messaging.SW_HIDE,
        .minimize => windows_and_messaging.SW_MINIMIZE,
        .maximize => windows_and_messaging.SW_MAXIMIZE,
        else => windows_and_messaging.SW_SHOWDEFAULT,
    });
    _ = gdi.UpdateWindow(win.handle);

    win.icon = .{ .icon = .default };
    win.cursor = .{ .icon = .default };
    win.theme = options.theme;

    try win.setCursor(options.cursor);
    try win.setIcon(options.icon);

    win.taskbar = try TaskBar.init(win.handle);

    if (options.show == .fullscreen) {
        win.fullscreen() catch {};
        _ = win.taskbar.markFullscreen(win.handle, true);
    }

    return win;
}

pub fn deinit(self: *@This()) void {
    _ = windows_and_messaging.DestroyWindow(self.handle);

    // Revoke and free drag and drop target handler
    if (self.drag_drop_handler) |h| {
        _ = ole.RevokeDragDrop(self.handle);
        h.deinit();
    }

    // Destroy allocated icon handle
    if (self.icon == .custom) {
        _ = DestroyIcon(self.icon.custom);
    }

    // Destroy allocated cursor handle
    if (self.cursor == .custom) {
        _ = DestroyCursor(self.cursor.custom.handle);
    }

    self.taskbar.deinit(self.arena.allocator());

    // Free allocated menu bar memory
    for (self.menus.items) |m| _ = windows_and_messaging.DestroyMenu(m);

    // Unregister the class
    _ = windows_and_messaging.UnregisterClassW(self.class, self.instance);

    const parent = self.arena.child_allocator;
    self.arena.deinit();
    parent.destroy(self);
}

pub fn setJumpList(self: *@This(), list: TaskBar.JumpList) !void {
    try self.taskbar.setJumpList(self.arena.allocator(), list);
}

pub fn setThumbBar(self: *@This(), buttons: []const TaskBar.Button) !void {
    try self.taskbar.addButtons(self.arena.allocator(), buttons);
}

pub fn setTaskbarProgress(self: *@This(), state: TaskBar.TBPFLAG, completed: u64, total: u64) !void {
    try self.taskbar.setProgress(state, completed, total);
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

        _ = self.taskbar.markFullscreen(self.handle, false);
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

    // Free old icon memory
    switch (self.icon) {
        .custom => |handle| _ = DestroyIcon(handle),
        else => {},
    }

    // Assign new icon value/memory
    switch (new_icon) {
        .icon => |i| self.icon = .{ .icon = i },
        .custom => |c| {
            const path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, c);
            defer allocator.free(path);

            self.icon = .{
                .custom = @ptrCast(windows_and_messaging.LoadImageW(
                    null,
                    path.ptr,
                    windows_and_messaging.IMAGE_ICON,
                    0,
                    0,
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

    const hIcon = getHIcon(self.icon);

    // Send message to window to now render new icon
    _ = windows_and_messaging.SendMessageW(
        self.handle,
        windows_and_messaging.WM_SETICON,
        windows_and_messaging.ICON_SMALL,
        @intCast(@as(usize, @intFromPtr(hIcon))),
    );
    _ = windows_and_messaging.SendMessageW(
        self.handle,
        windows_and_messaging.WM_SETICON,
        windows_and_messaging.ICON_BIG,
        @intCast(@as(usize, @intFromPtr(hIcon))),
    );

    // Update system tray to use new icon
    if (self.system_tray) |tray| {
        var nid = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = self.handle;
        nid.uID = ID_TRAY;
        nid.uFlags = .{ .MESSAGE = 1, .ICON = 1, .TIP = 1, .SHOWTIP = 1 };
        nid.hIcon = hIcon;

        const tip_len = @min(tray.tip.len, nid.szTip.len);
        @memcpy(nid.szTip[0..tip_len], tray.tip[0..tip_len]);
        nid.szTip[tip_len] = 0;

        _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
    }
}

/// Set window cursor
pub fn setCursor(self: *@This(), new_cursor: csr.Cursor) !void {
    const allocator = self.arena.allocator();

    // Free old cursor memory
    switch (self.cursor) {
        .custom => |c| _ = DestroyCursor(c.handle),
        else => {},
    }

    // Assign new cursor value/memory
    switch (new_cursor) {
        .icon => |i| self.cursor = .{ .icon = i },
        .custom => |c| {
            const path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, c.path);
            defer allocator.free(path);

            self.cursor = .{
                .custom = .{
                    .width = c.width,
                    .height = c.height,
                    .handle = @ptrCast(windows_and_messaging.LoadImageW(
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
                },
            };
        },
    }

    // If the mouse is focused on the current window
    // update the cursor to the new value
    const currHandle = windows_and_messaging.GetForegroundWindow();
    if (currHandle) |hwnd| {
        if (hwnd == self.handle) {
            // Get HCURSOR pointer from icon
            _ = windows_and_messaging.SetCursor(getHCursor(self.cursor));
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

    _ = self.taskbar.markFullscreen(self.handle, true);
}

/// Get the current area that is used for rendering
pub fn getClientRect(self: *@This()) Rect(u32) {
    var area: util.RECT = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 };
    _ = windows_and_messaging.GetClientRect(self.handle, &area);
    return .{
        .x = @as(u32, @bitCast(area.left)),
        .y = @as(u32, @bitCast(area.top)),
        .width = @as(u32, @bitCast(area.right - area.left)),
        .height = @as(u32, @bitCast(area.bottom - area.top)),
    };
}

pub fn setTheme(self: *@This(), theme: Win.Theme) void {
    if (theme == self.theme) return;
    self.theme = theme;

    self.setCurrentTheme(theme);
}

pub fn setCurrentTheme(self: *@This(), theme: Win.Theme) void {
    if (theme == self.current_theme) return;
    switch (theme) {
        .light => {
            self.current_theme = .light;
            _ = dwm.DwmSetWindowAttribute(self.handle, dwm.DWMWA_USE_IMMERSIVE_DARK_MODE, &zig.FALSE, @sizeOf(foundation.BOOL));
        },
        .dark => {
            self.current_theme = .dark;
            _ = dwm.DwmSetWindowAttribute(self.handle, dwm.DWMWA_USE_IMMERSIVE_DARK_MODE, &zig.TRUE, @sizeOf(foundation.BOOL));
        },
        .system => if (self.ui_settings.GetColorValue(.Foreground)) |color| {
            if (util.isLight(color)) {
                self.current_theme = .light;
                _ = dwm.DwmSetWindowAttribute(self.handle, dwm.DWMWA_USE_IMMERSIVE_DARK_MODE, &zig.FALSE, @sizeOf(foundation.BOOL));
            } else {
                self.current_theme = .dark;
                _ = dwm.DwmSetWindowAttribute(self.handle, dwm.DWMWA_USE_IMMERSIVE_DARK_MODE, &zig.TRUE, @sizeOf(foundation.BOOL));
            }
        } else |_| {},
    }
}

pub fn setMenu(self: *@This(), new_menu: ?[]const MenuItem) !void {
    const allocator = self.arena.allocator();

    for (self.menus.items) |m| _ = windows_and_messaging.DestroyMenu(m);
    for (self.item_to_menubar.values()) |v| switch (v.payload) {
        .toggle => |t| allocator.free(t.label),
        .action => |a| allocator.free(a.label),
        .radio => |r| allocator.free(r.label),
    };
    self.menus.clearAndFree(allocator);
    self.item_to_menubar.clearAndFree(allocator);

    var rootMenu: ?HMENU = null;
    if (new_menu) |userMenu| {
        if (userMenu.len > 0) {
            rootMenu = windows_and_messaging.CreateMenu().?;
            try self.menus.append(allocator, rootMenu.?);

            var count: usize = 0;
            var context = MenuContext{
                .allocator = allocator,
                .current = rootMenu.?,
                .menus = &self.menus,
                .itemToMenu = &self.item_to_menubar,
                .count = &count,
            };

            try context.appendMenu(userMenu);

            _ = windows_and_messaging.SetMenu(self.handle, rootMenu);
            _ = windows_and_messaging.DrawMenuBar(self.handle);
            return;
        }
    }
    _ = windows_and_messaging.SetMenu(self.handle, null);
    _ = windows_and_messaging.DrawMenuBar(self.handle);
}

pub fn getCurrentTheme(self: *@This()) Win.Theme {
    return self.current_theme;
}

pub fn getTheme(self: *@This()) Win.Theme {
    return self.theme;
}

pub fn getHCursor(cursor: Cursor) ?windows_and_messaging.HCURSOR {
    return switch (cursor) {
        .icon => |i| windows_and_messaging.LoadCursorW(null, cursorToResource(i)),
        .custom => |c| c.handle,
    };
}

pub fn showSystemTray(self: *@This()) u32 {
    if (self.system_tray) |tray| {
        if (tray.popup) |popup| {
            var pt: win32.foundation.POINT = undefined;
            _ = windows_and_messaging.GetCursorPos(&pt);

            _ = windows_and_messaging.SetForegroundWindow(self.handle);
            const selected = windows_and_messaging.TrackPopupMenu(
                popup,
                .{ .RIGHTBUTTON = 1, .RETURNCMD = 1 },
                pt.x,
                pt.y,
                0,
                self.handle,
                null,
            );
            _ = windows_and_messaging.PostMessageW(self.handle, windows_and_messaging.WM_NULL, 0, 0);
            return @as(u32, @bitCast(selected));
        }
    }
    return 0;
}
pub fn systemTrayOnClick(self: *const @This(), event_loop: *EventLoop, window: *@This()) void {
    if (self.system_tray) |tray| {
        if (tray.onclick) |onclick| {
            onclick(event_loop, window);
        }
    }
}

const SystemTrayOnClick = *const fn (event_loop: *EventLoop, window: *@This()) void;
pub fn setSystemTray(self: *@This(), tip: []const u8, onclick: ?SystemTrayOnClick, new_menu: ?[]const MenuItem) !void {
    const allocator = self.arena.allocator();

    if (new_menu) |new| {
        if (self.system_tray) |*tray| {
            allocator.free(tray.tip);
            // TODO: Release other allocated resources

            var nid = std.mem.zeroes(NOTIFYICONDATAW);
            nid.cbSize = @sizeOf(NOTIFYICONDATAW);
            nid.hWnd = self.handle;
            nid.uID = ID_TRAY;
            nid.uFlags = .{ .MESSAGE = 1, .ICON = 1, .TIP = 1, .SHOWTIP = 1 };

            const tip_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, tip);
            self.system_tray.?.tip = tip_w;

            const tip_len = @min(tip_w.len, nid.szTip.len);
            @memcpy(nid.szTip[0..tip_len], tip_w[0..tip_len]);
            nid.szTip[tip_len] = 0;

            _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
        } else {
            var nid = std.mem.zeroes(NOTIFYICONDATAW);
            nid.cbSize = @sizeOf(NOTIFYICONDATAW);
            nid.hWnd = self.handle;
            nid.uID = ID_TRAY;
            nid.uCallbackMessage = windows_and_messaging.WM_USER + 1;
            nid.uFlags = .{ .MESSAGE = 1, .ICON = 1, .TIP = 1, .SHOWTIP = 1 };
            nid.hIcon = getHIcon(self.icon);

            const tip_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, tip);
            self.system_tray = .{ .tip = tip_w };

            const tip_len = @min(tip_w.len, nid.szTip.len);
            @memcpy(nid.szTip[0..tip_len], tip_w[0..tip_len]);
            nid.szTip[tip_len] = 0;

            _ = Shell_NotifyIconW(NIM_ADD, &nid);
            nid.Anonymous.uVersion = NOTIFYICON_VERSION_4;
            _ = Shell_NotifyIconW(NIM_SETVERSION, &nid);
        }

        self.system_tray.?.onclick = onclick;

        for (self.systray_menus.items) |m| _ = windows_and_messaging.DestroyMenu(m);
        for (self.item_to_systray.values()) |v| switch (v.payload) {
            .toggle => |t| allocator.free(t.label),
            .action => |a| allocator.free(a.label),
            .radio => |r| allocator.free(r.label),
        };
        self.menus.clearAndFree(allocator);
        self.item_to_menubar.clearAndFree(allocator);

        var root_menu: ?HMENU = undefined;
        if (new.len > 0) {
            root_menu = windows_and_messaging.CreatePopupMenu().?;
            self.system_tray.?.popup = root_menu;
            try self.menus.append(allocator, root_menu.?);

            var count: usize = 0;
            var context = MenuContext{
                .allocator = allocator,
                .current = root_menu.?,
                .menus = &self.systray_menus,
                .itemToMenu = &self.item_to_systray,
                .count = &count,
            };

            try context.appendMenu(new);
        }
    } else if (self.system_tray) |tray| {
        allocator.free(tray.tip);

        var nid = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = self.handle;
        nid.uID = ID_TRAY;
        _ = Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}

pub fn setDragDrop(self: *@This(), context: ?dnd.DropTarget.Context) !void {
    const allocator = self.arena.allocator();

    if (self.drag_drop_handler) |handler| {
        handler.deinit();
        self.drag_drop = null;
        const hr = ole.RevokeDragDrop(self.handle);
        if (hr != 0) try windows.core.hresultToError(hr);
        ole.OleUninitialize();
    }

    if (context) |ctx| {
        var hr = ole.OleInitialize(null);
        if (hr != 0) try windows.core.hresultToError(hr);

        self.drag_drop = dnd.DropTarget.init(allocator, ctx);
        self.drag_drop_handler = try dnd_win.DropTargetHandler.init(self.handle, &self.drag_drop.?);
        errdefer self.drag_drop_handler.?.deinit();

        hr = ole.RegisterDragDrop(self.handle, @ptrCast(self.drag_drop_handler.?));
        if (hr != 0) try windows.core.hresultToError(hr);
    }
}

fn getHIcon(icon: Icon) ?windows_and_messaging.HICON {
    return switch (icon) {
        .icon => |i| windows_and_messaging.LoadIconW(null, iconToResource(i)),
        .custom => |c| c,
    };
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
