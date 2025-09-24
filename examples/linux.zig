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

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
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

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, state: *AppState) void {
    switch (event) {
        .configure => |configure| {
            if (state.configured and state.dirty) {
                if (Buffer.create(state.allocator, state.shm, state.width, state.height)) |new_buf| {
                    new_buf.repaint(0xFF000000);
                    new_buf.present(state.surface);
                    state.buffer.destroy();
                    state.buffer = new_buf;
                    state.dirty = false;
                } else |_| {}
            } else {
                state.configured = true;
            }

            xdg_surface.ackConfigure(configure.serial);
            state.surface.commit();
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, state: *AppState) void {
    switch (event) {
        .configure => |cfg| {
            if (cfg.width != 0) state.width = cfg.width;
            if (cfg.height != 0) state.height = cfg.height;
            state.dirty = true;
        },
        .close => state.running = false,
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const display = try wl.Display.connect(null);
    defer display.disconnect();

    const registry = try display.getRegistry();

    var context = Context{
        .shm = null,
        .compositor = null,
        .wm_base = null,
        .deco_mng = null,
        .seat = null,
    };

    registry.setListener(*Context, registryListener, &context);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const shm = context.shm orelse return error.NoWlShm;
    const compositor = context.compositor orelse return error.NoWlCompositor;
    const wm_base = context.wm_base orelse return error.NoXdgWmBase;
    const wl_seat = context.seat orelse return error.NoSeat;
    const deco_mng = context.deco_mng;

    const buffer = try Buffer.create(allocator, shm, 640, 480);
    defer buffer.destroy();

    buffer.repaint(0xFF000000);

    // Create Surface
    const surface = try compositor.createSurface();
    defer surface.destroy();

    // Create toplevel shell surface. Handles adding titlebar with buttons
    const xdg_surface = try wm_base.getXdgSurface(surface);
    defer xdg_surface.destroy();
    const xdg_toplevel = try xdg_surface.getToplevel();
    defer xdg_toplevel.destroy();

    var seat = Seat{ .seat = wl_seat, .top_level = xdg_toplevel };
    defer seat.deinit();

    wl_seat.setListener(*Seat, Seat.capabilities, &seat);

    var state = AppState{
        .allocator = allocator,
        .width = 640,
        .height = 480,
        .shm = shm,
        .display = display,
        .surface = surface,
        .buffer = buffer,
    };

    xdg_surface.setListener(*AppState, xdgSurfaceListener, &state);
    xdg_toplevel.setListener(*AppState, xdgToplevelListener, &state);

    var tl_deco: ?*zxdg.ToplevelDecorationV1 = null;
    var server_deco = false;
    if (deco_mng) |dm| {
        tl_deco = try dm.getToplevelDecoration(xdg_toplevel);
        tl_deco.?.setListener(*bool, Deco.listener, &server_deco);
        tl_deco.?.setMode(.server_side);
    }

    surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    buffer.present(surface);

    std.debug.print("{any}\n", .{server_deco});
    while (state.running) {
        // Non blocking check for events. If there are any then it flushes and dispatches all of them
        //     - This is best for loop driven applications
        //     - Carefull with this one as it is not blocking and
        //         can ramp up cpu usage but is good for a non blocking flush
        //         of the event queue
        // try poll(display);

        // Blocks until there are events then flushes and dispatches all of them
        //     - This is best for event driven applications
        try next(display);
    }
}

fn next(display: *wl.Display) !void {
    if (display.dispatch() != .SUCCESS) return error.DisplayDispatch;
}

fn poll(display: *wl.Display) !void {
    while (!display.prepareRead()) {
        if (display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
    }

    var watch: i16 = std.posix.POLL.IN;
    if (display.flush() != .SUCCESS) {
        watch |= std.posix.POLL.OUT;
    }

    var pollfd = [_]std.posix.pollfd{.{ .fd = display.getFd(), .events = watch, .revents = 0 }};
    if (try std.posix.poll(&pollfd, 0) > 0) {
        if ((pollfd[0].revents & std.posix.POLL.IN) != 0) {
            if (display.readEvents() != .SUCCESS) return error.DisplayReadEvents;
            if (display.flush() != .SUCCESS) return error.DisplayFlush;
            if (display.dispatchPending() != .SUCCESS) return error.DisplayDispatchPending;
        }
    } else {
        display.cancelRead();
    }
}

const Context = struct {
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    wm_base: ?*xdg.WmBase,
    deco_mng: ?*zxdg.DecorationManagerV1,
    seat: ?*wl.Seat,
};

const Seat = struct {
    seat: *wl.Seat,
    top_level: *xdg.Toplevel,
    wl_pointer: ?*wl.Pointer = null,
    wl_keyboard: ?*wl.Keyboard = null,

    kctx: ?*xkbcommon.xkb_context = null,
    keymap: ?*xkbcommon.xkb_keymap = null,
    key_state: ?*xkbcommon.xkb_state = null,
    table: ?*xkbcommon.xkb_compose_table = null,
    compose_state: ?*xkbcommon.xkb_compose_state = null,

    pub fn deinit(self: *@This()) void {
        if (self.key_state) |o| xkbcommon.xkb_state_unref(o);
        if (self.keymap) |o| xkbcommon.xkb_keymap_unref(o);

        if (self.compose_state) |o| xkbcommon.xkb_compose_state_unref(o);
        if (self.table) |o| xkbcommon.xkb_compose_table_unref(o);

        self.key_state = null;
        self.keymap = null;
        self.table = null;
        self.compose_state = null;
    }

    pub fn capabilities(seat: *wl.Seat, event: wl.Seat.Event, state: *@This()) void {
        switch (event) {
            .capabilities => |c| {
                if (c.capabilities.pointer and state.wl_pointer == null) {
                    state.wl_pointer = seat.getPointer() catch return;
                    state.wl_pointer.?.setListener(*@This(), pointer, state);
                } else if (!c.capabilities.pointer and state.wl_pointer != null) {
                    state.wl_pointer.?.destroy();
                    state.wl_pointer = null;
                }

                if (c.capabilities.keyboard and state.wl_keyboard == null) {
                    state.wl_keyboard = seat.getKeyboard() catch return;
                    state.wl_keyboard.?.setListener(*@This(), keyboard, state);
                } else if (!c.capabilities.keyboard and state.wl_keyboard != null) {
                    state.wl_keyboard.?.destroy();
                    state.wl_keyboard = null;
                }
            },
        }
    }

    pub fn pointer(p: *wl.Pointer, event: wl.Pointer.Event, state: *@This()) void {
        _ = .{ p, state };
        switch (event) {
            .enter => |enter| {
                _ = enter;
                std.debug.print("UNFOCUS\n", .{});
                // struct {
                //     serial: u32,
                //     surface: ?*client.wl.Surface,
                //     surface_x: common.Fixed,
                //     surface_y: common.Fixed,
                // }
            },
            .leave => |leave| {
                _ = leave;
                std.debug.print("FOCUS\n", .{});
                // struct {
                //    serial: u32,
                //    surface: ?*client.wl.Surface,
                // }
            },
            .motion => |motion| {
                // motion: struct {
                //     time: u32,
                //     surface_x: common.Fixed,
                //     surface_y: common.Fixed,
                // }
                std.debug.print("(x: {d}, y: {d})\n", .{ motion.surface_x, motion.surface_y });
            },
            .axis => |axis| {
                // axis: struct {
                //     time: u32,
                //     axis: Axis,
                //     value: common.Fixed,
                // },
                std.debug.print("{s} scroll: {d}\n", .{ if (axis.axis == .vertical_scroll) "vertical" else "horizontal", axis.value.toDouble() });
            },
            .button => |button| {
                // button: struct {
                //     serial: u32,
                //     time: u32,
                //     button: u32,
                //     state: ButtonState,
                // }
                std.debug.print("MOUSE: {s}", .{switch (button.button) {
                    0x110 => "Left",
                    0x111 => "Right",
                    0x112 => "Middle",
                    0x113 => "Side", // XBUTTON2
                    0x114 => "Extra", // XBUTTON1
                    0x115 => "Forward",
                    0x116 => "Back",
                    0x117 => "Task",
                    else => "?",
                }});
                std.debug.print(" {s}\n", .{@tagName(button.state)});
            },
        }
    }

    pub fn keyboard(k: *wl.Keyboard, event: wl.Keyboard.Event, state: *@This()) void {
        _ = .{ k, event, state };

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
                if (state.kctx == null) state.kctx = xkbcommon.xkb_context_new(xkbcommon.XKB_CONTEXT_NO_FLAGS);
                if (state.keymap) |old| xkbcommon.xkb_keymap_unref(old);
                if (state.key_state) |old| xkbcommon.xkb_state_unref(old);

                const locale: ?[]const u8 = std.process.getEnvVarOwned(std.heap.page_allocator, "LC_ALL") catch std.process.getEnvVarOwned(std.heap.page_allocator, "LANG") catch null;
                defer if (locale) |l| std.heap.page_allocator.free(l);

                state.table = xkbcommon.xkb_compose_table_new_from_locale(state.kctx.?, if (locale) |l| l.ptr else "C", xkbcommon.XKB_COMPOSE_COMPILE_NO_FLAGS);
                state.compose_state = xkbcommon.xkb_compose_state_new(state.table, xkbcommon.XKB_COMPOSE_STATE_NO_FLAGS);

                const keymap = xkbcommon.xkb_keymap_new_from_string(
                    state.kctx.?,
                    map_ptr,
                    xkbcommon.XKB_KEYMAP_FORMAT_TEXT_V1,
                    xkbcommon.XKB_KEYMAP_COMPILE_NO_FLAGS,
                );
                state.keymap = keymap;
                state.key_state = xkbcommon.xkb_state_new(keymap);

                _ = std.posix.munmap(map);
                std.posix.close(km.fd);
            },
            .enter => |_| {
                // struct {
                //    serial: u32,
                //    surface: ?*client.wl.Surface,
                //    keys: *common.Array,
                // }
                std.debug.print("FOCUS\n", .{});
            },
            .leave => |_| {
                // struct {
                //     serial: u32,
                //     surface: ?*client.wl.Surface,
                // }
                std.debug.print("UNFOCUS\n", .{});
            },
            .key => |key| {
                // key: struct {
                //     serial: u32,
                //     time: u32,
                //     key: u32,
                //     state: KeyState,
                // },

                if (state.key_state == null) return;

                const keycode = key.key + 8;
                const sym = xkbcommon.xkb_state_key_get_one_sym(state.key_state.?, keycode);

                var buf: [4]u8 = std.mem.zeroes([4]u8);

                if (state.compose_state) |cs| {
                    _ = xkbcommon.xkb_compose_state_feed(cs, sym);
                    switch (xkbcommon.xkb_compose_state_get_status(cs)) {
                        xkbcommon.XKB_COMPOSE_COMPOSED => {
                            const n = xkbcommon.xkb_compose_state_get_utf8(cs, &buf, buf.len);
                            xkbcommon.xkb_compose_state_reset(cs);
                            if (n > 0) {
                                std.debug.print("typed({d}): {s}\n", .{ n, buf[0..@intCast(n)] });
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

                const n = xkbcommon.xkb_state_key_get_utf8(state.key_state.?, keycode, &buf, buf.len);
                if (n > 0) {
                    const s = buf[0..@intCast(n)];
                    std.debug.print("typed({d}): {s}\n", .{ s.len, s });
                } else {
                    std.debug.print("typed: {{ {d} }}\n", .{sym});
                }
            },
            // modifiers: struct {
            //     serial: u32,
            //     mods_depressed: u32,
            //     mods_latched: u32,
            //     mods_locked: u32,
            //     group: u32,
            // },
            else => {},
        }
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

    pub fn create(allocator: std.mem.Allocator, shm: *wl.Shm, width: i32, height: i32) !*@This() {
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

        const pool = try shm.createPool(fd, size);
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

const AppState = struct {
    running: bool = true,
    configured: bool = false,
    allocator: std.mem.Allocator,

    dirty: bool = false,
    width: i32 = 0,
    height: i32 = 0,

    shm: *wl.Shm,
    display: *wl.Display,
    surface: *wl.Surface,
    buffer: *Buffer,
};
