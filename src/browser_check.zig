const std = @import("std");
const chasen = @import("chasen_runtime");

const app_core = @import("app_core.zig");
const browser_render = @import("browser_render.zig");
const browser_surface = @import("browser_surface.zig");
const model = @import("model.zig");

// Keep the wasm check root stricter than a plain re-export root. Zig analyzes
// function bodies lazily, so the exported function below calls the browser code
// that we want `zig build check-browser` to compile for wasm32-freestanding.
comptime {
    refAllDecls(app_core);
    refAllDecls(browser_render);
    refAllDecls(browser_surface);
    refAllDecls(model);

    _ = app_core.App.init;
    _ = app_core.App.update;
    _ = app_core.App.deinit;
    _ = browser_render.view;
    _ = browser_surface.BrowserSurface.init;
    _ = browser_surface.BrowserSurface.deinit;
    _ = browser_surface.BrowserSurface.clear;
    _ = browser_surface.BrowserSurface.putTextAt;
    _ = browser_surface.BrowserSurface.fill;
    _ = browser_surface.BrowserSurface.readCell;
    _ = model.World.init;
    _ = model.World.step;
}

fn refAllDecls(comptime namespace: type) void {
    for (@typeInfo(namespace).@"struct".decls) |decl| {
        _ = @field(namespace, decl.name);
    }
}

// This is intentionally not used by JS yet. It exists to make the browser
// surface, renderer, and shared model compile as real wasm code before the
// browser shell/glue is introduced.
pub export fn lifegame_browser_compile_check() void {
    var buffer: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var app = app_core.App.create();
    var ctx: chasen.Ctx(app_core.App.Msg) = .{ ._allocator = allocator };
    app.init(&ctx) catch unreachable;
    defer app.deinit(.{ .allocator = allocator, .io = undefined });
    app.update(.step_once, &ctx) catch unreachable;

    var surface = browser_surface.BrowserSurface.init(allocator, 24, 12) catch unreachable;
    defer surface.deinit(allocator);

    browser_render.view(&surface, .{
        .world = app.world,
        .paused = false,
        .viewport_x = app.viewport_x,
        .viewport_y = app.viewport_y,
        .zoom = app.zoom,
        .speed_index = app.speed_index,
        .speed_interval_ns = app.speedIntervalNs(),
    });
}
