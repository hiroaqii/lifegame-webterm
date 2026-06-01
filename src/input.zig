const std = @import("std");
const chasen = @import("chasen");

const app = @import("app.zig");

pub fn handleEvent(event: chasen.Event) ?app.App.Msg {
    return switch (event) {
        .key_press => |key| switch (key.codepoint) {
            ' ' => .toggle_pause,
            'n' => .step_once,
            'r' => .randomize,
            'c' => .clear,
            'q' => .quit,
            else => null,
        },
        else => null,
    };
}

test "maps keyboard events to app messages" {
    try std.testing.expectEqual(app.App.Msg.toggle_pause, handleEvent(.{ .key_press = .{ .codepoint = ' ' } }).?);
    try std.testing.expectEqual(app.App.Msg.step_once, handleEvent(.{ .key_press = .{ .codepoint = 'n' } }).?);
    try std.testing.expectEqual(app.App.Msg.randomize, handleEvent(.{ .key_press = .{ .codepoint = 'r' } }).?);
    try std.testing.expectEqual(app.App.Msg.clear, handleEvent(.{ .key_press = .{ .codepoint = 'c' } }).?);
    try std.testing.expectEqual(app.App.Msg.quit, handleEvent(.{ .key_press = .{ .codepoint = 'q' } }).?);
    try std.testing.expectEqual(@as(?app.App.Msg, null), handleEvent(.{ .key_press = .{ .codepoint = 'x' } }));
}
