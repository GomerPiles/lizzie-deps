//! Applies and verifies Maker's installation/fork gate in derived Zig bundles.
//! Remove when upstream prevents installation writers from leaking into children.
const std = @import("std");
const Io = std.Io;

const marker = "Lizzie Linux Maker: installation and process creation share an owned gate.\n";
const helper_path = "lib/compiler/Maker/InstallGuard.zig";
const helper = @embedFile("InstallGuard.zig");
const Replacement = struct { before: []const u8, after: []const u8, count: usize = 1 };
const maker_replacements = [_]Replacement{
    .{
        .before = "scanned_config: *const ScannedConfig,\n",
        .after = "scanned_config: *const ScannedConfig,\ninstall_guard: @import(\"Maker/InstallGuard.zig\") = .{},\n",
    },
    .{ .before = "    return Dir.updateFile(\n", .after = "    return maker.install_guard.updateFile(\n" },
};
const step_replacements = [_]Replacement{
    .{ .before = "std.process.run(allocator, io, .{", .after = "maker.install_guard.run(allocator, io, .{" },
    .{ .before = "std.process.spawn(io, .{", .after = "maker.install_guard.spawn(io, .{" },
};
const run_replacements = [_]Replacement{
    .{ .before = "process.spawn(io, spawn_options)", .after = "maker.install_guard.spawn(io, spawn_options)", .count = 3 },
};
const files = .{
    .{ "lib/compiler/Maker.zig", &maker_replacements },
    .{ "lib/compiler/Maker/Step.zig", &step_replacements },
    .{ "lib/compiler/Maker/Step/Run.zig", &run_replacements },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.ExpectedApplyOrVerifyAndDistribution;
    var dir = try Io.Dir.cwd().openDir(init.io, args[2], .{});
    defer dir.close(init.io);
    if (std.mem.eql(u8, args[1], "verify")) {
        const observed = try dir.readFileAlloc(init.io, "LIZZIE-INSTALL-GUARD.txt", allocator, .limited(4096));
        if (!std.mem.eql(u8, marker, observed)) return error.WrongInstallGuardPatch;
        const installed_helper = try dir.readFileAlloc(init.io, helper_path, allocator, .limited(65536));
        if (!std.mem.eql(u8, helper, installed_helper)) return error.WrongInstallGuardPatch;
        inline for (files) |file| {
            const source = try dir.readFileAlloc(init.io, file[0], allocator, .limited(1024 * 1024));
            for (file[1]) |replacement| {
                if (std.mem.count(u8, source, replacement.after) != replacement.count)
                    return error.WrongInstallGuardPatch;
            }
        }
        return;
    }
    if (!std.mem.eql(u8, args[1], "apply")) return error.ExpectedApplyOrVerify;
    var patched: [files.len][]const u8 = undefined;
    inline for (files, 0..) |file, index| {
        var source: []const u8 = try dir.readFileAlloc(init.io, file[0], allocator, .limited(1024 * 1024));
        for (file[1]) |replacement| source = try replace(allocator, source, replacement);
        patched[index] = source;
    }
    // Review every source anchor before changing any file. Configure-script
    // launches precede Maker creation and installation, so they need no gate.
    inline for (files, 0..) |file, index| {
        try dir.writeFile(init.io, .{ .sub_path = file[0], .data = patched[index] });
    }
    try dir.writeFile(init.io, .{ .sub_path = helper_path, .data = helper });
    try dir.writeFile(init.io, .{ .sub_path = "LIZZIE-INSTALL-GUARD.txt", .data = marker });
}

fn replace(allocator: std.mem.Allocator, source: []const u8, replacement: Replacement) ![]const u8 {
    if (std.mem.count(u8, source, replacement.before) != replacement.count or
        std.mem.count(u8, source, replacement.after) != 0)
        return error.UpstreamMakerChanged;
    return std.mem.replaceOwned(u8, allocator, source, replacement.before, replacement.after);
}

test "install patch rejects absent and ambiguous upstream anchors" {
    const allocator = std.testing.allocator;
    const replacement: Replacement = .{ .before = "x", .after = "patched" };
    try std.testing.expectError(error.UpstreamMakerChanged, replace(allocator, "none", replacement));
    try std.testing.expectError(error.UpstreamMakerChanged, replace(allocator, "xx", replacement));
    const result = try replace(allocator, "before x after", replacement);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("before patched after", result);
}
