const std = @import("std");
const mem = std.mem;
const types = @import("types.zig");
const TreeOptions = types.TreeOptions;

/// Result of argument parsing.
pub const ParseResult = struct {
    options: TreeOptions,
    target_path: []const u8,
};

/// Parses command line arguments.
pub fn parseArgs(args: []const []const u8) anyerror!ParseResult {
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
