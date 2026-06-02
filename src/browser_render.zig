const std = @import("std");

const model = @import("model.zig");
const browser_surface = @import("browser_surface.zig");

pub const BrowserViewState = struct {
    world: ?model.World,
    paused: bool,
    viewport_x: usize,
    viewport_y: usize,
    zoom: u8,
    speed_index: usize,
    speed_interval_ns: u64,
};

// Browser renderer for the app-specific prototype. It mirrors the terminal
// renderer's intent, but writes into a logical frame buffer instead of Chasen.
pub fn view(surface: *browser_surface.BrowserSurface, state: BrowserViewState) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    surface.clear();
    surface.putTextAt(0, 0, "Lifegame Webterm");

    if (state.world) |world| {
        writeStatus(surface, state, world);
        const rect = gridRect(size) orelse return;
        drawGrid(surface, rect, world.grid, .{
            .x = state.viewport_x,
            .y = state.viewport_y,
            .zoom = state.zoom,
        });
    } else {
        surface.putTextAt(0, 3, "model is not initialized");
    }

    surface.putTextAt(0, size.height - 1, "space run/pause  n step  r randomize  c clear");
}

fn writeStatus(surface: *browser_surface.BrowserSurface, state: BrowserViewState, world: model.World) void {
    var buf: [128]u8 = undefined;
    const mode = if (state.paused) "paused" else "running";
    const text = std.fmt.bufPrint(&buf, "{s} gen:{d} pop:{d} view:{d},{d} z:{d} speed:{d}ms L{d}", .{
        mode,
        world.generation,
        world.population(),
        state.viewport_x,
        state.viewport_y,
        state.zoom,
        state.speed_interval_ns / std.time.ns_per_ms,
        state.speed_index + 1,
    }) catch return;
    surface.putTextAt(0, 1, text);
}

const Viewport = struct {
    x: usize,
    y: usize,
    zoom: u8,
};

fn gridRect(size: browser_surface.Size) ?browser_surface.Rect {
    if (size.height <= 3 or size.width == 0) return null;
    return .{
        .col = 0,
        .row = 2,
        .width = size.width,
        .height = size.height - 3,
    };
}

fn drawGrid(surface: *browser_surface.BrowserSurface, rect: browser_surface.Rect, grid: model.Grid, viewport: Viewport) void {
    const zoom: u16 = @max(viewport.zoom, 1);
    // Browser logical cells are square; terminal rendering uses a wider cell
    // to compensate for character-cell aspect ratio.
    const cell_width = zoom;
    const cell_height = zoom;

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
                drawLiveCell(surface, rect, col, row, cell_width, cell_height);
            }
        }
    }
}

fn drawLiveCell(surface: *browser_surface.BrowserSurface, rect: browser_surface.Rect, cell_col: u16, cell_row: u16, cell_width: u16, cell_height: u16) void {
    surface.fill(.{
        .col = rect.col + cell_col * cell_width,
        .row = rect.row + cell_row * cell_height,
        .width = cell_width,
        .height = cell_height,
    }, .{ .kind = .live, .char = '#' });
}

test "browser renderer draws visible live cells" {
    var world = try model.World.init(std.testing.allocator, 8, 8);
    defer world.deinit(std.testing.allocator);
    world.grid.set(3, 4, .alive);

    var surface = try browser_surface.BrowserSurface.init(std.testing.allocator, 20, 10);
    defer surface.deinit(std.testing.allocator);

    view(&surface, .{
        .world = world,
        .paused = true,
        .viewport_x = 2,
        .viewport_y = 3,
        .zoom = 1,
        .speed_index = 1,
        .speed_interval_ns = 250 * std.time.ns_per_ms,
    });

    try std.testing.expectEqual(browser_surface.CellKind.live, surface.readCell(1, 3).?.kind);
    try std.testing.expectEqual(@as(u8, '#'), surface.cellChar(1, 3));
}

test "browser renderer uses square logical zoom cells" {
    var world = try model.World.init(std.testing.allocator, 4, 4);
    defer world.deinit(std.testing.allocator);
    world.grid.set(1, 1, .alive);

    var surface = try browser_surface.BrowserSurface.init(std.testing.allocator, 12, 8);
    defer surface.deinit(std.testing.allocator);

    view(&surface, .{
        .world = world,
        .paused = true,
        .viewport_x = 0,
        .viewport_y = 0,
        .zoom = 2,
        .speed_index = 1,
        .speed_interval_ns = 250 * std.time.ns_per_ms,
    });

    try std.testing.expectEqual(browser_surface.CellKind.live, surface.readCell(2, 4).?.kind);
    try std.testing.expectEqual(browser_surface.CellKind.live, surface.readCell(3, 5).?.kind);
}
