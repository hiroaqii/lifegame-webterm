const std = @import("std");

const model = @import("model.zig");

const Case = struct {
    width: usize,
    height: usize,
    steps: usize,
    seed: u64,
};

const cases = [_]Case{
    .{ .width = 80, .height = 40, .steps = 500, .seed = 0x80_40 },
    .{ .width = 160, .height = 80, .steps = 250, .seed = 0x160_80 },
    .{ .width = 320, .height = 160, .steps = 100, .seed = 0x320_160 },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    try stdout.writeAll("Lifegame Webterm model benchmark\n");
    try stdout.writeAll("size,cells,steps,total_ms,avg_step_ms,population\n");

    for (cases) |case| {
        const result = try runCase(allocator, init.io, case);
        try stdout.print(
            "{d}x{d},{d},{d},{d:.3},{d:.3},{d}\n",
            .{
                case.width,
                case.height,
                case.width * case.height,
                case.steps,
                result.total_ms,
                result.avg_step_ms,
                result.population,
            },
        );
    }

    try stdout.flush();
}

const BenchResult = struct {
    total_ms: f64,
    avg_step_ms: f64,
    population: usize,
};

fn runCase(allocator: std.mem.Allocator, io: std.Io, case: Case) !BenchResult {
    var world = try model.World.init(allocator, case.width, case.height);
    defer world.deinit(allocator);
    seedRandom(&world.grid, case.seed);

    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..case.steps) |_| {
        try world.step(allocator);
    }
    const elapsed = start.untilNow(io).raw;
    const total_ms = @as(f64, @floatFromInt(elapsed.nanoseconds)) / @as(f64, std.time.ns_per_ms);

    return .{
        .total_ms = total_ms,
        .avg_step_ms = total_ms / @as(f64, @floatFromInt(case.steps)),
        .population = world.population(),
    };
}

fn seedRandom(grid: *model.Grid, seed: u64) void {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    for (grid.cells) |*cell| {
        cell.* = if (random.uintLessThan(u8, 100) < 28) .alive else .dead;
    }
}
