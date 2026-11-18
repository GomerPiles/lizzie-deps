//! Keeps installation writers out of fork children in Linux's build runner.
//! Owned by one Maker; running children do not hold this lock.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const InstallGuard = @This();

mutex: Io.Mutex = .init,

/// Hold the gate for the whole copy, including the destination descriptor's close.
/// Atomic rename and CLOEXEC alone cannot prevent an unrelated fork inheriting it.
pub fn updateFile(
    self: *InstallGuard,
    source_dir: Io.Dir,
    io: Io,
    source_path: []const u8,
    dest_dir: Io.Dir,
    dest_path: []const u8,
    options: Io.Dir.CopyFileOptions,
) !Io.Dir.PrevStatus {
    if (builtin.os.tag == .linux) try self.mutex.lock(io);
    defer if (builtin.os.tag == .linux) self.mutex.unlock(io);
    return Io.Dir.updateFile(source_dir, io, source_path, dest_dir, dest_path, options);
}

/// Exclude fork/exec from installation, then let the child run concurrently.
pub fn spawn(self: *InstallGuard, io: Io, options: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
    if (builtin.os.tag == .linux) try self.mutex.lock(io);
    defer if (builtin.os.tag == .linux) self.mutex.unlock(io);
    return std.process.spawn(io, options);
}

/// Maker's capture helper runs pkg-config and fmt. Keep its internal spawn under
/// the gate too; compilation and test execution use `spawn` instead.
pub fn run(self: *InstallGuard, allocator: std.mem.Allocator, io: Io, options: std.process.RunOptions) std.process.RunError!std.process.RunResult {
    if (builtin.os.tag == .linux) try self.mutex.lock(io);
    defer if (builtin.os.tag == .linux) self.mutex.unlock(io);
    return std.process.run(allocator, io, options);
}
