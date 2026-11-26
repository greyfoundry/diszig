//! Discord Gateway intent bits.
//!
//! Bits and privileged status follow the pinned Gateway documentation. Bits not
//! listed here are rejected rather than forwarded blindly.

const std = @import("std");

pub const guilds: u64 = 1 << 0;
pub const guild_members: u64 = 1 << 1;
pub const guild_moderation: u64 = 1 << 2;
pub const guild_expressions: u64 = 1 << 3;
pub const guild_integrations: u64 = 1 << 4;
pub const guild_webhooks: u64 = 1 << 5;
pub const guild_invites: u64 = 1 << 6;
pub const guild_voice_states: u64 = 1 << 7;
pub const guild_presences: u64 = 1 << 8;
pub const guild_messages: u64 = 1 << 9;
pub const guild_message_reactions: u64 = 1 << 10;
pub const guild_message_typing: u64 = 1 << 11;
pub const direct_messages: u64 = 1 << 12;
pub const direct_message_reactions: u64 = 1 << 13;
pub const direct_message_typing: u64 = 1 << 14;
pub const message_content: u64 = 1 << 15;
pub const guild_scheduled_events: u64 = 1 << 16;
pub const auto_moderation_configuration: u64 = 1 << 20;
pub const auto_moderation_execution: u64 = 1 << 21;
pub const guild_message_polls: u64 = 1 << 24;
pub const direct_message_polls: u64 = 1 << 25;

pub const known_mask: u64 = ((1 << 17) - 1) |
    auto_moderation_configuration |
    auto_moderation_execution |
    guild_message_polls |
    direct_message_polls;

pub const privileged_mask: u64 = guild_members | guild_presences | message_content;

pub const Error = error{UnknownIntentBits};

pub fn isKnown(bits: u64) bool {
    return bits & ~known_mask == 0;
}

pub fn validate(bits: u64) Error!void {
    if (!isKnown(bits)) return error.UnknownIntentBits;
}

pub fn isPrivileged(bits: u64) bool {
    return bits & privileged_mask != 0;
}

pub fn has(bits: u64, intent: u64) bool {
    return bits & intent != 0;
}

/// Name-to-bit mapping for callers that prefer not to hard-code shifts.
pub const Intent = enum(u6) {
    guilds = 0,
    guild_members = 1,
    guild_moderation = 2,
    guild_expressions = 3,
    guild_integrations = 4,
    guild_webhooks = 5,
    guild_invites = 6,
    guild_voice_states = 7,
    guild_presences = 8,
    guild_messages = 9,
    guild_message_reactions = 10,
    guild_message_typing = 11,
    direct_messages = 12,
    direct_message_reactions = 13,
    direct_message_typing = 14,
    message_content = 15,
    guild_scheduled_events = 16,
    auto_moderation_configuration = 20,
    auto_moderation_execution = 21,
    guild_message_polls = 24,
    direct_message_polls = 25,

    pub fn bit(self: Intent) u64 {
        return @as(u64, 1) << @backingInt(self);
    }
};

test "documented values match the pinned table" {
    try std.testing.expectEqual(@as(u64, 1), guilds);
    try std.testing.expectEqual(@as(u64, 1 << 1), guild_members);
    try std.testing.expectEqual(@as(u64, 1 << 16), guild_scheduled_events);
    try std.testing.expectEqual(@as(u64, 1 << 20), auto_moderation_configuration);
    try std.testing.expectEqual(@as(u64, 1 << 24), guild_message_polls);
    try std.testing.expectEqual(@as(u64, 1 << 25), Intent.direct_message_polls.bit());
}

test "privileged intents are identified and unknown bits are rejected" {
    try std.testing.expect(isPrivileged(guild_members));
    try std.testing.expect(isPrivileged(guild_presences));
    try std.testing.expect(isPrivileged(message_content));
    try std.testing.expect(!isPrivileged(guilds | guild_messages));
    try std.testing.expect(isKnown(known_mask));
    try std.testing.expectError(error.UnknownIntentBits, validate(1 << 17));
    try std.testing.expectError(error.UnknownIntentBits, validate(1 << 63));
    try validate(guilds | guild_messages | guild_message_polls);
}
