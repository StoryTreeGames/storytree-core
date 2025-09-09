const std = @import("std");
const uuid = @import("uuid");
const windows = @import("windows");
const win32 = windows.win32;
const registry = win32.system.registry;

const Color = @import("../root.zig").Color;

pub const HDC = win32.graphics.gdi.HDC;
pub const GetDC = win32.graphics.gdi.GetDC;
pub const GetDeviceCaps = win32.graphics.gdi.GetDeviceCaps;

pub const HWND = win32.foundation.HWND;
pub const HINSTANCE = win32.foundation.HINSTANCE;
pub const RECT = win32.foundation.RECT;
pub const POINT = win32.foundation.POINT;
pub const BOOL = win32.foundation.BOOL;
pub const HRESULT = win32.foundation.HRESULT;

pub const PROPERTYKEY = win32.ui.shell.properties_system.PROPERTYKEY;
pub const IPropertyStore = win32.ui.shell.properties_system.IPropertyStore;
pub const IPropertyDescriptionList = win32.ui.shell.properties_system.IPropertyDescriptionList;
pub const GETPROPERTYSTOREFLAGS = win32.ui.shell.properties_system.GETPROPERTYSTOREFLAGS;
pub const COMDLG_FILTERSPEC = win32.ui.shell.common.COMDLG_FILTERSPEC;

pub const TRUE = win32.zig.TRUE;
pub const FALSE = win32.zig.FALSE;
pub const Guid = win32.zig.Guid;

pub const CoInit = win32.system.com.COINIT;
pub const IBindCtx = win32.system.com.IBindCtx;
pub const IUnknown = win32.system.com.IUnknown;
pub const PROPVARIANT = win32.system.com.structured_storage.PROPVARIANT;
pub const CLSCTX_ALL = win32.system.com.CLSCTX_ALL;
pub const CoInitializeEx = win32.system.com.CoInitializeEx;
pub const CoUninitialize = win32.system.com.CoUninitialize;
pub const CoTaskMemFree = win32.system.com.CoTaskMemFree;
pub const CoCreateInstance = win32.system.com.CoCreateInstance;

pub const CHOOSECOLORA = win32.ui.controls.dialogs.CHOOSECOLORA;
pub const LOGFONTA = win32.graphics.gdi.LOGFONTA;
pub const CHOOSEFONTA = win32.ui.controls.dialogs.CHOOSEFONTA;
pub const CommDlgExtendedError = win32.ui.controls.dialogs.CommDlgExtendedError;
pub const ChooseFontA = win32.ui.controls.dialogs.ChooseFontA;
pub const ChooseColorA = win32.ui.controls.dialogs.ChooseColorA;

pub const Win32Error = std.os.windows.Win32Error;
pub const S_OK: HRESULT = 0;
pub const S_FALSE: HRESULT = 1;
pub const SIGDN_FILESYSPATH: i32 = -2147123200;
pub const SFGAO_FILESYSTEM: i32 = 0x40000000;

pub const WM_TRAYICON = win32.ui.windows_and_messaging.WM_USER + 1;

pub const CLSID_FileOpenDialog: Guid = .{ .Ints = .{
    .a = 0xdc1c5a9c,
    .b = 0xe88a,
    .c = 0x4dde, 
    .d = .{ 0xa5, 0xa1, 0x60, 0xf8, 0x2a, 0x20, 0xae, 0xf7 }
}};

pub const CLSID_FileSaveDialog: Guid = .{ .Ints = .{
    .a = 0xc0b4e2f3,
    .b = 0xba21,
    .c = 0x4773,
    .d = .{ 0x8d, 0xba, 0x33, 0x5e, 0xc9, 0x46, 0xeb, 0x8b },
}};

pub extern "shell32" fn SHCreateItemFromParsingName(pszPath: [*:0]const u16, pbc: ?*anyopaque, riid: *const Guid, ppv: **anyopaque) HRESULT;
pub extern "shell32" fn SetCurrentProcessExplicitAppUserModelID([*:0]const u16) HRESULT;

pub fn isLight(clr: windows.UI.Color) bool {
    return ((5 * @as(u32, @intCast(clr.G))) + (2 * @as(u32, @intCast(clr.R))) + @as(u32, @intCast(clr.B))) <= (8 * 128);
}

/// Allocate a sentinal utf16 string from a utf8 string
pub fn utf8ToUtf16Alloc(allocator: std.mem.Allocator, data: []const u8) ![:0]u16 {
    const len: usize = std.unicode.calcUtf16LeLen(data) catch unreachable;
    var utf16le: [:0]u16 = try allocator.allocSentinel(u16, len, 0);
    const utf16le_len = try std.unicode.utf8ToUtf16Le(utf16le[0..], data[0..]);
    std.debug.assert(len == utf16le_len);
    return utf16le;
}

/// Create/Allocate a unique window class with a uuid v4 prefixed with `STC`
pub fn createUIDClass(allocator: std.mem.Allocator) ![:0]u16 {
    // Size of {3}-{36}{null} == 41
    const uid = uuid.urn.serialize(uuid.v4.new());
    const temp = try std.fmt.allocPrint(allocator, "STC-{s}", .{uid});
    defer allocator.free(temp);

    return try utf8ToUtf16Alloc(allocator, temp);
}
