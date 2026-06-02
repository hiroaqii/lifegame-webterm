const std = @import("std");

pub const browser_render = @import("browser_render.zig");
pub const browser_surface = @import("browser_surface.zig");
pub const model = @import("model.zig");

pub const BrowserSurface = browser_surface.BrowserSurface;
pub const BrowserViewState = browser_render.BrowserViewState;
pub const Cell = model.Cell;
pub const Grid = model.Grid;
pub const World = model.World;

test {
    std.testing.refAllDecls(browser_render);
    std.testing.refAllDecls(browser_surface);
    std.testing.refAllDecls(model);
}
