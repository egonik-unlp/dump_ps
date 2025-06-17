const std = @import("std");

pub const PsLine = struct {
    user: []const u8,
    pid: usize,
    percent_cpu: f32,
    percent_mem: f32,
    command: []const u8,
    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("PsLine {{user: {s}, pid: {d}, percent_cpu: {d}, percent_mem: {d}, command: {s}}}", .{ self.user, self.pid, self.percent_cpu, self.percent_mem, self.command });
    }
    pub fn deinit(self: *PsLine, allocator: std.mem.Allocator) !void {
        allocator.free(self.user);
        allocator.free(self.command);
    }
};
