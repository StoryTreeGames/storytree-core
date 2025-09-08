const std = @import("std");

const windows = @import("windows");
const win32 = windows.win32;

const com = win32.system.com;
const ole = win32.system.ole;
const shell = win32.ui.shell;
const gdi = win32.graphics.gdi;
const windows_and_messaging = win32.ui.windows_and_messaging;
const foundation = win32.foundation;
const structured_storage = win32.storage.structured_storage;
const security = win32.security;
const data_exchange = win32.system.data_exchange;

const IUnknown = com.IUnknown;
const IID_IUnknown = com.IID_IUnknown;
const IDataObject = com.IDataObject;
const IDropTarget = ole.IDropTarget;
const IDropTargetHelper = shell.IDropTargetHelper;
const CLSID_DragDropHelper = shell.CLSID_DragDropHelper;

const HWND = foundation.HWND;
const HRESULT = foundation.HRESULT;
const Guid = windows.Guid;

const DROPEFFECT_NONE: i32 = 0x0;
const DROPEFFECT_COPY: i32 = 0x1;
const DROPEFFECT_MOVE: i32 = 0x2;
const DROPEFFECT_LINK: i32 = 0x4;
const DROPEFFECT_SCROLL: i32 = 0x8000000;

const DVASPECT_CONTENT = com.DVASPECT_CONTENT;
const TYMED_HGLOBAL = com.TYMED_HGLOBAL;
const TYMED = com.TYMED;
const CLIPBOARD_FORMATS = win32.system.system_services.CLIPBOARD_FORMATS;

const FORMATETC = com.FORMATETC;
const STGMEDIUM = com.STGMEDIUM;

const RegisterDragDrop = ole.RegisterDragDrop;
const RevokeDragDrop = ole.RevokeDragDrop;
const OleInitialize = ole.OleInitialize;
const OleUninitialize = ole.OleUninitialize;
const CoInitializeEx = com.CoInitializeEx;
const CoUninitialize = com.CoUninitialize;

const GlobalLock = win32.system.memory.GlobalLock;
const GlobalUnlock = win32.system.memory.GlobalUnlock;
const GlobalSize = win32.system.memory.GlobalSize;
const DragQueryFileW = shell.DragQueryFileW;
const DragFinish = shell.DragFinish;

const L = std.unicode.utf8ToUtf16LeStringLiteral;
const print = std.debug.print;

const DropEffect = enum { none, move, copy, link, scroll };

const DragKeyState = struct {
    left: bool = false,
    middle: bool = false,
    right: bool = false,
    x1: bool = false,
    x2: bool = false,
    control: bool = false,
    shift: bool = false,
};

pub const FormatSet = std.StringArrayHashMapUnmanaged(void);

const DragDropContext = extern struct {
    enter: ?*anyopaque = null,
    over: ?*anyopaque = null,
    drop: ?*anyopaque = null, // TODO: Add way for user to process the data
    leave: ?*anyopaque = null,

    pub fn onEnter(self: *const @This(), state: ?*anyopaque, point: core.Point(u32), key_state: DragKeyState) DropEffect {
        if (self.enter) |c| {
            const callback: OnEnter = @ptrCast(@alignCast(c));
            return callback(state, point, key_state) catch .none;
        }
        return .none;
    }

    pub fn onOver(self: *const @This(), state: ?*anyopaque, point: core.Point(u32), key_state: DragKeyState) DropEffect {
        if (self.over) |c| {
            const callback: OnOver = @ptrCast(@alignCast(c));
            return callback(state, point, key_state) catch .none;
        }
        return .none;
    }

    pub fn onDrop(self: *const @This(), state: ?*anyopaque, point: core.Point(u32), key_state: DragKeyState, data: DropData) DropEffect {
        if (self.drop) |c| {
            const callback: OnDrop = @ptrCast(@alignCast(c));
            return callback(state, point, key_state, data) catch .none;
        }
        return .none;
    }

    pub fn onLeave(self: *const @This(), state: ?*anyopaque) void {
        if (self.leave) |c| {
            const callback: OnLeave = @ptrCast(@alignCast(c));
            callback(state) catch {};
        }
    }

    pub const OnEnter = *const fn (state: ?*anyopaque, point: core.Point(u32), key_state: DragKeyState) anyerror!DropEffect;
    pub const OnOver = *const fn (state: ?*anyopaque, point: core.Point(u32), key_state: DragKeyState) anyerror!DropEffect;
    pub const OnDrop = *const fn (state: ?*anyopaque, point: core.Point(u32), key_state: DragKeyState, data: DropData) anyerror!DropEffect;
    pub const OnLeave = *const fn (state: ?*anyopaque) anyerror!void;
};

fn getDataHGLOBAL(dobj: *IDataObject, cf: u16) ?STGMEDIUM {
    var fmt = FORMATETC{ .cfFormat = cf, .ptd = null, .dwAspect = @intFromEnum(DVASPECT_CONTENT), .lindex = -1, .tymed = @intFromEnum(TYMED.HGLOBAL) };
    var stg = std.mem.zeroes(STGMEDIUM);
    if (dobj.GetData(&fmt, &stg) != 0) return null;
    if (stg.tymed != @as(u32, @intFromEnum(TYMED.HGLOBAL))) {
        ole.ReleaseStgMedium(&stg);
        return null;
    }
    return stg; // caller must ReleaseStgMedium
}

fn hglobalToBytes(writer: *std.io.Writer, stg: *STGMEDIUM) void {
    const h = stg.Anonymous.hGlobal;
    const n = GlobalSize(h);
    if (n == 0) return;
    const p = GlobalLock(h) orelse return;
    defer _ = GlobalUnlock(h);

    _ = writer.writeAll(@as([*]const u8, @ptrCast(p))[0..n]) catch {};
}

fn hglobalToBytesOwned(allocator: std.mem.Allocator, stg: *STGMEDIUM) ?[]const u8 {
    const h = stg.Anonymous.hGlobal;
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

/// Supported MIME Types:
///   - text/plain
///   - text/uri-list
///   - text/html
///   - image/bmp
///   - image/png
///   - application/x-virtual-files
const DropDataResolver = struct {
    pub fn streamBytes(writer: *std.io.Writer, allocator: std.mem.Allocator, state: *anyopaque, ty: u16) void {
        const obj: *IDataObject = @ptrCast(@alignCast(state));

        // TODO: "application/x-virtual-files"
        if (ty == 0) {
            if (hasFormat(obj, CF_HDROP)) {
                getFiles(obj, allocator, writer);
            } else {
                getUrl(obj, writer);
            }
        } else {
            var stg = getDataHGLOBAL(obj, ty) orelse return;
            defer ole.ReleaseStgMedium(&stg);
            hglobalToBytes(writer, &stg);
        }
    }

    pub fn getBytes(allocator: std.mem.Allocator, state: *anyopaque, ty: u16) ?DropData.Data {
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

    pub fn getText(allocator: std.mem.Allocator, state: *anyopaque) ?DropData.Data {
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

    pub fn getUrlList(allocator: std.mem.Allocator, state: *anyopaque) ?DropData.Data {
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

    pub fn getHtml(allocator: std.mem.Allocator, state: *anyopaque) ?DropData.Data {
        const obj: *IDataObject = @ptrCast(@alignCast(state));
        var stg = getDataHGLOBAL(obj, CFSTR_HTMLFORMAT()) orelse return null;
        defer ole.ReleaseStgMedium(&stg);
        const bytes = hglobalToBytesOwned(allocator, &stg) orelse return null;

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

    fn collectFormats(allocator: std.mem.Allocator, state: *anyopaque) !std.StringArrayHashMapUnmanaged(u16) {
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

const DropData = struct {
    _state: ?*anyopaque,
    _allocator: std.mem.Allocator,
    mime_to_format: std.StringArrayHashMapUnmanaged(u16),

    pub const Data = struct {
        __a: std.mem.Allocator,
        value: []const u8,
        pub fn deinit(self: @This()) void {
            self.__a.free(self.value);
        }
    };

    pub fn init(allocator: std.mem.Allocator, instance: ?*anyopaque) @This() {
        if (instance) |data| {
            return .{
                ._allocator = allocator,
                ._state = instance,
                .mime_to_format = DropDataResolver.collectFormats(allocator, data) catch .empty,
            };
        } else {
            return .{
                ._allocator = allocator,
                ._state = instance,
                .mime_to_format = .empty,
            };
        }
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.mime_to_format.deinit(allocator);
    }

    pub fn contains(self: *const @This(), mime: []const u8) bool {
        return self.mime_to_format.contains(mime);
    }

    pub fn mime_types(self: *const @This()) []const []const u8 {
        return self.mime_to_format.keys();
    }

    pub fn streamBytes(self: *const @This(), mime: []const u8, writer: *std.io.Writer) void {
        if (self._state) |state| {
            DropDataResolver.streamBytes(
                writer,
                self._allocator,
                state,
                self.mime_to_format.get(mime) orelse 0,
            );
            writer.flush() catch {};
        }
    }

    pub fn getBytes(self: *const @This(), mime: []const u8) ?DropData.Data {
        if (self._state) |state| {
            return DropDataResolver.getBytes(
                self._allocator,
                state,
                self.mime_to_format.get(mime) orelse 0,
            );
        }
        return null;
    }

    pub fn getText(self: *const @This()) ?DropData.Data {
        if (self._state) |state| {
            return DropDataResolver.getText(self._allocator, state);
        }
        return null;
    }

    pub fn getUrlList(self: *const @This()) ?DropData.Data {
        if (self._state) |state| {
            return DropDataResolver.getUrlList(self._allocator, state);
        }
        return null;
    }

    pub fn getHtml(self: *const @This()) ?DropData.Data {
        if (self._state) |state| {
            return DropDataResolver.getHtml(self._allocator, state);
        }
        return null;
    }
};

const DropTarget = struct {
    allocator: std.mem.Allocator,
    context: DragDropContext,
    state: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator, context: Context) @This() {
        return .{
            .allocator = allocator,
            .context = .{
                .enter = @ptrCast(@constCast(context.enter)),
                .over = @ptrCast(@constCast(context.over)),
                .drop = @ptrCast(@constCast(context.drop)),
                .leave = @ptrCast(@constCast(context.leave)),
            },
        };
    }

    pub fn initWithState(allocator: std.mem.Allocator, context: Context, state: anytype) @This() {
        return .{ .allocator = allocator, .context = .{
            .enter = @ptrCast(@constCast(context.enter)),
            .over = @ptrCast(@constCast(context.over)),
            .drop = @ptrCast(@constCast(context.drop)),
            .leave = @ptrCast(@constCast(context.leave)),
        }, .state = @ptrCast(state) };
    }

    pub const Context = struct {
        enter: ?DragDropContext.OnEnter = null,
        over: ?DragDropContext.OnOver = null,
        drop: ?DragDropContext.OnDrop = null,
        leave: ?DragDropContext.OnLeave = null,
    };
};

const DropTargetHandler = extern struct {
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
        if (hr != 0) return windows.core.hresultToError(hr).err;
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

const CF_UNICODETEXT: u16 = @intFromEnum(win32.system.system_services.CF_UNICODETEXT);
const CF_TEXT: u16 = @intFromEnum(win32.system.system_services.CF_UNICODETEXT);
const CF_HDROP: u16 = @intFromEnum(win32.system.system_services.CF_HDROP);
const CF_DIB: u16 = @intFromEnum(win32.system.system_services.CF_DIB);
const CF_DIBV5: u16 = @intFromEnum(win32.system.system_services.CF_DIBV5);

const core = @import("storytree-core");
const event = core.event;
const input = core.input;

const Window = @import("storytree-core").Window;
const EventLoop = event.EventLoop;
const Event = event.Event;

pub fn handleEvent(event_loop: *EventLoop, window: *Window, evt: Event) !void {
    switch (evt) {
        .close => event_loop.closeWindow(window.id()),
        .key_input => |key_event| {
            std.debug.print("{any}\n", .{key_event.key});
        },
        else => {},
    }
}

fn onDrag(state: ?*anyopaque, point: core.Point(u32), key_state: DragKeyState) !DropEffect {
    _ = state;
    _ = point;

    if (key_state.control and key_state.shift) return .link;
    if (key_state.shift) return .move;
    return .copy;
}

fn onDrop(state: ?*anyopaque, point: core.Point(u32), key_state: DragKeyState, data: DropData) !DropEffect {
    _ = state;
    _ = point;

    // TODO: Virtual Files
    if (data.contains("text/uri-list")) {
        const stdout = std.fs.File.stdout();
        var buffer: [1024]u8 = undefined;
        var writer = stdout.writer(&buffer);

        std.debug.print("[URL List]\n", .{});
        data.streamBytes("text/uri-list", &writer.interface);
    } else if (data.contains("text/html")) {
        const stdout = std.fs.File.stdout();
        var buffer: [1024]u8 = undefined;
        var writer = stdout.writer(&buffer);

        std.debug.print("----- HTML -----\n", .{});
        data.streamBytes("text/html", &writer.interface);
        std.debug.print("\n", .{});
        std.debug.print("----- TEXT -----\n", .{});
        data.streamBytes("text/plain", &writer.interface);
    } else if (data.contains("text/plain")) {
        if (data.getText()) |text| {
            defer text.deinit();
            std.debug.print("[TEXT] {s}\n", .{text.value});
        }
    }

    if (key_state.control and key_state.shift) return .link;
    if (key_state.shift) return .move;
    return .copy;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = OleInitialize(null);
    defer OleUninitialize();

    var event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    const window = try event_loop.createWindow(.{
        .title = "Drag & Drop",
        .width = 800,
        .height = 600,
    });

    const hwnd = window.impl.handle;

    const drag_drop = DropTarget.init(allocator, .{
        .enter = onDrag,
        .over = onDrag,
        .drop = onDrop,
    });

    const handler = try DropTargetHandler.init(hwnd, &drag_drop);
    defer handler.deinit();

    const hr = RegisterDragDrop(hwnd, @ptrCast(handler));
    defer _ = RevokeDragDrop(hwnd);
    if (hr != 0) return windows.core.hresultToError(hr).err;

    while (event_loop.isActive()) {
        if (event_loop.poll()) |data| {
            try handleEvent(&event_loop, data.window, data.event);
        }
    }
}
