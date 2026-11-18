const std = @import("std");
pub fn build(b: *std.Build) void {
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = b.graph.host,
    }) });
    const translated = b.addTranslateC(.{
        .root_source_file = b.path("check.h"),
        .target = b.graph.host,
        .optimize = .debug,
    });
    tests.root_module.addImport("translated", translated.createModule());
    b.step("test", "Check compiler resource controls").dependOn(&b.addRunArtifact(tests).step);
}
