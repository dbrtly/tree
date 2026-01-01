//! Root library file exporting the public API.

/// Argument parsing module.
pub const args = @import("args.zig");
/// File system operations module.
pub const files = @import("fs.zig");
/// Git integration module.
pub const git = @import("git.zig");
/// Tree printing module.
pub const print = @import("print.zig");
/// Common types module.
pub const types = @import("types.zig");

/// Tree options struct.
pub const TreeOptions = types.TreeOptions;
/// File entry struct.
pub const FileEntry = types.FileEntry;
/// Parse result struct.
pub const ParseResult = args.ParseResult;
/// Argument parsing function.
pub const parseArgs = args.parseArgs;
/// Git ignore checking function.
pub const checkGitIgnoreBatch = git.checkGitIgnoreBatch;
/// File entry comparison function.
pub const compareFileEntries = files.compareFileEntries;
/// Function to get sorted entries.
pub const getSortedEntries = files.getSortedEntries;
/// Function to print the tree.
pub const printTree = print.printTree;

test {
    _ = types;
    _ = args;
    _ = git;
    _ = files;
    _ = print;
}
