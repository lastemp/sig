const std = @import("std");
const time = @import("../time/time.zig");
const Field = @import("field.zig").Field;
const Level = @import("level.zig").Level;
const logfmt = @import("logfmt.zig");
const Logger = @import("./log.zig").Logger;
const Channel = @import("../sync/channel.zig").Channel;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const AtomicBool = std.atomic.Atomic(bool);

pub const Entry = union(enum) {
    standard: *StandardEntry,
    noop,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, channel: *Channel(*StandardEntry)) Self {
        return .{ .standard = StandardEntry.init(allocator, channel) };
    }

    pub fn deinit(self: Self) void {
        switch (self) {
            .standard => |entry| {
                entry.deinit();
            },
            .noop => {},
        }
    }

    pub fn field(self: Self, name: []const u8, value: anytype) Self {
        switch (self) {
            .standard => |entry| {
                _ = entry.field(name, value);
                return self;
            },
            .noop => {
                return self;
            },
        }
    }

    pub fn debugf(self: Self, comptime fmt: []const u8, args: anytype) void {
        switch (self) {
            .standard => |entry| {
                entry.logf(.debug, fmt, args);
            },
            .noop => {},
        }
    }

    pub fn errf(self: Self, comptime fmt: []const u8, args: anytype) void {
        switch (self) {
            .standard => |entry| {
                entry.logf(.err, fmt, args);
            },
            .noop => {},
        }
    }

    pub fn warnf(self: Self, comptime fmt: []const u8, args: anytype) void {
        switch (self) {
            .standard => |entry| {
                entry.logf(.warn, fmt, args);
            },
            .noop => {},
        }
    }

    pub fn infof(self: Self, comptime fmt: []const u8, args: anytype) void {
        switch (self) {
            .standard => |entry| {
                entry.logf(.info, fmt, args);
            },
            .noop => {},
        }
    }

    pub fn info(self: Self, msg: []const u8) void {
        switch (self) {
            .standard => |entry| {
                entry.log(.info, msg);
            },
            .noop => {},
        }
    }

    pub fn debug(self: Self, msg: []const u8) void {
        switch (self) {
            .standard => |entry| {
                entry.log(.debug, msg);
            },
            .noop => {},
        }
    }

    pub fn err(self: Self, msg: []const u8) void {
        switch (self) {
            .standard => |entry| {
                entry.log(.err, msg);
            },
            .noop => {},
        }
    }

    pub fn warn(self: Self, msg: []const u8) void {
        switch (self) {
            .standard => |entry| {
                entry.log(.warn, msg);
            },
            .noop => {},
        }
    }

    pub fn format(
        self: *const Self,
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .standard => |entry| {
                try entry.format(fmt, options, writer);
            },
            .noop => {},
        }
    }

    pub fn custom_format(self: *const Self, formatter: anytype, writer: anytype) !void {
        switch (self) {
            .standard => |entry| {
                try formatter(entry, writer);
            },
            .noop => {},
        }
    }
};

pub const StandardEntry = struct {
    level: Level,
    allocator: std.mem.Allocator,
    fields: std.ArrayList(Field),
    time: time.DateTime,
    message: std.ArrayList(u8),
    channel: *Channel(*StandardEntry),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, channel: *Channel(*StandardEntry)) *Self {
        var self = allocator.create(Self) catch @panic("could not allocate.Create Entry");
        self.* = Self{
            .allocator = allocator,
            .fields = std.ArrayList(Field).init(allocator),
            .level = Level.debug,
            .channel = channel,
            .time = time.DateTime.epoch_unix,
            .message = std.ArrayList(u8).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.fields.items) |*f| {
            f.deinit(self.allocator);
        }
        self.fields.deinit();
        self.message.deinit();
        self.allocator.destroy(self);
    }

    pub fn field(self: *Self, name: []const u8, value: anytype) *Self {
        self.fields.append(Field.init(self.allocator, name, value)) catch @panic("could not append Field");
        return self;
    }

    pub fn logf(self: *Self, level: Level, comptime fmt: []const u8, args: anytype) void {
        var message = std.ArrayList(u8).initCapacity(self.allocator, fmt.len * 2) catch @panic("could not initCapacity for message");
        std.fmt.format(message.writer(), fmt, args) catch @panic("could not format");
        self.message = message;
        self.time = time.DateTime.now();
        self.level = level;
        self.channel.send(self) catch @panic("could not send to channel");
    }

    pub fn log(self: *Self, level: Level, msg: []const u8) void {
        var message = std.ArrayList(u8).initCapacity(self.allocator, msg.len) catch @panic("could not initCapacity for message");
        message.appendSlice(msg[0..]) catch @panic("could not appendSlice for message");
        self.message = message;
        self.time = time.DateTime.now();
        self.level = level;
        self.channel.send(self) catch @panic("could not send to channel");
    }

    pub fn format(
        self: *const Self,
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        // default formatting style
        try logfmt.formatter(self, writer);
    }

    pub fn custom_format(self: *const Self, formatter: anytype, writer: anytype) !void {
        try formatter(self, writer);
    }
};

const A = enum(u8) {
    some_enum_variant,
};

test "trace.entry: should info log correctly" {
    var logger = Logger.init(testing.allocator, Level.info);
    defer logger.deinit();
    var entry = StandardEntry.init(testing.allocator, logger.standard.channel);
    defer entry.deinit();

    var anull: ?u8 = null;

    entry
        .field("some_val", true)
        .field("enum_field", A.some_enum_variant)
        .field("name", "a-mod")
        .field("elapsed", @as(i48, 135133340042))
        .field("possible_value", anull)
        .logf(.info, "hello, {s}", .{"world!"});

    std.debug.print("{any}\n\n", .{logger});
}
