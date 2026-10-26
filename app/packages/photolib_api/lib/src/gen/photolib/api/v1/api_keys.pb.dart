// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/api_keys.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

import 'api_keys.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'api_keys.pbenum.dart';

/// A credential for scripts, the CLI and other programs, which send its secret as `Authorization: Bearer <secret>`.
class ApiKey extends $pb.GeneratedMessage {
  factory ApiKey({
    $core.String? apiKeyId,
    $core.String? name,
    $core.Iterable<ApiKeyScope>? scopes,
    $0.Timestamp? expiresAt,
    $core.int? requestsPerMinute,
    $0.Timestamp? createdAt,
    $0.Timestamp? lastUsedAt,
    $0.Timestamp? revokedAt,
  }) {
    final result = ApiKey._();
    if (apiKeyId != null) result.apiKeyId = apiKeyId;
    if (name != null) result.name = name;
    if (scopes != null) result.scopes.addAll(scopes);
    if (expiresAt != null) result.expiresAt = expiresAt;
    if (requestsPerMinute != null) result.requestsPerMinute = requestsPerMinute;
    if (createdAt != null) result.createdAt = createdAt;
    if (lastUsedAt != null) result.lastUsedAt = lastUsedAt;
    if (revokedAt != null) result.revokedAt = revokedAt;
    return result;
  }

  ApiKey._();

  factory ApiKey.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApiKey()..mergeFromBuffer(data, registry);
  factory ApiKey.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApiKey()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ApiKey',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ApiKey.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'apiKeyId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..pc<ApiKeyScope>(3, _omitFieldNames ? '' : 'scopes', $pb.PbFieldType.KE,
        valueOf: ApiKeyScope.valueOf,
        enumValues: ApiKeyScope.values,
        defaultEnumValue: ApiKeyScope.API_KEY_SCOPE_UNSPECIFIED)
    ..aOM<$0.Timestamp>(4, _omitFieldNames ? '' : 'expiresAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aI(5, _omitFieldNames ? '' : 'requestsPerMinute',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<$0.Timestamp>(6, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<$0.Timestamp>(7, _omitFieldNames ? '' : 'lastUsedAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<$0.Timestamp>(8, _omitFieldNames ? '' : 'revokedAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApiKey clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApiKey copyWith(void Function(ApiKey) updates) =>
      super.copyWith((message) => updates(message as ApiKey)) as ApiKey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ApiKey() / ApiKey.new instead')
  static ApiKey create() => ApiKey._();
  static $pb.GeneratedMessage $_createMessage() => ApiKey._();
  @$core.override
  ApiKey createEmptyInstance() => ApiKey._();
  @$core.pragma('dart2js:noInline')
  static ApiKey getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ApiKey>(ApiKey.$_createMessage);
  static ApiKey? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get apiKeyId => $_getSZ(0);
  @$pb.TagNumber(1)
  set apiKeyId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApiKeyId() => $_has(0);
  @$pb.TagNumber(1)
  void clearApiKeyId() => $_clearField(1);

  /// What its owner calls it: 1 to 100 printable characters.
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// At least one.
  @$pb.TagNumber(3)
  $pb.PbList<ApiKeyScope> get scopes => $_getList(2);

  /// Required, and in the future when the key is created.
  @$pb.TagNumber(4)
  $0.Timestamp get expiresAt => $_getN(3);
  @$pb.TagNumber(4)
  set expiresAt($0.Timestamp value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasExpiresAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpiresAt() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.Timestamp ensureExpiresAt() => $_ensure(3);

  /// Requests the key may make per minute, in bursts of up to as many: 1 to 60000; 0 when creating means 600.
  @$pb.TagNumber(5)
  $core.int get requestsPerMinute => $_getIZ(4);
  @$pb.TagNumber(5)
  set requestsPerMinute($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRequestsPerMinute() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequestsPerMinute() => $_clearField(5);

  @$pb.TagNumber(6)
  $0.Timestamp get createdAt => $_getN(5);
  @$pb.TagNumber(6)
  set createdAt($0.Timestamp value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasCreatedAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreatedAt() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.Timestamp ensureCreatedAt() => $_ensure(5);

  /// The last request the key made, to the minute; absent until then.
  @$pb.TagNumber(7)
  $0.Timestamp get lastUsedAt => $_getN(6);
  @$pb.TagNumber(7)
  set lastUsedAt($0.Timestamp value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasLastUsedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearLastUsedAt() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.Timestamp ensureLastUsedAt() => $_ensure(6);

  /// Absent until the key is revoked.
  @$pb.TagNumber(8)
  $0.Timestamp get revokedAt => $_getN(7);
  @$pb.TagNumber(8)
  set revokedAt($0.Timestamp value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasRevokedAt() => $_has(7);
  @$pb.TagNumber(8)
  void clearRevokedAt() => $_clearField(8);
  @$pb.TagNumber(8)
  $0.Timestamp ensureRevokedAt() => $_ensure(7);
}

/// Asks for the caller's keys.
class ListApiKeysRequest extends $pb.GeneratedMessage {
  factory ListApiKeysRequest() => ListApiKeysRequest._();

  ListApiKeysRequest._();

  factory ListApiKeysRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListApiKeysRequest()..mergeFromBuffer(data, registry);
  factory ListApiKeysRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListApiKeysRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListApiKeysRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListApiKeysRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListApiKeysRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListApiKeysRequest copyWith(void Function(ListApiKeysRequest) updates) =>
      super.copyWith((message) => updates(message as ListApiKeysRequest))
          as ListApiKeysRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListApiKeysRequest() / ListApiKeysRequest.new instead')
  static ListApiKeysRequest create() => ListApiKeysRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListApiKeysRequest._();
  @$core.override
  ListApiKeysRequest createEmptyInstance() => ListApiKeysRequest._();
  @$core.pragma('dart2js:noInline')
  static ListApiKeysRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListApiKeysRequest>(
          ListApiKeysRequest.$_createMessage);
  static ListApiKeysRequest? _defaultInstance;
}

/// The caller's keys.
class ListApiKeysResponse extends $pb.GeneratedMessage {
  factory ListApiKeysResponse({
    $core.Iterable<ApiKey>? apiKeys,
  }) {
    final result = ListApiKeysResponse._();
    if (apiKeys != null) result.apiKeys.addAll(apiKeys);
    return result;
  }

  ListApiKeysResponse._();

  factory ListApiKeysResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListApiKeysResponse()..mergeFromBuffer(data, registry);
  factory ListApiKeysResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListApiKeysResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListApiKeysResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListApiKeysResponse.$_createMessage)
    ..pPM<ApiKey>(1, _omitFieldNames ? '' : 'apiKeys',
        subBuilder: ApiKey.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListApiKeysResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListApiKeysResponse copyWith(void Function(ListApiKeysResponse) updates) =>
      super.copyWith((message) => updates(message as ListApiKeysResponse))
          as ListApiKeysResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListApiKeysResponse() / ListApiKeysResponse.new instead')
  static ListApiKeysResponse create() => ListApiKeysResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListApiKeysResponse._();
  @$core.override
  ListApiKeysResponse createEmptyInstance() => ListApiKeysResponse._();
  @$core.pragma('dart2js:noInline')
  static ListApiKeysResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListApiKeysResponse>(
          ListApiKeysResponse.$_createMessage);
  static ListApiKeysResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ApiKey> get apiKeys => $_getList(0);
}

/// The key to create.
class CreateApiKeyRequest extends $pb.GeneratedMessage {
  factory CreateApiKeyRequest({
    ApiKey? apiKey,
  }) {
    final result = CreateApiKeyRequest._();
    if (apiKey != null) result.apiKey = apiKey;
    return result;
  }

  CreateApiKeyRequest._();

  factory CreateApiKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateApiKeyRequest()..mergeFromBuffer(data, registry);
  factory CreateApiKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateApiKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateApiKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateApiKeyRequest.$_createMessage)
    ..aOM<ApiKey>(1, _omitFieldNames ? '' : 'apiKey',
        subBuilder: ApiKey.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateApiKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateApiKeyRequest copyWith(void Function(CreateApiKeyRequest) updates) =>
      super.copyWith((message) => updates(message as CreateApiKeyRequest))
          as CreateApiKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use CreateApiKeyRequest() / CreateApiKeyRequest.new instead')
  static CreateApiKeyRequest create() => CreateApiKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => CreateApiKeyRequest._();
  @$core.override
  CreateApiKeyRequest createEmptyInstance() => CreateApiKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateApiKeyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateApiKeyRequest>(
          CreateApiKeyRequest.$_createMessage);
  static CreateApiKeyRequest? _defaultInstance;

  /// Only name, scopes, expires_at and requests_per_minute are read.
  @$pb.TagNumber(1)
  ApiKey get apiKey => $_getN(0);
  @$pb.TagNumber(1)
  set apiKey(ApiKey value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasApiKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearApiKey() => $_clearField(1);
  @$pb.TagNumber(1)
  ApiKey ensureApiKey() => $_ensure(0);
}

/// The key created, and its secret.
class CreateApiKeyResponse extends $pb.GeneratedMessage {
  factory CreateApiKeyResponse({
    ApiKey? apiKey,
    $core.String? secret,
  }) {
    final result = CreateApiKeyResponse._();
    if (apiKey != null) result.apiKey = apiKey;
    if (secret != null) result.secret = secret;
    return result;
  }

  CreateApiKeyResponse._();

  factory CreateApiKeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateApiKeyResponse()..mergeFromBuffer(data, registry);
  factory CreateApiKeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateApiKeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateApiKeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateApiKeyResponse.$_createMessage)
    ..aOM<ApiKey>(1, _omitFieldNames ? '' : 'apiKey',
        subBuilder: ApiKey.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'secret')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateApiKeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateApiKeyResponse copyWith(void Function(CreateApiKeyResponse) updates) =>
      super.copyWith((message) => updates(message as CreateApiKeyResponse))
          as CreateApiKeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateApiKeyResponse() / CreateApiKeyResponse.new instead')
  static CreateApiKeyResponse create() => CreateApiKeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => CreateApiKeyResponse._();
  @$core.override
  CreateApiKeyResponse createEmptyInstance() => CreateApiKeyResponse._();
  @$core.pragma('dart2js:noInline')
  static CreateApiKeyResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateApiKeyResponse>(
          CreateApiKeyResponse.$_createMessage);
  static CreateApiKeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  ApiKey get apiKey => $_getN(0);
  @$pb.TagNumber(1)
  set apiKey(ApiKey value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasApiKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearApiKey() => $_clearField(1);
  @$pb.TagNumber(1)
  ApiKey ensureApiKey() => $_ensure(0);

  /// `plk_` and 64 lowercase hexadecimal digits.
  @$pb.TagNumber(2)
  $core.String get secret => $_getSZ(1);
  @$pb.TagNumber(2)
  set secret($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearSecret() => $_clearField(2);
}

/// The key to revoke.
class RevokeApiKeyRequest extends $pb.GeneratedMessage {
  factory RevokeApiKeyRequest({
    $core.String? apiKeyId,
  }) {
    final result = RevokeApiKeyRequest._();
    if (apiKeyId != null) result.apiKeyId = apiKeyId;
    return result;
  }

  RevokeApiKeyRequest._();

  factory RevokeApiKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeApiKeyRequest()..mergeFromBuffer(data, registry);
  factory RevokeApiKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeApiKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeApiKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: RevokeApiKeyRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'apiKeyId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeApiKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeApiKeyRequest copyWith(void Function(RevokeApiKeyRequest) updates) =>
      super.copyWith((message) => updates(message as RevokeApiKeyRequest))
          as RevokeApiKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use RevokeApiKeyRequest() / RevokeApiKeyRequest.new instead')
  static RevokeApiKeyRequest create() => RevokeApiKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => RevokeApiKeyRequest._();
  @$core.override
  RevokeApiKeyRequest createEmptyInstance() => RevokeApiKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static RevokeApiKeyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeApiKeyRequest>(
          RevokeApiKeyRequest.$_createMessage);
  static RevokeApiKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get apiKeyId => $_getSZ(0);
  @$pb.TagNumber(1)
  set apiKeyId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApiKeyId() => $_has(0);
  @$pb.TagNumber(1)
  void clearApiKeyId() => $_clearField(1);
}

/// The revoked key.
class RevokeApiKeyResponse extends $pb.GeneratedMessage {
  factory RevokeApiKeyResponse({
    ApiKey? apiKey,
  }) {
    final result = RevokeApiKeyResponse._();
    if (apiKey != null) result.apiKey = apiKey;
    return result;
  }

  RevokeApiKeyResponse._();

  factory RevokeApiKeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeApiKeyResponse()..mergeFromBuffer(data, registry);
  factory RevokeApiKeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeApiKeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeApiKeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: RevokeApiKeyResponse.$_createMessage)
    ..aOM<ApiKey>(1, _omitFieldNames ? '' : 'apiKey',
        subBuilder: ApiKey.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeApiKeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeApiKeyResponse copyWith(void Function(RevokeApiKeyResponse) updates) =>
      super.copyWith((message) => updates(message as RevokeApiKeyResponse))
          as RevokeApiKeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RevokeApiKeyResponse() / RevokeApiKeyResponse.new instead')
  static RevokeApiKeyResponse create() => RevokeApiKeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => RevokeApiKeyResponse._();
  @$core.override
  RevokeApiKeyResponse createEmptyInstance() => RevokeApiKeyResponse._();
  @$core.pragma('dart2js:noInline')
  static RevokeApiKeyResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeApiKeyResponse>(
          RevokeApiKeyResponse.$_createMessage);
  static RevokeApiKeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  ApiKey get apiKey => $_getN(0);
  @$pb.TagNumber(1)
  set apiKey(ApiKey value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasApiKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearApiKey() => $_clearField(1);
  @$pb.TagNumber(1)
  ApiKey ensureApiKey() => $_ensure(0);
}

/// The caller's API keys, which only the account signed in, never a key, manages.
class ApiKeyServiceApi {
  final $pb.RpcClient _client;

  ApiKeyServiceApi(this._client);

  /// Returns the caller's keys, revoked and expired ones included, newest first.
  $async.Future<ListApiKeysResponse> listApiKeys(
          $pb.ClientContext? ctx, ListApiKeysRequest request) =>
      _client.invoke<ListApiKeysResponse>(
          ctx, 'ApiKeyService', 'ListApiKeys', request, ListApiKeysResponse());

  /// Creates a key for the caller and returns its secret, which the server keeps only hashed and never shows again.
  $async.Future<CreateApiKeyResponse> createApiKey(
          $pb.ClientContext? ctx, CreateApiKeyRequest request) =>
      _client.invoke<CreateApiKeyResponse>(ctx, 'ApiKeyService', 'CreateApiKey',
          request, CreateApiKeyResponse());

  /// Revokes one of the caller's keys at once; revoking a revoked key changes nothing.
  $async.Future<RevokeApiKeyResponse> revokeApiKey(
          $pb.ClientContext? ctx, RevokeApiKeyRequest request) =>
      _client.invoke<RevokeApiKeyResponse>(ctx, 'ApiKeyService', 'RevokeApiKey',
          request, RevokeApiKeyResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
