// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/opaque.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The client's OPAQUE registration: without a response, the registration request; with the server's response, the
/// record to upload. Both steps take the same randomness.
class OpaqueRegisterRequest extends $pb.GeneratedMessage {
  factory OpaqueRegisterRequest({
    $core.String? password,
    $core.List<$core.int>? params,
    $core.List<$core.int>? randomness,
    $core.List<$core.int>? response,
  }) {
    final result = OpaqueRegisterRequest._();
    if (password != null) result.password = password;
    if (params != null) result.params = params;
    if (randomness != null) result.randomness = randomness;
    if (response != null) result.response = response;
    return result;
  }

  OpaqueRegisterRequest._();

  factory OpaqueRegisterRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueRegisterRequest()..mergeFromBuffer(data, registry);
  factory OpaqueRegisterRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueRegisterRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpaqueRegisterRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpaqueRegisterRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'password')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'params', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'randomness', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'response', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueRegisterRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueRegisterRequest copyWith(
          void Function(OpaqueRegisterRequest) updates) =>
      super.copyWith((message) => updates(message as OpaqueRegisterRequest))
          as OpaqueRegisterRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use OpaqueRegisterRequest() / OpaqueRegisterRequest.new instead')
  static OpaqueRegisterRequest create() => OpaqueRegisterRequest._();
  static $pb.GeneratedMessage $_createMessage() => OpaqueRegisterRequest._();
  @$core.override
  OpaqueRegisterRequest createEmptyInstance() => OpaqueRegisterRequest._();
  @$core.pragma('dart2js:noInline')
  static OpaqueRegisterRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpaqueRegisterRequest>(
          OpaqueRegisterRequest.$_createMessage);
  static OpaqueRegisterRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get password => $_getSZ(0);
  @$pb.TagNumber(1)
  set password($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPassword() => $_has(0);
  @$pb.TagNumber(1)
  void clearPassword() => $_clearField(1);

  /// The account's Argon2id parameter set; the KSF takes m and t from it.
  @$pb.TagNumber(2)
  $core.List<$core.int> get params => $_getN(1);
  @$pb.TagNumber(2)
  set params($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasParams() => $_has(1);
  @$pb.TagNumber(2)
  void clearParams() => $_clearField(2);

  /// 96 random bytes.
  @$pb.TagNumber(3)
  $core.List<$core.int> get randomness => $_getN(2);
  @$pb.TagNumber(3)
  set randomness($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRandomness() => $_has(2);
  @$pb.TagNumber(3)
  void clearRandomness() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get response => $_getN(3);
  @$pb.TagNumber(4)
  set response($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResponse() => $_has(3);
  @$pb.TagNumber(4)
  void clearResponse() => $_clearField(4);
}

/// The client's OPAQUE login: without KE2, KE1; with the server's KE2, KE3. Both steps take the same randomness.
class OpaqueLoginRequest extends $pb.GeneratedMessage {
  factory OpaqueLoginRequest({
    $core.String? password,
    $core.List<$core.int>? params,
    $core.List<$core.int>? randomness,
    $core.List<$core.int>? ke2,
  }) {
    final result = OpaqueLoginRequest._();
    if (password != null) result.password = password;
    if (params != null) result.params = params;
    if (randomness != null) result.randomness = randomness;
    if (ke2 != null) result.ke2 = ke2;
    return result;
  }

  OpaqueLoginRequest._();

  factory OpaqueLoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueLoginRequest()..mergeFromBuffer(data, registry);
  factory OpaqueLoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueLoginRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpaqueLoginRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpaqueLoginRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'password')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'params', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'randomness', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'ke2', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueLoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueLoginRequest copyWith(void Function(OpaqueLoginRequest) updates) =>
      super.copyWith((message) => updates(message as OpaqueLoginRequest))
          as OpaqueLoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use OpaqueLoginRequest() / OpaqueLoginRequest.new instead')
  static OpaqueLoginRequest create() => OpaqueLoginRequest._();
  static $pb.GeneratedMessage $_createMessage() => OpaqueLoginRequest._();
  @$core.override
  OpaqueLoginRequest createEmptyInstance() => OpaqueLoginRequest._();
  @$core.pragma('dart2js:noInline')
  static OpaqueLoginRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpaqueLoginRequest>(
          OpaqueLoginRequest.$_createMessage);
  static OpaqueLoginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get password => $_getSZ(0);
  @$pb.TagNumber(1)
  set password($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPassword() => $_has(0);
  @$pb.TagNumber(1)
  void clearPassword() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get params => $_getN(1);
  @$pb.TagNumber(2)
  set params($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasParams() => $_has(1);
  @$pb.TagNumber(2)
  void clearParams() => $_clearField(2);

  /// 128 random bytes.
  @$pb.TagNumber(3)
  $core.List<$core.int> get randomness => $_getN(2);
  @$pb.TagNumber(3)
  set randomness($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRandomness() => $_has(2);
  @$pb.TagNumber(3)
  void clearRandomness() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ke2 => $_getN(3);
  @$pb.TagNumber(4)
  set ke2($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasKe2() => $_has(3);
  @$pb.TagNumber(4)
  void clearKe2() => $_clearField(4);
}

/// The client's next message; after login, the protocol's session and export keys (crypto v1 derives no key from them).
class OpaqueClientResponse extends $pb.GeneratedMessage {
  factory OpaqueClientResponse({
    $core.List<$core.int>? message,
    $core.List<$core.int>? sessionKey,
    $core.List<$core.int>? exportKey,
  }) {
    final result = OpaqueClientResponse._();
    if (message != null) result.message = message;
    if (sessionKey != null) result.sessionKey = sessionKey;
    if (exportKey != null) result.exportKey = exportKey;
    return result;
  }

  OpaqueClientResponse._();

  factory OpaqueClientResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueClientResponse()..mergeFromBuffer(data, registry);
  factory OpaqueClientResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueClientResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpaqueClientResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpaqueClientResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'message', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'sessionKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'exportKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueClientResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueClientResponse copyWith(void Function(OpaqueClientResponse) updates) =>
      super.copyWith((message) => updates(message as OpaqueClientResponse))
          as OpaqueClientResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use OpaqueClientResponse() / OpaqueClientResponse.new instead')
  static OpaqueClientResponse create() => OpaqueClientResponse._();
  static $pb.GeneratedMessage $_createMessage() => OpaqueClientResponse._();
  @$core.override
  OpaqueClientResponse createEmptyInstance() => OpaqueClientResponse._();
  @$core.pragma('dart2js:noInline')
  static OpaqueClientResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpaqueClientResponse>(
          OpaqueClientResponse.$_createMessage);
  static OpaqueClientResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get message => $_getN(0);
  @$pb.TagNumber(1)
  set message($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get sessionKey => $_getN(1);
  @$pb.TagNumber(2)
  set sessionKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get exportKey => $_getN(2);
  @$pb.TagNumber(3)
  set exportKey($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExportKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearExportKey() => $_clearField(3);
}

/// The server's answer to a registration request.
class OpaqueServerRegisterRequest extends $pb.GeneratedMessage {
  factory OpaqueServerRegisterRequest({
    $core.List<$core.int>? oprfSeed,
    $core.List<$core.int>? privateKey,
    $core.List<$core.int>? credentialId,
    $core.List<$core.int>? request,
  }) {
    final result = OpaqueServerRegisterRequest._();
    if (oprfSeed != null) result.oprfSeed = oprfSeed;
    if (privateKey != null) result.privateKey = privateKey;
    if (credentialId != null) result.credentialId = credentialId;
    if (request != null) result.request = request;
    return result;
  }

  OpaqueServerRegisterRequest._();

  factory OpaqueServerRegisterRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueServerRegisterRequest()..mergeFromBuffer(data, registry);
  factory OpaqueServerRegisterRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueServerRegisterRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpaqueServerRegisterRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpaqueServerRegisterRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'oprfSeed', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'privateKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'credentialId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'request', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueServerRegisterRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueServerRegisterRequest copyWith(
          void Function(OpaqueServerRegisterRequest) updates) =>
      super.copyWith(
              (message) => updates(message as OpaqueServerRegisterRequest))
          as OpaqueServerRegisterRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use OpaqueServerRegisterRequest() / OpaqueServerRegisterRequest.new instead')
  static OpaqueServerRegisterRequest create() =>
      OpaqueServerRegisterRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      OpaqueServerRegisterRequest._();
  @$core.override
  OpaqueServerRegisterRequest createEmptyInstance() =>
      OpaqueServerRegisterRequest._();
  @$core.pragma('dart2js:noInline')
  static OpaqueServerRegisterRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpaqueServerRegisterRequest>(
          OpaqueServerRegisterRequest.$_createMessage);
  static OpaqueServerRegisterRequest? _defaultInstance;

  /// 64 bytes.
  @$pb.TagNumber(1)
  $core.List<$core.int> get oprfSeed => $_getN(0);
  @$pb.TagNumber(1)
  set oprfSeed($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOprfSeed() => $_has(0);
  @$pb.TagNumber(1)
  void clearOprfSeed() => $_clearField(1);

  /// The server's ristretto255 private key.
  @$pb.TagNumber(2)
  $core.List<$core.int> get privateKey => $_getN(1);
  @$pb.TagNumber(2)
  set privateKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPrivateKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrivateKey() => $_clearField(2);

  /// The user id.
  @$pb.TagNumber(3)
  $core.List<$core.int> get credentialId => $_getN(2);
  @$pb.TagNumber(3)
  set credentialId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCredentialId() => $_has(2);
  @$pb.TagNumber(3)
  void clearCredentialId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get request => $_getN(3);
  @$pb.TagNumber(4)
  set request($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRequest() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequest() => $_clearField(4);
}

/// The server's side of a login: without KE3, KE2; with the client's KE3, its check. Both steps take the same randomness.
class OpaqueServerLoginRequest extends $pb.GeneratedMessage {
  factory OpaqueServerLoginRequest({
    $core.List<$core.int>? oprfSeed,
    $core.List<$core.int>? privateKey,
    $core.List<$core.int>? credentialId,
    $core.List<$core.int>? record,
    $core.List<$core.int>? randomness,
    $core.List<$core.int>? ke1,
    $core.List<$core.int>? ke3,
  }) {
    final result = OpaqueServerLoginRequest._();
    if (oprfSeed != null) result.oprfSeed = oprfSeed;
    if (privateKey != null) result.privateKey = privateKey;
    if (credentialId != null) result.credentialId = credentialId;
    if (record != null) result.record = record;
    if (randomness != null) result.randomness = randomness;
    if (ke1 != null) result.ke1 = ke1;
    if (ke3 != null) result.ke3 = ke3;
    return result;
  }

  OpaqueServerLoginRequest._();

  factory OpaqueServerLoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueServerLoginRequest()..mergeFromBuffer(data, registry);
  factory OpaqueServerLoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueServerLoginRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpaqueServerLoginRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpaqueServerLoginRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'oprfSeed', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'privateKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'credentialId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'record', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'randomness', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'ke1', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'ke3', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueServerLoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueServerLoginRequest copyWith(
          void Function(OpaqueServerLoginRequest) updates) =>
      super.copyWith((message) => updates(message as OpaqueServerLoginRequest))
          as OpaqueServerLoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use OpaqueServerLoginRequest() / OpaqueServerLoginRequest.new instead')
  static OpaqueServerLoginRequest create() => OpaqueServerLoginRequest._();
  static $pb.GeneratedMessage $_createMessage() => OpaqueServerLoginRequest._();
  @$core.override
  OpaqueServerLoginRequest createEmptyInstance() =>
      OpaqueServerLoginRequest._();
  @$core.pragma('dart2js:noInline')
  static OpaqueServerLoginRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpaqueServerLoginRequest>(
          OpaqueServerLoginRequest.$_createMessage);
  static OpaqueServerLoginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get oprfSeed => $_getN(0);
  @$pb.TagNumber(1)
  set oprfSeed($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOprfSeed() => $_has(0);
  @$pb.TagNumber(1)
  void clearOprfSeed() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get privateKey => $_getN(1);
  @$pb.TagNumber(2)
  set privateKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPrivateKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrivateKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get credentialId => $_getN(2);
  @$pb.TagNumber(3)
  set credentialId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCredentialId() => $_has(2);
  @$pb.TagNumber(3)
  void clearCredentialId() => $_clearField(3);

  /// The registration record.
  @$pb.TagNumber(4)
  $core.List<$core.int> get record => $_getN(3);
  @$pb.TagNumber(4)
  set record($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRecord() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecord() => $_clearField(4);

  /// 96 random bytes.
  @$pb.TagNumber(5)
  $core.List<$core.int> get randomness => $_getN(4);
  @$pb.TagNumber(5)
  set randomness($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRandomness() => $_has(4);
  @$pb.TagNumber(5)
  void clearRandomness() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get ke1 => $_getN(5);
  @$pb.TagNumber(6)
  set ke1($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasKe1() => $_has(5);
  @$pb.TagNumber(6)
  void clearKe1() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get ke3 => $_getN(6);
  @$pb.TagNumber(7)
  set ke3($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasKe3() => $_has(6);
  @$pb.TagNumber(7)
  void clearKe3() => $_clearField(7);
}

/// The server's next message; after login, the session key.
class OpaqueServerResponse extends $pb.GeneratedMessage {
  factory OpaqueServerResponse({
    $core.List<$core.int>? message,
    $core.List<$core.int>? sessionKey,
  }) {
    final result = OpaqueServerResponse._();
    if (message != null) result.message = message;
    if (sessionKey != null) result.sessionKey = sessionKey;
    return result;
  }

  OpaqueServerResponse._();

  factory OpaqueServerResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueServerResponse()..mergeFromBuffer(data, registry);
  factory OpaqueServerResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpaqueServerResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpaqueServerResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpaqueServerResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'message', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'sessionKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueServerResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpaqueServerResponse copyWith(void Function(OpaqueServerResponse) updates) =>
      super.copyWith((message) => updates(message as OpaqueServerResponse))
          as OpaqueServerResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use OpaqueServerResponse() / OpaqueServerResponse.new instead')
  static OpaqueServerResponse create() => OpaqueServerResponse._();
  static $pb.GeneratedMessage $_createMessage() => OpaqueServerResponse._();
  @$core.override
  OpaqueServerResponse createEmptyInstance() => OpaqueServerResponse._();
  @$core.pragma('dart2js:noInline')
  static OpaqueServerResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpaqueServerResponse>(
          OpaqueServerResponse.$_createMessage);
  static OpaqueServerResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get message => $_getN(0);
  @$pb.TagNumber(1)
  set message($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get sessionKey => $_getN(1);
  @$pb.TagNumber(2)
  set sessionKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionKey() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
