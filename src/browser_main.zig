const std = @import("std");
const chasen = @import("chasen_runtime");

const app_core = @import("app_core.zig");
const browser_render = @import("browser_render.zig");
const browser_surface = @import("browser_surface.zig");
const model = @import("model.zig");

const max_memory_bytes = 4 * 1024 * 1024;
const default_cell_count = app_core.App.default_width * app_core.App.default_height;

var memory: [max_memory_bytes]u8 = undefined;
var world_snapshot: [default_cell_count]model.Cell = undefined;
var allocator_state = std.heap.FixedBufferAllocator.init(&memory);
var app_state: app_core.App = app_core.App.create();
var surface_state: ?browser_surface.BrowserSurface = null;

pub export fn lifegame_init(surface_width: u32, surface_height: u32) u32 {
    cleanup();
    allocator_state = std.heap.FixedBufferAllocator.init(&memory);
    const allocator = allocator_state.allocator();

    const width: u16 = @intCast(@min(surface_width, std.math.maxInt(u16)));
    const height: u16 = @intCast(@min(surface_height, std.math.maxInt(u16)));
    if (width == 0 or height == 0) return 0;

    app_state = app_core.App.create();
    var ctx = makeCtx(allocator);
    app_state.init(&ctx) catch return 0;
    surface_state = browser_surface.BrowserSurface.init(allocator, width, height) catch return 0;

    render();
    return 1;
}

pub export fn lifegame_resize(surface_width: u32, surface_height: u32) u32 {
    const width: u16 = @intCast(@min(surface_width, std.math.maxInt(u16)));
    const height: u16 = @intCast(@min(surface_height, std.math.maxInt(u16)));
    if (width == 0 or height == 0) return 0;
    const current_world = app_state.world orelse return lifegame_init(width, height);

    // A resize changes the surface allocation size. Reset the fixed allocator
    // and rebuild owned objects so repeated browser resizes cannot fragment it.
    const cell_count = current_world.grid.cells.len;
    const generation = current_world.generation;
    const paused = app_state.paused;
    const random_seed = app_state.random_seed;
    const viewport_x = app_state.viewport_x;
    const viewport_y = app_state.viewport_y;
    const zoom = app_state.zoom;
    const speed_index = app_state.speed_index;
    @memcpy(world_snapshot[0..cell_count], current_world.grid.cells);

    cleanup();
    allocator_state = std.heap.FixedBufferAllocator.init(&memory);
    const allocator = allocator_state.allocator();

    app_state = .{
        .world = model.World.init(allocator, app_core.App.default_width, app_core.App.default_height) catch return 0,
        .paused = paused,
        .random_seed = random_seed,
        .viewport_x = viewport_x,
        .viewport_y = viewport_y,
        .zoom = zoom,
        .speed_index = speed_index,
    };
    @memcpy(app_state.world.?.grid.cells, world_snapshot[0..cell_count]);
    app_state.world.?.generation = generation;

    surface_state = browser_surface.BrowserSurface.init(allocator, width, height) catch return 0;
    render();
    return 1;
}

pub export fn lifegame_dispatch_key(key: u32) void {
    const msg = msgForKey(key) orelse return;
    dispatch(msg);
    render();
}

pub export fn lifegame_tick() void {
    if (!app_state.paused) {
        const ctx = dispatchWithCtx(.simulation_tick);
        if (!ctx.redrawWasSuppressed()) {
            render();
        }
    }
}

pub export fn lifegame_render() void {
    render();
}

pub export fn lifegame_surface_width() u32 {
    const surface = surface_state orelse return 0;
    return surface.width;
}

pub export fn lifegame_surface_height() u32 {
    const surface = surface_state orelse return 0;
    return surface.height;
}

pub export fn lifegame_cell_kind_at(index: u32) u32 {
    const surface = surface_state orelse return 0;
    if (index >= surface.cells.len) return 0;
    return switch (surface.cells[index].kind) {
        .blank => 0,
        .text => 1,
        .live => 2,
    };
}

pub export fn lifegame_cell_char_at(index: u32) u32 {
    const surface = surface_state orelse return ' ';
    if (index >= surface.cells.len) return ' ';
    return surface.cells[index].char;
}

pub export fn lifegame_is_paused() u32 {
    return if (app_state.paused) 1 else 0;
}

pub export fn lifegame_speed_ms() u32 {
    return @intCast(app_state.speedIntervalNs() / std.time.ns_per_ms);
}

fn msgForKey(key: u32) ?app_core.App.Msg {
    return switch (key) {
        ' ' => .toggle_pause,
        'n' => .step_once,
        'r' => .randomize,
        'c' => .clear,
        'h' => .pan_left,
        'l' => .pan_right,
        'k' => .pan_up,
        'j' => .pan_down,
        '+' => .zoom_in,
        '=' => .zoom_in,
        '-' => .zoom_out,
        ']' => .speed_up,
        '[' => .speed_down,
        'q' => .quit,
        else => null,
    };
}

fn dispatch(msg: app_core.App.Msg) void {
    const ctx = dispatchWithCtx(msg);
    if (ctx.shouldQuit()) {
        // Browser "quit" stops the simulation instead of terminating the tab.
        app_state.paused = true;
    }
}

fn dispatchWithCtx(msg: app_core.App.Msg) chasen.Ctx(app_core.App.Msg) {
    var ctx = makeCtx(allocator_state.allocator());
    app_state.update(msg, &ctx) catch {};
    return ctx;
}

fn render() void {
    const surface = if (surface_state) |*value| value else return;
    browser_render.view(surface, .{
        .world = app_state.world,
        .paused = app_state.paused,
        .viewport_x = app_state.viewport_x,
        .viewport_y = app_state.viewport_y,
        .zoom = app_state.zoom,
        .speed_index = app_state.speed_index,
        .speed_interval_ns = app_state.speedIntervalNs(),
    });
}

fn makeCtx(allocator: std.mem.Allocator) chasen.Ctx(app_core.App.Msg) {
    return .{ ._allocator = allocator };
}

fn cleanup() void {
    if (surface_state) |*surface| {
        surface.deinit(allocator_state.allocator());
        surface_state = null;
    }
    app_state.deinit(.{ .allocator = allocator_state.allocator(), .io = undefined });
}
