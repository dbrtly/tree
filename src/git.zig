const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = std.mem;

/// Checks which files are ignored by git.
pub fn checkGitIgnoreBatch(allocator: Allocator, dir_path: []const u8, names: []const []const u8) !std.StringHashMap(void) {
    var ignored_set = std.StringHashMap(void).init(allocator);
    errdefer ignored_set.deinit();

    // Prepare arguments for git check-ignore
    // We want: git check-ignore --stdin
    const argv_run = &[_][]const u8{ "git", "check-ignore", "--stdin" };

    var child = std.process.Child.init(argv_run, allocator);
    child.cwd = dir_path;
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore; // Ignore errors (like not a git repo)

    try child.spawn();

    // Write names to stdin
    {
        const stdin = child.stdin.?;
        var writer_wrapper = stdin.writer(&[_]u8{});
        for (names) |name| {
            try writer_wrapper.interface.writeAll(name);
            try writer_wrapper.interface.writeAll("\n");
        }
        stdin.close();
    }
    // Close stdin to signal end of input
    child.stdin = null;

    // Read stdout
    var buf: [4096]u8 = undefined;
    var start: usize = 0;
    const stdout = child.stdout.?;

    while (true) {
        const bytes_read = try stdout.read(buf[start..]);
        if (bytes_read == 0) break;

        const end = start + bytes_read;
        var slice = buf[0..end];

        while (mem.indexOfScalar(u8, slice, '\n')) |newline_idx| {
            const line = slice[0..newline_idx];
            try ignored_set.put(try allocator.dupe(u8, line), {});

            // Move remaining
            const remaining = slice[newline_idx + 1 ..];
            mem.copyForwards(u8, buf[0..remaining.len], remaining);
            slice = buf[0..remaining.len];
        }
        start = slice.len;
    }

    const term = try child.wait();
    if (term != .Exited) return error.GitCheckIgnoreFailed;
    if (term.Exited != 0 and term.Exited != 1) {
        return error.GitCheckIgnoreFailed;
    }

    return ignored_set;
}

test "checkGitIgnoreBatch" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a temporary directory for testing
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Get path to the temporary directory
    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    // Initialize git repo
    const argv_init = &[_][]const u8{ "git", "init", "--quiet" };
    var child_init = std.process.Child.init(argv_init, allocator);
    child_init.cwd = path;
    child_init.stdin_behavior = .Ignore;
    child_init.stdout_behavior = .Ignore;
    child_init.stderr_behavior = .Ignore;
    _ = try child_init.spawnAndWait();

    // Create .gitignore
    {
        var file = try tmp_dir.dir.createFile(".gitignore", .{});
        var writer_wrapper = file.writer(&[_]u8{});
        try writer_wrapper.interface.writeAll("ignored.txt\n");
        file.close();
    }

    // Test checkGitIgnoreBatch
    const names = &[_][]const u8{ "ignored.txt", "visible.txt", ".gitignore" };
    var ignored_set = try checkGitIgnoreBatch(allocator, path, names);
    defer {
        var key_iter = ignored_set.keyIterator();
        while (key_iter.next()) |key| {
            allocator.free(key.*);
        }
        ignored_set.deinit();
    }

    try testing.expect(ignored_set.contains("ignored.txt"));
    try testing.expect(!ignored_set.contains("visible.txt"));
    try testing.expect(!ignored_set.contains(".gitignore"));
}

test "checkGitIgnoreBatch buffer management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    // Init git
    const argv_init = &[_][]const u8{ "git", "init", "--quiet" };
    var child_init = std.process.Child.init(argv_init, allocator);
    child_init.cwd = path;
    child_init.stdin_behavior = .Ignore;
    child_init.stdout_behavior = .Ignore;
    child_init.stderr_behavior = .Ignore;
    _ = try child_init.spawnAndWait();

    // Create .gitignore with many entries to potentially trigger buffer logic
    {
        var file = try tmp_dir.dir.createFile(".gitignore", .{});
        var writer_wrapper = file.writer(&[_]u8{});
        try writer_wrapper.interface.writeAll("file1.txt\nfile2.txt\nfile3.txt\n");
        file.close();
    }

    const names = &[_][]const u8{ "file1.txt", "file2.txt", "file3.txt" };
    var ignored_set = try checkGitIgnoreBatch(allocator, path, names);
    defer {
        var key_iter = ignored_set.keyIterator();
        while (key_iter.next()) |key| {
            allocator.free(key.*);
        }
        ignored_set.deinit();
    }

    try testing.expect(ignored_set.contains("file1.txt"));
    try testing.expect(ignored_set.contains("file2.txt"));
    try testing.expect(ignored_set.contains("file3.txt"));
}

test "checkGitIgnoreBatch invalid directory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const names = &[_][]const u8{"file.txt"};
    // Use a non-existent directory
    try testing.expectError(error.FileNotFound, checkGitIgnoreBatch(allocator, "/non/existent/dir/path/12345", names));
}

test "checkGitIgnoreBatch empty names" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    // Init git
    const argv_init = &[_][]const u8{ "git", "init", "--quiet" };
    var child_init = std.process.Child.init(argv_init, allocator);
    child_init.cwd = path;
    child_init.stdin_behavior = .Ignore;
    child_init.stdout_behavior = .Ignore;
    child_init.stderr_behavior = .Ignore;
    _ = try child_init.spawnAndWait();

    const names = &[_][]const u8{};
    var ignored_set = try checkGitIgnoreBatch(allocator, path, names);
    defer ignored_set.deinit();

    try testing.expectEqual(@as(u32, 0), ignored_set.count());
}

test "checkGitIgnoreBatch not a git repo" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    const names = &[_][]const u8{"file.txt"};
    // To force a git failure even if we are inside another git repo,
    // we can create a dummy .git FILE (not directory).
    try tmp_dir.dir.writeFile(.{ .sub_path = ".git", .data = "not a directory" });

    const result = checkGitIgnoreBatch(allocator, path, names);
    try testing.expectError(error.GitCheckIgnoreFailed, result);
}
