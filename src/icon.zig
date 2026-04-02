pub const Icon = union(enum) {
    symbol: Symbol,
    resource: []const u8,

    pub fn custom(p: []const u8) @This() {
        return .{ .resource = p };
    }

    pub const Default: @This() = .{ .symbol = .default };
    pub const Error: @This() = .{ .symbol = .@"error" };
    pub const Question: @This() = .{ .symbol = .question };
    pub const Warning: @This() = .{ .symbol = .warning };
    pub const Information: @This() = .{ .symbol = .information };
    pub const Security: @This() = .{ .symbol = .security };
};

pub const Symbol = enum {
    default,
    @"error",
    question,
    warning,
    information,
    security,
};
