const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;

const Seat = @import("seat.zig");
const EventLoop = @import("event.zig");

const Payload = struct {
    shm: ?*wl.Shm = null,
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,
    seat: ?*wl.Seat = null,
    deco_mng: ?*zxdg.DecorationManagerV1 = null,
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

pub fn deinit(self: *@This()) void {
    self.shm.destroy();
    self.compositor.destroy();
    self.base.destroy();
    self.seat.deinit();
    if (self.deco_mng) |o| o.destroy();
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Payload) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, zxdg.DecorationManagerV1.interface.name) == .eq) {
                context.deco_mng = registry.bind(global.name, zxdg.DecorationManagerV1, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                context.seat = registry.bind(global.name, wl.Seat, 7) catch return;
            }
        },
        .global_remove => {},
    }
}
