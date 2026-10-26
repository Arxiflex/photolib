// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/local.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// A lockbox slot: one factor that unlocks the device.
class LockboxSlot extends $pb.GeneratedMessage {
  factory LockboxSlot({
    $core.int? factor,
    $core.bool? hardware,
    $core.List<$core.int>? userId,
    $core.List<$core.int>? params,
    $core.List<$core.int>? wrap,
    $core.int? key,
    $core.List<$core.int>? nonce,
  }) {
    final result = LockboxSlot._();
    if (factor != null) result.factor = factor;
    if (hardware != null) result.hardware = hardware;
    if (userId != null) result.userId = userId;
    if (params != null) result.params = params;
    if (wrap != null) result.wrap = wrap;
    if (key != null) result.key = key;
    if (nonce != null) result.nonce = nonce;
    return result;
  }

  LockboxSlot._();

  factory LockboxSlot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LockboxSlot()..mergeFromBuffer(data, registry);
  factory LockboxSlot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LockboxSlot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LockboxSlot',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: LockboxSlot.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'factor', fieldType: $pb.PbFieldType.OU3)
    ..aOB(2, _omitFieldNames ? '' : 'hardware')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'params', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'wrap', $pb.PbFieldType.OY)
    ..aI(6, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LockboxSlot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LockboxSlot copyWith(void Function(LockboxSlot) updates) =>
      super.copyWith((message) => updates(message as LockboxSlot))
          as LockboxSlot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LockboxSlot() / LockboxSlot.new instead')
  static LockboxSlot create() => LockboxSlot._();
  static $pb.GeneratedMessage $_createMessage() => LockboxSlot._();
  @$core.override
  LockboxSlot createEmptyInstance() => LockboxSlot._();
  @$core.pragma('dart2js:noInline')
  static LockboxSlot getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LockboxSlot>(
          LockboxSlot.$_createMessage);
  static LockboxSlot? _defaultInstance;

  /// 1 keystore, 2 passcode, 3 biometric, 4 recovery code, 5 account.
  @$pb.TagNumber(1)
  $core.int get factor => $_getIZ(0);
  @$pb.TagNumber(1)
  set factor($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFactor() => $_has(0);
  @$pb.TagNumber(1)
  void clearFactor() => $_clearField(1);

  /// The passcode's key includes the hardware binding.
  @$pb.TagNumber(2)
  $core.bool get hardware => $_getBF(1);
  @$pb.TagNumber(2)
  set hardware($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHardware() => $_has(1);
  @$pb.TagNumber(2)
  void clearHardware() => $_clearField(2);

  /// The account of factor 5.
  @$pb.TagNumber(3)
  $core.List<$core.int> get userId => $_getN(2);
  @$pb.TagNumber(3)
  set userId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(2);
  @$pb.TagNumber(3)
  void clearUserId() => $_clearField(3);

  /// The passcode's Argon2id parameters, held to the device policy.
  @$pb.TagNumber(4)
  $core.List<$core.int> get params => $_getN(3);
  @$pb.TagNumber(4)
  set params($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasParams() => $_has(3);
  @$pb.TagNumber(4)
  void clearParams() => $_clearField(4);

  /// The slot's PLW; sealing keeps it when the slot names no key.
  @$pb.TagNumber(5)
  $core.List<$core.int> get wrap => $_getN(4);
  @$pb.TagNumber(5)
  set wrap($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasWrap() => $_has(4);
  @$pb.TagNumber(5)
  void clearWrap() => $_clearField(5);

  /// When sealing, the factor's key, to wrap the device data key under anew.
  @$pb.TagNumber(6)
  $core.int get key => $_getIZ(5);
  @$pb.TagNumber(6)
  set key($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasKey() => $_has(5);
  @$pb.TagNumber(6)
  void clearKey() => $_clearField(6);

  /// With a key: 24 random bytes.
  @$pb.TagNumber(7)
  $core.List<$core.int> get nonce => $_getN(6);
  @$pb.TagNumber(7)
  set nonce($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasNonce() => $_has(6);
  @$pb.TagNumber(7)
  void clearNonce() => $_clearField(7);
}

/// Seals a lockbox: the device data key wrapped under each slot's key, or kept from the lockbox it replaces.
class SealLockboxRequest extends $pb.GeneratedMessage {
  factory SealLockboxRequest({
    $core.int? key,
    $core.List<$core.int>? deviceId,
    $core.Iterable<LockboxSlot>? slots,
  }) {
    final result = SealLockboxRequest._();
    if (key != null) result.key = key;
    if (deviceId != null) result.deviceId = deviceId;
    if (slots != null) result.slots.addAll(slots);
    return result;
  }

  SealLockboxRequest._();

  factory SealLockboxRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SealLockboxRequest()..mergeFromBuffer(data, registry);
  factory SealLockboxRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SealLockboxRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SealLockboxRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: SealLockboxRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..pPM<LockboxSlot>(3, _omitFieldNames ? '' : 'slots',
        subBuilder: LockboxSlot.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SealLockboxRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SealLockboxRequest copyWith(void Function(SealLockboxRequest) updates) =>
      super.copyWith((message) => updates(message as SealLockboxRequest))
          as SealLockboxRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SealLockboxRequest() / SealLockboxRequest.new instead')
  static SealLockboxRequest create() => SealLockboxRequest._();
  static $pb.GeneratedMessage $_createMessage() => SealLockboxRequest._();
  @$core.override
  SealLockboxRequest createEmptyInstance() => SealLockboxRequest._();
  @$core.pragma('dart2js:noInline')
  static SealLockboxRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SealLockboxRequest>(
          SealLockboxRequest.$_createMessage);
  static SealLockboxRequest? _defaultInstance;

  /// The device data key.
  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceId => $_getN(1);
  @$pb.TagNumber(2)
  set deviceId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<LockboxSlot> get slots => $_getList(2);
}

/// A lockbox.
class SealLockboxResponse extends $pb.GeneratedMessage {
  factory SealLockboxResponse({
    $core.List<$core.int>? lockbox,
  }) {
    final result = SealLockboxResponse._();
    if (lockbox != null) result.lockbox = lockbox;
    return result;
  }

  SealLockboxResponse._();

  factory SealLockboxResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SealLockboxResponse()..mergeFromBuffer(data, registry);
  factory SealLockboxResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SealLockboxResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SealLockboxResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: SealLockboxResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'lockbox', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SealLockboxResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SealLockboxResponse copyWith(void Function(SealLockboxResponse) updates) =>
      super.copyWith((message) => updates(message as SealLockboxResponse))
          as SealLockboxResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use SealLockboxResponse() / SealLockboxResponse.new instead')
  static SealLockboxResponse create() => SealLockboxResponse._();
  static $pb.GeneratedMessage $_createMessage() => SealLockboxResponse._();
  @$core.override
  SealLockboxResponse createEmptyInstance() => SealLockboxResponse._();
  @$core.pragma('dart2js:noInline')
  static SealLockboxResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SealLockboxResponse>(
          SealLockboxResponse.$_createMessage);
  static SealLockboxResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get lockbox => $_getN(0);
  @$pb.TagNumber(1)
  set lockbox($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLockbox() => $_has(0);
  @$pb.TagNumber(1)
  void clearLockbox() => $_clearField(1);
}

/// Checks a lockbox and lists its slots without opening any.
class ReadLockboxRequest extends $pb.GeneratedMessage {
  factory ReadLockboxRequest({
    $core.List<$core.int>? lockbox,
  }) {
    final result = ReadLockboxRequest._();
    if (lockbox != null) result.lockbox = lockbox;
    return result;
  }

  ReadLockboxRequest._();

  factory ReadLockboxRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadLockboxRequest()..mergeFromBuffer(data, registry);
  factory ReadLockboxRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadLockboxRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadLockboxRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ReadLockboxRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'lockbox', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadLockboxRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadLockboxRequest copyWith(void Function(ReadLockboxRequest) updates) =>
      super.copyWith((message) => updates(message as ReadLockboxRequest))
          as ReadLockboxRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReadLockboxRequest() / ReadLockboxRequest.new instead')
  static ReadLockboxRequest create() => ReadLockboxRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReadLockboxRequest._();
  @$core.override
  ReadLockboxRequest createEmptyInstance() => ReadLockboxRequest._();
  @$core.pragma('dart2js:noInline')
  static ReadLockboxRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadLockboxRequest>(
          ReadLockboxRequest.$_createMessage);
  static ReadLockboxRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get lockbox => $_getN(0);
  @$pb.TagNumber(1)
  set lockbox($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLockbox() => $_has(0);
  @$pb.TagNumber(1)
  void clearLockbox() => $_clearField(1);
}

/// What a lockbox holds; its slots carry their wraps, for sealing a lockbox that keeps them.
class ReadLockboxResponse extends $pb.GeneratedMessage {
  factory ReadLockboxResponse({
    $core.List<$core.int>? deviceId,
    $core.List<$core.int>? keyId,
    $core.Iterable<LockboxSlot>? slots,
  }) {
    final result = ReadLockboxResponse._();
    if (deviceId != null) result.deviceId = deviceId;
    if (keyId != null) result.keyId = keyId;
    if (slots != null) result.slots.addAll(slots);
    return result;
  }

  ReadLockboxResponse._();

  factory ReadLockboxResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadLockboxResponse()..mergeFromBuffer(data, registry);
  factory ReadLockboxResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadLockboxResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadLockboxResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ReadLockboxResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'keyId', $pb.PbFieldType.OY)
    ..pPM<LockboxSlot>(3, _omitFieldNames ? '' : 'slots',
        subBuilder: LockboxSlot.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadLockboxResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadLockboxResponse copyWith(void Function(ReadLockboxResponse) updates) =>
      super.copyWith((message) => updates(message as ReadLockboxResponse))
          as ReadLockboxResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ReadLockboxResponse() / ReadLockboxResponse.new instead')
  static ReadLockboxResponse create() => ReadLockboxResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReadLockboxResponse._();
  @$core.override
  ReadLockboxResponse createEmptyInstance() => ReadLockboxResponse._();
  @$core.pragma('dart2js:noInline')
  static ReadLockboxResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadLockboxResponse>(
          ReadLockboxResponse.$_createMessage);
  static ReadLockboxResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceId => $_getN(0);
  @$pb.TagNumber(1)
  set deviceId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  /// The key_id of the device data key.
  @$pb.TagNumber(2)
  $core.List<$core.int> get keyId => $_getN(1);
  @$pb.TagNumber(2)
  set keyId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKeyId() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<LockboxSlot> get slots => $_getList(2);
}

/// Opens a lockbox slot with its factor's key: the device data key enters the keyring.
class OpenLockboxRequest extends $pb.GeneratedMessage {
  factory OpenLockboxRequest({
    $core.List<$core.int>? lockbox,
    $core.int? slot,
    $core.int? key,
  }) {
    final result = OpenLockboxRequest._();
    if (lockbox != null) result.lockbox = lockbox;
    if (slot != null) result.slot = slot;
    if (key != null) result.key = key;
    return result;
  }

  OpenLockboxRequest._();

  factory OpenLockboxRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenLockboxRequest()..mergeFromBuffer(data, registry);
  factory OpenLockboxRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenLockboxRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpenLockboxRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpenLockboxRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'lockbox', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'slot', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenLockboxRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenLockboxRequest copyWith(void Function(OpenLockboxRequest) updates) =>
      super.copyWith((message) => updates(message as OpenLockboxRequest))
          as OpenLockboxRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use OpenLockboxRequest() / OpenLockboxRequest.new instead')
  static OpenLockboxRequest create() => OpenLockboxRequest._();
  static $pb.GeneratedMessage $_createMessage() => OpenLockboxRequest._();
  @$core.override
  OpenLockboxRequest createEmptyInstance() => OpenLockboxRequest._();
  @$core.pragma('dart2js:noInline')
  static OpenLockboxRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpenLockboxRequest>(
          OpenLockboxRequest.$_createMessage);
  static OpenLockboxRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get lockbox => $_getN(0);
  @$pb.TagNumber(1)
  set lockbox($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLockbox() => $_has(0);
  @$pb.TagNumber(1)
  void clearLockbox() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get slot => $_getIZ(1);
  @$pb.TagNumber(2)
  set slot($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSlot() => $_has(1);
  @$pb.TagNumber(2)
  void clearSlot() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get key => $_getIZ(2);
  @$pb.TagNumber(3)
  set key($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearKey() => $_clearField(3);
}

/// Asks for the public key of an inbox key, which locked work seals journal entries to.
class InboxPublicKeyRequest extends $pb.GeneratedMessage {
  factory InboxPublicKeyRequest({
    $core.int? key,
  }) {
    final result = InboxPublicKeyRequest._();
    if (key != null) result.key = key;
    return result;
  }

  InboxPublicKeyRequest._();

  factory InboxPublicKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InboxPublicKeyRequest()..mergeFromBuffer(data, registry);
  factory InboxPublicKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InboxPublicKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InboxPublicKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: InboxPublicKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InboxPublicKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InboxPublicKeyRequest copyWith(
          void Function(InboxPublicKeyRequest) updates) =>
      super.copyWith((message) => updates(message as InboxPublicKeyRequest))
          as InboxPublicKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use InboxPublicKeyRequest() / InboxPublicKeyRequest.new instead')
  static InboxPublicKeyRequest create() => InboxPublicKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => InboxPublicKeyRequest._();
  @$core.override
  InboxPublicKeyRequest createEmptyInstance() => InboxPublicKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static InboxPublicKeyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InboxPublicKeyRequest>(
          InboxPublicKeyRequest.$_createMessage);
  static InboxPublicKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);
}

/// An X25519 public key, 32 bytes.
class InboxPublicKeyResponse extends $pb.GeneratedMessage {
  factory InboxPublicKeyResponse({
    $core.List<$core.int>? publicKey,
  }) {
    final result = InboxPublicKeyResponse._();
    if (publicKey != null) result.publicKey = publicKey;
    return result;
  }

  InboxPublicKeyResponse._();

  factory InboxPublicKeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InboxPublicKeyResponse()..mergeFromBuffer(data, registry);
  factory InboxPublicKeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InboxPublicKeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InboxPublicKeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: InboxPublicKeyResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InboxPublicKeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InboxPublicKeyResponse copyWith(
          void Function(InboxPublicKeyResponse) updates) =>
      super.copyWith((message) => updates(message as InboxPublicKeyResponse))
          as InboxPublicKeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use InboxPublicKeyResponse() / InboxPublicKeyResponse.new instead')
  static InboxPublicKeyResponse create() => InboxPublicKeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => InboxPublicKeyResponse._();
  @$core.override
  InboxPublicKeyResponse createEmptyInstance() => InboxPublicKeyResponse._();
  @$core.pragma('dart2js:noInline')
  static InboxPublicKeyResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InboxPublicKeyResponse>(
          InboxPublicKeyResponse.$_createMessage);
  static InboxPublicKeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get publicKey => $_getN(0);
  @$pb.TagNumber(1)
  set publicKey($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPublicKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearPublicKey() => $_clearField(1);
}

/// Seals a journal entry to an inbox public key; it needs no secret.
class SealJournalEntryRequest extends $pb.GeneratedMessage {
  factory SealJournalEntryRequest({
    $core.List<$core.int>? publicKey,
    $core.List<$core.int>? randomness,
    $core.List<$core.int>? plaintext,
  }) {
    final result = SealJournalEntryRequest._();
    if (publicKey != null) result.publicKey = publicKey;
    if (randomness != null) result.randomness = randomness;
    if (plaintext != null) result.plaintext = plaintext;
    return result;
  }

  SealJournalEntryRequest._();

  factory SealJournalEntryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SealJournalEntryRequest()..mergeFromBuffer(data, registry);
  factory SealJournalEntryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SealJournalEntryRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SealJournalEntryRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: SealJournalEntryRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'randomness', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'plaintext', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SealJournalEntryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SealJournalEntryRequest copyWith(
          void Function(SealJournalEntryRequest) updates) =>
      super.copyWith((message) => updates(message as SealJournalEntryRequest))
          as SealJournalEntryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SealJournalEntryRequest() / SealJournalEntryRequest.new instead')
  static SealJournalEntryRequest create() => SealJournalEntryRequest._();
  static $pb.GeneratedMessage $_createMessage() => SealJournalEntryRequest._();
  @$core.override
  SealJournalEntryRequest createEmptyInstance() => SealJournalEntryRequest._();
  @$core.pragma('dart2js:noInline')
  static SealJournalEntryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SealJournalEntryRequest>(
          SealJournalEntryRequest.$_createMessage);
  static SealJournalEntryRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get publicKey => $_getN(0);
  @$pb.TagNumber(1)
  set publicKey($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPublicKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearPublicKey() => $_clearField(1);

  /// 32 random bytes.
  @$pb.TagNumber(2)
  $core.List<$core.int> get randomness => $_getN(1);
  @$pb.TagNumber(2)
  set randomness($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRandomness() => $_has(1);
  @$pb.TagNumber(2)
  void clearRandomness() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get plaintext => $_getN(2);
  @$pb.TagNumber(3)
  set plaintext($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPlaintext() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlaintext() => $_clearField(3);
}

/// A sealed journal entry.
class SealJournalEntryResponse extends $pb.GeneratedMessage {
  factory SealJournalEntryResponse({
    $core.List<$core.int>? entry,
  }) {
    final result = SealJournalEntryResponse._();
    if (entry != null) result.entry = entry;
    return result;
  }

  SealJournalEntryResponse._();

  factory SealJournalEntryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SealJournalEntryResponse()..mergeFromBuffer(data, registry);
  factory SealJournalEntryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SealJournalEntryResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SealJournalEntryResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: SealJournalEntryResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'entry', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SealJournalEntryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SealJournalEntryResponse copyWith(
          void Function(SealJournalEntryResponse) updates) =>
      super.copyWith((message) => updates(message as SealJournalEntryResponse))
          as SealJournalEntryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SealJournalEntryResponse() / SealJournalEntryResponse.new instead')
  static SealJournalEntryResponse create() => SealJournalEntryResponse._();
  static $pb.GeneratedMessage $_createMessage() => SealJournalEntryResponse._();
  @$core.override
  SealJournalEntryResponse createEmptyInstance() =>
      SealJournalEntryResponse._();
  @$core.pragma('dart2js:noInline')
  static SealJournalEntryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SealJournalEntryResponse>(
          SealJournalEntryResponse.$_createMessage);
  static SealJournalEntryResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get entry => $_getN(0);
  @$pb.TagNumber(1)
  set entry($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEntry() => $_has(0);
  @$pb.TagNumber(1)
  void clearEntry() => $_clearField(1);
}

/// Opens a journal entry with the inbox key.
class OpenJournalEntryRequest extends $pb.GeneratedMessage {
  factory OpenJournalEntryRequest({
    $core.int? key,
    $core.List<$core.int>? entry,
  }) {
    final result = OpenJournalEntryRequest._();
    if (key != null) result.key = key;
    if (entry != null) result.entry = entry;
    return result;
  }

  OpenJournalEntryRequest._();

  factory OpenJournalEntryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenJournalEntryRequest()..mergeFromBuffer(data, registry);
  factory OpenJournalEntryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenJournalEntryRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpenJournalEntryRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpenJournalEntryRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'entry', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenJournalEntryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenJournalEntryRequest copyWith(
          void Function(OpenJournalEntryRequest) updates) =>
      super.copyWith((message) => updates(message as OpenJournalEntryRequest))
          as OpenJournalEntryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use OpenJournalEntryRequest() / OpenJournalEntryRequest.new instead')
  static OpenJournalEntryRequest create() => OpenJournalEntryRequest._();
  static $pb.GeneratedMessage $_createMessage() => OpenJournalEntryRequest._();
  @$core.override
  OpenJournalEntryRequest createEmptyInstance() => OpenJournalEntryRequest._();
  @$core.pragma('dart2js:noInline')
  static OpenJournalEntryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpenJournalEntryRequest>(
          OpenJournalEntryRequest.$_createMessage);
  static OpenJournalEntryRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get entry => $_getN(1);
  @$pb.TagNumber(2)
  set entry($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEntry() => $_has(1);
  @$pb.TagNumber(2)
  void clearEntry() => $_clearField(2);
}

/// The plaintext of a journal entry.
class OpenJournalEntryResponse extends $pb.GeneratedMessage {
  factory OpenJournalEntryResponse({
    $core.List<$core.int>? plaintext,
  }) {
    final result = OpenJournalEntryResponse._();
    if (plaintext != null) result.plaintext = plaintext;
    return result;
  }

  OpenJournalEntryResponse._();

  factory OpenJournalEntryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenJournalEntryResponse()..mergeFromBuffer(data, registry);
  factory OpenJournalEntryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenJournalEntryResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpenJournalEntryResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: OpenJournalEntryResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'plaintext', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenJournalEntryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenJournalEntryResponse copyWith(
          void Function(OpenJournalEntryResponse) updates) =>
      super.copyWith((message) => updates(message as OpenJournalEntryResponse))
          as OpenJournalEntryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use OpenJournalEntryResponse() / OpenJournalEntryResponse.new instead')
  static OpenJournalEntryResponse create() => OpenJournalEntryResponse._();
  static $pb.GeneratedMessage $_createMessage() => OpenJournalEntryResponse._();
  @$core.override
  OpenJournalEntryResponse createEmptyInstance() =>
      OpenJournalEntryResponse._();
  @$core.pragma('dart2js:noInline')
  static OpenJournalEntryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpenJournalEntryResponse>(
          OpenJournalEntryResponse.$_createMessage);
  static OpenJournalEntryResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get plaintext => $_getN(0);
  @$pb.TagNumber(1)
  set plaintext($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaintext() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaintext() => $_clearField(1);
}

/// Derives the page key of a database file from the device data key. It is the one key a response carries, because
/// SQLite3MultipleCiphers must hold it (ADR-0057).
class DatabaseKeyRequest extends $pb.GeneratedMessage {
  factory DatabaseKeyRequest({
    $core.int? key,
    $core.List<$core.int>? fileId,
  }) {
    final result = DatabaseKeyRequest._();
    if (key != null) result.key = key;
    if (fileId != null) result.fileId = fileId;
    return result;
  }

  DatabaseKeyRequest._();

  factory DatabaseKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DatabaseKeyRequest()..mergeFromBuffer(data, registry);
  factory DatabaseKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DatabaseKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DatabaseKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DatabaseKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'fileId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DatabaseKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DatabaseKeyRequest copyWith(void Function(DatabaseKeyRequest) updates) =>
      super.copyWith((message) => updates(message as DatabaseKeyRequest))
          as DatabaseKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DatabaseKeyRequest() / DatabaseKeyRequest.new instead')
  static DatabaseKeyRequest create() => DatabaseKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => DatabaseKeyRequest._();
  @$core.override
  DatabaseKeyRequest createEmptyInstance() => DatabaseKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static DatabaseKeyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DatabaseKeyRequest>(
          DatabaseKeyRequest.$_createMessage);
  static DatabaseKeyRequest? _defaultInstance;

  /// The device data key.
  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  /// The 16-byte id of the database file.
  @$pb.TagNumber(2)
  $core.List<$core.int> get fileId => $_getN(1);
  @$pb.TagNumber(2)
  set fileId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFileId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileId() => $_clearField(2);
}

/// HKDF(DDK, "photolib/v1/local/db" ‖ file_id), 32 bytes.
class DatabaseKeyResponse extends $pb.GeneratedMessage {
  factory DatabaseKeyResponse({
    $core.List<$core.int>? pageKey,
  }) {
    final result = DatabaseKeyResponse._();
    if (pageKey != null) result.pageKey = pageKey;
    return result;
  }

  DatabaseKeyResponse._();

  factory DatabaseKeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DatabaseKeyResponse()..mergeFromBuffer(data, registry);
  factory DatabaseKeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DatabaseKeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DatabaseKeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DatabaseKeyResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'pageKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DatabaseKeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DatabaseKeyResponse copyWith(void Function(DatabaseKeyResponse) updates) =>
      super.copyWith((message) => updates(message as DatabaseKeyResponse))
          as DatabaseKeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use DatabaseKeyResponse() / DatabaseKeyResponse.new instead')
  static DatabaseKeyResponse create() => DatabaseKeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => DatabaseKeyResponse._();
  @$core.override
  DatabaseKeyResponse createEmptyInstance() => DatabaseKeyResponse._();
  @$core.pragma('dart2js:noInline')
  static DatabaseKeyResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DatabaseKeyResponse>(
          DatabaseKeyResponse.$_createMessage);
  static DatabaseKeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pageKey => $_getN(0);
  @$pb.TagNumber(1)
  set pageKey($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPageKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearPageKey() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
