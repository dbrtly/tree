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
            if (i + 1 < args.len) {
                if (std.fmt.parseInt(usize, args[i + 1], 10) catch null) |val| {
                    options.max_depth = val;
                    i += 1;
                }
            }
        } else if (mem.eql(u8, arg, "--gitignore")) {
            options.should_ignore_git_ignored = true;
        } else if (mem.startsWith(u8, arg, "-")) {
            // Handle short flags and combined flags
            // Special case for -L which takes an argument
            if (mem.eql(u8, arg, "-L")) {
                if (i + 1 < args.len) {
                    if (std.fmt.parseInt(usize, args[i + 1], 10) catch null) |val| {
                        options.max_depth = val;
                        i += 1;
                    }
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

test "parseArgs long flags" {
    const testing = std.testing;

    // Test --all
    {
        const args = &[_][]const u8{ "tree", "--all" };
        const result = try parseArgs(args);
        try testing.expect(result.options.show_hidden);
    }

    // Test --gitignore
    {
        const args = &[_][]const u8{ "tree", "--gitignore" };
        const result = try parseArgs(args);
        try testing.expect(result.options.should_ignore_git_ignored);
    }
}

test "parseArgs max-depth" {
    const testing = std.testing;

    // Test --max-depth with value
    {
        const args = &[_][]const u8{ "tree", "--max-depth", "5" };
        const result = try parseArgs(args);
        try testing.expectEqual(@as(?usize, 5), result.options.max_depth);
    }

    // Test -L with value
    {
        const args = &[_][]const u8{ "tree", "-L", "3" };
        const result = try parseArgs(args);
        try testing.expectEqual(@as(?usize, 3), result.options.max_depth);
    }

    // Test --max-depth without value (trailing)
    {
        const args = &[_][]const u8{ "tree", "--max-depth" };
        const result = try parseArgs(args);
        try testing.expectEqual(@as(?usize, null), result.options.max_depth);
    }

    // Test -L without value (trailing)
    {
        const args = &[_][]const u8{ "tree", "-L" };
        const result = try parseArgs(args);
        try testing.expectEqual(@as(?usize, null), result.options.max_depth);
    }

    // Test --max-depth with non-integer value (should be treated as path)
    {
        const args = &[_][]const u8{ "tree", "--max-depth", "src" };
        const result = try parseArgs(args);
        try testing.expectEqual(@as(?usize, null), result.options.max_depth);
        try testing.expectEqualStrings("src", result.target_path);
    }

    // Default (null/unlimited)
    {
        const args = &[_][]const u8{"tree"};
        const result = try parseArgs(args);
        try testing.expect(result.options.max_depth == null);
    }
}

test "parseArgs defaults and paths" {
    const testing = std.testing;

    // No args
    {
        const args = &[_][]const u8{"tree"};
        const result = try parseArgs(args);
        try testing.expect(!result.options.show_hidden);
        try testing.expectEqualStrings(".", result.target_path);
    }

    // Multiple paths (last one wins)
    {
        const args = &[_][]const u8{ "tree", "dir1", "dir2" };
        const result = try parseArgs(args);
        try testing.expectEqualStrings("dir2", result.target_path);
    }

    // Unknown short flag (ignored)
    {
        const args = &[_][]const u8{ "tree", "-z" };
        const result = try parseArgs(args);
        try testing.expect(!result.options.show_hidden);
    }
}
