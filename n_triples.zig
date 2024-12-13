const std = @import("std");
const rdf = @import("rdf.zig");

const Allocator = std.mem.Allocator;
const Triple = rdf.Triple;

const ParseError = error{
    MissingPredicate,
    MissingObject,
    MissingEndingDot,
};

/// Reads a `N-Triples` input, and return triples.
/// Caller owns the returned memory.
pub fn parse(allocator: Allocator, input: []const u8) ![]Triple {
    var triples = std.ArrayList(Triple).init(allocator);
    defer triples.deinit();

    var lines = std.mem.splitSequence(u8, input, "\n");

    while (lines.next()) |line| {
        if (line.len == 0) {
            continue;
        }

        var it = std.mem.splitSequence(u8, line, " ");
        const subject = it.first();
        const predicate = it.next() orelse return error.MissingPredicate;

        const object = it.next() orelse return error.MissingObject;

        const end = it.next();
        if (end == null or end.?.len > 1 or end.?[0] != '.') {
            return error.MissingEndingDot;
        }

        try triples.append(.{
            .subject = subject,
            .predicate = predicate,
            .object = object,
        });
    }

    return triples.toOwnedSlice();
}

test "parse" {
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

    const triples = try parse(std.testing.allocator, str);
    defer std.testing.allocator.free(triples);

    try std.testing.expectEqual(7, triples.len);
}

/// Outputs a `N-Triples` string from triples.
/// Caller owns the returned memory.
pub fn print(allocator: Allocator, triples: []const Triple) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    for (triples, 0..) |triple, i| {
        try output.appendSlice(triple.subject);
        try output.append(' ');
        try output.appendSlice(triple.predicate);
        try output.append(' ');
        try output.appendSlice(triple.object);
        try output.appendSlice(" .");

        if (i + 1 < triples.len) {
            try output.append('\n');
        }
    }

    return output.toOwnedSlice();
}

test "print" {
    const triples = [_]Triple{
        .{
            .subject = "<http://example.org/person#Alice>",
            .predicate = "<http://xmlns.com/foaf/0.1/name>",
            .object = "\"Alice\"",
        },
        .{
            .subject = "<http://example.org/person#Alice>",
            .predicate = "<http://xmlns.com/foaf/0.1/age>",
            .object = "\"30\"^^<http://www.w3.org/2001/XMLSchema#integer>",
        },
    };

    const str = try print(std.testing.allocator, &triples);
    defer std.testing.allocator.free(str);

    const expected =
        \\<http://example.org/person#Alice> <http://xmlns.com/foaf/0.1/name> "Alice" .
        \\<http://example.org/person#Alice> <http://xmlns.com/foaf/0.1/age> "30"^^<http://www.w3.org/2001/XMLSchema#integer> .
    ;

    try std.testing.expectEqualStrings(expected, str);
}
