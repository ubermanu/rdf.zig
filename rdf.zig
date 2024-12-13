const std = @import("std");

pub const Triple = struct {
    subject: []const u8,
    predicate: []const u8,
    object: []const u8,
};

pub const Graph = @import("Graph.zig");

test {
    _ = @import("n_triples.zig");
    _ = @import("turtle.zig");
    _ = Graph;
}
