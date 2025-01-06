const std = @import("std");

pub const Triple = @import("Triple.zig");
pub const Graph = @import("Graph.zig");

test {
    _ = @import("n_triples.zig");
    _ = @import("turtle.zig");
    _ = Graph;
}
