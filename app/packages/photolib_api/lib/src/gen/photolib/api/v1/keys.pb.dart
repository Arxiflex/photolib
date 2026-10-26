// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/keys.proto.

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

import 'keys.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'keys.pbenum.dart';

/// The AMK wrapped for one way in.
class UnlockPath extends $pb.GeneratedMessage {
  factory UnlockPath({
    UnlockKind? kind,
    $core.List<$core.int>? wrap,
    $core.List<$core.int>? params,
    $0.Timestamp? createdAt,
  }) {
    final result = UnlockPath._();
    if (kind != null) result.kind = kind;
    if (wrap != null) result.wrap = wrap;
    if (params != null) result.params = params;
    if (createdAt != null) result.createdAt = createdAt;
    return result;
  }

  UnlockPath._();

  factory UnlockPath.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UnlockPath()..mergeFromBuffer(data, registry);
  factory UnlockPath.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UnlockPath()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UnlockPath',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: UnlockPath.$_createMessage)
    ..aE<UnlockKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: UnlockKind.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'wrap', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'params', $pb.PbFieldType.OY)
    ..aOM<$0.Timestamp>(4, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnlockPath clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnlockPath copyWith(void Function(UnlockPath) updates) =>
      super.copyWith((message) => updates(message as UnlockPath)) as UnlockPath;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UnlockPath() / UnlockPath.new instead')
  static UnlockPath create() => UnlockPath._();
  static $pb.GeneratedMessage $_createMessage() => UnlockPath._();
  @$core.override
  UnlockPath createEmptyInstance() => UnlockPath._();
  @$core.pragma('dart2js:noInline')
  static UnlockPath getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UnlockPath>(UnlockPath.$_createMessage);
  static UnlockPath? _defaultInstance;

  @$pb.TagNumber(1)
  UnlockKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(UnlockKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// A PLW of the AMK (wrapped type 1) under the path's key: its wrapped_key_id is the AMK's key_id, as in every
  /// path's, and its wrapping_key_id the path key's. Empty in GetKeys for the password.
  @$pb.TagNumber(2)
  $core.List<$core.int> get wrap => $_getN(1);
  @$pb.TagNumber(2)
  set wrap($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWrap() => $_has(1);
  @$pb.TagNumber(2)
  void clearWrap() => $_clearField(2);

  /// The password's Argon2id parameters, 26 bytes within the account policy; empty for other kinds.
  @$pb.TagNumber(3)
  $core.List<$core.int> get params => $_getN(2);
  @$pb.TagNumber(3)
  set params($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasParams() => $_has(2);
  @$pb.TagNumber(3)
  void clearParams() => $_clearField(3);

  @$pb.TagNumber(4)
  $0.Timestamp get createdAt => $_getN(3);
  @$pb.TagNumber(4)
  set createdAt($0.Timestamp value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCreatedAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearCreatedAt() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.Timestamp ensureCreatedAt() => $_ensure(3);
}

/// An account's keys.
class AccountKeys extends $pb.GeneratedMessage {
  factory AccountKeys({
    $core.List<$core.int>? identity,
    $core.List<$core.int>? signingKey,
    $core.List<$core.int>? decryptionKey,
    $core.Iterable<UnlockPath>? paths,
    $0.Timestamp? recoveryVerifiedAt,
    $0.Timestamp? drillDueAt,
    $core.bool? ready,
  }) {
    final result = AccountKeys._();
    if (identity != null) result.identity = identity;
    if (signingKey != null) result.signingKey = signingKey;
    if (decryptionKey != null) result.decryptionKey = decryptionKey;
    if (paths != null) result.paths.addAll(paths);
    if (recoveryVerifiedAt != null)
      result.recoveryVerifiedAt = recoveryVerifiedAt;
    if (drillDueAt != null) result.drillDueAt = drillDueAt;
    if (ready != null) result.ready = ready;
    return result;
  }

  AccountKeys._();

  factory AccountKeys.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AccountKeys()..mergeFromBuffer(data, registry);
  factory AccountKeys.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AccountKeys()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AccountKeys',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: AccountKeys.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'identity', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'signingKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'decryptionKey', $pb.PbFieldType.OY)
    ..pPM<UnlockPath>(4, _omitFieldNames ? '' : 'paths',
        subBuilder: UnlockPath.$_createMessage)
    ..aOM<$0.Timestamp>(5, _omitFieldNames ? '' : 'recoveryVerifiedAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<$0.Timestamp>(6, _omitFieldNames ? '' : 'drillDueAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOB(7, _omitFieldNames ? '' : 'ready')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AccountKeys clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AccountKeys copyWith(void Function(AccountKeys) updates) =>
      super.copyWith((message) => updates(message as AccountKeys))
          as AccountKeys;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AccountKeys() / AccountKeys.new instead')
  static AccountKeys create() => AccountKeys._();
  static $pb.GeneratedMessage $_createMessage() => AccountKeys._();
  @$core.override
  AccountKeys createEmptyInstance() => AccountKeys._();
  @$core.pragma('dart2js:noInline')
  static AccountKeys getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AccountKeys>(
          AccountKeys.$_createMessage);
  static AccountKeys? _defaultInstance;

  /// The genesis entry of the account's identity log (a PLS signed by its identity signing key).
  @$pb.TagNumber(1)
  $core.List<$core.int> get identity => $_getN(0);
  @$pb.TagNumber(1)
  set identity($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIdentity() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdentity() => $_clearField(1);

  /// The seeds of the identity's signing and decryption keys, each a PLW under the AMK (wrapped types 8 and 9).
  @$pb.TagNumber(2)
  $core.List<$core.int> get signingKey => $_getN(1);
  @$pb.TagNumber(2)
  set signingKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSigningKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearSigningKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get decryptionKey => $_getN(2);
  @$pb.TagNumber(3)
  set decryptionKey($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDecryptionKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearDecryptionKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<UnlockPath> get paths => $_getList(3);

  /// When the recovery kit was last verified; unset until it is.
  @$pb.TagNumber(5)
  $0.Timestamp get recoveryVerifiedAt => $_getN(4);
  @$pb.TagNumber(5)
  set recoveryVerifiedAt($0.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasRecoveryVerifiedAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecoveryVerifiedAt() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.Timestamp ensureRecoveryVerifiedAt() => $_ensure(4);

  /// When the next recovery drill is due: six months after the last verification.
  @$pb.TagNumber(6)
  $0.Timestamp get drillDueAt => $_getN(5);
  @$pb.TagNumber(6)
  set drillDueAt($0.Timestamp value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasDrillDueAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearDrillDueAt() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.Timestamp ensureDrillDueAt() => $_ensure(5);

  /// Two unlock paths and a verified recovery kit: the server accepts private uploads.
  @$pb.TagNumber(7)
  $core.bool get ready => $_getBF(6);
  @$pb.TagNumber(7)
  set ready($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasReady() => $_has(6);
  @$pb.TagNumber(7)
  void clearReady() => $_clearField(7);
}

/// Asks for the caller's keys.
class GetKeysRequest extends $pb.GeneratedMessage {
  factory GetKeysRequest() => GetKeysRequest._();

  GetKeysRequest._();

  factory GetKeysRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetKeysRequest()..mergeFromBuffer(data, registry);
  factory GetKeysRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetKeysRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetKeysRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetKeysRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetKeysRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetKeysRequest copyWith(void Function(GetKeysRequest) updates) =>
      super.copyWith((message) => updates(message as GetKeysRequest))
          as GetKeysRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetKeysRequest() / GetKeysRequest.new instead')
  static GetKeysRequest create() => GetKeysRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetKeysRequest._();
  @$core.override
  GetKeysRequest createEmptyInstance() => GetKeysRequest._();
  @$core.pragma('dart2js:noInline')
  static GetKeysRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetKeysRequest>(
          GetKeysRequest.$_createMessage);
  static GetKeysRequest? _defaultInstance;
}

/// The caller's keys, unset before CreateKeys.
class GetKeysResponse extends $pb.GeneratedMessage {
  factory GetKeysResponse({
    AccountKeys? keys,
    $core.bool? password,
    $core.String? userId,
  }) {
    final result = GetKeysResponse._();
    if (keys != null) result.keys = keys;
    if (password != null) result.password = password;
    if (userId != null) result.userId = userId;
    return result;
  }

  GetKeysResponse._();

  factory GetKeysResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetKeysResponse()..mergeFromBuffer(data, registry);
  factory GetKeysResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetKeysResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetKeysResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetKeysResponse.$_createMessage)
    ..aOM<AccountKeys>(1, _omitFieldNames ? '' : 'keys',
        subBuilder: AccountKeys.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'password')
    ..aOS(3, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetKeysResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetKeysResponse copyWith(void Function(GetKeysResponse) updates) =>
      super.copyWith((message) => updates(message as GetKeysResponse))
          as GetKeysResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetKeysResponse() / GetKeysResponse.new instead')
  static GetKeysResponse create() => GetKeysResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetKeysResponse._();
  @$core.override
  GetKeysResponse createEmptyInstance() => GetKeysResponse._();
  @$core.pragma('dart2js:noInline')
  static GetKeysResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetKeysResponse>(
          GetKeysResponse.$_createMessage);
  static GetKeysResponse? _defaultInstance;

  @$pb.TagNumber(1)
  AccountKeys get keys => $_getN(0);
  @$pb.TagNumber(1)
  set keys(AccountKeys value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKeys() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeys() => $_clearField(1);
  @$pb.TagNumber(1)
  AccountKeys ensureKeys() => $_ensure(0);

  /// The account has a password, which a password path needs: one that signs in with OpenID Connect sets one as its
  /// vault passphrase with StartPasswordSetup.
  @$pb.TagNumber(2)
  $core.bool get password => $_getBF(1);
  @$pb.TagNumber(2)
  set password($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => $_clearField(2);

  /// The caller's account id, which its identity log and wraps name.
  @$pb.TagNumber(3)
  $core.String get userId => $_getSZ(2);
  @$pb.TagNumber(3)
  set userId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(2);
  @$pb.TagNumber(3)
  void clearUserId() => $_clearField(3);
}

/// The keys a client made: the identity log's genesis for the caller, its key seeds wrapped under the AMK, and paths.
class CreateKeysRequest extends $pb.GeneratedMessage {
  factory CreateKeysRequest({
    $core.List<$core.int>? identity,
    $core.List<$core.int>? signingKey,
    $core.List<$core.int>? decryptionKey,
    $core.Iterable<UnlockPath>? paths,
  }) {
    final result = CreateKeysRequest._();
    if (identity != null) result.identity = identity;
    if (signingKey != null) result.signingKey = signingKey;
    if (decryptionKey != null) result.decryptionKey = decryptionKey;
    if (paths != null) result.paths.addAll(paths);
    return result;
  }

  CreateKeysRequest._();

  factory CreateKeysRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateKeysRequest()..mergeFromBuffer(data, registry);
  factory CreateKeysRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateKeysRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateKeysRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateKeysRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'identity', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'signingKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'decryptionKey', $pb.PbFieldType.OY)
    ..pPM<UnlockPath>(4, _omitFieldNames ? '' : 'paths',
        subBuilder: UnlockPath.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateKeysRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateKeysRequest copyWith(void Function(CreateKeysRequest) updates) =>
      super.copyWith((message) => updates(message as CreateKeysRequest))
          as CreateKeysRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CreateKeysRequest() / CreateKeysRequest.new instead')
  static CreateKeysRequest create() => CreateKeysRequest._();
  static $pb.GeneratedMessage $_createMessage() => CreateKeysRequest._();
  @$core.override
  CreateKeysRequest createEmptyInstance() => CreateKeysRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateKeysRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateKeysRequest>(
          CreateKeysRequest.$_createMessage);
  static CreateKeysRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get identity => $_getN(0);
  @$pb.TagNumber(1)
  set identity($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIdentity() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdentity() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get signingKey => $_getN(1);
  @$pb.TagNumber(2)
  set signingKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSigningKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearSigningKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get decryptionKey => $_getN(2);
  @$pb.TagNumber(3)
  set decryptionKey($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDecryptionKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearDecryptionKey() => $_clearField(3);

  /// At most one of each kind.
  @$pb.TagNumber(4)
  $pb.PbList<UnlockPath> get paths => $_getList(3);
}

/// The keys as stored.
class CreateKeysResponse extends $pb.GeneratedMessage {
  factory CreateKeysResponse({
    AccountKeys? keys,
  }) {
    final result = CreateKeysResponse._();
    if (keys != null) result.keys = keys;
    return result;
  }

  CreateKeysResponse._();

  factory CreateKeysResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateKeysResponse()..mergeFromBuffer(data, registry);
  factory CreateKeysResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateKeysResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateKeysResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateKeysResponse.$_createMessage)
    ..aOM<AccountKeys>(1, _omitFieldNames ? '' : 'keys',
        subBuilder: AccountKeys.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateKeysResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateKeysResponse copyWith(void Function(CreateKeysResponse) updates) =>
      super.copyWith((message) => updates(message as CreateKeysResponse))
          as CreateKeysResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CreateKeysResponse() / CreateKeysResponse.new instead')
  static CreateKeysResponse create() => CreateKeysResponse._();
  static $pb.GeneratedMessage $_createMessage() => CreateKeysResponse._();
  @$core.override
  CreateKeysResponse createEmptyInstance() => CreateKeysResponse._();
  @$core.pragma('dart2js:noInline')
  static CreateKeysResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateKeysResponse>(
          CreateKeysResponse.$_createMessage);
  static CreateKeysResponse? _defaultInstance;

  @$pb.TagNumber(1)
  AccountKeys get keys => $_getN(0);
  @$pb.TagNumber(1)
  set keys(AccountKeys value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKeys() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeys() => $_clearField(1);
  @$pb.TagNumber(1)
  AccountKeys ensureKeys() => $_ensure(0);
}

/// An unlock path of the AMK the caller's keys wrap.
class PutUnlockPathRequest extends $pb.GeneratedMessage {
  factory PutUnlockPathRequest({
    UnlockPath? path,
  }) {
    final result = PutUnlockPathRequest._();
    if (path != null) result.path = path;
    return result;
  }

  PutUnlockPathRequest._();

  factory PutUnlockPathRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutUnlockPathRequest()..mergeFromBuffer(data, registry);
  factory PutUnlockPathRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutUnlockPathRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutUnlockPathRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: PutUnlockPathRequest.$_createMessage)
    ..aOM<UnlockPath>(1, _omitFieldNames ? '' : 'path',
        subBuilder: UnlockPath.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutUnlockPathRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutUnlockPathRequest copyWith(void Function(PutUnlockPathRequest) updates) =>
      super.copyWith((message) => updates(message as PutUnlockPathRequest))
          as PutUnlockPathRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PutUnlockPathRequest() / PutUnlockPathRequest.new instead')
  static PutUnlockPathRequest create() => PutUnlockPathRequest._();
  static $pb.GeneratedMessage $_createMessage() => PutUnlockPathRequest._();
  @$core.override
  PutUnlockPathRequest createEmptyInstance() => PutUnlockPathRequest._();
  @$core.pragma('dart2js:noInline')
  static PutUnlockPathRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PutUnlockPathRequest>(
          PutUnlockPathRequest.$_createMessage);
  static PutUnlockPathRequest? _defaultInstance;

  @$pb.TagNumber(1)
  UnlockPath get path => $_getN(0);
  @$pb.TagNumber(1)
  set path(UnlockPath value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);
  @$pb.TagNumber(1)
  UnlockPath ensurePath() => $_ensure(0);
}

/// The keys as stored.
class PutUnlockPathResponse extends $pb.GeneratedMessage {
  factory PutUnlockPathResponse({
    AccountKeys? keys,
  }) {
    final result = PutUnlockPathResponse._();
    if (keys != null) result.keys = keys;
    return result;
  }

  PutUnlockPathResponse._();

  factory PutUnlockPathResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutUnlockPathResponse()..mergeFromBuffer(data, registry);
  factory PutUnlockPathResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PutUnlockPathResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PutUnlockPathResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: PutUnlockPathResponse.$_createMessage)
    ..aOM<AccountKeys>(1, _omitFieldNames ? '' : 'keys',
        subBuilder: AccountKeys.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutUnlockPathResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PutUnlockPathResponse copyWith(
          void Function(PutUnlockPathResponse) updates) =>
      super.copyWith((message) => updates(message as PutUnlockPathResponse))
          as PutUnlockPathResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PutUnlockPathResponse() / PutUnlockPathResponse.new instead')
  static PutUnlockPathResponse create() => PutUnlockPathResponse._();
  static $pb.GeneratedMessage $_createMessage() => PutUnlockPathResponse._();
  @$core.override
  PutUnlockPathResponse createEmptyInstance() => PutUnlockPathResponse._();
  @$core.pragma('dart2js:noInline')
  static PutUnlockPathResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PutUnlockPathResponse>(
          PutUnlockPathResponse.$_createMessage);
  static PutUnlockPathResponse? _defaultInstance;

  @$pb.TagNumber(1)
  AccountKeys get keys => $_getN(0);
  @$pb.TagNumber(1)
  set keys(AccountKeys value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKeys() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeys() => $_clearField(1);
  @$pb.TagNumber(1)
  AccountKeys ensureKeys() => $_ensure(0);
}

/// The key_id of the KEK_rec the person reached with the kit.
class VerifyRecoveryKitRequest extends $pb.GeneratedMessage {
  factory VerifyRecoveryKitRequest({
    $core.List<$core.int>? kitId,
  }) {
    final result = VerifyRecoveryKitRequest._();
    if (kitId != null) result.kitId = kitId;
    return result;
  }

  VerifyRecoveryKitRequest._();

  factory VerifyRecoveryKitRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyRecoveryKitRequest()..mergeFromBuffer(data, registry);
  factory VerifyRecoveryKitRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyRecoveryKitRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VerifyRecoveryKitRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: VerifyRecoveryKitRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'kitId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyRecoveryKitRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyRecoveryKitRequest copyWith(
          void Function(VerifyRecoveryKitRequest) updates) =>
      super.copyWith((message) => updates(message as VerifyRecoveryKitRequest))
          as VerifyRecoveryKitRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use VerifyRecoveryKitRequest() / VerifyRecoveryKitRequest.new instead')
  static VerifyRecoveryKitRequest create() => VerifyRecoveryKitRequest._();
  static $pb.GeneratedMessage $_createMessage() => VerifyRecoveryKitRequest._();
  @$core.override
  VerifyRecoveryKitRequest createEmptyInstance() =>
      VerifyRecoveryKitRequest._();
  @$core.pragma('dart2js:noInline')
  static VerifyRecoveryKitRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VerifyRecoveryKitRequest>(
          VerifyRecoveryKitRequest.$_createMessage);
  static VerifyRecoveryKitRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get kitId => $_getN(0);
  @$pb.TagNumber(1)
  set kitId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKitId() => $_has(0);
  @$pb.TagNumber(1)
  void clearKitId() => $_clearField(1);
}

/// The keys as stored.
class VerifyRecoveryKitResponse extends $pb.GeneratedMessage {
  factory VerifyRecoveryKitResponse({
    AccountKeys? keys,
  }) {
    final result = VerifyRecoveryKitResponse._();
    if (keys != null) result.keys = keys;
    return result;
  }

  VerifyRecoveryKitResponse._();

  factory VerifyRecoveryKitResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyRecoveryKitResponse()..mergeFromBuffer(data, registry);
  factory VerifyRecoveryKitResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyRecoveryKitResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VerifyRecoveryKitResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: VerifyRecoveryKitResponse.$_createMessage)
    ..aOM<AccountKeys>(1, _omitFieldNames ? '' : 'keys',
        subBuilder: AccountKeys.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyRecoveryKitResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyRecoveryKitResponse copyWith(
          void Function(VerifyRecoveryKitResponse) updates) =>
      super.copyWith((message) => updates(message as VerifyRecoveryKitResponse))
          as VerifyRecoveryKitResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use VerifyRecoveryKitResponse() / VerifyRecoveryKitResponse.new instead')
  static VerifyRecoveryKitResponse create() => VerifyRecoveryKitResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      VerifyRecoveryKitResponse._();
  @$core.override
  VerifyRecoveryKitResponse createEmptyInstance() =>
      VerifyRecoveryKitResponse._();
  @$core.pragma('dart2js:noInline')
  static VerifyRecoveryKitResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VerifyRecoveryKitResponse>(
          VerifyRecoveryKitResponse.$_createMessage);
  static VerifyRecoveryKitResponse? _defaultInstance;

  @$pb.TagNumber(1)
  AccountKeys get keys => $_getN(0);
  @$pb.TagNumber(1)
  set keys(AccountKeys value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKeys() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeys() => $_clearField(1);
  @$pb.TagNumber(1)
  AccountKeys ensureKeys() => $_ensure(0);
}

/// The keys of private mode (design 06 §4 and §6, ADR-0255): an account's identity, its account master key (AMK)
/// wrapped once per unlock path, and its recovery kit. Clients make and wrap every key; the server keeps the wraps and
/// reads only their headers, so nothing it holds opens anything. It accepts no upload to a private library from an
/// account with fewer than two unlock paths or an unverified recovery kit (`keys.recovery_incomplete`).
class KeyServiceApi {
  final $pb.RpcClient _client;

  KeyServiceApi(this._client);

  /// The caller's keys, and whether its account has a password. Only a password sign-in returns the password path's
  /// wrap (FinishLoginResponse.password_path), so that a session alone cannot test guesses at the password offline.
  $async.Future<GetKeysResponse> getKeys(
          $pb.ClientContext? ctx, GetKeysRequest request) =>
      _client.invoke<GetKeysResponse>(
          ctx, 'KeyService', 'GetKeys', request, GetKeysResponse());

  /// Creates the caller's keys, once (`keys.exist`). A password path needs the account's password (`keys.no_password`).
  $async.Future<CreateKeysResponse> createKeys(
          $pb.ClientContext? ctx, CreateKeysRequest request) =>
      _client.invoke<CreateKeysResponse>(
          ctx, 'KeyService', 'CreateKeys', request, CreateKeysResponse());

  /// Adds an unlock path or replaces the one of its kind (`keys.none` before CreateKeys). A new recovery kit is
  /// unverified until VerifyRecoveryKit.
  $async.Future<PutUnlockPathResponse> putUnlockPath(
          $pb.ClientContext? ctx, PutUnlockPathRequest request) =>
      _client.invoke<PutUnlockPathResponse>(
          ctx, 'KeyService', 'PutUnlockPath', request, PutUnlockPathResponse());

  /// Records that the person proved they hold the recovery kit: at setup by typing words of it again, in a drill by
  /// unlocking with it. `kit_id` names the kit (`keys.kit_mismatch` when it is not the current one).
  $async.Future<VerifyRecoveryKitResponse> verifyRecoveryKit(
          $pb.ClientContext? ctx, VerifyRecoveryKitRequest request) =>
      _client.invoke<VerifyRecoveryKitResponse>(ctx, 'KeyService',
          'VerifyRecoveryKit', request, VerifyRecoveryKitResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
