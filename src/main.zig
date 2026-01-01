const std = @import("std");
const fs = std.fs;
const root = @import("tree_lib");

/// Main function of the tree application.
pub fn main() anyerror!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const parse_result = try root.parseArgs(args);
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

    try root.printTree(allocator, abs_path, "", options, 0, buffered_stdout);
}

test {
    _ = root;
}
