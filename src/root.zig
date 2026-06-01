const std = @import("std");

pub const model = @import("model.zig");

pub const Cell = model.Cell;
pub const Grid = model.Grid;
pub const World = model.World;

test {
    std.testing.refAllDecls(model);
}
