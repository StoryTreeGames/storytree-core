const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;

const wl_cursor = @cImport({
    @cInclude("wayland-cursor.h");
});

const EventLoop = @import("event.zig");
const input = @import("input.zig");

const cursorToShape = @import("cursor.zig").cursorToShape;
const cursorToName = @import("cursor.zig").cursorToName;

const xkbcommon = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-compose.h");
});

const CursorType = @import("../cursor.zig").CursorType;

_seat: *wl.Seat,

cursor_shape_device: ?*wp.CursorShapeDeviceV1 = null,
cursor_theme: ?*wl_cursor.wl_cursor_theme = null,
cursor_surface: ?*wl.Surface = null,

pointer: ?*wl.Pointer = null,
keyboard: ?*wl.Keyboard = null,

kctx: ?*xkbcommon.xkb_context = null,
keymap: ?*xkbcommon.xkb_keymap = null,
key_state: ?*xkbcommon.xkb_state = null,

surface: ?*wl.Surface = null,
compose: Compose = .{},

mods: Mods = .{},

// cached modifier & LED indices (looked up once per keymap)
mod_shift: u32 = @as(u32, xkbcommon.XKB_MOD_INVALID),
mod_ctrl: u32 = @as(u32, xkbcommon.XKB_MOD_INVALID),
mod_alt: u32 = @as(u32, xkbcommon.XKB_MOD_INVALID), // "Alt"/Mod1
mod_logo: u32 = @as(u32, xkbcommon.XKB_MOD_INVALID), // Mod4/"Logo"
mod_mod5: u32 = @as(u32, xkbcommon.XKB_MOD_INVALID), // often AltGr
led_caps: u32 = @as(u32, xkbcommon.XKB_LED_INVALID),
led_num: u32 = @as(u32, xkbcommon.XKB_LED_INVALID),
led_scroll: u32 = @as(u32, xkbcommon.XKB_LED_INVALID),

const Compose = struct {
    table: ?*xkbcommon.xkb_compose_table = null,
    state: ?*xkbcommon.xkb_compose_state = null,

    pub fn deinit(self: *@This()) void {
        if (self.state) |o| xkbcommon.xkb_compose_state_unref(o);
        if (self.table) |o| xkbcommon.xkb_compose_table_unref(o);
        self.table = null;
        self.state = null;
    }
};

pub fn deinit(self: *@This()) void {
    if (self.kctx) |o| xkbcommon.xkb_context_unref(o);
    if (self.key_state) |o| xkbcommon.xkb_state_unref(o);
    if (self.keymap) |o| xkbcommon.xkb_keymap_unref(o);
    if (self.cursor_surface) |o| o.destroy();
    if (self.cursor_theme) |o| wl_cursor.wl_cursor_theme_destroy(o);
    if (self.cursor_shape_device) |o| o.destroy();

    self.kctx = null;
    self.key_state = null;
    self.keymap = null;

    self.cursor_theme = null;
    self.cursor_shape_device = null;
    self.cursor_surface = null;

    self.compose.deinit();
    self._seat.destroy();
}

fn setTheme(self: *@This(), serial: u32, cursor: CursorType) void {
    if (self.pointer == null or self.cursor_theme == null or self.cursor_surface == null) return;

    const names = cursorToName(cursor);
    for (0..names.len) |i| {
        if (@as(?*wl.Cursor, @ptrCast(wl_cursor.wl_cursor_theme_get_cursor(self.cursor_theme.?, names[i])))) |cur| {
            const img = cur.images[0];
            if (img.getBuffer()) |buf| {
                // Scale + hotspot are in surface coords
                // wl.client.wl_surface.set_buffer_scale(self.cursor_surface.?, self.scale);
                const hx: i32 = @intCast(img.hotspot_x);
                const hy: i32 = @intCast(img.hotspot_y);

                self.cursor_surface.?.attach(buf, hx, hy);
                self.cursor_surface.?.commit();
                self.pointer.?.setCursor(serial, self.cursor_surface, hx, hy);
                return;
            } else |_| {}
        }
    }
}

pub fn capabilitiesListener(wl_seat: *wl.Seat, event: wl.Seat.Event, el: *EventLoop) void {
    const seat: *@This() = &el.context.seat;
    switch (event) {
        .capabilities => |c| {
            if (c.capabilities.pointer and seat.pointer == null) {
                seat.pointer = wl_seat.getPointer() catch return;
                seat.pointer.?.setListener(*EventLoop, pointerListener, el);
            } else if (!c.capabilities.pointer and seat.pointer != null) {
                seat.pointer.?.destroy();
                seat.pointer = null;
            }

            if (el.context.cursor_mng) |cm| {
                if (c.capabilities.pointer and seat.cursor_shape_device == null) {
                    if (cm.getPointer(seat.pointer.?)) |d| {
                        seat.cursor_shape_device = d;
                    } else |_| {}
                } else if (!c.capabilities.pointer and seat.cursor_shape_device != null) {
                    seat.cursor_shape_device.?.destroy();
                    seat.cursor_shape_device = null;
                }
            } else {
                if (c.capabilities.pointer and seat.cursor_surface == null) {
                    if (seat.cursor_theme == null) {
                        seat.cursor_theme = wl_cursor.wl_cursor_theme_load(null, 24, @ptrCast(el.context.shm));
                    }
                    if (el.context.compositor.createSurface()) |surface| {
                        seat.cursor_surface = surface;
                    } else |_| {}
                } else if (!c.capabilities.pointer and seat.cursor_surface != null) {
                    seat.cursor_surface.?.destroy();
                    seat.cursor_surface = null;
                }
            }

            if (c.capabilities.keyboard and seat.keyboard == null) {
                seat.keyboard = wl_seat.getKeyboard() catch return;
                seat.keyboard.?.setListener(*EventLoop, keyboardListener, el);
            } else if (!c.capabilities.keyboard and seat.keyboard != null) {
                seat.keyboard.?.destroy();
                seat.keyboard = null;
            }
        },
    }
}

pub fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, el: *EventLoop) void {
    switch (event) {
        .enter => |enter| {
            // struct {
            //     serial: u32,
            //     surface: ?*client.wl.Surface,
            //     surface_x: common.Fixed,
            //     surface_y: common.Fixed,
            // }

            if (enter.surface) |surface| {
                if (el.windows.get(@intFromPtr(enter.surface))) |window| {
                    switch (window.cursor) {
                        .icon => |ico| if (el.context.seat.cursor_shape_device) |device| {
                            device.setShape(enter.serial, cursorToShape(ico));
                        } else {
                            setTheme(&el.context.seat, enter.serial, ico);
                        },
                        else => {}, // TODO: Implement custom cursor shape
                    }
                }

                el.context.seat.surface = surface;
                el.queue.append(.{
                    .window = .{
                        .target = @intFromPtr(surface),
                        .event = .{ .focused = true },
                    },
                }) catch {};
            }
        },
        .leave => |leave| {
            // struct {
            //    serial: u32,
            //    surface: ?*client.wl.Surface,
            // }
            if (leave.surface) |surface| {
                el.queue.append(.{
                    .window = .{
                        .target = @intFromPtr(surface),
                        .event = .{ .focused = false },
                    },
                }) catch {};
            }
            el.context.seat.surface = null;
        },
        .motion => |motion| {
            // motion: struct {
            //     time: u32,
            //     surface_x: common.Fixed,
            //     surface_y: common.Fixed,
            // }
            if (el.context.seat.surface) |surface| {
                el.queue.append(.{
                    .window = .{
                        .target = @intFromPtr(surface),
                        .event = .{
                            .mouse_move = .{
                                .x = @intCast(motion.surface_x.toInt()),
                                .y = @intCast(motion.surface_y.toInt()),
                            },
                        },
                    },
                }) catch {};
            }
        },
        .axis => |axis| {
            // axis: struct {
            //     time: u32,
            //     axis: Axis,
            //     value: common.Fixed,
            // },
            if (el.context.seat.surface) |surface| {
                el.queue.append(.{
                    .window = .{
                        .target = @intFromPtr(surface),
                        .event = .{
                            .mouse_scroll = .{
                                .direction = switch (axis.axis) {
                                    .horizontal_scroll => .horizontal,
                                    else => .vertical,
                                },
                                .delta = @intCast(axis.value.toInt()),
                            },
                        },
                    },
                }) catch {};
            }
        },
        .button => |button| {
            // button: struct {
            //     serial: u32,
            //     time: u32,
            //     button: u32,
            //     state: ButtonState,
            // }
            // std.debug.print("MOUSE: {s}", .{switch (button.button) {
            //     0x110 => "Left",
            //     0x111 => "Right",
            //     0x112 => "Middle",
            //     0x113 => "Side", // XBUTTON2
            //     0x114 => "Extra", // XBUTTON1
            //     0x115 => "Forward",
            //     0x116 => "Back",
            //     0x117 => "Task",
            //     else => "?",
            // }});
            if (el.context.seat.surface) |surface| {
                el.queue.append(.{
                    .window = .{
                        .target = @intFromPtr(surface),
                        .event = .{
                            .mouse_input = .{
                                .state = switch (button.state) {
                                    .released => .released,
                                    else => .pressed,
                                },
                                .button = switch (button.button) {
                                    0x110 => .left,
                                    0x111 => .right,
                                    0x112 => .middle,
                                    0x113 => .x2,
                                    0x114 => .x1,
                                    else => .unknown,
                                },
                            },
                        },
                    },
                }) catch {};
            }
        },
    }
}

pub fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, el: *EventLoop) void {
    const seat: *@This() = &el.context.seat;
    switch (event) {
        .keymap => |km| {
            if (km.format != .xkb_v1) {
                std.posix.close(km.fd);
                return;
            }
            const size: usize = @intCast(km.size);
            const map = std.posix.mmap(
                null,
                size,
                std.posix.PROT.READ,
                .{ .TYPE = .PRIVATE },
                km.fd,
                0,
            ) catch {
                std.posix.close(km.fd);
                return;
            };

            const map_ptr: [*]const u8 = @ptrCast(map);
            if (seat.kctx == null) seat.kctx = xkbcommon.xkb_context_new(xkbcommon.XKB_CONTEXT_NO_FLAGS);
            if (seat.keymap) |old| xkbcommon.xkb_keymap_unref(old);
            if (seat.key_state) |old| xkbcommon.xkb_state_unref(old);

            const locale: ?[]const u8 = std.process.getEnvVarOwned(std.heap.page_allocator, "LC_ALL") catch std.process.getEnvVarOwned(std.heap.page_allocator, "LANG") catch null;
            defer if (locale) |l| std.heap.page_allocator.free(l);

            seat.compose.table = xkbcommon.xkb_compose_table_new_from_locale(seat.kctx.?, if (locale) |l| l.ptr else "C", xkbcommon.XKB_COMPOSE_COMPILE_NO_FLAGS);
            seat.compose.state = xkbcommon.xkb_compose_state_new(seat.compose.table, xkbcommon.XKB_COMPOSE_STATE_NO_FLAGS);

            const keymap = xkbcommon.xkb_keymap_new_from_string(
                seat.kctx.?,
                map_ptr,
                xkbcommon.XKB_KEYMAP_FORMAT_TEXT_V1,
                xkbcommon.XKB_KEYMAP_COMPILE_NO_FLAGS,
            );
            seat.keymap = keymap;
            seat.key_state = xkbcommon.xkb_state_new(keymap);

            if (keymap) |k| {
                seat.mod_shift = xkbcommon.xkb_keymap_mod_get_index(k, xkbcommon.XKB_MOD_NAME_SHIFT);
                seat.mod_alt = xkbcommon.xkb_keymap_mod_get_index(k, xkbcommon.XKB_MOD_NAME_ALT);
                seat.mod_ctrl = xkbcommon.xkb_keymap_mod_get_index(k, xkbcommon.XKB_MOD_NAME_CTRL);
                seat.mod_logo = xkbcommon.xkb_keymap_mod_get_index(k, xkbcommon.XKB_MOD_NAME_LOGO);
                seat.mod_mod5 = xkbcommon.xkb_keymap_mod_get_index(k, "Mod5");

                seat.led_caps = xkbcommon.xkb_keymap_led_get_index(k, xkbcommon.XKB_LED_NAME_CAPS);
                seat.led_num = xkbcommon.xkb_keymap_led_get_index(k, xkbcommon.XKB_LED_NAME_NUM);
                seat.led_scroll = xkbcommon.xkb_keymap_led_get_index(k, xkbcommon.XKB_LED_NAME_SCROLL);
            }

            _ = std.posix.munmap(map);
            std.posix.close(km.fd);
        },
        .enter => |enter| {
            // struct {
            //    serial: u32,
            //    surface: ?*client.wl.Surface,
            //    keys: *common.Array,
            // }
            if (enter.surface) |surface| {
                el.context.seat.surface = surface;
                el.queue.append(.{
                    .window = .{
                        .target = @intFromPtr(surface),
                        .event = .{ .focused = true },
                    },
                }) catch {};
            }
        },
        .leave => |leave| {
            // struct {
            //     serial: u32,
            //     surface: ?*client.wl.Surface,
            // }
            if (leave.surface) |surface| {
                el.queue.append(.{
                    .window = .{
                        .target = @intFromPtr(surface),
                        .event = .{ .focused = false },
                    },
                }) catch {};
            }
            el.context.seat.surface = null;
        },
        .key => |key| {
            // key: struct {
            //     serial: u32,
            //     time: u32,
            //     key: u32,
            //     state: KeyState,
            // },

            if (seat.key_state == null) return;

            const keycode = key.key + 8;
            const sym = xkbcommon.xkb_state_key_get_one_sym(seat.key_state.?, keycode);

            var buf: [4]u8 = std.mem.zeroes([4]u8);

            if (seat.compose.state) |cs| {
                _ = xkbcommon.xkb_compose_state_feed(cs, sym);
                switch (xkbcommon.xkb_compose_state_get_status(cs)) {
                    xkbcommon.XKB_COMPOSE_COMPOSED => {
                        const n = xkbcommon.xkb_compose_state_get_utf8(cs, &buf, buf.len);
                        xkbcommon.xkb_compose_state_reset(cs);
                        if (n > 0) {
                            if (el.context.seat.surface) |surface| {
                                el.queue.append(.{
                                    .window = .{
                                        .target = @intFromPtr(surface),
                                        .event = .{
                                            .key_input = .{
                                                .state = switch (key.state) {
                                                    .released => .released,
                                                    else => .pressed,
                                                },
                                                .key = .{ .char = buf },
                                                .scan = sym,
                                                .virtual = keycode,
                                                .modifiers = .{
                                                    .ctrl = seat.mods.ctrl,
                                                    .alt = seat.mods.alt,
                                                    .shift = seat.mods.shift,
                                                },
                                            },
                                        },
                                    },
                                }) catch {};
                            }
                        }
                        return;
                    },
                    xkbcommon.XKB_COMPOSE_COMPOSING => {
                        return;
                    },
                    xkbcommon.XKB_COMPOSE_CANCELLED => {
                        xkbcommon.xkb_compose_state_reset(cs);
                    },
                    xkbcommon.XKB_COMPOSE_NOTHING => {},
                    else => {},
                }
            }

            const virtual_key = input.codeToVirtualKey(sym, keycode);
            const n = xkbcommon.xkb_state_key_get_utf8(seat.key_state.?, keycode, &buf, buf.len);

            if (el.context.seat.surface) |surface| {
                if (virtual_key) |vk| {
                    el.queue.append(.{
                        .window = .{
                            .target = @intFromPtr(surface),
                            .event = .{
                                .key_input = .{
                                    .state = switch (key.state) {
                                        .released => .released,
                                        else => .pressed,
                                    },
                                    .key = .{ .virtual = vk },
                                    .scan = sym,
                                    .virtual = keycode,
                                    .modifiers = .{
                                        .ctrl = seat.mods.ctrl,
                                        .alt = seat.mods.alt,
                                        .shift = seat.mods.shift,
                                    },
                                },
                            },
                        },
                    }) catch {};
                } else if (n > 0) {
                    el.queue.append(.{
                        .window = .{
                            .target = @intFromPtr(surface),
                            .event = .{
                                .key_input = .{
                                    .state = switch (key.state) {
                                        .released => .released,
                                        else => .pressed,
                                    },
                                    .key = .{ .char = buf },
                                    .scan = sym,
                                    .virtual = keycode,
                                    .modifiers = .{
                                        .ctrl = seat.mods.ctrl,
                                        .alt = seat.mods.alt,
                                        .shift = seat.mods.shift,
                                    },
                                },
                            },
                        },
                    }) catch {};
                } else {
                    el.queue.append(.{
                        .window = .{
                            .target = @intFromPtr(surface),
                            .event = .{
                                .key_input = .{
                                    .state = switch (key.state) {
                                        .released => .released,
                                        else => .pressed,
                                    },
                                    .key = .{ .virtual = .unknown },
                                    .scan = sym,
                                    .virtual = keycode,
                                    .modifiers = .{
                                        .ctrl = seat.mods.ctrl,
                                        .alt = seat.mods.alt,
                                        .shift = seat.mods.shift,
                                    },
                                },
                            },
                        },
                    }) catch {};
                }
            }
        },
        .modifiers => |modifiers| {
            // modifiers: struct {
            //     serial: u32,
            //     mods_depressed: u32,
            //     mods_latched: u32,
            //     mods_locked: u32,
            //     group: u32,
            // },
            if (seat.key_state == null) return;

            _ = xkbcommon.xkb_state_update_mask(
                seat.key_state,
                modifiers.mods_depressed,
                modifiers.mods_latched,
                modifiers.mods_locked,
                0,
                0,
                modifiers.group,
            );

            const eff = xkbcommon.XKB_STATE_MODS_EFFECTIVE;

            seat.mods.shift = (seat.mod_shift != xkbcommon.XKB_MOD_INVALID and xkbcommon.xkb_state_mod_index_is_active(
                seat.key_state,
                seat.mod_shift,
                eff,
            ) != 0);
            seat.mods.alt = (seat.mod_alt != xkbcommon.XKB_MOD_INVALID and xkbcommon.xkb_state_mod_index_is_active(
                seat.key_state,
                seat.mod_alt,
                eff,
            ) != 0);
            seat.mods.ctrl = (seat.mod_ctrl != xkbcommon.XKB_MOD_INVALID and xkbcommon.xkb_state_mod_index_is_active(
                seat.key_state,
                seat.mod_ctrl,
                eff,
            ) != 0);
            seat.mods.super = (seat.mod_logo != xkbcommon.XKB_MOD_INVALID and xkbcommon.xkb_state_mod_index_is_active(
                seat.key_state,
                seat.mod_logo,
                eff,
            ) != 0);
            seat.mods.altgr = (seat.mod_mod5 != xkbcommon.XKB_MOD_INVALID and xkbcommon.xkb_state_mod_index_is_active(
                seat.key_state,
                seat.mod_mod5,
                eff,
            ) != 0);

            seat.mods.caps = (seat.led_caps != xkbcommon.XKB_LED_INVALID and xkbcommon.xkb_state_led_index_is_active(
                seat.key_state,
                seat.led_caps,
            ) != 0);
            seat.mods.num = (seat.led_num != xkbcommon.XKB_LED_INVALID and xkbcommon.xkb_state_led_index_is_active(
                seat.key_state,
                seat.led_num,
            ) != 0);
            seat.mods.scroll = (seat.led_scroll != xkbcommon.XKB_LED_INVALID and xkbcommon.xkb_state_led_index_is_active(
                seat.key_state,
                seat.led_scroll,
            ) != 0);
        },
    }
}

pub const Mods = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false, // usually Mod1
    super: bool = false, // usually Mod4 / "Logo"
    altgr: bool = false, // often Mod5 (Level3)

    caps: bool = false, // via LED
    num: bool = false, // via LED
    scroll: bool = false, // via LED
};
