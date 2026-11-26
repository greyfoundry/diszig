//! Discord guild/channel permission flags and documented overwrite ordering.
//!
//! These helpers compute what Discord documents. They do not replace server
//! enforcement: the server may reject an action despite a computed permission,
//! and role hierarchy / 2FA / owner rules still apply.

const std = @import("std");
const flags = @import("flags.zig");

pub const Permissions = flags.Flags(u64);

pub const CREATE_INSTANT_INVITE: u64 = 1 << 0;
pub const KICK_MEMBERS: u64 = 1 << 1;
pub const BAN_MEMBERS: u64 = 1 << 2;
pub const ADMINISTRATOR: u64 = 1 << 3;
pub const MANAGE_CHANNELS: u64 = 1 << 4;
pub const MANAGE_GUILD: u64 = 1 << 5;
pub const ADD_REACTIONS: u64 = 1 << 6;
pub const VIEW_AUDIT_LOG: u64 = 1 << 7;
pub const PRIORITY_SPEAKER: u64 = 1 << 8;
pub const STREAM: u64 = 1 << 9;
pub const VIEW_CHANNEL: u64 = 1 << 10;
pub const SEND_MESSAGES: u64 = 1 << 11;
pub const SEND_TTS_MESSAGES: u64 = 1 << 12;
pub const MANAGE_MESSAGES: u64 = 1 << 13;
pub const EMBED_LINKS: u64 = 1 << 14;
pub const ATTACH_FILES: u64 = 1 << 15;
pub const READ_MESSAGE_HISTORY: u64 = 1 << 16;
pub const MENTION_EVERYONE: u64 = 1 << 17;
pub const USE_EXTERNAL_EMOJIS: u64 = 1 << 18;
pub const VIEW_GUILD_INSIGHTS: u64 = 1 << 19;
pub const CONNECT: u64 = 1 << 20;
pub const SPEAK: u64 = 1 << 21;
pub const MUTE_MEMBERS: u64 = 1 << 22;
pub const DEAFEN_MEMBERS: u64 = 1 << 23;
pub const MOVE_MEMBERS: u64 = 1 << 24;
pub const USE_VAD: u64 = 1 << 25;
pub const CHANGE_NICKNAME: u64 = 1 << 26;
pub const MANAGE_NICKNAMES: u64 = 1 << 27;
pub const MANAGE_ROLES: u64 = 1 << 28;
pub const MANAGE_WEBHOOKS: u64 = 1 << 29;
pub const MANAGE_GUILD_EXPRESSIONS: u64 = 1 << 30;
pub const USE_APPLICATION_COMMANDS: u64 = 1 << 31;
pub const REQUEST_TO_SPEAK: u64 = 1 << 32;
pub const MANAGE_EVENTS: u64 = 1 << 33;
pub const MANAGE_THREADS: u64 = 1 << 34;
pub const CREATE_PUBLIC_THREADS: u64 = 1 << 35;
pub const CREATE_PRIVATE_THREADS: u64 = 1 << 36;
pub const USE_EXTERNAL_STICKERS: u64 = 1 << 37;
pub const SEND_MESSAGES_IN_THREADS: u64 = 1 << 38;
pub const USE_EMBEDDED_ACTIVITIES: u64 = 1 << 39;
pub const MODERATE_MEMBERS: u64 = 1 << 40;
pub const VIEW_CREATOR_MONETIZATION_ANALYTICS: u64 = 1 << 41;
pub const USE_SOUNDBOARD: u64 = 1 << 42;
pub const CREATE_GUILD_EXPRESSIONS: u64 = 1 << 43;
pub const CREATE_EVENTS: u64 = 1 << 44;
pub const USE_EXTERNAL_SOUNDS: u64 = 1 << 45;
pub const SEND_VOICE_MESSAGES: u64 = 1 << 46;
pub const SET_VOICE_CHANNEL_STATUS: u64 = 1 << 48;
pub const SEND_POLLS: u64 = 1 << 49;
pub const USE_EXTERNAL_APPS: u64 = 1 << 50;
pub const PIN_MESSAGES: u64 = 1 << 51;
pub const BYPASS_SLOWMODE: u64 = 1 << 52;

pub const known_mask: u64 = blk: {
    var mask: u64 = 0;
    for ([_]u64{
        CREATE_INSTANT_INVITE,  KICK_MEMBERS,                        BAN_MEMBERS,              ADMINISTRATOR,
        MANAGE_CHANNELS,        MANAGE_GUILD,                        ADD_REACTIONS,            VIEW_AUDIT_LOG,
        PRIORITY_SPEAKER,       STREAM,                              VIEW_CHANNEL,             SEND_MESSAGES,
        SEND_TTS_MESSAGES,      MANAGE_MESSAGES,                     EMBED_LINKS,              ATTACH_FILES,
        READ_MESSAGE_HISTORY,   MENTION_EVERYONE,                    USE_EXTERNAL_EMOJIS,      VIEW_GUILD_INSIGHTS,
        CONNECT,                SPEAK,                               MUTE_MEMBERS,             DEAFEN_MEMBERS,
        MOVE_MEMBERS,           USE_VAD,                             CHANGE_NICKNAME,          MANAGE_NICKNAMES,
        MANAGE_ROLES,           MANAGE_WEBHOOKS,                     MANAGE_GUILD_EXPRESSIONS, USE_APPLICATION_COMMANDS,
        REQUEST_TO_SPEAK,       MANAGE_EVENTS,                       MANAGE_THREADS,           CREATE_PUBLIC_THREADS,
        CREATE_PRIVATE_THREADS, USE_EXTERNAL_STICKERS,               SEND_MESSAGES_IN_THREADS, USE_EMBEDDED_ACTIVITIES,
        MODERATE_MEMBERS,       VIEW_CREATOR_MONETIZATION_ANALYTICS, USE_SOUNDBOARD,           CREATE_GUILD_EXPRESSIONS,
        CREATE_EVENTS,          USE_EXTERNAL_SOUNDS,                 SEND_VOICE_MESSAGES,      SET_VOICE_CHANNEL_STATUS,
        SEND_POLLS,             USE_EXTERNAL_APPS,                   PIN_MESSAGES,             BYPASS_SLOWMODE,
    }) |flag| {
        mask |= flag;
    }
    break :blk mask;
};

pub const Overwrite = struct {
    allow: Permissions = .empty,
    deny: Permissions = .empty,

    pub fn apply(self: Overwrite, base: Permissions) Permissions {
        var result = base;
        result.remove(self.deny.bits);
        result.add(self.allow.bits);
        return result;
    }
};

pub const ComputeError = error{
    IncompleteMember,
};

/// Applies the documented order: @everyone overwrite, aggregated role
/// overwrites, then the member overwrite. `roles_complete` must be false when
/// the role list is known to be partial (for example a cache miss); the caller
/// gets an explicit error instead of an inferred permission set.
pub fn compute(
    base: Permissions,
    everyone: ?Overwrite,
    roles: []const Overwrite,
    member: ?Overwrite,
    roles_complete: bool,
) ComputeError!Permissions {
    if (!roles_complete) return error.IncompleteMember;

    var result = base;
    if (result.has(ADMINISTRATOR)) return .{ .bits = (result.bits | known_mask) };

    if (everyone) |overwrite| result = overwrite.apply(result);

    var role_allow: u64 = 0;
    var role_deny: u64 = 0;
    for (roles) |overwrite| {
        role_allow |= overwrite.allow.bits;
        role_deny |= overwrite.deny.bits;
    }
    result.remove(role_deny);
    result.add(role_allow);

    if (member) |overwrite| result = overwrite.apply(result);
    return result;
}

/// Threads inherit the parent channel permissions, except SEND_MESSAGES is not
/// inherited. SEND_MESSAGES_IN_THREADS remains the permission that controls
/// sending in a thread. Thread creation/locked/private rules are server-side.
pub fn threadFromParent(parent: Permissions, overwrite: ?Overwrite) Permissions {
    var result = if (overwrite) |value| value.apply(parent) else parent;
    result.remove(SEND_MESSAGES);
    return result;
}

/// Timed-out members keep only VIEW_CHANNEL and READ_MESSAGE_HISTORY. Owners and
/// administrators are exempt.
pub fn timedOut(base: Permissions, is_owner: bool) Permissions {
    if (is_owner or base.has(ADMINISTRATOR)) return base;
    return .{ .bits = base.bits & (VIEW_CHANNEL | READ_MESSAGE_HISTORY) };
}

/// Role hierarchy is separate from permission bits. Equal positions do not
/// outrank each other; the guild owner outranks everyone.
pub fn outranks(actor_top_position: i32, target_top_position: i32, actor_is_owner: bool) bool {
    if (actor_is_owner) return true;
    return actor_top_position > target_top_position;
}

test "unknown high permission bit round-trips" {
    const future = Permissions{ .bits = 1 << 63 };
    var buffer: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try future.writeDecimal(&writer);
    const parsed = try Permissions.parseDecimal(writer.buffered());
    try std.testing.expect(parsed.has(1 << 63));
}

test "everyone deny, role allow, member deny follows the documented order" {
    const base = Permissions.init(VIEW_CHANNEL | SEND_MESSAGES);
    const everyone = Overwrite{
        .deny = Permissions.init(VIEW_CHANNEL),
    };
    const roles = [_]Overwrite{
        .{
            .allow = Permissions.init(VIEW_CHANNEL | SEND_MESSAGES),
            .deny = Permissions.init(SEND_MESSAGES),
        },
    };
    const member = Overwrite{
        .deny = Permissions.init(SEND_MESSAGES),
    };
    const result = try compute(base, everyone, &roles, member, true);
    try std.testing.expect(result.has(VIEW_CHANNEL));
    try std.testing.expect(!result.has(SEND_MESSAGES));
}

test "partial member roles are an explicit error" {
    try std.testing.expectError(
        error.IncompleteMember,
        compute(Permissions.empty, null, &.{}, null, false),
    );
}

test "threads inherit parent but do not inherit SEND_MESSAGES" {
    const parent = Permissions.init(VIEW_CHANNEL | SEND_MESSAGES | SEND_MESSAGES_IN_THREADS);
    const thread = threadFromParent(parent, null);
    try std.testing.expect(thread.has(VIEW_CHANNEL));
    try std.testing.expect(!thread.has(SEND_MESSAGES));
    try std.testing.expect(thread.has(SEND_MESSAGES_IN_THREADS));
}

test "timed out members keep only view and history unless exempt" {
    const base = Permissions.init(VIEW_CHANNEL | READ_MESSAGE_HISTORY | SEND_MESSAGES);
    const limited = timedOut(base, false);
    try std.testing.expect(limited.has(VIEW_CHANNEL));
    try std.testing.expect(limited.has(READ_MESSAGE_HISTORY));
    try std.testing.expect(!limited.has(SEND_MESSAGES));

    const admin = Permissions.init(ADMINISTRATOR | SEND_MESSAGES);
    try std.testing.expect(timedOut(admin, false).has(SEND_MESSAGES));
    try std.testing.expect(timedOut(base, true).has(SEND_MESSAGES));
}

test "administrator grants known permissions and bypasses overwrites" {
    const base = Permissions.init(ADMINISTRATOR);
    const result = try compute(base, .{ .deny = Permissions.init(VIEW_CHANNEL) }, &.{}, null, true);
    try std.testing.expect(result.has(VIEW_CHANNEL));
}

test "role hierarchy uses positions and owner override" {
    try std.testing.expect(outranks(10, 5, false));
    try std.testing.expect(!outranks(5, 10, false));
    try std.testing.expect(!outranks(5, 5, false));
    try std.testing.expect(outranks(0, 999, true));
}
