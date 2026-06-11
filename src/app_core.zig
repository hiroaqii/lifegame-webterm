const std = @import("std");
const chasen = @import("chasen_runtime");

const model = @import("model.zig");

pub const App = struct {
    pub const default_width: usize = 80;
    pub const default_height: usize = 40;
    pub const simulation_timer_id = "lifegame.simulation";
    pub const initial_seed: u64 = 0x6c_69_66_65_67_61_6d_65;
    pub const speed_intervals_ns = [_]u64{
        500 * std.time.ns_per_ms,
        250 * std.time.ns_per_ms,
        125 * std.time.ns_per_ms,
        62 * std.time.ns_per_ms,
    };

    world: ?model.World = null,
    paused: bool = true,
    random_seed: u64 = initial_seed,
    viewport_x: usize = 0,
    viewport_y: usize = 0,
    zoom: u8 = 1,
    speed_index: usize = 1,

    pub const Msg = union(enum) {
        toggle_pause,
        step_once,
        simulation_tick,
        randomize,
        clear,
        pan_left,
        pan_right,
        pan_up,
        pan_down,
        zoom_in,
        zoom_out,
        speed_up,
        speed_down,
        quit,
    };

    pub fn create() App {
        return .{};
    }

    pub fn init(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        self.world = try model.World.init(ctx.allocator(), default_width, default_height);
        seedInitialPattern(&self.world.?.grid);
    }

    pub fn deinit(self: *App, ctx: chasen.AppDeinitContext) void {
        if (self.world) |*world| {
            world.deinit(ctx.allocator);
            self.world = null;
        }
    }

    pub fn update(self: *App, msg: Msg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .toggle_pause => try self.togglePause(ctx),
            .step_once => if (self.world) |*world| try world.step(ctx.allocator()),
            .simulation_tick => try self.simulationTick(ctx),
            .randomize => if (self.world) |*world| self.randomize(world),
            .clear => if (self.world) |*world| {
                world.clear();
                self.paused = true;
                self.viewport_x = 0;
                self.viewport_y = 0;
                try ctx.timer().cancel(simulation_timer_id);
            },
            .pan_left => self.pan(-1, 0),
            .pan_right => self.pan(1, 0),
            .pan_up => self.pan(0, -1),
            .pan_down => self.pan(0, 1),
            .zoom_in => self.zoom = @min(self.zoom + 1, 4),
            .zoom_out => self.zoom = @max(self.zoom -| 1, 1),
            .speed_up => try self.changeSpeed(ctx, 1),
            .speed_down => try self.changeSpeed(ctx, -1),
            .quit => {
                try ctx.timer().cancel(simulation_timer_id);
                ctx.quit();
            },
        }
    }

    pub fn speedIntervalNs(self: *const App) u64 {
        return speed_intervals_ns[self.speed_index];
    }

    fn randomize(self: *App, world: *model.World) void {
        var prng = std.Random.DefaultPrng.init(self.random_seed);
        const random = prng.random();
        for (world.grid.cells) |*cell| {
            cell.* = if (random.uintLessThan(u8, 100) < 28) .alive else .dead;
        }
        world.generation = 0;
        self.random_seed +%= 0x9e37_79b9_7f4a_7c15;
    }

    fn togglePause(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        self.paused = !self.paused;
        if (self.paused) {
            try ctx.timer().cancel(simulation_timer_id);
        } else {
            try self.scheduleSimulation(ctx);
        }
    }

    fn simulationTick(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        // A tick can still arrive after cancellation if it was already queued.
        // Keep that stale message from advancing the model or redrawing.
        if (self.paused) {
            ctx.redraw().skip();
            return;
        }
        if (self.world) |*world| {
            try world.step(ctx.allocator());
        }
    }

    fn changeSpeed(self: *App, ctx: *chasen.Ctx(Msg), delta: i2) !void {
        self.speed_index = switch (delta) {
            -1 => self.speed_index -| 1,
            0 => self.speed_index,
            1 => @min(self.speed_index + 1, speed_intervals_ns.len - 1),
            else => unreachable,
        };
        if (!self.paused) try self.scheduleSimulation(ctx);
    }

    fn scheduleSimulation(self: *const App, ctx: *chasen.Ctx(Msg)) !void {
        // Reusing the same timer id lets Chasen replace the active interval
        // when speed changes while the simulation is running.
        try ctx.timer().every(simulation_timer_id, self.speedIntervalNs(), .simulation_tick);
    }

    fn pan(self: *App, dx: i2, dy: i2) void {
        // Pan moves the viewport/camera through the grid, not the cells
        // themselves. The visible world therefore appears to move oppositely.
        const world = self.world orelse return;
        self.viewport_x = panAxis(self.viewport_x, world.grid.width, dx);
        self.viewport_y = panAxis(self.viewport_y, world.grid.height, dy);
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
        // Keep the initial blinker inside the origin viewport so first launch
        // immediately shows live cells in a standard 80-column terminal.
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
};

test "update toggles pause state" {
    var app = App.create();
    var ctx: chasen.Ctx(App.Msg) = .{ ._allocator = std.testing.allocator };
    defer ctx.clearPendingEffectCopies();

    try std.testing.expect(app.paused);
    try app.update(.toggle_pause, &ctx);
    try std.testing.expect(!app.paused);
    try std.testing.expectEqual(@as(u8, 1), ctx.pending_everys_len);

    resetTransient(&ctx);

    try app.update(.toggle_pause, &ctx);
    try std.testing.expect(app.paused);
    try std.testing.expectEqual(@as(u8, 1), ctx.pending_cancels_len);
}

test "clear resets model and pauses" {
    var app = App.create();
    app.world = try model.World.init(std.testing.allocator, 5, 5);
    defer if (app.world) |*world| world.deinit(std.testing.allocator);

    app.world.?.grid.set(2, 2, .alive);
    app.paused = false;

    var ctx: chasen.Ctx(App.Msg) = .{ ._allocator = std.testing.allocator };
    defer ctx.clearPendingEffectCopies();

    try app.update(.clear, &ctx);
    try std.testing.expect(app.paused);
    try std.testing.expectEqual(@as(usize, 0), app.world.?.population());
    try std.testing.expectEqual(@as(u64, 0), app.world.?.generation);
    try std.testing.expectEqual(@as(u8, 1), ctx.pending_cancels_len);
}

test "pan and zoom update viewport state" {
    var app = App.create();
    app.world = try model.World.init(std.testing.allocator, 5, 5);
    defer if (app.world) |*world| world.deinit(std.testing.allocator);

    var ctx: chasen.Ctx(App.Msg) = .{ ._allocator = std.testing.allocator };
    defer ctx.clearPendingEffectCopies();

    try app.update(.pan_right, &ctx);
    try app.update(.pan_down, &ctx);
    try app.update(.zoom_in, &ctx);

    try std.testing.expectEqual(@as(usize, 1), app.viewport_x);
    try std.testing.expectEqual(@as(usize, 1), app.viewport_y);
    try std.testing.expectEqual(@as(u8, 2), app.zoom);

    try app.update(.pan_left, &ctx);
    try app.update(.zoom_out, &ctx);

    try std.testing.expectEqual(@as(usize, 0), app.viewport_x);
    try std.testing.expectEqual(@as(u8, 1), app.zoom);
}

test "initial pattern is visible from origin viewport" {
    var world = try model.World.init(std.testing.allocator, App.default_width, App.default_height);
    defer world.deinit(std.testing.allocator);

    App.seedInitialPattern(&world.grid);

    try std.testing.expectEqual(model.Cell.alive, world.grid.get(4, 2));
    try std.testing.expectEqual(model.Cell.alive, world.grid.get(4, 3));
    try std.testing.expectEqual(model.Cell.alive, world.grid.get(4, 4));
}

test "simulation tick advances only while running" {
    var app = App.create();
    app.world = try model.World.init(std.testing.allocator, 5, 5);
    defer if (app.world) |*world| world.deinit(std.testing.allocator);
    app.world.?.grid.set(2, 1, .alive);
    app.world.?.grid.set(2, 2, .alive);
    app.world.?.grid.set(2, 3, .alive);

    var ctx: chasen.Ctx(App.Msg) = .{ ._allocator = std.testing.allocator };
    defer ctx.clearPendingEffectCopies();

    try app.update(.simulation_tick, &ctx);
    try std.testing.expectEqual(@as(u64, 0), app.world.?.generation);
    try std.testing.expect(ctx.redraw_suppressed);

    app.paused = false;
    resetTransient(&ctx);

    try app.update(.simulation_tick, &ctx);
    try std.testing.expectEqual(@as(u64, 1), app.world.?.generation);
    try std.testing.expect(!ctx.redraw_suppressed);
}

test "speed changes reschedule timer only while running" {
    var app = App.create();
    var ctx: chasen.Ctx(App.Msg) = .{ ._allocator = std.testing.allocator };
    defer ctx.clearPendingEffectCopies();

    try app.update(.speed_up, &ctx);
    try std.testing.expectEqual(@as(usize, 2), app.speed_index);
    try std.testing.expectEqual(@as(u8, 0), ctx.pending_everys_len);

    app.paused = false;
    resetTransient(&ctx);

    try app.update(.speed_down, &ctx);
    try std.testing.expectEqual(@as(usize, 1), app.speed_index);
    try std.testing.expectEqual(@as(u8, 1), ctx.pending_everys_len);
}

test "quit cancels simulation timer" {
    var app = App.create();
    app.paused = false;

    var ctx: chasen.Ctx(App.Msg) = .{ ._allocator = std.testing.allocator };
    defer ctx.clearPendingEffectCopies();

    try app.update(.quit, &ctx);

    try std.testing.expect(ctx.should_quit);
    try std.testing.expectEqual(@as(u8, 1), ctx.pending_cancels_len);
}

fn resetTransient(ctx: *chasen.Ctx(App.Msg)) void {
    ctx.pending_tasks_len = 0;
    ctx.pending_tasks_with_len = 0;
    ctx.clearPendingEffectCopies();
    ctx.redraw_suppressed = false;
    ctx.frame_requested = false;
}
