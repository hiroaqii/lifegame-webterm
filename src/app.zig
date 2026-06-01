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

    pub const Msg = union(enum) {
        toggle_pause,
        step_once,
        randomize,
        clear,
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
            },
            .quit => ctx.quit(),
        }
    }

    pub fn view(self: *const App, surface: *chasen.Surface) !void {
        try render.view(surface, .{
            .world = self.world,
            .paused = self.paused,
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

    fn seedInitialPattern(grid: *model.Grid) void {
        const center_x = grid.width / 2;
        const center_y = grid.height / 2;
        grid.set(center_x, center_y - 1, .alive);
        grid.set(center_x, center_y, .alive);
        grid.set(center_x, center_y + 1, .alive);
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
