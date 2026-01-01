const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const FileEntry = types.FileEntry;
const TreeOptions = types.TreeOptions;

const fs_mod = @import("fs.zig");
const getSortedEntries = fs_mod.getSortedEntries;

fn printTreeRecursive(
    allocator: Allocator,
    entries: []const FileEntry,
    prefix: []const u8,
    options: TreeOptions,
    depth: usize,
    writer: anytype,
) !void {
    if (options.max_depth) |max_depth| {
        if (depth > max_depth) return;
    }

    for (entries, 0..) |entry, i| {
        const is_last = i == entries.len - 1;
        const branch = if (is_last) "└── " else "├── ";
        const next_prefix = if (is_last) "    " else "│   ";

        try writer.print("{s}{s}{s}\n", .{ prefix, branch, entry.name });

        if (entry.is_dir) {
            const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, next_prefix });
            defer allocator.free(new_prefix);

            var sub_entries = try getSortedEntries(allocator, entry.path, options);
            defer {
                for (sub_entries.items) |*sub_entry| {
                    sub_entry.deinit(allocator);
                }
                sub_entries.deinit(allocator);
            }

            try printTreeRecursive(allocator, sub_entries.items, new_prefix, options, depth + 1, writer);
        }
    }
}

/// Prints the directory tree.
pub fn printTree(
    allocator: Allocator,
    path: []const u8,
    prefix: []const u8,
    options: TreeOptions,
    depth: usize,
    writer: anytype,
) anyerror!void {
    var entries = try getSortedEntries(allocator, path, options);
    defer {
        for (entries.items) |*entry| {
            entry.deinit(allocator);
        }
        entries.deinit(allocator);
    }
    try printTreeRecursive(allocator, entries.items, prefix, options, depth, writer);
}

test "Directory traversal with printTree" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a test directory structure
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Get path to the temporary directory
    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    // Create a simple directory structure
    try tmp_dir.dir.makeDir("dir1");
    try tmp_dir.dir.makeDir("dir2");
    {
        var file = try tmp_dir.dir.createFile("file1.txt", .{});
        file.close();
    }
    {
        var file = try tmp_dir.dir.createFile(".hidden", .{});
        file.close();
    }

    var sub_dir = try tmp_dir.dir.openDir("dir1", .{});
    {
        var file = try sub_dir.createFile("subfile.txt", .{});
        file.close();
    }
    sub_dir.close();

    // This test is tricky because printTree prints to stdout
    // We're going to do a minimal test to ensure it doesn't crash
    // A more thorough test would redirect stdout and verify output
    const options = TreeOptions{};
    var alloc_writer = std.io.Writer.Allocating.init(allocator);
    defer alloc_writer.deinit();

    try printTree(allocator, path, "", options, 0, &alloc_writer.writer);

    // Test with show_hidden = true
    alloc_writer.deinit();
    alloc_writer = std.io.Writer.Allocating.init(allocator);
    const options_hidden = TreeOptions{ .show_hidden = true };
    try printTree(allocator, path, "", options_hidden, 0, &alloc_writer.writer);

    // Test with max_depth = 0 (should only show the root)
    alloc_writer.deinit();
    alloc_writer = std.io.Writer.Allocating.init(allocator);
    const options_depth = TreeOptions{ .max_depth = 0 };
    try printTree(allocator, path, "", options_depth, 0, &alloc_writer.writer);
}
