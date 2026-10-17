const std = @import("std");

const greeting = "Hello from Zig!";

pub fn main() void {
    std.debug.print("{s}\n", .{greeting});
}

test "greeting_always_expected_text" {
    try std.testing.expectEqualStrings("Hello from Zig!", greeting);
}
