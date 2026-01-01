const std = @import("std");
const Allocator = std.mem.Allocator;

/// Options for the tree command.
pub const TreeOptions = struct {
    max_depth: ?usize = null,
    show_hidden: bool = false,
    should_ignore_git_ignored: bool = false,
};

/// Represents a file or directory entry.
pub const FileEntry = struct {
    name: []const u8,
    path: []const u8,
    is_dir: bool,
    is_hidden: bool,

    /// Creates a new FileEntry.
    pub fn create(allocator: Allocator, dir_path: []const u8, name: []const u8) anyerror!FileEntry {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, name });
        errdefer allocator.free(path);
        const is_hidden = name.len > 0 and name[0] == '.';

        var stat_buf: std.fs.File.Stat = undefined;
        var dir = try std.fs.cwd().openDir(dir_path, .{});
        defer dir.close();

        stat_buf = try dir.statFile(name);

        return FileEntry{
            .name = try allocator.dupe(u8, name),
            .path = path,
            .is_dir = stat_buf.kind == .directory,
            .is_hidden = is_hidden,
        };
    }

    /// Frees memory associated with the FileEntry.
    pub fn deinit(self: *FileEntry, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
    }
};

test "TreeOptions default values" {
    const testing = std.testing;

    // Create default options
    const options = TreeOptions{};

    // Check default values
    try testing.expect(!options.show_hidden);
    try testing.expect(options.max_depth == null);
    try testing.expect(!options.should_ignore_git_ignored);
}

test "FileEntry creation and properties" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a temporary directory for testing
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Get path to the temporary directory
    const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    // Create a regular file
    {
        var file = try tmp_dir.dir.createFile("regular_file.txt", .{});
        file.close();
    }

    // Create a directory
    try tmp_dir.dir.makeDir("test_dir");

    // Create a hidden file
    {
        var file = try tmp_dir.dir.createFile(".hidden_file", .{});
        file.close();
    }

    // Test regular file
    {
        var entry = try FileEntry.create(allocator, path, "regular_file.txt");
        defer entry.deinit(allocator);

        try testing.expect(!entry.is_dir);
        try testing.expect(!entry.is_hidden);
        try testing.expectEqualStrings("regular_file.txt", entry.name);
    }

    // Test directory
    {
        var entry = try FileEntry.create(allocator, path, "test_dir");
        defer entry.deinit(allocator);

        try testing.expect(entry.is_dir);
        try testing.expect(!entry.is_hidden);
        try testing.expectEqualStrings("test_dir", entry.name);
    }

    // Test hidden file
    {
        var entry = try FileEntry.create(allocator, path, ".hidden_file");
        defer entry.deinit(allocator);

        try testing.expect(!entry.is_dir);
        try testing.expect(entry.is_hidden);
        try testing.expectEqualStrings(".hidden_file", entry.name);
    }
}
