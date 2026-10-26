// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/auth.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

import 'auth.pbenum.dart';
import 'keys.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'auth.pbenum.dart';

/// A passkey of an account.
class Passkey extends $pb.GeneratedMessage {
  factory Passkey({
    $core.String? passkeyId,
    $core.String? name,
    $0.Timestamp? createdAt,
    $0.Timestamp? lastUsedAt,
  }) {
    final result = Passkey._();
    if (passkeyId != null) result.passkeyId = passkeyId;
    if (name != null) result.name = name;
    if (createdAt != null) result.createdAt = createdAt;
    if (lastUsedAt != null) result.lastUsedAt = lastUsedAt;
    return result;
  }

  Passkey._();

  factory Passkey.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Passkey()..mergeFromBuffer(data, registry);
  factory Passkey.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Passkey()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Passkey',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: Passkey.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'passkeyId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOM<$0.Timestamp>(3, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<$0.Timestamp>(4, _omitFieldNames ? '' : 'lastUsedAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Passkey clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Passkey copyWith(void Function(Passkey) updates) =>
      super.copyWith((message) => updates(message as Passkey)) as Passkey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Passkey() / Passkey.new instead')
  static Passkey create() => Passkey._();
  static $pb.GeneratedMessage $_createMessage() => Passkey._();
  @$core.override
  Passkey createEmptyInstance() => Passkey._();
  @$core.pragma('dart2js:noInline')
  static Passkey getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Passkey>(Passkey.$_createMessage);
  static Passkey? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get passkeyId => $_getSZ(0);
  @$pb.TagNumber(1)
  set passkeyId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPasskeyId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPasskeyId() => $_clearField(1);

  /// What the person calls it, e.g. "Ann's iPhone": 1 to 100 printable characters.
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.Timestamp get createdAt => $_getN(2);
  @$pb.TagNumber(3)
  set createdAt($0.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCreatedAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreatedAt() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Timestamp ensureCreatedAt() => $_ensure(2);

  @$pb.TagNumber(4)
  $0.Timestamp get lastUsedAt => $_getN(3);
  @$pb.TagNumber(4)
  set lastUsedAt($0.Timestamp value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasLastUsedAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastUsedAt() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.Timestamp ensureLastUsedAt() => $_ensure(3);
}

/// What a password sign-in still needs from an account with a second factor.
class SecondFactorChallenge extends $pb.GeneratedMessage {
  factory SecondFactorChallenge({
    $core.String? loginId,
    $core.Iterable<SecondFactor>? factors,
    $core.String? passkeyOptionsJson,
  }) {
    final result = SecondFactorChallenge._();
    if (loginId != null) result.loginId = loginId;
    if (factors != null) result.factors.addAll(factors);
    if (passkeyOptionsJson != null)
      result.passkeyOptionsJson = passkeyOptionsJson;
    return result;
  }

  SecondFactorChallenge._();

  factory SecondFactorChallenge.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SecondFactorChallenge()..mergeFromBuffer(data, registry);
  factory SecondFactorChallenge.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SecondFactorChallenge()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SecondFactorChallenge',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: SecondFactorChallenge.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'loginId')
    ..pc<SecondFactor>(2, _omitFieldNames ? '' : 'factors', $pb.PbFieldType.KE,
        valueOf: SecondFactor.valueOf,
        enumValues: SecondFactor.values,
        defaultEnumValue: SecondFactor.SECOND_FACTOR_UNSPECIFIED)
    ..aOS(3, _omitFieldNames ? '' : 'passkeyOptionsJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SecondFactorChallenge clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SecondFactorChallenge copyWith(
          void Function(SecondFactorChallenge) updates) =>
      super.copyWith((message) => updates(message as SecondFactorChallenge))
          as SecondFactorChallenge;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SecondFactorChallenge() / SecondFactorChallenge.new instead')
  static SecondFactorChallenge create() => SecondFactorChallenge._();
  static $pb.GeneratedMessage $_createMessage() => SecondFactorChallenge._();
  @$core.override
  SecondFactorChallenge createEmptyInstance() => SecondFactorChallenge._();
  @$core.pragma('dart2js:noInline')
  static SecondFactorChallenge getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SecondFactorChallenge>(
          SecondFactorChallenge.$_createMessage);
  static SecondFactorChallenge? _defaultInstance;

  /// Names this sign-in in FinishSecondFactor, for five minutes.
  @$pb.TagNumber(1)
  $core.String get loginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set loginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLoginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLoginId() => $_clearField(1);

  /// The factors the account can answer with.
  @$pb.TagNumber(2)
  $pb.PbList<SecondFactor> get factors => $_getList(1);

  /// PublicKeyCredentialRequestOptionsJSON for one of the account's passkeys; empty without one.
  @$pb.TagNumber(3)
  $core.String get passkeyOptionsJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set passkeyOptionsJson($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPasskeyOptionsJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearPasskeyOptionsJson() => $_clearField(3);
}

/// A device signed in to an account: an app install, a browser or the CLI.
class Device extends $pb.GeneratedMessage {
  factory Device({
    $core.String? deviceId,
    $core.String? name,
    $core.String? platform,
    $core.String? appVersion,
    $0.Timestamp? createdAt,
    $0.Timestamp? lastSeenAt,
    $core.bool? current,
  }) {
    final result = Device._();
    if (deviceId != null) result.deviceId = deviceId;
    if (name != null) result.name = name;
    if (platform != null) result.platform = platform;
    if (appVersion != null) result.appVersion = appVersion;
    if (createdAt != null) result.createdAt = createdAt;
    if (lastSeenAt != null) result.lastSeenAt = lastSeenAt;
    if (current != null) result.current = current;
    return result;
  }

  Device._();

  factory Device.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Device()..mergeFromBuffer(data, registry);
  factory Device.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Device()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Device',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: Device.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'platform')
    ..aOS(4, _omitFieldNames ? '' : 'appVersion')
    ..aOM<$0.Timestamp>(5, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<$0.Timestamp>(6, _omitFieldNames ? '' : 'lastSeenAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOB(7, _omitFieldNames ? '' : 'current')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Device clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Device copyWith(void Function(Device) updates) =>
      super.copyWith((message) => updates(message as Device)) as Device;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Device() / Device.new instead')
  static Device create() => Device._();
  static $pb.GeneratedMessage $_createMessage() => Device._();
  @$core.override
  Device createEmptyInstance() => Device._();
  @$core.pragma('dart2js:noInline')
  static Device getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Device>(Device.$_createMessage);
  static Device? _defaultInstance;

  /// Made by the server; a client that signs in again sends the id it was given to stay the same device.
  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  /// What the person calls it, e.g. "Ann's Pixel": 1 to 100 printable characters.
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// e.g. "android", "ios", "web" or "linux": 1 to 32 printable characters.
  @$pb.TagNumber(3)
  $core.String get platform => $_getSZ(2);
  @$pb.TagNumber(3)
  set platform($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get appVersion => $_getSZ(3);
  @$pb.TagNumber(4)
  set appVersion($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAppVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearAppVersion() => $_clearField(4);

  @$pb.TagNumber(5)
  $0.Timestamp get createdAt => $_getN(4);
  @$pb.TagNumber(5)
  set createdAt($0.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasCreatedAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreatedAt() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.Timestamp ensureCreatedAt() => $_ensure(4);

  @$pb.TagNumber(6)
  $0.Timestamp get lastSeenAt => $_getN(5);
  @$pb.TagNumber(6)
  set lastSeenAt($0.Timestamp value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasLastSeenAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastSeenAt() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.Timestamp ensureLastSeenAt() => $_ensure(5);

  /// Whether this is the device that asks.
  @$pb.TagNumber(7)
  $core.bool get current => $_getBF(6);
  @$pb.TagNumber(7)
  set current($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCurrent() => $_has(6);
  @$pb.TagNumber(7)
  void clearCurrent() => $_clearField(7);
}

/// The bearer credential of a device.
class Session extends $pb.GeneratedMessage {
  factory Session({
    $core.String? token,
    $0.Timestamp? expiresAt,
    $core.String? deviceId,
    $core.String? userId,
    $core.String? deviceSecret,
  }) {
    final result = Session._();
    if (token != null) result.token = token;
    if (expiresAt != null) result.expiresAt = expiresAt;
    if (deviceId != null) result.deviceId = deviceId;
    if (userId != null) result.userId = userId;
    if (deviceSecret != null) result.deviceSecret = deviceSecret;
    return result;
  }

  Session._();

  factory Session.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Session()..mergeFromBuffer(data, registry);
  factory Session.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Session()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Session',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: Session.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'token')
    ..aOM<$0.Timestamp>(2, _omitFieldNames ? '' : 'expiresAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOS(3, _omitFieldNames ? '' : 'deviceId')
    ..aOS(4, _omitFieldNames ? '' : 'userId')
    ..aOS(5, _omitFieldNames ? '' : 'deviceSecret')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Session clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Session copyWith(void Function(Session) updates) =>
      super.copyWith((message) => updates(message as Session)) as Session;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Session() / Session.new instead')
  static Session create() => Session._();
  static $pb.GeneratedMessage $_createMessage() => Session._();
  @$core.override
  Session createEmptyInstance() => Session._();
  @$core.pragma('dart2js:noInline')
  static Session getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Session>(Session.$_createMessage);
  static Session? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get token => $_getSZ(0);
  @$pb.TagNumber(1)
  set token($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearToken() => $_clearField(1);

  /// Unless rotated before then.
  @$pb.TagNumber(2)
  $0.Timestamp get expiresAt => $_getN(1);
  @$pb.TagNumber(2)
  set expiresAt($0.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasExpiresAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresAt() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Timestamp ensureExpiresAt() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get deviceId => $_getSZ(2);
  @$pb.TagNumber(3)
  set deviceId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeviceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get userId => $_getSZ(3);
  @$pb.TagNumber(4)
  set userId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUserId() => $_has(3);
  @$pb.TagNumber(4)
  void clearUserId() => $_clearField(4);

  /// New at each sign-in, never from RotateSession: proves this device at its next StartLogin. Keep it across sign-outs.
  @$pb.TagNumber(5)
  $core.String get deviceSecret => $_getSZ(4);
  @$pb.TagNumber(5)
  set deviceSecret($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDeviceSecret() => $_has(4);
  @$pb.TagNumber(5)
  void clearDeviceSecret() => $_clearField(5);
}

/// The client's OPAQUE RegistrationRequest.
class StartPasswordSetupRequest extends $pb.GeneratedMessage {
  factory StartPasswordSetupRequest({
    $core.List<$core.int>? registrationRequest,
    $core.String? passwordSetupToken,
  }) {
    final result = StartPasswordSetupRequest._();
    if (registrationRequest != null)
      result.registrationRequest = registrationRequest;
    if (passwordSetupToken != null)
      result.passwordSetupToken = passwordSetupToken;
    return result;
  }

  StartPasswordSetupRequest._();

  factory StartPasswordSetupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasswordSetupRequest()..mergeFromBuffer(data, registry);
  factory StartPasswordSetupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasswordSetupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartPasswordSetupRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartPasswordSetupRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'registrationRequest', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'passwordSetupToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasswordSetupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasswordSetupRequest copyWith(
          void Function(StartPasswordSetupRequest) updates) =>
      super.copyWith((message) => updates(message as StartPasswordSetupRequest))
          as StartPasswordSetupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartPasswordSetupRequest() / StartPasswordSetupRequest.new instead')
  static StartPasswordSetupRequest create() => StartPasswordSetupRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      StartPasswordSetupRequest._();
  @$core.override
  StartPasswordSetupRequest createEmptyInstance() =>
      StartPasswordSetupRequest._();
  @$core.pragma('dart2js:noInline')
  static StartPasswordSetupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartPasswordSetupRequest>(
          StartPasswordSetupRequest.$_createMessage);
  static StartPasswordSetupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get registrationRequest => $_getN(0);
  @$pb.TagNumber(1)
  set registrationRequest($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRegistrationRequest() => $_has(0);
  @$pb.TagNumber(1)
  void clearRegistrationRequest() => $_clearField(1);

  /// From CreateFirstAdmin or UserService.CreatePasswordSetup; empty to use the caller's session.
  @$pb.TagNumber(2)
  $core.String get passwordSetupToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set passwordSetupToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPasswordSetupToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearPasswordSetupToken() => $_clearField(2);
}

/// The server's OPAQUE RegistrationResponse.
class StartPasswordSetupResponse extends $pb.GeneratedMessage {
  factory StartPasswordSetupResponse({
    $core.List<$core.int>? registrationResponse,
    $core.List<$core.int>? registrationId,
    $core.bool? privateLibraries,
  }) {
    final result = StartPasswordSetupResponse._();
    if (registrationResponse != null)
      result.registrationResponse = registrationResponse;
    if (registrationId != null) result.registrationId = registrationId;
    if (privateLibraries != null) result.privateLibraries = privateLibraries;
    return result;
  }

  StartPasswordSetupResponse._();

  factory StartPasswordSetupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasswordSetupResponse()..mergeFromBuffer(data, registry);
  factory StartPasswordSetupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasswordSetupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartPasswordSetupResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartPasswordSetupResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'registrationResponse', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'registrationId', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'privateLibraries')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasswordSetupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasswordSetupResponse copyWith(
          void Function(StartPasswordSetupResponse) updates) =>
      super.copyWith(
              (message) => updates(message as StartPasswordSetupResponse))
          as StartPasswordSetupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartPasswordSetupResponse() / StartPasswordSetupResponse.new instead')
  static StartPasswordSetupResponse create() => StartPasswordSetupResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      StartPasswordSetupResponse._();
  @$core.override
  StartPasswordSetupResponse createEmptyInstance() =>
      StartPasswordSetupResponse._();
  @$core.pragma('dart2js:noInline')
  static StartPasswordSetupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartPasswordSetupResponse>(
          StartPasswordSetupResponse.$_createMessage);
  static StartPasswordSetupResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get registrationResponse => $_getN(0);
  @$pb.TagNumber(1)
  set registrationResponse($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRegistrationResponse() => $_has(0);
  @$pb.TagNumber(1)
  void clearRegistrationResponse() => $_clearField(1);

  /// The credential identifier of this password, new for each; FinishPasswordSetup sends it back.
  @$pb.TagNumber(2)
  $core.List<$core.int> get registrationId => $_getN(1);
  @$pb.TagNumber(2)
  set registrationId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRegistrationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRegistrationId() => $_clearField(2);

  /// With a setup token, the account has private libraries or private-mode keys, which a new password does not reopen:
  /// the client says what does (design 06 §6) before it finishes.
  @$pb.TagNumber(3)
  $core.bool get privateLibraries => $_getBF(2);
  @$pb.TagNumber(3)
  set privateLibraries($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPrivateLibraries() => $_has(2);
  @$pb.TagNumber(3)
  void clearPrivateLibraries() => $_clearField(3);
}

/// The client's OPAQUE registration record and Argon2id parameters.
class FinishPasswordSetupRequest extends $pb.GeneratedMessage {
  factory FinishPasswordSetupRequest({
    $core.List<$core.int>? registrationRecord,
    $core.List<$core.int>? ksfParams,
    $core.String? passwordSetupToken,
    $core.List<$core.int>? registrationId,
    $1.UnlockPath? passwordPath,
  }) {
    final result = FinishPasswordSetupRequest._();
    if (registrationRecord != null)
      result.registrationRecord = registrationRecord;
    if (ksfParams != null) result.ksfParams = ksfParams;
    if (passwordSetupToken != null)
      result.passwordSetupToken = passwordSetupToken;
    if (registrationId != null) result.registrationId = registrationId;
    if (passwordPath != null) result.passwordPath = passwordPath;
    return result;
  }

  FinishPasswordSetupRequest._();

  factory FinishPasswordSetupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasswordSetupRequest()..mergeFromBuffer(data, registry);
  factory FinishPasswordSetupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasswordSetupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishPasswordSetupRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishPasswordSetupRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'registrationRecord', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ksfParams', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'passwordSetupToken')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'registrationId', $pb.PbFieldType.OY)
    ..aOM<$1.UnlockPath>(5, _omitFieldNames ? '' : 'passwordPath',
        subBuilder: $1.UnlockPath.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasswordSetupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasswordSetupRequest copyWith(
          void Function(FinishPasswordSetupRequest) updates) =>
      super.copyWith(
              (message) => updates(message as FinishPasswordSetupRequest))
          as FinishPasswordSetupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishPasswordSetupRequest() / FinishPasswordSetupRequest.new instead')
  static FinishPasswordSetupRequest create() => FinishPasswordSetupRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinishPasswordSetupRequest._();
  @$core.override
  FinishPasswordSetupRequest createEmptyInstance() =>
      FinishPasswordSetupRequest._();
  @$core.pragma('dart2js:noInline')
  static FinishPasswordSetupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishPasswordSetupRequest>(
          FinishPasswordSetupRequest.$_createMessage);
  static FinishPasswordSetupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get registrationRecord => $_getN(0);
  @$pb.TagNumber(1)
  set registrationRecord($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRegistrationRecord() => $_has(0);
  @$pb.TagNumber(1)
  void clearRegistrationRecord() => $_clearField(1);

  /// The 26-byte parameter set of docs/dev/crypto-v1.md#argon2id-parameters, within the account policy.
  @$pb.TagNumber(2)
  $core.List<$core.int> get ksfParams => $_getN(1);
  @$pb.TagNumber(2)
  set ksfParams($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKsfParams() => $_has(1);
  @$pb.TagNumber(2)
  void clearKsfParams() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get passwordSetupToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set passwordSetupToken($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPasswordSetupToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearPasswordSetupToken() => $_clearField(3);

  /// From StartPasswordSetupResponse.
  @$pb.TagNumber(4)
  $core.List<$core.int> get registrationId => $_getN(3);
  @$pb.TagNumber(4)
  set registrationId($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRegistrationId() => $_has(3);
  @$pb.TagNumber(4)
  void clearRegistrationId() => $_clearField(4);

  /// With the caller's session, for an account with private-mode keys: the AMK wrapped under the new password, which
  /// replaces the password path. Without it the password path goes, as the old password no longer opens it.
  @$pb.TagNumber(5)
  $1.UnlockPath get passwordPath => $_getN(4);
  @$pb.TagNumber(5)
  set passwordPath($1.UnlockPath value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPasswordPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearPasswordPath() => $_clearField(5);
  @$pb.TagNumber(5)
  $1.UnlockPath ensurePasswordPath() => $_ensure(4);
}

/// The password is set.
class FinishPasswordSetupResponse extends $pb.GeneratedMessage {
  factory FinishPasswordSetupResponse() => FinishPasswordSetupResponse._();

  FinishPasswordSetupResponse._();

  factory FinishPasswordSetupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasswordSetupResponse()..mergeFromBuffer(data, registry);
  factory FinishPasswordSetupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasswordSetupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishPasswordSetupResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishPasswordSetupResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasswordSetupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasswordSetupResponse copyWith(
          void Function(FinishPasswordSetupResponse) updates) =>
      super.copyWith(
              (message) => updates(message as FinishPasswordSetupResponse))
          as FinishPasswordSetupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishPasswordSetupResponse() / FinishPasswordSetupResponse.new instead')
  static FinishPasswordSetupResponse create() =>
      FinishPasswordSetupResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinishPasswordSetupResponse._();
  @$core.override
  FinishPasswordSetupResponse createEmptyInstance() =>
      FinishPasswordSetupResponse._();
  @$core.pragma('dart2js:noInline')
  static FinishPasswordSetupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishPasswordSetupResponse>(
          FinishPasswordSetupResponse.$_createMessage);
  static FinishPasswordSetupResponse? _defaultInstance;
}

/// The account and the client's OPAQUE KE1.
class StartLoginRequest extends $pb.GeneratedMessage {
  factory StartLoginRequest({
    $core.String? handle,
    $core.List<$core.int>? ke1,
    $core.String? deviceId,
    $core.String? deviceSecret,
  }) {
    final result = StartLoginRequest._();
    if (handle != null) result.handle = handle;
    if (ke1 != null) result.ke1 = ke1;
    if (deviceId != null) result.deviceId = deviceId;
    if (deviceSecret != null) result.deviceSecret = deviceSecret;
    return result;
  }

  StartLoginRequest._();

  factory StartLoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartLoginRequest()..mergeFromBuffer(data, registry);
  factory StartLoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartLoginRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartLoginRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartLoginRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'handle')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ke1', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'deviceId')
    ..aOS(4, _omitFieldNames ? '' : 'deviceSecret')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartLoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartLoginRequest copyWith(void Function(StartLoginRequest) updates) =>
      super.copyWith((message) => updates(message as StartLoginRequest))
          as StartLoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StartLoginRequest() / StartLoginRequest.new instead')
  static StartLoginRequest create() => StartLoginRequest._();
  static $pb.GeneratedMessage $_createMessage() => StartLoginRequest._();
  @$core.override
  StartLoginRequest createEmptyInstance() => StartLoginRequest._();
  @$core.pragma('dart2js:noInline')
  static StartLoginRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StartLoginRequest>(
          StartLoginRequest.$_createMessage);
  static StartLoginRequest? _defaultInstance;

  /// The account's handle or email.
  @$pb.TagNumber(1)
  $core.String get handle => $_getSZ(0);
  @$pb.TagNumber(1)
  set handle($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandle() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ke1 => $_getN(1);
  @$pb.TagNumber(2)
  set ke1($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKe1() => $_has(1);
  @$pb.TagNumber(2)
  void clearKe1() => $_clearField(2);

  /// A device that signed in before: its id and the secret that sign-in gave it (Session.device_secret). Its attempts
  /// count apart from everyone else's, so that guessing at the account locks out only the guesser.
  @$pb.TagNumber(3)
  $core.String get deviceId => $_getSZ(2);
  @$pb.TagNumber(3)
  set deviceId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeviceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get deviceSecret => $_getSZ(3);
  @$pb.TagNumber(4)
  set deviceSecret($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDeviceSecret() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceSecret() => $_clearField(4);
}

/// The server's OPAQUE KE2.
class StartLoginResponse extends $pb.GeneratedMessage {
  factory StartLoginResponse({
    $core.String? loginId,
    $core.List<$core.int>? ke2,
    $core.List<$core.int>? ksfParams,
  }) {
    final result = StartLoginResponse._();
    if (loginId != null) result.loginId = loginId;
    if (ke2 != null) result.ke2 = ke2;
    if (ksfParams != null) result.ksfParams = ksfParams;
    return result;
  }

  StartLoginResponse._();

  factory StartLoginResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartLoginResponse()..mergeFromBuffer(data, registry);
  factory StartLoginResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartLoginResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartLoginResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartLoginResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'loginId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ke2', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'ksfParams', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartLoginResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartLoginResponse copyWith(void Function(StartLoginResponse) updates) =>
      super.copyWith((message) => updates(message as StartLoginResponse))
          as StartLoginResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StartLoginResponse() / StartLoginResponse.new instead')
  static StartLoginResponse create() => StartLoginResponse._();
  static $pb.GeneratedMessage $_createMessage() => StartLoginResponse._();
  @$core.override
  StartLoginResponse createEmptyInstance() => StartLoginResponse._();
  @$core.pragma('dart2js:noInline')
  static StartLoginResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartLoginResponse>(
          StartLoginResponse.$_createMessage);
  static StartLoginResponse? _defaultInstance;

  /// Names this attempt in FinishLogin, for two minutes.
  @$pb.TagNumber(1)
  $core.String get loginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set loginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLoginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLoginId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ke2 => $_getN(1);
  @$pb.TagNumber(2)
  set ke2($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKe2() => $_has(1);
  @$pb.TagNumber(2)
  void clearKe2() => $_clearField(2);

  /// The account's Argon2id parameters, the KSF's cost.
  @$pb.TagNumber(3)
  $core.List<$core.int> get ksfParams => $_getN(2);
  @$pb.TagNumber(3)
  set ksfParams($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasKsfParams() => $_has(2);
  @$pb.TagNumber(3)
  void clearKsfParams() => $_clearField(3);
}

/// The client's OPAQUE KE3 and the device that signs in.
class FinishLoginRequest extends $pb.GeneratedMessage {
  factory FinishLoginRequest({
    $core.String? loginId,
    $core.List<$core.int>? ke3,
    Device? device,
  }) {
    final result = FinishLoginRequest._();
    if (loginId != null) result.loginId = loginId;
    if (ke3 != null) result.ke3 = ke3;
    if (device != null) result.device = device;
    return result;
  }

  FinishLoginRequest._();

  factory FinishLoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishLoginRequest()..mergeFromBuffer(data, registry);
  factory FinishLoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishLoginRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishLoginRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishLoginRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'loginId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ke3', $pb.PbFieldType.OY)
    ..aOM<Device>(3, _omitFieldNames ? '' : 'device',
        subBuilder: Device.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishLoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishLoginRequest copyWith(void Function(FinishLoginRequest) updates) =>
      super.copyWith((message) => updates(message as FinishLoginRequest))
          as FinishLoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FinishLoginRequest() / FinishLoginRequest.new instead')
  static FinishLoginRequest create() => FinishLoginRequest._();
  static $pb.GeneratedMessage $_createMessage() => FinishLoginRequest._();
  @$core.override
  FinishLoginRequest createEmptyInstance() => FinishLoginRequest._();
  @$core.pragma('dart2js:noInline')
  static FinishLoginRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishLoginRequest>(
          FinishLoginRequest.$_createMessage);
  static FinishLoginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get loginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set loginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLoginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLoginId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ke3 => $_getN(1);
  @$pb.TagNumber(2)
  set ke3($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKe3() => $_has(1);
  @$pb.TagNumber(2)
  void clearKe3() => $_clearField(2);

  /// device_id (optional), name, platform and app_version are read.
  @$pb.TagNumber(3)
  Device get device => $_getN(2);
  @$pb.TagNumber(3)
  set device(Device value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDevice() => $_has(2);
  @$pb.TagNumber(3)
  void clearDevice() => $_clearField(3);
  @$pb.TagNumber(3)
  Device ensureDevice() => $_ensure(2);
}

/// The new session, or what the sign-in still needs.
class FinishLoginResponse extends $pb.GeneratedMessage {
  factory FinishLoginResponse({
    Session? session,
    SecondFactorChallenge? secondFactor,
    $1.UnlockPath? passwordPath,
  }) {
    final result = FinishLoginResponse._();
    if (session != null) result.session = session;
    if (secondFactor != null) result.secondFactor = secondFactor;
    if (passwordPath != null) result.passwordPath = passwordPath;
    return result;
  }

  FinishLoginResponse._();

  factory FinishLoginResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishLoginResponse()..mergeFromBuffer(data, registry);
  factory FinishLoginResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishLoginResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishLoginResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishLoginResponse.$_createMessage)
    ..aOM<Session>(1, _omitFieldNames ? '' : 'session',
        subBuilder: Session.$_createMessage)
    ..aOM<SecondFactorChallenge>(2, _omitFieldNames ? '' : 'secondFactor',
        subBuilder: SecondFactorChallenge.$_createMessage)
    ..aOM<$1.UnlockPath>(3, _omitFieldNames ? '' : 'passwordPath',
        subBuilder: $1.UnlockPath.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishLoginResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishLoginResponse copyWith(void Function(FinishLoginResponse) updates) =>
      super.copyWith((message) => updates(message as FinishLoginResponse))
          as FinishLoginResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use FinishLoginResponse() / FinishLoginResponse.new instead')
  static FinishLoginResponse create() => FinishLoginResponse._();
  static $pb.GeneratedMessage $_createMessage() => FinishLoginResponse._();
  @$core.override
  FinishLoginResponse createEmptyInstance() => FinishLoginResponse._();
  @$core.pragma('dart2js:noInline')
  static FinishLoginResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishLoginResponse>(
          FinishLoginResponse.$_createMessage);
  static FinishLoginResponse? _defaultInstance;

  /// Unset while `second_factor` is.
  @$pb.TagNumber(1)
  Session get session => $_getN(0);
  @$pb.TagNumber(1)
  set session(Session value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSession() => $_has(0);
  @$pb.TagNumber(1)
  void clearSession() => $_clearField(1);
  @$pb.TagNumber(1)
  Session ensureSession() => $_ensure(0);

  /// Set when the account has a second factor: FinishSecondFactor answers it.
  @$pb.TagNumber(2)
  SecondFactorChallenge get secondFactor => $_getN(1);
  @$pb.TagNumber(2)
  set secondFactor(SecondFactorChallenge value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSecondFactor() => $_has(1);
  @$pb.TagNumber(2)
  void clearSecondFactor() => $_clearField(2);
  @$pb.TagNumber(2)
  SecondFactorChallenge ensureSecondFactor() => $_ensure(1);

  /// With the session, for an account with private-mode keys: its password path, the AMK wrapped under this password,
  /// which only a password sign-in returns (KeyService).
  @$pb.TagNumber(3)
  $1.UnlockPath get passwordPath => $_getN(2);
  @$pb.TagNumber(3)
  set passwordPath($1.UnlockPath value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPasswordPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearPasswordPath() => $_clearField(3);
  @$pb.TagNumber(3)
  $1.UnlockPath ensurePasswordPath() => $_ensure(2);
}

/// Asks for a new token for the calling session.
class RotateSessionRequest extends $pb.GeneratedMessage {
  factory RotateSessionRequest() => RotateSessionRequest._();

  RotateSessionRequest._();

  factory RotateSessionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RotateSessionRequest()..mergeFromBuffer(data, registry);
  factory RotateSessionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RotateSessionRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RotateSessionRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: RotateSessionRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RotateSessionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RotateSessionRequest copyWith(void Function(RotateSessionRequest) updates) =>
      super.copyWith((message) => updates(message as RotateSessionRequest))
          as RotateSessionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RotateSessionRequest() / RotateSessionRequest.new instead')
  static RotateSessionRequest create() => RotateSessionRequest._();
  static $pb.GeneratedMessage $_createMessage() => RotateSessionRequest._();
  @$core.override
  RotateSessionRequest createEmptyInstance() => RotateSessionRequest._();
  @$core.pragma('dart2js:noInline')
  static RotateSessionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RotateSessionRequest>(
          RotateSessionRequest.$_createMessage);
  static RotateSessionRequest? _defaultInstance;
}

/// The calling session with its new token.
class RotateSessionResponse extends $pb.GeneratedMessage {
  factory RotateSessionResponse({
    Session? session,
  }) {
    final result = RotateSessionResponse._();
    if (session != null) result.session = session;
    return result;
  }

  RotateSessionResponse._();

  factory RotateSessionResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RotateSessionResponse()..mergeFromBuffer(data, registry);
  factory RotateSessionResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RotateSessionResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RotateSessionResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: RotateSessionResponse.$_createMessage)
    ..aOM<Session>(1, _omitFieldNames ? '' : 'session',
        subBuilder: Session.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RotateSessionResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RotateSessionResponse copyWith(
          void Function(RotateSessionResponse) updates) =>
      super.copyWith((message) => updates(message as RotateSessionResponse))
          as RotateSessionResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RotateSessionResponse() / RotateSessionResponse.new instead')
  static RotateSessionResponse create() => RotateSessionResponse._();
  static $pb.GeneratedMessage $_createMessage() => RotateSessionResponse._();
  @$core.override
  RotateSessionResponse createEmptyInstance() => RotateSessionResponse._();
  @$core.pragma('dart2js:noInline')
  static RotateSessionResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RotateSessionResponse>(
          RotateSessionResponse.$_createMessage);
  static RotateSessionResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Session get session => $_getN(0);
  @$pb.TagNumber(1)
  set session(Session value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSession() => $_has(0);
  @$pb.TagNumber(1)
  void clearSession() => $_clearField(1);
  @$pb.TagNumber(1)
  Session ensureSession() => $_ensure(0);
}

/// Asks for the caller's devices.
class ListDevicesRequest extends $pb.GeneratedMessage {
  factory ListDevicesRequest() => ListDevicesRequest._();

  ListDevicesRequest._();

  factory ListDevicesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesRequest()..mergeFromBuffer(data, registry);
  factory ListDevicesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListDevicesRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListDevicesRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesRequest copyWith(void Function(ListDevicesRequest) updates) =>
      super.copyWith((message) => updates(message as ListDevicesRequest))
          as ListDevicesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListDevicesRequest() / ListDevicesRequest.new instead')
  static ListDevicesRequest create() => ListDevicesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListDevicesRequest._();
  @$core.override
  ListDevicesRequest createEmptyInstance() => ListDevicesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListDevicesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListDevicesRequest>(
          ListDevicesRequest.$_createMessage);
  static ListDevicesRequest? _defaultInstance;
}

/// The devices with a session that has not expired.
class ListDevicesResponse extends $pb.GeneratedMessage {
  factory ListDevicesResponse({
    $core.Iterable<Device>? devices,
  }) {
    final result = ListDevicesResponse._();
    if (devices != null) result.devices.addAll(devices);
    return result;
  }

  ListDevicesResponse._();

  factory ListDevicesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesResponse()..mergeFromBuffer(data, registry);
  factory ListDevicesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListDevicesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListDevicesResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListDevicesResponse.$_createMessage)
    ..pPM<Device>(1, _omitFieldNames ? '' : 'devices',
        subBuilder: Device.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListDevicesResponse copyWith(void Function(ListDevicesResponse) updates) =>
      super.copyWith((message) => updates(message as ListDevicesResponse))
          as ListDevicesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListDevicesResponse() / ListDevicesResponse.new instead')
  static ListDevicesResponse create() => ListDevicesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListDevicesResponse._();
  @$core.override
  ListDevicesResponse createEmptyInstance() => ListDevicesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListDevicesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListDevicesResponse>(
          ListDevicesResponse.$_createMessage);
  static ListDevicesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Device> get devices => $_getList(0);
}

/// The device to sign out.
class RevokeDeviceRequest extends $pb.GeneratedMessage {
  factory RevokeDeviceRequest({
    $core.String? deviceId,
  }) {
    final result = RevokeDeviceRequest._();
    if (deviceId != null) result.deviceId = deviceId;
    return result;
  }

  RevokeDeviceRequest._();

  factory RevokeDeviceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceRequest()..mergeFromBuffer(data, registry);
  factory RevokeDeviceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeDeviceRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: RevokeDeviceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceRequest copyWith(void Function(RevokeDeviceRequest) updates) =>
      super.copyWith((message) => updates(message as RevokeDeviceRequest))
          as RevokeDeviceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use RevokeDeviceRequest() / RevokeDeviceRequest.new instead')
  static RevokeDeviceRequest create() => RevokeDeviceRequest._();
  static $pb.GeneratedMessage $_createMessage() => RevokeDeviceRequest._();
  @$core.override
  RevokeDeviceRequest createEmptyInstance() => RevokeDeviceRequest._();
  @$core.pragma('dart2js:noInline')
  static RevokeDeviceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeDeviceRequest>(
          RevokeDeviceRequest.$_createMessage);
  static RevokeDeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);
}

/// The device is signed out.
class RevokeDeviceResponse extends $pb.GeneratedMessage {
  factory RevokeDeviceResponse() => RevokeDeviceResponse._();

  RevokeDeviceResponse._();

  factory RevokeDeviceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceResponse()..mergeFromBuffer(data, registry);
  factory RevokeDeviceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RevokeDeviceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeDeviceResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: RevokeDeviceResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeDeviceResponse copyWith(void Function(RevokeDeviceResponse) updates) =>
      super.copyWith((message) => updates(message as RevokeDeviceResponse))
          as RevokeDeviceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RevokeDeviceResponse() / RevokeDeviceResponse.new instead')
  static RevokeDeviceResponse create() => RevokeDeviceResponse._();
  static $pb.GeneratedMessage $_createMessage() => RevokeDeviceResponse._();
  @$core.override
  RevokeDeviceResponse createEmptyInstance() => RevokeDeviceResponse._();
  @$core.pragma('dart2js:noInline')
  static RevokeDeviceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeDeviceResponse>(
          RevokeDeviceResponse.$_createMessage);
  static RevokeDeviceResponse? _defaultInstance;
}

/// Where the calling device's backup is.
class ReportBackupRequest extends $pb.GeneratedMessage {
  factory ReportBackupRequest({
    $fixnum.Int64? pendingCount,
  }) {
    final result = ReportBackupRequest._();
    if (pendingCount != null) result.pendingCount = pendingCount;
    return result;
  }

  ReportBackupRequest._();

  factory ReportBackupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportBackupRequest()..mergeFromBuffer(data, registry);
  factory ReportBackupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportBackupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportBackupRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ReportBackupRequest.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'pendingCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportBackupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportBackupRequest copyWith(void Function(ReportBackupRequest) updates) =>
      super.copyWith((message) => updates(message as ReportBackupRequest))
          as ReportBackupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ReportBackupRequest() / ReportBackupRequest.new instead')
  static ReportBackupRequest create() => ReportBackupRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReportBackupRequest._();
  @$core.override
  ReportBackupRequest createEmptyInstance() => ReportBackupRequest._();
  @$core.pragma('dart2js:noInline')
  static ReportBackupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportBackupRequest>(
          ReportBackupRequest.$_createMessage);
  static ReportBackupRequest? _defaultInstance;

  /// Items chosen for backup that are not on the server yet; a negative count is invalid_argument `field.invalid`.
  @$pb.TagNumber(1)
  $fixnum.Int64 get pendingCount => $_getI64(0);
  @$pb.TagNumber(1)
  set pendingCount($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPendingCount() => $_has(0);
  @$pb.TagNumber(1)
  void clearPendingCount() => $_clearField(1);
}

/// The report is recorded.
class ReportBackupResponse extends $pb.GeneratedMessage {
  factory ReportBackupResponse() => ReportBackupResponse._();

  ReportBackupResponse._();

  factory ReportBackupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportBackupResponse()..mergeFromBuffer(data, registry);
  factory ReportBackupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReportBackupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReportBackupResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ReportBackupResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportBackupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReportBackupResponse copyWith(void Function(ReportBackupResponse) updates) =>
      super.copyWith((message) => updates(message as ReportBackupResponse))
          as ReportBackupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReportBackupResponse() / ReportBackupResponse.new instead')
  static ReportBackupResponse create() => ReportBackupResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReportBackupResponse._();
  @$core.override
  ReportBackupResponse createEmptyInstance() => ReportBackupResponse._();
  @$core.pragma('dart2js:noInline')
  static ReportBackupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReportBackupResponse>(
          ReportBackupResponse.$_createMessage);
  static ReportBackupResponse? _defaultInstance;
}

/// The provider and where it sends the person back.
class StartOidcRequest extends $pb.GeneratedMessage {
  factory StartOidcRequest({
    $core.String? provider,
    $core.String? redirectUri,
    $core.String? codeChallenge,
    $core.bool? link,
  }) {
    final result = StartOidcRequest._();
    if (provider != null) result.provider = provider;
    if (redirectUri != null) result.redirectUri = redirectUri;
    if (codeChallenge != null) result.codeChallenge = codeChallenge;
    if (link != null) result.link = link;
    return result;
  }

  StartOidcRequest._();

  factory StartOidcRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartOidcRequest()..mergeFromBuffer(data, registry);
  factory StartOidcRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartOidcRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartOidcRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartOidcRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'provider')
    ..aOS(2, _omitFieldNames ? '' : 'redirectUri')
    ..aOS(3, _omitFieldNames ? '' : 'codeChallenge')
    ..aOB(4, _omitFieldNames ? '' : 'link')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartOidcRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartOidcRequest copyWith(void Function(StartOidcRequest) updates) =>
      super.copyWith((message) => updates(message as StartOidcRequest))
          as StartOidcRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StartOidcRequest() / StartOidcRequest.new instead')
  static StartOidcRequest create() => StartOidcRequest._();
  static $pb.GeneratedMessage $_createMessage() => StartOidcRequest._();
  @$core.override
  StartOidcRequest createEmptyInstance() => StartOidcRequest._();
  @$core.pragma('dart2js:noInline')
  static StartOidcRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StartOidcRequest>(
          StartOidcRequest.$_createMessage);
  static StartOidcRequest? _defaultInstance;

  /// An `id` of GetServerInfoResponse.oidc_providers.
  @$pb.TagNumber(1)
  $core.String get provider => $_getSZ(0);
  @$pb.TagNumber(1)
  set provider($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProvider() => $_has(0);
  @$pb.TagNumber(1)
  void clearProvider() => $_clearField(1);

  /// Registered at the provider: the web app's page or the app's own URL scheme, such as `app.photolib:/oidc`.
  @$pb.TagNumber(2)
  $core.String get redirectUri => $_getSZ(1);
  @$pb.TagNumber(2)
  set redirectUri($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRedirectUri() => $_has(1);
  @$pb.TagNumber(2)
  void clearRedirectUri() => $_clearField(2);

  /// BASE64URL(SHA-256(code_verifier)) without padding: the S256 challenge of a verifier of 43 to 128 characters.
  @$pb.TagNumber(3)
  $core.String get codeChallenge => $_getSZ(2);
  @$pb.TagNumber(3)
  set codeChallenge($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCodeChallenge() => $_has(2);
  @$pb.TagNumber(3)
  void clearCodeChallenge() => $_clearField(3);

  /// Links the identity to the calling session's account instead of signing in.
  @$pb.TagNumber(4)
  $core.bool get link => $_getBF(3);
  @$pb.TagNumber(4)
  set link($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLink() => $_has(3);
  @$pb.TagNumber(4)
  void clearLink() => $_clearField(4);
}

/// Where to send the person.
class StartOidcResponse extends $pb.GeneratedMessage {
  factory StartOidcResponse({
    $core.String? authorizationUrl,
  }) {
    final result = StartOidcResponse._();
    if (authorizationUrl != null) result.authorizationUrl = authorizationUrl;
    return result;
  }

  StartOidcResponse._();

  factory StartOidcResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartOidcResponse()..mergeFromBuffer(data, registry);
  factory StartOidcResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartOidcResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartOidcResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartOidcResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'authorizationUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartOidcResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartOidcResponse copyWith(void Function(StartOidcResponse) updates) =>
      super.copyWith((message) => updates(message as StartOidcResponse))
          as StartOidcResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StartOidcResponse() / StartOidcResponse.new instead')
  static StartOidcResponse create() => StartOidcResponse._();
  static $pb.GeneratedMessage $_createMessage() => StartOidcResponse._();
  @$core.override
  StartOidcResponse createEmptyInstance() => StartOidcResponse._();
  @$core.pragma('dart2js:noInline')
  static StartOidcResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StartOidcResponse>(
          StartOidcResponse.$_createMessage);
  static StartOidcResponse? _defaultInstance;

  /// Valid for ten minutes and once.
  @$pb.TagNumber(1)
  $core.String get authorizationUrl => $_getSZ(0);
  @$pb.TagNumber(1)
  set authorizationUrl($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAuthorizationUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuthorizationUrl() => $_clearField(1);
}

/// What the provider appended to the redirect URI, and the client's PKCE verifier.
class CompleteOidcRequest extends $pb.GeneratedMessage {
  factory CompleteOidcRequest({
    $core.String? state,
    $core.String? code,
    $core.String? codeVerifier,
    Device? device,
  }) {
    final result = CompleteOidcRequest._();
    if (state != null) result.state = state;
    if (code != null) result.code = code;
    if (codeVerifier != null) result.codeVerifier = codeVerifier;
    if (device != null) result.device = device;
    return result;
  }

  CompleteOidcRequest._();

  factory CompleteOidcRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CompleteOidcRequest()..mergeFromBuffer(data, registry);
  factory CompleteOidcRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CompleteOidcRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompleteOidcRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CompleteOidcRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'state')
    ..aOS(2, _omitFieldNames ? '' : 'code')
    ..aOS(3, _omitFieldNames ? '' : 'codeVerifier')
    ..aOM<Device>(4, _omitFieldNames ? '' : 'device',
        subBuilder: Device.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompleteOidcRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompleteOidcRequest copyWith(void Function(CompleteOidcRequest) updates) =>
      super.copyWith((message) => updates(message as CompleteOidcRequest))
          as CompleteOidcRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use CompleteOidcRequest() / CompleteOidcRequest.new instead')
  static CompleteOidcRequest create() => CompleteOidcRequest._();
  static $pb.GeneratedMessage $_createMessage() => CompleteOidcRequest._();
  @$core.override
  CompleteOidcRequest createEmptyInstance() => CompleteOidcRequest._();
  @$core.pragma('dart2js:noInline')
  static CompleteOidcRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompleteOidcRequest>(
          CompleteOidcRequest.$_createMessage);
  static CompleteOidcRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get state => $_getSZ(0);
  @$pb.TagNumber(1)
  set state($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get code => $_getSZ(1);
  @$pb.TagNumber(2)
  set code($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearCode() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get codeVerifier => $_getSZ(2);
  @$pb.TagNumber(3)
  set codeVerifier($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCodeVerifier() => $_has(2);
  @$pb.TagNumber(3)
  void clearCodeVerifier() => $_clearField(3);

  /// As in FinishLoginRequest, also when linking, which opens no session.
  @$pb.TagNumber(4)
  Device get device => $_getN(3);
  @$pb.TagNumber(4)
  set device(Device value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasDevice() => $_has(3);
  @$pb.TagNumber(4)
  void clearDevice() => $_clearField(4);
  @$pb.TagNumber(4)
  Device ensureDevice() => $_ensure(3);
}

/// The new session, or nothing after linking.
class CompleteOidcResponse extends $pb.GeneratedMessage {
  factory CompleteOidcResponse({
    Session? session,
  }) {
    final result = CompleteOidcResponse._();
    if (session != null) result.session = session;
    return result;
  }

  CompleteOidcResponse._();

  factory CompleteOidcResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CompleteOidcResponse()..mergeFromBuffer(data, registry);
  factory CompleteOidcResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CompleteOidcResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompleteOidcResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CompleteOidcResponse.$_createMessage)
    ..aOM<Session>(1, _omitFieldNames ? '' : 'session',
        subBuilder: Session.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompleteOidcResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompleteOidcResponse copyWith(void Function(CompleteOidcResponse) updates) =>
      super.copyWith((message) => updates(message as CompleteOidcResponse))
          as CompleteOidcResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CompleteOidcResponse() / CompleteOidcResponse.new instead')
  static CompleteOidcResponse create() => CompleteOidcResponse._();
  static $pb.GeneratedMessage $_createMessage() => CompleteOidcResponse._();
  @$core.override
  CompleteOidcResponse createEmptyInstance() => CompleteOidcResponse._();
  @$core.pragma('dart2js:noInline')
  static CompleteOidcResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompleteOidcResponse>(
          CompleteOidcResponse.$_createMessage);
  static CompleteOidcResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Session get session => $_getN(0);
  @$pb.TagNumber(1)
  set session(Session value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSession() => $_has(0);
  @$pb.TagNumber(1)
  void clearSession() => $_clearField(1);
  @$pb.TagNumber(1)
  Session ensureSession() => $_ensure(0);
}

enum FinishSecondFactorRequest_Answer {
  totpCode,
  recoveryCode,
  passkeyCredentialJson,
  notSet
}

/// The answer to a second factor challenge.
class FinishSecondFactorRequest extends $pb.GeneratedMessage {
  factory FinishSecondFactorRequest({
    $core.String? loginId,
    $core.String? totpCode,
    $core.String? recoveryCode,
    $core.String? passkeyCredentialJson,
  }) {
    final result = FinishSecondFactorRequest._();
    if (loginId != null) result.loginId = loginId;
    if (totpCode != null) result.totpCode = totpCode;
    if (recoveryCode != null) result.recoveryCode = recoveryCode;
    if (passkeyCredentialJson != null)
      result.passkeyCredentialJson = passkeyCredentialJson;
    return result;
  }

  FinishSecondFactorRequest._();

  factory FinishSecondFactorRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishSecondFactorRequest()..mergeFromBuffer(data, registry);
  factory FinishSecondFactorRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishSecondFactorRequest()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FinishSecondFactorRequest_Answer>
      _FinishSecondFactorRequest_AnswerByTag = {
    2: FinishSecondFactorRequest_Answer.totpCode,
    3: FinishSecondFactorRequest_Answer.recoveryCode,
    4: FinishSecondFactorRequest_Answer.passkeyCredentialJson,
    0: FinishSecondFactorRequest_Answer.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishSecondFactorRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishSecondFactorRequest.$_createMessage)
    ..oo(0, [2, 3, 4])
    ..aOS(1, _omitFieldNames ? '' : 'loginId')
    ..aOS(2, _omitFieldNames ? '' : 'totpCode')
    ..aOS(3, _omitFieldNames ? '' : 'recoveryCode')
    ..aOS(4, _omitFieldNames ? '' : 'passkeyCredentialJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishSecondFactorRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishSecondFactorRequest copyWith(
          void Function(FinishSecondFactorRequest) updates) =>
      super.copyWith((message) => updates(message as FinishSecondFactorRequest))
          as FinishSecondFactorRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishSecondFactorRequest() / FinishSecondFactorRequest.new instead')
  static FinishSecondFactorRequest create() => FinishSecondFactorRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinishSecondFactorRequest._();
  @$core.override
  FinishSecondFactorRequest createEmptyInstance() =>
      FinishSecondFactorRequest._();
  @$core.pragma('dart2js:noInline')
  static FinishSecondFactorRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishSecondFactorRequest>(
          FinishSecondFactorRequest.$_createMessage);
  static FinishSecondFactorRequest? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  FinishSecondFactorRequest_Answer whichAnswer() =>
      _FinishSecondFactorRequest_AnswerByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearAnswer() => $_clearField($_whichOneof(0));

  /// From SecondFactorChallenge.
  @$pb.TagNumber(1)
  $core.String get loginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set loginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLoginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLoginId() => $_clearField(1);

  /// Six digits from the authenticator app; each code counts once.
  @$pb.TagNumber(2)
  $core.String get totpCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set totpCode($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotpCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotpCode() => $_clearField(2);

  /// One of the account's recovery codes, which it uses up.
  @$pb.TagNumber(3)
  $core.String get recoveryCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set recoveryCode($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRecoveryCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearRecoveryCode() => $_clearField(3);

  /// The AuthenticationResponseJSON of the passkey for `passkey_options_json`.
  @$pb.TagNumber(4)
  $core.String get passkeyCredentialJson => $_getSZ(3);
  @$pb.TagNumber(4)
  set passkeyCredentialJson($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPasskeyCredentialJson() => $_has(3);
  @$pb.TagNumber(4)
  void clearPasskeyCredentialJson() => $_clearField(4);
}

/// The new session.
class FinishSecondFactorResponse extends $pb.GeneratedMessage {
  factory FinishSecondFactorResponse({
    Session? session,
    $1.UnlockPath? passwordPath,
  }) {
    final result = FinishSecondFactorResponse._();
    if (session != null) result.session = session;
    if (passwordPath != null) result.passwordPath = passwordPath;
    return result;
  }

  FinishSecondFactorResponse._();

  factory FinishSecondFactorResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishSecondFactorResponse()..mergeFromBuffer(data, registry);
  factory FinishSecondFactorResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishSecondFactorResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishSecondFactorResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishSecondFactorResponse.$_createMessage)
    ..aOM<Session>(1, _omitFieldNames ? '' : 'session',
        subBuilder: Session.$_createMessage)
    ..aOM<$1.UnlockPath>(2, _omitFieldNames ? '' : 'passwordPath',
        subBuilder: $1.UnlockPath.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishSecondFactorResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishSecondFactorResponse copyWith(
          void Function(FinishSecondFactorResponse) updates) =>
      super.copyWith(
              (message) => updates(message as FinishSecondFactorResponse))
          as FinishSecondFactorResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishSecondFactorResponse() / FinishSecondFactorResponse.new instead')
  static FinishSecondFactorResponse create() => FinishSecondFactorResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinishSecondFactorResponse._();
  @$core.override
  FinishSecondFactorResponse createEmptyInstance() =>
      FinishSecondFactorResponse._();
  @$core.pragma('dart2js:noInline')
  static FinishSecondFactorResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishSecondFactorResponse>(
          FinishSecondFactorResponse.$_createMessage);
  static FinishSecondFactorResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Session get session => $_getN(0);
  @$pb.TagNumber(1)
  set session(Session value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSession() => $_has(0);
  @$pb.TagNumber(1)
  void clearSession() => $_clearField(1);
  @$pb.TagNumber(1)
  Session ensureSession() => $_ensure(0);

  /// As FinishLoginResponse's.
  @$pb.TagNumber(2)
  $1.UnlockPath get passwordPath => $_getN(1);
  @$pb.TagNumber(2)
  set passwordPath($1.UnlockPath value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPasswordPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearPasswordPath() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.UnlockPath ensurePasswordPath() => $_ensure(1);
}

/// Asks to sign in with a passkey.
class StartPasskeyLoginRequest extends $pb.GeneratedMessage {
  factory StartPasskeyLoginRequest() => StartPasskeyLoginRequest._();

  StartPasskeyLoginRequest._();

  factory StartPasskeyLoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasskeyLoginRequest()..mergeFromBuffer(data, registry);
  factory StartPasskeyLoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasskeyLoginRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartPasskeyLoginRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartPasskeyLoginRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasskeyLoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasskeyLoginRequest copyWith(
          void Function(StartPasskeyLoginRequest) updates) =>
      super.copyWith((message) => updates(message as StartPasskeyLoginRequest))
          as StartPasskeyLoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartPasskeyLoginRequest() / StartPasskeyLoginRequest.new instead')
  static StartPasskeyLoginRequest create() => StartPasskeyLoginRequest._();
  static $pb.GeneratedMessage $_createMessage() => StartPasskeyLoginRequest._();
  @$core.override
  StartPasskeyLoginRequest createEmptyInstance() =>
      StartPasskeyLoginRequest._();
  @$core.pragma('dart2js:noInline')
  static StartPasskeyLoginRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartPasskeyLoginRequest>(
          StartPasskeyLoginRequest.$_createMessage);
  static StartPasskeyLoginRequest? _defaultInstance;
}

/// The ceremony to run.
class StartPasskeyLoginResponse extends $pb.GeneratedMessage {
  factory StartPasskeyLoginResponse({
    $core.String? loginId,
    $core.String? optionsJson,
  }) {
    final result = StartPasskeyLoginResponse._();
    if (loginId != null) result.loginId = loginId;
    if (optionsJson != null) result.optionsJson = optionsJson;
    return result;
  }

  StartPasskeyLoginResponse._();

  factory StartPasskeyLoginResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasskeyLoginResponse()..mergeFromBuffer(data, registry);
  factory StartPasskeyLoginResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasskeyLoginResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartPasskeyLoginResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartPasskeyLoginResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'loginId')
    ..aOS(2, _omitFieldNames ? '' : 'optionsJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasskeyLoginResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasskeyLoginResponse copyWith(
          void Function(StartPasskeyLoginResponse) updates) =>
      super.copyWith((message) => updates(message as StartPasskeyLoginResponse))
          as StartPasskeyLoginResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartPasskeyLoginResponse() / StartPasskeyLoginResponse.new instead')
  static StartPasskeyLoginResponse create() => StartPasskeyLoginResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      StartPasskeyLoginResponse._();
  @$core.override
  StartPasskeyLoginResponse createEmptyInstance() =>
      StartPasskeyLoginResponse._();
  @$core.pragma('dart2js:noInline')
  static StartPasskeyLoginResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartPasskeyLoginResponse>(
          StartPasskeyLoginResponse.$_createMessage);
  static StartPasskeyLoginResponse? _defaultInstance;

  /// Names this sign-in in FinishPasskeyLogin, for five minutes.
  @$pb.TagNumber(1)
  $core.String get loginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set loginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLoginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLoginId() => $_clearField(1);

  /// PublicKeyCredentialRequestOptionsJSON.
  @$pb.TagNumber(2)
  $core.String get optionsJson => $_getSZ(1);
  @$pb.TagNumber(2)
  set optionsJson($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOptionsJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptionsJson() => $_clearField(2);
}

/// The passkey's answer and the device that signs in.
class FinishPasskeyLoginRequest extends $pb.GeneratedMessage {
  factory FinishPasskeyLoginRequest({
    $core.String? loginId,
    $core.String? credentialJson,
    Device? device,
  }) {
    final result = FinishPasskeyLoginRequest._();
    if (loginId != null) result.loginId = loginId;
    if (credentialJson != null) result.credentialJson = credentialJson;
    if (device != null) result.device = device;
    return result;
  }

  FinishPasskeyLoginRequest._();

  factory FinishPasskeyLoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasskeyLoginRequest()..mergeFromBuffer(data, registry);
  factory FinishPasskeyLoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasskeyLoginRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishPasskeyLoginRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishPasskeyLoginRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'loginId')
    ..aOS(2, _omitFieldNames ? '' : 'credentialJson')
    ..aOM<Device>(3, _omitFieldNames ? '' : 'device',
        subBuilder: Device.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasskeyLoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasskeyLoginRequest copyWith(
          void Function(FinishPasskeyLoginRequest) updates) =>
      super.copyWith((message) => updates(message as FinishPasskeyLoginRequest))
          as FinishPasskeyLoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishPasskeyLoginRequest() / FinishPasskeyLoginRequest.new instead')
  static FinishPasskeyLoginRequest create() => FinishPasskeyLoginRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinishPasskeyLoginRequest._();
  @$core.override
  FinishPasskeyLoginRequest createEmptyInstance() =>
      FinishPasskeyLoginRequest._();
  @$core.pragma('dart2js:noInline')
  static FinishPasskeyLoginRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishPasskeyLoginRequest>(
          FinishPasskeyLoginRequest.$_createMessage);
  static FinishPasskeyLoginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get loginId => $_getSZ(0);
  @$pb.TagNumber(1)
  set loginId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLoginId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLoginId() => $_clearField(1);

  /// The AuthenticationResponseJSON.
  @$pb.TagNumber(2)
  $core.String get credentialJson => $_getSZ(1);
  @$pb.TagNumber(2)
  set credentialJson($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCredentialJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearCredentialJson() => $_clearField(2);

  /// As in FinishLoginRequest.
  @$pb.TagNumber(3)
  Device get device => $_getN(2);
  @$pb.TagNumber(3)
  set device(Device value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDevice() => $_has(2);
  @$pb.TagNumber(3)
  void clearDevice() => $_clearField(3);
  @$pb.TagNumber(3)
  Device ensureDevice() => $_ensure(2);
}

/// The new session.
class FinishPasskeyLoginResponse extends $pb.GeneratedMessage {
  factory FinishPasskeyLoginResponse({
    Session? session,
  }) {
    final result = FinishPasskeyLoginResponse._();
    if (session != null) result.session = session;
    return result;
  }

  FinishPasskeyLoginResponse._();

  factory FinishPasskeyLoginResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasskeyLoginResponse()..mergeFromBuffer(data, registry);
  factory FinishPasskeyLoginResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasskeyLoginResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishPasskeyLoginResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishPasskeyLoginResponse.$_createMessage)
    ..aOM<Session>(1, _omitFieldNames ? '' : 'session',
        subBuilder: Session.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasskeyLoginResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasskeyLoginResponse copyWith(
          void Function(FinishPasskeyLoginResponse) updates) =>
      super.copyWith(
              (message) => updates(message as FinishPasskeyLoginResponse))
          as FinishPasskeyLoginResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishPasskeyLoginResponse() / FinishPasskeyLoginResponse.new instead')
  static FinishPasskeyLoginResponse create() => FinishPasskeyLoginResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinishPasskeyLoginResponse._();
  @$core.override
  FinishPasskeyLoginResponse createEmptyInstance() =>
      FinishPasskeyLoginResponse._();
  @$core.pragma('dart2js:noInline')
  static FinishPasskeyLoginResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishPasskeyLoginResponse>(
          FinishPasskeyLoginResponse.$_createMessage);
  static FinishPasskeyLoginResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Session get session => $_getN(0);
  @$pb.TagNumber(1)
  set session(Session value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSession() => $_has(0);
  @$pb.TagNumber(1)
  void clearSession() => $_clearField(1);
  @$pb.TagNumber(1)
  Session ensureSession() => $_ensure(0);
}

/// Asks to add a passkey to the caller's account.
class StartPasskeySetupRequest extends $pb.GeneratedMessage {
  factory StartPasskeySetupRequest() => StartPasskeySetupRequest._();

  StartPasskeySetupRequest._();

  factory StartPasskeySetupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasskeySetupRequest()..mergeFromBuffer(data, registry);
  factory StartPasskeySetupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasskeySetupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartPasskeySetupRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartPasskeySetupRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasskeySetupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasskeySetupRequest copyWith(
          void Function(StartPasskeySetupRequest) updates) =>
      super.copyWith((message) => updates(message as StartPasskeySetupRequest))
          as StartPasskeySetupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartPasskeySetupRequest() / StartPasskeySetupRequest.new instead')
  static StartPasskeySetupRequest create() => StartPasskeySetupRequest._();
  static $pb.GeneratedMessage $_createMessage() => StartPasskeySetupRequest._();
  @$core.override
  StartPasskeySetupRequest createEmptyInstance() =>
      StartPasskeySetupRequest._();
  @$core.pragma('dart2js:noInline')
  static StartPasskeySetupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartPasskeySetupRequest>(
          StartPasskeySetupRequest.$_createMessage);
  static StartPasskeySetupRequest? _defaultInstance;
}

/// The ceremony to run.
class StartPasskeySetupResponse extends $pb.GeneratedMessage {
  factory StartPasskeySetupResponse({
    $core.String? setupId,
    $core.String? optionsJson,
  }) {
    final result = StartPasskeySetupResponse._();
    if (setupId != null) result.setupId = setupId;
    if (optionsJson != null) result.optionsJson = optionsJson;
    return result;
  }

  StartPasskeySetupResponse._();

  factory StartPasskeySetupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasskeySetupResponse()..mergeFromBuffer(data, registry);
  factory StartPasskeySetupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartPasskeySetupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartPasskeySetupResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartPasskeySetupResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'setupId')
    ..aOS(2, _omitFieldNames ? '' : 'optionsJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasskeySetupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartPasskeySetupResponse copyWith(
          void Function(StartPasskeySetupResponse) updates) =>
      super.copyWith((message) => updates(message as StartPasskeySetupResponse))
          as StartPasskeySetupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartPasskeySetupResponse() / StartPasskeySetupResponse.new instead')
  static StartPasskeySetupResponse create() => StartPasskeySetupResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      StartPasskeySetupResponse._();
  @$core.override
  StartPasskeySetupResponse createEmptyInstance() =>
      StartPasskeySetupResponse._();
  @$core.pragma('dart2js:noInline')
  static StartPasskeySetupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartPasskeySetupResponse>(
          StartPasskeySetupResponse.$_createMessage);
  static StartPasskeySetupResponse? _defaultInstance;

  /// Names this setup in FinishPasskeySetup, for five minutes.
  @$pb.TagNumber(1)
  $core.String get setupId => $_getSZ(0);
  @$pb.TagNumber(1)
  set setupId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSetupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSetupId() => $_clearField(1);

  /// PublicKeyCredentialCreationOptionsJSON.
  @$pb.TagNumber(2)
  $core.String get optionsJson => $_getSZ(1);
  @$pb.TagNumber(2)
  set optionsJson($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOptionsJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptionsJson() => $_clearField(2);
}

/// The new passkey.
class FinishPasskeySetupRequest extends $pb.GeneratedMessage {
  factory FinishPasskeySetupRequest({
    $core.String? setupId,
    $core.String? credentialJson,
    $core.String? name,
  }) {
    final result = FinishPasskeySetupRequest._();
    if (setupId != null) result.setupId = setupId;
    if (credentialJson != null) result.credentialJson = credentialJson;
    if (name != null) result.name = name;
    return result;
  }

  FinishPasskeySetupRequest._();

  factory FinishPasskeySetupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasskeySetupRequest()..mergeFromBuffer(data, registry);
  factory FinishPasskeySetupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasskeySetupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishPasskeySetupRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishPasskeySetupRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'setupId')
    ..aOS(2, _omitFieldNames ? '' : 'credentialJson')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasskeySetupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasskeySetupRequest copyWith(
          void Function(FinishPasskeySetupRequest) updates) =>
      super.copyWith((message) => updates(message as FinishPasskeySetupRequest))
          as FinishPasskeySetupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishPasskeySetupRequest() / FinishPasskeySetupRequest.new instead')
  static FinishPasskeySetupRequest create() => FinishPasskeySetupRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinishPasskeySetupRequest._();
  @$core.override
  FinishPasskeySetupRequest createEmptyInstance() =>
      FinishPasskeySetupRequest._();
  @$core.pragma('dart2js:noInline')
  static FinishPasskeySetupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishPasskeySetupRequest>(
          FinishPasskeySetupRequest.$_createMessage);
  static FinishPasskeySetupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get setupId => $_getSZ(0);
  @$pb.TagNumber(1)
  set setupId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSetupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSetupId() => $_clearField(1);

  /// The RegistrationResponseJSON.
  @$pb.TagNumber(2)
  $core.String get credentialJson => $_getSZ(1);
  @$pb.TagNumber(2)
  set credentialJson($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCredentialJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearCredentialJson() => $_clearField(2);

  /// As in Passkey.
  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);
}

/// The stored passkey.
class FinishPasskeySetupResponse extends $pb.GeneratedMessage {
  factory FinishPasskeySetupResponse({
    Passkey? passkey,
    $core.Iterable<$core.String>? recoveryCodes,
  }) {
    final result = FinishPasskeySetupResponse._();
    if (passkey != null) result.passkey = passkey;
    if (recoveryCodes != null) result.recoveryCodes.addAll(recoveryCodes);
    return result;
  }

  FinishPasskeySetupResponse._();

  factory FinishPasskeySetupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasskeySetupResponse()..mergeFromBuffer(data, registry);
  factory FinishPasskeySetupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishPasskeySetupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishPasskeySetupResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishPasskeySetupResponse.$_createMessage)
    ..aOM<Passkey>(1, _omitFieldNames ? '' : 'passkey',
        subBuilder: Passkey.$_createMessage)
    ..pPS(2, _omitFieldNames ? '' : 'recoveryCodes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasskeySetupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishPasskeySetupResponse copyWith(
          void Function(FinishPasskeySetupResponse) updates) =>
      super.copyWith(
              (message) => updates(message as FinishPasskeySetupResponse))
          as FinishPasskeySetupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishPasskeySetupResponse() / FinishPasskeySetupResponse.new instead')
  static FinishPasskeySetupResponse create() => FinishPasskeySetupResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      FinishPasskeySetupResponse._();
  @$core.override
  FinishPasskeySetupResponse createEmptyInstance() =>
      FinishPasskeySetupResponse._();
  @$core.pragma('dart2js:noInline')
  static FinishPasskeySetupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishPasskeySetupResponse>(
          FinishPasskeySetupResponse.$_createMessage);
  static FinishPasskeySetupResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Passkey get passkey => $_getN(0);
  @$pb.TagNumber(1)
  set passkey(Passkey value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPasskey() => $_has(0);
  @$pb.TagNumber(1)
  void clearPasskey() => $_clearField(1);
  @$pb.TagNumber(1)
  Passkey ensurePasskey() => $_ensure(0);

  /// Ten new recovery codes, to show once, when the account had none left; otherwise empty.
  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get recoveryCodes => $_getList(1);
}

/// Asks for a new TOTP secret.
class StartTotpSetupRequest extends $pb.GeneratedMessage {
  factory StartTotpSetupRequest() => StartTotpSetupRequest._();

  StartTotpSetupRequest._();

  factory StartTotpSetupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartTotpSetupRequest()..mergeFromBuffer(data, registry);
  factory StartTotpSetupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartTotpSetupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartTotpSetupRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartTotpSetupRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartTotpSetupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartTotpSetupRequest copyWith(
          void Function(StartTotpSetupRequest) updates) =>
      super.copyWith((message) => updates(message as StartTotpSetupRequest))
          as StartTotpSetupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartTotpSetupRequest() / StartTotpSetupRequest.new instead')
  static StartTotpSetupRequest create() => StartTotpSetupRequest._();
  static $pb.GeneratedMessage $_createMessage() => StartTotpSetupRequest._();
  @$core.override
  StartTotpSetupRequest createEmptyInstance() => StartTotpSetupRequest._();
  @$core.pragma('dart2js:noInline')
  static StartTotpSetupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartTotpSetupRequest>(
          StartTotpSetupRequest.$_createMessage);
  static StartTotpSetupRequest? _defaultInstance;
}

/// The secret to give the authenticator app.
class StartTotpSetupResponse extends $pb.GeneratedMessage {
  factory StartTotpSetupResponse({
    $core.String? setupId,
    $core.String? secret,
    $core.String? uri,
  }) {
    final result = StartTotpSetupResponse._();
    if (setupId != null) result.setupId = setupId;
    if (secret != null) result.secret = secret;
    if (uri != null) result.uri = uri;
    return result;
  }

  StartTotpSetupResponse._();

  factory StartTotpSetupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartTotpSetupResponse()..mergeFromBuffer(data, registry);
  factory StartTotpSetupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartTotpSetupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartTotpSetupResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartTotpSetupResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'setupId')
    ..aOS(2, _omitFieldNames ? '' : 'secret')
    ..aOS(3, _omitFieldNames ? '' : 'uri')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartTotpSetupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartTotpSetupResponse copyWith(
          void Function(StartTotpSetupResponse) updates) =>
      super.copyWith((message) => updates(message as StartTotpSetupResponse))
          as StartTotpSetupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StartTotpSetupResponse() / StartTotpSetupResponse.new instead')
  static StartTotpSetupResponse create() => StartTotpSetupResponse._();
  static $pb.GeneratedMessage $_createMessage() => StartTotpSetupResponse._();
  @$core.override
  StartTotpSetupResponse createEmptyInstance() => StartTotpSetupResponse._();
  @$core.pragma('dart2js:noInline')
  static StartTotpSetupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartTotpSetupResponse>(
          StartTotpSetupResponse.$_createMessage);
  static StartTotpSetupResponse? _defaultInstance;

  /// Names this setup in FinishTotpSetup, for ten minutes.
  @$pb.TagNumber(1)
  $core.String get setupId => $_getSZ(0);
  @$pb.TagNumber(1)
  set setupId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSetupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSetupId() => $_clearField(1);

  /// The secret in base32, for typing in.
  @$pb.TagNumber(2)
  $core.String get secret => $_getSZ(1);
  @$pb.TagNumber(2)
  set secret($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearSecret() => $_clearField(2);

  /// The same as an otpauth:// URI, for a QR code.
  @$pb.TagNumber(3)
  $core.String get uri => $_getSZ(2);
  @$pb.TagNumber(3)
  set uri($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUri() => $_has(2);
  @$pb.TagNumber(3)
  void clearUri() => $_clearField(3);
}

/// A code of the new secret.
class FinishTotpSetupRequest extends $pb.GeneratedMessage {
  factory FinishTotpSetupRequest({
    $core.String? setupId,
    $core.String? code,
  }) {
    final result = FinishTotpSetupRequest._();
    if (setupId != null) result.setupId = setupId;
    if (code != null) result.code = code;
    return result;
  }

  FinishTotpSetupRequest._();

  factory FinishTotpSetupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishTotpSetupRequest()..mergeFromBuffer(data, registry);
  factory FinishTotpSetupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishTotpSetupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishTotpSetupRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishTotpSetupRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'setupId')
    ..aOS(2, _omitFieldNames ? '' : 'code')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishTotpSetupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishTotpSetupRequest copyWith(
          void Function(FinishTotpSetupRequest) updates) =>
      super.copyWith((message) => updates(message as FinishTotpSetupRequest))
          as FinishTotpSetupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishTotpSetupRequest() / FinishTotpSetupRequest.new instead')
  static FinishTotpSetupRequest create() => FinishTotpSetupRequest._();
  static $pb.GeneratedMessage $_createMessage() => FinishTotpSetupRequest._();
  @$core.override
  FinishTotpSetupRequest createEmptyInstance() => FinishTotpSetupRequest._();
  @$core.pragma('dart2js:noInline')
  static FinishTotpSetupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishTotpSetupRequest>(
          FinishTotpSetupRequest.$_createMessage);
  static FinishTotpSetupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get setupId => $_getSZ(0);
  @$pb.TagNumber(1)
  set setupId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSetupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSetupId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get code => $_getSZ(1);
  @$pb.TagNumber(2)
  set code($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearCode() => $_clearField(2);
}

/// TOTP is on.
class FinishTotpSetupResponse extends $pb.GeneratedMessage {
  factory FinishTotpSetupResponse({
    $core.Iterable<$core.String>? recoveryCodes,
  }) {
    final result = FinishTotpSetupResponse._();
    if (recoveryCodes != null) result.recoveryCodes.addAll(recoveryCodes);
    return result;
  }

  FinishTotpSetupResponse._();

  factory FinishTotpSetupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishTotpSetupResponse()..mergeFromBuffer(data, registry);
  factory FinishTotpSetupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishTotpSetupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishTotpSetupResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishTotpSetupResponse.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'recoveryCodes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishTotpSetupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishTotpSetupResponse copyWith(
          void Function(FinishTotpSetupResponse) updates) =>
      super.copyWith((message) => updates(message as FinishTotpSetupResponse))
          as FinishTotpSetupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishTotpSetupResponse() / FinishTotpSetupResponse.new instead')
  static FinishTotpSetupResponse create() => FinishTotpSetupResponse._();
  static $pb.GeneratedMessage $_createMessage() => FinishTotpSetupResponse._();
  @$core.override
  FinishTotpSetupResponse createEmptyInstance() => FinishTotpSetupResponse._();
  @$core.pragma('dart2js:noInline')
  static FinishTotpSetupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishTotpSetupResponse>(
          FinishTotpSetupResponse.$_createMessage);
  static FinishTotpSetupResponse? _defaultInstance;

  /// Ten new recovery codes, to show once, when the account had none left; otherwise empty.
  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get recoveryCodes => $_getList(0);
}

/// Asks for the caller's second factors.
class ListSecondFactorsRequest extends $pb.GeneratedMessage {
  factory ListSecondFactorsRequest() => ListSecondFactorsRequest._();

  ListSecondFactorsRequest._();

  factory ListSecondFactorsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSecondFactorsRequest()..mergeFromBuffer(data, registry);
  factory ListSecondFactorsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSecondFactorsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSecondFactorsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListSecondFactorsRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSecondFactorsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSecondFactorsRequest copyWith(
          void Function(ListSecondFactorsRequest) updates) =>
      super.copyWith((message) => updates(message as ListSecondFactorsRequest))
          as ListSecondFactorsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListSecondFactorsRequest() / ListSecondFactorsRequest.new instead')
  static ListSecondFactorsRequest create() => ListSecondFactorsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListSecondFactorsRequest._();
  @$core.override
  ListSecondFactorsRequest createEmptyInstance() =>
      ListSecondFactorsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListSecondFactorsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSecondFactorsRequest>(
          ListSecondFactorsRequest.$_createMessage);
  static ListSecondFactorsRequest? _defaultInstance;
}

/// The caller's second factors.
class ListSecondFactorsResponse extends $pb.GeneratedMessage {
  factory ListSecondFactorsResponse({
    $core.Iterable<Passkey>? passkeys,
    $core.bool? totp,
    $core.int? recoveryCodesLeft,
  }) {
    final result = ListSecondFactorsResponse._();
    if (passkeys != null) result.passkeys.addAll(passkeys);
    if (totp != null) result.totp = totp;
    if (recoveryCodesLeft != null) result.recoveryCodesLeft = recoveryCodesLeft;
    return result;
  }

  ListSecondFactorsResponse._();

  factory ListSecondFactorsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSecondFactorsResponse()..mergeFromBuffer(data, registry);
  factory ListSecondFactorsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListSecondFactorsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSecondFactorsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListSecondFactorsResponse.$_createMessage)
    ..pPM<Passkey>(1, _omitFieldNames ? '' : 'passkeys',
        subBuilder: Passkey.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'totp')
    ..aI(3, _omitFieldNames ? '' : 'recoveryCodesLeft',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSecondFactorsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSecondFactorsResponse copyWith(
          void Function(ListSecondFactorsResponse) updates) =>
      super.copyWith((message) => updates(message as ListSecondFactorsResponse))
          as ListSecondFactorsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListSecondFactorsResponse() / ListSecondFactorsResponse.new instead')
  static ListSecondFactorsResponse create() => ListSecondFactorsResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      ListSecondFactorsResponse._();
  @$core.override
  ListSecondFactorsResponse createEmptyInstance() =>
      ListSecondFactorsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListSecondFactorsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSecondFactorsResponse>(
          ListSecondFactorsResponse.$_createMessage);
  static ListSecondFactorsResponse? _defaultInstance;

  /// Oldest first.
  @$pb.TagNumber(1)
  $pb.PbList<Passkey> get passkeys => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get totp => $_getBF(1);
  @$pb.TagNumber(2)
  set totp($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotp() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get recoveryCodesLeft => $_getIZ(2);
  @$pb.TagNumber(3)
  set recoveryCodesLeft($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRecoveryCodesLeft() => $_has(2);
  @$pb.TagNumber(3)
  void clearRecoveryCodesLeft() => $_clearField(3);
}

/// The passkey to remove.
class DeletePasskeyRequest extends $pb.GeneratedMessage {
  factory DeletePasskeyRequest({
    $core.String? passkeyId,
  }) {
    final result = DeletePasskeyRequest._();
    if (passkeyId != null) result.passkeyId = passkeyId;
    return result;
  }

  DeletePasskeyRequest._();

  factory DeletePasskeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeletePasskeyRequest()..mergeFromBuffer(data, registry);
  factory DeletePasskeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeletePasskeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeletePasskeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: DeletePasskeyRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'passkeyId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletePasskeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletePasskeyRequest copyWith(void Function(DeletePasskeyRequest) updates) =>
      super.copyWith((message) => updates(message as DeletePasskeyRequest))
          as DeletePasskeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeletePasskeyRequest() / DeletePasskeyRequest.new instead')
  static DeletePasskeyRequest create() => DeletePasskeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeletePasskeyRequest._();
  @$core.override
  DeletePasskeyRequest createEmptyInstance() => DeletePasskeyRequest._();
  @$core.pragma('dart2js:noInline')
  static DeletePasskeyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeletePasskeyRequest>(
          DeletePasskeyRequest.$_createMessage);
  static DeletePasskeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get passkeyId => $_getSZ(0);
  @$pb.TagNumber(1)
  set passkeyId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPasskeyId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPasskeyId() => $_clearField(1);
}

/// The passkey is removed.
class DeletePasskeyResponse extends $pb.GeneratedMessage {
  factory DeletePasskeyResponse() => DeletePasskeyResponse._();

  DeletePasskeyResponse._();

  factory DeletePasskeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeletePasskeyResponse()..mergeFromBuffer(data, registry);
  factory DeletePasskeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeletePasskeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeletePasskeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: DeletePasskeyResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletePasskeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletePasskeyResponse copyWith(
          void Function(DeletePasskeyResponse) updates) =>
      super.copyWith((message) => updates(message as DeletePasskeyResponse))
          as DeletePasskeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeletePasskeyResponse() / DeletePasskeyResponse.new instead')
  static DeletePasskeyResponse create() => DeletePasskeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => DeletePasskeyResponse._();
  @$core.override
  DeletePasskeyResponse createEmptyInstance() => DeletePasskeyResponse._();
  @$core.pragma('dart2js:noInline')
  static DeletePasskeyResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeletePasskeyResponse>(
          DeletePasskeyResponse.$_createMessage);
  static DeletePasskeyResponse? _defaultInstance;
}

/// Asks to turn TOTP off.
class DeleteTotpRequest extends $pb.GeneratedMessage {
  factory DeleteTotpRequest() => DeleteTotpRequest._();

  DeleteTotpRequest._();

  factory DeleteTotpRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteTotpRequest()..mergeFromBuffer(data, registry);
  factory DeleteTotpRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteTotpRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteTotpRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: DeleteTotpRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteTotpRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteTotpRequest copyWith(void Function(DeleteTotpRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteTotpRequest))
          as DeleteTotpRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeleteTotpRequest() / DeleteTotpRequest.new instead')
  static DeleteTotpRequest create() => DeleteTotpRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeleteTotpRequest._();
  @$core.override
  DeleteTotpRequest createEmptyInstance() => DeleteTotpRequest._();
  @$core.pragma('dart2js:noInline')
  static DeleteTotpRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeleteTotpRequest>(
          DeleteTotpRequest.$_createMessage);
  static DeleteTotpRequest? _defaultInstance;
}

/// TOTP is off.
class DeleteTotpResponse extends $pb.GeneratedMessage {
  factory DeleteTotpResponse() => DeleteTotpResponse._();

  DeleteTotpResponse._();

  factory DeleteTotpResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteTotpResponse()..mergeFromBuffer(data, registry);
  factory DeleteTotpResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteTotpResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteTotpResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: DeleteTotpResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteTotpResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteTotpResponse copyWith(void Function(DeleteTotpResponse) updates) =>
      super.copyWith((message) => updates(message as DeleteTotpResponse))
          as DeleteTotpResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeleteTotpResponse() / DeleteTotpResponse.new instead')
  static DeleteTotpResponse create() => DeleteTotpResponse._();
  static $pb.GeneratedMessage $_createMessage() => DeleteTotpResponse._();
  @$core.override
  DeleteTotpResponse createEmptyInstance() => DeleteTotpResponse._();
  @$core.pragma('dart2js:noInline')
  static DeleteTotpResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteTotpResponse>(
          DeleteTotpResponse.$_createMessage);
  static DeleteTotpResponse? _defaultInstance;
}

/// Asks for new recovery codes.
class CreateRecoveryCodesRequest extends $pb.GeneratedMessage {
  factory CreateRecoveryCodesRequest() => CreateRecoveryCodesRequest._();

  CreateRecoveryCodesRequest._();

  factory CreateRecoveryCodesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateRecoveryCodesRequest()..mergeFromBuffer(data, registry);
  factory CreateRecoveryCodesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateRecoveryCodesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateRecoveryCodesRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateRecoveryCodesRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateRecoveryCodesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateRecoveryCodesRequest copyWith(
          void Function(CreateRecoveryCodesRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CreateRecoveryCodesRequest))
          as CreateRecoveryCodesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateRecoveryCodesRequest() / CreateRecoveryCodesRequest.new instead')
  static CreateRecoveryCodesRequest create() => CreateRecoveryCodesRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      CreateRecoveryCodesRequest._();
  @$core.override
  CreateRecoveryCodesRequest createEmptyInstance() =>
      CreateRecoveryCodesRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateRecoveryCodesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateRecoveryCodesRequest>(
          CreateRecoveryCodesRequest.$_createMessage);
  static CreateRecoveryCodesRequest? _defaultInstance;
}

/// The new recovery codes, to show once; the old ones no longer work.
class CreateRecoveryCodesResponse extends $pb.GeneratedMessage {
  factory CreateRecoveryCodesResponse({
    $core.Iterable<$core.String>? recoveryCodes,
  }) {
    final result = CreateRecoveryCodesResponse._();
    if (recoveryCodes != null) result.recoveryCodes.addAll(recoveryCodes);
    return result;
  }

  CreateRecoveryCodesResponse._();

  factory CreateRecoveryCodesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateRecoveryCodesResponse()..mergeFromBuffer(data, registry);
  factory CreateRecoveryCodesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateRecoveryCodesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateRecoveryCodesResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateRecoveryCodesResponse.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'recoveryCodes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateRecoveryCodesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateRecoveryCodesResponse copyWith(
          void Function(CreateRecoveryCodesResponse) updates) =>
      super.copyWith(
              (message) => updates(message as CreateRecoveryCodesResponse))
          as CreateRecoveryCodesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateRecoveryCodesResponse() / CreateRecoveryCodesResponse.new instead')
  static CreateRecoveryCodesResponse create() =>
      CreateRecoveryCodesResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      CreateRecoveryCodesResponse._();
  @$core.override
  CreateRecoveryCodesResponse createEmptyInstance() =>
      CreateRecoveryCodesResponse._();
  @$core.pragma('dart2js:noInline')
  static CreateRecoveryCodesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateRecoveryCodesResponse>(
          CreateRecoveryCodesResponse.$_createMessage);
  static CreateRecoveryCodesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get recoveryCodes => $_getList(0);
}

/// Asks to prove the caller's person.
class StartStepUpRequest extends $pb.GeneratedMessage {
  factory StartStepUpRequest({
    $core.List<$core.int>? ke1,
  }) {
    final result = StartStepUpRequest._();
    if (ke1 != null) result.ke1 = ke1;
    return result;
  }

  StartStepUpRequest._();

  factory StartStepUpRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartStepUpRequest()..mergeFromBuffer(data, registry);
  factory StartStepUpRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartStepUpRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartStepUpRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartStepUpRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'ke1', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartStepUpRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartStepUpRequest copyWith(void Function(StartStepUpRequest) updates) =>
      super.copyWith((message) => updates(message as StartStepUpRequest))
          as StartStepUpRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StartStepUpRequest() / StartStepUpRequest.new instead')
  static StartStepUpRequest create() => StartStepUpRequest._();
  static $pb.GeneratedMessage $_createMessage() => StartStepUpRequest._();
  @$core.override
  StartStepUpRequest createEmptyInstance() => StartStepUpRequest._();
  @$core.pragma('dart2js:noInline')
  static StartStepUpRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartStepUpRequest>(
          StartStepUpRequest.$_createMessage);
  static StartStepUpRequest? _defaultInstance;

  /// The client's OPAQUE KE1, to prove the password; empty to answer with a second factor.
  @$pb.TagNumber(1)
  $core.List<$core.int> get ke1 => $_getN(0);
  @$pb.TagNumber(1)
  set ke1($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKe1() => $_has(0);
  @$pb.TagNumber(1)
  void clearKe1() => $_clearField(1);
}

/// What the proof answers.
class StartStepUpResponse extends $pb.GeneratedMessage {
  factory StartStepUpResponse({
    $core.String? stepUpId,
    $core.List<$core.int>? ke2,
    $core.List<$core.int>? ksfParams,
    $core.Iterable<SecondFactor>? factors,
    $core.String? passkeyOptionsJson,
  }) {
    final result = StartStepUpResponse._();
    if (stepUpId != null) result.stepUpId = stepUpId;
    if (ke2 != null) result.ke2 = ke2;
    if (ksfParams != null) result.ksfParams = ksfParams;
    if (factors != null) result.factors.addAll(factors);
    if (passkeyOptionsJson != null)
      result.passkeyOptionsJson = passkeyOptionsJson;
    return result;
  }

  StartStepUpResponse._();

  factory StartStepUpResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartStepUpResponse()..mergeFromBuffer(data, registry);
  factory StartStepUpResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StartStepUpResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartStepUpResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: StartStepUpResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'stepUpId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ke2', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'ksfParams', $pb.PbFieldType.OY)
    ..pc<SecondFactor>(4, _omitFieldNames ? '' : 'factors', $pb.PbFieldType.KE,
        valueOf: SecondFactor.valueOf,
        enumValues: SecondFactor.values,
        defaultEnumValue: SecondFactor.SECOND_FACTOR_UNSPECIFIED)
    ..aOS(5, _omitFieldNames ? '' : 'passkeyOptionsJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartStepUpResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartStepUpResponse copyWith(void Function(StartStepUpResponse) updates) =>
      super.copyWith((message) => updates(message as StartStepUpResponse))
          as StartStepUpResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use StartStepUpResponse() / StartStepUpResponse.new instead')
  static StartStepUpResponse create() => StartStepUpResponse._();
  static $pb.GeneratedMessage $_createMessage() => StartStepUpResponse._();
  @$core.override
  StartStepUpResponse createEmptyInstance() => StartStepUpResponse._();
  @$core.pragma('dart2js:noInline')
  static StartStepUpResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartStepUpResponse>(
          StartStepUpResponse.$_createMessage);
  static StartStepUpResponse? _defaultInstance;

  /// Names this step-up in FinishStepUp, for five minutes and once.
  @$pb.TagNumber(1)
  $core.String get stepUpId => $_getSZ(0);
  @$pb.TagNumber(1)
  set stepUpId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStepUpId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStepUpId() => $_clearField(1);

  /// With a KE1: KE2 and the account's Argon2id parameters, as in StartLoginResponse.
  @$pb.TagNumber(2)
  $core.List<$core.int> get ke2 => $_getN(1);
  @$pb.TagNumber(2)
  set ke2($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKe2() => $_has(1);
  @$pb.TagNumber(2)
  void clearKe2() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get ksfParams => $_getN(2);
  @$pb.TagNumber(3)
  set ksfParams($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasKsfParams() => $_has(2);
  @$pb.TagNumber(3)
  void clearKsfParams() => $_clearField(3);

  /// The second factors the account can answer with.
  @$pb.TagNumber(4)
  $pb.PbList<SecondFactor> get factors => $_getList(3);

  /// PublicKeyCredentialRequestOptionsJSON for one of the account's passkeys, which must verify its user; empty without
  /// one.
  @$pb.TagNumber(5)
  $core.String get passkeyOptionsJson => $_getSZ(4);
  @$pb.TagNumber(5)
  set passkeyOptionsJson($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPasskeyOptionsJson() => $_has(4);
  @$pb.TagNumber(5)
  void clearPasskeyOptionsJson() => $_clearField(5);
}

enum FinishStepUpRequest_Answer {
  ke3,
  totpCode,
  recoveryCode,
  passkeyCredentialJson,
  notSet
}

/// The proof.
class FinishStepUpRequest extends $pb.GeneratedMessage {
  factory FinishStepUpRequest({
    $core.String? stepUpId,
    $core.List<$core.int>? ke3,
    $core.String? totpCode,
    $core.String? recoveryCode,
    $core.String? passkeyCredentialJson,
  }) {
    final result = FinishStepUpRequest._();
    if (stepUpId != null) result.stepUpId = stepUpId;
    if (ke3 != null) result.ke3 = ke3;
    if (totpCode != null) result.totpCode = totpCode;
    if (recoveryCode != null) result.recoveryCode = recoveryCode;
    if (passkeyCredentialJson != null)
      result.passkeyCredentialJson = passkeyCredentialJson;
    return result;
  }

  FinishStepUpRequest._();

  factory FinishStepUpRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishStepUpRequest()..mergeFromBuffer(data, registry);
  factory FinishStepUpRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishStepUpRequest()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FinishStepUpRequest_Answer>
      _FinishStepUpRequest_AnswerByTag = {
    2: FinishStepUpRequest_Answer.ke3,
    3: FinishStepUpRequest_Answer.totpCode,
    4: FinishStepUpRequest_Answer.recoveryCode,
    5: FinishStepUpRequest_Answer.passkeyCredentialJson,
    0: FinishStepUpRequest_Answer.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishStepUpRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishStepUpRequest.$_createMessage)
    ..oo(0, [2, 3, 4, 5])
    ..aOS(1, _omitFieldNames ? '' : 'stepUpId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'ke3', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'totpCode')
    ..aOS(4, _omitFieldNames ? '' : 'recoveryCode')
    ..aOS(5, _omitFieldNames ? '' : 'passkeyCredentialJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishStepUpRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishStepUpRequest copyWith(void Function(FinishStepUpRequest) updates) =>
      super.copyWith((message) => updates(message as FinishStepUpRequest))
          as FinishStepUpRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use FinishStepUpRequest() / FinishStepUpRequest.new instead')
  static FinishStepUpRequest create() => FinishStepUpRequest._();
  static $pb.GeneratedMessage $_createMessage() => FinishStepUpRequest._();
  @$core.override
  FinishStepUpRequest createEmptyInstance() => FinishStepUpRequest._();
  @$core.pragma('dart2js:noInline')
  static FinishStepUpRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishStepUpRequest>(
          FinishStepUpRequest.$_createMessage);
  static FinishStepUpRequest? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  FinishStepUpRequest_Answer whichAnswer() =>
      _FinishStepUpRequest_AnswerByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  void clearAnswer() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get stepUpId => $_getSZ(0);
  @$pb.TagNumber(1)
  set stepUpId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStepUpId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStepUpId() => $_clearField(1);

  /// The client's OPAQUE KE3 for the KE2 of StartStepUpResponse.
  @$pb.TagNumber(2)
  $core.List<$core.int> get ke3 => $_getN(1);
  @$pb.TagNumber(2)
  set ke3($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKe3() => $_has(1);
  @$pb.TagNumber(2)
  void clearKe3() => $_clearField(2);

  /// As in FinishSecondFactorRequest.
  @$pb.TagNumber(3)
  $core.String get totpCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set totpCode($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotpCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotpCode() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get recoveryCode => $_getSZ(3);
  @$pb.TagNumber(4)
  set recoveryCode($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRecoveryCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecoveryCode() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get passkeyCredentialJson => $_getSZ(4);
  @$pb.TagNumber(5)
  set passkeyCredentialJson($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPasskeyCredentialJson() => $_has(4);
  @$pb.TagNumber(5)
  void clearPasskeyCredentialJson() => $_clearField(5);
}

/// The session has proved its person.
class FinishStepUpResponse extends $pb.GeneratedMessage {
  factory FinishStepUpResponse() => FinishStepUpResponse._();

  FinishStepUpResponse._();

  factory FinishStepUpResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishStepUpResponse()..mergeFromBuffer(data, registry);
  factory FinishStepUpResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FinishStepUpResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishStepUpResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FinishStepUpResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishStepUpResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishStepUpResponse copyWith(void Function(FinishStepUpResponse) updates) =>
      super.copyWith((message) => updates(message as FinishStepUpResponse))
          as FinishStepUpResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use FinishStepUpResponse() / FinishStepUpResponse.new instead')
  static FinishStepUpResponse create() => FinishStepUpResponse._();
  static $pb.GeneratedMessage $_createMessage() => FinishStepUpResponse._();
  @$core.override
  FinishStepUpResponse createEmptyInstance() => FinishStepUpResponse._();
  @$core.pragma('dart2js:noInline')
  static FinishStepUpResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishStepUpResponse>(
          FinishStepUpResponse.$_createMessage);
  static FinishStepUpResponse? _defaultInstance;
}

/// Signs devices in with a password the server never learns: OPAQUE (RFC 9807) with the configuration of
/// docs/dev/crypto-v1.md#opaque. A wrong password, an unknown handle or email and an account that cannot sign in look the same,
/// and a handle, a known device or an address with too many attempts is locked for a growing time (`login.throttled`,
/// `retry_after_seconds`).
/// An account with a passkey or TOTP finishes a password sign-in with one of them or a recovery code; a passkey that
/// verifies its user signs in alone. WebAuthn options and credentials travel in WebAuthn's own JSON serialisation
/// (Level 3), which browsers and Android take and give as they are; their ceremonies run on photolibd's `public_url`.
/// While the admin console's `require_two_factor` is on, a session of an account without a second factor is refused
/// everything but this service (`second_factor.required`), where it enrols one.
/// DeletePasskey, DeleteTotp, CreateRecoveryCodes, replacing a TOTP secret, adding a passkey and setting a password with a
/// session need the calling session to have proved its person within the last five minutes (`permission_denied`
/// `step_up.required`): a sign-in with a password, a passkey or a second factor counts, and so does StartStepUp and
/// FinishStepUp. A first TOTP secret, and a passkey or password for an account with nothing to prove itself with yet,
/// need no proof.
/// A session token is sent as `Authorization: Bearer <token>`; the server keeps only its hash.
class AuthServiceApi {
  final $pb.RpcClient _client;

  AuthServiceApi(this._client);

  /// First step of setting the password: evaluates the client's OPAQUE registration request. Needs a session of the
  /// account, or a password setup token.
  $async.Future<StartPasswordSetupResponse> startPasswordSetup(
          $pb.ClientContext? ctx, StartPasswordSetupRequest request) =>
      _client.invoke<StartPasswordSetupResponse>(ctx, 'AuthService',
          'StartPasswordSetup', request, StartPasswordSetupResponse());

  /// Second step: stores the client's registration record and Argon2id parameters in place of the old password. Uses
  /// up the password setup token.
  $async.Future<FinishPasswordSetupResponse> finishPasswordSetup(
          $pb.ClientContext? ctx, FinishPasswordSetupRequest request) =>
      _client.invoke<FinishPasswordSetupResponse>(ctx, 'AuthService',
          'FinishPasswordSetup', request, FinishPasswordSetupResponse());

  /// First step of signing in: answers the client's KE1 with KE2 and the account's Argon2id parameters.
  $async.Future<StartLoginResponse> startLogin(
          $pb.ClientContext? ctx, StartLoginRequest request) =>
      _client.invoke<StartLoginResponse>(
          ctx, 'AuthService', 'StartLogin', request, StartLoginResponse());

  /// Second step: checks the client's KE3 and opens a session on the device.
  $async.Future<FinishLoginResponse> finishLogin(
          $pb.ClientContext? ctx, FinishLoginRequest request) =>
      _client.invoke<FinishLoginResponse>(
          ctx, 'AuthService', 'FinishLogin', request, FinishLoginResponse());

  /// Gives the calling session a new token that lasts another 90 days. The old token keeps working until the new one is
  /// first used, or for 24 hours, so that a lost response signs no device out.
  $async.Future<RotateSessionResponse> rotateSession(
          $pb.ClientContext? ctx, RotateSessionRequest request) =>
      _client.invoke<RotateSessionResponse>(ctx, 'AuthService', 'RotateSession',
          request, RotateSessionResponse());

  /// The devices signed in to the caller's account, most recently seen first.
  $async.Future<ListDevicesResponse> listDevices(
          $pb.ClientContext? ctx, ListDevicesRequest request) =>
      _client.invoke<ListDevicesResponse>(
          ctx, 'AuthService', 'ListDevices', request, ListDevicesResponse());

  /// Signs a device of the caller's account out: its sessions end before the next request. Revoking the calling device
  /// signs it out and keeps it known, so that its device secret still counts its sign-in attempts apart.
  $async.Future<RevokeDeviceResponse> revokeDevice(
          $pb.ClientContext? ctx, RevokeDeviceRequest request) =>
      _client.invoke<RevokeDeviceResponse>(
          ctx, 'AuthService', 'RevokeDevice', request, RevokeDeviceResponse());

  /// Records the calling device's backup: how many items it still has to back up. The admin console and `/metrics`
  /// show a device that has not reported for the settings' `backup_silent_hours` as silent (ING-26).
  $async.Future<ReportBackupResponse> reportBackup(
          $pb.ClientContext? ctx, ReportBackupRequest request) =>
      _client.invoke<ReportBackupResponse>(
          ctx, 'AuthService', 'ReportBackup', request, ReportBackupResponse());

  /// First step of signing in with an OpenID Connect provider (GetServerInfoResponse.oidc_providers): the URL the
  /// client opens in the system browser, an authorization code request with PKCE (RFC 7636) whose verifier only the
  /// client knows. With `link`, the calling session's account gets this identity instead.
  $async.Future<StartOidcResponse> startOidc(
          $pb.ClientContext? ctx, StartOidcRequest request) =>
      _client.invoke<StartOidcResponse>(
          ctx, 'AuthService', 'StartOidc', request, StartOidcResponse());

  /// Second step: the provider's answer at the redirect URI. Signs the person in on the device, or links the identity.
  /// A failed check fails this sign-in only (`oidc.failed`, `oidc.claim_invalid` with the `claim`, `oidc.not_allowed`
  /// when no account may sign in with it, `oidc.unavailable` when the provider does not answer).
  $async.Future<CompleteOidcResponse> completeOidc(
          $pb.ClientContext? ctx, CompleteOidcRequest request) =>
      _client.invoke<CompleteOidcResponse>(
          ctx, 'AuthService', 'CompleteOidc', request, CompleteOidcResponse());

  /// Last step of a password sign-in that FinishLogin answered with a second factor challenge: a TOTP code, a
  /// recovery code or a passkey opens the session. Five wrong answers end the sign-in.
  $async.Future<FinishSecondFactorResponse> finishSecondFactor(
          $pb.ClientContext? ctx, FinishSecondFactorRequest request) =>
      _client.invoke<FinishSecondFactorResponse>(ctx, 'AuthService',
          'FinishSecondFactor', request, FinishSecondFactorResponse());

  /// First step of signing in with a passkey alone: request options for any passkey of this server that verifies its
  /// user. `passkey.unavailable` without `public_url`.
  $async.Future<StartPasskeyLoginResponse> startPasskeyLogin(
          $pb.ClientContext? ctx, StartPasskeyLoginRequest request) =>
      _client.invoke<StartPasskeyLoginResponse>(ctx, 'AuthService',
          'StartPasskeyLogin', request, StartPasskeyLoginResponse());

  /// Second step: checks the passkey's assertion and opens a session on the device.
  $async.Future<FinishPasskeyLoginResponse> finishPasskeyLogin(
          $pb.ClientContext? ctx, FinishPasskeyLoginRequest request) =>
      _client.invoke<FinishPasskeyLoginResponse>(ctx, 'AuthService',
          'FinishPasskeyLogin', request, FinishPasskeyLoginResponse());

  /// First step of adding a passkey to the caller's account: creation options. `passkey.unavailable` without
  /// `public_url`.
  $async.Future<StartPasskeySetupResponse> startPasskeySetup(
          $pb.ClientContext? ctx, StartPasskeySetupRequest request) =>
      _client.invoke<StartPasskeySetupResponse>(ctx, 'AuthService',
          'StartPasskeySetup', request, StartPasskeySetupResponse());

  /// Second step: stores the new passkey.
  $async.Future<FinishPasskeySetupResponse> finishPasskeySetup(
          $pb.ClientContext? ctx, FinishPasskeySetupRequest request) =>
      _client.invoke<FinishPasskeySetupResponse>(ctx, 'AuthService',
          'FinishPasskeySetup', request, FinishPasskeySetupResponse());

  /// First step of turning TOTP on for the caller's account: a new secret for an authenticator app.
  $async.Future<StartTotpSetupResponse> startTotpSetup(
          $pb.ClientContext? ctx, StartTotpSetupRequest request) =>
      _client.invoke<StartTotpSetupResponse>(ctx, 'AuthService',
          'StartTotpSetup', request, StartTotpSetupResponse());

  /// Second step: a code of the new secret puts it in place of any earlier one.
  $async.Future<FinishTotpSetupResponse> finishTotpSetup(
          $pb.ClientContext? ctx, FinishTotpSetupRequest request) =>
      _client.invoke<FinishTotpSetupResponse>(ctx, 'AuthService',
          'FinishTotpSetup', request, FinishTotpSetupResponse());

  /// The caller's passkeys, whether TOTP is on and how many recovery codes are left.
  $async.Future<ListSecondFactorsResponse> listSecondFactors(
          $pb.ClientContext? ctx, ListSecondFactorsRequest request) =>
      _client.invoke<ListSecondFactorsResponse>(ctx, 'AuthService',
          'ListSecondFactors', request, ListSecondFactorsResponse());

  /// Removes one of the caller's passkeys.
  $async.Future<DeletePasskeyResponse> deletePasskey(
          $pb.ClientContext? ctx, DeletePasskeyRequest request) =>
      _client.invoke<DeletePasskeyResponse>(ctx, 'AuthService', 'DeletePasskey',
          request, DeletePasskeyResponse());

  /// Turns TOTP off for the caller's account.
  $async.Future<DeleteTotpResponse> deleteTotp(
          $pb.ClientContext? ctx, DeleteTotpRequest request) =>
      _client.invoke<DeleteTotpResponse>(
          ctx, 'AuthService', 'DeleteTotp', request, DeleteTotpResponse());

  /// Replaces the caller's recovery codes with ten new ones.
  $async.Future<CreateRecoveryCodesResponse> createRecoveryCodes(
          $pb.ClientContext? ctx, CreateRecoveryCodesRequest request) =>
      _client.invoke<CreateRecoveryCodesResponse>(ctx, 'AuthService',
          'CreateRecoveryCodes', request, CreateRecoveryCodesResponse());

  /// First step of proving again, on the calling session, that its person is there: answers KE1 like StartLogin to
  /// prove the password, and names the account's second factors with a passkey challenge. Counts towards the lockout of
  /// the account's handle.
  $async.Future<StartStepUpResponse> startStepUp(
          $pb.ClientContext? ctx, StartStepUpRequest request) =>
      _client.invoke<StartStepUpResponse>(
          ctx, 'AuthService', 'StartStepUp', request, StartStepUpResponse());

  /// Second step: KE3, a TOTP code, a recovery code or a passkey that verifies its user records the proof on the
  /// session, for five minutes. A wrong answer is `login.failed` and ends the step-up.
  $async.Future<FinishStepUpResponse> finishStepUp(
          $pb.ClientContext? ctx, FinishStepUpRequest request) =>
      _client.invoke<FinishStepUpResponse>(
          ctx, 'AuthService', 'FinishStepUp', request, FinishStepUpResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
