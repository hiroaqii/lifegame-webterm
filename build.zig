const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const chasen_dep = b.dependency("chasen", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("lifegame_webterm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "chasen", .module = chasen_dep.module("chasen") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "lifegame-webterm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lifegame_webterm", .module = mod },
                .{ .name = "chasen", .module = chasen_dep.module("chasen") },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Lifegame Webterm");
    run_step.dependOn(&run_cmd.step);

    const bench_model_exe = b.addExecutable(.{
        .name = "lifegame-webterm-bench-model",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench_model.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const bench_model_cmd = b.addRunArtifact(bench_model_exe);
    const bench_model_step = b.step("bench-model", "Benchmark the backend-neutral Life model");
    bench_model_step.dependOn(&bench_model_cmd.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const browser_mod = b.createModule(.{
        .root_source_file = b.path("src/browser_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const browser_tests = b.addTest(.{
        .root_module = browser_mod,
    });
    const run_browser_tests = b.addRunArtifact(browser_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_browser_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const browser_wasm = b.addObject(.{
        .name = "lifegame-webterm-browser",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/browser_check.zig"),
            .target = wasm_target,
            .optimize = optimize,
        }),
    });

    const check_browser_step = b.step("check-browser", "Compile the browser-only module for wasm32-freestanding");
    check_browser_step.dependOn(&browser_wasm.step);

    const browser_app = b.addExecutable(.{
        .name = "lifegame-webterm-browser",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/browser_main.zig"),
            .target = wasm_target,
            .optimize = optimize,
        }),
    });
    browser_app.entry = .disabled;
    browser_app.rdynamic = true;

    const install_browser_wasm = b.addInstallFile(browser_app.getEmittedBin(), "web/lifegame-webterm-browser.wasm");
    const install_browser_assets = b.addInstallDirectory(.{
        .source_dir = b.path("web"),
        .install_dir = .prefix,
        .install_subdir = "web",
    });

    const web_step = b.step("web", "Build the browser prototype");
    web_step.dependOn(&install_browser_wasm.step);
    web_step.dependOn(&install_browser_assets.step);
}
