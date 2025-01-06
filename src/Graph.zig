const std = @import("std");
const n_triples = @import("n_triples.zig");
const turtle = @import("turtle.zig");
const Triple = @import("Triple.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Node = struct {
    name: []const u8,
    related: std.ArrayList(LinkedData),
};

const LinkedData = struct {
    predicate: []const u8,
    object: Object,
};

const Object = union(enum) {
    node: *Node,
    literal: Literal,
};

const Literal = struct {
    value: []const u8,
    type: ?[]const u8 = null,
};

arena: ArenaAllocator,
nodes: std.ArrayList(*Node),

const Graph = @This();

pub fn init(allocator: Allocator) Graph {
    return .{
        .arena = ArenaAllocator.init(allocator),
        .nodes = std.ArrayList(*Node).init(allocator),
    };
}

/// Free all the memory associated with this graph.
pub fn deinit(self: Graph) void {
    self.nodes.deinit();
    self.arena.deinit();
}

pub const Format = enum {
    n_triples,
    turtle,
};

/// Import some nodes into the graph, according to the given format.
pub fn loadFromString(self: *Graph, format: Format, buffer: []const u8) !void {
    const allocator = self.arena.allocator();

    const triples = switch (format) {
        .n_triples => try n_triples.parse(allocator, buffer),
        .turtle => try turtle.parse(allocator, buffer),
    };

    for (triples) |triple| {
        try self.addTriple(triple);
    }
}

// TODO: All fields of the triple must be filled
// TODO: Avoid duplicate relations
pub fn addTriple(self: *Graph, triple: Triple) !void {
    const subject = try self.getOrCreateNode(triple.subject);

    // If the object starts with a double quote, it's a literal
    const object: Object = if (triple.object[0] == '"')
        .{ .literal = try parseLiteral(triple.object) }
    else
        .{ .node = try self.getOrCreateNode(triple.object) };

    try subject.related.append(.{
        .predicate = trimString(triple.predicate, "<>"),
        .object = object,
    });
}

fn getOrCreateNode(self: *Graph, name: []const u8) !*Node {
    var node: *Node = undefined;

    if (self.getNodeByName(name)) |n| {
        node = n;
    } else {
        const allocator = self.arena.allocator();
        node = try allocator.create(Node);

        node.* = Node{
            .name = trimString(name, "<>"),
            .related = std.ArrayList(LinkedData).init(allocator),
        };

        try self.nodes.append(node);
    }

    return node;
}

/// Parses a string like `"1973-03-26"^^<http://www.w3.org/2001/XMLSchema#date>` to a literal.
// TODO: Throw error if malformed
fn parseLiteral(str: []const u8) !Literal {
    var it = std.mem.splitSequence(u8, str, "^^");
    return Literal{
        .value = trimString(it.first(), "\""),
        .type = if (it.next()) |t| trimString(t, "<>") else null,
    };
}

fn getNodeByName(self: Graph, name: []const u8) ?*Node {
    for (self.nodes.items) |n| {
        if (std.mem.eql(u8, n.name, name)) {
            return n;
        }
    }
    return null;
}

fn trimString(slice: []const u8, values_to_strip: []const u8) []const u8 {
    return std.mem.trim(u8, slice, values_to_strip);
}

test "graph from n_triples" {
    const str =
        \\<http://example.org/person#Alice> <http://xmlns.com/foaf/0.1/name> "Alice" .
        \\<http://example.org/person#Alice> <http://xmlns.com/foaf/0.1/age> "30"^^<http://www.w3.org/2001/XMLSchema#integer> .
        \\
        \\<http://example.org/person#Bob> <http://xmlns.com/foaf/0.1/name> "Bob" .
        \\<http://example.org/person#Bob> <http://xmlns.com/foaf/0.1/age> "25"^^<http://www.w3.org/2001/XMLSchema#integer> .
        \\<http://example.org/person#Bob> <http://xmlns.com/foaf/0.1/knows> <http://example.org/person#Charlie> .
        \\
        \\<http://example.org/person#Charlie> <http://xmlns.com/foaf/0.1/name> "Charlie" .
        \\<http://example.org/person#Charlie> <http://xmlns.com/foaf/0.1/age> "35"^^<http://www.w3.org/2001/XMLSchema#integer> .
    ;

    var g = init(std.testing.allocator);
    defer g.deinit();

    try g.loadFromString(.n_triples, str);

    try std.testing.expectEqualStrings("http://example.org/person#Alice", g.nodes.items[0].name);
    try std.testing.expectEqualStrings("http://xmlns.com/foaf/0.1/name", g.nodes.items[0].related.items[0].predicate);
    try std.testing.expectEqualStrings("Alice", g.nodes.items[0].related.items[0].object.literal.value);
    try std.testing.expectEqual(null, g.nodes.items[0].related.items[0].object.literal.type);
}
