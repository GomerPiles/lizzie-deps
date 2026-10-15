const std = @import("std");
test "compiler worker limits preserve runtime threading" {
    try std.testing.expect(!@import("builtin").single_threaded);
    try std.testing.expectEqual(42, @import("translated").answer);
}
