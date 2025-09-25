const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;

const Context = @import("context.zig");

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
    const fd = try std.posix.memfd_create("hello-zig-wayland", 0);
    try std.posix.ftruncate(fd, @intCast(size));

    // Map writable shared memory
    const data = try std.posix.mmap(
        null,
        @intCast(size),
        std.posix.PROT.READ | std.posix.PROT.WRITE,
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

pub fn destroy(self: *@This()) void {
    if (!self.busy) {
        std.debug.print("Buffer Destroy Free Mem\n", .{});
        _ = std.posix.munmap(@ptrCast(@alignCast(self.data)));
        std.posix.close(self.fd);
        self.buf.destroy();
        self.allocator.destroy(self);
        return;
    }
    self.want_free = true;
}

pub fn listener(_: *wl.Buffer, _: wl.Buffer.Event, self: *@This()) void {
    self.busy = false;
    if (self.want_free) {
        std.debug.print("Buffer Listener Free Mem\n", .{});
        _ = std.posix.munmap(@ptrCast(@alignCast(self.data)));
        std.posix.close(self.fd);
        self.buf.destroy();
        self.allocator.destroy(self);
    }
}

pub fn repaint(self: *@This(), color: u32) void {
    const count: usize = @intCast(self.width * self.height);
    for (0..count) |i| {
        self.data[i] = color;
    }
}

pub fn present(self: *@This(), surface: *wl.Surface) void {
    surface.attach(self.buf, 0, 0);
    surface.damage(0, 0, self.width, self.height);
    surface.commit();
    self.busy = true;
}
