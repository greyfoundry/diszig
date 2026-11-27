//! Applications wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

pub const ApplicationEventWebhooksStatus = enum(u8) {
    disabled = 1,
    enabled = 2,
    disabled_by_discord = 3,
};

pub const InboundApplicationEventWebhooksStatus = json.InboundEnum(ApplicationEventWebhooksStatus);

pub const ApplicationExplicitContentFilterTypes = enum(u8) {
    inherit = 0,
    always = 1,
};

pub const InboundApplicationExplicitContentFilterTypes = json.InboundEnum(ApplicationExplicitContentFilterTypes);

pub const ApplicationTypes = enum(u8) {
    guild_role_subscriptions = 4,
};

pub const InboundApplicationTypes = json.InboundEnum(ApplicationTypes);

pub const OAuth2Key = struct {
    kty: []const u8,
    use: []const u8,
    kid: []const u8,
    n: []const u8,
    e: []const u8,
    alg: []const u8,
};

/// OAuth2 scope wire strings contain dots, so the enum uses identifier tags and
/// an explicit wire mapping.
pub const OAuth2Scopes = enum {
    identify,
    email,
    connections,
    guilds,
    guilds_join,
    guilds_members_read,
    gdm_join,
    bot,
    rpc,
    rpc_notifications_read,
    rpc_voice_read,
    rpc_voice_write,
    rpc_video_read,
    rpc_video_write,
    rpc_screenshare_read,
    rpc_screenshare_write,
    rpc_activities_write,
    webhook_incoming,
    messages_read,
    applications_builds_upload,
    applications_builds_read,
    applications_commands,
    applications_commands_permissions_update,
    applications_commands_update,
    applications_store_update,
    applications_entitlements,
    activities_read,
    activities_write,
    activities_invites_write,
    relationships_read,
    voice,
    dm_channels_read,
    role_connections_write,
    openid,
    identify_premium,
    sdk_social_layer,
    sdk_social_layer_presence,

    pub fn wire(self: OAuth2Scopes) []const u8 {
        return switch (self) {
            .identify => "identify",
            .email => "email",
            .connections => "connections",
            .guilds => "guilds",
            .guilds_join => "guilds.join",
            .guilds_members_read => "guilds.members.read",
            .gdm_join => "gdm.join",
            .bot => "bot",
            .rpc => "rpc",
            .rpc_notifications_read => "rpc.notifications.read",
            .rpc_voice_read => "rpc.voice.read",
            .rpc_voice_write => "rpc.voice.write",
            .rpc_video_read => "rpc.video.read",
            .rpc_video_write => "rpc.video.write",
            .rpc_screenshare_read => "rpc.screenshare.read",
            .rpc_screenshare_write => "rpc.screenshare.write",
            .rpc_activities_write => "rpc.activities.write",
            .webhook_incoming => "webhook.incoming",
            .messages_read => "messages.read",
            .applications_builds_upload => "applications.builds.upload",
            .applications_builds_read => "applications.builds.read",
            .applications_commands => "applications.commands",
            .applications_commands_permissions_update => "applications.commands.permissions.update",
            .applications_commands_update => "applications.commands.update",
            .applications_store_update => "applications.store.update",
            .applications_entitlements => "applications.entitlements",
            .activities_read => "activities.read",
            .activities_write => "activities.write",
            .activities_invites_write => "activities.invites.write",
            .relationships_read => "relationships.read",
            .voice => "voice",
            .dm_channels_read => "dm_channels.read",
            .role_connections_write => "role_connections.write",
            .openid => "openid",
            .identify_premium => "identify.premium",
            .sdk_social_layer => "sdk.social_layer",
            .sdk_social_layer_presence => "sdk.social_layer_presence",
        };
    }

    pub fn parseWire(text: []const u8) ?OAuth2Scopes {
        inline for (@typeInfo(OAuth2Scopes).@"enum".field_values) |enum_value| {
            const tag: OAuth2Scopes = @fromBackingInt(@intCast(enum_value));
            if (std.mem.eql(u8, tag.wire(), text)) return tag;
        }
        return null;
    }

    /// Scopes are dotted strings, so the default enum tag parser cannot be
    /// used. JSON input goes through the explicit wire mapping.
    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !OAuth2Scopes {
        const text = try std.json.innerParse([]const u8, allocator, source, options);
        return parseWire(text) orelse error.InvalidEnumTag;
    }

    pub fn jsonStringify(self: OAuth2Scopes, jw: anytype) !void {
        try jw.write(self.wire());
    }
};

pub const InboundOAuth2Scopes = struct {
    raw: []const u8,

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        return .{ .raw = try std.json.innerParse([]const u8, allocator, source, options) };
    }

    pub fn known(self: InboundOAuth2Scopes) ?OAuth2Scopes {
        return OAuth2Scopes.parseWire(self.raw);
    }
};

pub const Error = error{
    EmptyScopes,
    DuplicateScope,
    ScopeNotInstallable,
    PermissionsTooLarge,
};

/// Highest install-permission bitmask the pinned schema allows.
pub const max_install_permissions: u64 = 18_014_398_509_481_983;

/// Default install link parameters. Only the two installation scopes are
/// allowed, and the list must be non-empty and duplicate free.
pub const ApplicationOAuth2InstallParams = struct {
    scopes: ?[]const OAuth2Scopes = null,
    permissions: ?u64 = null,

    pub fn validate(self: ApplicationOAuth2InstallParams) Error!void {
        if (self.scopes) |scopes| {
            if (scopes.len == 0) return error.EmptyScopes;
            for (scopes, 0..) |scope, index| {
                if (scope != .bot and scope != .applications_commands) return error.ScopeNotInstallable;
                for (scopes[0..index]) |earlier| {
                    if (earlier == scope) return error.DuplicateScope;
                }
            }
        }
        if (self.permissions) |permissions| {
            if (permissions > max_install_permissions) return error.PermissionsTooLarge;
        }
    }
};

pub const ApplicationOAuth2InstallParamsResponse = struct {
    scopes: []const OAuth2Scopes,
    /// Decimal permission bitmask; the response schema types it as a string.
    permissions: []const u8,
};

pub const OAuth2GetKeys = struct {
    keys: []const OAuth2Key,
};

test "application enums and wire scopes" {
    try std.testing.expectEqual(@as(u8, 2), @backingInt(ApplicationEventWebhooksStatus.enabled));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(ApplicationExplicitContentFilterTypes.always));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(ApplicationTypes.guild_role_subscriptions));
    try std.testing.expectEqualStrings("guilds.join", OAuth2Scopes.guilds_join.wire());
    try std.testing.expectEqualStrings(
        "applications.commands.permissions.update",
        OAuth2Scopes.applications_commands_permissions_update.wire(),
    );
    try std.testing.expectEqual(OAuth2Scopes.openid, OAuth2Scopes.parseWire("openid").?);
    try std.testing.expect(@as(?OAuth2Scopes, null) == OAuth2Scopes.parseWire("future.scope"));
}

test "oauth2 key requires every field" {
    var parsed = try std.json.parseFromSlice(OAuth2Key, std.testing.allocator,
        \\{"kty":"RSA","use":"sig","kid":"1","n":"abc","e":"AQAB","alg":"RS256"}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("RS256", parsed.value.alg);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(OAuth2Key, std.testing.allocator,
            \\{"kty":"RSA","use":"sig","kid":"1","n":"abc","e":"AQAB"}
        , .{ .ignore_unknown_fields = true }),
    );
}

test "unknown inbound scope is retained" {
    var parsed = try std.json.parseFromSlice(InboundOAuth2Scopes, std.testing.allocator, "\"future.scope\"", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?OAuth2Scopes, null), parsed.value.known());
    try std.testing.expectEqualStrings("future.scope", parsed.value.raw);
}

test "install params restrict scopes and permissions" {
    try (ApplicationOAuth2InstallParams{
        .scopes = &.{ .applications_commands, .bot },
        .permissions = max_install_permissions,
    }).validate();
    try (ApplicationOAuth2InstallParams{ .scopes = null, .permissions = null }).validate();

    try std.testing.expectError(
        error.EmptyScopes,
        (ApplicationOAuth2InstallParams{ .scopes = &.{} }).validate(),
    );
    try std.testing.expectError(
        error.DuplicateScope,
        (ApplicationOAuth2InstallParams{ .scopes = &.{ .bot, .bot } }).validate(),
    );
    try std.testing.expectError(
        error.ScopeNotInstallable,
        (ApplicationOAuth2InstallParams{ .scopes = &.{.identify} }).validate(),
    );
    try std.testing.expectError(
        error.PermissionsTooLarge,
        (ApplicationOAuth2InstallParams{ .permissions = max_install_permissions + 1 }).validate(),
    );
}

test "install params response and key list parse" {
    var params = try std.json.parseFromSlice(ApplicationOAuth2InstallParamsResponse, std.testing.allocator,
        \\{"scopes":["applications.commands","bot"],"permissions":"2048"}
    , .{ .ignore_unknown_fields = true });
    defer params.deinit();
    try std.testing.expectEqual(@as(usize, 2), params.value.scopes.len);
    try std.testing.expectEqualStrings("2048", params.value.permissions);

    var keys = try std.json.parseFromSlice(OAuth2GetKeys, std.testing.allocator,
        \\{"keys":[{"kty":"RSA","use":"sig","kid":"1","n":"abc","e":"AQAB","alg":"RS256"}]}
    , .{ .ignore_unknown_fields = true });
    defer keys.deinit();
    try std.testing.expectEqual(@as(usize, 1), keys.value.keys.len);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(OAuth2GetKeys, std.testing.allocator, "{}", .{ .ignore_unknown_fields = true }),
    );
}
