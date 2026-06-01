const std = @import("std");

pub const Error = error{
    InvalidGridSize,
    GridTooLarge,
};

pub const Cell = enum {
    dead,
    alive,

    pub fn isAlive(self: Cell) bool {
        return self == .alive;
    }
};

pub const Grid = struct {
    width: usize,
    height: usize,
    cells: []Cell,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Grid {
        if (width == 0 or height == 0) return Error.InvalidGridSize;

        const cell_count = std.math.mul(usize, width, height) catch return Error.GridTooLarge;
        const cells = try allocator.alloc(Cell, cell_count);
        @memset(cells, .dead);

        return .{
            .width = width,
            .height = height,
            .cells = cells,
        };
    }

    pub fn deinit(self: *Grid, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        self.* = undefined;
    }

    pub fn clear(self: *Grid) void {
        @memset(self.cells, .dead);
    }

    pub fn get(self: Grid, x: usize, y: usize) Cell {
        std.debug.assert(x < self.width);
        std.debug.assert(y < self.height);
        return self.cells[self.index(x, y)];
    }

    pub fn set(self: *Grid, x: usize, y: usize, cell: Cell) void {
        std.debug.assert(x < self.width);
        std.debug.assert(y < self.height);
        self.cells[self.index(x, y)] = cell;
    }

    pub fn population(self: Grid) usize {
        var count: usize = 0;
        for (self.cells) |cell| {
            if (cell.isAlive()) count += 1;
        }
        return count;
    }

    fn liveNeighborCount(self: Grid, x: usize, y: usize) u4 {
        var count: u4 = 0;
        const center_x: isize = @intCast(x);
        const center_y: isize = @intCast(y);

        for (neighbor_offsets) |offset| {
            if (self.getOrDead(center_x + offset.x, center_y + offset.y).isAlive()) {
                count += 1;
            }
        }

        return count;
    }

    fn getOrDead(self: Grid, x: isize, y: isize) Cell {
        if (x < 0 or y < 0) return .dead;

        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= self.width or uy >= self.height) return .dead;

        return self.get(ux, uy);
    }

    fn index(self: Grid, x: usize, y: usize) usize {
        return y * self.width + x;
    }
};

pub const World = struct {
    grid: Grid,
    generation: u64,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !World {
        return .{
            .grid = try Grid.init(allocator, width, height),
            .generation = 0,
        };
    }

    pub fn deinit(self: *World, allocator: std.mem.Allocator) void {
        self.grid.deinit(allocator);
        self.* = undefined;
    }

    pub fn clear(self: *World) void {
        self.grid.clear();
        self.generation = 0;
    }

    pub fn population(self: World) usize {
        return self.grid.population();
    }

    pub fn step(self: *World, allocator: std.mem.Allocator) !void {
        const next = try allocator.alloc(Cell, self.grid.cells.len);
        defer allocator.free(next);

        for (0..self.grid.height) |y| {
            for (0..self.grid.width) |x| {
                const current = self.grid.get(x, y);
                const neighbors = self.grid.liveNeighborCount(x, y);
                next[self.grid.index(x, y)] = nextCell(current, neighbors);
            }
        }

        @memcpy(self.grid.cells, next);
        self.generation += 1;
    }
};

fn nextCell(current: Cell, live_neighbors: u4) Cell {
    return switch (current) {
        .alive => if (live_neighbors == 2 or live_neighbors == 3) .alive else .dead,
        .dead => if (live_neighbors == 3) .alive else .dead,
    };
}

const NeighborOffset = struct {
    x: isize,
    y: isize,
};

const neighbor_offsets = [_]NeighborOffset{
    .{ .x = -1, .y = -1 },
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = -1 },
    .{ .x = -1, .y = 0 },
    .{ .x = 1, .y = 0 },
    .{ .x = -1, .y = 1 },
    .{ .x = 0, .y = 1 },
    .{ .x = 1, .y = 1 },
};

test "Grid rejects zero-sized dimensions" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(Error.InvalidGridSize, Grid.init(allocator, 0, 1));
    try std.testing.expectError(Error.InvalidGridSize, Grid.init(allocator, 1, 0));
}

test "Grid stores cells and counts population" {
    const allocator = std.testing.allocator;
    var grid = try Grid.init(allocator, 3, 2);
    defer grid.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), grid.population());

    grid.set(0, 0, .alive);
    grid.set(2, 1, .alive);

    try std.testing.expectEqual(Cell.alive, grid.get(0, 0));
    try std.testing.expectEqual(Cell.dead, grid.get(1, 1));
    try std.testing.expectEqual(@as(usize, 2), grid.population());

    grid.clear();
    try std.testing.expectEqual(@as(usize, 0), grid.population());
}

test "World clear resets cells and generation" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator, 3, 3);
    defer world.deinit(allocator);

    world.grid.set(1, 1, .alive);
    try world.step(allocator);

    try std.testing.expectEqual(@as(u64, 1), world.generation);

    world.clear();
    try std.testing.expectEqual(@as(u64, 0), world.generation);
    try std.testing.expectEqual(@as(usize, 0), world.population());
}

test "underpopulation kills a live cell" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator, 3, 3);
    defer world.deinit(allocator);

    world.grid.set(1, 1, .alive);

    try world.step(allocator);

    try std.testing.expectEqual(Cell.dead, world.grid.get(1, 1));
}

test "survival keeps a live cell with two or three neighbors" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator, 3, 3);
    defer world.deinit(allocator);

    world.grid.set(1, 1, .alive);
    world.grid.set(0, 1, .alive);
    world.grid.set(2, 1, .alive);

    try world.step(allocator);

    try std.testing.expectEqual(Cell.alive, world.grid.get(1, 1));
}

test "overpopulation kills a live cell" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator, 3, 3);
    defer world.deinit(allocator);

    world.grid.set(1, 1, .alive);
    world.grid.set(0, 0, .alive);
    world.grid.set(0, 1, .alive);
    world.grid.set(0, 2, .alive);
    world.grid.set(1, 0, .alive);

    try world.step(allocator);

    try std.testing.expectEqual(Cell.dead, world.grid.get(1, 1));
}

test "reproduction creates a live cell with three neighbors" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator, 3, 3);
    defer world.deinit(allocator);

    world.grid.set(0, 1, .alive);
    world.grid.set(1, 0, .alive);
    world.grid.set(2, 1, .alive);

    try world.step(allocator);

    try std.testing.expectEqual(Cell.alive, world.grid.get(1, 1));
}

test "bounded grid treats out-of-bounds neighbors as dead" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator, 3, 3);
    defer world.deinit(allocator);

    world.grid.set(0, 0, .alive);
    world.grid.set(1, 0, .alive);
    world.grid.set(0, 1, .alive);

    try world.step(allocator);

    try std.testing.expectEqual(Cell.alive, world.grid.get(0, 0));
    try std.testing.expectEqual(Cell.alive, world.grid.get(1, 1));
    try std.testing.expectEqual(@as(usize, 4), world.population());
}

test "blinker oscillator advances generations" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator, 5, 5);
    defer world.deinit(allocator);

    world.grid.set(2, 1, .alive);
    world.grid.set(2, 2, .alive);
    world.grid.set(2, 3, .alive);

    try world.step(allocator);

    try std.testing.expectEqual(@as(u64, 1), world.generation);
    try std.testing.expectEqual(Cell.alive, world.grid.get(1, 2));
    try std.testing.expectEqual(Cell.alive, world.grid.get(2, 2));
    try std.testing.expectEqual(Cell.alive, world.grid.get(3, 2));
    try std.testing.expectEqual(@as(usize, 3), world.population());

    try world.step(allocator);

    try std.testing.expectEqual(@as(u64, 2), world.generation);
    try std.testing.expectEqual(Cell.alive, world.grid.get(2, 1));
    try std.testing.expectEqual(Cell.alive, world.grid.get(2, 2));
    try std.testing.expectEqual(Cell.alive, world.grid.get(2, 3));
    try std.testing.expectEqual(@as(usize, 3), world.population());
}
