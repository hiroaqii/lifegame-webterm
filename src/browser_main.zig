const std = @import("std");

const browser_render = @import("browser_render.zig");
const browser_surface = @import("browser_surface.zig");
const model = @import("model.zig");

const default_grid_width: usize = 80;
const default_grid_height: usize = 40;
const max_memory_bytes = 4 * 1024 * 1024;
const speed_intervals_ms = [_]u32{ 500, 250, 125, 62 };
const default_cell_count = default_grid_width * default_grid_height;

var memory: [max_memory_bytes]u8 = undefined;
var world_snapshot: [default_cell_count]model.Cell = undefined;
var allocator_state = std.heap.FixedBufferAllocator.init(&memory);
var world_state: ?model.World = null;
var surface_state: ?browser_surface.BrowserSurface = null;
var paused_state: bool = true;
var viewport_x: usize = 0;
var viewport_y: usize = 0;
var zoom_state: u8 = 1;
var speed_index: usize = 1;
var random_seed: u64 = 0x6c_69_66_65_67_61_6d_65;

pub export fn lifegame_init(surface_width: u32, surface_height: u32) u32 {
    cleanup();
    allocator_state = std.heap.FixedBufferAllocator.init(&memory);
    const allocator = allocator_state.allocator();

    const width: u16 = @intCast(@min(surface_width, std.math.maxInt(u16)));
    const height: u16 = @intCast(@min(surface_height, std.math.maxInt(u16)));
    if (width == 0 or height == 0) return 0;

    world_state = model.World.init(allocator, default_grid_width, default_grid_height) catch return 0;
    surface_state = browser_surface.BrowserSurface.init(allocator, width, height) catch return 0;
    seedInitialPattern(&world_state.?.grid);

    paused_state = true;
    viewport_x = 0;
    viewport_y = 0;
    zoom_state = 1;
    speed_index = 1;
    render();
    return 1;
}

pub export fn lifegame_resize(surface_width: u32, surface_height: u32) u32 {
    const width: u16 = @intCast(@min(surface_width, std.math.maxInt(u16)));
    const height: u16 = @intCast(@min(surface_height, std.math.maxInt(u16)));
    if (width == 0 or height == 0) return 0;
    const current_world = world_state orelse return lifegame_init(width, height);

    // A resize changes the surface allocation size. Reset the fixed allocator
    // and rebuild both objects so repeated browser resizes cannot fragment it.
    const cell_count = current_world.grid.cells.len;
    const generation = current_world.generation;
    @memcpy(world_snapshot[0..cell_count], current_world.grid.cells);

    cleanup();
    allocator_state = std.heap.FixedBufferAllocator.init(&memory);
    const allocator = allocator_state.allocator();

    world_state = model.World.init(allocator, default_grid_width, default_grid_height) catch return 0;
    @memcpy(world_state.?.grid.cells, world_snapshot[0..cell_count]);
    world_state.?.generation = generation;

    surface_state = browser_surface.BrowserSurface.init(allocator, width, height) catch return 0;
    render();
    return 1;
}

pub export fn lifegame_dispatch_key(key: u32) void {
    switch (key) {
        ' ' => paused_state = !paused_state,
        'n' => stepOnce(),
        'r' => randomize(),
        'c' => clear(),
        'h' => pan(-1, 0),
        'l' => pan(1, 0),
        'k' => pan(0, -1),
        'j' => pan(0, 1),
        '+' => zoom_state = @min(zoom_state + 1, 4),
        '=' => zoom_state = @min(zoom_state + 1, 4),
        '-' => zoom_state = @max(zoom_state -| 1, 1),
        ']' => speed_index = @min(speed_index + 1, speed_intervals_ms.len - 1),
        '[' => speed_index = speed_index -| 1,
        'q' => paused_state = true,
        else => {},
    }
    render();
}

pub export fn lifegame_tick() void {
    if (!paused_state) {
        stepOnce();
        render();
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
    return if (paused_state) 1 else 0;
}

pub export fn lifegame_speed_ms() u32 {
    return speed_intervals_ms[speed_index];
}

fn render() void {
    const surface = if (surface_state) |*value| value else return;
    const world = world_state;
    browser_render.view(surface, .{
        .world = world,
        .paused = paused_state,
        .viewport_x = viewport_x,
        .viewport_y = viewport_y,
        .zoom = zoom_state,
        .speed_index = speed_index,
        .speed_interval_ns = @as(u64, speed_intervals_ms[speed_index]) * std.time.ns_per_ms,
    });
}

fn stepOnce() void {
    if (world_state) |*world| {
        world.step(allocator_state.allocator()) catch {};
    }
}

fn randomize() void {
    var world = if (world_state) |*value| value else return;
    var prng = std.Random.DefaultPrng.init(random_seed);
    const random = prng.random();
    for (world.grid.cells) |*cell| {
        cell.* = if (random.uintLessThan(u8, 100) < 28) .alive else .dead;
    }
    world.generation = 0;
    random_seed +%= 0x9e37_79b9_7f4a_7c15;
}

fn clear() void {
    if (world_state) |*world| {
        world.clear();
    }
    paused_state = true;
    viewport_x = 0;
    viewport_y = 0;
}

fn pan(dx: i2, dy: i2) void {
    const world = world_state orelse return;
    viewport_x = panAxis(viewport_x, world.grid.width, dx);
    viewport_y = panAxis(viewport_y, world.grid.height, dy);
}

fn panAxis(current: usize, limit: usize, delta: i2) usize {
    return switch (delta) {
        -1 => current -| 1,
        0 => current,
        1 => if (limit == 0) current else @min(current + 1, limit - 1),
        else => unreachable,
    };
}

fn seedInitialPattern(grid: *model.Grid) void {
    if (grid.height < 3) {
        grid.set(0, 0, .alive);
        return;
    }

    const x: usize = @min(grid.width - 1, @as(usize, 4));
    const y: usize = @min(grid.height - 2, @as(usize, 3));
    grid.set(x, y - 1, .alive);
    grid.set(x, y, .alive);
    grid.set(x, y + 1, .alive);
}

fn cleanup() void {
    if (surface_state) |*surface| {
        surface.deinit(allocator_state.allocator());
        surface_state = null;
    }
    if (world_state) |*world| {
        world.deinit(allocator_state.allocator());
        world_state = null;
    }
}
