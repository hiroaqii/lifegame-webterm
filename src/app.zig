const std = @import("std");
const chasen = @import("chasen");

const input = @import("input.zig");
const model = @import("model.zig");
const render = @import("render.zig");

pub const App = struct {
    pub const default_width: usize = 80;
    pub const default_height: usize = 40;
    const initial_seed: u64 = 0x6c_69_66_65_67_61_6d_65;

    world: ?model.World = null,
    paused: bool = true,
    random_seed: u64 = initial_seed,
    viewport_x: usize = 0,
    viewport_y: usize = 0,
    zoom: u8 = 1,

    pub const Msg = union(enum) {
        toggle_pause,
        step_once,
        randomize,
        clear,
        pan_left,
        pan_right,
        pan_up,
        pan_down,
        zoom_in,
        zoom_out,
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
            .toggle_pause => self.paused = !self.paused,
            .step_once => if (self.world) |*world| try world.step(ctx.allocator()),
            .randomize => if (self.world) |*world| self.randomize(world),
            .clear => if (self.world) |*world| {
                world.clear();
                self.paused = true;
                self.viewport_x = 0;
                self.viewport_y = 0;
            },
            .pan_left => self.pan(-1, 0),
            .pan_right => self.pan(1, 0),
            .pan_up => self.pan(0, -1),
            .pan_down => self.pan(0, 1),
            .zoom_in => self.zoom = @min(self.zoom + 1, 4),
            .zoom_out => self.zoom = @max(self.zoom -| 1, 1),
            .quit => ctx.quit(),
        }
    }

    pub fn view(self: *const App, surface: *chasen.Surface) !void {
        try render.view(surface, .{
            .world = self.world,
            .paused = self.paused,
            .viewport_x = self.viewport_x,
            .viewport_y = self.viewport_y,
            .zoom = self.zoom,
        });
    }

    pub fn handleEvent(self: *const App, event: chasen.Event) ?Msg {
        _ = self;
        return input.handleEvent(event);
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

    fn pan(self: *App, dx: i2, dy: i2) void {
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

test "handleEvent maps quit key" {
    const msg = App.create().handleEvent(.{ .key_press = .{ .codepoint = 'q' } }).?;
    try std.testing.expectEqual(App.Msg.quit, msg);
}

test "update toggles pause state" {
    var app = App.create();
    var tc: chasen.testing.TestCtx(App.Msg) = .{};

    try std.testing.expect(app.paused);
    try app.update(.toggle_pause, &tc.ctx);
    try std.testing.expect(!app.paused);
}

test "clear resets model and pauses" {
    var app = App.create();
    app.world = try model.World.init(std.testing.allocator, 5, 5);
    defer if (app.world) |*world| world.deinit(std.testing.allocator);

    app.world.?.grid.set(2, 2, .alive);
    app.paused = false;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};

    try app.update(.clear, &tc.ctx);
    try std.testing.expect(app.paused);
    try std.testing.expectEqual(@as(usize, 0), app.world.?.population());
    try std.testing.expectEqual(@as(u64, 0), app.world.?.generation);
}

test "pan and zoom update viewport state" {
    var app = App.create();
    app.world = try model.World.init(std.testing.allocator, 5, 5);
    defer if (app.world) |*world| world.deinit(std.testing.allocator);

    var tc: chasen.testing.TestCtx(App.Msg) = .{};

    try app.update(.pan_right, &tc.ctx);
    try app.update(.pan_down, &tc.ctx);
    try app.update(.zoom_in, &tc.ctx);

    try std.testing.expectEqual(@as(usize, 1), app.viewport_x);
    try std.testing.expectEqual(@as(usize, 1), app.viewport_y);
    try std.testing.expectEqual(@as(u8, 2), app.zoom);

    try app.update(.pan_left, &tc.ctx);
    try app.update(.zoom_out, &tc.ctx);

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
