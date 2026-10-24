//! Holds a real fork child before exec to reproduce inherited-writer ETXTBSY.
//! Also verifies the actual Maker gate excludes installation from process creation.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const InstallGuard = @import("install_guard");

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag != .linux) return;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--exit")) return;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--wait")) {
        var byte: [1]u8 = undefined;
        var reader = Io.File.stdin().readerStreaming(init.io, &byte);
        _ = reader.interface.takeByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        return;
    }
    if (args.len != 3) return error.ExpectedBusyOrFixedAndScratch;
    const expect_busy = std.mem.eql(u8, args[1], "busy");
    if (!expect_busy and !std.mem.eql(u8, args[1], "fixed")) return error.ExpectedBusyOrFixed;
    const io = init.io;
    const target = try std.fs.path.join(allocator, &.{ args[2], "spawn-probe" });
    if (!expect_busy) return checkGuard(init, target);
    _ = try Io.Dir.updateFile(.cwd(), io, "/proc/self/exe", .cwd(), target, .{});
    defer Io.Dir.cwd().deleteFile(io, target) catch {};
    const writer = try Io.Dir.cwd().openFile(io, target, .{ .mode = .write_only });
    var writer_open = true;
    defer if (writer_open) writer.close(io);

    var first: Launch = .{ .io = io };
    const thread = try std.Thread.spawn(.{}, Launch.run, .{&first});
    var joined = false;
    var pid: ?std.posix.pid_t = null;
    defer {
        if (!joined) {
            if (pid) |child_pid| std.posix.kill(child_pid, .CONT) catch {};
            thread.join();
        }
        if (first.child) |*child| child.kill(io) else |_| {}
    }
    const child_pid = try stoppedChild(io, allocator, &first, &pid);
    const inherited_fd = try std.fmt.allocPrint(allocator, "/proc/{d}/fd/{d}", .{ child_pid, writer.handle });
    var link_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const len = try Io.Dir.readLinkAbsolute(io, inherited_fd, &link_buffer);
    if (!std.mem.eql(u8, link_buffer[0..len], target)) return error.WriterNotInherited;
    // The installer closes its own descriptor, but the stopped child still has it.
    writer.close(io);
    writer_open = false;
    std.log.info("child {d} retains writer fd {d} after parent close: {s}", .{ child_pid, writer.handle, target });

    // Keep the competing child stopped until the unguarded attempt returns.
    // This reproduces the error without relying on a scheduling delay.
    const launched = std.process.spawn(io, .{ .argv = &.{ target, "--exit" } });
    try std.posix.kill(child_pid, .CONT);
    thread.join();
    joined = true;
    var waiting = try first.child;
    first.child = error.AlreadyReaped;
    defer waiting.kill(io);
    if (waiting.stdin) |file| {
        file.close(io);
        waiting.stdin = null;
    }
    if (!(try waiting.wait(io)).success()) return error.CompetingChildFailed;
    if (launched) |value| {
        var child = value;
        defer child.kill(io);
        if (!(try child.wait(io)).success()) return error.ProbeChildFailed;
        return error.ExpectedFileBusy;
    } else |err| {
        if (err != error.FileBusy or !expect_busy) return err;
        std.log.info("REPRODUCED: FileBusy from the inherited writer, with the installer already closed", .{});
    }
}

fn checkGuard(init: std.process.Init, target: []const u8) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    Io.Dir.cwd().deleteFile(io, target) catch |err| if (err != error.FileNotFound) return err;
    defer Io.Dir.cwd().deleteFile(io, target) catch {};
    var guard: InstallGuard = .{};
    var first: Launch = .{ .io = io, .guard = &guard };
    const thread = try std.Thread.spawn(.{}, Launch.run, .{&first});
    var joined = false;
    var pid: ?std.posix.pid_t = null;
    defer {
        if (!joined) {
            if (pid) |child_pid| std.posix.kill(child_pid, .CONT) catch {};
            thread.join();
        }
        if (first.child) |*child| child.kill(io) else |_| {}
    }
    const child_pid = try stoppedChild(io, allocator, &first, &pid);
    var release: Release = .{ .io = io, .pid = child_pid, .target = target };
    const resumer = try std.Thread.spawn(.{}, Release.run, .{&release});
    var resume_joined = false;
    defer if (!resume_joined) resumer.join();
    // This must not even open the installation writer while the first spawn is
    // stopped. The release thread checks that before allowing exec to continue.
    _ = try guard.updateFile(.cwd(), io, "/proc/self/exe", .cwd(), target, .{});
    resumer.join();
    resume_joined = true;
    try release.result;
    // The first child is now executing but blocked on stdin. A second launch
    // must succeed before we let the first exit: child runtimes stay concurrent.
    var child = try guard.spawn(io, .{ .argv = &.{ target, "--exit" } });
    defer child.kill(io);
    if (!(try child.wait(io)).success()) return error.ProbeChildFailed;
    thread.join();
    joined = true;
    var waiting = try first.child;
    first.child = error.AlreadyReaped;
    defer waiting.kill(io);
    if (waiting.stdin) |file| {
        file.close(io);
        waiting.stdin = null;
    }
    if (!(try waiting.wait(io)).success()) return error.CompetingChildFailed;
    try checkErrors(&guard, io, target);
    std.log.info("PASS: installation excluded from fork/exec; child runtimes remain concurrent", .{});
}

const Release = struct {
    io: Io,
    pid: std.posix.pid_t,
    target: []const u8,
    result: anyerror!void = {},

    fn run(self: *Release) void {
        defer std.posix.kill(self.pid, .CONT) catch {};
        Io.sleep(self.io, .fromMilliseconds(100), .awake) catch {};
        if (Io.Dir.cwd().statFile(self.io, self.target, .{})) |_| {
            self.result = error.InstallationOverlappedProcessCreation;
        } else |err| {
            if (err != error.FileNotFound) self.result = err;
        }
    }
};

fn checkErrors(guard: *InstallGuard, io: Io, target: []const u8) !void {
    // A real writer must still prevent execution. The guard is synchronization,
    // not a retry or a way to hide genuine launch failures.
    const writer = try Io.Dir.cwd().openFile(io, target, .{ .mode = .write_only });
    const blocked = guard.spawn(io, .{ .argv = &.{ target, "--exit" } });
    writer.close(io);
    if (blocked) |value| {
        var child = value;
        child.kill(io);
        return error.PersistentWriterAccepted;
    } else |err| if (err != error.FileBusy) return err;
    var child = try guard.spawn(io, .{ .argv = &.{ target, "--exit" } });
    defer child.kill(io);
    if (!(try child.wait(io)).success()) return error.SpawnGuardNotReleased;
    std.log.info("PASS: genuine FileBusy propagates and a failed launch releases the guard", .{});
}

const Launch = struct {
    io: Io,
    guard: ?*InstallGuard = null,
    tid: std.atomic.Value(std.Thread.Id) = .init(0),
    child: anyerror!std.process.Child = error.Unexpected,

    fn run(self: *Launch) void {
        self.tid.store(std.Thread.getCurrentId(), .release);
        const options: std.process.SpawnOptions = .{
            .argv = &.{ "/proc/self/exe", "--wait" },
            .stdin = .pipe,
            .start_suspended = true,
        };
        self.child = if (self.guard) |guard| guard.spawn(self.io, options) else std.process.spawn(self.io, options);
    }
};

fn stoppedChild(io: Io, allocator: std.mem.Allocator, launch: *Launch, known_pid: *?std.posix.pid_t) !std.posix.pid_t {
    const deadline = Io.Timestamp.now(io, .awake).addDuration(.fromSeconds(5));
    while (Io.Timestamp.now(io, .awake).nanoseconds < deadline.nanoseconds) {
        const tid = launch.tid.load(.acquire);
        if (tid != 0) {
            const children_path = try std.fmt.allocPrint(allocator, "/proc/self/task/{d}/children", .{tid});
            const children = try readProc(io, allocator, children_path);
            const trimmed = std.mem.trim(u8, children, " \n");
            if (trimmed.len != 0) {
                const child_pid = try std.fmt.parseInt(std.posix.pid_t, trimmed, 10);
                known_pid.* = child_pid;
                const status_path = try std.fmt.allocPrint(allocator, "/proc/{d}/status", .{child_pid});
                const status = try readProc(io, allocator, status_path);
                if (std.mem.indexOf(u8, status, "State:\tT") != null) return child_pid;
            }
        }
        try Io.sleep(io, .fromMilliseconds(1), .awake);
    }
    return error.ChildDidNotStop;
}

fn readProc(io: Io, allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    // procfs files report size zero; do not let a stat-based reader treat that as EOF.
    var reader = file.readerStreaming(io, &.{});
    return reader.interface.allocRemaining(allocator, .limited(16384));
}
