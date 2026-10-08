//! Links only the packaged public C interface, exactly as a Zig consumer would.
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const package = b.option([]const u8, "package", "Absolute unpacked package path") orelse @panic("-Dpackage required");
    const translated = b.addTranslateC(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ package, "include/lizzie_crashpad.h" }) },
        .target = target,
        .optimize = optimize,
    });
    const module = b.createModule(.{
        .root_source_file = b.path("smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("crashpad", translated.createModule());
    const exe = b.addExecutable(.{ .name = "smoke", .root_module = module });
    const windows = target.result.os.tag == .windows;
    module.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ package, "lib", if (windows) "lizzie_crashpad.lib" else "liblizzie_crashpad.a" }) });
    if (windows) {
        b.getInstallStep().dependOn(&b.addInstallBinFile(.{ .cwd_relative = b.pathJoin(&.{ package, "bin/lizzie_crashpad.dll" }) }, "lizzie_crashpad.dll").step);
    } else if (target.result.os.tag == .macos) {
        module.linkSystemLibrary("c++.1", .{});
        module.linkSystemLibrary("bsm", .{});
        module.linkSystemLibrary("z", .{});
        for ([_][]const u8{ "Foundation", "CoreFoundation", "Security" }) |framework| module.linkFramework(framework, .{});
    } else {
        module.link_libcpp = true;
        for ([_][]const u8{ "dl", "pthread", "rt" }) |library| module.linkSystemLibrary(library, .{});
    }
    b.installArtifact(exe);
}
