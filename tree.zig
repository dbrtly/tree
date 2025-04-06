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
