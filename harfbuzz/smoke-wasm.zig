const std = @import("std");

const allocator = std.heap.wasm_allocator;
const alignment = std.mem.Alignment.fromByteUnits(16);
// Keep the allocation size in an aligned prefix so free and realloc can
// recover the original slice from a C pointer.
const prefix = alignment.toByteUnits();

fn allocationSize(size: usize) ?usize {
    return std.math.add(usize, prefix, @max(size, 1)) catch null;
}

fn allocation(ptr: [*]u8) []align(prefix) u8 {
    const base: [*]align(prefix) u8 = @ptrFromInt(@intFromPtr(ptr) - prefix);
    return base[0..@as(*usize, @ptrCast(base)).*];
}

export fn malloc(size: usize) ?[*]u8 {
    const total = allocationSize(size) orelse return null;
    const storage = allocator.alignedAlloc(u8, alignment, total) catch return null;
    @as(*usize, @ptrCast(storage.ptr)).* = total;
    return storage.ptr + prefix;
}

export fn calloc(count: usize, size: usize) ?[*]u8 {
    const bytes = std.math.mul(usize, count, size) catch return null;
    const ptr = malloc(bytes) orelse return null;
    @memset(ptr[0..bytes], 0);
    return ptr;
}

export fn realloc(ptr: ?[*]u8, size: usize) ?[*]u8 {
    const old = ptr orelse return malloc(size);
    if (size == 0) {
        free(old);
        return null;
    }
    const total = allocationSize(size) orelse return null;
    const storage = allocator.realloc(allocation(old), total) catch return null;
    @as(*usize, @ptrCast(storage.ptr)).* = total;
    return storage.ptr + prefix;
}

export fn free(ptr: ?[*]u8) void {
    if (ptr) |p| allocator.free(allocation(p));
}

export fn abs(value: c_int) c_int {
    return @bitCast(@abs(value));
}

export fn hypotf(x: f32, y: f32) f32 {
    const a: f64 = x;
    const b: f64 = y;
    if (@abs(a) == std.math.inf(f64) or @abs(b) == std.math.inf(f64)) return std.math.inf(f32);
    return @floatCast(@sqrt(a * a + b * b));
}

export fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int {
    return strncmp(a, b, std.math.maxInt(usize));
}

export fn strncmp(a: [*:0]const u8, b: [*:0]const u8, limit: usize) c_int {
    for (0..limit) |i| {
        const diff = @as(c_int, a[i]) - @as(c_int, b[i]);
        if (diff != 0 or a[i] == 0) return diff;
    }
    return 0;
}

export fn strchr(s: [*:0]const u8, c: c_int) ?[*]const u8 {
    const needle: u8 = @truncate(@as(c_uint, @bitCast(c)));
    var i: usize = 0;
    while (true) : (i += 1) {
        if (s[i] == needle) return s + i;
        if (s[i] == 0) return null;
    }
}

export fn strstr(s: [*:0]const u8, needle: [*:0]const u8) ?[*]const u8 {
    const i = std.mem.find(u8, std.mem.span(s), std.mem.span(needle)) orelse return null;
    return s + i;
}

export fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8 {
    const n = std.mem.len(src) + 1;
    @memcpy(dest[0..n], src[0..n]);
    return dest;
}

export fn strncpy(dest: [*]u8, src: [*:0]const u8, count: usize) [*]u8 {
    var n: usize = 0;
    while (n < count and src[n] != 0) : (n += 1) dest[n] = src[n];
    @memset(dest[n..count], 0);
    return dest;
}

const Compare = *const fn ([*]const u8, [*]const u8) callconv(.c) c_int;

const SortContext = struct {
    base: [*]u8,
    width: usize,
    compare: Compare,

    pub fn lessThan(ctx: SortContext, a: usize, b: usize) bool {
        return ctx.compare(ctx.base + a * ctx.width, ctx.base + b * ctx.width) < 0;
    }

    pub fn swap(ctx: SortContext, a: usize, b: usize) void {
        const left = ctx.base + a * ctx.width;
        const right = ctx.base + b * ctx.width;
        for (left[0..ctx.width], right[0..ctx.width]) |*l, *r| std.mem.swap(u8, l, r);
    }
};

export fn qsort(base: [*]u8, count: usize, width: usize, compare: Compare) void {
    if (count < 2 or width == 0) return;
    std.sort.heapContext(0, count, SortContext{ .base = base, .width = width, .compare = compare });
}

// The smoke fixture uses a known language tag and does no text formatting.
export fn snprintf(_: ?[*]u8, _: usize, _: [*:0]const u8, ...) c_int {
    @trap();
}
