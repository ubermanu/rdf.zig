# rdf.zig

A RDF Graph parser, supports the following formats:

- N-Triples
- Turtle

## Install

```sh
zig fetch --save git+https://github.com/ubermanu/rdf.zig
```

```zig
const rdf_mod = b.dependency("rdf", .{});
exe.addImport("rdf", rdf_mod.module("rdf"));
```

## Usage

```zig
const Graph = @import("rdf").Graph;

test {
    const graph = Graph.init(std.testing.allocator);
    defer graph.deinit();

    const ttl =
        \\@prefix foaf: <http://xmlns.com/foaf/0.1/> .
        \\
        \\<http://example.org/person#Alice>
        \\    a foaf:Person ;
        \\    foaf:name "Alice" ;
        \\    foaf:age "30"^^xsd:integer .
    ;

    graph.loadFromString(.turtle, ttl);

    try std.testing.expectEqualStrings(
        "http://example.org/person#Alice",
        graph.nodes.items[0].name,
    );
}
```
