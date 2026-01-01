const std = @import("std");

/// Main function to inspect build options.
pub fn main() anyerror!void {
    // Check std.Build.ExecutableOptions
    if (@hasDecl(std.Build, "ExecutableOptions")) {
        const ExecutableOptions = std.Build.ExecutableOptions;
        std.debug.print("ExecutableOptions fields:\n", .{});
        inline for (@typeInfo(ExecutableOptions).Struct.fields) |field| {
            std.debug.print("  {s}\n", .{field.name});
        }
    } else {
        std.debug.print("std.Build.ExecutableOptions not found\n", .{});
    }

    // Check std.Build.CreateModuleOptions or similar
    if (@hasDecl(std.Build, "CreateModuleOptions")) {
        const CreateModuleOptions = std.Build.CreateModuleOptions;
        std.debug.print("\nCreateModuleOptions fields:\n", .{});
        inline for (@typeInfo(CreateModuleOptions).Struct.fields) |field| {
            std.debug.print("  {s}\n", .{field.name});
        }
    } else if (@hasDecl(std.Build, "Module")) {
        if (@hasDecl(std.Build.Module, "CreateOptions")) {
            const CreateOptions = std.Build.Module.CreateOptions;
            std.debug.print("\nstd.Build.Module.CreateOptions fields:\n", .{});
            inline for (@typeInfo(CreateOptions).Struct.fields) |field| {
                std.debug.print("  {s}\n", .{field.name});
            }
        } else {
            std.debug.print("std.Build.Module.CreateOptions not found\n", .{});
        }
    } else {
        std.debug.print("std.Build.CreateModuleOptions not found\n", .{});
    }
}
