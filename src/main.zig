const std = @import("std");
const formatura = @import("formatura");

const Config = formatura.Config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try Config.init(allocator);
    defer config.deinit();

    try formatura.startServer(allocator, config);
}
