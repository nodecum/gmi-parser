const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        invalid,
        text,
        arg, // argument of head,link,etc terminated by crlf
        head,
        link,
        quote,
        preformat_toggle,
        eof,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .invalid,
                .text,
                .arg,
                .eof,
                => null,
                .head => "#",
                .link => "=>",
                .quote => ">",
                .preformat_toggle => "```",
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid bytes",
                .text => "text",
                .arg => "argument",
                .eof => "EOF",
                else => unreachable,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize,
    preformat_toggle_mode: bool,
    new_line: bool,

    /// For debugging purposes
    pub fn dump(self: *Tokenizer, token: *const Token) void {
        std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
    }

    pub fn init(buffer: [:0]const u8) Tokenizer {
        // Skip the UTF-8 BOM if present
        const src_start: usize = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0;
        return Tokenizer{
            .buffer = buffer,
            .index = src_start,
            .preformat_toggle_mode = false,
            .new_line = true,
        };
    }

    const State = enum {
        start,
        space,
        bt1, // `
        bt2, // ``
        ln1, // =
        h1, // #
        h2, // ##
        text,
        arg,
    };

    pub fn next(self: *Tokenizer) Token {
        var state: State = .start;
        var result = Token{
            .tag = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };
        var exclude_char = false;
        while (true) : (self.index += 1) {
            const c = self.buffer[self.index];
            if (c == 0) {
                if (self.index != self.buffer.len) {
                    result.tag = .invalid;
                    result.loc.start = self.index;
                    self.index += 1;
                    result.loc.end = self.index;
                } else {
                    result.tag =
                        switch (state) {
                        .start => .eof,
                        .space => .eof,
                        .bt1 => .text,
                        .bt2 => .text,
                        .ln1 => .text,
                        .h1 => .head,
                        .h2 => .head,
                        .text => .text,
                        .arg => .arg,
                    };
                    result.loc.end = self.index;
                }
                return result;
            }
            switch (state) {
                .start => {
                    if (self.new_line) {
                        // we start on a new line
                        if (self.preformat_toggle_mode) {
                            if (c == '`') {
                                state = .bt1;
                            } else {
                                state = .text;
                            }
                        } else {
                            // normal mode
                            switch (c) {
                                '#' => {
                                    state = .h1;
                                },
                                '=' => {
                                    state = .ln1;
                                },
                                '>' => {
                                    result.tag = .quote;
                                    self.new_line = false;
                                    break;
                                },
                                '`' => {
                                    state = .bt1;
                                },
                                '\n' => {
                                    result.tag = .text;
                                    exclude_char = true;
                                    break;
                                },
                                else => {
                                    state = .text;
                                },
                            }
                        }
                    } else {
                        // we start not on a new line
                        switch (c) {
                            ' ', '\t' => {
                                state = .space;
                            },
                            '\n' => {
                                // state stays at .start;
                                self.new_line = true;
                            },
                            else => {
                                state = .arg;
                            },
                        }
                    }
                },
                .space => switch (c) {
                    // we are looking for arguments
                    ' ', '\t' => {},
                    '\n' => {
                        state = .start;
                        self.new_line = true;
                    },
                    else => {
                        result.loc.start = self.index;
                        state = .arg;
                    },
                },
                .bt1 => switch (c) {
                    '`' => {
                        state = .bt2;
                    },
                    '\n' => {
                        result.tag = .text;
                        self.new_line = true;
                        exclude_char = true;
                        break;
                    },
                    else => {
                        state = .text;
                    },
                },
                .bt2 => switch (c) {
                    '`' => {
                        result.tag = .preformat_toggle;
                        self.new_line = false;
                        break;
                    },
                    '\n' => {
                        result.tag = .text;
                        self.new_line = true;
                        exclude_char = true;
                        break;
                    },
                    else => {
                        state = .text;
                    },
                },
                .ln1 => switch (c) {
                    '>' => {
                        result.tag = .link;
                        self.new_line = false;
                        break;
                    },
                    '\n' => {
                        result.tag = .text;
                        self.new_line = true;
                        exclude_char = true;

                        break;
                    },
                    else => {
                        state = .text;
                    },
                },
                .h1 => switch (c) {
                    '#' => {
                        state = .h2;
                    },
                    else => {
                        result.tag = .head;
                        self.index -= 1; // reread char
                        self.new_line = false;
                        break;
                    },
                },
                .h2 => switch (c) {
                    '#' => {
                        result.tag = .head;
                        self.new_line = false;
                        break;
                    },
                    else => {
                        result.tag = .head;
                        self.index -= 1; // reread char
                        self.new_line = false;
                        break;
                    },
                },
                .text => switch (c) {
                    '\n' => {
                        result.tag = .text;
                        self.new_line = true;
                        exclude_char = true;
                        break;
                    },
                    else => {},
                },
                .arg => switch (c) {
                    '\n' => {
                        result.tag = .arg;
                        self.new_line = true;
                        exclude_char = true;
                        break;
                    },
                    ' ', '\t' => {
                        result.tag = .arg;
                        self.new_line = false;
                        exclude_char = true;
                        break;
                    },
                    else => {},
                },
            }
        }
        self.index += 1;
        if (exclude_char) {
            result.loc.end = self.index - 1;
        } else {
            result.loc.end = self.index;
        }
        return result;
    }

    fn checkLiteralCharacter(self: *Tokenizer) void {
        if (self.pending_invalid_token != null) return;
        const invalid_length = self.getInvalidCharacterLength();
        if (invalid_length == 0) return;
        self.pending_invalid_token = .{
            .tag = .invalid,
            .loc = .{
                .start = self.index,
                .end = self.index + invalid_length,
            },
        };
    }

    fn getInvalidCharacterLength(self: *Tokenizer) u3 {
        const c0 = self.buffer[self.index];
        if (std.ascii.isASCII(c0)) {
            if (c0 == '\r') {
                if (self.index + 1 < self.buffer.len and self.buffer[self.index + 1] == '\n') {
                    // Carriage returns are *only* allowed just before a linefeed as part of a CRLF pair, otherwise
                    // they constitute an illegal byte!
                    return 0;
                } else {
                    return 1;
                }
            } else if (std.ascii.isControl(c0)) {
                // ascii control codes are never allowed
                // (note that \n was checked before we got here)
                return 1;
            }
            // looks fine to me.
            return 0;
        } else {
            // check utf8-encoded character.
            const length = std.unicode.utf8ByteSequenceLength(c0) catch return 1;
            if (self.index + length > self.buffer.len) {
                return @as(u3, @intCast(self.buffer.len - self.index));
            }
            const bytes = self.buffer[self.index .. self.index + length];
            switch (length) {
                2 => {
                    const value = std.unicode.utf8Decode2(bytes) catch return length;
                    if (value == 0x85) return length; // U+0085 (NEL)
                },
                3 => {
                    const value = std.unicode.utf8Decode3(bytes) catch return length;
                    if (value == 0x2028) return length; // U+2028 (LS)
                    if (value == 0x2029) return length; // U+2029 (PS)
                },
                4 => {
                    _ = std.unicode.utf8Decode4(bytes) catch return length;
                },
                else => unreachable,
            }
            self.index += length - 1;
            return 0;
        }
    }
};

test "Text" {
    try testTokenize("Text", &.{
        .{ .tag = .text, .loc = .{
            .start = 0,
            .end = 4,
        } },
    });
}

test "TextText" {
    try testTokenize("abc\ndef", &.{
        .{ .tag = .text, .loc = .{
            .start = 0,
            .end = 3,
        } },
        .{ .tag = .text, .loc = .{
            .start = 4,
            .end = 7,
        } },
    });
}

test ">Quote" {
    try testTokenize(">Quote", &.{
        .{ .tag = .quote, .loc = .{
            .start = 0,
            .end = 1,
        } },
        .{ .tag = .arg, .loc = .{
            .start = 1,
            .end = 6,
        } },
    });
}

test "=> foo" {
    try testTokenize("=> foo xx\nbar", &.{
        .{ .tag = .link, .loc = .{
            .start = 0,
            .end = 2,
        } },
        .{ .tag = .arg, .loc = .{
            .start = 3,
            .end = 6,
        } },
        .{ .tag = .arg, .loc = .{
            .start = 7,
            .end = 9,
        } },
        .{ .tag = .text, .loc = .{
            .start = 10,
            .end = 13,
        } },
    });
}
test "#Hello" {
    try testTokenize("#Hello", &.{
        .{ .tag = .head, .loc = .{
            .start = 0,
            .end = 1,
        } },
        .{ .tag = .arg, .loc = .{
            .start = 1,
            .end = 6,
        } },
    });
}
test "##Hello" {
    try testTokenize("##Hello", &.{
        .{ .tag = .head, .loc = .{
            .start = 0,
            .end = 2,
        } },
        .{ .tag = .arg, .loc = .{
            .start = 2,
            .end = 7,
        } },
    });
}
test "###Hello" {
    try testTokenize("###Hello", &.{
        .{ .tag = .head, .loc = .{
            .start = 0,
            .end = 3,
        } },
        .{ .tag = .arg, .loc = .{
            .start = 3,
            .end = 8,
        } },
    });
}
test "# Hello" {
    try testTokenize("# Hello", &.{
        .{ .tag = .head, .loc = .{
            .start = 0,
            .end = 1,
        } },
        .{ .tag = .arg, .loc = .{
            .start = 2,
            .end = 7,
        } },
    });
}

test "```\nfoo\n```" {
    try testTokenize("```arg\nfoo\n```", &.{
        .{ .tag = .preformat_toggle, .loc = .{
            .start = 0,
            .end = 3,
        } },
        .{ .tag = .arg, .loc = .{
            .start = 3,
            .end = 6,
        } },
        .{ .tag = .text, .loc = .{
            .start = 7,
            .end = 10,
        } },
        .{ .tag = .preformat_toggle, .loc = .{
            .start = 11,
            .end = 14,
        } },
    });
}
fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_token_tags) |expected_token_tag| {
        const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, token);
    }
    const last_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.loc.start);
    try std.testing.expectEqual(source.len, last_token.loc.end);
}
