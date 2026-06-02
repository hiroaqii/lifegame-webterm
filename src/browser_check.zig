const std = @import("std");

const browser_render = @import("browser_render.zig");
const browser_surface = @import("browser_surface.zig");
const model = @import("model.zig");

// Keep the wasm check root stricter than a plain re-export root. Zig analyzes
// function bodies lazily, so the exported function below calls the browser code
// that we want `zig build check-browser` to compile for wasm32-freestanding.
comptime {
    refAllDecls(browser_render);
    refAllDecls(browser_surface);
    refAllDecls(model);

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

    var world = model.World.init(allocator, 8, 8) catch unreachable;
    defer world.deinit(allocator);
    world.grid.set(3, 4, .alive);
    world.step(allocator) catch unreachable;

    var surface = browser_surface.BrowserSurface.init(allocator, 24, 12) catch unreachable;
    defer surface.deinit(allocator);

    browser_render.view(&surface, .{
        .world = world,
        .paused = false,
        .viewport_x = 0,
        .viewport_y = 0,
        .zoom = 1,
        .speed_index = 1,
        .speed_interval_ns = 250 * std.time.ns_per_ms,
    });
}
