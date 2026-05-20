const std = @import("std");

const Icon = @import("./icon.zig").Icon;

const windows = @import("windows");
const win32 = windows.win32;
const windows_and_messaging = win32.ui.windows_and_messaging;

const HRESULT = win32.foundation.HRESULT;
const RECT = win32.foundation.RECT;
const BOOL = win32.foundation.BOOL;
const HWND = win32.foundation.HWND;
const TRUE = win32.zig.TRUE;
const FALSE = win32.zig.FALSE;
const HICON = win32.ui.windows_and_messaging.HICON;
const CoInitializeEx = win32.system.com.CoInitializeEx;
const CoTaskMemFree = win32.system.com.CoTaskMemFree;
const CoCreateInstance = win32.system.com.CoCreateInstance;
const CoUninitialize = win32.system.com.CoUninitialize;
const COINIT_APARTMENTTHREADED = win32.system.com.COINIT_APARTMENTTHREADED;
const CLSCTX_INPROC_SERVER = win32.system.com.CLSCTX_INPROC_SERVER;
const LR_SHARED = win32.ui.windows_and_messaging.LR_SHARED;

const IUnknown = windows.IUnknown;
const IID_ITaskbarList3 = win32.ui.shell.IID_ITaskbarList3;
const CLSID_TaskbarList = win32.ui.shell.CLSID_TaskbarList;
const controls = win32.ui.controls;
const HIMAGELIST = controls.HIMAGELIST;

const ICustomDestinationList = win32.ui.shell.ICustomDestinationList;
const IID_ICustomDestinationList = win32.ui.shell.IID_ICustomDestinationList;
const CLSID_DestinationList = win32.ui.shell.CLSID_DestinationList;

const IObjectCollection = win32.ui.shell.common.IObjectCollection;
const IID_IObjectCollection = win32.ui.shell.common.IID_IObjectCollection;
const CLSID_EnumerableObjectCollection = win32.ui.shell.CLSID_EnumerableObjectCollection;
const IObjectArray = win32.ui.shell.common.IObjectArray;
const IID_IObjectArray = win32.ui.shell.common.IID_IObjectArray;

const IShellItem = win32.ui.shell.IShellItem;
const IID_IShellItem = win32.ui.shell.IID_IShellItem;
const SIGDN_DESKTOPABSOLUTEPARSING = win32.ui.shell.SIGDN_DESKTOPABSOLUTEPARSING;
const SHCreateItemFromParsingName = win32.ui.shell.SHCreateItemFromParsingName;

const IShellLinkW = win32.ui.shell.IShellLinkW;
const IID_IShellLinkW = win32.ui.shell.IID_IShellLinkW;
const CLSID_ShellLink = win32.ui.shell.CLSID_ShellLink;

const iconToResource = @import("./icon.zig").iconToResource;

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
    no_progress = 0,
    indeterminate = 1,
    normal = 2,
    @"error" = 4,
    paused = 8,
};

pub const ITaskbarList3 = extern struct {
    vtable: *VTable,

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
        return self.vtable.MarkFullscreenWindow(self, hwnd, if (state) TRUE else FALSE);
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
            .handle = controls.ImageList_Create(
                16,
                16,
                controls.ILC_COLOR32,
                @intCast(capacity),
                1,
            ) orelse return error.ImageListCreate,
        };
    }

    pub fn destroy(self: *@This()) bool {
        return TRUE == controls.ImageList_Destroy(self.handle);
    }

    pub fn count(self: *@This()) i32 {
        return controls.ImageList_GetImageCount(self.handle);
    }

    pub fn resize(self: *@This(), size: u32) bool {
        return TRUE == controls.ImageList_SetImageCount(self.handle, size);
    }

    pub fn add(self: *@This(), bitmap: controls.HBITMAP, mask: controls.HBITMAP) i32 {
        return controls.ImageList_Add(self.handle, bitmap, mask);
    }

    pub fn replace(self: *@This(), index: i32, bitmap: controls.HBITMAP, mask: controls.HBITMAP) bool {
        return TRUE == controls.ImageList_Replace(self.handle, index, bitmap, mask);
    }

    pub fn replaceIcon(self: *@This(), i: i32, icon: ?HICON) i32 {
        return controls.ImageList_ReplaceIcon(self.handle, i, icon);
    }

    pub fn remove(self: *@This(), index: i32) bool {
        return TRUE == controls.ImageList_Remove(self.handle, index);
    }

    pub fn setBkColor(self: *@This(), clrBk: u32) u32 {
        return controls.ImageList_SetBkColor(self.handle, clrBk);
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
    icon: @import("../icon.zig").Icon,
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

arena: std.heap.ArenaAllocator,

handle: HWND,

taskbar: *ITaskbarList3 = undefined,
state: ?*anyopaque = null,

image_list: ?ImageList = null,
buttons: ?[]Button.FlagState = null,

pub const Options = struct {
    /// Buttons cannot be added or removed later
    ///
    /// Instead set or update a button to be hidden
    /// when you do not want to display it
    buttons: ?[]const Button = null,
    state: ?*anyopaque,
};

pub fn attach(allocator: std.mem.Allocator, window: usize, options: Options) !*@This() {
    // STA is fine for UI thread
    if (!ok(CoInitializeEx(null, COINIT_APARTMENTTHREADED))) return error.ComInitFailed;

    var unk: *anyopaque = undefined;
    if (!ok(CoCreateInstance(CLSID_TaskbarList, null, CLSCTX_INPROC_SERVER, IID_ITaskbarList3, &unk)))
        return error.CoCreateInstanceFailed;

    const taskbar: *ITaskbarList3 = @ptrCast(@alignCast(unk));
    if (!ok(taskbar.hrInit())) return error.TaskbarHrInitFailed;
    errdefer _ = taskbar.release();

    const instance = try allocator.create(@This());
    instance.* = .{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .handle = @ptrFromInt(window),
        .taskbar = taskbar,
        .image_list = null,
        .state = options.state,
    };
    errdefer instance.detach();

    if (options.buttons) |buttons| {
        try instance.addButtons(buttons);
    }

    return instance;
}

pub fn detach(self: *@This()) void {
    defer self.arena.child_allocator.destroy(self);
    defer self.arena.deinit();

    _ = self.taskbar.release();
    if (self.image_list) |*il| _ = il.destroy();
    CoUninitialize();
}

/// Mark the window as fullscreen.
///
/// This pushes the taskbar to the bottom of the z-order when the window is active.
pub fn markFullscreen(self: *@This(), state: bool) !void {
    if (!ok(self.taskbar.markFullscreenWindow(self.handle, state))) return error.TaskbarMarkFullscreen;
}

/// Set the progress bar in the taskbar icon
pub fn setProgress(self: *@This(), state: TBPFLAG, completed: u64, total: u64) !void {
    if (!ok(self.taskbar.setProgressValue(self.handle, completed, total))) return error.SetTaskbarProgressValue;
    if (!ok(self.taskbar.setProgressState(self.handle, state))) return error.SetTaskbarProgressState;
}

/// Set the icon used for a specific button
///
/// The index is the same order as what is defined in addButtons
pub fn setIcon(self: *@This(), index: usize, icon: @import("../icon.zig").Icon) !void {
    if (self.image_list) |*images| {

        const ico = try Icon.init(self.arena.allocator(), icon);
        defer ico.deinit();

        if (images.replaceIcon(@intCast(index), ico.handle()) != @as(i32, @intCast(index))) return error.UpdateButtonIcon;
        _ = self.taskbar.setImages(self.handle, images.handle);
        if (!ok(self.taskbar.updateButtons(self.handle, &.{
            .{
                .iId = @intCast(index),
                .dwMask = .{ .BITMAP = 1 },
                .iBitmap = @intCast(index),
            },
        }))) return error.UpdateButtons;
    }
}

/// Update the tooltip used for a specific button
///
/// The index is the same order as what is defined in addButtons
pub fn setTooltip(self: *@This(), index: usize, tooltip: ?[]const u8) !void {
    var button: THUMBBUTTON = .{
        .iId = @intCast(index),
        .dwMask = .{ .TOOLTIP = 1 },
    };

    if (tooltip) |t| {
        _ = try std.unicode.utf8ToUtf16Le(&button.szTip, t);
    }

    if (!ok(self.taskbar.updateButtons(self.handle, &.{button}))) return error.UpdateButtons;
}

/// Update the flags used for a specific button
///
/// The index is the same order as what is defined in addButtons
pub fn setFlags(self: *@This(), index: usize, button: Button.Flags) !void {
    if (self.buttons) |buttons| {
        if (button.background) |b| buttons[index].background = b;
        if (button.hidden) |h| buttons[index].hidden = h;
        if (button.disabled) |d| buttons[index].disabled = d;
        if (button.dismiss_on_click) |d| buttons[index].dismiss_on_click = d;

        if (!ok(self.taskbar.updateButtons(self.handle, &.{
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

/// Add buttons to the window preview when hovering on the taskbar icon
///
/// The index of a button is the same order as what is defined in this method
fn addButtons(self: *@This(), buttons: []const Button) !void {
    const allocator = self.arena.allocator();

    if (buttons.len == 0) return;
    if (self.image_list != null) return error.InitializeThumbBarMoreThanOnce;

    self.buttons = try allocator.alloc(Button.FlagState, buttons.len);

    self.image_list = try ImageList.create(@intCast(buttons.len));
    _ = self.image_list.?.setBkColor(@bitCast(controls.CLR_NONE));

    const thumb_buttons: []THUMBBUTTON = try allocator.alloc(THUMBBUTTON, buttons.len);
    defer allocator.free(thumb_buttons);

    for (buttons, 0..) |button, i| {
        self.buttons.?[i] = .{
            .background = button.background,
            .hidden = button.hidden,
            .disabled = button.disabled,
            .dismiss_on_click = button.dismiss_on_click,
        };

        const icon = try Icon.init(allocator, button.icon);
        defer icon.deinit();

        if (self.image_list.?.replaceIcon(-1, icon.handle()) == -1) return error.AppendButtonIcon;

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

    _ = self.taskbar.setImages(self.handle, self.image_list.?.handle);
    _ = self.taskbar.addButtons(self.handle, thumb_buttons);
}

pub const JumpList = struct {
    tasks: ?[]const Link = null,
    categories: ?[]const Category = null,
    recent: bool = false,
    frequent: bool = false,

    pub const Link = struct {
        label: []const u8,
        args: []const u8,
        icon: ?[]const u8 = null,
    };

    pub const Category = struct {
        label: []const u8,
        items: []const Item,

        pub const Item = union(enum) {
            link: Link,
            file: []const u8,
        };
    };
};

/// Use IApplicationAssociationRegistrationUI::LaunchAdvancedAssociationUI to prompt user to
/// select the current app for a file association
///
/// To specify that the app is associated with a file type register handler for "appid"
/// HKCU\Software\Classes\.story\
///     (Default)          (REG_SZ) "Storytree.story"
///     OpenWithProgids\
///         Storytree.story (REG_NONE or REG_SZ) ""   ; empty data
///
/// HKCU\Software\Classes\Storytree.story\
///     (Default)          (REG_SZ) "Storytree Document"
///     FriendlyTypeName   (REG_SZ) "Storytree Document"
///     DefaultIcon        (REG_SZ) "<full\path\to\dev.exe>,0"
///     shell\open\command (REG_SZ) "\"<full\path\to\dev.exe>\" \"%1\""
///
/// Or With
///
/// HKCU\Software\Classes\Applications\<YourExeName>.exe\
///     FriendlyAppName    (REG_SZ) "Storytree"
///     DefaultIcon        (REG_SZ) "<full\path\to\dev.exe>,0"
///     shell\open\command (REG_SZ) "\"<full\path\to\dev.exe>\" \"%1\""
///     SupportedTypes\
///         .story         (REG_SZ) ""      ; value name = extension, empty data
///         .tree          (REG_SZ) ""
///
/// TODO: Report on the category items that were removed
pub fn setJumpList(self: *@This(), io: std.Io, list: JumpList) !void {
    const allocator = self.arena.allocator();

    if (!ok(CoInitializeEx(null, COINIT_APARTMENTTHREADED))) return error.ComInit;
    defer CoUninitialize();

    var cdl_unk: *anyopaque = undefined;
    if (!ok(CoCreateInstance(
        CLSID_DestinationList,
        null,
        CLSCTX_INPROC_SERVER,
        IID_ICustomDestinationList,
        &cdl_unk,
    )))
        return error.CoCreateDestList;

    const cdl: *ICustomDestinationList = @ptrCast(@alignCast(cdl_unk));
    defer _ = IUnknown.Release(@ptrCast(cdl));
    errdefer _ = cdl.AbortList();

    var max_slots: u32 = 0;
    var removed_unk: *anyopaque = undefined;
    if (!ok(cdl.BeginList(&max_slots, IID_IObjectArray, &removed_unk))) {
        return error.BeginList;
    }

    const removed: *IObjectArray = @ptrCast(@alignCast(removed_unk));
    defer _ = IUnknown.Release(@ptrCast(removed));

    var total_removed: u32 = 0;
    _ = removed.GetCount(&total_removed);

    var removed_lookup: std.AutoArrayHashMapUnmanaged(u64, void) = .empty;
    defer removed_lookup.deinit(allocator);

    for (0..total_removed) |i| {
        var r: *IUnknown = undefined;
        if (!ok(removed.GetAt(@intCast(i), &IUnknown.IID, @ptrCast(&r)))) continue;

        var item_unk: ?*anyopaque = undefined;
        if (r.QueryInterface(IID_IShellLinkW, &item_unk)) {
            const item: *IShellLinkW = @ptrCast(@alignCast(item_unk.?));

            var hasher = std.hash.Wyhash.init(0);

            {
                var path: [260:0]u16 = std.mem.zeroes([260:0]u16);
                _ = item.GetPath(&path, @intCast(path.len), null, 0);
                const path_utf8 = try std.unicode.utf16LeToUtf8Alloc(allocator, &path);
                defer allocator.free(path_utf8);
                hasher.update(std.mem.sliceTo(path_utf8, 0));
            }

            {
                var args: [512:0]u16 = std.mem.zeroes([512:0]u16);
                _ = item.GetArguments(&args, @intCast(args.len));

                const args_utf8 = try std.unicode.utf16LeToUtf8Alloc(allocator, &args);
                defer allocator.free(args_utf8);
                hasher.update(std.mem.sliceTo(args_utf8, 0));
            }

            try removed_lookup.put(allocator, hasher.final(), {});
        } else |_| {
            if (r.QueryInterface(IID_IShellItem, &item_unk)) {
                const item: *IShellItem = @ptrCast(@alignCast(item_unk.?));

                var name: ?[*:0]u16 = null;
                defer CoTaskMemFree(@ptrCast(name));
                _ = item.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &name);

                var buffer: [260]u8 = undefined;
                const size = try std.unicode.utf16LeToUtf8(&buffer, std.mem.sliceTo(name.?, 0));

                try removed_lookup.put(allocator, std.hash.Wyhash.hash(0, buffer[0..size]), {});
            } else |_| {}
        }
    }

    // TODO respect removed items <here>

    // ----- TASKS -----
    task_blk: {
        if (list.tasks) |tasks| {
            if (tasks.len == 0) break :task_blk;

            var tasks_unk: *anyopaque = undefined;
            if (!ok(CoCreateInstance(
                CLSID_EnumerableObjectCollection,
                null,
                CLSCTX_INPROC_SERVER,
                IID_IObjectCollection,
                &tasks_unk,
            ))) {
                return error.CoCreateCollection;
            }

            const task_collection: *IObjectCollection = @ptrCast(@alignCast(tasks_unk));
            defer _ = IUnknown.Release(@ptrCast(task_collection));

            const exe_path = try std.process.executablePathAlloc(io, allocator);
            defer allocator.free(exe_path);

            const cwd = std.Io.Dir.cwd();
            var path_buffer: [260]u8 = undefined;

            const l = try std.process.executableDirPath(io, &path_buffer);
            var exe_dir = try cwd.openDir(io, path_buffer[0..l], .{});
            defer exe_dir.close(io);

            const wide_exe_path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, exe_path);
            defer allocator.free(wide_exe_path);

            for (tasks) |task| {
                const label = try std.unicode.utf8ToUtf16LeAllocZ(allocator, task.label);
                defer allocator.free(label);

                const args = try std.unicode.utf8ToUtf16LeAllocZ(allocator, task.args);
                defer allocator.free(args);

                var icon: ?[:0]const u16 = null;
                defer if (icon) |i| allocator.free(i);

                if (task.icon) |i| {
                    const path = try exe_dir.realPathFileAlloc(io, i, allocator);
                    defer allocator.free(path);
                    icon = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
                }

                const link = try makeLink(label, wide_exe_path, args, icon orelse wide_exe_path, 0);
                defer _ = IUnknown.Release(@ptrCast(link));

                _ = task_collection.AddObject(@ptrCast(link));
            }

            const hr = cdl.AddUserTasks(@ptrCast(task_collection));
            if (!ok(hr)) return error.AddTasks;
        }
    }

    if (list.categories) |categories| {
        for (categories) |category| {
            if (category.items.len == 0) continue;

            var total: usize = 0;

            var tasks_unk: *anyopaque = undefined;
            if (!ok(CoCreateInstance(
                CLSID_EnumerableObjectCollection,
                null,
                CLSCTX_INPROC_SERVER,
                IID_IObjectCollection,
                &tasks_unk,
            ))) {
                return error.CoCreateCollection;
            }

            const task_collection: *IObjectCollection = @ptrCast(@alignCast(tasks_unk));
            defer _ = IUnknown.Release(@ptrCast(task_collection));

            const exe_path = try std.process.executablePathAlloc(io, allocator);
            defer allocator.free(exe_path);

            const cwd = std.Io.Dir.cwd();

            var path_buffer: [260]u8 = undefined;
            const l = try std.process.executableDirPath(io, &path_buffer);
            var exe_dir = try cwd.openDir(io, path_buffer[0..l], .{});
            defer exe_dir.close(io);

            const wide_exe_path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, exe_path);
            defer allocator.free(wide_exe_path);

            for (category.items) |item| {
                switch (item) {
                    .link => |task| {
                        var hasher = std.hash.Wyhash.init(0);
                        hasher.update(exe_path);
                        hasher.update(task.args);
                        const hash = hasher.final();
                        if (removed_lookup.contains(hash)) continue;

                        const label = try std.unicode.utf8ToUtf16LeAllocZ(allocator, task.label);
                        defer allocator.free(label);

                        const args = try std.unicode.utf8ToUtf16LeAllocZ(allocator, task.args);
                        defer allocator.free(args);

                        var icon: ?[:0]const u16 = null;
                        defer if (icon) |i| allocator.free(i);

                        if (task.icon) |i| {
                            const path = try exe_dir.realPathFileAlloc(io, i, allocator);
                            defer allocator.free(path);
                            icon = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
                        }

                        const link = try makeLink(label, wide_exe_path, args, icon orelse wide_exe_path, 0);
                        defer _ = IUnknown.Release(@ptrCast(link));

                        total += 1;
                        _ = task_collection.AddObject(@ptrCast(link));
                    },
                    .file => |path| {
                        if (removed_lookup.contains(std.hash.Wyhash.hash(0, path))) continue;

                        const wide_path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
                        defer allocator.free(wide_path);

                        var shell_item: *IShellItem = undefined;
                        if (ok(SHCreateItemFromParsingName(wide_path.ptr, null, IID_IShellItem, @ptrCast(&shell_item)))) {
                            total += 1;
                            _ = task_collection.AddObject(@ptrCast(shell_item));
                            _ = IUnknown.Release(@ptrCast(shell_item));
                        }
                    },
                }
            }

            if (total > 0) {
                const name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, category.label);
                defer allocator.free(name);

                const hr = cdl.AppendCategory(name.ptr, @ptrCast(task_collection));
                if (!ok(hr) and @as(u32, @bitCast(hr)) != 0x80070005) {
                    std.debug.print("0x{x}\n", .{ @as(u32, @bitCast(hr))});
                    return error.AppendCategory;
                }
            }
        }
    }

    if (list.recent) _ = cdl.AppendKnownCategory(.RECENT);
    if (list.frequent) _ = cdl.AppendKnownCategory(.FREQUENT);

    _ = cdl.CommitList();
}

fn iconPath(allocator: std.mem.Allocator, base: *std.Io.Dir, subpath: []const u8) ![:0]const u16 {
    const icon_path = try base.realpathAlloc(allocator, subpath);
    defer allocator.free(icon_path);
    const wide_icon_path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, icon_path);
    return wide_icon_path;
}

// Helper: create an IShellLinkW with a visible title (Tasks/custom items use this)
fn makeLink(title: [*:0]const u16, exe_path: [*:0]const u16, args: [*:0]const u16, icon_path: [*:0]const u16, icon_index: c_int) !*IShellLinkW {
    var unk: *anyopaque = undefined;
    if (!ok(CoCreateInstance(CLSID_ShellLink, null, CLSCTX_INPROC_SERVER, IID_IShellLinkW, &unk)))
        return error.CoCreateShellLink;

    const link: *IShellLinkW = @ptrCast(@alignCast(unk));

    _ = link.SetPath(exe_path);
    _ = link.SetArguments(args);
    _ = link.SetIconLocation(icon_path, icon_index);
    // (optional) SetWorkingDirectory, SetDescription, etc…

    // Set the display text via IPropertyStore/PKEY_Title
    var ps: ?*IPropertyStore = null;
    if (IUnknown.QueryInterface(@ptrCast(link), IID_IPropertyStore, @ptrCast(&ps))) {
        var pv: PROPVARIANT = undefined;
        _ = InitPropVariantFromString(title, &pv);
        _ = ps.?.SetValue(&PKEY_Title, &pv);
        _ = ps.?.Commit();
        _ = PropVariantClear(&pv);
        _ = IUnknown.Release(@ptrCast(ps.?));
    } else |_| {}
    return link;
}

const L = std.unicode.utf8ToUtf16LeStringLiteral;

const IID_IPropertyStore = win32.ui.shell.properties_system.IID_IPropertyStore;
const IPropertyStore = win32.ui.shell.properties_system.IPropertyStore;
const PROPVARIANT = win32.system.com.structured_storage.PROPVARIANT;
const InitPropVariantFromString = win32.ui.shell.properties_system.InitPropVariantFromStringAsVector;
const PropVariantClear = win32.system.com.structured_storage.PropVariantClear;
const PKEY_Title = win32.storage.enhanced_storage.PKEY_Title;
