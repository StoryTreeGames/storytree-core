const std = @import("std");
const windows = @import("windows");
const win32 = windows.win32;

const HRESULT = win32.foundation.HRESULT;
const RECT = win32.foundation.RECT;
const BOOL = win32.foundation.BOOL;
const HWND = win32.foundation.HWND;
const HICON = win32.ui.windows_and_messaging.HICON;
const CoInitializeEx = win32.system.com.CoInitializeEx;
const CoCreateInstance = win32.system.com.CoCreateInstance;
const CoUninitialize = win32.system.com.CoUninitialize;
const COINIT_APARTMENTTHREADED = win32.system.com.COINIT_APARTMENTTHREADED;
const CLSCTX_INPROC_SERVER = win32.system.com.CLSCTX_INPROC_SERVER;
const LR_SHARED = win32.ui.windows_and_messaging.LR_SHARED;

const shobjidl = @cImport({
    @cInclude("shobjidl.h");
});

const HIMAGELIST = shobjidl.HIMAGELIST;

fn ok(hr: HRESULT) bool {
    return hr >= 0;
}

const ButtonBaseId = 40000;
const BTN_PLAY = ButtonBaseId + 0;
const BTN_PAUSE = ButtonBaseId + 1;
const BTN_STOP = ButtonBaseId + 2;

pub const THUMBBUTTONMASK = packed struct(u32) {
    BITMAP: u1 = 0,
    ICON: u1 = 0,
    TOOLTIP: u1 = 0,
    FLAGS: u1 = 0,
    _: u28 = 0,
};

pub const THUMBBUTTONFLAGS = packed struct(u32) {
    DISABLED: u1 = 0,
    DISMISSONCLICK: u1 = 0,
    NOBACKGROUND: u1 = 0,
    HIDDEN: u1 = 0,
    NONINTERACTIVE: u1 = 0,
    _: u27 = 0,
};

pub const THUMBBUTTON = extern struct {
    dwMask: THUMBBUTTONMASK = .{},
    iId: u32 = 0,
    iBitmap: u32 = 0,
    hIcon: ?HICON = null,
    szTip: [260]u16 = @import("std").mem.zeroes([260]u16),
    dwFlags: THUMBBUTTONFLAGS = .{},
};

pub const TBPFLAG = enum(i32) {
    NOPROGRESS = 0,
    INDETERMINATE = 1,
    NORMAL = 2,
    ERROR = 4,
    PAUSED = 8,
};

pub const CLSID_TaskbarList = windows.Guid.initString("56FDF344-FD6D-11D0-958A-006097C9A090");

pub const ITaskbarList3 = extern struct {
    vtable: *VTable,

    pub const IID: windows.Guid = windows.Guid.initString("EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF");
    pub const VTable = extern struct {
        QueryInterface: *const fn (*ITaskbarList3, *const windows.Guid, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*ITaskbarList3) callconv(.c) u32,
        Release: *const fn (*ITaskbarList3) callconv(.c) u32,
        HrInit: *const fn (*ITaskbarList3) callconv(.c) HRESULT,
        AddTab: *const fn (*ITaskbarList3, HWND) callconv(.c) HRESULT,
        DeleteTab: *const fn (*ITaskbarList3, HWND) callconv(.c) HRESULT,
        ActivateTab: *const fn (*ITaskbarList3, HWND) callconv(.c) HRESULT,
        SetActiveAlt: *const fn (*ITaskbarList3, HWND) callconv(.c) HRESULT,
        MarkFullscreenWindow: *const fn (*ITaskbarList3, HWND, BOOL) callconv(.c) HRESULT,
        SetProgressValue: *const fn (*ITaskbarList3, HWND, u64, u64) callconv(.c) HRESULT,
        SetProgressState: *const fn (*ITaskbarList3, HWND, TBPFLAG) callconv(.c) HRESULT,
        RegisterTab: *const fn (*ITaskbarList3, HWND, HWND) callconv(.c) HRESULT,
        UnregisterTab: *const fn (*ITaskbarList3, HWND) callconv(.c) HRESULT,
        SetTabOrder: *const fn (*ITaskbarList3, HWND, HWND) callconv(.c) HRESULT,
        SetTabActive: *const fn (*ITaskbarList3, HWND, HWND, u32) callconv(.c) HRESULT,
        ThumbBarAddButtons: *const fn (*ITaskbarList3, HWND, u32, [*]const THUMBBUTTON) callconv(.c) HRESULT,
        ThumbBarUpdateButtons: *const fn (*ITaskbarList3, HWND, u32, [*]const THUMBBUTTON) callconv(.c) HRESULT,
        ThumbBarSetImageList: *const fn (*ITaskbarList3, HWND, HIMAGELIST) callconv(.c) HRESULT,
        SetOverlayIcon: *const fn (*ITaskbarList3, HWND, HICON, [*:0]const u16) callconv(.c) HRESULT,
        SetThumbnailTooltip: *const fn (*ITaskbarList3, HWND, [*:0]const u16) callconv(.c) HRESULT,
        SetThumbnailClip: *const fn (*ITaskbarList3, HWND, *RECT) callconv(.c) HRESULT,
    };

    pub fn markFullscreenWindow(self: *@This(), hwnd: HWND, state: bool) HRESULT {
        return self.vtable.MarkFullscreenWindow(self, hwnd, if (state) win32.zig.TRUE else win32.zig.FALSE);
    }

    pub fn setProgressValue(self: *@This(), hwnd: HWND, completed: u64, total: u64) HRESULT {
        return self.vtable.SetProgressValue(self, hwnd, completed, total);
    }

    pub fn setProgressState(self: *@This(), hwnd: HWND, flags: TBPFLAG) HRESULT {
        return self.vtable.SetProgressState(self, hwnd, flags);
    }

    pub fn release(self: *@This()) u32 {
        return self.vtable.Release(self);
    }

    pub fn hrInit(self: *@This()) HRESULT {
        return self.vtable.HrInit(self);
    }

    pub fn setImages(self: *@This(), hwnd: HWND, image_list: HIMAGELIST) HRESULT {
        return self.vtable.ThumbBarSetImageList(self, hwnd, image_list);
    }

    pub fn addButtons(self: *@This(), hwnd: HWND, buttons: []const THUMBBUTTON) HRESULT {
        return self.vtable.ThumbBarAddButtons(self, hwnd, @intCast(buttons.len), buttons.ptr);
    }

    pub fn updateButtons(self: *@This(), hwnd: HWND, buttons: []const THUMBBUTTON) HRESULT {
        return self.vtable.ThumbBarUpdateButtons(self, hwnd, @intCast(buttons.len), buttons.ptr);
    }
};

const ImageList = struct {
    handle: HIMAGELIST,
    pub fn create(capacity: u32) !@This() {
        return .{
            .handle = shobjidl.ImageList_Create(
                16,
                16,
                shobjidl.ILC_COLOR32,
                @intCast(capacity),
                1,
            ) orelse return error.ImageListCreate,
        };
    }

    pub fn destroy(self: *@This()) bool {
        return 1 == shobjidl.ImageList_Destroy(self.handle);
    }

    pub fn count(self: *@This()) u32 {
        return @intCast(shobjidl.ImageList_GetImageCount(self.handle));
    }

    pub fn resize(self: *@This(), size: u32) bool {
        return 1 == shobjidl.ImageList_SetImageCount(self.handle, @intCast(size));
    }

    pub fn add(self: *@This(), bitmap: shobjidl.HBITMAP, mask: shobjidl.HBITMAP) i32 {
        return @intCast(shobjidl.ImageList_Add(self.handle, bitmap, mask));
    }

    pub fn replace(self: *@This(), index: i32, bitmap: shobjidl.HBITMAP, mask: shobjidl.HBITMAP) bool {
        return 1 == shobjidl.ImageList_Replace(self.handle, @intCast(index), bitmap, mask);
    }

    extern "comctl32" fn ImageList_ReplaceIcon(list: HIMAGELIST, i: i32, hicon: HICON) i32;
    pub fn replaceIcon(self: *@This(), i: i32, icon: HICON) i32 {
        return @intCast(ImageList_ReplaceIcon(self.handle, @intCast(i), icon));
    }

    pub fn remove(self: *@This(), index: u32) bool {
        return 1 == shobjidl.ImageList_Remove(self.handle, @intCast(index));
    }

    // pub extern fn ImageList_SetBkColor(himl: HIMAGELIST, clrBk: COLORREF) COLORREF;
    pub fn setBkColor(self: *@This(), clrBk: shobjidl.COLORREF) shobjidl.COLORREF {
        return shobjidl.ImageList_SetBkColor(self.handle, clrBk);
    }

    // pub extern fn ImageList_GetIcon(himl: HIMAGELIST, i: c_int, flags: UINT) HICON;
    // pub extern fn ImageList_LoadImageW(hi: HINSTANCE, lpbmp: LPCWSTR, cx: c_int, cGrow: c_int, crMask: COLORREF, uType: UINT, uFlags: UINT) HIMAGELIST;
    // pub extern fn ImageList_SetBkColor(himl: HIMAGELIST, clrBk: COLORREF) COLORREF;
    // pub extern fn ImageList_GetBkColor(himl: HIMAGELIST) COLORREF;
    // pub extern fn ImageList_SetOverlayImage(himl: HIMAGELIST, iImage: c_int, iOverlay: c_int) WINBOOL;
    // pub extern fn ImageList_Draw(himl: HIMAGELIST, i: c_int, hdcDst: HDC, x: c_int, y: c_int, fStyle: UINT) WINBOOL;
    // pub extern fn ImageList_AddMasked(himl: HIMAGELIST, hbmImage: HBITMAP, crMask: COLORREF) c_int;
    // pub extern fn ImageList_DrawEx(himl: HIMAGELIST, i: c_int, hdcDst: HDC, x: c_int, y: c_int, dx: c_int, dy: c_int, rgbBk: COLORREF, rgbFg: COLORREF, fStyle: UINT) WINBOOL;
    // pub extern fn ImageList_DrawIndirect(pimldp: [*c]IMAGELISTDRAWPARAMS) WINBOOL;
};

pub const Button = struct {
    icon: Icon,
    tooltip: ?[]const u8 = null,

    background: bool = true,
    dismiss_on_click: bool = false,
    disabled: bool = false,
    hidden: bool = false,

    pub const Flags = struct {
        background: ?bool = null,
        dismiss_on_click: ?bool = null,
        disabled: ?bool = null,
        hidden: ?bool = null,
    };

    pub const FlagState = struct {
        background: bool,
        dismiss_on_click: bool,
        disabled: bool,
        hidden: bool,
    };
};

pub const Icon = union(enum) {
    icon: Symbol,
    custom: []const u8,

    pub fn getHIcon(self: @This()) ?HICON {
        switch (self) {
            .custom => |path| {
                // Buffer of longest allowed windows path
                var buffer: [260:0]u16 = std.mem.zeroes([260:0]u16);
                _ = std.unicode.utf8ToUtf16Le(&buffer, path) catch 0;
                return @ptrCast(win32.ui.windows_and_messaging.LoadImageW(
                    null,
                    &buffer,
                    .ICON,
                    16,
                    16,
                    .{ .LOADFROMFILE = 1, .LOADTRANSPARENT = 1 },
                ));
            },
            .icon => |symbol| {
                const path = switch (symbol) {
                    .application => win32.ui.windows_and_messaging.IDI_APPLICATION,
                    .hand => win32.ui.windows_and_messaging.IDI_HAND,
                    .question => win32.ui.windows_and_messaging.IDI_QUESTION,
                    .exclamation => win32.ui.windows_and_messaging.IDI_EXCLAMATION,
                    .asterisk => win32.ui.windows_and_messaging.IDI_ASTERISK,
                    .winlogo => win32.ui.windows_and_messaging.IDI_WINLOGO,
                    .shield => win32.ui.windows_and_messaging.IDI_SHIELD,
                    .warning => @as([*:0]align(1) const u16, @ptrFromInt(@as(usize, @intCast(win32.ui.windows_and_messaging.IDI_WARNING)))),
                    .@"error" => @as([*:0]align(1) const u16, @ptrFromInt(@as(usize, @intCast(win32.ui.windows_and_messaging.IDI_ERROR)))),
                    .information => @as([*:0]align(1) const u16, @ptrFromInt(@as(usize, @intCast(win32.ui.windows_and_messaging.IDI_INFORMATION)))),
                };
                return @ptrCast(win32.ui.windows_and_messaging.LoadImageW(null, path, .ICON, 16, 16, LR_SHARED));
            }
        }
    }

    pub const Symbol = enum {
        application,
        hand,
        question,
        exclamation,
        asterisk,
        winlogo,
        shield,
        warning,
        @"error",
        information,
    };

    pub const Application: @This() = .{ .icon = .application };
    pub const Hand: @This() = .{ .icon = .hand };
    pub const Question: @This() = .{ .icon = .question };
    pub const Exclamation: @This() = .{ .icon = .exclamation };
    pub const Asterisk: @This() = .{ .icon = .asterisk };
    pub const Winlogo: @This() = .{ .icon = .winlogo };
    pub const Shield: @This() = .{ .icon = .shield };
    pub const Warning: @This() = .{ .icon = .warning };
    pub const Error: @This() = .{ .icon = .@"error" };
    pub const Information: @This() = .{ .icon = .information };
};

hwnd: HWND,
taskbar: *ITaskbarList3 = undefined,

image_list: ?ImageList = null,
buttons: ?[]Button.FlagState = null,

pub fn init(hwnd: HWND) !@This() {
    // STA is fine for UI thread
    if (!ok(CoInitializeEx(null, COINIT_APARTMENTTHREADED))) return error.ComInitFailed;

    var unk: *anyopaque = undefined;
    if (!ok(CoCreateInstance(&CLSID_TaskbarList, null, CLSCTX_INPROC_SERVER, &ITaskbarList3.IID, &unk)))
        return error.CoCreateInstanceFailed;

    const taskbar: *ITaskbarList3 = @ptrCast(@alignCast(unk));
    if (!ok(taskbar.hrInit())) return error.TaskbarHrInitFailed;
    errdefer _ = taskbar.release();

    return .{
        .hwnd = hwnd,
        .taskbar = taskbar,
        .image_list = null,
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    _ = self.taskbar.release();
    if (self.image_list) |*il| _ = il.destroy();
    if (self.buttons) |b| allocator.free(b);
    CoUninitialize();
}

pub fn markFullscreen(self: *@This(), hwnd: HWND, state: bool) HRESULT {
    return self.taskbar.markFullscreenWindow(hwnd, state);
}

pub fn setProgress(self: *@This(), state: TBPFLAG, completed: u64, total: u64) !void {
    if (!ok(self.taskbar.setProgressValue(self.hwnd, completed, total))) return error.SetTaskbarProgressValue;
    if (!ok(self.taskbar.setProgressState(self.hwnd, state))) return error.SetTaskbarProgressState;
}

pub fn updateIcon(self: *@This(), index: usize, icon: Icon) !void {
    if (self.image_list) |*images| {
        const ico = icon.getHIcon() orelse return error.CreateButtonIcon;
        defer _ = win32.ui.windows_and_messaging.DestroyIcon(ico);

        if (images.replaceIcon(@intCast(index), ico) != @as(i32, @intCast(index))) return error.UpdateButtonIcon;
        _ = self.taskbar.setImages(self.hwnd, images.handle);
        if (!ok(self.taskbar.updateButtons(self.hwnd, &.{
            .{
                .iId = @intCast(index),
                .dwMask = .{ .BITMAP = 1 },
                .iBitmap = @intCast(index),
            },
        }))) return error.UpdateButtons;
    }
}

pub fn updateTooltip(self: *@This(), index: usize, tooltip: ?[]const u8) !void {
    var button: THUMBBUTTON = .{
        .iId = @intCast(index),
        .dwMask = .{ .TOOLTIP = 1 },
    };

    if (tooltip) |t| {
        _ = try std.unicode.utf8ToUtf16Le(&button.szTip, t);
    }

    if (!ok(self.taskbar.updateButtons(self.hwnd, &.{ button }))) return error.UpdateButtons;
}

pub fn updateFlags(self: *@This(), index: usize, button: Button.Flags) !void {
    if (self.buttons) |buttons| {
        if (button.background) |b| buttons[index].background = b;
        if (button.hidden) |h| buttons[index].hidden = h;
        if (button.disabled) |d| buttons[index].disabled = d;
        if (button.dismiss_on_click) |d| buttons[index].dismiss_on_click = d;

        if (!ok(self.taskbar.updateButtons(self.hwnd, &.{
            .{
                .iId = @intCast(index),
                .dwMask = .{ .FLAGS = 1 },
                .iBitmap = @intCast(index),
                .dwFlags = .{
                    .NOBACKGROUND = if (buttons[index].background) 0 else 1,
                    .DISABLED = if (buttons[index].disabled) 1 else 0,
                    .DISMISSONCLICK = if (buttons[index].dismiss_on_click) 1 else 0,
                    .HIDDEN = if (buttons[index].hidden) 1 else 0,
                },
                },
            }))) return error.UpdateButtons;
    }
}

pub fn addButtons(self: *@This(), allocator: std.mem.Allocator, buttons: []const Button) !void {
    if (buttons.len == 0) return;
    if (self.image_list != null) return error.InitializeThumbBarMoreThanOnce;

    self.buttons = try allocator.alloc(Button.FlagState, buttons.len);

    self.image_list = try ImageList.create(@intCast(buttons.len));
    _ = self.image_list.?.setBkColor(shobjidl.CLR_NONE);

    const thumb_buttons: []THUMBBUTTON = try allocator.alloc(THUMBBUTTON, buttons.len);
    defer allocator.free(thumb_buttons);

    for (buttons, 0..) |button, i| {
        self.buttons.?[i] = .{
            .background = button.background,
            .hidden = button.hidden,
            .disabled = button.disabled,
            .dismiss_on_click = button.dismiss_on_click,
        };

        const icon = button.icon.getHIcon() orelse return error.CreateButtonIcon;
        defer _ = win32.ui.windows_and_messaging.DestroyIcon(icon);

        if (self.image_list.?.replaceIcon(-1, icon) == -1) return error.AppendButtonIcon;

        thumb_buttons[i] = .{
            .iId = @intCast(i),
            .dwMask = .{
                .ICON = 0,
                .TOOLTIP = if (button.tooltip != null) 1 else 0,
                .FLAGS = 1,
                .BITMAP = 1,
            },
            .iBitmap = @intCast(i),
            .dwFlags = .{
                .NOBACKGROUND = if (button.background) 0 else 1,
                .DISABLED = if (button.disabled) 1 else 0,
                .DISMISSONCLICK = if (button.dismiss_on_click) 1 else 0,
                .HIDDEN = if (button.hidden) 1 else 0,
            },
        };

        if (button.tooltip) |t| {
            _ = try std.unicode.utf8ToUtf16Le(&thumb_buttons[i].szTip, t);
        }
    }

    _ = self.taskbar.setImages(self.hwnd, self.image_list.?.handle);
    _ = self.taskbar.addButtons(self.hwnd, thumb_buttons);
}
