const std = @import("std");
const mvzr = @import("mvzr");

const ArrayList = std.ArrayList;

const phoneRegex: mvzr.Regex = mvzr.compile("^\\(\\d{2}\\)?\\s?\\d{5}-?\\d{4}$").?;

pub const Presence = struct {
    name: []const u8,
    phone: []const u8,
    restriction: ?[]const u8,
};
const Prop = enum {
    name,
    phone,
    restriction,
    plusOne,
    other,
};

const ValidationError = error{
    InvalidName,
    InvalidPhone,
    InvalidRestriction,
    InvalidPlusOne,
};

pub const PresenceBuilder = struct {
    name: ?[]const u8,
    phone: ?[]const u8,
    restriction: ?[]const u8,
    plusOne: ?[]const u8,
    otherPresences: ArrayList(Presence),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !PresenceBuilder {
        const otherPresences = try ArrayList(Presence).initCapacity(allocator, 3);
        return PresenceBuilder{ .allocator = allocator, .name = null, .phone = null, .restriction = null, .plusOne = null, .otherPresences = otherPresences };
    }

    pub fn deinit(self: *PresenceBuilder) void {
        self.otherPresences.deinit(self.allocator);
    }

    pub fn setProp(self: *PresenceBuilder, prop: []const u8, value: []const u8) !void {
        const propString = std.meta.stringToEnum(Prop, prop) orelse {
            return;
        };

        switch (propString) {
            .name => {
                self.name = value;
            },
            .phone => {
                self.phone = value;
            },
            .restriction => {
                if (std.mem.eql(u8, value, "outro")) {
                    return;
                }
                self.restriction = value;
            },
            .plusOne => {
                self.plusOne = value;
            },
            .other => {
                if (self.restriction == null) {
                    self.restriction = value;
                    return;
                }

                const updatedRestriction = try std.mem.concat(
                    self.allocator,
                    u8,
                    &[_][]const u8{
                        self.restriction.?,
                        ", ",
                        value,
                    },
                );
                self.allocator.free(self.restriction.?);
                self.restriction = updatedRestriction;
            },
        }
    }

    pub fn build(self: *PresenceBuilder) ![]Presence {
        const name = self.name orelse return error.InvalidName;
        if (name.len < 1 or name.len > 60) {
            return error.InvalidName;
        }

        const phone = self.phone orelse return error.InvalidPhone;
        if (phone.len < 9 or !phoneRegex.isMatch(phone)) {
            return error.InvalidPhone;
        }

        if (self.plusOne) |plusOne| {
            if (plusOne.len < 1 or plusOne.len > 60) {
                return error.InvalidPlusOne;
            }

            var iter = std.mem.splitSequence(u8, plusOne, ",");
            while (iter.next()) |item| {
                const plusOneName = std.mem.trim(u8, item, " ");
                try self.otherPresences.append(
                    self.allocator,
                    Presence{
                        .name = plusOneName,
                        .phone = phone,
                        .restriction = self.restriction,
                    },
                );
            }
        }

        var presences = try ArrayList(Presence).initCapacity(self.allocator, 1 + self.otherPresences.items.len);

        try presences.append(self.allocator, Presence{
            .name = name,
            .phone = phone,
            .restriction = self.restriction,
        });

        if (self.otherPresences.items.len > 0) {
            try presences.appendSlice(self.allocator, self.otherPresences.items);
        }

        return presences.toOwnedSlice(self.allocator);
    }
};
