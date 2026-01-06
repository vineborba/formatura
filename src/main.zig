const std = @import("std");
const formatura = @import("formatura");

pub fn main() !void {
    try formatura.startServer();
}
