// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/logs.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Signs a PLS log entry or statement with an Ed25519 seed in the keyring.
class SignEntryRequest extends $pb.GeneratedMessage {
  factory SignEntryRequest({
    $core.int? key,
    $core.int? logType,
    $core.int? bodyType,
    $core.List<$core.int>? logId,
    $fixnum.Int64? seq,
    $core.List<$core.int>? prevHash,
    $fixnum.Int64? timeMs,
    $core.List<$core.int>? body,
  }) {
    final result = SignEntryRequest._();
    if (key != null) result.key = key;
    if (logType != null) result.logType = logType;
    if (bodyType != null) result.bodyType = bodyType;
    if (logId != null) result.logId = logId;
    if (seq != null) result.seq = seq;
    if (prevHash != null) result.prevHash = prevHash;
    if (timeMs != null) result.timeMs = timeMs;
    if (body != null) result.body = body;
    return result;
  }

  SignEntryRequest._();

  factory SignEntryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignEntryRequest()..mergeFromBuffer(data, registry);
  factory SignEntryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignEntryRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignEntryRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: SignEntryRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'logType', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'bodyType', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'logId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'prevHash', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'timeMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        8, _omitFieldNames ? '' : 'body', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignEntryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignEntryRequest copyWith(void Function(SignEntryRequest) updates) =>
      super.copyWith((message) => updates(message as SignEntryRequest))
          as SignEntryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SignEntryRequest() / SignEntryRequest.new instead')
  static SignEntryRequest create() => SignEntryRequest._();
  static $pb.GeneratedMessage $_createMessage() => SignEntryRequest._();
  @$core.override
  SignEntryRequest createEmptyInstance() => SignEntryRequest._();
  @$core.pragma('dart2js:noInline')
  static SignEntryRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SignEntryRequest>(
          SignEntryRequest.$_createMessage);
  static SignEntryRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  /// 1 identity, 2 album membership, 3 library membership, 4 statement.
  @$pb.TagNumber(2)
  $core.int get logType => $_getIZ(1);
  @$pb.TagNumber(2)
  set logType($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLogType() => $_has(1);
  @$pb.TagNumber(2)
  void clearLogType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get bodyType => $_getIZ(2);
  @$pb.TagNumber(3)
  set bodyType($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBodyType() => $_has(2);
  @$pb.TagNumber(3)
  void clearBodyType() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get logId => $_getN(3);
  @$pb.TagNumber(4)
  set logId($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLogId() => $_has(3);
  @$pb.TagNumber(4)
  void clearLogId() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get seq => $_getI64(4);
  @$pb.TagNumber(5)
  set seq($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSeq() => $_has(4);
  @$pb.TagNumber(5)
  void clearSeq() => $_clearField(5);

  /// The entry_hash of entry seq - 1; empty for entry 0 and statements.
  @$pb.TagNumber(6)
  $core.List<$core.int> get prevHash => $_getN(5);
  @$pb.TagNumber(6)
  set prevHash($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPrevHash() => $_has(5);
  @$pb.TagNumber(6)
  void clearPrevHash() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get timeMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timeMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTimeMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimeMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get body => $_getN(7);
  @$pb.TagNumber(8)
  set body($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(8)
  $core.bool hasBody() => $_has(7);
  @$pb.TagNumber(8)
  void clearBody() => $_clearField(8);
}

/// A signed PLS entry.
class SignEntryResponse extends $pb.GeneratedMessage {
  factory SignEntryResponse({
    $core.List<$core.int>? entry,
  }) {
    final result = SignEntryResponse._();
    if (entry != null) result.entry = entry;
    return result;
  }

  SignEntryResponse._();

  factory SignEntryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignEntryResponse()..mergeFromBuffer(data, registry);
  factory SignEntryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignEntryResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignEntryResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: SignEntryResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'entry', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignEntryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignEntryResponse copyWith(void Function(SignEntryResponse) updates) =>
      super.copyWith((message) => updates(message as SignEntryResponse))
          as SignEntryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SignEntryResponse() / SignEntryResponse.new instead')
  static SignEntryResponse create() => SignEntryResponse._();
  static $pb.GeneratedMessage $_createMessage() => SignEntryResponse._();
  @$core.override
  SignEntryResponse createEmptyInstance() => SignEntryResponse._();
  @$core.pragma('dart2js:noInline')
  static SignEntryResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SignEntryResponse>(
          SignEntryResponse.$_createMessage);
  static SignEntryResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get entry => $_getN(0);
  @$pb.TagNumber(1)
  set entry($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEntry() => $_has(0);
  @$pb.TagNumber(1)
  void clearEntry() => $_clearField(1);
}

/// A position in a log: the seq and entry_hash of an entry.
class Checkpoint extends $pb.GeneratedMessage {
  factory Checkpoint({
    $fixnum.Int64? seq,
    $core.List<$core.int>? entryHash,
  }) {
    final result = Checkpoint._();
    if (seq != null) result.seq = seq;
    if (entryHash != null) result.entryHash = entryHash;
    return result;
  }

  Checkpoint._();

  factory Checkpoint.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Checkpoint()..mergeFromBuffer(data, registry);
  factory Checkpoint.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Checkpoint()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Checkpoint',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Checkpoint.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'entryHash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Checkpoint clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Checkpoint copyWith(void Function(Checkpoint) updates) =>
      super.copyWith((message) => updates(message as Checkpoint)) as Checkpoint;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Checkpoint() / Checkpoint.new instead')
  static Checkpoint create() => Checkpoint._();
  static $pb.GeneratedMessage $_createMessage() => Checkpoint._();
  @$core.override
  Checkpoint createEmptyInstance() => Checkpoint._();
  @$core.pragma('dart2js:noInline')
  static Checkpoint getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Checkpoint>(Checkpoint.$_createMessage);
  static Checkpoint? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get entryHash => $_getN(1);
  @$pb.TagNumber(2)
  set entryHash($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEntryHash() => $_has(1);
  @$pb.TagNumber(2)
  void clearEntryHash() => $_clearField(2);
}

/// A wrap that a verified entry names by its SHA-256: a PLH to a member or device, or the back-link PLW of a new epoch.
class SignedWrap extends $pb.GeneratedMessage {
  factory SignedWrap({
    $fixnum.Int64? seq,
    $core.List<$core.int>? recipientId,
    $core.List<$core.int>? sha256,
  }) {
    final result = SignedWrap._();
    if (seq != null) result.seq = seq;
    if (recipientId != null) result.recipientId = recipientId;
    if (sha256 != null) result.sha256 = sha256;
    return result;
  }

  SignedWrap._();

  factory SignedWrap.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignedWrap()..mergeFromBuffer(data, registry);
  factory SignedWrap.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SignedWrap()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignedWrap',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: SignedWrap.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'recipientId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'sha256', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignedWrap clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignedWrap copyWith(void Function(SignedWrap) updates) =>
      super.copyWith((message) => updates(message as SignedWrap)) as SignedWrap;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SignedWrap() / SignedWrap.new instead')
  static SignedWrap create() => SignedWrap._();
  static $pb.GeneratedMessage $_createMessage() => SignedWrap._();
  @$core.override
  SignedWrap createEmptyInstance() => SignedWrap._();
  @$core.pragma('dart2js:noInline')
  static SignedWrap getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SignedWrap>(SignedWrap.$_createMessage);
  static SignedWrap? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  /// The member or device; empty for a back-link.
  @$pb.TagNumber(2)
  $core.List<$core.int> get recipientId => $_getN(1);
  @$pb.TagNumber(2)
  set recipientId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRecipientId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecipientId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get sha256 => $_getN(2);
  @$pb.TagNumber(3)
  set sha256($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSha256() => $_has(2);
  @$pb.TagNumber(3)
  void clearSha256() => $_clearField(3);
}

/// Replays a user's identity log from entry 0; the view must contain the reader's checkpoint, if it has one.
class VerifyIdentityLogRequest extends $pb.GeneratedMessage {
  factory VerifyIdentityLogRequest({
    $core.List<$core.int>? userId,
    $core.Iterable<$core.List<$core.int>>? entries,
    Checkpoint? checkpoint,
  }) {
    final result = VerifyIdentityLogRequest._();
    if (userId != null) result.userId = userId;
    if (entries != null) result.entries.addAll(entries);
    if (checkpoint != null) result.checkpoint = checkpoint;
    return result;
  }

  VerifyIdentityLogRequest._();

  factory VerifyIdentityLogRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyIdentityLogRequest()..mergeFromBuffer(data, registry);
  factory VerifyIdentityLogRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyIdentityLogRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VerifyIdentityLogRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: VerifyIdentityLogRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PY)
    ..aOM<Checkpoint>(3, _omitFieldNames ? '' : 'checkpoint',
        subBuilder: Checkpoint.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyIdentityLogRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyIdentityLogRequest copyWith(
          void Function(VerifyIdentityLogRequest) updates) =>
      super.copyWith((message) => updates(message as VerifyIdentityLogRequest))
          as VerifyIdentityLogRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use VerifyIdentityLogRequest() / VerifyIdentityLogRequest.new instead')
  static VerifyIdentityLogRequest create() => VerifyIdentityLogRequest._();
  static $pb.GeneratedMessage $_createMessage() => VerifyIdentityLogRequest._();
  @$core.override
  VerifyIdentityLogRequest createEmptyInstance() =>
      VerifyIdentityLogRequest._();
  @$core.pragma('dart2js:noInline')
  static VerifyIdentityLogRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VerifyIdentityLogRequest>(
          VerifyIdentityLogRequest.$_createMessage);
  static VerifyIdentityLogRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.List<$core.int>> get entries => $_getList(1);

  @$pb.TagNumber(3)
  Checkpoint get checkpoint => $_getN(2);
  @$pb.TagNumber(3)
  set checkpoint(Checkpoint value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCheckpoint() => $_has(2);
  @$pb.TagNumber(3)
  void clearCheckpoint() => $_clearField(3);
  @$pb.TagNumber(3)
  Checkpoint ensureCheckpoint() => $_ensure(2);
}

/// A device of an identity log.
class Device extends $pb.GeneratedMessage {
  factory Device({
    $core.List<$core.int>? deviceId,
    $core.List<$core.int>? publicKey,
  }) {
    final result = Device._();
    if (deviceId != null) result.deviceId = deviceId;
    if (publicKey != null) result.publicKey = publicKey;
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
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Device.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
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

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceId => $_getN(0);
  @$pb.TagNumber(1)
  set deviceId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  /// Its X-Wing public key.
  @$pb.TagNumber(2)
  $core.List<$core.int> get publicKey => $_getN(1);
  @$pb.TagNumber(2)
  set publicKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPublicKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPublicKey() => $_clearField(2);
}

/// The verified state of an identity log.
class VerifyIdentityLogResponse extends $pb.GeneratedMessage {
  factory VerifyIdentityLogResponse({
    $core.Iterable<$core.List<$core.int>>? signingKeys,
    $core.List<$core.int>? encryptionKey,
    $core.Iterable<Device>? devices,
    $core.int? amkGeneration,
    Checkpoint? head,
    $core.Iterable<SignedWrap>? wraps,
  }) {
    final result = VerifyIdentityLogResponse._();
    if (signingKeys != null) result.signingKeys.addAll(signingKeys);
    if (encryptionKey != null) result.encryptionKey = encryptionKey;
    if (devices != null) result.devices.addAll(devices);
    if (amkGeneration != null) result.amkGeneration = amkGeneration;
    if (head != null) result.head = head;
    if (wraps != null) result.wraps.addAll(wraps);
    return result;
  }

  VerifyIdentityLogResponse._();

  factory VerifyIdentityLogResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyIdentityLogResponse()..mergeFromBuffer(data, registry);
  factory VerifyIdentityLogResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyIdentityLogResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VerifyIdentityLogResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: VerifyIdentityLogResponse.$_createMessage)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'signingKeys', $pb.PbFieldType.PY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'encryptionKey', $pb.PbFieldType.OY)
    ..pPM<Device>(3, _omitFieldNames ? '' : 'devices',
        subBuilder: Device.$_createMessage)
    ..aI(4, _omitFieldNames ? '' : 'amkGeneration',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<Checkpoint>(5, _omitFieldNames ? '' : 'head',
        subBuilder: Checkpoint.$_createMessage)
    ..pPM<SignedWrap>(6, _omitFieldNames ? '' : 'wraps',
        subBuilder: SignedWrap.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyIdentityLogResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyIdentityLogResponse copyWith(
          void Function(VerifyIdentityLogResponse) updates) =>
      super.copyWith((message) => updates(message as VerifyIdentityLogResponse))
          as VerifyIdentityLogResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use VerifyIdentityLogResponse() / VerifyIdentityLogResponse.new instead')
  static VerifyIdentityLogResponse create() => VerifyIdentityLogResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      VerifyIdentityLogResponse._();
  @$core.override
  VerifyIdentityLogResponse createEmptyInstance() =>
      VerifyIdentityLogResponse._();
  @$core.pragma('dart2js:noInline')
  static VerifyIdentityLogResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VerifyIdentityLogResponse>(
          VerifyIdentityLogResponse.$_createMessage);
  static VerifyIdentityLogResponse? _defaultInstance;

  /// Ed25519 public keys, oldest first; the last one signs.
  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get signingKeys => $_getList(0);

  /// The X-Wing public key.
  @$pb.TagNumber(2)
  $core.List<$core.int> get encryptionKey => $_getN(1);
  @$pb.TagNumber(2)
  set encryptionKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEncryptionKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearEncryptionKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<Device> get devices => $_getList(2);

  @$pb.TagNumber(4)
  $core.int get amkGeneration => $_getIZ(3);
  @$pb.TagNumber(4)
  set amkGeneration($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAmkGeneration() => $_has(3);
  @$pb.TagNumber(4)
  void clearAmkGeneration() => $_clearField(4);

  /// The last entry: the reader's next checkpoint.
  @$pb.TagNumber(5)
  Checkpoint get head => $_getN(4);
  @$pb.TagNumber(5)
  set head(Checkpoint value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasHead() => $_has(4);
  @$pb.TagNumber(5)
  void clearHead() => $_clearField(5);
  @$pb.TagNumber(5)
  Checkpoint ensureHead() => $_ensure(4);

  @$pb.TagNumber(6)
  $pb.PbList<SignedWrap> get wraps => $_getList(5);
}

/// A user's signing keys from a verified identity log, oldest first.
class Identity extends $pb.GeneratedMessage {
  factory Identity({
    $core.List<$core.int>? userId,
    $core.Iterable<$core.List<$core.int>>? signingKeys,
  }) {
    final result = Identity._();
    if (userId != null) result.userId = userId;
    if (signingKeys != null) result.signingKeys.addAll(signingKeys);
    return result;
  }

  Identity._();

  factory Identity.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Identity()..mergeFromBuffer(data, registry);
  factory Identity.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Identity()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Identity',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Identity.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'signingKeys', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Identity clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Identity copyWith(void Function(Identity) updates) =>
      super.copyWith((message) => updates(message as Identity)) as Identity;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Identity() / Identity.new instead')
  static Identity create() => Identity._();
  static $pb.GeneratedMessage $_createMessage() => Identity._();
  @$core.override
  Identity createEmptyInstance() => Identity._();
  @$core.pragma('dart2js:noInline')
  static Identity getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Identity>(Identity.$_createMessage);
  static Identity? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.List<$core.int>> get signingKeys => $_getList(1);
}

/// Replays an album or library membership log from entry 0, then checks upload statements against it.
class VerifyMembershipLogRequest extends $pb.GeneratedMessage {
  factory VerifyMembershipLogRequest({
    $core.int? logType,
    $core.List<$core.int>? logId,
    $core.Iterable<$core.List<$core.int>>? entries,
    Checkpoint? checkpoint,
    $core.Iterable<Identity>? identities,
    $core.Iterable<$core.List<$core.int>>? statements,
  }) {
    final result = VerifyMembershipLogRequest._();
    if (logType != null) result.logType = logType;
    if (logId != null) result.logId = logId;
    if (entries != null) result.entries.addAll(entries);
    if (checkpoint != null) result.checkpoint = checkpoint;
    if (identities != null) result.identities.addAll(identities);
    if (statements != null) result.statements.addAll(statements);
    return result;
  }

  VerifyMembershipLogRequest._();

  factory VerifyMembershipLogRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyMembershipLogRequest()..mergeFromBuffer(data, registry);
  factory VerifyMembershipLogRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyMembershipLogRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VerifyMembershipLogRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: VerifyMembershipLogRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'logType', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'logId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PY)
    ..aOM<Checkpoint>(4, _omitFieldNames ? '' : 'checkpoint',
        subBuilder: Checkpoint.$_createMessage)
    ..pPM<Identity>(5, _omitFieldNames ? '' : 'identities',
        subBuilder: Identity.$_createMessage)
    ..p<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'statements', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyMembershipLogRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyMembershipLogRequest copyWith(
          void Function(VerifyMembershipLogRequest) updates) =>
      super.copyWith(
              (message) => updates(message as VerifyMembershipLogRequest))
          as VerifyMembershipLogRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use VerifyMembershipLogRequest() / VerifyMembershipLogRequest.new instead')
  static VerifyMembershipLogRequest create() => VerifyMembershipLogRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      VerifyMembershipLogRequest._();
  @$core.override
  VerifyMembershipLogRequest createEmptyInstance() =>
      VerifyMembershipLogRequest._();
  @$core.pragma('dart2js:noInline')
  static VerifyMembershipLogRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VerifyMembershipLogRequest>(
          VerifyMembershipLogRequest.$_createMessage);
  static VerifyMembershipLogRequest? _defaultInstance;

  /// 2 album, 3 library.
  @$pb.TagNumber(1)
  $core.int get logType => $_getIZ(0);
  @$pb.TagNumber(1)
  set logType($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLogType() => $_has(0);
  @$pb.TagNumber(1)
  void clearLogType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get logId => $_getN(1);
  @$pb.TagNumber(2)
  set logId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLogId() => $_has(1);
  @$pb.TagNumber(2)
  void clearLogId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.List<$core.int>> get entries => $_getList(2);

  @$pb.TagNumber(4)
  Checkpoint get checkpoint => $_getN(3);
  @$pb.TagNumber(4)
  set checkpoint(Checkpoint value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCheckpoint() => $_has(3);
  @$pb.TagNumber(4)
  void clearCheckpoint() => $_clearField(4);
  @$pb.TagNumber(4)
  Checkpoint ensureCheckpoint() => $_ensure(3);

  /// Every member's, from VerifyIdentityLog.
  @$pb.TagNumber(5)
  $pb.PbList<Identity> get identities => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.List<$core.int>> get statements => $_getList(5);
}

/// A member: role 1 viewer, 2 contributor, 3 admin, and the pk_id of its pinned signing key.
class Member extends $pb.GeneratedMessage {
  factory Member({
    $core.List<$core.int>? userId,
    $core.int? role,
    $core.List<$core.int>? signingKeyId,
  }) {
    final result = Member._();
    if (userId != null) result.userId = userId;
    if (role != null) result.role = role;
    if (signingKeyId != null) result.signingKeyId = signingKeyId;
    return result;
  }

  Member._();

  factory Member.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Member()..mergeFromBuffer(data, registry);
  factory Member.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Member()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Member',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Member.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'role', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'signingKeyId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Member clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Member copyWith(void Function(Member) updates) =>
      super.copyWith((message) => updates(message as Member)) as Member;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Member() / Member.new instead')
  static Member create() => Member._();
  static $pb.GeneratedMessage $_createMessage() => Member._();
  @$core.override
  Member createEmptyInstance() => Member._();
  @$core.pragma('dart2js:noInline')
  static Member getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Member>(Member.$_createMessage);
  static Member? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get role => $_getIZ(1);
  @$pb.TagNumber(2)
  set role($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearRole() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get signingKeyId => $_getN(2);
  @$pb.TagNumber(3)
  set signingKeyId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSigningKeyId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSigningKeyId() => $_clearField(3);
}

/// A link, with its drop key's X-Wing public key once set.
class Link extends $pb.GeneratedMessage {
  factory Link({
    $core.List<$core.int>? linkId,
    $core.List<$core.int>? dropKey,
  }) {
    final result = Link._();
    if (linkId != null) result.linkId = linkId;
    if (dropKey != null) result.dropKey = dropKey;
    return result;
  }

  Link._();

  factory Link.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Link()..mergeFromBuffer(data, registry);
  factory Link.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Link()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Link',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Link.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'linkId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'dropKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Link clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Link copyWith(void Function(Link) updates) =>
      super.copyWith((message) => updates(message as Link)) as Link;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Link() / Link.new instead')
  static Link create() => Link._();
  static $pb.GeneratedMessage $_createMessage() => Link._();
  @$core.override
  Link createEmptyInstance() => Link._();
  @$core.pragma('dart2js:noInline')
  static Link getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Link>(Link.$_createMessage);
  static Link? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get linkId => $_getN(0);
  @$pb.TagNumber(1)
  set linkId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLinkId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLinkId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get dropKey => $_getN(1);
  @$pb.TagNumber(2)
  set dropKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDropKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearDropKey() => $_clearField(2);
}

/// What an upload statement says, or why it is rejected: an error code of the specification.
class Upload extends $pb.GeneratedMessage {
  factory Upload({
    $core.List<$core.int>? fileId,
    $core.List<$core.int>? uploader,
    $core.List<$core.int>? objectsHash,
    $core.String? rejected,
  }) {
    final result = Upload._();
    if (fileId != null) result.fileId = fileId;
    if (uploader != null) result.uploader = uploader;
    if (objectsHash != null) result.objectsHash = objectsHash;
    if (rejected != null) result.rejected = rejected;
    return result;
  }

  Upload._();

  factory Upload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Upload()..mergeFromBuffer(data, registry);
  factory Upload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Upload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Upload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Upload.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'fileId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'uploader', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'objectsHash', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'rejected')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Upload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Upload copyWith(void Function(Upload) updates) =>
      super.copyWith((message) => updates(message as Upload)) as Upload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Upload() / Upload.new instead')
  static Upload create() => Upload._();
  static $pb.GeneratedMessage $_createMessage() => Upload._();
  @$core.override
  Upload createEmptyInstance() => Upload._();
  @$core.pragma('dart2js:noInline')
  static Upload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Upload>(Upload.$_createMessage);
  static Upload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get fileId => $_getN(0);
  @$pb.TagNumber(1)
  set fileId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get uploader => $_getN(1);
  @$pb.TagNumber(2)
  set uploader($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUploader() => $_has(1);
  @$pb.TagNumber(2)
  void clearUploader() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get objectsHash => $_getN(2);
  @$pb.TagNumber(3)
  set objectsHash($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasObjectsHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearObjectsHash() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get rejected => $_getSZ(3);
  @$pb.TagNumber(4)
  set rejected($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRejected() => $_has(3);
  @$pb.TagNumber(4)
  void clearRejected() => $_clearField(4);
}

/// The verified state of a membership log; members and links ordered by id, uploads as the statements.
class VerifyMembershipLogResponse extends $pb.GeneratedMessage {
  factory VerifyMembershipLogResponse({
    $core.List<$core.int>? owner,
    $core.Iterable<Member>? members,
    $core.int? epoch,
    $core.bool? rotationDue,
    $core.Iterable<Link>? links,
    Checkpoint? head,
    $core.Iterable<SignedWrap>? wraps,
    $core.Iterable<Upload>? uploads,
  }) {
    final result = VerifyMembershipLogResponse._();
    if (owner != null) result.owner = owner;
    if (members != null) result.members.addAll(members);
    if (epoch != null) result.epoch = epoch;
    if (rotationDue != null) result.rotationDue = rotationDue;
    if (links != null) result.links.addAll(links);
    if (head != null) result.head = head;
    if (wraps != null) result.wraps.addAll(wraps);
    if (uploads != null) result.uploads.addAll(uploads);
    return result;
  }

  VerifyMembershipLogResponse._();

  factory VerifyMembershipLogResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyMembershipLogResponse()..mergeFromBuffer(data, registry);
  factory VerifyMembershipLogResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VerifyMembershipLogResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VerifyMembershipLogResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: VerifyMembershipLogResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'owner', $pb.PbFieldType.OY)
    ..pPM<Member>(2, _omitFieldNames ? '' : 'members',
        subBuilder: Member.$_createMessage)
    ..aI(3, _omitFieldNames ? '' : 'epoch', fieldType: $pb.PbFieldType.OU3)
    ..aOB(4, _omitFieldNames ? '' : 'rotationDue')
    ..pPM<Link>(5, _omitFieldNames ? '' : 'links',
        subBuilder: Link.$_createMessage)
    ..aOM<Checkpoint>(6, _omitFieldNames ? '' : 'head',
        subBuilder: Checkpoint.$_createMessage)
    ..pPM<SignedWrap>(7, _omitFieldNames ? '' : 'wraps',
        subBuilder: SignedWrap.$_createMessage)
    ..pPM<Upload>(8, _omitFieldNames ? '' : 'uploads',
        subBuilder: Upload.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyMembershipLogResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VerifyMembershipLogResponse copyWith(
          void Function(VerifyMembershipLogResponse) updates) =>
      super.copyWith(
              (message) => updates(message as VerifyMembershipLogResponse))
          as VerifyMembershipLogResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use VerifyMembershipLogResponse() / VerifyMembershipLogResponse.new instead')
  static VerifyMembershipLogResponse create() =>
      VerifyMembershipLogResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      VerifyMembershipLogResponse._();
  @$core.override
  VerifyMembershipLogResponse createEmptyInstance() =>
      VerifyMembershipLogResponse._();
  @$core.pragma('dart2js:noInline')
  static VerifyMembershipLogResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VerifyMembershipLogResponse>(
          VerifyMembershipLogResponse.$_createMessage);
  static VerifyMembershipLogResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get owner => $_getN(0);
  @$pb.TagNumber(1)
  set owner($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOwner() => $_has(0);
  @$pb.TagNumber(1)
  void clearOwner() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<Member> get members => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get epoch => $_getIZ(2);
  @$pb.TagNumber(3)
  set epoch($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEpoch() => $_has(2);
  @$pb.TagNumber(3)
  void clearEpoch() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get rotationDue => $_getBF(3);
  @$pb.TagNumber(4)
  set rotationDue($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRotationDue() => $_has(3);
  @$pb.TagNumber(4)
  void clearRotationDue() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<Link> get links => $_getList(4);

  @$pb.TagNumber(6)
  Checkpoint get head => $_getN(5);
  @$pb.TagNumber(6)
  set head(Checkpoint value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasHead() => $_has(5);
  @$pb.TagNumber(6)
  void clearHead() => $_clearField(6);
  @$pb.TagNumber(6)
  Checkpoint ensureHead() => $_ensure(5);

  @$pb.TagNumber(7)
  $pb.PbList<SignedWrap> get wraps => $_getList(6);

  @$pb.TagNumber(8)
  $pb.PbList<Upload> get uploads => $_getList(7);
}

/// The safety number two users compare out of band.
class SafetyNumberRequest extends $pb.GeneratedMessage {
  factory SafetyNumberRequest({
    $core.List<$core.int>? userA,
    $core.List<$core.int>? signingKeyA,
    $core.List<$core.int>? userB,
    $core.List<$core.int>? signingKeyB,
  }) {
    final result = SafetyNumberRequest._();
    if (userA != null) result.userA = userA;
    if (signingKeyA != null) result.signingKeyA = signingKeyA;
    if (userB != null) result.userB = userB;
    if (signingKeyB != null) result.signingKeyB = signingKeyB;
    return result;
  }

  SafetyNumberRequest._();

  factory SafetyNumberRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SafetyNumberRequest()..mergeFromBuffer(data, registry);
  factory SafetyNumberRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SafetyNumberRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SafetyNumberRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: SafetyNumberRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'userA', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'signingKeyA', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'userB', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'signingKeyB', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SafetyNumberRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SafetyNumberRequest copyWith(void Function(SafetyNumberRequest) updates) =>
      super.copyWith((message) => updates(message as SafetyNumberRequest))
          as SafetyNumberRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use SafetyNumberRequest() / SafetyNumberRequest.new instead')
  static SafetyNumberRequest create() => SafetyNumberRequest._();
  static $pb.GeneratedMessage $_createMessage() => SafetyNumberRequest._();
  @$core.override
  SafetyNumberRequest createEmptyInstance() => SafetyNumberRequest._();
  @$core.pragma('dart2js:noInline')
  static SafetyNumberRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SafetyNumberRequest>(
          SafetyNumberRequest.$_createMessage);
  static SafetyNumberRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userA => $_getN(0);
  @$pb.TagNumber(1)
  set userA($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserA() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserA() => $_clearField(1);

  /// User A's Ed25519 signing public key.
  @$pb.TagNumber(2)
  $core.List<$core.int> get signingKeyA => $_getN(1);
  @$pb.TagNumber(2)
  set signingKeyA($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSigningKeyA() => $_has(1);
  @$pb.TagNumber(2)
  void clearSigningKeyA() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get userB => $_getN(2);
  @$pb.TagNumber(3)
  set userB($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUserB() => $_has(2);
  @$pb.TagNumber(3)
  void clearUserB() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get signingKeyB => $_getN(3);
  @$pb.TagNumber(4)
  set signingKeyB($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSigningKeyB() => $_has(3);
  @$pb.TagNumber(4)
  void clearSigningKeyB() => $_clearField(4);
}

/// The epoch code members compare: of a membership log at its head.
class EpochCodeRequest extends $pb.GeneratedMessage {
  factory EpochCodeRequest({
    $core.List<$core.int>? logId,
    $core.List<$core.int>? head,
  }) {
    final result = EpochCodeRequest._();
    if (logId != null) result.logId = logId;
    if (head != null) result.head = head;
    return result;
  }

  EpochCodeRequest._();

  factory EpochCodeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EpochCodeRequest()..mergeFromBuffer(data, registry);
  factory EpochCodeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EpochCodeRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EpochCodeRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: EpochCodeRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'logId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'head', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EpochCodeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EpochCodeRequest copyWith(void Function(EpochCodeRequest) updates) =>
      super.copyWith((message) => updates(message as EpochCodeRequest))
          as EpochCodeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EpochCodeRequest() / EpochCodeRequest.new instead')
  static EpochCodeRequest create() => EpochCodeRequest._();
  static $pb.GeneratedMessage $_createMessage() => EpochCodeRequest._();
  @$core.override
  EpochCodeRequest createEmptyInstance() => EpochCodeRequest._();
  @$core.pragma('dart2js:noInline')
  static EpochCodeRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EpochCodeRequest>(
          EpochCodeRequest.$_createMessage);
  static EpochCodeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get logId => $_getN(0);
  @$pb.TagNumber(1)
  set logId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLogId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLogId() => $_clearField(1);

  /// The head's entry_hash.
  @$pb.TagNumber(2)
  $core.List<$core.int> get head => $_getN(1);
  @$pb.TagNumber(2)
  set head($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHead() => $_has(1);
  @$pb.TagNumber(2)
  void clearHead() => $_clearField(2);
}

/// Groups of five digits separated by spaces.
class CodeResponse extends $pb.GeneratedMessage {
  factory CodeResponse({
    $core.String? code,
  }) {
    final result = CodeResponse._();
    if (code != null) result.code = code;
    return result;
  }

  CodeResponse._();

  factory CodeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CodeResponse()..mergeFromBuffer(data, registry);
  factory CodeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CodeResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CodeResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: CodeResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CodeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CodeResponse copyWith(void Function(CodeResponse) updates) =>
      super.copyWith((message) => updates(message as CodeResponse))
          as CodeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CodeResponse() / CodeResponse.new instead')
  static CodeResponse create() => CodeResponse._();
  static $pb.GeneratedMessage $_createMessage() => CodeResponse._();
  @$core.override
  CodeResponse createEmptyInstance() => CodeResponse._();
  @$core.pragma('dart2js:noInline')
  static CodeResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CodeResponse>(
          CodeResponse.$_createMessage);
  static CodeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
