//! Applies and verifies the build-runner worker limit in derived compiler bundles.
//! The compiler binary and target-program threading semantics remain upstream's.
const std = @import("std");
const Io = std.Io;

const marker = "Lizzie build runner: LIZZIE_COMPILER_JOBS, default 2; positive u16.\n";
const compile_path = "lib/compiler/Maker/Step/Compile.zig";
const translate_path = "lib/compiler/Maker/Step/TranslateC.zig";
const worker_count =
    \\    const worker_count = std.fmt.parseInt(u16, graph.environ_map.get("LIZZIE_COMPILER_JOBS") orelse "2", 10) catch
    \\        return step.fail(maker, "LIZZIE_COMPILER_JOBS must be a positive u16", .{});
    \\    if (worker_count == 0) return step.fail(maker, "LIZZIE_COMPILER_JOBS must be positive", .{});
    \\
;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.ExpectedApplyOrVerifyAndDistribution;
    var dir = try Io.Dir.cwd().openDir(init.io, args[2], .{});
    defer dir.close(init.io);
    if (std.mem.eql(u8, args[1], "verify")) {
        const observed = try dir.readFileAlloc(init.io, "LIZZIE-COMPILER-JOBS.txt", allocator, .limited(4096));
        if (!std.mem.eql(u8, marker, observed)) return error.WrongBuildRunnerPatch;
        for ([_][]const u8{ compile_path, translate_path }) |path| {
            const source = try dir.readFileAlloc(init.io, path, allocator, .limited(1024 * 1024));
            if (std.mem.count(u8, source, worker_count) != 1) return error.WrongBuildRunnerPatch;
        }
        return;
    }
    if (!std.mem.eql(u8, args[1], "apply")) return error.ExpectedApplyOrVerify;
    const compile_source = try dir.readFileAlloc(init.io, compile_path, allocator, .limited(1024 * 1024));
    const compiled = try replaceOnce(allocator, compile_source, "    try zig_args.append(gpa, cmd);\n", "    try zig_args.append(gpa, cmd);\n\n" ++ worker_count ++
        "    try zig_args.append(gpa, try arena.print(\"-j{d}\", .{worker_count}));\n");
    const translate_source = try dir.readFileAlloc(init.io, translate_path, allocator, .limited(1024 * 1024));
    const translated = try replaceOnce(allocator, translate_source, "    argv.appendAssumeCapacity(\"translate-c\");\n", "    argv.appendAssumeCapacity(\"translate-c\");\n\n" ++ worker_count ++
        "    try argv.append(arena, try arena.print(\"-j{d}\", .{worker_count}));\n" ++
        "    try argv.ensureUnusedCapacity(arena, 10);\n");
    // Validate both source anchors before changing either file. An upstream change
    // requires reviewing the patch, never silently skipping it.
    try dir.writeFile(init.io, .{ .sub_path = compile_path, .data = compiled });
    try dir.writeFile(init.io, .{ .sub_path = translate_path, .data = translated });
    try dir.writeFile(init.io, .{ .sub_path = "LIZZIE-COMPILER-JOBS.txt", .data = marker });
}

fn replaceOnce(allocator: std.mem.Allocator, source: []const u8, needle: []const u8, replacement: []const u8) ![]const u8 {
    if (std.mem.count(u8, source, needle) != 1) return error.UpstreamBuildRunnerChanged;
    const at = std.mem.indexOf(u8, source, needle).?;
    return std.mem.concat(allocator, u8, &.{ source[0..at], replacement, source[at + needle.len ..] });
}

test "patch rejects absent and ambiguous upstream anchors" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.UpstreamBuildRunnerChanged, replaceOnce(allocator, "old", "new", "patched"));
    try std.testing.expectError(error.UpstreamBuildRunnerChanged, replaceOnce(allocator, "xx", "x", "patched"));
    const result = try replaceOnce(allocator, "before x after", "x", "patched");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("before patched after", result);
}
