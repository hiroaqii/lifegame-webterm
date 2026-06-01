const std = @import("std");

pub const app = @import("app.zig");
pub const input = @import("input.zig");
pub const model = @import("model.zig");
pub const render = @import("render.zig");

pub const App = app.App;
pub const Cell = model.Cell;
pub const Grid = model.Grid;
pub const World = model.World;

test {
    std.testing.refAllDecls(app);
    std.testing.refAllDecls(input);
    std.testing.refAllDecls(model);
    std.testing.refAllDecls(render);
}
