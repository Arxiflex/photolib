// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/keys.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'keys.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'keys.pbenum.dart';

/// Brings 32 bytes of key material into the keyring: fresh randomness, or what a platform keystore releases.
class ImportKeyRequest extends $pb.GeneratedMessage {
  factory ImportKeyRequest({
    $core.List<$core.int>? secret,
  }) {
    final result = ImportKeyRequest._();
    if (secret != null) result.secret = secret;
    return result;
  }

  ImportKeyRequest._();

  factory ImportKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImportKeyRequest()..mergeFromBuffer(data, registry);
  factory ImportKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImportKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImportKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ImportKeyRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'secret', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportKeyRequest copyWith(void Function(ImportKeyRequest) updates) =>
      super.copyWith((message) => updates(message as ImportKeyRequest))
          as ImportKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImportKeyRequest() / ImportKeyRequest.new instead')
  static ImportKeyRequest create() => ImportKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => ImportKeyRequest._();
  @$core.override
  ImportKeyRequest createEmptyInstance() => ImportKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static ImportKeyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ImportKeyRequest>(
          ImportKeyRequest.$_createMessage);
  static ImportKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get secret => $_getN(0);
  @$pb.TagNumber(1)
  set secret($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSecret() => $_has(0);
  @$pb.TagNumber(1)
  void clearSecret() => $_clearField(1);
}

/// A key in the keyring: the handle later requests name it by, and its key_id. Key material never leaves the kernel.
class KeyResponse extends $pb.GeneratedMessage {
  factory KeyResponse({
    $core.int? key,
    $core.List<$core.int>? keyId,
  }) {
    final result = KeyResponse._();
    if (key != null) result.key = key;
    if (keyId != null) result.keyId = keyId;
    return result;
  }

  KeyResponse._();

  factory KeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KeyResponse()..mergeFromBuffer(data, registry);
  factory KeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: KeyResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'keyId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyResponse copyWith(void Function(KeyResponse) updates) =>
      super.copyWith((message) => updates(message as KeyResponse))
          as KeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use KeyResponse() / KeyResponse.new instead')
  static KeyResponse create() => KeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => KeyResponse._();
  @$core.override
  KeyResponse createEmptyInstance() => KeyResponse._();
  @$core.pragma('dart2js:noInline')
  static KeyResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KeyResponse>(
          KeyResponse.$_createMessage);
  static KeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get keyId => $_getN(1);
  @$pb.TagNumber(2)
  set keyId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKeyId() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyId() => $_clearField(2);
}

/// Zeroizes a key and forgets its handle.
class DropKeyRequest extends $pb.GeneratedMessage {
  factory DropKeyRequest({
    $core.int? key,
  }) {
    final result = DropKeyRequest._();
    if (key != null) result.key = key;
    return result;
  }

  DropKeyRequest._();

  factory DropKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DropKeyRequest()..mergeFromBuffer(data, registry);
  factory DropKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DropKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DropKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DropKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DropKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DropKeyRequest copyWith(void Function(DropKeyRequest) updates) =>
      super.copyWith((message) => updates(message as DropKeyRequest))
          as DropKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DropKeyRequest() / DropKeyRequest.new instead')
  static DropKeyRequest create() => DropKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => DropKeyRequest._();
  @$core.override
  DropKeyRequest createEmptyInstance() => DropKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static DropKeyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DropKeyRequest>(
          DropKeyRequest.$_createMessage);
  static DropKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);
}

/// Nothing: the key is gone.
class DropKeyResponse extends $pb.GeneratedMessage {
  factory DropKeyResponse() => DropKeyResponse._();

  DropKeyResponse._();

  factory DropKeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DropKeyResponse()..mergeFromBuffer(data, registry);
  factory DropKeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DropKeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DropKeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DropKeyResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DropKeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DropKeyResponse copyWith(void Function(DropKeyResponse) updates) =>
      super.copyWith((message) => updates(message as DropKeyResponse))
          as DropKeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DropKeyResponse() / DropKeyResponse.new instead')
  static DropKeyResponse create() => DropKeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => DropKeyResponse._();
  @$core.override
  DropKeyResponse createEmptyInstance() => DropKeyResponse._();
  @$core.pragma('dart2js:noInline')
  static DropKeyResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DropKeyResponse>(
          DropKeyResponse.$_createMessage);
  static DropKeyResponse? _defaultInstance;
}

/// Derives HKDF-SHA256(key, "photolib/v1/" ‖ label ‖ context) into the keyring.
class DeriveKeyRequest extends $pb.GeneratedMessage {
  factory DeriveKeyRequest({
    $core.int? key,
    $core.String? label,
    $core.List<$core.int>? context,
  }) {
    final result = DeriveKeyRequest._();
    if (key != null) result.key = key;
    if (label != null) result.label = label;
    if (context != null) result.context = context;
    return result;
  }

  DeriveKeyRequest._();

  factory DeriveKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeriveKeyRequest()..mergeFromBuffer(data, registry);
  factory DeriveKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeriveKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeriveKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DeriveKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'label')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'context', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeriveKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeriveKeyRequest copyWith(void Function(DeriveKeyRequest) updates) =>
      super.copyWith((message) => updates(message as DeriveKeyRequest))
          as DeriveKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeriveKeyRequest() / DeriveKeyRequest.new instead')
  static DeriveKeyRequest create() => DeriveKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeriveKeyRequest._();
  @$core.override
  DeriveKeyRequest createEmptyInstance() => DeriveKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static DeriveKeyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeriveKeyRequest>(
          DeriveKeyRequest.$_createMessage);
  static DeriveKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  /// E.g. "local/db".
  @$pb.TagNumber(2)
  $core.String get label => $_getSZ(1);
  @$pb.TagNumber(2)
  set label($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLabel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLabel() => $_clearField(2);

  /// E.g. a database file id.
  @$pb.TagNumber(3)
  $core.List<$core.int> get context => $_getN(2);
  @$pb.TagNumber(3)
  set context($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContext() => $_has(2);
  @$pb.TagNumber(3)
  void clearContext() => $_clearField(3);
}

/// Stretches a password into the keyring: HKDF(Argon2id(NFC(password), params) ‖ hardware, "photolib/v1/" ‖ label), or
/// the Argon2id output itself when the label is empty.
class DerivePasswordKeyRequest extends $pb.GeneratedMessage {
  factory DerivePasswordKeyRequest({
    $core.String? password,
    $core.List<$core.int>? params,
    $core.String? label,
    $core.List<$core.int>? hardware,
  }) {
    final result = DerivePasswordKeyRequest._();
    if (password != null) result.password = password;
    if (params != null) result.params = params;
    if (label != null) result.label = label;
    if (hardware != null) result.hardware = hardware;
    return result;
  }

  DerivePasswordKeyRequest._();

  factory DerivePasswordKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DerivePasswordKeyRequest()..mergeFromBuffer(data, registry);
  factory DerivePasswordKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DerivePasswordKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DerivePasswordKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DerivePasswordKeyRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'password')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'params', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'label')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'hardware', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DerivePasswordKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DerivePasswordKeyRequest copyWith(
          void Function(DerivePasswordKeyRequest) updates) =>
      super.copyWith((message) => updates(message as DerivePasswordKeyRequest))
          as DerivePasswordKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DerivePasswordKeyRequest() / DerivePasswordKeyRequest.new instead')
  static DerivePasswordKeyRequest create() => DerivePasswordKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => DerivePasswordKeyRequest._();
  @$core.override
  DerivePasswordKeyRequest createEmptyInstance() =>
      DerivePasswordKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static DerivePasswordKeyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DerivePasswordKeyRequest>(
          DerivePasswordKeyRequest.$_createMessage);
  static DerivePasswordKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get password => $_getSZ(0);
  @$pb.TagNumber(1)
  set password($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPassword() => $_has(0);
  @$pb.TagNumber(1)
  void clearPassword() => $_clearField(1);

  /// An Argon2id parameter set, 26 bytes, with one lane, at most 2 GiB and 64 passes.
  @$pb.TagNumber(2)
  $core.List<$core.int> get params => $_getN(1);
  @$pb.TagNumber(2)
  set params($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasParams() => $_has(1);
  @$pb.TagNumber(2)
  void clearParams() => $_clearField(2);

  /// E.g. "kek/passcode".
  @$pb.TagNumber(3)
  $core.String get label => $_getSZ(2);
  @$pb.TagNumber(3)
  set label($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLabel() => $_has(2);
  @$pb.TagNumber(3)
  void clearLabel() => $_clearField(3);

  /// The output of the device's hardware binding; empty without one.
  @$pb.TagNumber(4)
  $core.List<$core.int> get hardware => $_getN(3);
  @$pb.TagNumber(4)
  set hardware($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHardware() => $_has(3);
  @$pb.TagNumber(4)
  void clearHardware() => $_clearField(4);
}

/// Checks an Argon2id parameter set against a policy.
class CheckKdfParamsRequest extends $pb.GeneratedMessage {
  factory CheckKdfParamsRequest({
    $core.List<$core.int>? params,
    KdfPolicy? policy,
  }) {
    final result = CheckKdfParamsRequest._();
    if (params != null) result.params = params;
    if (policy != null) result.policy = policy;
    return result;
  }

  CheckKdfParamsRequest._();

  factory CheckKdfParamsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckKdfParamsRequest()..mergeFromBuffer(data, registry);
  factory CheckKdfParamsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckKdfParamsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckKdfParamsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: CheckKdfParamsRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'params', $pb.PbFieldType.OY)
    ..aE<KdfPolicy>(2, _omitFieldNames ? '' : 'policy',
        enumValues: KdfPolicy.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckKdfParamsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckKdfParamsRequest copyWith(
          void Function(CheckKdfParamsRequest) updates) =>
      super.copyWith((message) => updates(message as CheckKdfParamsRequest))
          as CheckKdfParamsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CheckKdfParamsRequest() / CheckKdfParamsRequest.new instead')
  static CheckKdfParamsRequest create() => CheckKdfParamsRequest._();
  static $pb.GeneratedMessage $_createMessage() => CheckKdfParamsRequest._();
  @$core.override
  CheckKdfParamsRequest createEmptyInstance() => CheckKdfParamsRequest._();
  @$core.pragma('dart2js:noInline')
  static CheckKdfParamsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckKdfParamsRequest>(
          CheckKdfParamsRequest.$_createMessage);
  static CheckKdfParamsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get params => $_getN(0);
  @$pb.TagNumber(1)
  set params($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasParams() => $_has(0);
  @$pb.TagNumber(1)
  void clearParams() => $_clearField(1);

  @$pb.TagNumber(2)
  KdfPolicy get policy => $_getN(1);
  @$pb.TagNumber(2)
  set policy(KdfPolicy value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPolicy() => $_has(1);
  @$pb.TagNumber(2)
  void clearPolicy() => $_clearField(2);
}

/// Nothing: the parameters pass.
class CheckKdfParamsResponse extends $pb.GeneratedMessage {
  factory CheckKdfParamsResponse() => CheckKdfParamsResponse._();

  CheckKdfParamsResponse._();

  factory CheckKdfParamsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckKdfParamsResponse()..mergeFromBuffer(data, registry);
  factory CheckKdfParamsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckKdfParamsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckKdfParamsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: CheckKdfParamsResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckKdfParamsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckKdfParamsResponse copyWith(
          void Function(CheckKdfParamsResponse) updates) =>
      super.copyWith((message) => updates(message as CheckKdfParamsResponse))
          as CheckKdfParamsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CheckKdfParamsResponse() / CheckKdfParamsResponse.new instead')
  static CheckKdfParamsResponse create() => CheckKdfParamsResponse._();
  static $pb.GeneratedMessage $_createMessage() => CheckKdfParamsResponse._();
  @$core.override
  CheckKdfParamsResponse createEmptyInstance() => CheckKdfParamsResponse._();
  @$core.pragma('dart2js:noInline')
  static CheckKdfParamsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckKdfParamsResponse>(
          CheckKdfParamsResponse.$_createMessage);
  static CheckKdfParamsResponse? _defaultInstance;
}

/// Where a wrap belongs. Readers rebuild it, so a wrap moved elsewhere fails; empty ids are zero.
class WrapContext extends $pb.GeneratedMessage {
  factory WrapContext({
    $core.List<$core.int>? userId,
    $core.List<$core.int>? containerId,
    $core.List<$core.int>? subjectId,
    $core.int? number,
  }) {
    final result = WrapContext._();
    if (userId != null) result.userId = userId;
    if (containerId != null) result.containerId = containerId;
    if (subjectId != null) result.subjectId = subjectId;
    if (number != null) result.number = number;
    return result;
  }

  WrapContext._();

  factory WrapContext.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WrapContext()..mergeFromBuffer(data, registry);
  factory WrapContext.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WrapContext()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WrapContext',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: WrapContext.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'containerId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'subjectId', $pb.PbFieldType.OY)
    ..aI(4, _omitFieldNames ? '' : 'number', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WrapContext clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WrapContext copyWith(void Function(WrapContext) updates) =>
      super.copyWith((message) => updates(message as WrapContext))
          as WrapContext;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WrapContext() / WrapContext.new instead')
  static WrapContext create() => WrapContext._();
  static $pb.GeneratedMessage $_createMessage() => WrapContext._();
  @$core.override
  WrapContext createEmptyInstance() => WrapContext._();
  @$core.pragma('dart2js:noInline')
  static WrapContext getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WrapContext>(
          WrapContext.$_createMessage);
  static WrapContext? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get containerId => $_getN(1);
  @$pb.TagNumber(2)
  set containerId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContainerId() => $_has(1);
  @$pb.TagNumber(2)
  void clearContainerId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get subjectId => $_getN(2);
  @$pb.TagNumber(3)
  set subjectId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSubjectId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSubjectId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get number => $_getIZ(3);
  @$pb.TagNumber(4)
  set number($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNumber() => $_has(3);
  @$pb.TagNumber(4)
  void clearNumber() => $_clearField(4);
}

/// Wraps a key under another as a PLW.
class WrapKeyRequest extends $pb.GeneratedMessage {
  factory WrapKeyRequest({
    $core.int? wrappingKey,
    $core.int? key,
    $core.int? wrappedType,
    WrapContext? context,
    $core.List<$core.int>? nonce,
  }) {
    final result = WrapKeyRequest._();
    if (wrappingKey != null) result.wrappingKey = wrappingKey;
    if (key != null) result.key = key;
    if (wrappedType != null) result.wrappedType = wrappedType;
    if (context != null) result.context = context;
    if (nonce != null) result.nonce = nonce;
    return result;
  }

  WrapKeyRequest._();

  factory WrapKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WrapKeyRequest()..mergeFromBuffer(data, registry);
  factory WrapKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WrapKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WrapKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: WrapKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'wrappingKey',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'wrappedType',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<WrapContext>(4, _omitFieldNames ? '' : 'context',
        subBuilder: WrapContext.$_createMessage)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WrapKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WrapKeyRequest copyWith(void Function(WrapKeyRequest) updates) =>
      super.copyWith((message) => updates(message as WrapKeyRequest))
          as WrapKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WrapKeyRequest() / WrapKeyRequest.new instead')
  static WrapKeyRequest create() => WrapKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => WrapKeyRequest._();
  @$core.override
  WrapKeyRequest createEmptyInstance() => WrapKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static WrapKeyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WrapKeyRequest>(
          WrapKeyRequest.$_createMessage);
  static WrapKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get wrappingKey => $_getIZ(0);
  @$pb.TagNumber(1)
  set wrappingKey($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWrappingKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearWrappingKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get key => $_getIZ(1);
  @$pb.TagNumber(2)
  set key($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get wrappedType => $_getIZ(2);
  @$pb.TagNumber(3)
  set wrappedType($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWrappedType() => $_has(2);
  @$pb.TagNumber(3)
  void clearWrappedType() => $_clearField(3);

  @$pb.TagNumber(4)
  WrapContext get context => $_getN(3);
  @$pb.TagNumber(4)
  set context(WrapContext value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasContext() => $_has(3);
  @$pb.TagNumber(4)
  void clearContext() => $_clearField(4);
  @$pb.TagNumber(4)
  WrapContext ensureContext() => $_ensure(3);

  /// 24 random bytes.
  @$pb.TagNumber(5)
  $core.List<$core.int> get nonce => $_getN(4);
  @$pb.TagNumber(5)
  set nonce($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNonce() => $_has(4);
  @$pb.TagNumber(5)
  void clearNonce() => $_clearField(5);
}

/// A PLW, 144 bytes.
class WrapKeyResponse extends $pb.GeneratedMessage {
  factory WrapKeyResponse({
    $core.List<$core.int>? wrap,
  }) {
    final result = WrapKeyResponse._();
    if (wrap != null) result.wrap = wrap;
    return result;
  }

  WrapKeyResponse._();

  factory WrapKeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WrapKeyResponse()..mergeFromBuffer(data, registry);
  factory WrapKeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WrapKeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WrapKeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: WrapKeyResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'wrap', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WrapKeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WrapKeyResponse copyWith(void Function(WrapKeyResponse) updates) =>
      super.copyWith((message) => updates(message as WrapKeyResponse))
          as WrapKeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WrapKeyResponse() / WrapKeyResponse.new instead')
  static WrapKeyResponse create() => WrapKeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => WrapKeyResponse._();
  @$core.override
  WrapKeyResponse createEmptyInstance() => WrapKeyResponse._();
  @$core.pragma('dart2js:noInline')
  static WrapKeyResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WrapKeyResponse>(
          WrapKeyResponse.$_createMessage);
  static WrapKeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get wrap => $_getN(0);
  @$pb.TagNumber(1)
  set wrap($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWrap() => $_has(0);
  @$pb.TagNumber(1)
  void clearWrap() => $_clearField(1);
}

/// Opens a PLW into the keyring; a wrap of another wrapped type fails.
class UnwrapKeyRequest extends $pb.GeneratedMessage {
  factory UnwrapKeyRequest({
    $core.int? wrappingKey,
    $core.int? wrappedType,
    WrapContext? context,
    $core.List<$core.int>? wrap,
  }) {
    final result = UnwrapKeyRequest._();
    if (wrappingKey != null) result.wrappingKey = wrappingKey;
    if (wrappedType != null) result.wrappedType = wrappedType;
    if (context != null) result.context = context;
    if (wrap != null) result.wrap = wrap;
    return result;
  }

  UnwrapKeyRequest._();

  factory UnwrapKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UnwrapKeyRequest()..mergeFromBuffer(data, registry);
  factory UnwrapKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UnwrapKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UnwrapKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: UnwrapKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'wrappingKey',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'wrappedType',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<WrapContext>(3, _omitFieldNames ? '' : 'context',
        subBuilder: WrapContext.$_createMessage)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'wrap', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnwrapKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UnwrapKeyRequest copyWith(void Function(UnwrapKeyRequest) updates) =>
      super.copyWith((message) => updates(message as UnwrapKeyRequest))
          as UnwrapKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UnwrapKeyRequest() / UnwrapKeyRequest.new instead')
  static UnwrapKeyRequest create() => UnwrapKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => UnwrapKeyRequest._();
  @$core.override
  UnwrapKeyRequest createEmptyInstance() => UnwrapKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static UnwrapKeyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UnwrapKeyRequest>(
          UnwrapKeyRequest.$_createMessage);
  static UnwrapKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get wrappingKey => $_getIZ(0);
  @$pb.TagNumber(1)
  set wrappingKey($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWrappingKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearWrappingKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get wrappedType => $_getIZ(1);
  @$pb.TagNumber(2)
  set wrappedType($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWrappedType() => $_has(1);
  @$pb.TagNumber(2)
  void clearWrappedType() => $_clearField(2);

  @$pb.TagNumber(3)
  WrapContext get context => $_getN(2);
  @$pb.TagNumber(3)
  set context(WrapContext value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasContext() => $_has(2);
  @$pb.TagNumber(3)
  void clearContext() => $_clearField(3);
  @$pb.TagNumber(3)
  WrapContext ensureContext() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get wrap => $_getN(3);
  @$pb.TagNumber(4)
  set wrap($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasWrap() => $_has(3);
  @$pb.TagNumber(4)
  void clearWrap() => $_clearField(4);
}

/// The dedup token of an original: HMAC-SHA256(DedupKey, SHA-256 of its bytes), equal only within one user's library.
class DedupTokenRequest extends $pb.GeneratedMessage {
  factory DedupTokenRequest({
    $core.int? key,
    $core.List<$core.int>? sha256,
  }) {
    final result = DedupTokenRequest._();
    if (key != null) result.key = key;
    if (sha256 != null) result.sha256 = sha256;
    return result;
  }

  DedupTokenRequest._();

  factory DedupTokenRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DedupTokenRequest()..mergeFromBuffer(data, registry);
  factory DedupTokenRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DedupTokenRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DedupTokenRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DedupTokenRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'sha256', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DedupTokenRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DedupTokenRequest copyWith(void Function(DedupTokenRequest) updates) =>
      super.copyWith((message) => updates(message as DedupTokenRequest))
          as DedupTokenRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DedupTokenRequest() / DedupTokenRequest.new instead')
  static DedupTokenRequest create() => DedupTokenRequest._();
  static $pb.GeneratedMessage $_createMessage() => DedupTokenRequest._();
  @$core.override
  DedupTokenRequest createEmptyInstance() => DedupTokenRequest._();
  @$core.pragma('dart2js:noInline')
  static DedupTokenRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DedupTokenRequest>(
          DedupTokenRequest.$_createMessage);
  static DedupTokenRequest? _defaultInstance;

  /// The DedupKey.
  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  /// The SHA-256 of the original.
  @$pb.TagNumber(2)
  $core.List<$core.int> get sha256 => $_getN(1);
  @$pb.TagNumber(2)
  set sha256($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSha256() => $_has(1);
  @$pb.TagNumber(2)
  void clearSha256() => $_clearField(2);
}

/// A dedup token, 32 bytes.
class DedupTokenResponse extends $pb.GeneratedMessage {
  factory DedupTokenResponse({
    $core.List<$core.int>? token,
  }) {
    final result = DedupTokenResponse._();
    if (token != null) result.token = token;
    return result;
  }

  DedupTokenResponse._();

  factory DedupTokenResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DedupTokenResponse()..mergeFromBuffer(data, registry);
  factory DedupTokenResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DedupTokenResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DedupTokenResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DedupTokenResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'token', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DedupTokenResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DedupTokenResponse copyWith(void Function(DedupTokenResponse) updates) =>
      super.copyWith((message) => updates(message as DedupTokenResponse))
          as DedupTokenResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DedupTokenResponse() / DedupTokenResponse.new instead')
  static DedupTokenResponse create() => DedupTokenResponse._();
  static $pb.GeneratedMessage $_createMessage() => DedupTokenResponse._();
  @$core.override
  DedupTokenResponse createEmptyInstance() => DedupTokenResponse._();
  @$core.pragma('dart2js:noInline')
  static DedupTokenResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DedupTokenResponse>(
          DedupTokenResponse.$_createMessage);
  static DedupTokenResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get token => $_getN(0);
  @$pb.TagNumber(1)
  set token($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearToken() => $_clearField(1);
}

/// Derives the LinkKey of a public link or static export into the keyring, and the verifier the server stores.
class LinkKeysRequest extends $pb.GeneratedMessage {
  factory LinkKeysRequest({
    $core.int? secret,
    $core.List<$core.int>? linkId,
    $core.int? passwordHash,
  }) {
    final result = LinkKeysRequest._();
    if (secret != null) result.secret = secret;
    if (linkId != null) result.linkId = linkId;
    if (passwordHash != null) result.passwordHash = passwordHash;
    return result;
  }

  LinkKeysRequest._();

  factory LinkKeysRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkKeysRequest()..mergeFromBuffer(data, registry);
  factory LinkKeysRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkKeysRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LinkKeysRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: LinkKeysRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'secret', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'linkId', $pb.PbFieldType.OY)
    ..aI(3, _omitFieldNames ? '' : 'passwordHash',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkKeysRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkKeysRequest copyWith(void Function(LinkKeysRequest) updates) =>
      super.copyWith((message) => updates(message as LinkKeysRequest))
          as LinkKeysRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LinkKeysRequest() / LinkKeysRequest.new instead')
  static LinkKeysRequest create() => LinkKeysRequest._();
  static $pb.GeneratedMessage $_createMessage() => LinkKeysRequest._();
  @$core.override
  LinkKeysRequest createEmptyInstance() => LinkKeysRequest._();
  @$core.pragma('dart2js:noInline')
  static LinkKeysRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LinkKeysRequest>(
          LinkKeysRequest.$_createMessage);
  static LinkKeysRequest? _defaultInstance;

  /// The LinkSecret.
  @$pb.TagNumber(1)
  $core.int get secret => $_getIZ(0);
  @$pb.TagNumber(1)
  set secret($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSecret() => $_has(0);
  @$pb.TagNumber(1)
  void clearSecret() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get linkId => $_getN(1);
  @$pb.TagNumber(2)
  set linkId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLinkId() => $_has(1);
  @$pb.TagNumber(2)
  void clearLinkId() => $_clearField(2);

  /// With a password, its hash: DerivePasswordKey with no label and the parameters (1, 64 MiB, 3, 1, link_id).
  @$pb.TagNumber(3)
  $core.int get passwordHash => $_getIZ(2);
  @$pb.TagNumber(3)
  set passwordHash($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPasswordHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearPasswordHash() => $_clearField(3);
}

/// The LinkKey's handle and key_id, and SHA-256(LinkAuth).
class LinkKeysResponse extends $pb.GeneratedMessage {
  factory LinkKeysResponse({
    $core.int? key,
    $core.List<$core.int>? keyId,
    $core.List<$core.int>? verifier,
  }) {
    final result = LinkKeysResponse._();
    if (key != null) result.key = key;
    if (keyId != null) result.keyId = keyId;
    if (verifier != null) result.verifier = verifier;
    return result;
  }

  LinkKeysResponse._();

  factory LinkKeysResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkKeysResponse()..mergeFromBuffer(data, registry);
  factory LinkKeysResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkKeysResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LinkKeysResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: LinkKeysResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'keyId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'verifier', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkKeysResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkKeysResponse copyWith(void Function(LinkKeysResponse) updates) =>
      super.copyWith((message) => updates(message as LinkKeysResponse))
          as LinkKeysResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LinkKeysResponse() / LinkKeysResponse.new instead')
  static LinkKeysResponse create() => LinkKeysResponse._();
  static $pb.GeneratedMessage $_createMessage() => LinkKeysResponse._();
  @$core.override
  LinkKeysResponse createEmptyInstance() => LinkKeysResponse._();
  @$core.pragma('dart2js:noInline')
  static LinkKeysResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LinkKeysResponse>(
          LinkKeysResponse.$_createMessage);
  static LinkKeysResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get keyId => $_getN(1);
  @$pb.TagNumber(2)
  set keyId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKeyId() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get verifier => $_getN(2);
  @$pb.TagNumber(3)
  set verifier($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVerifier() => $_has(2);
  @$pb.TagNumber(3)
  void clearVerifier() => $_clearField(3);
}

/// Formats the URL fragment of a link: v1.<link_id>.<secret>[.p][.<SHA-256(manifest)[0..8)>], in base64url.
class LinkFragmentRequest extends $pb.GeneratedMessage {
  factory LinkFragmentRequest({
    $core.List<$core.int>? linkId,
    $core.List<$core.int>? secret,
    $core.bool? password,
    $core.List<$core.int>? manifest,
  }) {
    final result = LinkFragmentRequest._();
    if (linkId != null) result.linkId = linkId;
    if (secret != null) result.secret = secret;
    if (password != null) result.password = password;
    if (manifest != null) result.manifest = manifest;
    return result;
  }

  LinkFragmentRequest._();

  factory LinkFragmentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkFragmentRequest()..mergeFromBuffer(data, registry);
  factory LinkFragmentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkFragmentRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LinkFragmentRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: LinkFragmentRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'linkId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'secret', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'password')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'manifest', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkFragmentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkFragmentRequest copyWith(void Function(LinkFragmentRequest) updates) =>
      super.copyWith((message) => updates(message as LinkFragmentRequest))
          as LinkFragmentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use LinkFragmentRequest() / LinkFragmentRequest.new instead')
  static LinkFragmentRequest create() => LinkFragmentRequest._();
  static $pb.GeneratedMessage $_createMessage() => LinkFragmentRequest._();
  @$core.override
  LinkFragmentRequest createEmptyInstance() => LinkFragmentRequest._();
  @$core.pragma('dart2js:noInline')
  static LinkFragmentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LinkFragmentRequest>(
          LinkFragmentRequest.$_createMessage);
  static LinkFragmentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get linkId => $_getN(0);
  @$pb.TagNumber(1)
  set linkId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLinkId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLinkId() => $_clearField(1);

  /// The LinkSecret, which the fragment carries.
  @$pb.TagNumber(2)
  $core.List<$core.int> get secret => $_getN(1);
  @$pb.TagNumber(2)
  set secret($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearSecret() => $_clearField(2);

  /// A password is required.
  @$pb.TagNumber(3)
  $core.bool get password => $_getBF(2);
  @$pb.TagNumber(3)
  set password($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPassword() => $_has(2);
  @$pb.TagNumber(3)
  void clearPassword() => $_clearField(3);

  /// The link's PLX manifest; none when empty.
  @$pb.TagNumber(4)
  $core.List<$core.int> get manifest => $_getN(3);
  @$pb.TagNumber(4)
  set manifest($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasManifest() => $_has(3);
  @$pb.TagNumber(4)
  void clearManifest() => $_clearField(4);
}

/// The fragment, without the '#'.
class LinkFragmentResponse extends $pb.GeneratedMessage {
  factory LinkFragmentResponse({
    $core.String? fragment,
  }) {
    final result = LinkFragmentResponse._();
    if (fragment != null) result.fragment = fragment;
    return result;
  }

  LinkFragmentResponse._();

  factory LinkFragmentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkFragmentResponse()..mergeFromBuffer(data, registry);
  factory LinkFragmentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LinkFragmentResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LinkFragmentResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: LinkFragmentResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'fragment')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkFragmentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinkFragmentResponse copyWith(void Function(LinkFragmentResponse) updates) =>
      super.copyWith((message) => updates(message as LinkFragmentResponse))
          as LinkFragmentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use LinkFragmentResponse() / LinkFragmentResponse.new instead')
  static LinkFragmentResponse create() => LinkFragmentResponse._();
  static $pb.GeneratedMessage $_createMessage() => LinkFragmentResponse._();
  @$core.override
  LinkFragmentResponse createEmptyInstance() => LinkFragmentResponse._();
  @$core.pragma('dart2js:noInline')
  static LinkFragmentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LinkFragmentResponse>(
          LinkFragmentResponse.$_createMessage);
  static LinkFragmentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fragment => $_getSZ(0);
  @$pb.TagNumber(1)
  set fragment($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFragment() => $_has(0);
  @$pb.TagNumber(1)
  void clearFragment() => $_clearField(1);
}

/// Encodes 32 bytes of recovery entropy, fresh randomness, as the recovery phrase of a recovery kit
/// (docs/dev/crypto-v1.md#recovery-phrase).
class RecoveryPhraseRequest extends $pb.GeneratedMessage {
  factory RecoveryPhraseRequest({
    $core.List<$core.int>? entropy,
  }) {
    final result = RecoveryPhraseRequest._();
    if (entropy != null) result.entropy = entropy;
    return result;
  }

  RecoveryPhraseRequest._();

  factory RecoveryPhraseRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecoveryPhraseRequest()..mergeFromBuffer(data, registry);
  factory RecoveryPhraseRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecoveryPhraseRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecoveryPhraseRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: RecoveryPhraseRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'entropy', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecoveryPhraseRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecoveryPhraseRequest copyWith(
          void Function(RecoveryPhraseRequest) updates) =>
      super.copyWith((message) => updates(message as RecoveryPhraseRequest))
          as RecoveryPhraseRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RecoveryPhraseRequest() / RecoveryPhraseRequest.new instead')
  static RecoveryPhraseRequest create() => RecoveryPhraseRequest._();
  static $pb.GeneratedMessage $_createMessage() => RecoveryPhraseRequest._();
  @$core.override
  RecoveryPhraseRequest createEmptyInstance() => RecoveryPhraseRequest._();
  @$core.pragma('dart2js:noInline')
  static RecoveryPhraseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RecoveryPhraseRequest>(
          RecoveryPhraseRequest.$_createMessage);
  static RecoveryPhraseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get entropy => $_getN(0);
  @$pb.TagNumber(1)
  set entropy($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEntropy() => $_has(0);
  @$pb.TagNumber(1)
  void clearEntropy() => $_clearField(1);
}

/// The phrase: 24 English words joined by spaces.
class RecoveryPhraseResponse extends $pb.GeneratedMessage {
  factory RecoveryPhraseResponse({
    $core.String? phrase,
  }) {
    final result = RecoveryPhraseResponse._();
    if (phrase != null) result.phrase = phrase;
    return result;
  }

  RecoveryPhraseResponse._();

  factory RecoveryPhraseResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecoveryPhraseResponse()..mergeFromBuffer(data, registry);
  factory RecoveryPhraseResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecoveryPhraseResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecoveryPhraseResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: RecoveryPhraseResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'phrase')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecoveryPhraseResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecoveryPhraseResponse copyWith(
          void Function(RecoveryPhraseResponse) updates) =>
      super.copyWith((message) => updates(message as RecoveryPhraseResponse))
          as RecoveryPhraseResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RecoveryPhraseResponse() / RecoveryPhraseResponse.new instead')
  static RecoveryPhraseResponse create() => RecoveryPhraseResponse._();
  static $pb.GeneratedMessage $_createMessage() => RecoveryPhraseResponse._();
  @$core.override
  RecoveryPhraseResponse createEmptyInstance() => RecoveryPhraseResponse._();
  @$core.pragma('dart2js:noInline')
  static RecoveryPhraseResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RecoveryPhraseResponse>(
          RecoveryPhraseResponse.$_createMessage);
  static RecoveryPhraseResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get phrase => $_getSZ(0);
  @$pb.TagNumber(1)
  set phrase($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhrase() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhrase() => $_clearField(1);
}

/// Reads a recovery phrase as typed into the keyring as KEK_rec, which wraps the account master key. A phrase the
/// reader refuses fails with its reason: bad_length, unknown_word (with `word`, its 1-based position) or bad_checksum.
class RecoveryKeyRequest extends $pb.GeneratedMessage {
  factory RecoveryKeyRequest({
    $core.String? phrase,
  }) {
    final result = RecoveryKeyRequest._();
    if (phrase != null) result.phrase = phrase;
    return result;
  }

  RecoveryKeyRequest._();

  factory RecoveryKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecoveryKeyRequest()..mergeFromBuffer(data, registry);
  factory RecoveryKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecoveryKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecoveryKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: RecoveryKeyRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'phrase')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecoveryKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecoveryKeyRequest copyWith(void Function(RecoveryKeyRequest) updates) =>
      super.copyWith((message) => updates(message as RecoveryKeyRequest))
          as RecoveryKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RecoveryKeyRequest() / RecoveryKeyRequest.new instead')
  static RecoveryKeyRequest create() => RecoveryKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => RecoveryKeyRequest._();
  @$core.override
  RecoveryKeyRequest createEmptyInstance() => RecoveryKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static RecoveryKeyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RecoveryKeyRequest>(
          RecoveryKeyRequest.$_createMessage);
  static RecoveryKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get phrase => $_getSZ(0);
  @$pb.TagNumber(1)
  set phrase($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhrase() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhrase() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
