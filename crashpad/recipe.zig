//! Infrequent dependency production: fetch, tools, build, package and smoke.
//! GN's upstream Python actions remain upstream; all first-party orchestration is Zig.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Target = enum {
    @"aarch64-macos",
    @"x86_64-linux-gnu",
    @"aarch64-linux-gnu",
    @"x86_64-windows",

    fn windows(self: Target) bool {
        return self == .@"x86_64-windows";
    }
    fn linux(self: Target) bool {
        return self == .@"x86_64-linux-gnu" or self == .@"aarch64-linux-gnu";
    }
    fn cpu(self: Target) []const u8 {
        return switch (self) {
            .@"aarch64-macos" => "apple_m1",
            .@"aarch64-linux-gnu" => "generic+v8_2a",
            else => "x86_64_v3",
        };
    }
    fn triple(self: Target) []const u8 {
        return switch (self) {
            .@"x86_64-linux-gnu" => "x86_64-linux-gnu.2.28",
            .@"aarch64-linux-gnu" => "aarch64-linux-gnu.2.28",
            .@"x86_64-windows" => "x86_64-windows-msvc",
            .@"aarch64-macos" => "aarch64-macos",
        };
    }
};

const Recipe = struct {
    allocator: std.mem.Allocator,
    io: Io,
    environment: *std.process.Environ.Map,

    fn format(self: Recipe, comptime fmt: []const u8, args: anytype) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, fmt, args);
    }
    fn path(self: Recipe, parts: []const []const u8) ![]const u8 {
        return std.fs.path.join(self.allocator, parts);
    }
    fn mkdir(self: Recipe, name: []const u8) !void {
        try Io.Dir.cwd().createDirPath(self.io, name);
    }
    fn write(self: Recipe, name: []const u8, bytes: []const u8) !void {
        if (std.fs.path.dirname(name)) |parent| try self.mkdir(parent);
        try Io.Dir.cwd().writeFile(self.io, .{ .sub_path = name, .data = bytes });
    }
    fn read(self: Recipe, name: []const u8) ![]const u8 {
        return Io.Dir.cwd().readFileAlloc(self.io, name, self.allocator, .limited(64 * 1024 * 1024));
    }
    fn absolute(self: Recipe, name: []const u8) ![]const u8 {
        return Io.Dir.cwd().realPathFileAlloc(self.io, name, self.allocator);
    }
    fn execute(self: Recipe, argv: []const []const u8, cwd: ?[]const u8) !std.process.Child.Term {
        std.log.info("{s}", .{try std.mem.join(self.allocator, " ", argv)});
        var child = try std.process.spawn(self.io, .{
            .argv = argv,
            .cwd = if (cwd) |value| .{ .path = value } else .inherit,
            .environ_map = self.environment,
            .stdin = .ignore,
        });
        return child.wait(self.io);
    }
    fn run(self: Recipe, argv: []const []const u8, cwd: ?[]const u8) !void {
        const term = try self.execute(argv, cwd);
        if (term != .exited or term.exited != 0) {
            std.log.err("command failed: {any}", .{term});
            return error.CommandFailed;
        }
    }
    fn capture(self: Recipe, argv: []const []const u8, cwd: ?[]const u8) ![]const u8 {
        const result = try std.process.run(self.allocator, self.io, .{
            .argv = argv,
            .cwd = if (cwd) |value| .{ .path = value } else .inherit,
            .environ_map = self.environment,
            .stdout_limit = .limited(4 * 1024 * 1024),
        });
        if (result.term != .exited or result.term.exited != 0) {
            std.log.err("{s}\n{s}", .{ result.stdout, result.stderr });
            return error.CommandFailed;
        }
        return result.stdout;
    }
    fn zig(self: Recipe) []const u8 {
        return self.environment.get("ZIG") orelse "zig";
    }
    fn verifySources(self: Recipe, root: []const u8) !void {
        var lines = std.mem.tokenizeScalar(u8, @embedFile("SOURCES"), '\n');
        while (lines.next()) |line| {
            if (line[0] == '#') continue;
            var words = std.mem.tokenizeScalar(u8, line, ' ');
            _ = words.next().?;
            const revision = words.next().?;
            _ = words.next().?;
            const destination = try self.path(&.{ root, words.next().? });
            const head = try self.capture(&.{ "git", "-C", destination, "rev-parse", "HEAD" }, null);
            if (!std.mem.eql(u8, std.mem.trim(u8, head, "\r\n"), revision)) return error.SourceRevisionMismatch;
        }
    }
    fn fetch(self: Recipe, root: []const u8) !void {
        var lines = std.mem.tokenizeScalar(u8, @embedFile("SOURCES"), '\n');
        while (lines.next()) |line| {
            if (line[0] == '#') continue;
            var words = std.mem.tokenizeScalar(u8, line, ' ');
            _ = words.next() orelse return error.InvalidSourcePin;
            const revision = words.next() orelse return error.InvalidSourcePin;
            const url = words.next() orelse return error.InvalidSourcePin;
            const destination = try self.path(&.{ root, words.next() orelse return error.InvalidSourcePin });
            if (revision.len != 40) return error.InvalidSourcePin;
            try self.mkdir(destination);
            try self.run(&.{ "git", "init", "-q", destination }, null);
            try self.run(&.{ "git", "-C", destination, "-c", "core.autocrlf=false", "fetch", "--depth=1", url, revision }, null);
            try self.run(&.{ "git", "-C", destination, "-c", "core.autocrlf=false", "checkout", "--detach", "FETCH_HEAD" }, null);
            const head = try self.capture(&.{ "git", "-C", destination, "rev-parse", "HEAD" }, null);
            if (!std.mem.eql(u8, std.mem.trim(u8, head, "\r\n"), revision)) return error.SourceRevisionMismatch;
        }
    }
    fn tools(self: Recipe, root: []const u8) !void {
        const host = switch (builtin.os.tag) {
            .macos => "mac-arm64",
            .windows => "windows-amd64",
            .linux => if (builtin.cpu.arch == .aarch64) "linux-arm64" else "linux-amd64",
            else => return error.UnsupportedHost,
        };
        var lines = std.mem.tokenizeScalar(u8, @embedFile("GN"), '\n');
        var revision: ?[]const u8 = null;
        var expected: ?[]const u8 = null;
        while (lines.next()) |line| {
            var words = std.mem.tokenizeScalar(u8, line, ' ');
            const key = words.next().?;
            if (std.mem.eql(u8, key, "revision")) revision = words.next();
            if (std.mem.eql(u8, key, host)) expected = words.next();
        }
        try self.mkdir(root);
        const archive = try self.path(&.{ root, "gn.zip" });
        const url = try self.format("https://chrome-infra-packages.appspot.com/dl/gn/gn/{s}/+/git_revision:{s}", .{ host, revision orelse return error.MissingGnPin });
        try self.run(&.{ "curl", "-fL", "--retry", "2", "-o", archive, url }, null);
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(try self.read(archive), &hash, .{});
        if (!std.mem.eql(u8, &std.fmt.bytesToHex(hash, .lower), expected orelse return error.MissingGnPin)) return error.GnChecksumMismatch;
        try self.run(&.{ "cmake", "-E", "tar", "xf", try self.absolute(archive) }, root);
    }
    fn compiler(self: Recipe, name: []const u8, args: []const []const u8) !void {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(self.allocator, &.{ self.zig(), if (std.mem.eql(u8, name, "llvm-ar")) "ar" else if (std.mem.eql(u8, name, "clang")) "cc" else "c++" });
        const archive = std.mem.eql(u8, name, "llvm-ar");
        if (!archive) {
            const target = std.meta.stringToEnum(Target, self.environment.get("LIZZIE_CRASHPAD_TARGET") orelse return error.MissingTarget) orelse return error.UnsupportedTarget;
            try argv.appendSlice(self.allocator, &.{ "-target", target.triple(), try self.format("-mcpu={s}", .{target.cpu()}), "-g0" });
        }
        for (args) |arg| {
            // mini_chromium's arm64 default otherwise loses our explicit glibc floor.
            if (!archive and (std.mem.startsWith(u8, arg, "--target=") or std.mem.eql(u8, arg, "-m64"))) continue;
            try argv.append(self.allocator, arg);
        }
        const term = try self.execute(argv.items, null);
        std.process.exit(if (term == .exited) @intCast(@min(term.exited, 255)) else 1);
    }
    fn build(self: Recipe, target: Target, source_arg: []const u8, out_arg: []const u8, tools_arg: []const u8) !void {
        if ((target.linux() and builtin.os.tag != .linux) or
            (target.windows() and builtin.os.tag != .windows) or
            (target == .@"aarch64-macos" and builtin.os.tag != .macos)) return error.NativeBuildHostRequired;
        const source = try self.absolute(source_arg);
        try self.verifySources(source);
        try self.mkdir(out_arg);
        const out = try self.absolute(out_arg);
        const tools_root = try self.absolute(tools_arg);
        try self.write(try self.path(&.{ source, "lizzie", "BUILD.gn" }), @embedFile("BUILD.gn"));
        try self.write(try self.path(&.{ source, "lizzie", "lizzie_crashpad.h" }), @embedFile("lizzie_crashpad.h"));
        try self.write(try self.path(&.{ source, "lizzie", "lizzie_crashpad.cc" }), @embedFile("lizzie_crashpad.cc"));
        var gn_args: []const u8 = "is_debug=false ";
        if (target.linux()) {
            const shim = try self.path(&.{ out, "zig-toolchain" });
            const bin = try self.path(&.{ shim, "bin" });
            try self.mkdir(bin);
            const exe = try std.process.executablePathAlloc(self.io, self.allocator);
            for ([_][]const u8{ "clang", "clang++", "llvm-ar" }) |name| {
                const link = try self.path(&.{ bin, name });
                Io.Dir.cwd().deleteFile(self.io, link) catch |err| if (err != error.FileNotFound) return err;
                try Io.Dir.cwd().symLink(self.io, exe, link, .{});
            }
            try self.environment.put("LIZZIE_CRASHPAD_TARGET", @tagName(target));
            gn_args = try self.format("{s}target_cpu=\"{s}\" clang_path=\"{s}\" crashpad_http_transport_impl=\"socket\" crashpad_use_boringssl_for_http_transport_socket=false", .{ gn_args, if (target == .@"aarch64-linux-gnu") "arm64" else "x64", shim });
        } else if (target.windows()) {
            // Upstream's MSVC template reads invoker flags, but its x64 invocation
            // doesn't forward the declared extra_* args. Patch only that invocation.
            const config_path = try self.path(&.{ source, "third_party/mini_chromium/mini_chromium/build/config/BUILD.gn" });
            const original = try self.read(config_path);
            const needle = "msvc_toolchain(\"x64\") {\n";
            const replacement = needle ++ "    extra_cflags = extra_cflags\n    extra_cflags_cc = extra_cflags_cc\n    extra_ldflags = extra_ldflags\n";
            if (std.mem.indexOf(u8, original, replacement) == null) {
                const index = std.mem.indexOf(u8, original, needle) orelse return error.UpstreamToolchainChanged;
                try self.write(config_path, try self.format("{s}{s}{s}", .{ original[0..index], replacement, original[index + needle.len ..] }));
            }
            gn_args = try self.format("{s}target_cpu=\"x64\" mini_chromium_is_clang=false extra_cflags=\"/MT /arch:AVX2 /GR-\" extra_cflags_cc=\"/std:c++latest\"", .{gn_args});
        } else {
            gn_args = try self.format("{s}target_cpu=\"arm64\" mac_deployment_target=\"26.0\" extra_cflags=\"-mcpu=apple-m1 -g0\" extra_ldflags=\"-mcpu=apple-m1\"", .{gn_args});
        }
        try self.write(try self.path(&.{ out, "args.gn" }), gn_args);
        const gn = try self.path(&.{ tools_root, if (target.windows()) "gn.exe" else "gn" });
        try self.run(&.{ gn, "gen", out, "--root-target=//lizzie:package", "--fail-on-unused-args" }, source);
        try self.run(&.{ "ninja", "-C", out, "lizzie:lizzie_crashpad", "handler:crashpad_handler", "tools:crashpad_database_util", "tools:dump_minidump_annotations" }, source);
        const compiler_version = try self.capture(&.{ if (target.linux()) self.zig() else if (target.windows()) "cl.exe" else "clang++", if (target.linux()) "version" else if (target.windows()) "/?" else "--version" }, null);
        try self.write(try self.path(&.{ out, "COMPILER.txt" }), compiler_version);
        try self.write(try self.path(&.{ out, "TOOLS.txt" }), try self.format("GN: {s}Ninja: {s}", .{ try self.capture(&.{ gn, "--version" }, null), try self.capture(&.{ "ninja", "--version" }, null) }));
        try self.write(try self.path(&.{ out, "TARGET" }), @tagName(target));
        if (target.linux()) {
            const dependencies = try self.capture(&.{ "readelf", "-d", try self.path(&.{ out, "crashpad_handler" }) }, null);
            if (std.mem.indexOf(u8, dependencies, "libstdc++") != null or std.mem.indexOf(u8, dependencies, "libc++.so") != null or std.mem.indexOf(u8, dependencies, "libcurl") != null) return error.UnexpectedCppOrCurlRuntime;
            try self.write(try self.path(&.{ out, "RUNTIME.txt" }), dependencies);
        }
    }
    fn package(self: Recipe, target: Target, source: []const u8, out: []const u8, output: []const u8, commit: []const u8) !void {
        if (commit.len != 40) return error.InvalidRecipeCommit;
        try self.verifySources(source);
        if (!std.mem.eql(u8, try self.read(try self.path(&.{ out, "TARGET" })), @tagName(target))) return error.PackageTargetMismatch;
        const name = try self.format("crashpad-{s}-{s}", .{ sourceRevision("crashpad")[0..12], @tagName(target) });
        const stage = try self.path(&.{ output, name });
        // A fresh staging directory prevents stale files entering an archive.
        try self.mkdir(output);
        try Io.Dir.cwd().createDir(self.io, stage, .default_dir);
        for ([_][]const u8{ "include", "lib", "bin", "notices" }) |dir| try self.mkdir(try self.path(&.{ stage, dir }));
        try self.write(try self.path(&.{ stage, "include/lizzie_crashpad.h" }), @embedFile("lizzie_crashpad.h"));
        try self.copy(try self.path(&.{ out, if (target.windows()) "lizzie_crashpad.lib" else "obj/lizzie/liblizzie_crashpad.a" }), try self.path(&.{ stage, "lib", if (target.windows()) "lizzie_crashpad.lib" else "liblizzie_crashpad.a" }));
        if (target.windows()) try self.copy(try self.path(&.{ out, "lizzie_crashpad.dll" }), try self.path(&.{ stage, "bin/lizzie_crashpad.dll" }));
        for ([_][]const u8{ "crashpad_handler", "crashpad_database_util", "dump_minidump_annotations" }) |tool| {
            const filename = try self.format("{s}{s}", .{ tool, if (target.windows()) ".exe" else "" });
            try self.copy(try self.path(&.{ out, filename }), try self.path(&.{ stage, "bin", filename }));
        }
        try self.copy(try self.path(&.{ source, "LICENSE" }), try self.path(&.{ stage, "notices/Crashpad.LICENSE" }));
        try self.copy(try self.path(&.{ source, "third_party/mini_chromium/mini_chromium/LICENSE" }), try self.path(&.{ stage, "notices/mini_chromium.LICENSE" }));
        try self.copy(try self.path(&.{ source, "third_party/mini_chromium/mini_chromium/base/third_party/icu/LICENSE" }), try self.path(&.{ stage, "notices/icu.LICENSE" }));
        if (target.linux()) try self.copy(try self.path(&.{ source, "third_party/lss/lss/LICENSE" }), try self.path(&.{ stage, "notices/lss.LICENSE" }));
        if (target.windows()) try self.copy(try self.path(&.{ source, "third_party/zlib/zlib/LICENSE" }), try self.path(&.{ stage, "notices/zlib.LICENSE" }));
        try self.write(try self.path(&.{ stage, "BUILDINFO.txt" }), try self.format(
            "target: {s}\ncompiler-target: {s}\nrecipe: {s}\ncpu: {s}\nlink: {s}\nbridge: C ABI; max 16 attachments, 64 annotations\nuploads: disabled by bridge\nLinux compiler shim: pinned Zig cc/c++/ar, explicit target and CPU, -g0\nLinux HTTP: socket, no TLS (uploads out of scope)\n\n{s}\n{s}\nGN args:\n{s}\nCompiler:\n{s}\nTools:\n{s}\n",
            .{ @tagName(target), target.triple(), commit, target.cpu(), if (target.windows()) "import library; deploy bin/lizzie_crashpad.dll" else if (target.linux()) "c++ dl pthread rt z" else "c++.1 bsm z; Foundation CoreFoundation Security", @embedFile("SOURCES"), @embedFile("GN"), try self.read(try self.path(&.{ out, "args.gn" })), try self.read(try self.path(&.{ out, "COMPILER.txt" })), try self.read(try self.path(&.{ out, "TOOLS.txt" })) },
        ));
        if (target.linux()) try self.copy(try self.path(&.{ out, "RUNTIME.txt" }), try self.path(&.{ stage, "RUNTIME.txt" }));
        const archive = try self.path(&.{ output, try self.format("{s}.tar.gz", .{name}) });
        const absolute_archive = try self.path(&.{ try self.absolute(output), try self.format("{s}.tar.gz", .{name}) });
        try self.run(&.{ "cmake", "-E", "tar", "czf", absolute_archive, "--format=gnutar", "--mtime=2000-01-01 00:00:00 UTC", name }, output);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(try self.read(archive), &digest, .{});
        try self.write(try self.format("{s}.sha256", .{archive}), try self.format("{s}  {s}.tar.gz\n", .{ std.fmt.bytesToHex(digest, .lower), name }));
    }
    fn copy(self: Recipe, source: []const u8, dest: []const u8) !void {
        try Io.Dir.cwd().copyFile(source, Io.Dir.cwd(), dest, self.io, .{});
    }
    fn smoke(self: Recipe, target: Target, package_arg: []const u8, root_arg: []const u8) !void {
        const package_root = try self.absolute(package_arg);
        try self.mkdir(root_arg);
        const root = try self.absolute(root_arg);
        try self.write(try self.path(&.{ root, "build.zig" }), @embedFile("smoke_build.zig"));
        try self.write(try self.path(&.{ root, "smoke.zig" }), @embedFile("smoke.zig"));
        var build_args: std.ArrayList([]const u8) = .empty;
        try build_args.appendSlice(self.allocator, &.{ self.zig(), "build", "-Doptimize=ReleaseFast", try self.format("-Dpackage={s}", .{package_root}), try self.format("-Dcpu={s}", .{target.cpu()}) });
        // Keep the native macOS query so Zig discovers its Apple SDK.
        if (target.linux() or target.windows()) try build_args.append(self.allocator, try self.format("-Dtarget={s}", .{target.triple()}));
        try self.run(build_args.items, root);
        const exe = try self.path(&.{ root, "zig-out/bin", if (target.windows()) "smoke.exe" else "smoke" });
        try self.smokeModes(target, package_root, root, exe, "");
        // The identical DLL/import library must also work from the GNU ABI.
        if (target.windows()) {
            try self.run(&.{ self.zig(), "build", "-Dtarget=x86_64-windows-gnu", "-Dcpu=x86_64_v3", "-Doptimize=ReleaseFast", try self.format("-Dpackage={s}", .{package_root}) }, root);
            try self.smokeModes(target, package_root, root, exe, "gnu-");
        }
    }
    fn smokeModes(self: Recipe, target: Target, package_root: []const u8, root: []const u8, exe: []const u8, prefix: []const u8) !void {
        for ([_][]const u8{ "dump", "panic", "worker_fault" }) |mode| {
            const reports = try self.path(&.{ root, try self.format("{s}{s}", .{ prefix, mode }) });
            try self.mkdir(reports);
            const term = try self.execute(&.{ exe, try self.path(&.{ package_root, "bin", if (target.windows()) "crashpad_handler.exe" else "crashpad_handler" }), reports, mode }, null);
            if (mode[0] == 'd') {
                if (term != .exited or term.exited != 0) return error.SmokeFailed;
            } else if (term == .exited and term.exited == 0) return error.ExpectedCrash;
            try self.inspect(package_root, reports, target);
        }
    }
    fn inspect(self: Recipe, package_root: []const u8, reports: []const u8, target: Target) !void {
        const pending = try self.path(&.{ reports, "database/pending" });
        var dir = try Io.Dir.cwd().openDir(self.io, pending, .{ .iterate = true });
        defer dir.close(self.io);
        var iterator = dir.iterate();
        var count: usize = 0;
        while (try iterator.next(self.io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".dmp")) continue;
            count += 1;
            const bytes = try self.read(try self.path(&.{ pending, entry.name }));
            if (bytes.len < 32 or !std.mem.eql(u8, bytes[0..4], "MDMP")) return error.InvalidMinidump;
            const streams = std.mem.readInt(u32, bytes[8..12], .little);
            const table = std.mem.readInt(u32, bytes[12..16], .little);
            var required: u8 = 0;
            for (0..streams) |index| {
                const offset = @as(usize, table) + index * 12;
                if (offset > bytes.len or bytes.len - offset < 12) return error.InvalidMinidump;
                const kind = std.mem.readInt(u32, bytes[offset..][0..4], .little);
                required |= switch (kind) {
                    3 => 1,
                    4 => 2,
                    6 => 4,
                    7 => 8,
                    else => 0,
                };
            }
            if (required != 15) return error.MissingMinidumpStreams;
            const copied = try self.read(try self.path(&.{ reports, "database/attachments", entry.name[0 .. entry.name.len - 4], "evidence.txt" }));
            if (!std.mem.eql(u8, copied, "Crashpad attachment evidence\n")) return error.AttachmentMismatch;
            const annotations = try self.capture(&.{ try self.path(&.{ package_root, "bin", if (target.windows()) "dump_minidump_annotations.exe" else "dump_minidump_annotations" }), try self.format("--minidump={s}", .{try self.path(&.{ pending, entry.name })}) }, null);
            if (std.mem.indexOf(u8, annotations, "zig-package-smoke") == null) return error.AnnotationMissing;
        }
        if (count != 1) return error.ExpectedOneReport;
        const settings = try self.capture(&.{ try self.path(&.{ package_root, "bin", if (target.windows()) "crashpad_database_util.exe" else "crashpad_database_util" }), try self.format("--database={s}", .{try self.path(&.{ reports, "database" })}), "--show-uploads-enabled" }, null);
        if (std.mem.indexOf(u8, settings, "false") == null) return error.UploadsEnabled;
    }
};

fn sourceRevision(name: []const u8) []const u8 {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("SOURCES"), '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeScalar(u8, line, ' ');
        if (std.mem.eql(u8, words.next().?, name)) return words.next().?;
    }
    unreachable;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const recipe: Recipe = .{ .allocator = allocator, .io = init.io, .environment = init.environ_map };
    const name = std.fs.path.basename(args[0]);
    for ([_][]const u8{ "clang", "clang++", "llvm-ar" }) |compiler| {
        if (std.mem.eql(u8, name, compiler)) return recipe.compiler(compiler, args[1..]);
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "fetch")) return recipe.fetch(args[2]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "tools")) return recipe.tools(args[2]);
    if (args.len < 3) return error.ExpectedCommandAndArguments;
    const target = std.meta.stringToEnum(Target, args[2]) orelse return error.UnsupportedTarget;
    if (args.len == 6 and std.mem.eql(u8, args[1], "build")) return recipe.build(target, args[3], args[4], args[5]);
    if (args.len == 7 and std.mem.eql(u8, args[1], "package")) return recipe.package(target, args[3], args[4], args[5], args[6]);
    if (args.len == 5 and std.mem.eql(u8, args[1], "smoke")) return recipe.smoke(target, args[3], args[4]);
    return error.InvalidCommand;
}
