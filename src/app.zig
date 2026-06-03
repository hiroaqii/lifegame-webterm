const chasen = @import("chasen");

const app_core = @import("app_core.zig");
const input = @import("input.zig");
const render = @import("render.zig");

pub const App = struct {
    core: app_core.App = .{},

    pub const Msg = app_core.App.Msg;

    pub fn create() App {
        return .{ .core = app_core.App.create() };
    }

    pub fn init(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        try self.core.init(ctx);
    }

    pub fn deinit(self: *App, ctx: chasen.AppDeinitContext) void {
        self.core.deinit(ctx);
    }

    pub fn update(self: *App, msg: Msg, ctx: *chasen.Ctx(Msg)) !void {
        try self.core.update(msg, ctx);
    }

    pub fn view(self: *const App, surface: *chasen.Surface) !void {
        try render.view(surface, .{
            .world = self.core.world,
            .paused = self.core.paused,
            .viewport_x = self.core.viewport_x,
            .viewport_y = self.core.viewport_y,
            .zoom = self.core.zoom,
            .speed_index = self.core.speed_index,
            .speed_interval_ns = self.core.speedIntervalNs(),
        });
    }

    pub fn handleEvent(self: *const App, event: chasen.Event) ?Msg {
        _ = self;
        return input.handleEvent(event);
    }
};

test "handleEvent maps quit key" {
    const msg = App.create().handleEvent(.{ .key_press = .{ .codepoint = 'q' } }).?;
    try @import("std").testing.expectEqual(App.Msg.quit, msg);
}
