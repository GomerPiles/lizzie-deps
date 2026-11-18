//! Deliberate package faults. The parent checks the resulting reports and attachments.
const std = @import("std");
const c = @import("crashpad");
pub const std_options: std.Options = .{ .enable_segfault_handler = false };
pub const panic = std.debug.FullPanic(panicReport);

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) return error.ExpectedHandlerReportsMode;
    const database = try std.fs.path.join(allocator, &.{ args[2], "database" });
    const evidence = try std.fs.path.join(allocator, &.{ args[2], "evidence.txt" });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = evidence, .data = "Crashpad attachment evidence\n" });
    const handler_z = try allocator.dupeSentinel(u8, args[1], 0);
    const database_z = try allocator.dupeSentinel(u8, database, 0);
    const evidence_z = try allocator.dupeSentinel(u8, evidence, 0);
    const attachments = [_][*c]const u8{evidence_z};
    const owner = c.lizzie_crashpad_start(handler_z, database_z, &attachments, 1) orelse return error.StartFailed;
    defer c.lizzie_crashpad_free(owner);
    if (c.lizzie_crashpad_set(owner, "proof", 5, "zig-package-smoke", 17) != 1) return error.AnnotationFailed;
    if (std.mem.eql(u8, args[3], "dump")) {
        c.lizzie_crashpad_dump();
        try std.Io.sleep(init.io, .fromSeconds(1), .awake);
    } else if (std.mem.eql(u8, args[3], "panic")) {
        @panic("Crashpad package Zig panic");
    } else if (std.mem.eql(u8, args[3], "worker_fault")) {
        const worker = try std.Thread.spawn(.{}, fault, .{});
        worker.join();
    } else return error.UnknownMode;
}

fn panicReport(_: []const u8, _: ?usize) noreturn {
    @trap();
}
fn fault() void {
    @setRuntimeSafety(false);
    @as(*allowzero volatile u8, @ptrFromInt(0)).* = 1;
}
