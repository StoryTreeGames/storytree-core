const std = @import("std");

const super = @import("../menu.zig");

const Icon = @import("./icon.zig").Icon;
const Info = super.Info;
const Action = super.Action;
const Checkable = super.Checkable;
const Item = super.Item;

const windows = @import("windows");
const gdi = windows.win32.graphics.gdi;
const library_loader = windows.win32.system.library_loader;
const shell = windows.win32.ui.shell;
const windows_and_messaging = windows.win32.ui.windows_and_messaging;

const HWND = windows.win32.foundation.HWND;
const HMENU = windows_and_messaging.HMENU;
const HICON = windows_and_messaging.HICON;
const HINSTANCE = windows.win32.foundation.HINSTANCE;
const WM_USER = windows_and_messaging.WM_USER;
const NOTIFYICONDATAW = shell.NOTIFYICONDATAW;

const Shell_NotifyIconW = shell.Shell_NotifyIconW;
const NIM_ADD = shell.NIM_ADD;
const NIM_MODIFY = shell.NIM_MODIFY;
const NIM_DELETE = shell.NIM_DELETE;
const NIM_SETVERSION = shell.NIM_SETVERSION;
const NOTIFYICON_VERSION_4 = shell.NOTIFYICON_VERSION_4;

const CheckMenuItem = windows_and_messaging.CheckMenuItem;
const CheckMenuRadioItem = windows_and_messaging.CheckMenuRadioItem;

pub const HIcon = union(enum) {
    system: ?HICON,
    resource: ?HICON,

    pub fn handle(self: *const @This()) ?HICON {
        return switch (self.*) {
            .system => |h| h,
            .resource => |h| h,
        };
    }

    pub fn deinit(self: *const @This()) void {
        switch (self.*) {
            .resource => |h| _ = windows_and_messaging.DestroyIcon(h),
            else => {}
        }
    }
};

pub const Builder = struct {
    allocator: std.mem.Allocator,
    count: *usize,

    context: ?HMENU = null,
    current: HMENU,

    menus: *std.ArrayListUnmanaged(HMENU),
    itemToInfo: *std.AutoArrayHashMapUnmanaged(usize, Info),

    pub fn sub(self: *@This(), inner: HMENU) @This() {
        return .{
            .allocator = self.allocator,
            .count = self.count,
            .menus = self.menus,
            .itemToInfo = self.itemToInfo,
            .current = inner,
        };
    }

    pub fn appendSeparator(self: *@This()) !void {
        if (windows_and_messaging.AppendMenuA(self.current, windows_and_messaging.MF_SEPARATOR, 0, null) == 0) {
            return error.AppendMenuSeparator;
        }

        if (self.context) |context| {
            if (windows_and_messaging.AppendMenuA(context, windows_and_messaging.MF_SEPARATOR, 0, null) == 0) {
                return error.AppendMenuSeparator;
            }
        }
    }

    pub fn appendAction(self: *@This(), action: Action) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, action.label.len, 0);
        @memcpy(label, action.label);
        try self.itemToInfo.put(self.allocator, self.count.*, .{
            .id = action.id,
            .main = @ptrCast(self.current),
            .context = @ptrCast(self.context),
            .payload = .{ .action = .{ .label = label } },
        });

        if (windows_and_messaging.AppendMenuA(self.current, windows_and_messaging.MF_STRING, self.count.*, label.ptr) == 0) {
            return error.AppendMenuAction;
        }

        if (self.context) |context| {
            if (windows_and_messaging.AppendMenuA(context, windows_and_messaging.MF_STRING, self.count.*, label.ptr) == 0) {
                return error.AppendMenuAction;
            }
        }
    }

    pub fn appendToggle(self: *@This(), checkable: Checkable) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, checkable.label.len, 0);
        @memcpy(label, checkable.label);
        try self.itemToInfo.put(self.allocator, self.count.*, .{
            .id = checkable.id,
            .main = @ptrCast(self.current),
            .context = @ptrCast(self.context),
            .payload = .{
                .toggle = .{ .label = label, .state = checkable.default },
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

        if (self.context) |context| {
            if (windows_and_messaging.AppendMenuA(
                context,
                if (checkable.default) windows_and_messaging.MF_CHECKED else windows_and_messaging.MF_UNCHECKED,
                self.count.*,
                label.ptr,
            ) == 0) {
                return error.AppendMenuToggle;
            }
        }
    }

    pub fn appendRadioGroup(self: *@This(), items: []const Checkable) !void {
        const start = self.count.* + 1;
        const end = start + items.len;

        var checked: ?usize = null;
        for (items, start..) |item, i| {
            try self.appendRadioItem(item, start, end);
            if (item.default) checked = i;
        }

        if (checked) |idx| {
            _ = CheckMenuRadioItem(self.current, @intCast(start), @intCast(end), @intCast(idx), 0x0);
        }
    }

    pub fn appendRadioItem(self: *@This(), checkable: Checkable, start: usize, end: usize) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, checkable.label.len, 0);
        @memcpy(label, checkable.label);
        try self.itemToInfo.put(self.allocator, self.count.*, .{
            .id = checkable.id,
            .main = @ptrCast(self.current),
            .context = @ptrCast(self.context),
            .payload = .{
                .radio = .{
                    .group = .{ start, end },
                    .label = label,
                },
            },
        });

        if (windows_and_messaging.AppendMenuA(
            self.current,
            windows_and_messaging.MF_BYCOMMAND,
            self.count.*,
            label.ptr,
        ) == 0) {
            return error.AppendMenuRadioItem;
        }

        if (self.context) |context| {
            if (windows_and_messaging.AppendMenuA(
                context,
                windows_and_messaging.MF_BYCOMMAND,
                self.count.*,
                label.ptr,
            ) == 0) {
                return error.AppendMenuRadioItem;
            }
        }
    }

    pub fn appendMenu(self: *@This(), items: []const Item) !void {
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

                    if (self.context) |context| {
                        if (windows_and_messaging.AppendMenuA(
                            context,
                            windows_and_messaging.MF_POPUP,
                            @intFromPtr(innerMenu),
                            subMenu.label.ptr,
                        ) == 0) {
                            return error.AppendMenuSubmenu;
                        }
                    }

                    var inner = self.sub(innerMenu);
                    try inner.appendMenu(subMenu.items);
                },
            }
        }
    }
};

pub const MenuEvent = struct {
    id: u32,
    info: *Info,

    /// Select an item. This applies to radio and toggle items
    ///
    /// - `radio`: Will select the current item out of the list making it the currently selected option
    /// - `toggle`: Will toggle the current item inverting it's state. True is now false, and false is now true.
    pub fn select(self: *const @This()) void {
        switch (self.info.payload) {
            .toggle => |*ti| {
                ti.state = !ti.state;
                _ = CheckMenuItem(@ptrCast(@alignCast(self.info.main)), self.id, if (ti.state) 0x8 else 0x0);
                if (self.info.context) |context| {
                    _ = CheckMenuItem(@ptrCast(@alignCast(context)), self.id, if (ti.state) 0x8 else 0x0);
                }
            },
            .radio => |r| {
                _ = CheckMenuRadioItem(@ptrCast(@alignCast(self.info.main)), @intCast(r.group[0]), @intCast(r.group[1]), self.id, 0x0);
                if (self.info.context) |context| {
                    _ = CheckMenuRadioItem(@ptrCast(@alignCast(context)), @intCast(r.group[0]), @intCast(r.group[1]), self.id, 0x0);
                }
            },
            else => {},
        }
    }

    pub fn into(self: @This(), comptime T: type) T {
        return switch (@typeInfo(T)) {
            .@"enum" => @enumFromInt(self.info.id),
            .int => |i| switch (i.signedness) {
                .signed => @intCast(@as(i32, @bitCast(self.info.id))),
                .unsigned => @intCast(self.info.id)
            },
            else => @compileError("unsupported payload type")
        };
    }
};

pub const Menu = struct {
    arena: std.heap.ArenaAllocator,

    main: HMENU = undefined,
    context: HMENU = undefined,
    menus: std.ArrayListUnmanaged(HMENU) = .empty,
    item_to_info: std.AutoArrayHashMapUnmanaged(usize, Info) = .empty,

    /// Create a new menu.
    ///
    /// This does not display a menu but just initializes the resources
    /// needed for the menu.
    ///
    /// Instead of changing the items in the menu, the previous menu should
    /// be de-initialized and a new one should be initialized to replace it.
    pub fn init(allocator: std.mem.Allocator, menu: super.MenuOptions) !*@This() {
        var instance = try allocator.create(Menu);
        instance.* = .{
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
        errdefer instance.deinit();

        const a = instance.arena.allocator();

        instance.main = windows_and_messaging.CreateMenu().?;
        instance.context = windows_and_messaging.CreatePopupMenu().?;

        var count: usize = 0;
        var builder = Builder{
            .allocator = a,
            .context = instance.context,
            .current = instance.main,
            .menus = &instance.menus,
            .itemToInfo = &instance.item_to_info,
            .count = &count,
        };

        try builder.appendMenu(menu.items);

        return instance;
    }

    pub fn deinit(self: *@This()) void {
        defer self.arena.child_allocator.destroy(self);
        defer self.arena.deinit();

        for (self.menus.items) |m| _ = windows_and_messaging.DestroyMenu(m);

        _ = windows_and_messaging.DestroyMenu(self.main);
        _ = windows_and_messaging.DestroyMenu(self.context);
    }

    /// Attaches the menu to the specified window and calls platform specific APIs
    /// to render the menu.
    ///
    /// Most of the time the operating system will cleanup the menu rendered
    /// when the window it is attached to is destroyed. Call `detach` sooner if you
    /// want to remove it from the window and not display any menu.
    ///
    /// `detach` should be called if the menu calls `deinit` before the window is
    /// destroyed.
    pub fn attach(self: *const @This(), window: usize) !void {
        _ = windows_and_messaging.SetMenu(@ptrFromInt(window), self.main);
        _ = windows_and_messaging.DrawMenuBar(@ptrFromInt(window));
    }

    /// Removes the menu from the specified window.
    ///
    /// This does not free allocated menu resources. It will
    /// only remove it from the attached window which will stop
    /// rendering it.
    pub fn detach(_: *const @This(), window: usize) void {
        _ = windows_and_messaging.SetMenu(@ptrFromInt(window), null);
        _ = windows_and_messaging.DrawMenuBar(@ptrFromInt(window));
    }

    /// Transform an event id into the menu specific event
    pub fn transform(self: *const @This(), id: u32) ?MenuEvent {
        if (self.item_to_info.getPtr(id)) |info| {
            return .{ .id = id, .info = info };
        }
        return null;
    }

    /// Show the menu as a popup context menu at the specified location for the
    /// given window.
    pub fn popup(self: *const @This(), window: usize, x: i32, y: i32) ?MenuEvent {
        // _ = windows_and_messaging.SetForegroundWindow(self.handle);
        const handle: HWND = @ptrFromInt(window);
        const selected = windows_and_messaging.TrackPopupMenu(
            self.context,
            .{ .RIGHTBUTTON = 1, .RETURNCMD = 1 },
            x,
            y,
            0,
            handle,
            null,
        );
        _ = windows_and_messaging.PostMessageW(handle, windows_and_messaging.WM_NULL, 0, 0);

        return self.transform(@bitCast(selected));
    }

    /// Show the menu as a popup context menu where the cursor is currently
    /// located for the specified window.
    pub fn popupAtCursor(self: *const @This(), window: usize) ?MenuEvent {
        var pt: windows.win32.foundation.POINT = undefined;
        _ = windows_and_messaging.GetCursorPos(&pt);
        return self.popup(window, pt.x, pt.y);
    }
};

pub const SystemTrayEventHandler = struct {
    handler: *const fn (state: *anyopaque, tray: *const SystemTray, evt: super.SystemTrayEvent) void,
    state: *anyopaque,
};

pub const SystemTray = struct {
    arena: std.heap.ArenaAllocator,

    menu: ?*Menu = null,
    event_handler: ?SystemTrayEventHandler = null,

    tip_wide: ?[:0]const u16 = null,

    title: [:0]const u16 = undefined,
    class: [:0]const u16 = undefined,

    handle: ?HWND = null,
    instance: ?HINSTANCE = null,

    /// Initialize a system tray with a handler struct instance that is called when system tray events occur
    ///
    /// Ownership of the handler is transfered to the system tray and it is assigned to allocated memory.
    ///
    /// Use this when you want to handle the events assigning any state required to the handler instance.
    ///
    /// # Example
    ///
    /// ```zig
    /// SystemTray.initWithHandler(allocator, .{ .menu = menu }, struct {
    ///     event_loop: *EventLoop,
    ///     pub fn handler(self: *@This(), tray: *const SystemTray, event: SystemTrayEvent) void {
    ///         // ...
    ///     }
    /// }{ .event_loop = event_loop })
    /// ```
    ///
    /// or
    ///
    /// ```zig
    /// const SystemTrayHandler = struct {
    ///     event_loop: *EventLoop,
    ///     pub fn handler(self: *@This(), tray: *const SystemTray, event: SystemTrayEvent) void {
    ///         // ...
    ///     }
    /// }
    ///
    /// SystemTray.initWithHandler(allocator, .{ .menu = menu }, SystemTrayHandler{ .event_loop = event_loop })
    /// ```
    pub fn initWithHandler(allocator: std.mem.Allocator, tray: super.SystemTrayOptions, handler: anytype) !*@This() {
        const T = @TypeOf(handler);
        switch (@typeInfo(T)) {
            .@"struct" => if (!@hasDecl(T, "handler")) {
                @compileError("missing event handler method");
            },
            else => @compileError("handler must be a struct")
        }

        const Handler = &(struct {
            pub fn onevent(state: *anyopaque, systray: *const SystemTray, event: super.SystemTrayEvent) void {
                const this: *T = @ptrCast(@alignCast(state));
                @call(.auto, T.handler, .{ this, systray, event });
            }
        }).onevent;

        const self = try @This().init(allocator, tray);
        const handlerInstance = try self.arena.allocator().create(T);
        handlerInstance.* = handler;

        self.event_handler = .{
            .handler = Handler,
            .state = @ptrCast(handlerInstance)
        };

        return self;
    }

    /// Initialize the system tray.
    ///
    /// This will not handle any events as no event handler is initialized. Instead
    /// it is used to only display the system tray icon.
    pub fn init(allocator: std.mem.Allocator, tray: super.SystemTrayOptions) !*@This() {
        var instance = try allocator.create(SystemTray);
        instance.* = .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .menu = tray.menu,
        };
        errdefer instance.deinit();

        const allo = instance.arena.allocator();

        instance.title = try std.unicode.utf8ToUtf16LeAllocZ(allo, "");
        errdefer allo.free(instance.title);
        instance.class = try std.unicode.utf8ToUtf16LeAllocZ(allo, "menu-zig.system-tray");
        errdefer allo.free(instance.class);

        instance.instance = library_loader.GetModuleHandleW(null);
        const wnd_class = windows_and_messaging.WNDCLASSW{
            .lpszClassName = instance.class.ptr,

            .style = windows_and_messaging.WNDCLASS_STYLES{ .HREDRAW = 1, .VREDRAW = 1 },
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = null,

            .hInstance = instance.instance,
            .lpfnWndProc = wndProc, // wndProc,
        };

        const result = windows_and_messaging.RegisterClassW(&wnd_class);
        if (result == 0) {
            return error.SystemCreateWindow;
        }

        const window_style = windows_and_messaging.WINDOW_STYLE{
            .TABSTOP = 1,
            .GROUP = 1,
            .THICKFRAME = 1,
            .SYSMENU = 1,
            .DLGFRAME = 1,
            .BORDER = 1,
        };

        instance.handle = windows_and_messaging.CreateWindowExW(
            windows_and_messaging.WINDOW_EX_STYLE{},
            instance.class.ptr,
            instance.title.ptr,
            window_style, // style
            windows_and_messaging.CW_USEDEFAULT,
            windows_and_messaging.CW_USEDEFAULT, // initial position
            windows_and_messaging.CW_USEDEFAULT,
            windows_and_messaging.CW_USEDEFAULT, // initial size
            null, // Parent
            null, // Menu
            instance.instance,
            @ptrCast(instance), // WM_CREATE lpParam
        ) orelse return error.SystemCreateWindow;

        const ico = try Icon.init(instance.arena.allocator(), tray.icon);
        defer ico.deinit();

        var nid = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = instance.handle;
        nid.uID = WM_USER + 1;
        nid.uCallbackMessage = WM_USER + 1;
        nid.uFlags = .{ .MESSAGE = 1, .ICON = 1 };
        nid.hIcon = ico.handle();

        if (tray.tip) |tip| {
            instance.tip_wide = try std.unicode.utf8ToUtf16LeAllocZ(instance.arena.allocator(), tip);

            nid.uFlags.TIP = 1;
            nid.uFlags.SHOWTIP = 1;

            const tip_len = @min(instance.tip_wide.?.len, nid.szTip.len);
            @memcpy(nid.szTip[0..tip_len], instance.tip_wide.?[0..tip_len]);
            nid.szTip[tip_len] = 0;
        }

        _ = Shell_NotifyIconW(NIM_ADD, &nid);
        nid.Anonymous.uVersion = NOTIFYICON_VERSION_4;
        _ = Shell_NotifyIconW(NIM_SETVERSION, &nid);

        return instance;
    }

    /// Set the system tray's icon
    pub fn setIcon(self: *@This(), icon: @import("../icon.zig").Icon) !void {
        const ico = try Icon.init(self.arena.allocator(), icon);
        defer ico.deinit();

        var nid = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = self.handle;
        nid.uID = WM_USER + 1;
        nid.uFlags = .{ .MESSAGE = 1, .ICON = 1 };
        nid.hIcon = ico.handle();

        if (self.tip_wide) |tip| {
            nid.uFlags.TIP = 1;
            nid.uFlags.SHOWTIP = 1;

            const tip_len = @min(tip.len, nid.szTip.len);
            @memcpy(nid.szTip[0..tip_len], tip[0..tip_len]);
            nid.szTip[tip_len] = 0;
        }

        _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
    }

    /// Run `popoverAtCursor` for the provided menu on the SystemTray's window
    pub fn popover(self: *const @This(), menu: *const Menu) ?MenuEvent {
        return menu.popupAtCursor(@intFromPtr(self.handle));
    }

    /// Remove the system tray and cleanup all resources associated with it
    pub fn deinit(self: *@This()) void {
        defer self.arena.child_allocator.destroy(self);
        defer self.arena.deinit();

        var nid = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = self.handle;
        nid.uID = WM_USER + 1;
        _ = Shell_NotifyIconW(NIM_DELETE, &nid);

        _ = windows_and_messaging.DestroyWindow(self.handle);
    }

    fn handleEvent(self: *@This(), target: u32) void {
        if (target == windows_and_messaging.WM_CONTEXTMENU or target == windows_and_messaging.WM_RBUTTONUP) {
            if (self.menu) |menu| {
                if (menu.popupAtCursor(@intFromPtr(self.handle.?))) |evt| {
                    if (self.event_handler) |eh| {
                        eh.handler(eh.state, self, .{ .select = evt });
                    }
                }
            } else if (self.event_handler) |eh| {
                eh.handler(eh.state, self, .{ .click = .right });
            }
        } else if (target == windows_and_messaging.WM_LBUTTONUP) {
            if (self.event_handler) |eh| {
                eh.handler(eh.state, self, .{ .click = .left });
            }
        }
    }
};

fn wndProc(
    hwnd: HWND,
    uMsg: u32,
    wparam: windows.win32.foundation.WPARAM,
    lparam: windows.win32.foundation.LPARAM,
) callconv(.winapi) windows.win32.foundation.LRESULT {
    if (uMsg == windows_and_messaging.WM_CREATE) {
        // Get CREATESTRUCTW pointer from lparam
        const lpptr: usize = @intCast(lparam);
        const create_struct: *windows_and_messaging.CREATESTRUCTA = @ptrFromInt(lpptr);

        // If lpCreateParams exists then assign window data/state
        if (create_struct.lpCreateParams) |create_params| {
            // Cast from anyopaque to an expected EventLoop
            // this includes casting the pointer alignment
            const event_loop: *SystemTray = @ptrCast(@alignCast(create_params));
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
        const system_tray: ?*SystemTray = @ptrFromInt(lptr);

        switch (uMsg) {
            windows_and_messaging.WM_DESTROY => {
                _ = windows_and_messaging.DestroyWindow(hwnd);
                return 0;
            },
            windows_and_messaging.WM_USER + 1 => if (system_tray) |systray| {
                _ = windows_and_messaging.SetForegroundWindow(hwnd);
                const target: u32 = @bitCast(@as(i32, @intCast(@as(i16, @truncate(lparam)))));
                systray.handleEvent(target);
            },
            else => {},
        }

        return windows_and_messaging.DefWindowProcW(hwnd, uMsg, wparam, lparam);
    }

    return 0;
}
