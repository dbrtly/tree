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
    should_ignore_git_ignored: bool = false,
};

fn isUpper(name: []const u8) bool {
    if (name.len == 0) return false;
    const c = name[0];
    return c >= 'A' and c <= 'Z';
}

fn compareFileEntries(context: void, a: FileEntry, b: FileEntry) bool {
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

fn checkGitIgnoreBatch(allocator: Allocator, dir_path: []const u8, names: []const []const u8) !std.StringHashMap(void) {
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
        for (names) |name| {
            try stdin.writeAll(name);
            try stdin.writeAll("\n");
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
            const remaining = slice[newline_idx + 1..];
            mem.copyForwards(u8, buf[0..remaining.len], remaining);
            slice = buf[0..remaining.len];
        }
        start = slice.len;
    }

    _ = try child.wait();

    return ignored_set;
}

fn getSortedEntries(allocator: Allocator, path: []const u8, options: TreeOptions) !std.ArrayList(FileEntry) {
    var dir = try fs.openDirAbsolute(path, .{ .iterate = true });
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
        try all_names.append(allocator, try allocator.dupe(u8, entry.name));
    }

    var ignored_set: ?std.StringHashMap(void) = null;
    if (options.should_ignore_git_ignored) {
        // We attempt to check git ignore. If it fails (e.g. not a git repo), we just proceed with empty set.
        ignored_set = checkGitIgnoreBatch(allocator, path, all_names.items) catch null;
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
        if (ignored_set) |set| {
            if (set.contains(name)) {
                continue;
            }
        }
        const file_entry = try FileEntry.create(allocator, path, name);
        try entries.append(allocator, file_entry);
    }

    std.sort.insertion(FileEntry, entries.items, {}, compareFileEntries);
    return entries;
}

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

fn printTree(
    allocator: Allocator,
    path: []const u8,
    prefix: []const u8,
    options: TreeOptions,
    depth: usize,
    writer: anytype,
) !void {
    var entries = try getSortedEntries(allocator, path, options);
    defer {
        for (entries.items) |*entry| {
            entry.deinit(allocator);
        }
        entries.deinit(allocator);
    }
    try printTreeRecursive(allocator, entries.items, prefix, options, depth, writer);
}

const ParseResult = struct {
    options: TreeOptions,
    target_path: []const u8,
};

fn parseArgs(args: []const []const u8) !ParseResult {
    var options = TreeOptions{};
    var target_path: []const u8 = ".";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (mem.eql(u8, arg, "--all")) {
            options.show_hidden = true;
        } else if (mem.eql(u8, arg, "--max-depth")) {
            i += 1;
            if (i < args.len) {
                options.max_depth = try std.fmt.parseInt(usize, args[i], 10);
            } else {
                std.debug.print("Missing argument for max depth\n", .{});
                return error.InvalidArgument;
            }
        } else if (mem.eql(u8, arg, "--gitignore")) {
            options.should_ignore_git_ignored = true;
        } else if (mem.startsWith(u8, arg, "-")) {
            // Handle short flags and combined flags
            // Special case for -L which takes an argument
            if (mem.eql(u8, arg, "-L")) {
                i += 1;
                if (i < args.len) {
                    options.max_depth = try std.fmt.parseInt(usize, args[i], 10);
                } else {
                    std.debug.print("Missing argument for max depth\n", .{});
                    return error.InvalidArgument;
                }
                continue;
            }

            // Iterate over characters for combined flags
            for (arg[1..]) |c| {
                switch (c) {
                    'a' => options.show_hidden = true,
                    'g' => options.should_ignore_git_ignored = true,
                    else => {
                        // Unknown flag, treat as path if it looks like one? 
                        // Or just ignore/error? 
                        // Standard behavior is usually error for unknown flag.
                        // But for now let's just ignore unknown chars in combined flags 
                        // or maybe print warning?
                        // Let's stick to simple: if it's not a known flag char, it's ignored.
                    },
                }
            }
        } else {
            target_path = arg;
        }
    }

    return ParseResult{
        .options = options,
        .target_path = target_path,
    };
}

/// Main function of the tree application.
pub fn main() anyerror!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const parse_result = try parseArgs(args);
    const options = parse_result.options;
    const target_path = parse_result.target_path;

    // Get absolute path
    var abs_path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try fs.realpath(target_path, &abs_path_buf);

    // Print the name of the directory we're listing
    const dirname = std.fs.path.basename(abs_path);
    std.debug.print("{s}\n", .{dirname});

    // Create writer
    var buffer: [1024]u8 = undefined;
    var stdout_file_writer = std.fs.File.stdout().writer(&buffer);
    const buffered_stdout = &stdout_file_writer.interface;

    try printTree(allocator, abs_path, "", options, 0, buffered_stdout);
    try buffered_stdout.flush();
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
    try testing.expect(!options.should_ignore_git_ignored);
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
    const argv_init = &[_][]const u8{ "git", "init" };
    var child_init = std.process.Child.init(argv_init, allocator);
    child_init.cwd = path;
    child_init.stdin_behavior = .Ignore;
    child_init.stdout_behavior = .Ignore;
    child_init.stderr_behavior = .Ignore;
    _ = try child_init.spawnAndWait();

    // Create .gitignore
    {
        var file = try tmp_dir.dir.createFile(".gitignore", .{});
        try file.writeAll("ignored.txt\n");
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

// Test to run the entire program with mock arguments
test "parseArgs combined flags" {
    const testing = std.testing;

    // Test -ag
    {
        const args = &[_][]const u8{ "tree", "-ag" };
        const result = try parseArgs(args);
        try testing.expect(result.options.show_hidden);
        try testing.expect(result.options.should_ignore_git_ignored);
    }

    // Test -ga
    {
        const args = &[_][]const u8{ "tree", "-ga" };
        const result = try parseArgs(args);
        try testing.expect(result.options.show_hidden);
        try testing.expect(result.options.should_ignore_git_ignored);
    }

    // Test separate flags
    {
        const args = &[_][]const u8{ "tree", "-a", "-g" };
        const result = try parseArgs(args);
        try testing.expect(result.options.show_hidden);
        try testing.expect(result.options.should_ignore_git_ignored);
    }

    // Test mixed with path
    {
        const args = &[_][]const u8{ "tree", "-ag", "src" };
        const result = try parseArgs(args);
        try testing.expect(result.options.show_hidden);
        try testing.expect(result.options.should_ignore_git_ignored);
        try testing.expectEqualStrings("src", result.target_path);
    }
}
