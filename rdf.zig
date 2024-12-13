const std = @import("std");

pub const Triple = struct {
    subject: []const u8,
    predicate: []const u8,
    object: []const u8,
};

pub const n_triples = @import("n_triples.zig");
pub const turtle = @import("turtle.zig");

test {
    _ = n_triples;
    _ = turtle;
}
