const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;

const FileEntry = struct {
    name: []const u8,
    path: []const u8,
    is_dir: bool,
    is_hidden: bool,

    fn create(allocator: Allocator, dir_path: []const u8, name: []const u8) !FileEntry {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, name });
        const is_hidden = name.len > 0 and name[0] == '.';

        var stat_buf: std.fs.File.Stat = undefined;
        var dir = try std.fs.openDirAbsolute(dir_path, .{});
        defer dir.close();

        stat_buf = try dir.statFile(name);

        return FileEntry{
            .name = try allocator.dupe(u8, name),
            .path = path,
            .is_dir = stat_buf.kind == .directory,
            .is_hidden = is_hidden,
        };
    }

    fn deinit(self: *FileEntry, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
    }
};

const TreeOptions = struct {
    show_hidden: bool = false,
    max_depth: ?usize = null,
};

fn compareFileEntries(context: void, a: FileEntry, b: FileEntry) bool {
    _ = context;

    // Hidden files first (if they're shown)
    if (a.is_hidden != b.is_hidden) {
        return a.is_hidden;
    }

    // Directories first
    if (a.is_dir != b.is_dir) {
        return a.is_dir;
    }

    // Check for uppercase - uppercase comes first
    const a_first_char = if (a.name.len > 0) a.name[0] else 0;
    const b_first_char = if (b.name.len > 0) b.name[0] else 0;

    const a_is_upper = a_first_char >= 'A' and a_first_char <= 'Z';
    const b_is_upper = b_first_char >= 'A' and b_first_char <= 'Z';

    if (a_is_upper != b_is_upper) {
        return a_is_upper;
    }

    // Finally, natural sort (alphanumeric)
    return std.ascii.lessThanIgnoreCase(a.name, b.name);
}

fn printTree(
    allocator: Allocator,
    path: []const u8,
    prefix: []const u8,
    options: TreeOptions,
    depth: usize,
) !void {
    // Check max depth
    if (options.max_depth) |max_depth| {
        if (depth > max_depth) return;
    }

    var dir = try fs.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    var entries = std.ArrayList(FileEntry).init(allocator);
    defer {
        for (entries.items) |*entry| {
            entry.deinit(allocator);
        }
        entries.deinit();
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Skip hidden files if not showing hidden
        if (!options.show_hidden and entry.name[0] == '.') {
            continue;
        }

        const file_entry = try FileEntry.create(allocator, path, entry.name);
        try entries.append(file_entry);
    }

    // Sort entries according to our custom logic
    std.sort.insertion(FileEntry, entries.items, {}, compareFileEntries);

    for (entries.items, 0..) |entry, i| {
        const is_last = i == entries.items.len - 1;
        const branch = if (is_last) "└── " else "├── ";
        const next_prefix = if (is_last) "    " else "│   ";

        // Print current entry
        std.debug.print("{s}{s}{s}\n", .{ prefix, branch, entry.name });

        // Recursively process directories
        if (entry.is_dir) {
            const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, next_prefix });
            defer allocator.free(new_prefix);
            try printTree(allocator, entry.path, new_prefix, options, depth + 1);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var options = TreeOptions{};
    var target_path: []const u8 = "."; // Default to current directory

    // Simple argument parsing
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (mem.eql(u8, arg, "-a") or mem.eql(u8, arg, "--all")) {
            options.show_hidden = true;
        } else if (mem.eql(u8, arg, "-L") or mem.eql(u8, arg, "--max-depth")) {
            i += 1;
            if (i < args.len) {
                options.max_depth = try std.fmt.parseInt(usize, args[i], 10);
            } else {
                std.debug.print("Missing argument for max depth\n", .{});
                return error.InvalidArgument;
            }
        } else if (!mem.startsWith(u8, arg, "-")) {
            target_path = arg;
        }
    }

    // Get absolute path
    var abs_path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try fs.realpath(target_path, &abs_path_buf);

    // Print the name of the directory we're listing
    const dirname = std.fs.path.basename(abs_path);
    std.debug.print("{s}\n", .{dirname});

    // Start tree traversal
    try printTree(allocator, abs_path, "", options, 0);
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

test "TreeOptions default values" {
    const testing = std.testing;

    // Create default options
    const options = TreeOptions{};

    // Check default values
    try testing.expect(!options.show_hidden);
    try testing.expect(options.max_depth == null);
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
    try printTree(allocator, path, "", options, 0);

    // Test with show_hidden = true
    const options_hidden = TreeOptions{ .show_hidden = true };
    try printTree(allocator, path, "", options_hidden, 0);

    // Test with max_depth = 0 (should only show the root)
    const options_depth = TreeOptions{ .max_depth = 0 };
    try printTree(allocator, path, "", options_depth, 0);
}

// Test to run the entire program with mock arguments
test "main function argument parsing" {
    // To properly test main, you would need to mock process.args
    // This is a more advanced test that might require modifications
    // to your code to make it testable
    // For now, we'll just note that this would be valuable to test
}
