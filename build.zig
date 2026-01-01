const std = @import("std");
const zlinter = @import("zlinter");

/// Build function for the tree project.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("tree_lib", lib_mod);

    const exe = b.addExecutable(.{
        .name = "tree",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_artifact_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_artifact_tests.step);

    // Coverage run
    const cov_step = b.step("cov", "Generate code coverage report");
    const run_cov = b.addSystemCommand(&.{
        "kcov",
        "--clean",
        "--include-pattern=src/",
        b.pathJoin(&.{ b.install_path, "coverage" }),
    });
    run_cov.addArtifactArg(unit_tests);
    cov_step.dependOn(&run_cov.step);

    const lint_step = b.step("lint", "Lint source code");
    lint_step.dependOn(step: {
        var builder = zlinter.builder(b, .{});
        inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |f| {
            const rule = @as(zlinter.BuiltinLintRule, @enumFromInt(f.value));
            if (rule == .no_deprecated) continue;
            builder.addRule(.{ .builtin = rule }, .{});
        }
        break :step builder.build();
    });

    const fmt_step = b.step("fmt", "Run zig fmt");
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "build.zig", "build.zig.zon", "inspect_build.zig" },
    });
    fmt_step.dependOn(&fmt.step);

    const style_step = b.step("style", "Check for style compliance (lint and fmt)");
    style_step.dependOn(lint_step);
    style_step.dependOn(fmt_step);

    const ci_tests = b.addRunArtifact(unit_tests);
    ci_tests.step.dependOn(style_step);

    // Force coverage to run AFTER standalone tests pass
    run_cov.step.dependOn(&ci_tests.step);

    const ci_step = b.step("ci", "Continuous integration (lint, fmt, test, then coverage)");
    ci_step.dependOn(cov_step);
}
