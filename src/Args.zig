//! A simple argument parser

process_args: ?[][:0]u8,
args: []const []const u8,
index: usize,
consumed: bool,
positionals_only: bool,

pub fn initArgs(gpa: std.mem.Allocator) !Args {
    const args = try std.process.argsAlloc(gpa);
    return .{
        .process_args = args,
        .args = args[1..],
        .index = 0,
        .consumed = false,
        .positionals_only = false,
    };
}

pub fn initSlice(args: []const []const u8) Args {
    return .{
        .process_args = null,
        .args = args,
        .index = 0,
        .consumed = false,
        .positionals_only = false,
    };
}

pub fn deinit(args: *Args, gpa: std.mem.Allocator) void {
    if (args.process_args) |process_args|
        std.process.argsFree(gpa, process_args);
    args.* = undefined;
}

pub fn next(args: *Args) bool {
    args.consumed = args.index >= args.args.len;
    return !args.consumed;
}

pub fn flag(args: *Args, names: []const []const u8) bool {
    if (args.consumed or args.positionals_only)
        return false;

    for (names) |name| {
        if (!std.mem.eql(u8, args.args[args.index], name))
            continue;

        args.consumed = true;
        args.index += 1;
        return true;
    }

    return false;
}

pub fn option(args: *Args, names: []const []const u8) ?[]const u8 {
    if (args.consumed or args.positionals_only)
        return null;

    const arg = args.args[args.index];
    for (names) |name| {
        if (!std.mem.startsWith(u8, arg, name))
            continue;
        if (!std.mem.startsWith(u8, arg[name.len..], "="))
            continue;

        args.consumed = true;
        args.index += 1;
        return arg[name.len + 1 ..];
    }

    if (args.index + 1 < args.args.len) {
        if (args.flag(names))
            return args.eat();
    }

    return null;
}

pub fn positional(args: *Args) ?[]const u8 {
    if (args.consumed)
        return null;

    const res = args.eat();
    args.consumed = true;

    if (!args.positionals_only and std.mem.eql(u8, res, "--")) {
        args.positionals_only = true;
        return null;
    }
    return res;
}

fn eat(args: *Args) []const u8 {
    defer args.index += 1;
    return args.args[args.index];
}

test flag {
    var args = Args.initSlice(&.{
        "-a",
        "--beta",
        "command",
    });
    defer args.deinit(std.testing.allocator);

    try std.testing.expect(args.flag(&.{ "-a", "--alpha" }));
    try std.testing.expect(!args.flag(&.{ "-b", "--beta" }));
    try std.testing.expect(!args.flag(&.{"command"}));

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try std.testing.expect(args.flag(&.{ "-b", "--beta" }));
    try std.testing.expect(!args.flag(&.{"command"}));

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try std.testing.expect(!args.flag(&.{ "-b", "--beta" }));
    try std.testing.expect(args.flag(&.{"command"}));

    try std.testing.expect(!args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try std.testing.expect(!args.flag(&.{ "-b", "--beta" }));
    try std.testing.expect(!args.flag(&.{"command"}));
}

fn expectEqualOptionalString(m_expect: ?[]const u8, m_actual: ?[]const u8) !void {
    if (m_expect) |expect| {
        try std.testing.expect(m_actual != null);
        try std.testing.expectEqualStrings(expect, m_actual.?);
    } else {
        try std.testing.expect(m_actual == null);
    }
}

test option {
    var args = Args.initSlice(&.{
        "-a",
        "a_value",
        "--beta=b_value",
        "command",
        "command_value",
    });
    defer args.deinit(std.testing.allocator);

    try expectEqualOptionalString("a_value", args.option(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{"command"}));

    try std.testing.expect(args.next());
    try expectEqualOptionalString(null, args.option(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString("b_value", args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{"command"}));

    try std.testing.expect(args.next());
    try expectEqualOptionalString(null, args.option(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString("command_value", args.option(&.{"command"}));

    try std.testing.expect(!args.next());
    try expectEqualOptionalString(null, args.option(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{"command"}));
}

test positional {
    var args = Args.initSlice(&.{
        "-a",
        "--beta",
        "command",
    });
    defer args.deinit(std.testing.allocator);

    try expectEqualOptionalString("-a", args.positional());
    try std.testing.expect(args.next());
    try expectEqualOptionalString("--beta", args.positional());
    try std.testing.expect(args.next());
    try expectEqualOptionalString("command", args.positional());
    try std.testing.expect(!args.next());
    try expectEqualOptionalString(null, args.positional());
}

test "all" {
    var args = Args.initSlice(&.{
        "-a",
        "--beta",
        "b_value",
        "-c=c_value",
        "command",
    });
    defer args.deinit(std.testing.allocator);

    try std.testing.expect(args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString(null, args.positional());

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString("b_value", args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString(null, args.positional());

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString("c_value", args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString(null, args.positional());

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString("command", args.positional());

    try std.testing.expect(!args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString(null, args.positional());
}

test "all positionals" {
    var args = Args.initSlice(&.{
        "--",
        "-a",
        "--beta",
        "b_value",
        "-c=c_value",
        "command",
    });
    defer args.deinit(std.testing.allocator);

    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString(null, args.positional());

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString("-a", args.positional());

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString("--beta", args.positional());

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString("b_value", args.positional());

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString("-c=c_value", args.positional());

    try std.testing.expect(args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString("command", args.positional());

    try std.testing.expect(!args.next());
    try std.testing.expect(!args.flag(&.{ "-a", "--alpha" }));
    try expectEqualOptionalString(null, args.option(&.{ "-b", "--beta" }));
    try expectEqualOptionalString(null, args.option(&.{ "-c", "--center" }));
    try expectEqualOptionalString(null, args.positional());
}

// Example
test Args {
    var args = Args.initSlice(&.{
        "--flag",
        "--option=option",
        "positional",
    });
    defer args.deinit(std.testing.allocator);

    var f = false;
    var o: ?[]const u8 = null;
    var p: ?[]const u8 = null;

    while (args.next()) {
        if (args.flag(&.{ "-f", "--flag" }))
            f = true;
        if (args.option(&.{ "-o", "--option" })) |v|
            o = v;
        if (args.positional()) |v|
            p = v;
    }

    try std.testing.expect(f);
    try std.testing.expect(o != null);
    try std.testing.expectEqualStrings("option", o.?);
    try std.testing.expect(p != null);
    try std.testing.expectEqualStrings("positional", p.?);
}

const Args = @This();

const std = @import("std");
