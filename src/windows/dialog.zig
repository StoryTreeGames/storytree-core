const std = @import("std");
const builtin = @import("builtin");

const windows = @import("windows");
const win32 = windows.win32;

const hresultToError = windows.core.hresultToError;

const LOGFONTA = win32.graphics.gdi.LOGFONTA;
const CHOOSECOLORA = win32.ui.controls.dialogs.CHOOSECOLORA;
const CHOOSEFONTA = win32.ui.controls.dialogs.CHOOSEFONTA;
const CHOOSECOLOR_FLAGS = win32.system.system_services.CHOOSECOLOR_FLAGS;
const ChooseColorA = win32.ui.controls.dialogs.ChooseColorA;
const ChooseFontA = win32.ui.controls.dialogs.ChooseFontA;
const CommDlgExtendedError = win32.ui.controls.dialogs.CommDlgExtendedError;

const MB_ABORTRETRYIGNORE = win32.ui.windows_and_messaging.MB_ABORTRETRYIGNORE;
const MB_CANCELTRYCONTINUE = win32.ui.windows_and_messaging.MB_CANCELTRYCONTINUE;
const MB_HELP = win32.ui.windows_and_messaging.MB_HELP;
const MB_OK = win32.ui.windows_and_messaging.MB_OK;
const MB_OKCANCEL = win32.ui.windows_and_messaging.MB_OKCANCEL;
const MB_RETRYCANCEL = win32.ui.windows_and_messaging.MB_RETRYCANCEL;
const MB_YESNO = win32.ui.windows_and_messaging.MB_YESNO;
const MB_YESNOCANCEL = win32.ui.windows_and_messaging.MB_YESNOCANCEL;
const MB_ICONWARNING = win32.ui.windows_and_messaging.MB_ICONWARNING;
const MB_ICONINFORMATION = win32.ui.windows_and_messaging.MB_ICONINFORMATION;
const MB_ICONQUESTION = win32.ui.windows_and_messaging.MB_ICONQUESTION;
const MB_ICONERROR = win32.ui.windows_and_messaging.MB_ICONERROR;
const MESSAGEBOX_STYLE = win32.ui.windows_and_messaging.MESSAGEBOX_STYLE;
const MESSAGEBOX_RESULT = win32.ui.windows_and_messaging.MESSAGEBOX_RESULT;
const MessageBoxA = win32.ui.windows_and_messaging.MessageBoxA;

const CLSCTX_ALL = win32.system.com.CLSCTX_ALL;
const COMDLG_FILTERSPEC = win32.ui.shell.common.COMDLG_FILTERSPEC;
const CoInitializeEx = win32.system.com.CoInitializeEx;
const CoUninitialize = win32.system.com.CoUninitialize;
const CoCreateInstance = win32.system.com.CoCreateInstance;
const CoTaskMemFree = win32.system.com.CoTaskMemFree;

const SHCreateItemFromParsingName = win32.ui.shell.SHCreateItemFromParsingName;
const SFGAO_FILESYSTEM = win32.ui.shell.SFGAO_FILESYSTEM;
const CLSID_FileOpenDialog = win32.ui.shell.CLSID_FileOpenDialog;
const CLSID_FileSaveDialog = win32.ui.shell.CLSID_FileSaveDialog;
const IID_IFileOpenDialog = win32.ui.shell.IID_IFileOpenDialog;
const IID_IFileSaveDialog = win32.ui.shell.IID_IFileSaveDialog;
const IID_IShellItem = win32.ui.shell.IID_IShellItem;
const FILEOPENDIALOGOPTIONS = win32.ui.shell.FILEOPENDIALOGOPTIONS;
const IFileOpenDialog = win32.ui.shell.IFileOpenDialog;
const IFileSaveDialog = win32.ui.shell.IFileSaveDialog;
const IFileDialog = win32.ui.shell.IFileDialog;
const IShellItem = win32.ui.shell.IShellItem;
const IShellItemArray = win32.ui.shell.IShellItemArray;
const IModalWindow = win32.ui.shell.IModalWindow;

const IUnknown = windows.IUnknown;

const d = @import("../dialog.zig");
const root = @import("../root.zig");

const Color = root.Color;
const Font = root.Font;
const FileOpenDialogOptions = d.FileOpenDialogOptions;
const FileSaveDialogOptions = d.FileSaveDialogOptions;
const ColorOptions = d.ColorOptions;
const FontOptions = d.FontOptions;

const Buttons = d.Buttons;
const MessageOptions = d.MessageOptions;
const Button = d.Button;

pub const AllocatedConfiguration = struct {
    default_folder: ?*IShellItem = null,

    pub fn deinit(self: *const @This()) void {
        if (self.default_folder) |default_folder| {
            _ = IUnknown.Release(@ptrCast(default_folder));
        }
    }
};

fn configureFileDialog(allocator: std.mem.Allocator, dialog: *IFileDialog, options: anytype) !AllocatedConfiguration {
    var config: AllocatedConfiguration = .{};
    var hresult: i32 = 0;

    if (options.folder.len > 0) {
        const path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, options.folder);
        var default_folder: *IShellItem = undefined;

        const result = SHCreateItemFromParsingName(path.ptr, null, IID_IShellItem, @ptrCast(&default_folder));
        if (result != 0) return error.Win32Error;
        hresult = dialog.SetFolder(default_folder);
        if (hresult != 0) return hresultToError(hresult).err;

        config.default_folder = default_folder;
    }

    if (options.file_name.len > 0) {
        const path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, options.file_name);
        hresult = dialog.SetFileName(path.ptr);
        if (hresult != 0) return hresultToError(hresult).err;
    }

    if (options.filters.len > 0) {
        try addFileDialogFilters(allocator, dialog, options.filters);
    }

    if (options.title.len > 0) {
        const title = try std.unicode.utf8ToUtf16LeAllocZ(allocator, options.title);
        hresult = dialog.SetTitle(title.ptr);
        if (hresult != 0) return hresultToError(hresult).err;
    }

    return config;
}

fn addFileDialogFilters(
    allocator: std.mem.Allocator,
    dialog: *IFileDialog,
    types: []const std.meta.Tuple(&.{ []const u8, []const u8 }),
) !void {
    const filters = try allocator.alloc(COMDLG_FILTERSPEC, types.len);
    for (types, 0..) |filter, i| {
        const name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, filter[0]);
        const spec = try std.unicode.utf8ToUtf16LeAllocZ(allocator, filter[1]);

        filters[i] = COMDLG_FILTERSPEC{
            .pszName = name,
            .pszSpec = spec,
        };
    }
    const hresult = dialog.SetFileTypes(@intCast(filters.len), filters.ptr);
    if (hresult != 0) return hresultToError(hresult).err;
}

pub fn processResult(buttons: ?Buttons, action: i32) ?Button {
    switch (builtin.os.tag) {
        .windows => {
            const result: MESSAGEBOX_RESULT = @enumFromInt(action);

            if (buttons) |btns| {
                switch (btns) {
                    .abort_retry_ignore => switch (result) {
                        .ABORT => return Button.abort,
                        .RETRY => return Button.retry,
                        .IGNORE => return Button.retry,
                        else => return null,
                    },
                    .cancel_try_continue => switch (result) {
                        .CANCEL => return Button.cancel,
                        .TRYAGAIN => return Button.@"try",
                        .CONTINUE => return Button.@"continue",
                        else => return null,
                    },
                    .help => switch (result) {
                        .OK => return .help,
                        else => return null,
                    },
                    .ok => switch (result) {
                        .OK => return .ok,
                        else => return null,
                    },
                    .ok_cancel => switch (result) {
                        .OK => return Button.ok,
                        .CANCEL => return Button.cancel,
                        else => return null,
                    },
                    .retry_cancel => switch (result) {
                        .RETRY => return Button.retry,
                        .CANCEL => return Button.cancel,
                        else => return null,
                    },
                    .yes_no => switch (result) {
                        .YES => return Button.yes,
                        else => return Button.no,
                    },
                    .yes_no_cancel => switch (result) {
                        .YES => return Button.yes,
                        .NO => return Button.no,
                        .CANCEL => return Button.cancel,
                        else => return null,
                    },
                }
            }
            return null;
        },
        else => @compileError("platform not supported"),
    }
}

pub fn message(buttons: ?Buttons, opts: MessageOptions) ?Button {
    const button_style: u32 = @bitCast(if (buttons) |btns| switch (btns) {
        .abort_retry_ignore => MB_ABORTRETRYIGNORE,
        .cancel_try_continue => MB_CANCELTRYCONTINUE, // AD
        .help => MB_HELP,
        .ok => MB_OK,
        .ok_cancel => MB_OKCANCEL, // AD
        .retry_cancel => MB_RETRYCANCEL, // AD
        .yes_no => MB_YESNO,
        .yes_no_cancel => MB_YESNOCANCEL, // AD
    } else MESSAGEBOX_STYLE{});

    const icon_style: u32 = @bitCast(if (opts.icon) |ico| switch (ico) {
        .warning => MB_ICONWARNING,
        .information => MB_ICONINFORMATION,
        .question => MB_ICONQUESTION,
        .@"error" => MB_ICONERROR,
    } else MESSAGEBOX_STYLE{});

    const result = MessageBoxA(
        if (opts.owner) |p| @ptrFromInt(p) else null,
        if (opts.message) |m| @ptrCast(m.ptr) else null,
        if (opts.title) |t| @ptrCast(t.ptr) else null,
        @as(MESSAGEBOX_STYLE, @bitCast(button_style | icon_style)),
    );

    return processResult(buttons, @intFromEnum(result));
}

pub fn open(allocator: std.mem.Allocator, opts: FileOpenDialogOptions) !?[]const []const u8 {
    if (CoInitializeEx(null, .{
        .APARTMENTTHREADED = 1,
        .DISABLE_OLE1DDE = 1,
    }) != 0) return error.CoInitializeFailure;
    defer CoUninitialize();

    var file_open_dialog: *IFileOpenDialog = undefined;
    if (CoCreateInstance(
        CLSID_FileOpenDialog,
        null,
        CLSCTX_ALL,
        IID_IFileOpenDialog,
        @ptrCast(&file_open_dialog),
    ) != 0) return error.CoCreateInstanceFailure;
    defer _ = IUnknown.Release(@ptrCast(file_open_dialog));

    const file_dialog: *IFileDialog = @ptrCast(file_open_dialog);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const config = try configureFileDialog(arena.allocator(), file_dialog, opts);
    defer config.deinit();

    var options: FILEOPENDIALOGOPTIONS = undefined;
    var hresult = file_dialog.GetOptions(&options);
    if (hresult != 0) return hresultToError(hresult).err;

    options.PICKFOLDERS = @intFromBool(opts.directory);
    options.ALLOWMULTISELECT = @intFromBool(opts.multiple);
    if (opts.directory)
        options.PATHMUSTEXIST = @intFromBool(opts.exists)
    else
        options.FILEMUSTEXIST = @intFromBool(opts.exists);

    hresult = file_dialog.SetOptions(options);
    if (hresult != 0) return hresultToError(hresult).err;

    const modal: *IModalWindow = @ptrCast(file_open_dialog);
    switch (@as(u32, @bitCast(modal.Show(if (opts.owner) |p| @ptrFromInt(p) else null)))) {
        0 => {},
        0x800704C7 => return error.UserCancelled,
        else => |other| return hresultToError(@bitCast(other)).err,
    }

    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(allocator);

    if (opts.multiple) {
        var shell_items: ?*IShellItemArray = undefined;
        hresult = file_open_dialog.GetResults(&shell_items);
        if (hresult != 0) return hresultToError(hresult).err;

        if (shell_items) |items| {
            defer _ = IUnknown.Release(@ptrCast(items));
            var len: u32 = 0;
            _ = items.GetCount(&len);

            for (0..len) |i| {
                var shell_item: ?*IShellItem = undefined;
                hresult = items.GetItemAt(@intCast(i), &shell_item);
                if (hresult != 0) return hresultToError(hresult).err;

                if (shell_item) |item| {
                    defer _ = IUnknown.Release(@ptrCast(item));
                    var attrs: u32 = 0;
                    hresult = item.GetAttributes(SFGAO_FILESYSTEM, &attrs);
                    if (hresult != 0) return hresultToError(hresult).err;
                    if (attrs & SFGAO_FILESYSTEM == 0) continue;

                    var display_name: ?[*:0]u16 = null;
                    hresult = item.GetDisplayName(.DESKTOPABSOLUTEPARSING, &display_name);
                    if (hresult != 0) return hresultToError(hresult).err;

                    if (display_name) |name| {
                        defer CoTaskMemFree(@ptrCast(name));
                        const n = try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(name, 0));
                        try out.append(allocator, n);
                    }
                }
            }
        }
    } else {
        var shell_item: ?*IShellItem = null;
        hresult = file_dialog.GetResult(&shell_item);
        if (hresult != 0) return hresultToError(hresult).err;

        if (shell_item) |item| {
            defer _ = IUnknown.Release(@ptrCast(item));

            var attrs: u32 = 0;
            hresult = item.GetAttributes(SFGAO_FILESYSTEM, &attrs);
            if (hresult != 0) return hresultToError(hresult).err;
            if (attrs & SFGAO_FILESYSTEM != 0) {
                var display_name: ?[*:0]u16 = null;
                hresult = item.GetDisplayName(.DESKTOPABSOLUTEPARSING, &display_name);
                if (hresult != 0) return hresultToError(hresult).err;

                if (display_name) |name| {
                    defer CoTaskMemFree(@ptrCast(name));
                    const n = try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(name, 0));
                    try out.append(allocator, n);
                }
            }
        }
    }

    return try out.toOwnedSlice(allocator);
}

pub fn save(allocator: std.mem.Allocator, opts: FileSaveDialogOptions) !?[]const u8 {
    if (CoInitializeEx(null, .{
        .APARTMENTTHREADED = 1,
        .DISABLE_OLE1DDE = 1,
    }) != 0) return error.CoInitializeFailure;
    defer CoUninitialize();

    var file_save_dialog: *IFileSaveDialog = undefined;
    if (CoCreateInstance(
        CLSID_FileSaveDialog,
        null,
        CLSCTX_ALL,
        IID_IFileSaveDialog,
        @ptrCast(&file_save_dialog),
    ) != 0) return error.CoCreateInstanceFailure;

    const file_dialog: *IFileDialog = @ptrCast(file_save_dialog);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const config = try configureFileDialog(arena.allocator(), file_dialog, opts);
    defer config.deinit();

    var options: FILEOPENDIALOGOPTIONS = undefined;
    var hresult = file_dialog.GetOptions(&options);
    if (hresult != 0) return hresultToError(hresult).err;

    options.CREATEPROMPT = @intFromBool(opts.prompt_on_create);
    hresult = file_dialog.SetOptions(options);
    if (hresult != 0) return hresultToError(hresult).err;

    const modal: *IModalWindow = @ptrCast(file_save_dialog);
    switch (@as(u32, @bitCast(modal.Show(if (opts.owner) |p| @ptrFromInt(p) else null)))) {
        0 => {},
        0x800704C7 => return error.UserCancelled,
        else => |other| return hresultToError(@bitCast(other)).err,
    }

    var shell_item: ?*IShellItem = undefined;
    hresult = file_dialog.GetResult(&shell_item);
    if (hresult != 0) return hresultToError(hresult).err;

    if (shell_item) |item| {
        defer _ = IUnknown.Release(@ptrCast(item));

        var display_name: ?[*:0]u16 = null;
        hresult = item.GetDisplayName(.DESKTOPABSOLUTEPARSING, &display_name);
        if (hresult != 0) return hresultToError(hresult).err;

        if (display_name) |name| {
            defer CoTaskMemFree(@ptrCast(@constCast(name)));
            return try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(name, 0));
        }
    }

    return null;
}

pub fn color(options: ColorOptions) !?Color {
    var custom_colors: [16]u32 = [_]u32{0x00FFFFFF} ** 16;
    if (options.custom) |custom| {
        for (custom, 0..) |c, i| {
            custom_colors[i] = @bitCast(c);
        }
    }

    var cc: CHOOSECOLORA = std.mem.zeroes(CHOOSECOLORA);
    cc.lStructSize = @sizeOf(CHOOSECOLORA);
    cc.hwndOwner = if (options.owner) |p| @ptrFromInt(p) else null;
    cc.lpCustColors = @ptrCast(@alignCast(custom_colors[0..].ptr));
    cc.rgbResult = @bitCast(options.initial);
    cc.Flags = @bitCast(CHOOSECOLOR_FLAGS { .RGBINIT = 1, .FULLOPEN = 1 });

    if (ChooseColorA(&cc) != win32.zig.TRUE) {
        switch (CommDlgExtendedError()) {
            .CDERR_GENERALCODES => return null,
            else => return error.UnknownError,
        }
    }

    if (options.custom) |custom| {
        for (custom_colors, 0..) |c, i| {
            custom[i] = @bitCast(c);
        }
    }

    return @bitCast(cc.rgbResult);
}

fn getDpiY(hwnd: ?win32.foundation.HWND) i32 {
    const hdc = win32.graphics.gdi.GetDC(hwnd);
    defer _ = win32.graphics.gdi.ReleaseDC(hwnd, hdc);
    return win32.graphics.gdi.GetDeviceCaps(hdc, win32.graphics.gdi.LOGPIXELSY);
}

fn ptToLfHeight(pt: i32, dpiY: i32) i32 {
    // lfHeight in logical units; negative -> character height mapping.
    // height = -round(pt * dpi / 72)
    return -@as(i32, @intCast(@divTrunc(pt * dpiY + 36, 72))); // simple rounding
}

/// Caller is responsible for calling `Font.deinit()`
pub fn font(allocator: std.mem.Allocator, options: FontOptions) !?Font {
    const style = try allocator.dupeZ(u8, options.style);
    defer allocator.free(style);

    var face_name: [32:0]u8 = std.mem.zeroes([32:0]u8);
    for (options.face[0..@min(options.face.len, 32)], 0..) |f, i| {
        face_name[i] = f;
    }

    var lf: LOGFONTA = std.mem.zeroes(LOGFONTA);
    lf.lfHeight = ptToLfHeight(options.point_size, getDpiY(null));
    lf.lfFaceName = face_name;

    var cf: CHOOSEFONTA = std.mem.zeroes(CHOOSEFONTA);
    cf.lStructSize = @sizeOf(CHOOSEFONTA);
    cf.lpLogFont = &lf;
    cf.Flags = .{ .SCREENFONTS = 1, .EFFECTS = 1, .INITTOLOGFONTSTRUCT = 1, .USESTYLE = 1 };
    cf.hwndOwner = if (options.owner) |p| @ptrFromInt(p) else null;
    cf.lpszStyle = style.ptr;
    cf.rgbColors = @bitCast(options.color);
    cf.iPointSize = options.point_size;

    if (ChooseFontA(&cf) == win32.zig.FALSE) {
        switch (CommDlgExtendedError()) {
            .CDERR_GENERALCODES => return null,
            else => return error.UnknownError,
        }
    }

    const name_slice: []const u8 = std.mem.sliceTo(&lf.lfFaceName, 0);
    const name = try allocator.dupe(u8, name_slice);

    return .{
        .height = @intCast(@abs(lf.lfHeight)),
        .width = @intCast(@abs(lf.lfWidth)),
        .point_size = @bitCast(@divTrunc(cf.iPointSize, 10)),
        .color = @bitCast(cf.rgbColors),
        .weight = @intCast(@abs(lf.lfWeight)),
        .italic = lf.lfItalic == 1,
        .underline = lf.lfUnderline == 1,
        .strikeout = lf.lfStrikeOut == 1,
        .name = name,
    };
}
