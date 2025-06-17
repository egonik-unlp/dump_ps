const std = @import("std");
const pg = @import("pg");
const types = @import("types");
const DatabaseError = error{creation_error};
const dbrow = struct {
    actual_name: []const u8,
    info_para_reporte: []const u8,
    cita: []const u8,
    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;
        try writer.print("DbRow {{.actual_name : {s}, .info_para_reporte: {s}, .cita: {s} }} ", .{ self.actual_name, self.info_para_reporte, self.cita });
    }
};
pub fn create_connection(allocator: std.mem.Allocator) !*pg.Pool {
    const pool = try pg.Pool.init(allocator, .{ .size = 5, .connect = .{
        .port = 5432,
        .host = "127.0.0.1",
    }, .auth = .{
        .username = "postgres",
        .database = "postgres",
        .password = "example",
        .timeout = 10_000,
    } });
    return pool;
}
pub fn create_event_table(pool: *pg.Pool) !void {
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec("create table if not exists event_logs (id serial primary key, timestamp bigint)", .{});
}
pub fn create_event(pool: *pg.Pool) !i32 {
    var conn = try pool.acquire();
    defer {
        conn.commit() catch unreachable;
        conn.release();
    }
    const timestamp = std.time.timestamp();
    const result = conn.query("insert into event_logs (timestamp) values ($1) returning id;", .{timestamp}) catch |err| {
        if (conn.err) |pg_err| {
            std.debug.print("PG error = {s}", .{pg_err.message});
        } else {
            std.debug.print("Other error = {}", .{err});
        }
        return err;
    };

    defer result.deinit();
    var id: ?i32 = null;
    if (try result.next()) |row| {
        id = row.get(i32, 0);
    }
    while (try result.next()) |_| {}
    return id orelse DatabaseError.creation_error;
}

pub fn create_table(pool: *pg.Pool) !void {
    const q = "create table if not exists pslines ( id serial primary key ,username varchar, pid integer, percent_cpu real, percent_mem real, command varchar, event_id int4,  foreign key (event_id) references event_logs(id))";
    var conn = try pool.acquire();
    defer conn.release();
    _ = conn.exec(q, .{}) catch |err| {
        if (conn.err) |pg_err| {
            std.debug.print("Error creando tabla = {s}\n", .{pg_err.message});
        } else {
            std.debug.print("Error que ocurre {}\n", .{err});
        }
        return err;
    };
}

pub fn drop_tables(pool: *pg.Pool) !void {
    var conn = try pool.acquire();
    defer conn.release();
    _ = try conn.exec("drop table if exists pslines", .{});
    _ = try conn.exec("drop table if exists event_logs", .{});
    _ = conn.exec("drop table if exists log_events", .{}) catch |err| {
        std.debug.print("Can't delete log_events err = {}\n", .{err});
    };
}

const Log = struct { id: i32, timestamp: i64 };

pub fn get_event(pool: *pg.Pool, last_transaction_id: i32) !void {
    var conn = try pool.acquire();
    defer conn.release();
    var result = try conn.queryOpts("select * from event_logs", .{}, .{ .column_names = true });
    defer result.deinit();
    var mapper = result.mapper(Log, .{ .dupe = true });
    while (try mapper.next()) |log| {
        std.debug.print("{any} -  {} \n", .{ log, last_transaction_id });
    }
}

pub fn insert_data_to_table(pool: *pg.Pool, instances: []types.PsLine, event_id: i32, MAX: u16) !void {
    var conn = try pool.acquire();
    defer conn.release();
    for (instances, 0..) |instance, count| {
        if (count < MAX) {
            _ = conn.exec("insert into pslines (username, pid, percent_cpu, percent_mem, command, event_id) values ($1, $2, $3, $4, $5, $6)", .{ instance.user, instance.pid, instance.percent_cpu, instance.percent_mem, instance.command, event_id }) catch |err| {
                if (conn.err) |pgerr| {
                    std.debug.print("Error con la db insertando data = {s}\n", .{pgerr.message});
                } else {
                    std.debug.print("Otro error = {}", .{err});
                }
            };
        }
    }
}
