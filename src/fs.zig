const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = std.mem;
const fs = std.fs;

const types = @import("types.zig");
const FileEntry = types.FileEntry;
const TreeOptions = types.TreeOptions;

const git = @import("git.zig");

fn isUpper(name: []const u8) bool {
    if (name.len == 0) return false;
    const c = name[0];
    return c >= 'A' and c <= 'Z';
}

/// Compares two FileEntries for sorting.
pub fn compareFileEntries(context: void, a: FileEntry, b: FileEntry) bool {
    _ = context;

    if (a.is_hidden != b.is_hidden) {
        return a.is_hidden; // hidden comes first
    }
    if (a.is_dir != b.is_dir) {
        return a.is_dir; // directories come first
    }
    const a_is_upper = isUpper(a.name);
    const b_is_upper = isUpper(b.name);
    if (a_is_upper != b_is_upper) {
        return a_is_upper; // uppercase comes first
    }

    return std.ascii.lessThanIgnoreCase(a.name, b.name);
}

/// Retrieves and sorts entries in a directory.
pub fn getSortedEntries(allocator: Allocator, path: []const u8, options: TreeOptions) !std.ArrayList(FileEntry) {
    var dir = try fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var all_names = std.ArrayList([]const u8){};
    defer {
        for (all_names.items) |name| {
            allocator.free(name);
        }
        all_names.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (!options.show_hidden and entry.name[0] == '.') {
            continue;
        }
        const name_dupe = try allocator.dupe(u8, entry.name);
        all_names.append(allocator, name_dupe) catch |err| {
            allocator.free(name_dupe);
            return err;
        };
    }

    var ignored_set: ?std.StringHashMap(void) = null;
    if (options.should_ignore_git_ignored) {
        // We attempt to check git ignore. If it fails (e.g. not a git repo), we just proceed with empty set.
        ignored_set = git.checkGitIgnoreBatch(allocator, path, all_names.items) catch null;
    }
    defer if (ignored_set) |*set| {
        var key_iter = set.keyIterator();
        while (key_iter.next()) |key| {
            allocator.free(key.*);
        }
        set.deinit();
    };

    var entries = std.ArrayList(FileEntry){};
    errdefer {
        for (entries.items) |*e| e.deinit(allocator);
        entries.deinit(allocator);
    }

    for (all_names.items) |name| {
        var ignored = false;
        if (ignored_set) |set| {
            if (set.contains(name)) {
                ignored = true;
            }
        }
        if (ignored) {
            continue;
        }
        const file_entry = try FileEntry.create(allocator, path, name);
        entries.append(allocator, file_entry) catch |err| {
            var mutable_entry = file_entry;
            mutable_entry.deinit(allocator);
            return err;
        };
    }

    std.sort.insertion(FileEntry, entries.items, {}, compareFileEntries);
    return entries;
}

test "compareFileEntries sorting logic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test entries
    var entries = [_]FileEntry{
        // Regular files
        FileEntry{
            .name = try allocator.dupe(u8, "file.txt"),
            .path = try allocator.dupe(u8, "/path/file.txt"),
            .is_dir = false,
            .is_hidden = false,
        },
        // Uppercase files (should come before lowercase)
        FileEntry{
            .name = try allocator.dupe(u8, "Uppercase.txt"),
            .path = try allocator.dupe(u8, "/path/Uppercase.txt"),
            .is_dir = false,
            .is_hidden = false,
        },
        // Directories (should come before files)
        FileEntry{
            .name = try allocator.dupe(u8, "directory"),
            .path = try allocator.dupe(u8, "/path/directory"),
            .is_dir = true,
            .is_hidden = false,
        },
        // Hidden files (should come first)
        FileEntry{
            .name = try allocator.dupe(u8, ".hidden"),
            .path = try allocator.dupe(u8, "/path/.hidden"),
            .is_dir = false,
            .is_hidden = true,
        },
        // Hidden directory (should come before hidden files)
        FileEntry{
            .name = try allocator.dupe(u8, ".hidden_dir"),
            .path = try allocator.dupe(u8, "/path/.hidden_dir"),
            .is_dir = true,
            .is_hidden = true,
        },
        // Uppercase directory (should come before lowercase directories)
        FileEntry{
            .name = try allocator.dupe(u8, "Upper_dir"),
            .path = try allocator.dupe(u8, "/path/Upper_dir"),
            .is_dir = true,
            .is_hidden = false,
        },
    };

    // Clean up all the allocated memory
    defer for (&entries) |*entry| {
        allocator.free(entry.name);
        allocator.free(entry.path);
    };

    // Sort the entries
    std.sort.insertion(FileEntry, &entries, {}, compareFileEntries);

    // Check that hidden entries come first
    try testing.expect(entries[0].is_hidden);
    try testing.expect(entries[1].is_hidden);

    // Check that hidden directories come before hidden files
    try testing.expect(entries[0].is_dir);
    try testing.expect(!entries[1].is_dir);

    // Check that non-hidden directories come next
    try testing.expect(entries[2].is_dir);
    try testing.expect(entries[3].is_dir);

    // Check that uppercase directories come before lowercase directories
    try testing.expectEqualStrings("Upper_dir", entries[2].name);
    try testing.expectEqualStrings("directory", entries[3].name);

    // Check that uppercase files come before lowercase files
    try testing.expectEqualStrings("Uppercase.txt", entries[4].name);
    try testing.expectEqualStrings("file.txt", entries[5].name);
}

test "should_ignore_git_ignored flag" {
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

    // Create ignored file
    {
        var file = try tmp_dir.dir.createFile("ignored.txt", .{});
        file.close();
    }

    // Create visible file
    {
        var file = try tmp_dir.dir.createFile("visible.txt", .{});
        file.close();
    }

    // Test with should_ignore_git_ignored = true
    const options = TreeOptions{ .should_ignore_git_ignored = true, .show_hidden = true };
    var entries = try getSortedEntries(allocator, path, options);
    defer {
        for (entries.items) |*entry| {
            entry.deinit(allocator);
        }
        entries.deinit(allocator);
    }

    // Verify results
    try testing.expectEqual(@as(usize, 3), entries.items.len); // .git, .gitignore and visible.txt

    var found_visible = false;
    var found_ignored = false;
    var found_git = false;

    for (entries.items) |entry| {
        if (mem.eql(u8, entry.name, "visible.txt")) found_visible = true;
        if (mem.eql(u8, entry.name, "ignored.txt")) found_ignored = true;
        if (mem.eql(u8, entry.name, ".git")) found_git = true;
    }

    try testing.expect(found_visible);
    try testing.expect(!found_ignored);
    try testing.expect(found_git);
}

test "isUpper with empty string" {
    const testing = std.testing;
    // This covers the name.len == 0 check in isUpper
    const entry = FileEntry{
        .name = "",
        .path = "",
        .is_dir = false,
        .is_hidden = false,
    };
    // compareFileEntries calls isUpper
    try testing.expect(!compareFileEntries({}, entry, entry));
}

test "getSortedEntries git failure" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    // Create a file
    {
        var file = try tmp_dir.dir.createFile("test.txt", .{});
        defer file.close();
        try file.writeAll("hello");
    }

    // To force a git failure even if we are inside another git repo,
    // we can create a dummy .git FILE (not directory).
    try tmp_dir.dir.writeFile(.{ .sub_path = ".git", .data = "not a directory" });

    // Test with should_ignore_git_ignored = true in a non-git directory
    // This should hit the 'catch null' branch in getSortedEntries
    const options = TreeOptions{ .should_ignore_git_ignored = true };
    var entries = try getSortedEntries(allocator, path, options);
    defer {
        for (entries.items) |*entry| entry.deinit(allocator);
        entries.deinit(allocator);
    }

    try testing.expectEqual(@as(usize, 1), entries.items.len);
    try testing.expectEqualStrings("test.txt", entries.items[0].name);
}

test "getSortedEntries hidden files" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    try tmp_dir.dir.writeFile(.{ .sub_path = ".hidden", .data = "" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "visible", .data = "" });

    // Test with show_hidden = false
    {
        const options = TreeOptions{ .show_hidden = false };
        var entries = try getSortedEntries(allocator, path, options);
        defer {
            for (entries.items) |*entry| entry.deinit(allocator);
            entries.deinit(allocator);
        }
        try testing.expectEqual(@as(usize, 1), entries.items.len);
        try testing.expectEqualStrings("visible", entries.items[0].name);
    }

    // Test with show_hidden = true
    {
        const options = TreeOptions{ .show_hidden = true };
        var entries = try getSortedEntries(allocator, path, options);
        defer {
            for (entries.items) |*entry| entry.deinit(allocator);
            entries.deinit(allocator);
        }
        try testing.expectEqual(@as(usize, 2), entries.items.len);
    }
}

fn getSortedEntriesWrapper(allocator: Allocator, path: []const u8, options: TreeOptions) !void {
    var entries = try getSortedEntries(allocator, path, options);
    for (entries.items) |*e| e.deinit(allocator);
    entries.deinit(allocator);
}

test "getSortedEntries allocation failures" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    try tmp_dir.dir.writeFile(.{ .sub_path = "file1.txt", .data = "" });

    const options = TreeOptions{};

    try testing.checkAllAllocationFailures(allocator, getSortedEntriesWrapper, .{ path, options });
}
