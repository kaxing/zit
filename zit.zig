const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;

const stderr_file = fs.File{ .handle = std.posix.STDERR_FILENO };

fn stderrPrint(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "zit: format error\n";
    stderr_file.writeAll(msg) catch {};
}

pub fn main() !u8 {
    // Use a small fixed buffer to avoid page allocator overhead on common paths.
    // Falls back to heap allocation for larger inputs.
    var fba_buf: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fba_buf);
    const gpa = fba.allocator();

    const all_args = try process.argsAlloc(gpa);
    // No explicit free is needed; process exits or execs.

    if (all_args.len < 2) {
        printUsage();
        return 1;
    }

    var arg_idx: usize = 1;
    const first = all_args[1];

    if (mem.eql(u8, first, "clean-caches")) {
        return cleanCaches(gpa);
    }
    if (mem.eql(u8, first, "toggle-shebang")) {
        if (all_args.len < 3) {
            stderrPrint("zit: missing target source file\n", .{});
            printUsage();
            return 1;
        }
        return toggleShebang(gpa, all_args[2]);
    }

    var opt_mode: []const u8 = "-OReleaseSmall";
    var recompile = false;
    while (arg_idx < all_args.len) {
        const arg = all_args[arg_idx];
        if (mem.eql(u8, arg, "--debug")) {
            opt_mode = "-ODebug";
            arg_idx += 1;
        } else if (mem.eql(u8, arg, "--recompile")) {
            recompile = true;
            arg_idx += 1;
        } else if (mem.startsWith(u8, arg, "-")) {
            stderrPrint("zit: unknown option '{s}'\n", .{arg});
            printUsage();
            return 1;
        } else break;
    }

    if (arg_idx >= all_args.len) {
        stderrPrint("zit: no source file specified\n", .{});
        printUsage();
        return 1;
    }

    const source_path = all_args[arg_idx];
    const forward_args = all_args[arg_idx + 1 ..];

    // Read and hash source with a stack buffer first; fall back to allocated read for larger files.
    var hasher = std.hash.XxHash3.init(0);
    hashField(&hasher, source_path);
    hashField(&hasher, opt_mode);
    hashField(&hasher, zigVersion());

    var has_shebang = false;
    var source_buf: [8192]u8 = undefined;
    const source = blk: {
        const fd = std.posix.openat(std.posix.AT.FDCWD, source_path, .{}, 0) catch |err| {
            stderrPrint("zit: cannot open '{s}': {s}\n", .{ source_path, @errorName(err) });
            return 1;
        };
        defer std.posix.close(fd);
        const n = std.posix.read(fd, &source_buf) catch |err| {
            stderrPrint("zit: cannot read '{s}': {s}\n", .{ source_path, @errorName(err) });
            return 1;
        };
        if (n == source_buf.len) {
            // File too large for stack buffer — fall back to allocator
            const source_alloc = fs.cwd().readFileAlloc(gpa, source_path, 64 * 1024 * 1024) catch |err| {
                stderrPrint("zit: cannot read '{s}': {s}\n", .{ source_path, @errorName(err) });
                return 1;
            };
            has_shebang = hasShebang(source_alloc);
            hashField(&hasher, source_alloc);
            hashImports(&hasher, source_alloc, source_path, gpa);
            gpa.free(source_alloc);
            break :blk source_buf[0..0]; // sentinel: used allocator path
        }
        const src = source_buf[0..n];
        has_shebang = hasShebang(src);
        hashField(&hasher, src);
        hashImports(&hasher, src, source_path, gpa);
        break :blk src;
    };
    _ = source;

    const digest = hasher.final();
    var hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x:0>16}", .{digest}) catch unreachable;

    // Ensure cache directory exists
    const cache_dir = try getCacheDir(gpa);
    defer gpa.free(cache_dir);
    try fs.cwd().makePath(cache_dir);

    const cached_bin = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ cache_dir, &hex });
    defer gpa.free(cached_bin);

    // Build if binary not cached (or --recompile)
    const needs_build = recompile or blk: {
        fs.cwd().access(cached_bin, .{}) catch break :blk true;
        break :blk false;
    };

    if (needs_build) {
        const emit_arg = try std.fmt.allocPrint(gpa, "-femit-bin={s}", .{cached_bin});
        defer gpa.free(emit_arg);

        var compile_source_path: []const u8 = source_path;
        var temp_source_path: ?[]u8 = null;
        if (has_shebang) {
            const source_alloc = fs.cwd().readFileAlloc(gpa, source_path, 64 * 1024 * 1024) catch |err| {
                stderrPrint("zit: cannot read '{s}': {s}\n", .{ source_path, @errorName(err) });
                return 1;
            };
            defer gpa.free(source_alloc);

            const stripped = stripShebang(source_alloc);
            const temp = try std.fmt.allocPrint(gpa, "{s}/{s}.src.zig", .{ cache_dir, &hex });
            errdefer gpa.free(temp);
            fs.cwd().writeFile(.{ .sub_path = temp, .data = stripped }) catch |err| {
                stderrPrint("zit: cannot prepare shebang source: {s}\n", .{@errorName(err)});
                return 1;
            };
            temp_source_path = temp;
            compile_source_path = temp;
        }
        defer if (temp_source_path) |temp| {
            fs.cwd().deleteFile(temp) catch {};
            gpa.free(temp);
        };

        var compile = process.Child.init(
            &.{ "zig", "build-exe", compile_source_path, emit_arg, opt_mode, "-fstrip", "-fno-llvm", "-fno-unwind-tables" },
            gpa,
        );
        compile.stderr_behavior = .Inherit;
        compile.stdout_behavior = .Inherit;

        const term = try compile.spawnAndWait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    fs.cwd().deleteFile(cached_bin) catch {};
                    stderrPrint("zit: compilation failed (exit {})\n", .{code});
                    return 1;
                }
            },
            else => {
                fs.cwd().deleteFile(cached_bin) catch {};
                stderrPrint("zit: compiler terminated abnormally\n", .{});
                return 1;
            },
        }

        // Clean up .o files zig leaves behind
        cleanGlob(gpa, cache_dir, "_zcu.o") catch {};
    }

    // execve: replace this process with the cached binary.
    // Build argv on stack to avoid any allocator use.
    var cached_bin_z_buf: [512]u8 = undefined;
    if (cached_bin.len >= cached_bin_z_buf.len) {
        stderrPrint("zit: cache path too long\n", .{});
        return 1;
    }
    @memcpy(cached_bin_z_buf[0..cached_bin.len], cached_bin);
    cached_bin_z_buf[cached_bin.len] = 0;
    const cached_bin_z: [*:0]const u8 = cached_bin_z_buf[0..cached_bin.len :0];

    // Support up to 64 forwarded arguments.
    var argv_storage: [66]?[*:0]const u8 = undefined;
    if (forward_args.len + 2 > argv_storage.len) {
        stderrPrint("zit: too many arguments\n", .{});
        return 1;
    }
    argv_storage[0] = cached_bin_z;
    for (forward_args, 0..) |arg, i| {
        // argsAlloc already dupeZ'd these, but the type is []const u8.
        // We need [*:0]const u8. The underlying data from argsAlloc IS null-terminated.
        argv_storage[1 + i] = @ptrCast(arg.ptr);
    }
    argv_storage[1 + forward_args.len] = null;
    const argv_ptr: [*:null]const ?[*:0]const u8 = argv_storage[0 .. forward_args.len + 1 :null];

    const envp: [*:null]const ?[*:0]const u8 = @ptrCast(std.os.environ.ptr);
    const err = std.posix.execveZ(cached_bin_z, argv_ptr, envp);
    stderrPrint("zit: exec failed: {s}\n", .{@errorName(err)});
    return 1;
}

fn printUsage() void {
    stderrPrint(
        \\usage:
        \\  zit [--debug] [--recompile] <source.zig> [args...]
        \\  zit clean-caches
        \\  zit toggle-shebang <source.zig>
    , .{});
}

fn cleanCaches(gpa: mem.Allocator) u8 {
    const cache_dir = getCacheDir(gpa) catch |err| {
        stderrPrint("zit: cannot resolve cache dir: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(cache_dir);

    fs.cwd().deleteTree(cache_dir) catch {};
    stderrPrint("zit: cache cleared ({s})\n", .{cache_dir});
    return 0;
}

fn toggleShebang(gpa: mem.Allocator, source_path: []const u8) u8 {
    const source = fs.cwd().readFileAlloc(gpa, source_path, 64 * 1024 * 1024) catch |err| {
        stderrPrint("zit: cannot read '{s}': {s}\n", .{ source_path, @errorName(err) });
        return 1;
    };
    defer gpa.free(source);

    const shebang = "#!/usr/bin/env zit\n";
    if (hasShebang(source)) {
        const stripped = stripShebang(source);
        fs.cwd().writeFile(.{ .sub_path = source_path, .data = stripped }) catch |err| {
            stderrPrint("zit: cannot update '{s}': {s}\n", .{ source_path, @errorName(err) });
            return 1;
        };
        stderrPrint("zit: shebang removed ({s})\n", .{source_path});
        return 0;
    }

    const with_shebang = std.fmt.allocPrint(gpa, "{s}{s}", .{ shebang, source }) catch |err| {
        stderrPrint("zit: cannot build shebang source: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(with_shebang);

    fs.cwd().writeFile(.{ .sub_path = source_path, .data = with_shebang }) catch |err| {
        stderrPrint("zit: cannot update '{s}': {s}\n", .{ source_path, @errorName(err) });
        return 1;
    };
    stderrPrint("zit: shebang added ({s})\n", .{source_path});
    return 0;
}

fn hasShebang(source: []const u8) bool {
    return source.len >= 2 and source[0] == '#' and source[1] == '!';
}

fn stripShebang(source: []const u8) []const u8 {
    if (!hasShebang(source)) return source;
    const newline = mem.indexOfScalar(u8, source, '\n') orelse return source[source.len..];
    return source[newline + 1 ..];
}

/// Length-prefix a field into the hasher to avoid domain collisions.
/// e.g. "/tmp/ab" + "cdef" != "/tmp/abc" + "def"
fn hashField(hasher: *std.hash.XxHash3, data: []const u8) void {
    var len_buf: [8]u8 = undefined;
    mem.writeInt(u64, &len_buf, @intCast(data.len), .little);
    hasher.update(&len_buf);
    hasher.update(data);
}

/// Scan source for @import("...") with relative paths, read & hash those files.
/// Only goes one level deep — good enough for script-style single-file + helpers.
fn hashImports(hasher: *std.hash.XxHash3, source: []const u8, source_path: []const u8, gpa: mem.Allocator) void {
    // Get directory of source file
    const dir = if (mem.lastIndexOfScalar(u8, source_path, '/')) |i| source_path[0 .. i + 1] else "./";

    var pos: usize = 0;
    while (pos < source.len) {
        // Find @import("
        const needle = "@import(\"";
        const idx = mem.indexOfPos(u8, source, pos, needle) orelse break;
        const start = idx + needle.len;
        const end = mem.indexOfScalarPos(u8, source, start, '"') orelse break;
        const path = source[start..end];
        pos = end + 1;

        // Skip std library imports
        if (mem.eql(u8, path, "std") or mem.eql(u8, path, "builtin")) continue;
        // Only relative paths (contain '/' or end in '.zig')
        if (!mem.endsWith(u8, path, ".zig")) continue;

        // Resolve relative to source file's directory
        const full = std.fmt.allocPrint(gpa, "{s}{s}", .{ dir, path }) catch continue;
        defer gpa.free(full);

        const contents = fs.cwd().readFileAlloc(gpa, full, 64 * 1024 * 1024) catch continue;
        defer gpa.free(contents);

        hashField(hasher, path);
        hashField(hasher, contents);
    }
}

/// Get zig compiler version string (compile-time constant).
fn zigVersion() []const u8 {
    return @import("builtin").zig_version_string;
}

/// Remove files in dir whose names contain the given substring.
fn cleanGlob(gpa: mem.Allocator, dir_path: []const u8, substring: []const u8) !void {
    var dir = try fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (mem.indexOf(u8, entry.name, substring) != null) {
            const full = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir_path, entry.name });
            defer gpa.free(full);
            fs.cwd().deleteFile(full) catch {};
        }
    }
}

fn getCacheDir(allocator: mem.Allocator) ![]u8 {
    if (std.posix.getenv("XDG_CACHE_HOME")) |xdg| {
        return std.fmt.allocPrint(allocator, "{s}/zit", .{xdg});
    }
    if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.cache/zit", .{home});
    }
    return std.fmt.allocPrint(allocator, "/tmp/zit", .{});
}
