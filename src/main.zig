const std = @import("std");
const chasen = @import("chasen");
const lifegame_webterm = @import("lifegame_webterm");

pub fn main(init: std.process.Init) !void {
    try chasen.run(init, lifegame_webterm.App.create());
}
