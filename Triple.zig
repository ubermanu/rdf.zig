const std = @import("std");

subject: []u8,
predicate: []u8,
object: []u8,

const Triple = @This();

pub fn alloc(allocator: std.mem.Allocator, subject: []const u8, predicate: []const u8, object: []const u8) !Triple {
    return .{
        .subject = try allocator.dupe(u8, subject),
        .predicate = try allocator.dupe(u8, predicate),
        .object = try allocator.dupe(u8, object),
    };
}

pub fn deinit(self: Triple, allocator: std.mem.Allocator) void {
    allocator.free(self.subject);
    allocator.free(self.predicate);
    allocator.free(self.object);
}
