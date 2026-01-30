const std = @import("std");
const windows = @import("windows");
const win32 = windows.win32;
const core = @import("../root.zig");
const super = @import("../drag_drop.zig");

const DropData = super.DropData;
const DropTarget = super.DropTarget;
const Ref = super.Ref;

const com = win32.system.com;
const data_exchange = win32.system.data_exchange;
const foundation = win32.foundation;
const gdi = win32.graphics.gdi;
const security = win32.security;
const shell = win32.ui.shell;
const structured_storage = win32.storage.structured_storage;
const ole = win32.system.ole;
const windows_and_messaging = win32.ui.windows_and_messaging;

const CF_UNICODETEXT: u16 = @intFromEnum(win32.system.system_services.CF_UNICODETEXT);
const CF_TEXT: u16 = @intFromEnum(win32.system.system_services.CF_UNICODETEXT);
const CF_HDROP: u16 = @intFromEnum(win32.system.system_services.CF_HDROP);
const CF_DIB: u16 = @intFromEnum(win32.system.system_services.CF_DIB);
const CF_DIBV5: u16 = @intFromEnum(win32.system.system_services.CF_DIBV5);
const CLSID_DragDropHelper = shell.CLSID_DragDropHelper;
const DROPEFFECT_NONE: i32 = 0x0;
const DROPEFFECT_COPY: i32 = 0x1;
const DROPEFFECT_MOVE: i32 = 0x2;
const DROPEFFECT_LINK: i32 = 0x4;
const DROPEFFECT_SCROLL: i32 = 0x8000000;
const DVASPECT_CONTENT = com.DVASPECT_CONTENT;
const GMEM_MOVEABLE = win32.system.memory.GMEM_MOVEABLE;
const IID_IUnknown = com.IID_IUnknown;
const TYMED_HGLOBAL = com.TYMED_HGLOBAL;

const CLIPBOARD_FORMATS = win32.system.system_services.CLIPBOARD_FORMATS;
const FILEDESCRIPTORW = shell.FILEDESCRIPTORW;
const FORMATETC = com.FORMATETC;
const Guid = windows.Guid;
const HRESULT = foundation.HRESULT;
const HWND = foundation.HWND;
const IDataObject = com.IDataObject;
const IDropTarget = ole.IDropTarget;
const IDropTargetHelper = shell.IDropTargetHelper;
const ILockBytes = com.structured_storage.ILockBytes;
const ISequentialStream = com.ISequentialStream;
const IStream = com.IStream;
const IStorage = com.structured_storage.IStorage;
const IUnknown = com.IUnknown;
const TYMED = com.TYMED;
const STGC = com.STGC;
const STGM = com.structured_storage.STGM;
const STGMEDIUM = com.STGMEDIUM;

const CreateILockBytesOnHGlobal = com.structured_storage.CreateILockBytesOnHGlobal;
const CoInitializeEx = com.CoInitializeEx;
const CoUninitialize = com.CoUninitialize;
const DeleteFileW = win32.storage.file_system.DeleteFileW;
const DragQueryFileW = shell.DragQueryFileW;
const DragFinish = shell.DragFinish;
const GetTemptFileNameW = win32.storage.file_system.GetTempFileNameW;
const GetTempPathW = win32.storage.file_system.GetTempPathW;
const GlobalAlloc = win32.system.memory.GlobalAlloc;
const GlobalFree = win32.system.memory.GlobalFree;
const GlobalLock = win32.system.memory.GlobalLock;
const GlobalSize = win32.system.memory.GlobalSize;
const GlobalUnlock = win32.system.memory.GlobalUnlock;
const RegisterDragDrop = ole.RegisterDragDrop;
const RevokeDragDrop = ole.RevokeDragDrop;
const OleInitialize = ole.OleInitialize;
const OleUninitialize = ole.OleUninitialize;

const L = std.unicode.utf8ToUtf16LeStringLiteral;

fn getDataHGLOBAL(dobj: *IDataObject, cf: u16) ?STGMEDIUM {
    var fmt = FORMATETC{
        .cfFormat = cf,
        .ptd = null,
        .dwAspect = @intFromEnum(DVASPECT_CONTENT),
        .lindex = -1,
        .tymed = @intFromEnum(TYMED.HGLOBAL),
    };
    var stg = std.mem.zeroes(STGMEDIUM);
    if (dobj.GetData(&fmt, &stg) != 0) return null;
    if (stg.tymed != @as(u32, @intFromEnum(TYMED.HGLOBAL))) {
        ole.ReleaseStgMedium(&stg);
        return null;
    }
    return stg; // caller must ReleaseStgMedium
}

fn tryGetData(dobj: *const IDataObject, cf: u16, tymed: TYMED, idx: i32) ?STGMEDIUM {
    var fmt = FORMATETC{
        .cfFormat = cf,
        .ptd = null,
        .dwAspect = @intFromEnum(DVASPECT_CONTENT),
        .lindex = idx,
        .tymed = @bitCast(@intFromEnum(tymed)),
    };
    var stg = std.mem.zeroes(STGMEDIUM);
    // if (dobj.QueryGetData(&fmt) != 0) return null;
    if (dobj.GetData(&fmt, &stg) != 0) return null;
    if (stg.tymed != @as(u32, @bitCast(@intFromEnum(tymed)))) {
        ole.ReleaseStgMedium(&stg);
        return null;
    }
    return stg; // caller must ReleaseStgMedium
}

fn hglobalToBytes(writer: *std.io.Writer, h: isize) void {
    const n = GlobalSize(h);
    if (n == 0) return;
    const p = GlobalLock(h) orelse return;
    defer _ = GlobalUnlock(h);

    _ = writer.writeAll(@as([*]const u8, @ptrCast(p))[0..n]) catch {};
}

fn hglobalToBytesOwned(allocator: std.mem.Allocator, h: isize) ?[]const u8 {
    const n = GlobalSize(h);
    if (n == 0) return null;
    const p = GlobalLock(h) orelse return null;
    defer _ = GlobalUnlock(h);

    const out = allocator.alloc(u8, n) catch return null;
    @memcpy(out, @as([*]const u8, @ptrCast(p))[0..n]);
    return out;
}

fn hglobalUtf16ToUtf8(writer: *std.io.Writer, stg: *STGMEDIUM) void {
    const h = stg.Anonymous.hGlobal;
    const total = GlobalSize(h);
    if (total < 2) return;
    const p = GlobalLock(h) orelse return;
    defer _ = GlobalUnlock(h);

    const u16ptr: [*:0]const u16 = @ptrCast(@alignCast(p));
    const utf16Slice: []const u16 = std.mem.sliceTo(u16ptr, 0);

    var it = std.unicode.Utf16LeIterator.init(utf16Slice);
    var buff: [4]u8 = undefined;
    while (it.nextCodepoint() catch return) |cp| {
        const n = std.unicode.utf8Encode(cp, &buff) catch break;
        writer.writeAll(buff[0..n]) catch break;
    }
}

fn registerClipboardFormat(format: [:0]const u16) u16 {
    return @truncate(data_exchange.RegisterClipboardFormatW(format.ptr));
}

fn CFSTR_PNG() u16 {
    return registerClipboardFormat(L("PNG"));
}
fn CFSTR_HTMLFORMAT() u16 {
    return registerClipboardFormat(L("HTML Format"));
}
fn CFSTR_INETURLW() u16 {
    return registerClipboardFormat(L("UniformResourceLocatorW"));
}
fn CFSTR_FILEDESCRIPTORW() u16 {
    return registerClipboardFormat(L("FileGroupDescriptorW"));
}
fn CFSTR_FILECONTENTS() u16 {
    return registerClipboardFormat(L("FileContents"));
}

fn hasFormatExact(obj: *IDataObject, cf: u16, tymed: TYMED) bool {
    var fmt = FORMATETC{
        .cfFormat = @truncate(cf),
        .ptd = null,
        .dwAspect = @intFromEnum(DVASPECT_CONTENT),
        .lindex = -1,
        .tymed = tymed,
    };

    return obj.QueryGetData(&fmt) != 0;
}

fn hasFormat(dobj: *win32.system.com.IDataObject, cf: u16) bool {
    var fmt = FORMATETC{
        .cfFormat = cf,
        .ptd = null,
        .dwAspect = @intFromEnum(DVASPECT_CONTENT),
        .lindex = -1,
        .tymed = @intFromEnum(TYMED.HGLOBAL),
    };
    return dobj.QueryGetData(&fmt) == 0;
}

/// Supported MIME Types:
///   - text/plain
///   - text/uri-list
///   - text/html
///   - image/bmp
///   - image/png
///   - application/x-virtual-files
pub const DropDataResolver = struct {
    fn getUrl(data: *IDataObject, writer: *std.io.Writer) void {
        var stg = getDataHGLOBAL(data, CFSTR_INETURLW()) orelse return;
        defer ole.ReleaseStgMedium(&stg);
        hglobalUtf16ToUtf8(writer, &stg);
    }

    fn getFiles(data: *IDataObject, allocator: std.mem.Allocator, output: *std.io.Writer) void {
        var stg = getDataHGLOBAL(data, CF_HDROP) orelse return;
        defer ole.ReleaseStgMedium(&stg);

        const hdrop: shell.HDROP = @ptrFromInt(@as(usize, @bitCast(stg.Anonymous.hGlobal)));
        const count = DragQueryFileW(hdrop, 0xFFFFFFFF, null, 0);
        if (count == 0) return;

        for (0..count) |i| {
            const need = DragQueryFileW(hdrop, @intCast(i), null, 0) + 1;
            const tmp = allocator.allocSentinel(u16, need, 0) catch continue;
            defer allocator.free(tmp);
            _ = DragQueryFileW(hdrop, @intCast(i), tmp.ptr, need);

            if (i > 0) output.writeByte('\n') catch return;

            output.writeAll("file:///") catch break;
            var it = std.unicode.Utf16LeIterator.init(tmp[0..tmp.len]);
            var buff: [4]u8 = undefined;
            while (it.nextCodepoint() catch return) |cp| {
                const n = std.unicode.utf8Encode(cp, &buff) catch break;
                output.writeAll(buff[0..n]) catch break;
            }
        }
    }

    pub fn streamBytes(writer: *std.io.Writer, allocator: std.mem.Allocator, state: *anyopaque, ty: u16) void {
        const obj: *IDataObject = @ptrCast(@alignCast(state));

        // Skip virtual files as those are handled differently
        if (ty == CFSTR_FILEDESCRIPTORW()) return;

        if (ty == 0) {
            if (hasFormat(obj, CF_HDROP)) {
                getFiles(obj, allocator, writer);
            } else {
                getUrl(obj, writer);
            }
        } else {
            var stg = getDataHGLOBAL(obj, ty) orelse return;
            defer ole.ReleaseStgMedium(&stg);
            hglobalToBytes(writer, stg.Anonymous.hGlobal);
        }
    }

    pub fn getBytes(allocator: std.mem.Allocator, state: *anyopaque, ty: u16) ?Ref([]const u8) {
        var result = std.io.Writer.Allocating.init(allocator);
        defer result.deinit();
        const writer = &result.writer;

        streamBytes(writer, allocator, state, ty);

        writer.flush() catch {};
        return .{
            .value = result.toOwnedSlice() catch return null,
            .__a = allocator,
        };
    }

    pub fn getText(allocator: std.mem.Allocator, state: *anyopaque) ?Ref([]const u8) {
        const obj: *IDataObject = @ptrCast(@alignCast(state));
        var stg = getDataHGLOBAL(obj, CF_UNICODETEXT) orelse return null;
        defer ole.ReleaseStgMedium(&stg);

        var result = std.io.Writer.Allocating.init(allocator);
        defer result.deinit();
        const writer = &result.writer;

        hglobalUtf16ToUtf8(writer, &stg);

        writer.flush() catch {};
        return .{
            .value = result.toOwnedSlice() catch return null,
            .__a = allocator,
        };
    }

    pub fn getUrlList(allocator: std.mem.Allocator, state: *anyopaque) ?Ref([]const u8) {
        const obj: *IDataObject = @ptrCast(@alignCast(state));
        var result = std.io.Writer.Allocating.init(allocator);
        defer result.deinit();
        const writer = &result.writer;

        if (hasFormat(obj, CF_HDROP)) {
            getFiles(obj, allocator, writer);
        } else {
            getUrl(obj, writer);
        }

        writer.flush() catch {};
        return .{
            .value = result.toOwnedSlice() catch return null,
            .__a = allocator,
        };
    }

    pub fn getHtml(allocator: std.mem.Allocator, state: *anyopaque) ?Ref([]const u8) {
        const obj: *IDataObject = @ptrCast(@alignCast(state));
        var stg = getDataHGLOBAL(obj, CFSTR_HTMLFORMAT()) orelse return null;
        defer ole.ReleaseStgMedium(&stg);
        const bytes = hglobalToBytesOwned(allocator, stg.Anonymous.hGlobal) orelse return null;

        const start_tag = "<!--StartFragment-->";
        if (std.mem.indexOf(u8, bytes, start_tag)) |a| {
            if (std.mem.indexOf(u8, bytes, "<!--EndFragment-->")) |b| {
                defer allocator.free(bytes);
                return .{
                    .value = allocator.dupe(u8, bytes[a + start_tag.len .. b]) catch return null,
                    .__a = allocator,
                };
            }
        }

        const default: DropData.Data = .{
            .value = bytes,
            .__a = allocator,
        };

        // Fallback: attempt header offset fields
        const hdr = bytes;
        const s_off = std.mem.indexOf(u8, hdr, "StartFragment:") orelse return default;
        const e_off = std.mem.indexOf(u8, hdr, "EndFragment:") orelse return default;
        const s_val = std.fmt.parseInt(usize, hdr[s_off + 14 .. s_off + 14 + 10], 10) catch return default;
        const e_val = std.fmt.parseInt(usize, hdr[e_off + 12 .. e_off + 12 + 10], 10) catch return default;
        if (s_val < e_val and e_val <= bytes.len) {
            defer allocator.free(bytes);
            return .{
                .value = allocator.dupe(u8, bytes[s_val..e_val]) catch return null,
                .__a = allocator,
            };
        }

        // Return all bytes if parsing fails
        return default;
    }

    pub fn getVirtualFiles(allocator: std.mem.Allocator, state: *anyopaque) ?Ref([]const VirtualFile) {
        const obj: *IDataObject = @ptrCast(@alignCast(state));

        var stg = getDataHGLOBAL(obj, CFSTR_FILEDESCRIPTORW()) orelse return null;
        defer ole.ReleaseStgMedium(&stg);

        const p = GlobalLock(stg.Anonymous.hGlobal) orelse return null;
        defer _ = GlobalUnlock(stg.Anonymous.hGlobal);

        const count = @as(*const u32, @ptrCast(@alignCast(p))).*;
        const first_desc = @as([*]const FILEDESCRIPTORW, @ptrFromInt(@intFromPtr(p) + @sizeOf(u32)));
        var out: std.ArrayList(VirtualFile) = .empty;

        for (0..count) |i| {
            const fd = first_desc[i];
            const nm16: []const u16 = std.mem.span(@as([*:0]const u16, @ptrCast(@alignCast(&fd.cFileName))));
            const name = std.unicode.utf16LeToUtf8Alloc(allocator, nm16) catch continue;

            const has_size = fd.dwFlags & @as(u32, @intFromEnum(shell.FD_FLAGS.FILESIZE)) != 0;
            const sz: u64 = (@as(u64, fd.nFileSizeHigh) << 32) | fd.nFileSizeLow;
            out.append(allocator, .{
                .name = name,
                .size = if (has_size) sz else null,
                .index = @intCast(i),
                .__allocator = allocator,
                .__obj = obj,
            }) catch {
                allocator.free(name);
            };
        }

        return .{
            .value = out.toOwnedSlice(allocator) catch return null,
            .__a = allocator,
        };
    }

    pub fn collectFormats(allocator: std.mem.Allocator, state: *anyopaque) !std.StringArrayHashMapUnmanaged(u16) {
        const obj: *IDataObject = @ptrCast(@alignCast(state));
        var penum: ?*com.IEnumFORMATETC = null;
        if (obj.EnumFormatEtc(@intFromEnum(com.DATADIR_GET), &penum) != 0 or penum == null) return error.NoFormats;
        defer _ = IUnknown.Release(@ptrCast(penum.?));

        var fetched: u32 = 0;
        var arr: [1]FORMATETC = undefined;
        var buff: [128:0]u16 = undefined;

        var result: std.StringArrayHashMapUnmanaged(u16) = .empty;

        while (penum.?.Next(1, &arr, &fetched) == 0 and fetched == 1) {
            const cf = arr[0].cfFormat;

            if (cf >= 1 and cf <= 18) {
                switch (@as(CLIPBOARD_FORMATS, @enumFromInt(cf))) {
                    .TEXT, .UNICODETEXT => try result.put(allocator, "text/plain", CF_TEXT),
                    .HDROP => try result.put(allocator, "text/uri-list", 0),
                    .DIB => try result.put(allocator, "image/bmp", CF_DIB),
                    .DIBV5 => try result.put(allocator, "image/bmp", CF_DIBV5),
                    else => {},
                }
                continue;
            }

            const n = data_exchange.GetClipboardFormatNameW(@intCast(cf), &buff, buff.len);
            if (n > 0) {
                const wide_slice = buff[0..@as(usize, @intCast(n))];
                if (std.mem.eql(u16, wide_slice, L("HTML Format"))) {
                    try result.put(allocator, "text/html", cf);
                } else if (std.mem.eql(u16, wide_slice, L("UniformResourceLocatorW"))) {
                    try result.put(allocator, "text/url-list", cf);
                } else if (std.mem.eql(u16, wide_slice, L("PNG"))) {
                    try result.put(allocator, "image/png", cf);
                } else if (std.mem.eql(u16, wide_slice, L("FileGroupDescriptorW")) or std.mem.eql(u16, wide_slice, L("FileContents"))) {
                    try result.put(allocator, "application/x-virtual-files", cf);
                }
                // TODO: way to convert into custom mime type
            }
        }

        return result;
    }
};

pub const VirtualFile = struct {
    name: []const u8,
    size: ?u64,
    index: u32,

    __allocator: std.mem.Allocator,
    __obj: *const IDataObject,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }

    pub fn stream(self: *const @This(), writer: *std.io.Writer) !void {
        if (tryGetData(self.__obj, CFSTR_FILECONTENTS(), TYMED.ISTREAM, @bitCast(self.index))) |stg| {
            defer ole.ReleaseStgMedium(@constCast(&stg));

            if (stg.Anonymous.pstm) |istream| {
                const seq: *ISequentialStream = @ptrCast(istream);

                var buffer: [1024 * 32]u8 = undefined;
                while (true) {
                    var read: u32 = 0;
                    if (seq.Read(&buffer, buffer.len, &read) != 0) return error.ReadFailed;
                    if (read == 0) break;
                    try writer.writeAll(buffer[0..read]);
                }
            }
        } else if (tryGetData(self.__obj, CFSTR_FILECONTENTS(), TYMED.ISTORAGE, @bitCast(self.index))) |stg| {
            defer ole.ReleaseStgMedium(@constCast(&stg));

            if (stg.Anonymous.pstg) |istorage| {
                var tmpdir16: [260:0]u16 = undefined;
                const dlen = GetTempPathW(tmpdir16.len, &tmpdir16);
                if (dlen == 0 or dlen > tmpdir16.len) return error.TempDir;

                var tmpfile16: [260]u16 = undefined;
                if (GetTemptFileNameW(&tmpdir16, L("DND"), 0, &tmpfile16) == 0) {
                    return error.TempFile;
                }

                var dst: ?*IStorage = null;
                const flags = STGM{ .CREATE = 1, .READWRITE = 1, .SHARE_EXCLUSIVE = 1 };
                var h = com.structured_storage.StgCreateDocfile(@ptrCast(&tmpfile16), flags, 0, &dst);
                if (h != 0 or dst == null) {
                    std.debug.print("0x{X}\n", .{@as(u32, @bitCast(h))});
                    return error.CreateDocfileILockBytes;
                }
                defer _ = DeleteFileW(@ptrCast(&tmpfile16));
                defer _ = IUnknown.Release(@ptrCast(dst.?));

                h = istorage.CopyTo(0, null, null, dst.?);
                if (h != 0) {
                    std.debug.print("0x{X}\n", .{@as(u32, @bitCast(h))});
                    return error.IStorageCopyTo;
                }
                _ = dst.?.Commit(STGC{});

                const path = std.mem.span(@as([*:0]const u16, @ptrCast(&tmpfile16)));
                const pathUtf8 = try std.unicode.utf16LeToUtf8Alloc(self.__allocator, path);
                defer self.__allocator.free(pathUtf8);

                const f = try std.fs.openFileAbsolute(pathUtf8, .{});
                defer f.close();

                var buffer: [1024]u8 = undefined;
                var reader = f.reader(&buffer);
                _ = try writer.sendFileAll(&reader, .unlimited);
            }
        } else if (tryGetData(self.__obj, CFSTR_FILECONTENTS(), TYMED.HGLOBAL, @bitCast(self.index))) |stg| {
            defer ole.ReleaseStgMedium(@constCast(&stg));
            hglobalToBytes(writer, stg.Anonymous.hGlobal);
        }
    }

    pub fn bytes(self: *const @This()) !Ref([]const u8) {
        var result = std.io.Writer.Allocating.init(self.__allocator);
        defer result.deinit();
        try self.stream(&result.writer);
        return try result.toOwnedSlice();
    }
};

pub const DropTargetHandler = extern struct {
    vtable: *const IDropTarget.VTable,
    ref_count: std.atomic.Value(u32),
    hwnd: HWND,
    helper: ?*IDropTargetHelper,

    // DropTarget
    target: *anyopaque,

    pub fn init(hwnd: HWND, target: *const DropTarget) !*@This() {
        const self = try std.heap.c_allocator.create(@This());
        self.* = .{ .vtable = &VTABLE, .ref_count = .init(1), .hwnd = hwnd, .helper = null, .target = @ptrCast(@constCast(target)) };

        var p: *IDropTargetHelper = undefined;
        const hr = com.CoCreateInstance(&CLSID_DragDropHelper, null, com.CLSCTX_INPROC_SERVER, shell.IID_IDropTargetHelper, @ptrCast(&p));
        if (hr != 0) try windows.core.hresultToError(hr);
        self.helper = p;

        return self;
    }

    /// Calls `Release` and discards ref count response
    ///
    /// This function or `Release` should be called once for every
    /// `init` or `AddRef` called.
    pub fn deinit(self: *@This()) void {
        _ = Release(@ptrCast(self));
    }

    pub fn AddRef(self: *const IUnknown) callconv(.winapi) u32 {
        const this: *@This() = @ptrCast(@constCast(self));
        return this.ref_count.fetchAdd(1, .seq_cst) + 1;
    }

    pub fn Release(self: *const IUnknown) callconv(.winapi) u32 {
        const this: *@This() = @ptrCast(@constCast(self));
        const prev = this.ref_count.fetchSub(1, .seq_cst);
        if (prev == 1) {
            if (this.helper) |h| _ = IUnknown.Release(@ptrCast(h));
            std.heap.c_allocator.destroy(this);
            return 0;
        }
        return prev -| 1;
    }

    pub fn QueryInterface(
        self: *const IUnknown,
        riid: *const Guid,
        ppv: **anyopaque,
    ) callconv(.winapi) HRESULT {
        if (std.mem.eql(u8, &riid.Bytes, &IID_IUnknown.Bytes) or
            std.mem.eql(u8, &riid.Bytes, &ole.IID_IDropTarget.Bytes))
        {
            ppv.* = @ptrCast(@constCast(self));
            _ = AddRef(self);
            return 0;
        }
        return -2147467262; // E_NOINTERFACE
    }

    /// Convert point from screen space to window space
    fn screenToWindow(self: *@This(), point: foundation.POINTL) core.Point(u32) {
        var bounds: foundation.RECT = undefined;
        _ = windows_and_messaging.GetWindowRect(self.hwnd, &bounds);
        return .{
            .y = @intCast(point.y -| bounds.top),
            .x = @intCast(point.x -| bounds.left),
        };
    }

    fn DragEnter(
        self: *const IDropTarget,
        pDataObj: ?*IDataObject,
        grfKeyState: u32,
        pt: foundation.POINTL,
        pdwEffect: ?*u32,
    ) callconv(.winapi) HRESULT {
        const this: *@This() = @ptrCast(@constCast(self));
        const target: *const DropTarget = @ptrCast(@alignCast(this.target));

        const effect = target.context.onEnter(
            target.state,
            this.screenToWindow(pt),
            .{
                .left = grfKeyState & windows_and_messaging.MK_LBUTTON != 0,
                .middle = grfKeyState & windows_and_messaging.MK_MBUTTON != 0,
                .right = grfKeyState & windows_and_messaging.MK_RBUTTON != 0,
                .x1 = grfKeyState & windows_and_messaging.MK_XBUTTON1 != 0,
                .x2 = grfKeyState & windows_and_messaging.MK_XBUTTON2 != 0,
                .control = grfKeyState & windows_and_messaging.MK_CONTROL != 0,
                .shift = grfKeyState & windows_and_messaging.MK_SHIFT != 0,
            },
        );
        if (pdwEffect) |e| e.* = switch (effect) {
            .none => DROPEFFECT_NONE,
            .copy => DROPEFFECT_COPY,
            .move => DROPEFFECT_MOVE,
            .link => DROPEFFECT_LINK,
            .scroll => DROPEFFECT_SCROLL,
        };

        if (this.helper) |h| {
            var p: foundation.POINT = .{ .x = pt.x, .y = pt.y };
            _ = h.DragEnter(this.hwnd, pDataObj, &p, if (pdwEffect) |e| e.* else 0);
        }
        return 0;
    }

    fn DragOver(
        self: *const IDropTarget,
        grfKeyState: u32,
        pt: foundation.POINTL,
        pdwEffect: ?*u32,
    ) callconv(.winapi) HRESULT {
        const this: *@This() = @ptrCast(@constCast(self));
        const target: *const DropTarget = @ptrCast(@alignCast(this.target));

        const effect = target.context.onOver(
            target.state,
            this.screenToWindow(pt),
            .{
                .left = grfKeyState & windows_and_messaging.MK_LBUTTON != 0,
                .middle = grfKeyState & windows_and_messaging.MK_MBUTTON != 0,
                .right = grfKeyState & windows_and_messaging.MK_RBUTTON != 0,
                .x1 = grfKeyState & windows_and_messaging.MK_XBUTTON1 != 0,
                .x2 = grfKeyState & windows_and_messaging.MK_XBUTTON2 != 0,
                .control = grfKeyState & windows_and_messaging.MK_CONTROL != 0,
                .shift = grfKeyState & windows_and_messaging.MK_SHIFT != 0,
            },
        );
        if (pdwEffect) |e| e.* = switch (effect) {
            .none => DROPEFFECT_NONE,
            .copy => DROPEFFECT_COPY,
            .move => DROPEFFECT_MOVE,
            .link => DROPEFFECT_LINK,
            .scroll => DROPEFFECT_SCROLL,
        };

        if (this.helper) |h| {
            var p: foundation.POINT = .{ .x = pt.x, .y = pt.y };
            _ = h.DragOver(
                &p,
                if (pdwEffect) |e| e.* else 0,
            );
        }
        return 0;
    }

    fn DragLeave(self: *const IDropTarget) callconv(.winapi) HRESULT {
        const this: *@This() = @ptrCast(@constCast(self));
        const target: *const DropTarget = @ptrCast(@alignCast(this.target));

        target.context.onLeave(target.state);
        if (this.helper) |h| {
            _ = h.DragLeave();
        }

        return 0;
    }

    fn Drop(
        self: *const IDropTarget,
        pDataObj: ?*IDataObject,
        grfKeyState: u32,
        pt: foundation.POINTL,
        pdwEffect: ?*u32,
    ) callconv(.winapi) HRESULT {
        const this: *@This() = @ptrCast(@constCast(self));

        const target: *const DropTarget = @ptrCast(@alignCast(this.target));
        var arena = std.heap.ArenaAllocator.init(target.allocator);
        defer arena.deinit();

        const data = DropData.init(arena.allocator(), pDataObj);

        const effect = target.context.onDrop(
            target.state,
            this.screenToWindow(pt),
            .{
                .left = grfKeyState & windows_and_messaging.MK_LBUTTON != 0,
                .middle = grfKeyState & windows_and_messaging.MK_MBUTTON != 0,
                .right = grfKeyState & windows_and_messaging.MK_RBUTTON != 0,
                .x1 = grfKeyState & windows_and_messaging.MK_XBUTTON1 != 0,
                .x2 = grfKeyState & windows_and_messaging.MK_XBUTTON2 != 0,
                .control = grfKeyState & windows_and_messaging.MK_CONTROL != 0,
                .shift = grfKeyState & windows_and_messaging.MK_SHIFT != 0,
            },
            data,
        );
        if (pdwEffect) |e| e.* = switch (effect) {
            .none => DROPEFFECT_NONE,
            .copy => DROPEFFECT_COPY,
            .move => DROPEFFECT_MOVE,
            .link => DROPEFFECT_LINK,
            .scroll => DROPEFFECT_SCROLL,
        };

        if (this.helper) |h| {
            var p: foundation.POINT = .{ .x = pt.x, .y = pt.y };
            _ = h.Drop(
                pDataObj,
                &p,
                if (pdwEffect) |e| e.* else 0,
            );
        }
        return 0;
    }

    const VTABLE = IDropTarget.VTable{
        .base = IUnknown.VTable{
            .QueryInterface = QueryInterface,
            .AddRef = AddRef,
            .Release = Release,
        },
        .DragEnter = DragEnter,
        .DragOver = DragOver,
        .DragLeave = DragLeave,
        .Drop = Drop,
    };
};
