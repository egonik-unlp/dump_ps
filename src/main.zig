const std = @import("std");
const database = @import("database");
const types = @import("types");
const process = std.process.Child;
const pg = @import("pg");
const MAXPROCUPLOAD: u16 = 20;

fn capturePsOutput(allocator: std.mem.Allocator) !std.ArrayList(types.PsLine) {
    var proc = process.init(&[_][]const u8{ "ps", "aux" }, allocator);
    proc.stdout_behavior = .Pipe;
    try proc.spawn();
    var ouput_stream = proc.stdout.?.reader();
    const buffer = try ouput_stream.readAllAlloc(allocator, 1e6);
    defer allocator.free(buffer);
    const pss = try parsePsLine(allocator, buffer);
    for (pss.items) |psline| {
        const thresh = @as(f32, 1.0);
        if ((psline.percent_cpu > thresh or psline.percent_mem > thresh)) {
            std.debug.print("{}\n", .{psline});
        }
    }
    _ = try proc.wait();
    return pss;
}
fn parsePsLine(allocator: std.mem.Allocator, input: []const u8) !std.ArrayList(types.PsLine) {
    var lines = std.mem.tokenizeAny(u8, input, "\n");
    _ = lines.next(); // skip headers
    var ps = std.ArrayList(types.PsLine).init(allocator);
    errdefer {
        for (ps.items) |*it| {
            it.deinit(allocator) catch unreachable;
            ps.deinit();
        }
    }
    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, " ");
        const _user = tokens.next() orelse break;
        const user = try allocator.dupe(u8, _user);
        const pid = try std.fmt.parseInt(usize, tokens.next() orelse break, 10);
        const percent_cpu = try std.fmt.parseFloat(f32, tokens.next() orelse break);
        const percent_mem = try std.fmt.parseFloat(f32, tokens.next() orelse break);
        // Skip columns I don't care about.
        for (0..6) |_| {
            _ = tokens.next();
        }
        const _command = tokens.next() orelse break;
        const command = try allocator.dupe(u8, _command);
        const psline = types.PsLine{ .user = user, .pid = pid, .percent_cpu = percent_cpu, .percent_mem = percent_mem, .command = command };
        try ps.append(psline);
    }
    std.mem.sort(types.PsLine, ps.items, {}, sortLsLinesMem);
    return ps;
}

fn sortLsLinesMem(_: void, a: types.PsLine, b: types.PsLine) bool {
    return a.percent_mem > b.percent_mem;
}
fn sortLsLinesCpu(_: void, a: types.PsLine, b: types.PsLine) bool {
    return a.percent_cpu > b.percent_cpu;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const result_allocator = gpa.deinit();
        std.debug.print("{}\n", .{result_allocator});
    }
    const output = try capturePsOutput(gpa.allocator());
    defer {
        for (output.items) |*item| {
            item.deinit(gpa.allocator()) catch unreachable;
        }
        output.deinit();
    }
    const pool = try database.create_connection_with_string(gpa.allocator());
    defer pool.deinit();
    try database.create_event_table(pool);
    try database.create_table(pool);
    const id = try database.create_collection_event(pool);
    try database.insert_collection_data(pool, output.items, id, MAXPROCUPLOAD);
}
