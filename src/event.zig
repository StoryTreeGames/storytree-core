const std = @import("std");
const input = @import("input.zig");

const impl = switch (@import("builtin").os.tag) {
    .windows => @import("windows/event.zig"),
    else => @compileError("platform not supported"),
};

const Window = @import("window.zig");
const Key = input.Key;
const MouseButton = input.MouseButton;
const Point = @import("root.zig").Point;
const MenuItem = @import("menu.zig").Item;
const MenuInfo = @import("menu.zig").Info;

pub const Modifiers = packed struct(u3) {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};

pub const KeyEvent = struct {
    /// Current button state, i.e. pressed or released
    state: ButtonState,
    /// Modifiers: ctrl, alt, shift, etc as bit flags
    modifiers: Modifiers,
    /// Virtual key code
    virtual: u32 = 0,
    /// Scan code
    scan: u32 = 0,
    /// Key representation
    key: Key,

    pub fn matches(self: *const KeyEvent, key: anytype, modifiers: Mods) bool {
        const KEY = @TypeOf(key);

        const key_match = switch (KEY) {
            u8, u21, u32, comptime_int => self.key == .char and @as(u21, @intCast(key)) == @as(u21, @truncate(std.mem.readInt(u32, &self.key.char, .little))),
            input.VirtualKey, @Type(.enum_literal) => self.key == .virtual and self.key.virtual == key,
            else => @compileError("unsupported key type '" ++ @typeName(@TypeOf(key)) ++ "': expected u8, u21, u32, or virtual key"),
        };

        var modifiers_match = true;
        if (modifiers.ctrl != null and modifiers.ctrl != self.modifiers.ctrl) {
            modifiers_match = false;
        }
        if (modifiers.alt != null and modifiers.alt != self.modifiers.alt) {
            modifiers_match = false;
        }
        if (modifiers.shift != null and modifiers.shift != self.modifiers.shift) {
            modifiers_match = false;
        }

        return key_match and modifiers_match;
    }

    pub const Mods = struct {
        ctrl: ?bool = null,
        alt: ?bool = null,
        shift: ?bool = null,
    };
};

pub const ButtonState = enum {
    pressed,
    released,
};

pub const ScrollDirection = enum {
    vertical,
    horizontal,
};

pub const ScrollEvent = struct {
    /// Whether the scrolling is horizontal or vertical
    direction: ScrollDirection,
    /// The amount of pixels scrolled.
    ///
    /// Positive scrolling is to the right and down respectively for horizontal and vertical
    delta: i16,
};

pub const MouseEvent = struct {
    /// Mouse button state, i.e. pressed or released
    state: ButtonState,
    /// What mouse button was pressed: left, right, middle, x1, or x2
    button: MouseButton,
};

/// Event corresponding to a size
pub const SizeEvent = struct {
    width: u32,
    height: u32,
};

pub const MenuEvent = struct {
    id: u32,
    item: *MenuInfo,

    pub fn toggle(self: *const @This(), state: bool) void {
        impl.toggleMenuItem(self.id, self.item, state);
    }
};

pub const WindowEvent = struct {
    window: *Window,
    event: Event,
};

pub const Event = union(enum) {
    /// Repaint request
    repaint,
    /// Close request
    close,
    /// Resize event pose
    resize: SizeEvent,
    /// Focus or Unfocus event post
    focused: bool,
    /// Key input event post
    key_input: KeyEvent,
    /// Mouse button input event post
    mouse_input: MouseEvent,
    /// Mouse move event post
    mouse_move: Point(u16),
    /// Mouse scroll event post
    mouse_scroll: ScrollEvent,
    /// Menu item event
    menu: MenuEvent,
    theme: enum { light, dark },
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

        head: ?*Node = null, // oldest
        tail: ?*Node = null, // newest
        count: usize = 0,

        pub const PushError = std.mem.Allocator.Error;

        /// Frees any remaining nodes. Ensure no threads are using the queue.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.mutex.lock();
            var cur = self.head;
            self.head = null;
            self.tail = null;
            self.count = 0;
            self.mutex.unlock();

            while (cur) |n| {
                const next = n.next;
                allocator.destroy(n);
                cur = next;
            }
        }

        /// Enqueue one value. Allocates a node; never blocks (aside from the lock).
        pub fn append(self: *Self, allocator: std.mem.Allocator, value: T) PushError!void {
            const n = try allocator.create(Node);
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
        pub fn pop(self: *Self, allocator: std.mem.Allocator) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const h = self.head orelse return null;

            // Detach head
            const next = h.next;
            self.head = next;
            if (next == null) self.tail = null;
            self.count -= 1;

            const result = h.value;
            allocator.destroy(h);
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

pub const EventLoop = struct {
    arena: std.heap.ArenaAllocator,

    windows: std.AutoArrayHashMapUnmanaged(usize, *Window) = .empty,
    queue: LinkedQueueUnmanaged(std.meta.Tuple(&.{ usize, Event })) = .{},

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn setAppId(self: *const @This(), app_id: []const u8) !void {
        try impl.setAppId(self.arena.allocator(), app_id);
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn createWindow(self: *@This(), opts: Window.Options) !*Window {
        const allocator = self.arena.allocator();

        const win = try allocator.create(Window);
        errdefer allocator.destroy(win);
        win.* = try .init(allocator, opts, self);

        try self.windows.put(allocator, win.id(), win);
        return win;
    }

    pub fn closeWindow(self: *@This(), id: usize) void {
        if (self.windows.get(id)) |win| {
            win.deinit();
            self.arena.allocator().destroy(win);
            _ = self.windows.swapRemove(id);
        }
    }

    pub fn isActive(self: *const @This()) bool {
        return self.windows.count() > 0;
    }

    /// Poll for a new event
    ///
    /// `null` if no new events else `WindowEvent`
    pub fn poll(self: *@This()) ?WindowEvent {
        _ = impl.poll();
        if (self.queue.pop(self.arena.allocator())) |data| {
            if (self.windows.get(data[0])) |win| {
                return .{ .window = win, .event = data[1] };
            }
        }
        return null;
    }

    /// Get the next event
    ///
    /// Blocks until polling returns the next event
    pub fn next(self: *@This()) WindowEvent {
        while (true) {
            if (self.poll()) |event| return event;
        }
    }

    pub fn handleEvent(self: *@This(), args: anytype) bool {
        const winId = impl.parseWindowId(args);
        if (self.windows.get(winId)) |win| {
            const event = impl.parseEvent(win, args);
            if (event) |e| {
                self.queue.append(self.arena.allocator(), .{ winId, e }) catch return false;
                return true;
            }
        }
        return false;
    }
};
