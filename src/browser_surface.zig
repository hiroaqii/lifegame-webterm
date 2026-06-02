const std = @import("std");

pub const Size = struct {
    width: u16,
    height: u16,
};

pub const Rect = struct {
    col: u16,
    row: u16,
    width: u16,
    height: u16,
};

pub const CellKind = enum {
    blank,
    text,
    live,
};

pub const Cell = struct {
    kind: CellKind = .blank,
    char: u8 = ' ',
};

// App-specific logical frame buffer for the browser prototype. Canvas/JS glue
// will paint these cells later; this module stays independent of Chasen/vaxis.
pub const BrowserSurface = struct {
    width: u16,
    height: u16,
    cells: []Cell,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !BrowserSurface {
        const cell_count = std.math.mul(usize, width, height) catch return error.SurfaceTooLarge;
        const cells = try allocator.alloc(Cell, cell_count);
        @memset(cells, .{});
        return .{
            .width = width,
            .height = height,
            .cells = cells,
        };
    }

    pub fn deinit(self: *BrowserSurface, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        self.* = undefined;
    }

    pub fn size(self: *const BrowserSurface) Size {
        return .{
            .width = self.width,
            .height = self.height,
        };
    }

    pub fn clear(self: *BrowserSurface) void {
        @memset(self.cells, .{});
    }

    pub fn putTextAt(self: *BrowserSurface, col: u16, row: u16, text: []const u8) void {
        if (row >= self.height) return;

        var x = col;
        for (text) |byte| {
            if (x >= self.width) break;
            self.setCell(x, row, .{ .kind = .text, .char = byte });
            x += 1;
        }
    }

    pub fn fill(self: *BrowserSurface, rect: Rect, cell: Cell) void {
        // Clamp at the surface boundary so renderers can pass partially visible
        // rectangles without doing their own browser-specific clipping.
        const right = @min(self.width, rect.col + rect.width);
        const bottom = @min(self.height, rect.row + rect.height);

        var row = rect.row;
        while (row < bottom) : (row += 1) {
            var col = rect.col;
            while (col < right) : (col += 1) {
                self.setCell(col, row, cell);
            }
        }
    }

    pub fn readCell(self: *const BrowserSurface, col: u16, row: u16) ?Cell {
        if (col >= self.width or row >= self.height) return null;
        return self.cells[self.index(col, row)];
    }

    pub fn cellChar(self: *const BrowserSurface, col: u16, row: u16) u8 {
        const cell = self.readCell(col, row) orelse return ' ';
        return cell.char;
    }

    fn setCell(self: *BrowserSurface, col: u16, row: u16, cell: Cell) void {
        self.cells[self.index(col, row)] = cell;
    }

    fn index(self: *const BrowserSurface, col: u16, row: u16) usize {
        return @as(usize, row) * self.width + col;
    }
};

test "BrowserSurface stores text and filled cells" {
    var surface = try BrowserSurface.init(std.testing.allocator, 10, 4);
    defer surface.deinit(std.testing.allocator);

    surface.putTextAt(1, 1, "Life");
    surface.fill(.{ .col = 0, .row = 3, .width = 2, .height = 1 }, .{ .kind = .live, .char = '#' });

    try std.testing.expectEqual(@as(u8, 'L'), surface.cellChar(1, 1));
    try std.testing.expectEqual(@as(u8, 'e'), surface.cellChar(4, 1));
    try std.testing.expectEqual(CellKind.live, surface.readCell(0, 3).?.kind);
    try std.testing.expectEqual(@as(u8, '#'), surface.cellChar(1, 3));
}
