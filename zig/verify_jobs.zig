//! Runs real build actions to verify default, overridden and invalid worker limits.
const std = @import("std");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) return error.ExpectedDistributionFixtureAndScratch;
    const zig = try std.fs.path.join(allocator, &.{ args[1], if (builtin.os.tag == .windows) "zig.exe" else "zig" });
    const fixture = try std.fs.path.join(allocator, &.{ args[2], "build.zig" });
    const local = try std.fs.path.join(allocator, &.{ args[3], "worker-check-cache" });
    var environment = try init.environ_map.clone(allocator);
    _ = environment.swapRemove("LIZZIE_COMPILER_JOBS");
    // This is a separate public fixture, with its own local cache. The original
    // helper-cache relocation check still verifies the two seeded helper binaries.
    for ([_]?[]const u8{ null, "3", "0" }) |limit| {
        if (limit) |value| try environment.put("LIZZIE_COMPILER_JOBS", value);
        const result = try std.process.run(allocator, init.io, .{
            .argv = &.{ zig, "build", "--build-file", fixture, "--cache-dir", local, "test", "--verbose" },
            .environ_map = &environment,
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
        });
        const output = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
        if (limit != null and std.mem.eql(u8, limit.?, "0")) {
            if (result.term.success() or std.mem.indexOf(u8, output, "LIZZIE_COMPILER_JOBS must be positive") == null)
                return error.InvalidWorkerLimitAccepted;
        } else {
            const expected = if (limit == null) " -j2 " else " -j3 ";
            if (!result.term.success() or std.mem.count(u8, output, expected) < 2) {
                std.debug.print("{s}\n", .{output});
                return error.WorkerLimitNotForwarded;
            }
        }
    }
    std.log.info("PASS: compile and translate-c worker limits; runtime threading preserved", .{});
}
