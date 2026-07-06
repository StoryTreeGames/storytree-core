const std = @import("std");
const winapi = @import("windows");
const win32 = winapi.win32;

const EventHandler = winapi.Foundation.EventHandler;
const IInspectable = winapi.Foundation.IInspectable;
const EventRegistrationToken = winapi.Foundation.EventRegistrationToken;
const Gamepad = winapi.Gaming.Input.Gamepad;
const GamepadReading = winapi.Gaming.Input.GamepadReading;

const library_loader = win32.system.library_loader;
const windows_and_messaging = win32.ui.windows_and_messaging;
const graphics = win32.graphics;
const foundation = win32.foundation;
const keyboard_and_mouse = win32.ui.input.keyboard_and_mouse;

const HRAWINPUT = win32.ui.input.HRAWINPUT;
const RAWINPUT = win32.ui.input.RAWINPUT;
const GetRawInputData = win32.ui.input.GetRawInputData;
const RAW_INPUT_DATA_COMMAND_FLAGS = win32.ui.input.RAW_INPUT_DATA_COMMAND_FLAGS;
const RAWINPUTHEADER = win32.ui.input.RAWINPUTHEADER;
const RIM_TYPEMOUSE = win32.ui.input.RIM_TYPEMOUSE;
const RID_DEVICE_INFO_TYPE = win32.ui.input.RID_DEVICE_INFO_TYPE;

const zig = win32.zig;

const RegisterRawInputDevices = win32.ui.input.RegisterRawInputDevices;
const RAWINPUTDEVICE = win32.ui.input.RAWINPUTDEVICE;
const RAWINPUTDEVICE_FLAGS = win32.ui.input.RAWINPUTDEVICE_FLAGS;
const RIDEV_INPUTSINK = win32.ui.input.RIDEV_INPUTSINK;
const RIDEV_REMOVE = win32.ui.input.RIDEV_REMOVE;
const HID_USAGE_GENERIC_MOUSE = win32.devices.human_interface_device.HID_USAGE_GENERIC_MOUSE;
const HID_USAGE_GENERIC_KEYBOARD = win32.devices.human_interface_device.HID_USAGE_GENERIC_KEYBOARD;
const HID_USAGE_PAGE_GENERIC = win32.devices.human_interface_device.HID_USAGE_PAGE_GENERIC;
const MOUSE_MOVE_ABSOLUTE = win32.devices.human_interface_device.MOUSE_MOVE_ABSOLUTE;

const thm = @import("theme.zig");
const event = @import("../event.zig");
const ButtonState = @import("../event.zig").ButtonState;
const input = @import("input.zig");
const util = @import("./util.zig");

const EventLoop = event.EventLoop;
const Window = @import("window.zig");
const WindowOptions = @import("../window.zig").Options;
const Visibility = @import("../window.zig").Visibility;
const Modifiers = event.Modifiers;
const EventQueue = event.EventQueue;
const Event = event.Event;
const QueuedEvent = event.QueuedEvent;
const UserEvent = event.UserEvent;

const MSG = windows_and_messaging.MSG;
const GetMessageW = windows_and_messaging.GetMessageW;
const PeekMessageW = windows_and_messaging.PeekMessageW;
const TranslateMessage = windows_and_messaging.TranslateMessage;
const DispatchMessageW = windows_and_messaging.DispatchMessageW;

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

pub fn GamepadHandler(remove: *const fn (token: EventRegistrationToken) winapi.core.HResult!void) type {
    return struct {
        handler: *EventHandler(Gamepad),
        token: EventRegistrationToken,
        pub fn deinit(self: *const @This()) void {
            remove(self.token) catch {};
            self.handler.deinit();
        }
    };
}
const CustomEventHandler = struct {
    pub const Handler = *const fn(ev: *EventLoop, win: *Window, state: ?*anyopaque, payload: u32) ?QueuedEvent;

    handler: Handler,
    state: ?*anyopaque,

    pub fn call(self: *const @This(), ev: *EventLoop, win: *Window, payload: u32) ?QueuedEvent {
        return (self.handler)(ev, win, self.state, payload);
    }
};

io: std.Io,
arena: std.heap.ArenaAllocator,

is_exit: bool,
windows: std.AutoArrayHashMapUnmanaged(usize, *Window),
queue: EventQueue,

gamepads: std.AutoArrayHashMapUnmanaged(usize, GamepadReading),

gamepad_added_handler: GamepadHandler(Gamepad.removeGamepadAdded),
gamepad_removed_handler: GamepadHandler(Gamepad.removeGamepadRemoved),

msg_target: ?HWND = null,
raw_input: bool = false,

fn handleGamepadAdded(state: ?*anyopaque, sender: *IInspectable, args: *Gamepad) void {
    _ = sender;
    const this: *@This() = @ptrCast(@alignCast(state.?));
    _ = this;
    std.debug.print("Gamepad Added: {d}", .{@intFromPtr(args)});
}

fn handleGamepadRemoved(state: ?*anyopaque, sender: *IInspectable, args: *Gamepad) void {
    _ = sender;
    const this: *@This() = @ptrCast(@alignCast(state.?));
    _ = this;
    std.debug.print("Gamepad Removed: {d}", .{@intFromPtr(args)});
}

pub fn init(io: std.Io, allocator: std.mem.Allocator) !*@This() {
    const self = try allocator.create(@This());
    errdefer allocator.destroy(self);

    self.io = io;
    self.arena = std.heap.ArenaAllocator.init(allocator);
    self.queue = .init(io, self.arena.allocator());
    self.windows = .empty;

    self.msg_target = try createMsgTargetWindow(self);

    const gamepad_added_handler = try EventHandler(Gamepad).initWithState(handleGamepadAdded, self);
    self.gamepad_added_handler = .{
        .handler = gamepad_added_handler,
        .token = try Gamepad.addGamepadAdded(gamepad_added_handler),
    };
    const gamepad_removed_handler = try EventHandler(Gamepad).initWithState(handleGamepadRemoved, self);
    self.gamepad_removed_handler = .{
        .handler = gamepad_removed_handler,
        .token = try Gamepad.addGamepadRemoved(gamepad_removed_handler),
    };

    _ = thm.setPreferredAppMode(.AllowDark);

    return self;
}

const MSG_TARGET_WINDOW_CLASS = std.unicode.utf8ToUtf16LeStringLiteral("ZINIT-MSG-TARGET-WINDOW");
const MSG_TARGET_WINDOW_TITLE = std.unicode.utf8ToUtf16LeStringLiteral("MSG TARGET");

fn createMsgTargetWindow(event_loop: *EventLoop) !?HWND {
    const instance = library_loader.GetModuleHandleW(null);
    const wnd_class = windows_and_messaging.WNDCLASSW{
        .lpszClassName = MSG_TARGET_WINDOW_CLASS.ptr,

        .style = windows_and_messaging.WNDCLASS_STYLES{ .HREDRAW = 1, .VREDRAW = 1 },
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .hInstance = instance,
        .lpfnWndProc = @ptrCast(&threadEventTargetCallback), // wndProc,
    };

    const result = windows_and_messaging.RegisterClassW(&wnd_class);

    if (result == 0) {
        return error.SystemCreateWindow;
    }

    const handle = windows_and_messaging.CreateWindowExW(
        // Invisible window that is clicked through
        windows_and_messaging.WINDOW_EX_STYLE{
            .NOACTIVATE = 1,
            .TRANSPARENT = 1,
            .LAYERED = 1,
            .TOOLWINDOW = 1 
        },
        MSG_TARGET_WINDOW_CLASS.ptr,
        MSG_TARGET_WINDOW_TITLE.ptr,
        windows_and_messaging.WS_OVERLAPPED,
        0, 0, // initial position
        0, 0, // initial size
        null, // Parent
        null, // Menu
        instance,
        null, // WM_CREATE lpParam
    ) orelse return error.SystemCreateWindow;

    _ = windows_and_messaging.SetWindowLongPtrW(
        handle,
        windows_and_messaging.GWL_STYLE,
        // Window must be visible to receive WM_PAINT messages but it isn't shown
        // because of the LAYERED and TRANSPARENT style.
        //
        // NOTE: WM_PAINT messages are used for delivering events during resize
        @intCast(@as(u32, @bitCast(windows_and_messaging.WINDOW_STYLE { .VISIBLE = 1, .POPUP = 1 })))
    );

    const long_ptr: usize = @intFromPtr(event_loop);
    const ptr: isize = @intCast(long_ptr);
    _ = windows_and_messaging.SetWindowLongPtrW(handle, windows_and_messaging.GWLP_USERDATA, ptr);

    return handle;
}

pub fn deinit(self: *@This()) void {
    const parent = self.arena.child_allocator;
    for (self.windows.values()) |window| {
        window.deinit();
    }

    self.disableRawMouseInput();

    self.gamepad_added_handler.deinit();
    self.gamepad_removed_handler.deinit();

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

pub fn closeAll(self: *@This()) void {
    for (self.windows.values()) |w| {
        w.deinit();
    }
    self.windows.clearAndFree(self.arena.allocator());
}

pub fn exit(self: *@This()) void {
    self.is_exit = true;
}

pub fn isActive(self: *const @This()) bool {
    return !self.is_exit and self.windows.count() > 0;
}

pub fn push(self: *@This(), id: u32, comptime payload: anytype) !void {
    try self.queue.append(.{ .user = .{
        .id = id,
        .payload = switch (@typeInfo(@TypeOf(payload))) {
            .@"enum" => @intFromEnum(payload),
            .comptime_int => payload,
            .int => |i| switch (i.signedness) {
                .signed => @bitCast(@as(i32, @intCast(payload))),
                .unsigned => @intCast(payload)
            },
            else => @compileError("unsupported payload type"),
        }
    }});
}

/// Attempt to get the next `WindowEvent` in the queue.
///
/// This will skip events for windows that no longer exist
pub fn pop(self: *@This()) ?Event {
    switch (self.queue.pop() orelse return null) {
        .user => |ue| return .{ .user = ue },
        .destroy => |key| if (self.windows.fetchSwapRemove(key)) |window| {
            window.value.deinit();
        },
        .device => |de| {
            return .{
                .device = .{
                    .id = de.id,
                    .event = de.event,
                },
            };
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

/// Clear all queued events
pub fn clear(self: *@This()) void {
    self.queue.clear();
}

pub fn handleEvent(self: *@This(), args: std.meta.Tuple(&.{ HWND, u32, usize, isize })) bool {
    const winId = @intFromPtr(args[0]);
    if (self.windows.get(winId)) |win| {
        return parseEvent(self, win, args, &self.queue) catch false;
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

/// Enable raw mouse delta's without any acceleration, normalization, etc.
///
/// This is the raw phyical device input from the system and should be processed furthure
/// by the user to get the desired experience.
///
/// WARNING: This can only be enabled for a single window at a time for the parent process. If there
/// is a window that already has raw mouse input then calling this method again will fail to apply
/// raw mouse input to the new window.
pub fn registerRawInputDevices(self: *const @This(), filter: enum { never, always, when_focused  }) !void {
    const flags = RAWINPUTDEVICE_FLAGS{
        .DEVNOTIFY = @intFromBool(filter != .never),
        .INPUTSINK = @intFromBool(filter == .always),
        .REMOVE = @intFromBool(filter == .never)
    };

    var devices = [2]RAWINPUTDEVICE{
        .{
            // https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/hid-usages#usage-page
            // "Generic Desktop Controls" "HID_USAGE_PAGE_GENERIC"
            .usUsagePage = HID_USAGE_PAGE_GENERIC,
            // https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/hid-usages#usage-id
            // "Mouse" "HID_USAGE_GENERIC_MOUSE"
            .usUsage = HID_USAGE_GENERIC_MOUSE,
            .dwFlags = flags,
            .hwndTarget = self.msg_target,
        },
        .{
            .usUsagePage = HID_USAGE_PAGE_GENERIC,
            // https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/hid-usages#usage-id
            // "Keyboard" "HID_USAGE_GENERIC_KEYBOARD"
            .usUsage = HID_USAGE_GENERIC_KEYBOARD,
            .dwFlags = flags,
            .hwndTarget = self.msg_target,
        },
    };

    // Only if the registration succeeds will it be marked as raw input.
    //
    // This is because only one window can be declared as raw input at a time in windows.
    // To switch raw input to another window first disable raw input for the window that is currently
    // recieving raw input events.
    const result = RegisterRawInputDevices((&devices).ptr, @intCast(devices.len), @sizeOf(RAWINPUTDEVICE));
    if (result != 1) return error.RawInputAlreadyEnabled;
    self.raw_input = true;
}

/// Disables raw mouse input for the window that currently has the raw mouse input focus
pub fn disableRawMouseInput(self: *@This()) void {
    var devices = [2]RAWINPUTDEVICE{
        .{
            .usUsagePage = HID_USAGE_PAGE_GENERIC,
            .usUsage = HID_USAGE_GENERIC_MOUSE,
            .dwFlags = RIDEV_REMOVE,
            .hwndTarget = null,
        },
        .{
            .usUsagePage = HID_USAGE_PAGE_GENERIC,
            .usUsage = HID_USAGE_GENERIC_KEYBOARD,
            .dwFlags = RIDEV_REMOVE,
            .hwndTarget = null,
        }
    };

    if (RegisterRawInputDevices((&devices).ptr, @intCast(devices.len), @sizeOf(RAWINPUTDEVICE)) == 0) {
        self.raw_input = false;
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

var resize: ?util.RECT = null;
fn parseEvent(ev: *@This(), win: *Window, args: EventArgs, queue: *EventQueue) !bool {
    const hwnd: foundation.HWND, const message: u32, const wparam: usize, const lparam: isize = args;

    switch (message) {
        // Request to close the window
        windows_and_messaging.WM_NCCALCSIZE => {
            if (wparam == 1)
            {
                return false;
            }
        },
        windows_and_messaging.WM_CLOSE => {
            try queue.append(.{ .window = .{ .target = @intFromPtr(hwnd), .event = .close } });
            return true;
        },
        windows_and_messaging.WM_SYSCOMMAND => {
            switch (wparam & 0xFFF0) {
                windows_and_messaging.SC_CLOSE => {
                    try queue.append(.{ .window = .{ .target = @intFromPtr(hwnd), .event = .close } });
                    return true;
                },
                windows_and_messaging.SC_MINIMIZE => {
                    try queue.append(.{ .window = .{ .target = @intFromPtr(hwnd), .event = .{ .visibility = .minimize } } });
                    return false;
                },
                windows_and_messaging.SC_MAXIMIZE => {
                    try queue.append(.{ .window = .{ .target = @intFromPtr(hwnd), .event = .{ .visibility = .maximize } } });
                    return false;
                },
                windows_and_messaging.SC_RESTORE => {
                    try queue.append(.{ .window = .{ .target = @intFromPtr(hwnd), .event = .{ .visibility = .restore } } });
                    return false;
                },
                else => {},
            }
        },
        windows_and_messaging.WM_DESTROY => {
            try queue.append(.{ .destroy = @intFromPtr(hwnd) });
            return true;
        },
        windows_and_messaging.WM_SETCURSOR => {
            // Set user defined cursor when the mouse moves within the window
            _ = windows_and_messaging.SetCursor(win.cursor.handle());

            // Allow for resize cursor to be drawn if cursor is at correct position
            // return windows_and_messaging.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        windows_and_messaging.WM_USER...0x7FFF => {
            // try queue.append(.{
            //     .window = .{
            //         .target = @intFromPtr(hwnd),
            //         .event = .{
            //             .user = .{
            //                 .id = message -| windows_and_messaging.WM_USER,
            //                 .target = @bitCast(@as(i32, @intCast(@as(i16, @truncate(lparam))))),
            //             }
            //         },
            //     }
            // });
        },
        windows_and_messaging.WM_COMMAND => {
            const wmId: u16 = @truncate(wparam);
            const wmEvent: u16 = @truncate(wparam >> 16);

            switch (wmEvent) {
                0 => {
                    try queue.append(.{
                        .window = .{
                            .target = @intFromPtr(hwnd),
                            .event = .{
                                .menu = .{
                                    .kind = .window,
                                    .target = @intCast(wmId)
                                }
                            },
                        }
                    });
                },
                0x1800 => {
                    try queue.append(.{
                        .window = .{
                            .target = @intFromPtr(hwnd),
                            .event = .{
                                .menu = .{
                                    .kind = .taskbar,
                                    .target = @intCast(wmId)
                                }
                            },
                        }
                    });
                },
                else => {}
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
                    try queue.append(.{
                        .window = .{
                            .target = @intFromPtr(hwnd),
                            .event = .{
                                .key = .{
                                    .key = .{ .char = data },
                                    .modifiers = modifiers,
                                    .state = .pressed,
                                    .scan = scan_code,
                                    .virtual = virtual_key,
                                },
                            },
                        },
                    });
                    return true;
                }
            }
        },
        windows_and_messaging.WM_KEYDOWN => {
            if (input.codeToVirtualKey(wparam, lparam)) |key| {
                // Keyboard state to better match keyboard input with virtual keys
                var keyboard: [256]u8 = [_]u8{0} ** 256;
                getKeyboardState(&keyboard);

                const modifiers: Modifiers = getModifiers(&keyboard);

                try queue.append(.{
                    .window = .{
                        .target = @intFromPtr(hwnd),
                        .event = .{
                            .key = .{
                                .key = .{ .virtual = key },
                                .modifiers = modifiers,
                                .state = .pressed,
                            },
                        },
                    },
                });

                return true;
            }
        },
        windows_and_messaging.WM_INPUT => {
            var size: u32 = 0;
            const hraw: HRAWINPUT = @ptrFromInt(@as(usize, @intCast(lparam)));
            if (GetRawInputData(hraw, RAW_INPUT_DATA_COMMAND_FLAGS.INPUT, null, &size, @sizeOf(RAWINPUTHEADER)) == 0) {
                var allocator = ev.arena.allocator();

                const buffer = try allocator.alloc(u8, @intCast(size));
                defer allocator.free(buffer);

                if (GetRawInputData(hraw, RAW_INPUT_DATA_COMMAND_FLAGS.INPUT, @ptrCast(buffer.ptr), &size, @sizeOf(RAWINPUTHEADER)) != 0) {
                    const raw_input: *RAWINPUT = @ptrCast(@alignCast(buffer.ptr));
                    if (raw_input.header.dwType != @as(u32, @intFromEnum(RIM_TYPEMOUSE))) return false;
                    const m = raw_input.data.mouse;

                    const is_absolute = (m.usFlags & MOUSE_MOVE_ABSOLUTE) != 0;
                    if (!is_absolute) {
                        const dx: i32 = @intCast(m.lLastX);
                        const dy: i32 = @intCast(m.lLastY);
                        if (dx != 0 or dy != 0) {
                            try queue.append(.{ .device = .{
                                .id = @intFromPtr(raw_input.header.hDevice.?),
                                .event = .{
                                    .mouse_delta = .{ .x = dx, .y = dy },
                                },
                            } });
                            return true;
                        }
                    }
                }
            }
        },
        // MouseMove event

        // WM_MOUSELEAVE
        0x02A3 => {
            win.mouse_over = false;
            try queue.append(.{
                .window = .{
                    .target = @intFromPtr(hwnd),
                    .event = .{
                        .leave = {},
                    },
                },
            });
        },

        windows_and_messaging.WM_MOUSEMOVE => {
            if (!win.mouse_over) {
                win.mouse_over = true;
                var tme = keyboard_and_mouse.TRACKMOUSEEVENT {
                    .cbSize = @sizeOf(keyboard_and_mouse.TRACKMOUSEEVENT),
                    .dwFlags = keyboard_and_mouse.TME_LEAVE,
                    .dwHoverTime = 0,
                    .hwndTrack = hwnd,
                };
                _ = keyboard_and_mouse.TrackMouseEvent(&tme);
                try queue.append(.{
                    .window = .{
                        .target = @intFromPtr(hwnd),
                        .event = .{
                            .enter = {},
                        },
                    },
                });
            }

            if (lparam >= 0) {
                const x: i32 = GET_X_LPARAM(lparam);
                const y: i32 = GET_Y_LPARAM(lparam);
                try queue.append(.{ .window = .{
                    .target = @intFromPtr(hwnd),
                    .event = .{
                        .move = .{ .x = x, .y = y },
                    },
                } });
                return true;
            }
        },
        // Mouse scrolling events
        windows_and_messaging.WM_MOUSEWHEEL => {
            const params: isize = @intCast(wparam);
            const distance: i16 = @truncate(params >> 16);

            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .scroll = .{
                        .direction = .vertical,
                        .delta = distance,
                    },
                },
            } });
            return true;
        },
        windows_and_messaging.WM_MOUSEHWHEEL => {
            const params: isize = @intCast(wparam);
            const distance: i16 = @truncate(params >> 16);

            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .scroll = .{
                        .direction = .horizontal,
                        .delta = distance,
                    },
                },
            } });
            return true;
        },
        // Mouse button events == MouseInput
        windows_and_messaging.WM_LBUTTONDOWN => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .mouse = .{
                        .state = .pressed,
                        .button = .left,
                        .pos = .{
                            .x = GET_X_LPARAM(lparam),
                            .y = GET_Y_LPARAM(lparam)
                        },
                    },
                },
            } });
            return true;
        },
        windows_and_messaging.WM_LBUTTONUP => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .mouse = .{
                        .state = .released,
                        .button = .left,
                        .pos = .{
                            .x = GET_X_LPARAM(lparam),
                            .y = GET_Y_LPARAM(lparam)
                        },
                    },
                },
            } });
            return true;
        },
        windows_and_messaging.WM_MBUTTONDOWN => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .mouse = .{
                        .state = .pressed,
                        .button = .middle,
                        .pos = .{
                            .x = GET_X_LPARAM(lparam),
                            .y = GET_Y_LPARAM(lparam)
                        },
                    },
                },
            } });
            return true;
        },
        windows_and_messaging.WM_MBUTTONUP => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .mouse = .{ .state = .released, .button = .middle,
                        .pos = .{
                            .x = GET_X_LPARAM(lparam),
                            .y = GET_Y_LPARAM(lparam)
                        },
                    },
                },
            } });
            return true;
        },
        windows_and_messaging.WM_RBUTTONDOWN => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .mouse = .{ .state = .pressed, .button = .right,
                        .pos = .{
                            .x = GET_X_LPARAM(lparam),
                            .y = GET_Y_LPARAM(lparam)
                        },
                    },
                },
            } });
            return true;
        },
        windows_and_messaging.WM_RBUTTONUP => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .mouse = .{ .state = .released, .button = .right,
                        .pos = .{
                            .x = GET_X_LPARAM(lparam),
                            .y = GET_Y_LPARAM(lparam)
                        },
                    },
                },
            } });
            return true;
        },
        windows_and_messaging.WM_XBUTTONDOWN => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .mouse = .{
                        .state = .pressed,
                        .button = if ((wparam >> 16) & 0x0001 == 0x0001) .x1 else .x2,
                        .pos = .{
                            .x = GET_X_LPARAM(lparam),
                            .y = GET_Y_LPARAM(lparam)
                        },
                    },
                },
            } });
            return true;
        },
        windows_and_messaging.WM_XBUTTONUP => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .mouse = .{
                        .state = .released,
                        .button = if ((wparam >> 16) & 0x0001 == 0x0001) .x1 else .x2,
                        .pos = .{
                            .x = GET_X_LPARAM(lparam),
                            .y = GET_Y_LPARAM(lparam)
                        },
                    },
                },
            } });
            return true;
        },
        // Check for focus and unfocus
        windows_and_messaging.WM_SETFOCUS => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{ .focused = true },
            } });
            return true;
        },
        windows_and_messaging.WM_KILLFOCUS => {
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{ .focused = false },
            } });
            return true;
        },
        windows_and_messaging.WM_SIZING => {
            const area: *util.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            resize = area.*;
        },
        windows_and_messaging.WM_EXITSIZEMOVE => {
            defer resize = null;
            if (resize) |dim| {
                try queue.append(.{ .window = .{
                    .target = @intFromPtr(hwnd),
                    .event = .{
                        .resize = .{
                            .width = @bitCast(dim.right - dim.left),
                            .height = @bitCast(dim.bottom - dim.top),
                        },
                    },
                } });
                // return true;
            }
        },
        windows_and_messaging.WM_SIZE => {
            // If user is currently resizing the window
            // ignore this event as it is debounced into
            // a single event
            if (resize != null) return false;

            const width = @as(u16, @truncate(@as(usize, @bitCast(lparam))));
            const height = @as(u16, @intCast(lparam >> 16));
            try queue.append(.{ .window = .{
                .target = @intFromPtr(hwnd),
                .event = .{
                    .resize = .{
                        .width = width,
                        .height = height,
                    },
                },
            } });
        },
        windows_and_messaging.WM_SETTINGCHANGE => {
            const theme = win.preferred_theme;
            // If preferred window theme is system theme
            if (theme == null) {
                const new_theme = thm.tryTheme(hwnd, theme, false);
                if (win.theme != new_theme) {
                    win.theme = new_theme;
                    try queue.append(.{
                        .window = .{
                            .target = @intFromPtr(hwnd),
                            .event = .{ .theme = win.theme },
                        },
                    });
                }
            }
        },
        else => {},
    }

    return false;
}

fn GET_X_LPARAM(lParam: isize) i32 {
    return @as(i16, @intCast(lParam & 0xffff));
}

fn GET_Y_LPARAM(lParam: isize) i32 {
    return @as(i16, @intCast((lParam >> 16) & 0xffff));
}

fn threadEventTargetCallback(
    hwnd: HWND,
    msg: u32,
    wparam: usize,
    lparam: isize,
) callconv(.winapi) foundation.LRESULT {
    const ptr = windows_and_messaging.GetWindowLongPtrW(hwnd, windows_and_messaging.GWLP_USERDATA);
    const lptr: usize = @intCast(ptr);
    const event_loop: ?*EventLoop = @ptrFromInt(lptr);

    if (event_loop) |el| {
        if (msg != windows_and_messaging.WM_PAINT) {
            _ = graphics.gdi.RedrawWindow(hwnd, null, null, graphics.gdi.RDW_INTERNALPAINT);
        }

        switch (msg) {
            windows_and_messaging.WM_PAINT => {
                _ = graphics.gdi.ValidateRect(hwnd, null);
                // Default WM_PAINT behaviour. This makes sure modals and popups are shown immediately
                // when opening them.
                return windows_and_messaging.DefWindowProcW(hwnd, msg, wparam, lparam);
            },
            windows_and_messaging.WM_INPUT => {
                var size: u32 = 0;
                const hraw: HRAWINPUT = @ptrFromInt(@as(usize, @intCast(lparam)));
                if (GetRawInputData(hraw, RAW_INPUT_DATA_COMMAND_FLAGS.INPUT, null, &size, @sizeOf(RAWINPUTHEADER)) == 0) {
                    var allocator = el.arena.allocator();

                    if (allocator.alloc(u8, @intCast(size))) |buffer| {
                        defer allocator.free(buffer);
                        if (GetRawInputData(
                                hraw,
                                RAW_INPUT_DATA_COMMAND_FLAGS.INPUT,
                                @ptrCast(buffer.ptr),
                                &size,
                                @sizeOf(RAWINPUTHEADER)
                        ) != 0) {
                            const raw_input: *RAWINPUT = @ptrCast(@alignCast(buffer.ptr));
                            handleRawInput(el, raw_input) catch {};
                        }
                    } else |_| {}
                }

                return windows_and_messaging.DefWindowProcW(hwnd, msg, wparam, lparam);
            },
            else => return windows_and_messaging.DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    } else {
        return windows_and_messaging.DefWindowProcW(hwnd, msg, wparam, lparam);
    }
}

fn handleRawInput(event_loop: *EventLoop, raw_input: *RAWINPUT) !void {
    const ty: RID_DEVICE_INFO_TYPE = @enumFromInt(raw_input.header.dwType);
    switch (ty) {
        .MOUSE => {
            const data = raw_input.data.mouse;
            const is_absolute = (data.usFlags & MOUSE_MOVE_ABSOLUTE) != 0;
            if (!is_absolute) {
                const dx: i32 = @intCast(data.lLastX);
                const dy: i32 = @intCast(data.lLastY);
                if (dx != 0 or dy != 0) {
                    try event_loop.queue.append(.{
                        .device = .{
                            .id = @intFromPtr(raw_input.header.hDevice.?),
                            .event = .{
                                .mouse_delta = .{ .x = dx, .y = dy },
                            },
                        },
                    });
                }
            }

            const btn_flags = data.Anonymous.Anonymous.usButtonFlags;
            if ((btn_flags & windows_and_messaging.RI_MOUSE_WHEEL) != 0) {
                const btn_data: i16 = @bitCast(data.Anonymous.Anonymous.usButtonData);
                const delta = @as(f32, @floatFromInt(btn_data)) / @as(f32, @floatFromInt(windows_and_messaging.WHEEL_DELTA));

                try event_loop.queue.append(.{
                    .device = .{
                        .id = @intFromPtr(raw_input.header.hDevice.?),
                        .event = .{
                            .mouse_wheel = .{ .vertical = delta },
                        },
                    },
                });
            }

            if ((btn_flags & windows_and_messaging.RI_MOUSE_HWHEEL) != 0) {
                const btn_data: i16 = @bitCast(data.Anonymous.Anonymous.usButtonData);
                const delta = @as(f32, @floatFromInt(btn_data)) / @as(f32, @floatFromInt(windows_and_messaging.WHEEL_DELTA));

                try event_loop.queue.append(.{
                    .device = .{
                        .id = @intFromPtr(raw_input.header.hDevice.?),
                        .event = .{
                            .mouse_wheel = .{ .horizontal = delta },
                        },
                    },
                });
            }

            const btn_states = getRawMouseButtonState(btn_flags);
            for (btn_states, 0..) |bs, i| {
                if (bs) |s| {
                    try event_loop.queue.append(.{
                        .device = .{
                            .id = @intFromPtr(raw_input.header.hDevice.?),
                            .event = .{
                                .button = .{ .id = i, .state = s },
                            },
                        },
                    });
                }
            }
        },
        .KEYBOARD => {
            const data = raw_input.data.keyboard;

            const pressed = data.Message == windows_and_messaging.WM_KEYDOWN or data.Message == windows_and_messaging.WM_SYSKEYDOWN;
            const released = data.Message == windows_and_messaging.WM_KEYUP or data.Message == windows_and_messaging.WM_SYSKEYUP;

            if (!pressed and !released) return;

            const flags: u32 = @intCast(data.Flags);
            const extension: u16 = if (hasFlag(u32, flags, windows_and_messaging.RI_KEY_E0))
                0xe000
            else if (hasFlag(u32, flags, windows_and_messaging.RI_KEY_E1))
                0xe100
            else
                0x0000;

            const scancode = if (data.MakeCode == 0)
                @as(u16, @intCast(keyboard_and_mouse.MapVirtualKeyW(data.VKey, windows_and_messaging.MAPVK_VK_TO_VSC_EX)))
            else
                data.MakeCode | extension;

            if (scancode == 0xe11d or scancode == 0xe02a) {
                // Reference: https://github.com/rust-windowing/winit/blob/master/winit-win32/src/raw_input.rs#L226-L245
                return;
            }

            // Reference: https://github.com/rust-windowing/winit/blob/master/winit-win32/src/raw_input.rs#L249-L260
            const physical_key = (
                if (data.VKey == @intFromEnum(keyboard_and_mouse.VK_NUMLOCK))
                    .num_lock
                else
                    input.codeToVirtualKey(@intCast(scancode), 0)
            ) orelse return;

            if (data.VKey == @intFromEnum(keyboard_and_mouse.VK_SHIFT)) {
                switch (physical_key) {
                    .numpad0,
                    .numpad1,
                    .numpad2,
                    .numpad3,
                    .numpad4,
                    .numpad5,
                    .numpad6,
                    .numpad7,
                    .numpad8,
                    .numpad9,
                    .decimal =>  {
                        return;
                    },
                    else => {}
                }
            }

            try event_loop.queue.append(.{
                .device = .{
                    .id = @intFromPtr(raw_input.header.hDevice.?),
                    .event = .{
                        .key = .{
                            .key = physical_key,
                            .state = if (pressed) .pressed else .released
                        },
                    },
                },
            });
        },
        .HID => {}
    }
}

fn getRawMouseButtonState(flags: u32) [5]?ButtonState {
    const w = windows_and_messaging;
    return .{
        btnFlagsToState(flags, w.RI_MOUSE_BUTTON_1_DOWN, w.RI_MOUSE_BUTTON_1_UP),
        btnFlagsToState(flags, w.RI_MOUSE_BUTTON_2_DOWN, w.RI_MOUSE_BUTTON_2_UP),
        btnFlagsToState(flags, w.RI_MOUSE_BUTTON_3_DOWN, w.RI_MOUSE_BUTTON_3_UP),
        btnFlagsToState(flags, w.RI_MOUSE_BUTTON_4_DOWN, w.RI_MOUSE_BUTTON_4_UP),
        btnFlagsToState(flags, w.RI_MOUSE_BUTTON_5_DOWN, w.RI_MOUSE_BUTTON_5_UP),
    };
}

fn btnFlagsToState(flags: u32, down: u32, up: u32) ?ButtonState {
    return if (hasFlag(u32, flags, down))
        .pressed
    else if (hasFlag(u32, flags, up))
        .released
    else
        null;
}

fn hasFlag(comptime T: type, flags: T, value: T) bool {
    return (flags & value) != 0;
}
