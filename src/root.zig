const std = @import("std");

pub const app = @import("app.zig");
pub const app_core = @import("app_core.zig");
pub const browser_render = @import("browser_render.zig");
pub const browser_surface = @import("browser_surface.zig");
pub const input = @import("input.zig");
pub const model = @import("model.zig");
pub const render = @import("render.zig");

pub const App = app.App;
pub const BrowserSurface = browser_surface.BrowserSurface;
pub const Cell = model.Cell;
pub const Grid = model.Grid;
pub const World = model.World;

test {
    std.testing.refAllDecls(app);
    std.testing.refAllDecls(app_core);
    std.testing.refAllDecls(browser_render);
    std.testing.refAllDecls(browser_surface);
    std.testing.refAllDecls(input);
    std.testing.refAllDecls(model);
    std.testing.refAllDecls(render);
}
