const std = @import("std");
const win32 = @import("windows").win32;

const UISettings = @import("windows").UI.ViewManagement.UISettings;
const TypedEventHandler = @import("windows").Foundation.TypedEventHandler;
const IInspectable = @import("windows").Foundation.IInspectable;
const EventRegistrationToken = @import("windows").Foundation.EventRegistrationToken;

const windows_and_messaging = win32.ui.windows_and_messaging;
const graphics = win32.graphics;
const foundation = win32.foundation;
const keyboard_and_mouse = win32.ui.input.keyboard_and_mouse;
const zig = win32.zig;

const MenuInfo = @import("../menu.zig").Info;
const event = @import("../event.zig");
const input = @import("input.zig");
const util = @import("./util.zig");

const Window = @import("window.zig");
const WindowOptions = @import("../window.zig").Options;
const Modifiers = event.Modifiers;
const EventQueue = event.EventQueue;
const Event = event.Event;
const QueuedEvent = event.QueuedEvent;
const EventHandler = event.EventHandler;

const MSG = windows_and_messaging.MSG;
const GetMessageW = windows_and_messaging.GetMessageW;
const PeekMessageW = windows_and_messaging.PeekMessageW;
const TranslateMessage = windows_and_messaging.TranslateMessage;
const DispatchMessageW = windows_and_messaging.DispatchMessageW;
const CheckMenuItem = windows_and_messaging.CheckMenuItem;
const CheckMenuRadioItem = windows_and_messaging.CheckMenuRadioItem;
const PM_REMOVE = windows_and_messaging.PM_REMOVE;
const INFINITE = win32.system.windows_programming.INFINITE;
const QS_ALLINPUT = win32.ui.windows_and_messaging.QS_ALLINPUT;
const MWMO_INPUTAVAILABLE = win32.ui.windows_and_messaging.MWMO_INPUTAVAILABLE;

const VIRTUAL_KEY = keyboard_and_mouse.VIRTUAL_KEY;
const VK_CONTROL = keyboard_and_mouse.VK_CONTROL;
const VK_LCONTROL = keyboard_and_mouse.VK_LCONTROL;
const VK_RCONTROL = keyboard_and_mouse.VK_RCONTROL;
const VK_ALT = keyboard_and_mouse.VK_MENU;
const VK_LALT = keyboard_and_mouse.VK_LMENU;
const VK_RALT = keyboard_and_mouse.VK_RMENU;
const VK_SHIFT = keyboard_and_mouse.VK_SHIFT;
const VK_LSHIFT = keyboard_and_mouse.VK_LSHIFT;
const VK_RSHIFT = keyboard_and_mouse.VK_RSHIFT;
const HWND = foundation.HWND;

const PRESSED: u8 = 0b10000000;

arena: std.heap.ArenaAllocator,

windows: std.AutoArrayHashMapUnmanaged(usize, *Window),
queue: EventQueue,

ui_settings: *UISettings,
theme_change_handler: struct {
    instance: *TypedEventHandler(UISettings, IInspectable),
    handle: EventRegistrationToken,
},

pub fn init(allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    errdefer allocator.destroy(self);

    self.arena = std.heap.ArenaAllocator.init(allocator);
    self.queue = .{ .allocator = self.arena.allocator() };
    self.windows = .empty;

    self.ui_settings = try UISettings.init();
    errdefer self.ui_settings.deinit();

    const cvc_handler = try TypedEventHandler(UISettings, IInspectable).initWithState(handleThemeChange, self);
    errdefer cvc_handler.deinit();
    const cvc_handle = try self.ui_settings.addColorValuesChanged(cvc_handler);

    self.theme_change_handler = .{
        .instance = cvc_handler,
        .handle = cvc_handle,
    };

    return self;
}

pub fn deinit(self: *@This()) void {
    const parent = self.arena.child_allocator;
    const allocator = self.arena.allocator();
    for (self.windows.values()) |window| {
        window.deinit();
    }

    // Remove listener for color change in ui settings
    self.ui_settings.removeColorValuesChanged(self.theme_change_handler.handle) catch {};
    self.theme_change_handler.instance.deinit();
    self.ui_settings.deinit();

    self.windows.deinit(allocator);
    self.queue.deinit();
    self.arena.deinit();
    parent.destroy(self);
}

pub fn setAppId(self: *@This(), app_id: []const u8) !void {
    const allocator = self.arena.allocator();

    const wid: [:0]const u16 = try std.unicode.utf8ToUtf16LeAllocZ(allocator, app_id);
    defer allocator.free(wid);

    if (util.SetCurrentProcessExplicitAppUserModelID(wid.ptr) != util.S_OK) return error.UnknownError;
}

pub fn createWindow(self: *@This(), opts: WindowOptions) !*Window {
    const allocator = self.arena.allocator();

    const win = try Window.init(allocator, self, opts);
    try self.windows.put(allocator, win.id(), win);

    return win;
}

pub fn closeWindow(self: *@This(), id: usize) void {
    if (self.windows.fetchSwapRemove(id)) |win| {
        win.value.deinit();
    }
}

pub fn isActive(self: *const @This()) bool {
    return self.windows.count() > 0;
}

/// Attempt to get the next `WindowEvent` in the queue.
///
/// This will skip events for windows that no longer exist
pub fn pop(self: *@This()) ?Event {
    switch (self.queue.pop() orelse return null) {
        .theme => |theme| return .{ .theme = theme },
        .destroy => |key| if (self.windows.fetchSwapRemove(key)) |window| {
            window.value.deinit();
        },
        .window => |we| if (self.windows.get(we.target)) |window| {
            return .{
                .window = .{
                    .target = window,
                    .event = we.event,
                },
            };
        },
    }
    return null;
}

pub fn handleEvent(self: *@This(), args: std.meta.Tuple(&.{ HWND, u32, usize, isize })) bool {
    const winId = @intFromPtr(args[0]);
    if (self.windows.get(winId)) |win| {
        if (parseEvent(self, win, args)) |evt| {
            self.queue.append(evt) catch return false;
            return true;
        }
    }
    return false;
}

/// Poll for events draining all queued window events
///
/// This will translate all events and append them to the event loops queue.
///
/// The choice to drain all currently queued events comes from how linux (wayland) dispatches
/// all queued events regardless of blocking or not.
pub fn poll(_: *@This()) !void {
    var message: MSG = undefined;
    while (PeekMessageW(&message, null, 0, 0, PM_REMOVE) != 0) {
        if (message.message == windows_and_messaging.WM_QUIT) break;
        _ = TranslateMessage(&message);
        _ = DispatchMessageW(&message);
    }
}

/// Block the event loop until the next event draining all queued window events
///
/// This will translate all events and append them to the event loops queue.
pub fn wait(_: *@This()) !void {
    // Use this to wait for messages to avoid a problem with GetMessageW
    // not waking when no app windows are focused
    _ = win32.ui.windows_and_messaging.MsgWaitForMultipleObjectsEx(
        0,
        null,
        INFINITE,
        QS_ALLINPUT,
        MWMO_INPUTAVAILABLE,
    );

    var message: MSG = undefined;
    // DRAIN PHASE: flush any follow-up messages triggered by the handler
    while (PeekMessageW(&message, null, 0, 0, PM_REMOVE) != 0) {
        if (message.message == windows_and_messaging.WM_QUIT) break;
        _ = TranslateMessage(&message);
        _ = DispatchMessageW(&message);
    }
}

pub fn toggleMenuItem(id: u32, item: *MenuInfo, state: bool) void {
    switch (item.payload) {
        .toggle => {
            _ = CheckMenuItem(@ptrCast(@alignCast(item.menu)), id, if (state) 0x8 else 0x0);
        },
        .radio => |r| {
            _ = CheckMenuRadioItem(@ptrCast(@alignCast(item.menu)), @intCast(r.group[0]), @intCast(r.group[0]), id, 0x0);
        },
        else => {},
    }
}

fn getKeyboardState(keyboard: *[256]u8) void {
    _ = keyboard_and_mouse.GetKeyboardState(keyboard);
}

fn anyKeySet(keyboard: *const [256]u8, keys: []const VIRTUAL_KEY) bool {
    for (keys) |key| {
        if (key == keyboard_and_mouse.VK_CAPITAL or key == keyboard_and_mouse.VK_NUMLOCK) {
            if (keyboard[@intFromEnum(key)] & 1 == 1) return true;
        } else if (keyboard[@intFromEnum(key)] & PRESSED == PRESSED) return true;
    }
    return false;
}

fn getModifiers(keyboard: *const [256]u8) Modifiers {
    var modifiers: Modifiers = .{};
    if (anyKeySet(keyboard, &[3]VIRTUAL_KEY{ VK_CONTROL, VK_LCONTROL, VK_RCONTROL })) {
        modifiers.ctrl = true;
    }
    if (anyKeySet(keyboard, &[3]VIRTUAL_KEY{ VK_ALT, VK_LALT, VK_RALT })) {
        modifiers.alt = true;
    }
    if (anyKeySet(keyboard, &[3]VIRTUAL_KEY{ VK_SHIFT, VK_LSHIFT, VK_RSHIFT })) {
        modifiers.shift = true;
    }

    return modifiers;
}

const EventArgs = std.meta.Tuple(&.{ foundation.HWND, u32, usize, isize });

pub fn parseWindowId(args: EventArgs) usize {
    return @intFromPtr(args[0]);
}

var resize: ?util.RECT = null;
pub fn parseEvent(ev: *@This(), win: *Window, args: EventArgs) ?QueuedEvent {
    const hwnd: foundation.HWND, const message: u32, const wparam: usize, const lparam: isize = args;
    _ = hwnd;

    switch (message) {
        // Request to close the window
        windows_and_messaging.WM_CLOSE => {
            return .{ .window = .{ .target = @intFromPtr(args[0]), .event = .close } };
        },
        windows_and_messaging.WM_SYSCOMMAND => {
            if ((wparam & 0xFFF0) == windows_and_messaging.SC_CLOSE)
                return .{ .window = .{ .target = @intFromPtr(args[0]), .event = .close } };
        },
        windows_and_messaging.WM_DESTROY => {
            return .{ .destroy = @intFromPtr(args[0]) };
        },
        windows_and_messaging.WM_SETCURSOR => {
            // Set user defined cursor when the mouse moves within the window
            _ = windows_and_messaging.SetCursor(Window.getHCursor(win.cursor));

            // Allow for resize cursor to be drawn if cursor is at correct position
            // return windows_and_messaging.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        util.WM_TRAYICON => {
            const mouse: u32 = @bitCast(@as(i32, @intCast((@as(i16, @truncate(lparam))))));
            if (mouse == windows_and_messaging.WM_CONTEXTMENU or mouse == windows_and_messaging.WM_RBUTTONUP) {
                const selected = win.showSystemTray();
                const menu_item = win.item_to_systray.getPtr(selected);
                if (menu_item) |info| {
                    return .{ .window = .{
                        .target = @intFromPtr(args[0]),
                        .event = .{
                            .system_tray = .{
                                .id = selected,
                                .item = info,
                            },
                        },
                    } };
                }
            } else if (mouse == windows_and_messaging.WM_LBUTTONUP) {
                win.systemTrayOnClick(ev, win);
            }
        },
        windows_and_messaging.WM_COMMAND => {
            const wmId: u16 = @truncate(wparam);
            const wmEvent: u16 = @truncate(wparam >> 16);
            if (wmEvent == 0) {
                const menu_info = win.item_to_menubar.getPtr(@intCast(wmId));
                if (menu_info) |info| {
                    return .{ .window = .{
                        .target = @intFromPtr(args[0]),
                        .event = .{
                            .menu = .{
                                .id = @intCast(wmId),
                                .item = info,
                            },
                        },
                    } };
                }
            } else if (wmEvent == 0x1800) {
                return .{ .window = .{
                    .target = @intFromPtr(args[0]),
                    .event = .{
                        .thumb = @intCast(wmId),
                    },
                } };
            }
        },
        // Keyboard input events
        windows_and_messaging.WM_CHAR, windows_and_messaging.WM_SYSCHAR => {
            const scan_code: u32 = @as(u32, @intCast(lparam >> 16)) & 0xFF;
            const virtual_key: u32 = keyboard_and_mouse.MapVirtualKeyW(scan_code, windows_and_messaging.MAPVK_VSC_TO_VK);

            var keyboard: [256]u8 = [_]u8{0} ** 256;
            getKeyboardState(&keyboard);

            const modifiers: Modifiers = getModifiers(&keyboard);

            // Reset keyboard state for modifiers so they aren't processed with `ToUnicode`
            keyboard[@intFromEnum(keyboard_and_mouse.VK_CONTROL)] = 0;
            // keyboard[@intFromEnum(keyboard_and_mouse.VK_SHIFT)] = 0;
            keyboard[@intFromEnum(keyboard_and_mouse.VK_MENU)] = 0;
            keyboard[@intFromEnum(keyboard_and_mouse.VK_LCONTROL)] = 0;
            // keyboard[@intFromEnum(keyboard_and_mouse.VK_LSHIFT)] = 0;
            keyboard[@intFromEnum(keyboard_and_mouse.VK_LMENU)] = 0;
            keyboard[@intFromEnum(keyboard_and_mouse.VK_RCONTROL)] = 0;
            // keyboard[@intFromEnum(keyboard_and_mouse.VK_RSHIFT)] = 0;
            keyboard[@intFromEnum(keyboard_and_mouse.VK_RMENU)] = 0;

            var buffer: [3:0]u16 = [_:0]u16{0} ** 3;
            const result = keyboard_and_mouse.ToUnicodeEx(virtual_key, scan_code, &keyboard, &buffer, 3,
                // Set it to not modify keyboard state. Windows 1607 and above
                0b100, keyboard_and_mouse.GetKeyboardLayout(0));

            // TODO: If dead key then store for later and combine with next char/key input
            if (result == 0) {
                std.log.debug("[{d}] ToUnicode failed", .{result});
            } else if (result < 0) {
                std.log.debug("[{d}] Dead key detected", .{result});
            } else {
                var data: [4]u8 = [_]u8{0} ** 4;
                _ = std.unicode.utf16LeToUtf8(&data, buffer[0..]) catch unreachable;

                if (data.len <= 4) {
                    return .{ .window = .{
                        .target = @intFromPtr(args[0]),
                        .event = .{
                            .key_input = .{
                                .key = .{ .char = data },
                                .modifiers = modifiers,
                                .state = .pressed,
                                .scan = scan_code,
                                .virtual = virtual_key,
                            },
                        },
                    } };
                }
            }
        },
        windows_and_messaging.WM_KEYDOWN => {
            if (input.codeToVirtualKey(wparam, lparam)) |key| {
                // Keyboard state to better match keyboard input with virtual keys
                var keyboard: [256]u8 = [_]u8{0} ** 256;
                getKeyboardState(&keyboard);

                const modifiers: Modifiers = getModifiers(&keyboard);

                return .{ .window = .{
                    .target = @intFromPtr(args[0]),
                    .event = .{
                        .key_input = .{
                            .key = .{ .virtual = key },
                            .modifiers = modifiers,
                            .state = .pressed,
                        },
                    },
                } };
            }
            // return windows_and_messaging.DefWindowProcW(hwnd, uMsg, wparam, lparam);
        },
        // MouseMove event
        windows_and_messaging.WM_MOUSEMOVE => {
            if (lparam >= 0) {
                const pos: usize = @intCast(lparam);
                const x: u16 = @truncate(pos);
                const y: u16 = @truncate(pos >> 16);
                return .{ .window = .{
                    .target = @intFromPtr(args[0]),
                    .event = .{
                        .mouse_move = .{ .x = x, .y = y },
                    },
                } };
            }
        },
        // Mouse scrolling events
        windows_and_messaging.WM_MOUSEWHEEL => {
            const params: isize = @intCast(wparam);
            const distance: i16 = @truncate(params >> 16);

            return .{ .window = .{
                .target = @intFromPtr(args[0]),
                .event = .{
                    .mouse_scroll = .{
                        .direction = .vertical,
                        .delta = distance,
                    },
                },
            } };
        },
        windows_and_messaging.WM_MOUSEHWHEEL => {
            const params: isize = @intCast(wparam);
            const distance: i16 = @truncate(params >> 16);

            return .{ .window = .{
                .target = @intFromPtr(args[0]),
                .event = .{
                    .mouse_scroll = .{
                        .direction = .horizontal,
                        .delta = distance,
                    },
                },
            } };
        },
        // Mouse button events == MouseInput
        windows_and_messaging.WM_LBUTTONDOWN => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{
                .mouse_input = .{ .state = .pressed, .button = .left },
            },
        } },
        windows_and_messaging.WM_LBUTTONUP => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{
                .mouse_input = .{ .state = .released, .button = .left },
            },
        } },
        windows_and_messaging.WM_MBUTTONDOWN => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{
                .mouse_input = .{ .state = .pressed, .button = .middle },
            },
        } },
        windows_and_messaging.WM_MBUTTONUP => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{
                .mouse_input = .{ .state = .released, .button = .middle },
            },
        } },
        windows_and_messaging.WM_RBUTTONDOWN => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{
                .mouse_input = .{ .state = .pressed, .button = .right },
            },
        } },
        windows_and_messaging.WM_RBUTTONUP => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{
                .mouse_input = .{ .state = .released, .button = .right },
            },
        } },
        windows_and_messaging.WM_XBUTTONDOWN => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{
                .mouse_input = .{
                    .state = .pressed,
                    .button = if ((wparam >> 16) & 0x0001 == 0x0001) .x1 else .x2,
                },
            },
        } },
        windows_and_messaging.WM_XBUTTONUP => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{
                .mouse_input = .{
                    .state = .released,
                    .button = if ((wparam >> 16) & 0x0001 == 0x0001) .x1 else .x2,
                },
            },
        } },
        // Check for focus and unfocus
        windows_and_messaging.WM_SETFOCUS => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{ .focused = true },
        } },
        windows_and_messaging.WM_KILLFOCUS => return .{ .window = .{
            .target = @intFromPtr(args[0]),
            .event = .{ .focused = false },
        } },
        windows_and_messaging.WM_SIZING => {
            const area: *util.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            resize = area.*;
        },
        windows_and_messaging.WM_EXITSIZEMOVE => {
            defer resize = null;
            if (resize) |dim| {
                return .{ .window = .{
                    .target = @intFromPtr(args[0]),
                    .event = .{
                        .resize = .{
                            .width = @bitCast(dim.right - dim.left),
                            .height = @bitCast(dim.bottom - dim.top),
                        },
                    },
                } };
            }
        },
        windows_and_messaging.WM_SIZE => {
            // If user is currently resizing the window
            // ignore this event as it is debounced into
            // a single event
            if (resize != null) return null;

            const width = @as(u16, @truncate(@as(usize, @bitCast(lparam))));
            const height = @as(u16, @intCast(lparam >> 16));
            return .{ .window = .{
                .target = @intFromPtr(args[0]),
                .event = .{
                    .resize = .{
                        .width = width,
                        .height = height,
                    },
                },
            } };
        },
        else => return null,
    }

    return null;
}

fn handleThemeChange(state: ?*anyopaque, settings: *UISettings, _: *IInspectable) void {
    const event_loop: *@This() = @ptrCast(@alignCast(state));

    if (settings.GetColorValue(.Foreground)) |color| {
        for (event_loop.windows.values()) |window| {
            window.setCurrentTheme(if (util.isLight(color)) .light else .dark);
        }
    } else |_| {}
}
