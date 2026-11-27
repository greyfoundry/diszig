//! Documented OAuth2 request builders, response parsing and callback checks.
//!
//! This module is transport-agnostic: it builds authorization URLs and
//! `application/x-www-form-urlencoded` bodies, and parses the documented token
//! response. It never opens a browser, hosts a callback or stores credentials.
//! Callers own secure token storage, redirect hosting and CSRF state.

const std = @import("std");
const request = @import("request.zig");
const applications = @import("protocol").models.applications;

pub const OAuth2Scopes = applications.OAuth2Scopes;

/// Official endpoints from `developers/topics/oauth2.mdx`. The token and
/// revocation URLs are deliberately unversioned and accept form bodies only.
pub const endpoints = struct {
    pub const authorize = "https://discord.com/oauth2/authorize";
    pub const token = "https://discord.com/api/oauth2/token";
    pub const revoke = "https://discord.com/api/oauth2/token/revoke";
    pub const issuer = "https://discord.com";
};

pub const form_content_type = "application/x-www-form-urlencoded";

pub const Error = error{
    MissingClientId,
    InvalidClientId,
    MissingRedirectUri,
    InvalidRedirectUri,
    InvalidState,
    StateMismatch,
    InvalidIssuer,
    EmptyScopes,
    DuplicateScope,
    ScopeNotAllowedForGrant,
    MissingResponseType,
    InvalidResponseType,
    InvalidCodeChallenge,
    MissingCodeVerifier,
    ClientAuthenticationRequired,
    InvalidPermissions,
    InvalidCode,
    InvalidToken,
    InvalidTokenTypeHint,
    InvalidSecret,
    BufferTooSmall,
    WriteFailed,
};

pub const ResponseType = enum {
    code,
    token,

    fn wire(self: ResponseType) []const u8 {
        return switch (self) {
            .code => "code",
            .token => "token",
        };
    }
};

pub const Prompt = enum {
    consent,
    none,

    fn wire(self: Prompt) []const u8 {
        return switch (self) {
            .consent => "consent",
            .none => "none",
        };
    }
};

pub const IntegrationType = enum(u8) {
    guild_install = 0,
    user_install = 1,
};

pub const Grant = enum {
    authorization_code,
    refresh_token,
    client_credentials,
    implicit,

    pub fn wire(self: Grant) []const u8 {
        return switch (self) {
            .authorization_code => "authorization_code",
            .refresh_token => "refresh_token",
            .client_credentials => "client_credentials",
            .implicit => "implicit",
        };
    }
};

pub const TokenTypeHint = enum {
    access_token,
    refresh_token,
};

/// A credential value that is never rendered as itself. There is no formatter
/// that prints `value`; diagnostics must call `redacted()`.
pub const Secret = struct {
    value: []const u8,

    pub const redacted_text = "<redacted>";

    pub fn redacted(self: Secret) []const u8 {
        _ = self;
        return redacted_text;
    }
};

pub const AuthorizationOptions = struct {
    client_id: []const u8,
    scopes: []const OAuth2Scopes,
    /// Null omits `response_type`, which is only valid for pure bot installs.
    response_type: ?ResponseType = .code,
    /// Discord uses the first registered redirect URI when this is omitted.
    redirect_uri: ?[]const u8 = null,
    state: ?[]const u8 = null,
    prompt: ?Prompt = null,
    integration_type: ?IntegrationType = null,
    permissions: ?u64 = null,
    guild_id: ?[]const u8 = null,
    disable_guild_select: bool = false,
    /// S256 PKCE challenge; state the verifier alongside the caller's state.
    code_challenge: ?[]const u8 = null,
};

/// Writes the complete authorization URL. Values are percent-encoded; the
/// client secret is not a parameter and never appears here.
pub fn writeAuthorizationUrl(
    writer: *std.Io.Writer,
    options: AuthorizationOptions,
) Error![]const u8 {
    try validateClientId(options.client_id);
    const grant: Grant = if (options.response_type) |response_type|
        (if (response_type == .token) .implicit else .authorization_code)
    else
        .authorization_code;
    try validateScopes(grant, options.scopes);
    if (options.state) |state| try validateStateValue(state);
    if (options.redirect_uri) |uri| try validateRedirectUri(uri);
    if (options.code_challenge) |challenge| try validateCodeChallenge(challenge);

    if (options.response_type == null and !hasScope(options.scopes, .bot)) {
        return error.MissingResponseType;
    }

    writer.writeAll(endpoints.authorize) catch return error.WriteFailed;
    var query = FormBuilder{ .writer = writer, .separator = '?' };
    if (options.response_type) |response_type| {
        try query.add("response_type", response_type.wire());
    }
    try query.add("client_id", options.client_id);
    try query.addScopes("scope", options.scopes);
    if (options.state) |state| try query.add("state", state);
    if (options.redirect_uri) |uri| try query.add("redirect_uri", uri);
    if (options.prompt) |prompt| try query.add("prompt", prompt.wire());
    if (options.integration_type) |kind| {
        try query.add("integration_type", switch (kind) {
            .guild_install => "0",
            .user_install => "1",
        });
    }
    if (options.permissions) |bits| {
        var buffer: [20]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d}", .{bits}) catch return error.WriteFailed;
        try query.add("permissions", text);
    }
    if (options.guild_id) |guild_id| try query.add("guild_id", guild_id);
    if (options.disable_guild_select) try query.add("disable_guild_select", "true");
    if (options.code_challenge) |challenge| {
        try query.add("code_challenge", challenge);
        try query.add("code_challenge_method", "S256");
    }
    return query.done();
}

pub const AuthorizationCodeExchange = struct {
    code: []const u8,
    /// Must equal the value used in the authorization request.
    redirect_uri: []const u8,
    code_verifier: ?[]const u8 = null,
};

pub const RefreshRequest = struct {
    refresh_token: []const u8,
};

pub const ClientCredentialsRequest = struct {
    scopes: []const OAuth2Scopes,
};

pub const RevokeRequest = struct {
    token: []const u8,
    token_type_hint: ?TokenTypeHint = null,
};

pub const TokenAuth = union(enum) {
    /// HTTP Basic with client id and secret. Recommended default.
    basic: Credentials,
    /// `client_id` and `client_secret` in the form body.
    post: Credentials,
    /// Public client: `client_id` only. An authorization-code exchange also
    /// requires the S256 `code_verifier`.
    none: struct {
        client_id: []const u8,
        code_verifier: ?[]const u8 = null,
    },
};

pub const Credentials = struct {
    client_id: []const u8,
    client_secret: Secret,
};

pub fn writeAuthorizationCodeBody(
    writer: *std.Io.Writer,
    auth: TokenAuth,
    exchange: AuthorizationCodeExchange,
) Error![]const u8 {
    if (exchange.code.len == 0) return error.InvalidCode;
    try validateRedirectUri(exchange.redirect_uri);
    switch (auth) {
        .none => |public| {
            if (exchange.code_verifier == null and public.code_verifier == null) return error.MissingCodeVerifier;
        },
        else => {},
    }

    var form = FormBuilder{ .writer = writer };
    try form.add("grant_type", Grant.authorization_code.wire());
    try form.add("code", exchange.code);
    try form.add("redirect_uri", exchange.redirect_uri);
    try writeAuthFields(&form, auth, exchange.code_verifier);
    return form.done();
}

pub fn writeRefreshBody(
    writer: *std.Io.Writer,
    auth: TokenAuth,
    refresh: RefreshRequest,
) Error![]const u8 {
    try validateOpaqueToken(refresh.refresh_token, error.InvalidToken);
    var form = FormBuilder{ .writer = writer };
    try form.add("grant_type", Grant.refresh_token.wire());
    try form.add("refresh_token", refresh.refresh_token);
    try writeAuthFields(&form, auth, null);
    return form.done();
}

pub fn writeClientCredentialsBody(
    writer: *std.Io.Writer,
    auth: TokenAuth,
    credentials: ClientCredentialsRequest,
) Error![]const u8 {
    try validateScopes(.client_credentials, credentials.scopes);
    switch (auth) {
        // Documented: the client credentials grant requires client authentication.
        .none => return error.ClientAuthenticationRequired,
        else => {},
    }
    var form = FormBuilder{ .writer = writer };
    try form.add("grant_type", Grant.client_credentials.wire());
    try form.addScopes("scope", credentials.scopes);
    try writeAuthFields(&form, auth, null);
    return form.done();
}

pub fn writeRevokeBody(writer: *std.Io.Writer, revoke: RevokeRequest) Error![]const u8 {
    try validateOpaqueToken(revoke.token, error.InvalidToken);
    var form = FormBuilder{ .writer = writer };
    try form.add("token", revoke.token);
    if (revoke.token_type_hint) |hint| {
        try form.add("token_type_hint", switch (hint) {
            .access_token => "access_token",
            .refresh_token => "refresh_token",
        });
    }
    return form.done();
}

/// Writes the `Authorization: Basic ...` value for token and revocation
/// requests. The returned buffer contains the credential, so never log it.
pub fn writeBasicAuth(
    writer: *std.Io.Writer,
    credentials: Credentials,
) Error![]const u8 {
    try validateClientId(credentials.client_id);
    try validateSecret(credentials.client_secret.value);

    writer.writeAll("Basic ") catch return error.WriteFailed;
    const encoder = std.base64.standard.Encoder;
    const raw_len = credentials.client_id.len + 1 + credentials.client_secret.value.len;
    var raw_buffer: [1024]u8 = undefined;
    if (raw_len > raw_buffer.len) return error.BufferTooSmall;
    const raw = raw_buffer[0..raw_len];
    @memcpy(raw[0..credentials.client_id.len], credentials.client_id);
    raw[credentials.client_id.len] = ':';
    @memcpy(raw[credentials.client_id.len + 1 ..], credentials.client_secret.value);

    var encoded: [1400]u8 = undefined;
    const encoded_len = encoder.calcSize(raw.len);
    if (encoded_len > encoded.len) return error.BufferTooSmall;
    writer.writeAll(encoder.encode(encoded[0..encoded_len], raw)) catch return error.WriteFailed;
    @memset(&raw_buffer, 0);
    @memset(encoded[0..encoded_len], 0);
    return writer.buffered();
}

fn writeAuthFields(form: *FormBuilder, auth: TokenAuth, code_verifier: ?[]const u8) Error!void {
    switch (auth) {
        .basic => {},
        .post => |credentials| {
            try validateClientId(credentials.client_id);
            try validateSecret(credentials.client_secret.value);
            try form.add("client_id", credentials.client_id);
            try form.add("client_secret", credentials.client_secret.value);
        },
        .none => |public| {
            try validateClientId(public.client_id);
            const verifier = public.code_verifier orelse code_verifier;
            try form.add("client_id", public.client_id);
            if (verifier) |value| try form.add("code_verifier", value);
        },
    }
}

pub const AccessTokenResponse = struct {
    access_token: []const u8,
    token_type: []const u8,
    expires_in: i64,
    refresh_token: ?[]const u8 = null,
    scope: []const u8,
    /// Present for `webhook.incoming`; left raw in this batch.
    webhook: ?std.json.Value = null,
};

/// Parses a token endpoint response. A non-2xx status is rejected before any
/// parsing, so callers cannot accidentally treat an error body as a renewal.
pub fn parseAccessTokenResponse(
    allocator: std.mem.Allocator,
    status: u16,
    body: []const u8,
) !std.json.Parsed(AccessTokenResponse) {
    if (status < 200 or status >= 300) return error.TokenEndpointRejected;
    return std.json.parseFromSlice(AccessTokenResponse, allocator, body, .{
        .ignore_unknown_fields = true,
    });
}

/// Callback checks required by the official guide. `state` binds the response
/// to the caller's request and `iss` identifies Discord as the issuer.
pub fn validateCallback(expected_state: ?[]const u8, returned_state: ?[]const u8) Error!void {
    if (expected_state == null and returned_state == null) return;
    const expected = expected_state orelse return error.StateMismatch;
    const returned = returned_state orelse return error.StateMismatch;
    if (expected.len != returned.len) return error.StateMismatch;
    var diff: u8 = 0;
    for (expected, returned) |a, b| diff |= a ^ b;
    if (diff != 0) return error.StateMismatch;
}

pub fn validateIssuer(issuer: ?[]const u8) Error!void {
    const value = issuer orelse return error.InvalidIssuer;
    if (!std.mem.eql(u8, value, endpoints.issuer)) return error.InvalidIssuer;
}

pub fn validateClientId(client_id: []const u8) Error!void {
    if (client_id.len == 0) return error.MissingClientId;
    if (client_id.len > 20) return error.InvalidClientId;
    for (client_id) |c| {
        if (!std.ascii.isDigit(c)) return error.InvalidClientId;
    }
}

fn validateSecret(secret: []const u8) Error!void {
    if (secret.len == 0 or secret.len > 128) return error.InvalidSecret;
    for (secret) |c| {
        if (c == '\r' or c == '\n' or c == 0 or c == ' ') return error.InvalidSecret;
    }
}

fn validateOpaqueToken(value: []const u8, comptime err: Error) Error!void {
    if (value.len == 0 or value.len > 512) return err;
    for (value) |c| {
        if (c == '\r' or c == '\n' or c == 0) return err;
    }
}

fn validateStateValue(state: []const u8) Error!void {
    if (state.len == 0 or state.len > 1024) return error.InvalidState;
    for (state) |c| {
        if (c == '\r' or c == '\n' or c == 0) return error.InvalidState;
    }
}

pub fn validateRedirectUri(uri: []const u8) Error!void {
    if (uri.len == 0) return error.MissingRedirectUri;
    if (uri.len > 2048) return error.InvalidRedirectUri;
    for (uri) |c| {
        if (c == '\r' or c == '\n' or c == 0) return error.InvalidRedirectUri;
    }
    const parsed = std.Uri.parse(uri) catch return error.InvalidRedirectUri;
    if (parsed.host == null) return error.InvalidRedirectUri;
    if (!std.ascii.eqlIgnoreCase(parsed.scheme, "https") and !std.ascii.eqlIgnoreCase(parsed.scheme, "http")) {
        return error.InvalidRedirectUri;
    }
    if (parsed.fragment != null) return error.InvalidRedirectUri;
}

fn validateCodeChallenge(challenge: []const u8) Error!void {
    if (challenge.len < 43 or challenge.len > 128) return error.InvalidCodeChallenge;
    for (challenge) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') return error.InvalidCodeChallenge;
    }
}

pub fn validateScopes(grant: Grant, scopes: []const OAuth2Scopes) Error!void {
    if (scopes.len == 0) return error.EmptyScopes;
    for (scopes, 0..) |scope, index| {
        for (scopes[0..index]) |earlier| {
            if (earlier == scope) return error.DuplicateScope;
        }
        switch (grant) {
            // Documented restriction: role_connections.write needs user consent.
            .implicit => if (scope == .role_connections_write) return error.ScopeNotAllowedForGrant,
            // A bot install and webhook creation both require a user in the
            // loop, so a client-credentials token cannot grant them.
            .client_credentials => switch (scope) {
                .bot, .webhook_incoming => return error.ScopeNotAllowedForGrant,
                else => {},
            },
            .authorization_code, .refresh_token => {},
        }
    }
}

fn hasScope(scopes: []const OAuth2Scopes, needle: OAuth2Scopes) bool {
    for (scopes) |scope| {
        if (scope == needle) return true;
    }
    return false;
}

const FormBuilder = struct {
    writer: *std.Io.Writer,
    count: usize = 0,
    separator: u8 = 0,

    fn begin(self: *FormBuilder) Error!void {
        if (self.count == 0 and self.separator != 0) {
            self.writer.writeByte(self.separator) catch return error.WriteFailed;
        } else if (self.count != 0) {
            self.writer.writeByte('&') catch return error.WriteFailed;
        }
        self.count += 1;
    }

    fn add(self: *FormBuilder, name: []const u8, value: []const u8) Error!void {
        try self.begin();
        request.encodeQueryValue(self.writer, name) catch return error.WriteFailed;
        self.writer.writeByte('=') catch return error.WriteFailed;
        request.encodeQueryValue(self.writer, value) catch return error.WriteFailed;
    }

    fn addScopes(self: *FormBuilder, name: []const u8, scopes: []const OAuth2Scopes) Error!void {
        try self.begin();
        request.encodeQueryValue(self.writer, name) catch return error.WriteFailed;
        self.writer.writeByte('=') catch return error.WriteFailed;
        for (scopes, 0..) |scope, index| {
            if (index != 0) {
                self.writer.writeAll("%20") catch return error.WriteFailed;
            }
            request.encodeQueryValue(self.writer, scope.wire()) catch return error.WriteFailed;
        }
    }

    fn done(self: *FormBuilder) []const u8 {
        return self.writer.buffered();
    }
};

test "authorization URL matches the documented parameter order" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const url = try writeAuthorizationUrl(&writer, .{
        .client_id = "157730590492196864",
        .scopes = &.{ .identify, .guilds_join },
        .state = "15773059ghq9183habn",
        .redirect_uri = "https://nicememe.website",
        .prompt = .consent,
        .integration_type = .guild_install,
    });
    try std.testing.expectEqualStrings(
        "https://discord.com/oauth2/authorize?response_type=code&client_id=157730590492196864" ++
            "&scope=identify%20guilds.join&state=15773059ghq9183habn&redirect_uri=https%3A%2F%2Fnicememe.website" ++
            "&prompt=consent&integration_type=0",
        url,
    );
}

test "bot install omits response_type and carries permissions" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const url = try writeAuthorizationUrl(&writer, .{
        .client_id = "123456789012345678",
        .scopes = &.{.bot},
        .response_type = null,
        .permissions = 2048,
        .guild_id = "987654321098765432",
        .disable_guild_select = true,
    });
    try std.testing.expectEqualStrings(
        "https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot" ++
            "&permissions=2048&guild_id=987654321098765432&disable_guild_select=true",
        url,
    );
}

test "omitting response_type without bot scope is rejected" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.MissingResponseType,
        writeAuthorizationUrl(&writer, .{
            .client_id = "123456789012345678",
            .scopes = &.{.identify},
            .response_type = null,
        }),
    );
}

test "PKCE challenge is sent with S256 only" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const challenge = "Eb9PKXMFcHk0lVdEq4lPqRkOho2uMBTTrp4p0O4dtAc";
    const url = try writeAuthorizationUrl(&writer, .{
        .client_id = "123456789012345678",
        .scopes = &.{.openid},
        .code_challenge = challenge,
    });
    try std.testing.expect(std.mem.endsWith(u8, url, "&code_challenge_method=S256"));

    try std.testing.expectError(
        error.InvalidCodeChallenge,
        writeAuthorizationUrl(&writer, .{
            .client_id = "123456789012345678",
            .scopes = &.{.openid},
            .code_challenge = "too-short",
        }),
    );
}

test "token bodies use form encoding and keep basic secrets out of the body" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const body = try writeAuthorizationCodeBody(&writer, .{
        .basic = .{ .client_id = "332269999912132097", .client_secret = .{ .value = "s3cr3t" } },
    }, .{
        .code = "NhhvTDYsFcdgNLnnLijcl7Ku7bEEeee",
        .redirect_uri = "https://nicememe.website",
    });
    try std.testing.expectEqualStrings(
        "grant_type=authorization_code&code=NhhvTDYsFcdgNLnnLijcl7Ku7bEEeee" ++
            "&redirect_uri=https%3A%2F%2Fnicememe.website",
        body,
    );
    try std.testing.expect(std.mem.indexOf(u8, body, "s3cr3t") == null);
}

test "public client exchange sends client_id and verifier" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const body = try writeAuthorizationCodeBody(&writer, .{
        .none = .{ .client_id = "123456789012345678", .code_verifier = "verifier-value" },
    }, .{
        .code = "abc",
        .redirect_uri = "http://localhost:3000/callback",
    });
    try std.testing.expect(std.mem.startsWith(u8, body, "grant_type=authorization_code&code=abc"));
    try std.testing.expect(std.mem.endsWith(u8, body, "&client_id=123456789012345678&code_verifier=verifier-value"));
}

test "basic auth value is standard base64 and redaction hides the secret" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const value = try writeBasicAuth(&writer, .{
        .client_id = "332269999912132097",
        .client_secret = .{ .value = "937it3ow87i4ery69876wqire" },
    });
    try std.testing.expectEqualStrings("Basic MzMyMjY5OTk5OTEyMTMyMDk3OjkzN2l0M293ODdpNGVyeTY5ODc2d3FpcmU=", value);
    try std.testing.expectEqualStrings("<redacted>", Secret.redacted_text);
    try std.testing.expectEqualStrings("<redacted>", (Secret{ .value = "937it3ow87i4ery69876wqire" }).redacted());
}

test "client credentials reject install-only scopes" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.ScopeNotAllowedForGrant,
        writeClientCredentialsBody(&writer, .{
            .basic = .{ .client_id = "123456789012345678", .client_secret = .{ .value = "x" } },
        }, .{ .scopes = &.{.bot} }),
    );
}

test "public client exchange requires a PKCE verifier" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.MissingCodeVerifier,
        writeAuthorizationCodeBody(&writer, .{
            .none = .{ .client_id = "123456789012345678" },
        }, .{
            .code = "abc",
            .redirect_uri = "http://localhost:3000/callback",
        }),
    );
}

test "client credentials require client authentication" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.ClientAuthenticationRequired,
        writeClientCredentialsBody(&writer, .{
            .none = .{ .client_id = "123456789012345678" },
        }, .{ .scopes = &.{.identify} }),
    );
}

test "refresh body rejects an empty token and duplicate scopes are errors" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.InvalidToken,
        writeRefreshBody(&writer, .{ .basic = .{
            .client_id = "123456789012345678",
            .client_secret = .{ .value = "x" },
        } }, .{ .refresh_token = "" }),
    );
    try std.testing.expectError(
        error.DuplicateScope,
        validateScopes(.authorization_code, &.{ .identify, .identify }),
    );
}

test "callback state and issuer checks" {
    try validateCallback("abc", "abc");
    try validateCallback(null, null);
    try std.testing.expectError(error.StateMismatch, validateCallback("abc", "abd"));
    try std.testing.expectError(error.StateMismatch, validateCallback("abc", null));
    try std.testing.expectError(error.StateMismatch, validateCallback(null, "abc"));

    try validateIssuer("https://discord.com");
    try std.testing.expectError(error.InvalidIssuer, validateIssuer(null));
    try std.testing.expectError(error.InvalidIssuer, validateIssuer("https://evil.test"));
}

test "non-2xx token responses are rejected before parsing" {
    try std.testing.expectError(
        error.TokenEndpointRejected,
        parseAccessTokenResponse(std.testing.allocator, 400, "{\"access_token\":\"fake\"}"),
    );

    var parsed = try parseAccessTokenResponse(std.testing.allocator, 200,
        \\{"access_token":"6qrZcUqja7812RVdnEKjpzOL4CvHBFG","token_type":"Bearer","expires_in":604800,"refresh_token":"D43f5y0ahjqew82jZ4NViEr2YafMKhue","scope":"identify"}
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 604800), parsed.value.expires_in);
}
