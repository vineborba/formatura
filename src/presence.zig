const std = @import("std");

const ArrayList = std.ArrayList;

pub const Presence = struct {
    name: []const u8,
    phone: []const u8,
    restriction: ?[]const u8,
};

pub const PresenceBuilder = struct {
    name: ?[]const u8,
    phone: ?[]const u8,
    restriction: ?[]const u8,
    plusOne: ?[]const u8,
    otherPresences: ArrayList(Presence),
    allocator: std.mem.Allocator,

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
    };

    pub fn init(allocator: std.mem.Allocator) !PresenceBuilder {
        const otherPresences = try ArrayList(Presence).initCapacity(allocator, 3);
        return PresenceBuilder{ .allocator = allocator, .name = null, .phone = null, .restriction = null, .plusOne = null, .otherPresences = otherPresences };
    }

    pub fn deinit(self: *PresenceBuilder) void {
        self.otherPresences.deinit(self.allocator);
    }

    pub fn setProp(self: *PresenceBuilder, prop: []const u8, value: []const u8) void {
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
                }
            },
        }
    }

    pub fn build(self: *PresenceBuilder) ![]Presence {
        if (self.name == null or self.name.?.len < 1) {
            return error.InvalidName;
        }

        if (self.phone == null or self.phone.?.len < 9) {
            return error.InvalidPhone;
        }

        if (self.plusOne != null and self.plusOne.?.len > 1) {
            var iter = std.mem.splitSequence(u8, self.plusOne.?, ",");
            while (iter.next()) |item| {
                const name = std.mem.trim(u8, item, " ");
                try self.otherPresences.append(self.allocator, Presence{ .name = name, .phone = self.phone.?, .restriction = self.restriction });
            }
        }

        var presences = try ArrayList(Presence).initCapacity(self.allocator, 1 + self.otherPresences.items.len);

        try presences.append(self.allocator, Presence{
            .name = self.name.?,
            .phone = self.phone.?,
            .restriction = self.restriction,
        });

        if (self.otherPresences.items.len > 0) {
            try presences.appendSlice(self.allocator, self.otherPresences.items);
        }

        return presences.toOwnedSlice(self.allocator);
    }
};
