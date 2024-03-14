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
        list_item,
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
                .list_item => "*",
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
    state: State,
    //preformat_toggle_mode: bool,
    //new_line: bool,

    pub const State = enum {
        new_line,
        arg,
        bt1, // `
        bt2, // ``
        ln1, // =
        h1, // #
        h2, // ##
        li1, // *
        text,
        pf_new_line,
        pf_arg,
        pf_bt1,
        pf_bt2,
        pf_text,
    };
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
            .state = .new_line,
            //.preformat_toggle_mode = false,
            //.new_line = true,
        };
    }

    pub fn next(self: *Tokenizer) Token {
        //var state: State = .start;
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
                        switch (self.state) {
                        .new_line, .pf_new_line => .eof,
                        .bt1, .bt2, .pf_bt1, .pf_bt2, .ln1, .li1, .text, .pf_text => .text,
                        .h1, .h2 => .head,
                        .arg, .pf_arg => .arg,
                    };
                    self.state = .new_line; // the next read should get eof
                    result.loc.end = self.index;
                }
                return result;
            }
            switch (self.state) {
                .new_line => switch (c) {
                    '#' => {
                        self.state = .h1;
                    },
                    '=' => {
                        self.state = .ln1;
                    },
                    '>' => {
                        result.tag = .quote;
                        self.state = .arg;
                        break;
                    },
                    '*' => {
                        self.state = .li1;
                    },
                    '`' => {
                        self.state = .bt1;
                    },
                    '\n' => {
                        result.tag = .text;
                        exclude_char = true;
                        break;
                    },
                    else => {
                        self.state = .text;
                    },
                },
                .arg => switch (c) {
                    '\n' => {
                        result.tag = .arg;
                        self.state = .new_line;
                        exclude_char = true;
                        break;
                    },
                    else => {},
                },
                .bt1 => switch (c) {
                    '`' => {
                        self.state = .bt2;
                    },
                    '\n' => {
                        result.tag = .text;
                        self.state = .new_line;
                        exclude_char = true;
                        break;
                    },
                    else => {
                        self.state = .text;
                    },
                },
                .bt2 => switch (c) {
                    '`' => {
                        result.tag = .preformat_toggle;
                        self.state = .pf_arg;
                        break;
                    },
                    '\n' => {
                        result.tag = .text;
                        self.state = .new_line;
                        exclude_char = true;
                        break;
                    },
                    else => {
                        self.state = .text;
                    },
                },
                .li1 => switch (c) {
                    ' ' => {
                        result.tag = .list_item;
                        self.state = .arg;
                        break;
                    },
                    else => {
                        self.state = .text;
                    },
                },
                .h1 => switch (c) {
                    '#' => {
                        self.state = .h2;
                    },
                    else => {
                        result.tag = .head;
                        self.index -= 1; // reread char
                        self.state = .arg;
                        break;
                    },
                },
                .h2 => switch (c) {
                    '#' => {
                        result.tag = .head;
                        self.state = .arg;
                        break;
                    },
                    else => {
                        result.tag = .head;
                        self.index -= 1; // reread char
                        self.state = .arg;
                        break;
                    },
                },
                .ln1 => switch (c) {
                    '>' => {
                        result.tag = .link;
                        self.state = .arg;
                        break;
                    },
                    '\n' => {
                        result.tag = .text;
                        self.state = .new_line;
                        exclude_char = true;
                        break;
                    },
                    else => {
                        self.state = .text;
                    },
                },
                .text => switch (c) {
                    '\n' => {
                        result.tag = .text;
                        self.state = .new_line;
                        exclude_char = true;
                        break;
                    },
                    else => {},
                },
                .pf_new_line => switch (c) {
                    '`' => {
                        self.state = .bt1;
                    },
                    else => {
                        self.state = .pf_text;
                    },
                },
                .pf_bt1 => switch (c) {
                    '`' => {
                        self.state = .pf_bt2;
                    },
                    '\n' => {
                        result.tag = .text;
                        self.state = .pf_new_line;
                        exclude_char = true;
                        break;
                    },
                    else => {
                        self.state = .pf_text;
                    },
                },
                .pf_bt2 => switch (c) {
                    '`' => {
                        result.tag = .preformat_toggle;
                        self.state = .arg;
                        break;
                    },
                    '\n' => {
                        result.tag = .text;
                        self.state = .pf_new_line;
                        exclude_char = true;
                        break;
                    },
                    else => {
                        self.state = .pf_text;
                    },
                },
                .pf_arg => switch (c) {
                    '\n' => {
                        result.tag = .arg;
                        self.state = .pf_new_line;
                        exclude_char = true;
                        break;
                    },
                    else => {},
                },
                .pf_text => switch (c) {
                    '\n' => {
                        result.tag = .text;
                        self.state = .pf_new_line;
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
        //return 0;
    }
};

test "Text" {
    try testTokenize("Text", &.{
        .{ .tag = .text, .loc = .{ .start = 0, .end = 4 } },
    });
}

test "TextText" {
    try testTokenize("abc\ndef", &.{
        .{ .tag = .text, .loc = .{ .start = 0, .end = 3 } },
        .{ .tag = .text, .loc = .{ .start = 4, .end = 7 } },
    });
}

test ">Quote" {
    try testTokenize(">Quote", &.{
        .{ .tag = .quote, .loc = .{ .start = 0, .end = 1 } },
        .{ .tag = .arg, .loc = .{ .start = 1, .end = 6 } },
    });
}

test "=> foo" {
    try testTokenize("=> foo xx\nbar", &.{
        .{ .tag = .link, .loc = .{ .start = 0, .end = 2 } },
        .{ .tag = .arg, .loc = .{ .start = 3, .end = 6 } },
        .{ .tag = .arg, .loc = .{ .start = 7, .end = 9 } },
        .{ .tag = .text, .loc = .{ .start = 10, .end = 13 } },
    });
}
test "#Hello" {
    try testTokenize("#Hello", &.{
        .{ .tag = .head, .loc = .{ .start = 0, .end = 1 } },
        .{ .tag = .arg, .loc = .{ .start = 1, .end = 6 } },
    });
}
test "##Hello" {
    try testTokenize("##Hello", &.{
        .{ .tag = .head, .loc = .{ .start = 0, .end = 2 } },
        .{ .tag = .arg, .loc = .{ .start = 2, .end = 7 } },
    });
}
test "###Hello" {
    try testTokenize("###Hello", &.{
        .{ .tag = .head, .loc = .{ .start = 0, .end = 3 } },
        .{ .tag = .arg, .loc = .{ .start = 3, .end = 8 } },
    });
}
test "# Hello" {
    try testTokenize("# Hello", &.{
        .{ .tag = .head, .loc = .{ .start = 0, .end = 1 } },
        .{ .tag = .arg, .loc = .{ .start = 2, .end = 7 } },
    });
}

test "```\nfoo\n```" {
    try testTokenize("```arg\nfoo\n```", &.{
        .{ .tag = .preformat_toggle, .loc = .{ .start = 0, .end = 3 } },
        .{ .tag = .arg, .loc = .{ .start = 3, .end = 6 } },
        .{ .tag = .text, .loc = .{ .start = 7, .end = 10 } },
        .{ .tag = .preformat_toggle, .loc = .{ .start = 11, .end = 14 } },
    });
}

test "* item" {
    try testTokenize("* item", &.{
        .{ .tag = .list_item, .loc = .{ .start = 0, .end = 2 } },
        .{ .tag = .arg, .loc = .{ .start = 2, .end = 6 } },
    });
}
test "*text" {
    try testTokenize("*text", &.{
        .{ .tag = .text, .loc = .{ .start = 0, .end = 5 } },
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
