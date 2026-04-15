const std = @import("std");
const input = @import("input.zig");

const Window = @import("window.zig").Window;
const Theme = @import("window.zig").Theme;
const Visibility = @import("window.zig").Visibility;
const Key = input.Key;
const VirtualKey = input.VirtualKey;
const MouseButton = input.MouseButton;
const Point = @import("root.zig").Point;

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
    /// Mouse Position
    pos: Point(i32),
};

/// Event corresponding to a size
pub const SizeEvent = struct {
    width: u32,
    height: u32,
};

pub const DeviceEvent = union(enum) {
    added,
    removed,
    mouse_delta: struct { x: i32 = 0, y: i32 = 0  },
    mouse_wheel: struct { horizontal: f32 = 0.0, vertical: f32 = 0.0  },
    delta: struct { axis: u32, value: i32 },
    button: struct {
        id: usize,
        state: ButtonState,
    },
    key: struct {
        key: VirtualKey,
        state: ButtonState,
    }
};

pub const WindowEvent = union(enum) {
    /// Close request
    close,
    /// Resize event pose
    resize: SizeEvent,
    /// Focus or Unfocus event post
    focused: bool,
    /// Key input event post
    key: KeyEvent,
    /// Mouse button input event post
    mouse: MouseEvent,
    /// Mouse move event position
    move: Point(i32),
    /// Mouse enter
    enter: void,
    /// Mouse leave
    leave: void,
    /// Mouse scroll event post
    scroll: ScrollEvent,
    /// Change in window visibility
    visibility: Visibility,
    /// Menu item selected
    menu: MenuEvent,
    /// Window theme changed
    theme: Theme,
};

pub const MenuEvent = struct {
    kind: Kind,
    target: u32,

    pub const Kind = enum { window, taskbar };
};

pub const UserEvent = struct {
    id: u32,
    payload: u32,

    pub fn into(self: @This(), comptime T: type) T {
        return switch (@typeInfo(T)) {
            .@"enum" => @enumFromInt(self.payload),
            .int => |i| switch (i.signedness) {
                .signed => @intCast(@as(i32, @bitCast(self.payload))),
                .unsigned => @intCast(self.payload)
            },
            else => @compileError("unsupported payload type")
        };
    }
};

pub const Event = union(enum) {
    window: struct {
        target: *Window,
        event: WindowEvent,
    },
    device: struct {
        id: usize,
        event: DeviceEvent,
    },
    user: UserEvent
};

pub const QueuedEvent = union(enum) {
    destroy: usize,
    user: UserEvent,
    device: struct {
        id: usize,
        event: DeviceEvent,
    },
    window: struct {
        target: usize,
        event: WindowEvent,
    },
};

/// Linked queue (unbounded except by memory).
/// - Non-blocking: tryPop returns null when empty; push allocates a node per item.
/// - No Conditions/Mutexes. Just atomic pointer handoff.
pub fn LinkedQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            next: ?*Node,
            value: T,
        };

        allocator: std.mem.Allocator,

        mutex: std.Thread.Mutex = .{},

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
                const next = n.next;
                self.allocator.destroy(n);
                cur = next;
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

        /// Clear all items in the queue freeing the memeory
        /// and resetting the queue to 0 items.
        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var next = self.head;
            self.head = null;
            self.count = 0;

            while (next) |n| {
                next = n.next;
                self.allocator.destroy(n);
            }
        }

        /// Dequeue one value if available; returns null when empty.
        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const h = self.head orelse return null;

            // Detach head
            const next = h.next;
            self.head = next;
            if (next == null) self.tail = null;
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

pub const EventQueue = LinkedQueue(QueuedEvent);

pub const EventLoop = switch (@import("builtin").target.os.tag) {
    .windows => @import("windows/event.zig"),
    // TODO: Make a linux wrapper that will use wayland and fallback to x11
    .linux => @import("linux/wayland/event.zig"),
    else => @compileError("unsupported platform"),
};
