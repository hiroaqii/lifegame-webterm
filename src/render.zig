const std = @import("std");
const chasen = @import("chasen");

const model = @import("model.zig");

pub const ViewState = struct {
    world: ?model.World,
    paused: bool,
    viewport_x: usize,
    viewport_y: usize,
    zoom: u8,
    speed_index: usize,
    speed_interval_ns: u64,
};

pub fn view(surface: *chasen.Surface, state: ViewState) !void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    surface.hideCursor();
    surface.clear(.{
        .col = 0,
        .row = 0,
        .width = size.width,
        .height = size.height,
    });

    _ = try surface.copyTextAt(0, 0, "Lifegame Webterm", .{ .bold = true });

    if (state.world) |world| {
        const mode = if (state.paused) "paused" else "running";
        _ = try surface.printAt(0, 1, .{ .fg = .gray }, "{s}  gen:{d}  pop:{d}  view:{d},{d}  z:{d}  speed:{d}ms L{d}", .{
            mode,
            world.generation,
            world.population(),
            state.viewport_x,
            state.viewport_y,
            state.zoom,
            state.speed_interval_ns / std.time.ns_per_ms,
            state.speed_index + 1,
        });

        const grid_rect = gridRect(size) orelse return;
        drawGrid(surface, grid_rect, world.grid, .{
            .x = state.viewport_x,
            .y = state.viewport_y,
            .zoom = state.zoom,
        }) catch return error.OutOfMemory;
    } else {
        _ = try surface.copyTextAt(0, 3, "model is not initialized", .{ .fg = .{ .index = 9 } });
    }

    const footer_row = size.height - 1;
    _ = try surface.copyTextAt(0, footer_row, "space: run/pause  n: step  r: randomize  c: clear  h/j/k/l: pan  +/-: zoom  [/]: speed  q: quit", .{ .fg = .gray });
}

const Viewport = struct {
    x: usize,
    y: usize,
    zoom: u8,
};

fn gridRect(size: chasen.Size) ?chasen.Rect {
    if (size.height <= 3 or size.width == 0) return null;
    return .{
        .col = 0,
        .row = 2,
        .width = size.width,
        .height = size.height - 3,
    };
}

fn drawGrid(surface: *chasen.Surface, rect: chasen.Rect, grid: model.Grid, viewport: Viewport) !void {
    const zoom: u16 = @max(viewport.zoom, 1);
    const cell_width = zoom * 2;
    const cell_height = zoom;
    if (cell_width == 0 or cell_height == 0) return;

    const visible_cols = rect.width / cell_width;
    const visible_rows = rect.height / cell_height;

    var row: u16 = 0;
    while (row < visible_rows) : (row += 1) {
        const grid_y = viewport.y + row;
        if (grid_y >= grid.height) break;

        var col: u16 = 0;
        while (col < visible_cols) : (col += 1) {
            const grid_x = viewport.x + col;
            if (grid_x >= grid.width) break;
            if (grid.get(grid_x, grid_y) == .alive) {
                try drawLiveCell(surface, rect, col, row, cell_width, cell_height);
            }
        }
    }
}

fn drawLiveCell(surface: *chasen.Surface, rect: chasen.Rect, cell_col: u16, cell_row: u16, cell_width: u16, cell_height: u16) !void {
    const start_col = rect.col + cell_col * cell_width;
    const start_row = rect.row + cell_row * cell_height;

    var y: u16 = 0;
    while (y < cell_height) : (y += 1) {
        var x: u16 = 0;
        while (x < cell_width) : (x += 1) {
            _ = try surface.copyTextAt(start_col + x, start_row + y, "#", .{ .fg = .{ .index = 10 } });
        }
    }
}

test "renders status summary" {
    var world = try model.World.init(std.testing.allocator, 5, 5);
    defer world.deinit(std.testing.allocator);
    world.grid.set(2, 2, .alive);

    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(80, 10);
    defer ts.deinit();

    try view(&ts.surface, .{
        .world = world,
        .paused = true,
        .viewport_x = 0,
        .viewport_y = 0,
        .zoom = 1,
        .speed_index = 1,
        .speed_interval_ns = 250 * std.time.ns_per_ms,
    });

    try ts.expectCellText(0, 0, "L");
    try ts.expectCellText(0, 1, "p");
    try ts.expectCellText(0, 9, "s");
}

test "renders visible live cells in viewport" {
    var world = try model.World.init(std.testing.allocator, 6, 6);
    defer world.deinit(std.testing.allocator);
    world.grid.set(2, 3, .alive);

    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(20, 8);
    defer ts.deinit();

    try view(&ts.surface, .{
        .world = world,
        .paused = true,
        .viewport_x = 1,
        .viewport_y = 2,
        .zoom = 1,
        .speed_index = 1,
        .speed_interval_ns = 250 * std.time.ns_per_ms,
    });

    try ts.expectCellText(2, 3, "#");
    try ts.expectCellText(3, 3, "#");
}
