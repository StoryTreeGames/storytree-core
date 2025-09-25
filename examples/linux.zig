// Wayland: https://zig.news/leroycep/wayland-from-the-wire-part-1-12a1
// X11: https://www.youtube.com/watch?v=aPWFLkHRIAQ

const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");

const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;
const xkbcommon = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-compose.h");
});

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context.Payload) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, zxdg.DecorationManagerV1.interface.name) == .eq) {
                context.deco_mng = registry.bind(global.name, zxdg.DecorationManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                context.seat = registry.bind(global.name, wl.Seat, 7) catch return;
            }
        },
        .global_remove => {},
    }
}

const Event = union(enum) {
    resize: struct { width: i32, height: i32 },
    mouse: union(enum) {
        motion: struct { x: i32, y: i32 },
        button: struct {
            state: enum { pressed, released },
            button: ?enum {
                left,
                right,
                middle,
                x1,
                x2,
            },
        },
        scroll: struct {
            dir: enum { h, v },
            value: i32,
        },
    },
    focus: bool,
    keyboard: struct {
        state: enum { pressed, released },
        key: union(enum) {
            text: [4]u8,
            sym: u32,
        },
    },
    close: void,
};

const EventQueue = LinkedQueueUnmanaged(std.meta.Tuple(&.{ usize, Event }));

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit(allocator);

    const window = try event_loop.createWindow(.{});

    std.debug.print("[{d}] Server Decorations: {any}\n", .{ window.id(), window.server_side_decorations });

    var running = true;
    while (running) {
        // Non blocking check for events. If there are any then it flushes and dispatches all of them
        //     - This is best for loop driven applications
        //     - Carefull with this one as it is not blocking and
        //         can ramp up cpu usage but is good for a non blocking flush
        //         of the event queue
        // try poll(display);

        // Blocks until there are events then flushes and dispatches all of them
        //     - This is best for event driven applications
        try event_loop.next();

        const id = window.id();
        while (event_loop.queue.pop()) |event| {
            if (id == event[0]) {
                switch (event[1]) {
                    .close => running = false,
                    .keyboard => |keyboard| {
                        if (keyboard.state == .pressed) {
                            switch (keyboard.key) {
                                .text => |text| {
                                    std.debug.print("{any}\n", .{text});
                                    if (std.mem.eql(u8, std.mem.sliceTo(&text, 0), "q")) {
                                        running = false;
                                    } else if (std.mem.eql(u8, &text, &.{ 27, 0, 0, 0 })) {
                                        running = false;
                                    }
                                },
                                .sym => |sym| {
                                    if (sym == xkbcommon.XKB_KEY_Escape) {
                                        running = false;
                                    }
                                },
                            }
                        }
                    },
                    else => {},
                }
            }
        }
    }
}

const EventLoop = struct {
    arena: std.heap.ArenaAllocator,

    queue: EventQueue,
    windows: std.AutoArrayHashMapUnmanaged(usize, *Window),

    context: Context,
    display: *wl.Display,
    registry: *wl.Registry,

    pub fn init(allocator: std.mem.Allocator) !*@This() {
        const self = try allocator.create(@This());
        errdefer allocator.destroy(self);

        self.arena = std.heap.ArenaAllocator.init(allocator);
        errdefer self.arena.deinit();

        self.windows = .empty;
        self.queue = .{ .allocator = self.arena.allocator() };

        self.display = try wl.Display.connect(null);
        errdefer self.display.disconnect();

        self.registry = try self.display.getRegistry();
        errdefer self.registry.destroy();

        self.context = try Context.init(self);

        return self;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.windows.values()) |window| {
            window.deinit(self.arena.allocator());
        }
        self.windows.deinit(self.arena.allocator());

        self.context.deinit(self.arena.allocator());
        self.registry.destroy();
        self.display.disconnect();
        self.queue.deinit();

        self.arena.deinit();

        allocator.destroy(self);
    }

    pub fn createWindow(self: *@This(), options: Window.Options) !*Window {
        const allocator = self.arena.allocator();

        const window = try Window.init(allocator, self, options);
        errdefer window.deinit(allocator);

        try self.windows.put(allocator, window.id(), window);

        return window;
    }

    pub fn next(self: *@This()) !void {
        if (self.display.dispatch() != .SUCCESS) return error.DisplayDispatch;
    }

    pub fn poll(self: *@This()) !void {
        while (!self.display.prepareRead()) {
            if (self.display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
        }

        var watch: i16 = std.posix.POLL.IN;
        if (self.display.flush() != .SUCCESS) {
            watch |= std.posix.POLL.OUT;
        }

        var pollfd = [_]std.posix.pollfd{.{ .fd = self.display.getFd(), .events = watch, .revents = 0 }};
        if (try std.posix.poll(&pollfd, 0) > 0) {
            if ((pollfd[0].revents & std.posix.POLL.IN) != 0) {
                if (self.display.readEvents() != .SUCCESS) return error.DisplayReadEvents;
                if (self.display.flush() != .SUCCESS) return error.DisplayFlush;
                if (self.display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
            }
        } else {
            self.display.cancelRead();
        }
    }

    pub fn createBuffer(self: *@This(), width: i32, height: i32) !*Buffer {
        return Buffer.create(self.arena.allocator(), &self.context, width, height);
    }
};

const Context = struct {
    const Payload = struct {
        shm: ?*wl.Shm = null,
        compositor: ?*wl.Compositor = null,
        wm_base: ?*xdg.WmBase = null,
        deco_mng: ?*zxdg.DecorationManagerV1 = null,
        seat: ?*wl.Seat = null,
    };

    shm: *wl.Shm,
    compositor: *wl.Compositor,
    base: *xdg.WmBase,
    seat: Seat,
    deco_mng: ?*zxdg.DecorationManagerV1,

    pub fn init(event_loop: *EventLoop) !@This() {
        var payload = Payload{
            .shm = null,
            .compositor = null,
            .wm_base = null,
            .deco_mng = null,
            .seat = null,
        };
        errdefer {
            if (payload.compositor) |o| o.destroy();
            if (payload.shm) |o| o.destroy();
            if (payload.wm_base) |o| o.destroy();
            if (payload.seat) |o| o.destroy();
            if (payload.deco_mng) |o| o.destroy();
        }

        event_loop.registry.setListener(*Payload, registryListener, &payload);
        if (event_loop.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

        const seat = payload.seat orelse return error.NoSeat;

        seat.setListener(*EventLoop, Seat.capabilitiesListener, event_loop);

        return .{
            .shm = payload.shm orelse return error.NoWlShm,
            .compositor = payload.compositor orelse return error.NoWlCompositor,
            .base = payload.wm_base orelse return error.NoXdgWmBase,
            .seat = Seat{ ._seat = seat },
            .deco_mng = payload.deco_mng,
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.shm.destroy();
        self.compositor.destroy();
        self.base.destroy();
        self.seat.deinit();
        if (self.deco_mng) |o| o.destroy();

        allocator.destroy(self);
    }
};

const Deco = struct {
    server: *bool,
    fn listener(_: *zxdg.ToplevelDecorationV1, event: zxdg.ToplevelDecorationV1.Event, server: *bool) void {
        switch (event) {
            .configure => |cfg| {
                server.* = cfg.mode == .server_side;
            },
        }
    }
};

const Buffer = struct {
    fd: std.posix.fd_t,
    data: []u32,
    size: i32,
    width: i32,
    height: i32,
    buf: *wl.Buffer,
    busy: bool = false,
    want_free: bool = false,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, ctx: *const Context, width: i32, height: i32) !*@This() {
        const stride = width * @sizeOf(u32);
        const size = stride * height;

        // TODO: Make fd an guid like the Windows class equivelant
        const fd = try posix.memfd_create("hello-zig-wayland", 0);
        try posix.ftruncate(fd, @intCast(size));

        // Map writable shared memory
        const data = try posix.mmap(
            null,
            @intCast(size),
            posix.PROT.READ | posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );
        errdefer std.posix.munmap(data);

        const pool = try ctx.shm.createPool(fd, size);
        defer pool.destroy();

        const buffer = try pool.createBuffer(0, width, height, stride, wl.Shm.Format.argb8888);

        const self = try allocator.create(@This());
        self.* = .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .fd = fd,
            .size = size,
            .buf = buffer,
            .data = @ptrCast(@alignCast(data)),
        };

        buffer.setListener(*@This(), listener, self);

        return self;
    }

    fn destroy(self: *@This()) void {
        if (!self.busy) {
            _ = std.posix.munmap(@ptrCast(@alignCast(self.data)));
            std.posix.close(self.fd);
            self.buf.destroy();
            self.allocator.destroy(self);
            return;
        }
        self.want_free = true;
    }

    fn listener(buffer: *wl.Buffer, _: wl.Buffer.Event, self: *@This()) void {
        self.busy = false;
        if (self.want_free) {
            _ = std.posix.munmap(@ptrCast(@alignCast(self.data)));
            std.posix.close(self.fd);
            buffer.destroy();
            self.allocator.destroy(self);
        }
    }

    fn repaint(self: *@This(), color: u32) void {
        const count: usize = @intCast(self.width * self.height);
        for (0..count) |i| {
            self.data[i] = color;
        }
    }

    fn present(self: *@This(), surface: *wl.Surface) void {
        surface.attach(self.buf, 0, 0);
        surface.damage(0, 0, self.width, self.height);
        surface.commit();
        self.busy = true;
    }
};

const Seat = struct {
    _seat: *wl.Seat,

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
        if (self.key_state) |o| xkbcommon.xkb_state_unref(o);
        if (self.keymap) |o| xkbcommon.xkb_keymap_unref(o);
        self.key_state = null;
        self.keymap = null;

        self.compose.deinit();
        self._seat.destroy();
    }

    pub fn capabilitiesListener(wl_seat: *wl.Seat, event: wl.Seat.Event, el: *EventLoop) void {
        const seat: *Seat = &el.context.seat;
        switch (event) {
            .capabilities => |c| {
                if (c.capabilities.pointer and seat.pointer == null) {
                    seat.pointer = wl_seat.getPointer() catch return;
                    seat.pointer.?.setListener(*EventLoop, pointerListener, el);
                } else if (!c.capabilities.pointer and seat.pointer != null) {
                    seat.pointer.?.destroy();
                    seat.pointer = null;
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
                    el.context.seat.surface = surface;
                    el.queue.append(.{ @intFromPtr(surface), .{ .focus = true } }) catch {};
                }
            },
            .leave => |leave| {
                // struct {
                //    serial: u32,
                //    surface: ?*client.wl.Surface,
                // }
                if (leave.surface) |surface| {
                    el.queue.append(.{ @intFromPtr(surface), .{ .focus = false } }) catch {};
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
                        @intFromPtr(surface),
                        .{
                            .mouse = .{
                                .motion = .{
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
                        @intFromPtr(surface),
                        .{
                            .mouse = .{
                                .scroll = .{
                                    .dir = switch (axis.axis) {
                                        .horizontal_scroll => .h,
                                        else => .v,
                                    },
                                    .value = @intCast(axis.value.toInt()),
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
                        @intFromPtr(surface),
                        .{
                            .mouse = .{
                                .button = .{
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
                                        else => null,
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
        const seat: *Seat = &el.context.seat;
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
                    el.queue.append(.{ @intFromPtr(surface), .{ .focus = true } }) catch {};
                }
            },
            .leave => |leave| {
                // struct {
                //     serial: u32,
                //     surface: ?*client.wl.Surface,
                // }
                if (leave.surface) |surface| {
                    el.queue.append(.{ @intFromPtr(surface), .{ .focus = false } }) catch {};
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
                                        @intFromPtr(surface),
                                        .{
                                            .keyboard = .{
                                                .state = switch (key.state) {
                                                    .released => .released,
                                                    else => .pressed,
                                                },
                                                .key = .{ .text = buf },
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

                const n = xkbcommon.xkb_state_key_get_utf8(seat.key_state.?, keycode, &buf, buf.len);
                if (n > 0) {
                    if (el.context.seat.surface) |surface| {
                        el.queue.append(.{
                            @intFromPtr(surface),
                            .{
                                .keyboard = .{
                                    .state = switch (key.state) {
                                        .released => .released,
                                        else => .pressed,
                                    },
                                    .key = .{ .text = buf },
                                },
                            },
                        }) catch {};
                    }
                } else {
                    if (el.context.seat.surface) |surface| {
                        el.queue.append(.{
                            @intFromPtr(surface),
                            .{
                                .keyboard = .{
                                    .state = switch (key.state) {
                                        .released => .released,
                                        else => .pressed,
                                    },
                                    .key = .{ .sym = sym },
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
};

const WindowState = packed struct(u4) {
    maximized: bool = false,
    fullscreen: bool = false,
    resizing: bool = false,
    activated: bool = false,
};

const Window = struct {
    event_loop: *EventLoop,

    configured: bool = false,
    dirty: bool = false,

    state: WindowState = .{},

    width: i32 = 0,
    height: i32 = 0,

    server_side_decorations: bool = false,

    surface: *wl.Surface,
    buffer: *Buffer,
    xdg: Xdg,

    pub const Options = struct {
        width: i32 = 640,
        height: i32 = 480,
        color: u32 = 0xFF000000,
    };

    pub fn init(allocator: std.mem.Allocator, event_loop: *EventLoop, options: Options) !*@This() {
        const buffer = try event_loop.createBuffer(options.width, options.height);
        errdefer buffer.destroy();

        buffer.repaint(options.color);

        // Create Surface
        const surface = try event_loop.context.compositor.createSurface();
        errdefer surface.destroy();

        // Create toplevel shell surface. Handles adding titlebar with buttons
        const xdg_surface = try event_loop.context.base.getXdgSurface(surface);
        errdefer xdg_surface.destroy();
        const xdg_toplevel = try xdg_surface.getToplevel();
        errdefer xdg_toplevel.destroy();

        var tl_deco: ?*zxdg.ToplevelDecorationV1 = null;
        errdefer if (tl_deco) |o| o.destroy();

        var server_deco = false;
        if (event_loop.context.deco_mng) |dm| {
            tl_deco = try dm.getToplevelDecoration(xdg_toplevel);
            tl_deco.?.setListener(*bool, Deco.listener, &server_deco);
            tl_deco.?.setMode(.server_side);
        }

        const self = try allocator.create(Window);
        self.* = .{
            .event_loop = event_loop,
            .width = options.width,
            .height = options.height,
            .surface = surface,
            .buffer = buffer,
            .server_side_decorations = server_deco,
            .xdg = .{
                .surface = xdg_surface,
                .top_level = xdg_toplevel,
                .deco = tl_deco,
            },
        };
        errdefer {
            self.deinit(allocator);
            allocator.destroy(self);
        }

        xdg_surface.setListener(*Window, Window.xdgSurfaceListener, self);
        xdg_toplevel.setListener(*Window, Window.xdgToplevelListener, self);

        surface.commit();
        if (event_loop.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

        self.server_side_decorations = server_deco;

        buffer.present(surface);

        return self;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.surface.destroy();
        self.buffer.destroy();
        self.xdg.deinit();
        allocator.destroy(self);
    }

    pub fn id(self: *const @This()) usize {
        return @intFromPtr(self.surface);
    }

    const Xdg = struct {
        surface: *xdg.Surface,
        top_level: *xdg.Toplevel,
        deco: ?*zxdg.ToplevelDecorationV1,

        pub fn deinit(self: *@This()) void {
            self.surface.destroy();
            self.top_level.destroy();
            if (self.deco) |o| o.destroy();
        }
    };

    pub const State = struct {
        window: *Window,
        context: Context,
        queue: *EventQueue,
        allocator: std.mem.Allocator,
    };

    pub fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, self: *@This()) void {
        switch (event) {
            .configure => |configure| {
                xdg_surface.ackConfigure(configure.serial);

                // How to get window???
                self.surface.commit();

                if (self.configured and self.dirty) {
                    self.event_loop.queue.append(.{
                        @intFromPtr(self.surface),
                        .{ .resize = .{ .width = self.width, .height = self.height } },
                    }) catch {};
                    if (Buffer.create(self.event_loop.arena.allocator(), &self.event_loop.context, self.width, self.height)) |new_buf| {
                        new_buf.repaint(0xFF000000);
                        new_buf.present(self.surface);
                        self.buffer.destroy();
                        self.buffer = new_buf;
                        self.dirty = false;
                    } else |_| {}
                } else {
                    self.configured = true;
                }
            },
        }
    }

    pub fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, self: *@This()) void {
        switch (event) {
            .configure => |cfg| {
                if (cfg.width != 0) self.width = cfg.width;
                if (cfg.height != 0) self.height = cfg.height;
                self.state = .{};
                for (cfg.states.slice(xdg.Toplevel.State)) |state| {
                    switch (state) {
                        .fullscreen => self.state.fullscreen = true,
                        .maximized => self.state.maximized = true,
                        .activated => self.state.activated = true,
                        .resizing => self.state.resizing = true,
                        else => {},
                    }
                }
                self.dirty = true;
            },
            .close => self.event_loop.queue.append(.{
                @intFromPtr(self.surface),
                Event.close,
            }) catch {},
        }
    }
};

/// Linked queue (unbounded except by memory).
/// - Non-blocking: tryPop returns null when empty; push allocates a node per item.
/// - No Conditions/Mutexes. Just atomic pointer handoff.
pub fn LinkedQueueUnmanaged(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            next: ?*Node,
            value: T,
        };

        mutex: std.Thread.Mutex = .{},
        allocator: std.mem.Allocator,

        head: ?*Node = null, // oldest
        tail: ?*Node = null, // newest
        count: usize = 0,

        pub const PushError = std.mem.Allocator.Error;

        /// Frees any remaining nodes. Ensure no threads are using the queue.
        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            var cur = self.head;
            self.head = null;
            self.tail = null;
            self.count = 0;
            self.mutex.unlock();

            while (cur) |n| {
                const a = n.next;
                self.allocator.destroy(n);
                cur = a;
            }
        }

        /// Enqueue one value. Allocates a node; never blocks (aside from the lock).
        pub fn append(self: *Self, value: T) PushError!void {
            const n = try self.allocator.create(Node);
            n.* = .{ .next = null, .value = value };

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.tail) |t| {
                t.next = n;
            } else {
                self.head = n;
            }
            self.tail = n;
            self.count += 1;
        }

        /// Dequeue one value if available; returns null when empty.
        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const h = self.head orelse return null;

            // Detach head
            const n = h.next;
            self.head = n;
            if (n == null) self.tail = null;
            self.count -= 1;

            const result = h.value;
            self.allocator.destroy(h);
            return result;
        }

        pub fn isEmpty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.head == null;
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.count;
        }
    };
}
