const std = @import("std");
const chasen = @import("chasen");

const model = @import("model.zig");

pub const ViewState = struct {
    world: ?model.World,
    paused: bool,
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
    _ = try surface.copyTextAt(0, 1, "Conway's Game of Life for terminal and browser backends.", .{ .fg = .gray });

    if (state.world) |world| {
        const mode = if (state.paused) "paused" else "running";
        _ = try surface.printAt(0, 3, .{}, "mode: {s}", .{mode});
        _ = try surface.printAt(0, 4, .{}, "generation: {d}", .{world.generation});
        _ = try surface.printAt(0, 5, .{}, "population: {d}", .{world.population()});
        _ = try surface.printAt(0, 6, .{}, "grid: {d}x{d}", .{ world.grid.width, world.grid.height });
    } else {
        _ = try surface.copyTextAt(0, 3, "model is not initialized", .{ .fg = .{ .index = 9 } });
    }

    const footer_row = size.height - 1;
    _ = try surface.copyTextAt(0, footer_row, "space: pause  n: step  r: randomize  c: clear  q: quit", .{ .fg = .gray });
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
    });

    try ts.expectCellText(0, 0, "L");
    try ts.expectCellText(0, 3, "m");
    try ts.expectCellText(0, 5, "p");
    try ts.expectCellText(0, 9, "s");
}
