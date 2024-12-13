const std = @import("std");
const rdf = @import("rdf.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Triple = rdf.Triple;

const ParseError = error{
    UnexpectedCharacter,
    NonTerminatedQuote,
    UndefinedNamespace,
};

const type_ns = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";

const Token = struct {
    kind: union(enum) { literal, delimiter: u8 },
    pos: usize,
    len: usize,

    pub fn slice(self: Token, str: []const u8) []const u8 {
        return str[self.pos..][0..self.len];
    }
};

const Tokenizer = struct {
    allocator: Allocator,
    buffer: []const u8,
    pos: usize,

    pub fn init(allocator: Allocator) Tokenizer {
        return .{
            .allocator = allocator,
            .buffer = "",
            .pos = 0,
        };
    }

    /// Return tokens from the input text.
    /// Caller owns the returned memory.
    pub fn tokenize(self: *Tokenizer, buffer: []const u8) ![]Token {
        self.buffer = buffer;
        self.pos = 0;

        var tokens = std.ArrayList(Token).init(self.allocator);
        defer tokens.deinit();

        while (try self.nextToken()) |token| {
            try tokens.append(token);
        }

        return tokens.toOwnedSlice();
    }

    fn nextToken(self: *Tokenizer) !?Token {
        self.skipWhitespaces(0);

        if (self.pos >= self.buffer.len) {
            return null;
        }

        const pos = self.pos;
        const char = self.buffer[pos];

        switch (char) {
            '.', ';' => {
                self.skipWhitespaces(1);
                return .{ .kind = .{ .delimiter = char }, .pos = pos, .len = 1 };
            },
            else => {
                var quoted = false;

                while (self.pos < self.buffer.len) : (self.pos += 1) {
                    const c = self.buffer[self.pos];

                    if (c == '"') {
                        quoted = !quoted;
                        continue;
                    }

                    if (std.ascii.isWhitespace(c) and !quoted) {
                        break;
                    }
                }

                if (quoted) {
                    return error.NonTerminatedQuote;
                }

                return .{ .kind = .literal, .pos = pos, .len = self.pos - pos };
            },
        }
    }

    // Advance `offset` chars, skipping whitespaces.
    fn skipWhitespaces(self: *Tokenizer, offset: usize) void {
        self.pos += offset;

        while (self.pos < self.buffer.len) : (self.pos += 1) {
            if (std.ascii.isWhitespace(self.buffer[self.pos]) == false) {
                break;
            }
        }
    }
};

test "tokenizer" {
    const str =
        \\@prefix foaf: <http://xmlns.com/foaf/0.1/> .
        \\
        \\<http://example.org/person#Alice>
        \\    a foaf:Person ;
        \\    foaf:name "Alice" ;
        \\    foaf:age "30"^^xsd:integer .
    ;

    var t = Tokenizer.init(std.testing.allocator);

    const tokens = try t.tokenize(str);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(14, tokens.len);
}

const Parser = struct {
    allocator: Allocator,
    buffer: []const u8,
    pos: usize,
    prefixes: std.StringHashMap([]const u8),
    triples: std.ArrayList(Triple),
    tokens: []const Token,

    pub fn init(allocator: Allocator) Parser {
        return .{
            .allocator = allocator,
            .buffer = "",
            .pos = 0,
            .prefixes = std.StringHashMap([]const u8).init(allocator),
            .triples = std.ArrayList(Triple).init(allocator),
            .tokens = undefined,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.prefixes.deinit();
        self.triples.deinit();
    }

    pub fn parse(self: *Parser, buffer: []const u8) ![]Triple {
        self.buffer = buffer;
        self.pos = 0;

        var tnz = Tokenizer.init(self.allocator);
        self.tokens = try tnz.tokenize(self.buffer);
        defer self.allocator.free(self.tokens);

        while (self.pos < self.tokens.len) {
            const t = self.tokens[self.pos];

            if (t.kind == .literal and std.mem.eql(u8, "@prefix", t.slice(buffer))) {
                self.pos += 1;
                try self.parsePrefix();
                continue;
            }

            try self.parseBlock();
        }

        return self.triples.toOwnedSlice();
    }

    // Parse a prefix and store it for future use.
    fn parsePrefix(self: *Parser) !void {
        const name = try self.expectLiteral();

        if (name[name.len - 1] != ':') {
            return error.UnexpectedCharacter;
        }

        const value = try self.expectLiteral();

        if (value[0] != '<' or value[value.len - 1] != '>') {
            return error.UnexpectedCharacter;
        }

        try self.expectDelimiter('.');

        try self.prefixes.put(name[0 .. name.len - 1], value[1..][0 .. value.len - 2]);
    }

    // Parse a relationship block.
    fn parseBlock(self: *Parser) !void {
        const subject = try self.expectLiteralNS();

        while (self.pos < self.tokens.len) {
            var predicate = try self.expectLiteralNS();

            if (std.mem.eql(u8, predicate, "a")) {
                self.allocator.free(predicate);
                predicate = try self.allocator.dupe(u8, "<" ++ type_ns ++ ">");
            }

            const object = try self.expectLiteralNS();

            try self.triples.append(.{
                .subject = subject,
                .predicate = predicate,
                .object = object,
            });

            if (self.peekDelimiter('.')) {
                break;
            }

            try self.expectDelimiter(';');
        }

        try self.expectDelimiter('.');
    }

    // Get the literal str value or return an error.
    fn expectLiteral(self: *Parser) ![]const u8 {
        const token = self.tokens[self.pos];

        if (token.kind == .literal) {
            self.pos += 1;
            return token.slice(self.buffer);
        }

        return error.UnexpectedCharacter;
    }

    // Expect a literal, but replace the namespace if applicable
    fn expectLiteralNS(self: *Parser) ![]u8 {
        const str = try self.expectLiteral();

        var acc = std.ArrayList(u8).init(self.allocator);
        defer acc.deinit();

        var it = std.mem.splitSequence(u8, str, "^^");

        var i: usize = 0;

        while (it.next()) |part| : (i += 1) {
            if (i > 0) {
                try acc.appendSlice("^^");
            }

            if (getPrefixNS(part)) |prefix| {
                const ns = self.prefixes.get(prefix) orelse return error.UndefinedNamespace;
                try acc.append('<');
                try acc.appendSlice(ns);
                try acc.appendSlice(part[prefix.len + 1 ..]);
                try acc.append('>');
            } else {
                try acc.appendSlice(part);
            }
        }

        return acc.toOwnedSlice();
    }

    // Return true if the current token is the needed delimiter.
    fn peekDelimiter(self: Parser, c: u8) bool {
        const delimiter = self.tokens[self.pos];
        return delimiter.kind == .delimiter and delimiter.kind.delimiter == c;
    }

    // Return an error if the current token is not a proper delimiter.
    fn expectDelimiter(self: *Parser, c: u8) !void {
        const delimiter = self.tokens[self.pos];

        if (delimiter.kind == .delimiter and delimiter.kind.delimiter == c) {
            self.pos += 1;
        } else {
            return error.UnexpectedCharacter;
        }
    }
};

// Returns the namespace prefix, including `:`.
fn getPrefixNS(str: []const u8) ?[]const u8 {
    for (str, 0..) |c, i| {
        if (i > 0 and c == ':') {
            return str[0..i];
        }
        if (std.ascii.isAlphabetic(c) == false) {
            break;
        }
    }
    return null;
}

/// Reads a `Turtle` input, and return triples.
/// Caller owns the returned memory.
pub fn parse(allocator: Allocator, input: []const u8) ![]Triple {
    var parser = Parser.init(allocator);
    defer parser.deinit();
    return parser.parse(input);
}

test "parse" {
    const str =
        \\@prefix foaf: <http://xmlns.com/foaf/0.1/> .
        \\@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .
        \\
        \\<http://example.org/person#Alice>
        \\    a foaf:Person ;
        \\    foaf:name "Alice" ;
        \\    foaf:age "30"^^xsd:integer .
    ;

    var arena = ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const triples = try parse(arena.allocator(), str);

    try std.testing.expectEqual(3, triples.len);
    try std.testing.expectEqualStrings("<http://example.org/person#Alice>", triples[0].subject);
    try std.testing.expectEqualStrings("<" ++ type_ns ++ ">", triples[0].predicate);
    try std.testing.expectEqualStrings("<http://xmlns.com/foaf/0.1/Person>", triples[0].object);

    try std.testing.expectEqualStrings("<http://example.org/person#Alice>", triples[1].subject);
    try std.testing.expectEqualStrings("<http://xmlns.com/foaf/0.1/name>", triples[1].predicate);
    try std.testing.expectEqualStrings("\"Alice\"", triples[1].object);

    try std.testing.expectEqualStrings("<http://example.org/person#Alice>", triples[2].subject);
    try std.testing.expectEqualStrings("<http://xmlns.com/foaf/0.1/age>", triples[2].predicate);
    try std.testing.expectEqualStrings("\"30\"^^<http://www.w3.org/2001/XMLSchema#integer>", triples[2].object);
}
