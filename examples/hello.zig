#!/usr/bin/env zit
const std = @import("std");

pub fn main() !void {
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    try stdout.writeAll("Hello from zit!\n");
    if (args.len > 1) {
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Args: {s}\n", .{args[1]}) catch "...\n";
        try stdout.writeAll(msg);
    }
}
