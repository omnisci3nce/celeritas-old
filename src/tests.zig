// for now just do top level tests in a single file
const std = @import("std");
const builtin = @import("builtin");
const expect = std.testing.expect;

test "builtin.is_test" {
    expect(builtin.is_test);
}