// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/share.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'keys.pb.dart' as $0;
import 'share.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'share.pbenum.dart';

/// Asks for the public key of a seed in the keyring.
class PublicKeyRequest extends $pb.GeneratedMessage {
  factory PublicKeyRequest({
    $core.int? key,
    KeyPair? keyPair,
  }) {
    final result = PublicKeyRequest._();
    if (key != null) result.key = key;
    if (keyPair != null) result.keyPair = keyPair;
    return result;
  }

  PublicKeyRequest._();

  factory PublicKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PublicKeyRequest()..mergeFromBuffer(data, registry);
  factory PublicKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PublicKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PublicKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: PublicKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..aE<KeyPair>(2, _omitFieldNames ? '' : 'keyPair',
        enumValues: KeyPair.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicKeyRequest copyWith(void Function(PublicKeyRequest) updates) =>
      super.copyWith((message) => updates(message as PublicKeyRequest))
          as PublicKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PublicKeyRequest() / PublicKeyRequest.new instead')
  static PublicKeyRequest create() => PublicKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => PublicKeyRequest._();
  @$core.override
  PublicKeyRequest createEmptyInstance() => PublicKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static PublicKeyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PublicKeyRequest>(
          PublicKeyRequest.$_createMessage);
  static PublicKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  KeyPair get keyPair => $_getN(1);
  @$pb.TagNumber(2)
  set keyPair(KeyPair value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKeyPair() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyPair() => $_clearField(2);
}

/// A public key and its pk_id, SHA-256(public_key)[0..16).
class PublicKeyResponse extends $pb.GeneratedMessage {
  factory PublicKeyResponse({
    $core.List<$core.int>? publicKey,
    $core.List<$core.int>? keyId,
  }) {
    final result = PublicKeyResponse._();
    if (publicKey != null) result.publicKey = publicKey;
    if (keyId != null) result.keyId = keyId;
    return result;
  }

  PublicKeyResponse._();

  factory PublicKeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PublicKeyResponse()..mergeFromBuffer(data, registry);
  factory PublicKeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PublicKeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PublicKeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: PublicKeyResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'keyId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicKeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicKeyResponse copyWith(void Function(PublicKeyResponse) updates) =>
      super.copyWith((message) => updates(message as PublicKeyResponse))
          as PublicKeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PublicKeyResponse() / PublicKeyResponse.new instead')
  static PublicKeyResponse create() => PublicKeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => PublicKeyResponse._();
  @$core.override
  PublicKeyResponse createEmptyInstance() => PublicKeyResponse._();
  @$core.pragma('dart2js:noInline')
  static PublicKeyResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PublicKeyResponse>(
          PublicKeyResponse.$_createMessage);
  static PublicKeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get publicKey => $_getN(0);
  @$pb.TagNumber(1)
  set publicKey($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPublicKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearPublicKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get keyId => $_getN(1);
  @$pb.TagNumber(2)
  set keyId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKeyId() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyId() => $_clearField(2);
}

/// Sends a key to an X-Wing public key as a PLH.
class ShareKeyRequest extends $pb.GeneratedMessage {
  factory ShareKeyRequest({
    $core.int? key,
    $core.List<$core.int>? publicKey,
    $core.int? wrappedType,
    $0.WrapContext? context,
    $core.List<$core.int>? senderKeyId,
    $core.List<$core.int>? randomness,
  }) {
    final result = ShareKeyRequest._();
    if (key != null) result.key = key;
    if (publicKey != null) result.publicKey = publicKey;
    if (wrappedType != null) result.wrappedType = wrappedType;
    if (context != null) result.context = context;
    if (senderKeyId != null) result.senderKeyId = senderKeyId;
    if (randomness != null) result.randomness = randomness;
    return result;
  }

  ShareKeyRequest._();

  factory ShareKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ShareKeyRequest()..mergeFromBuffer(data, registry);
  factory ShareKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ShareKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ShareKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ShareKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..aI(3, _omitFieldNames ? '' : 'wrappedType',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<$0.WrapContext>(4, _omitFieldNames ? '' : 'context',
        subBuilder: $0.WrapContext.$_createMessage)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'senderKeyId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'randomness', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ShareKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ShareKeyRequest copyWith(void Function(ShareKeyRequest) updates) =>
      super.copyWith((message) => updates(message as ShareKeyRequest))
          as ShareKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ShareKeyRequest() / ShareKeyRequest.new instead')
  static ShareKeyRequest create() => ShareKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => ShareKeyRequest._();
  @$core.override
  ShareKeyRequest createEmptyInstance() => ShareKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static ShareKeyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ShareKeyRequest>(
          ShareKeyRequest.$_createMessage);
  static ShareKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  /// The recipient's X-Wing public key, 1216 bytes.
  @$pb.TagNumber(2)
  $core.List<$core.int> get publicKey => $_getN(1);
  @$pb.TagNumber(2)
  set publicKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPublicKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPublicKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get wrappedType => $_getIZ(2);
  @$pb.TagNumber(3)
  set wrappedType($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWrappedType() => $_has(2);
  @$pb.TagNumber(3)
  void clearWrappedType() => $_clearField(3);

  @$pb.TagNumber(4)
  $0.WrapContext get context => $_getN(3);
  @$pb.TagNumber(4)
  set context($0.WrapContext value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasContext() => $_has(3);
  @$pb.TagNumber(4)
  void clearContext() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.WrapContext ensureContext() => $_ensure(3);

  /// The pk_id of the sender's identity signing key; empty for anonymous senders.
  @$pb.TagNumber(5)
  $core.List<$core.int> get senderKeyId => $_getN(4);
  @$pb.TagNumber(5)
  set senderKeyId($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSenderKeyId() => $_has(4);
  @$pb.TagNumber(5)
  void clearSenderKeyId() => $_clearField(5);

  /// 64 random bytes.
  @$pb.TagNumber(6)
  $core.List<$core.int> get randomness => $_getN(5);
  @$pb.TagNumber(6)
  set randomness($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRandomness() => $_has(5);
  @$pb.TagNumber(6)
  void clearRandomness() => $_clearField(6);
}

/// A PLH, 1224 bytes.
class ShareKeyResponse extends $pb.GeneratedMessage {
  factory ShareKeyResponse({
    $core.List<$core.int>? wrap,
  }) {
    final result = ShareKeyResponse._();
    if (wrap != null) result.wrap = wrap;
    return result;
  }

  ShareKeyResponse._();

  factory ShareKeyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ShareKeyResponse()..mergeFromBuffer(data, registry);
  factory ShareKeyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ShareKeyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ShareKeyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ShareKeyResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'wrap', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ShareKeyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ShareKeyResponse copyWith(void Function(ShareKeyResponse) updates) =>
      super.copyWith((message) => updates(message as ShareKeyResponse))
          as ShareKeyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ShareKeyResponse() / ShareKeyResponse.new instead')
  static ShareKeyResponse create() => ShareKeyResponse._();
  static $pb.GeneratedMessage $_createMessage() => ShareKeyResponse._();
  @$core.override
  ShareKeyResponse createEmptyInstance() => ShareKeyResponse._();
  @$core.pragma('dart2js:noInline')
  static ShareKeyResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ShareKeyResponse>(
          ShareKeyResponse.$_createMessage);
  static ShareKeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get wrap => $_getN(0);
  @$pb.TagNumber(1)
  set wrap($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWrap() => $_has(0);
  @$pb.TagNumber(1)
  void clearWrap() => $_clearField(1);
}

/// Opens a PLH into the keyring with the recipient's X-Wing seed, if a verified log entry names it.
class AcceptKeyRequest extends $pb.GeneratedMessage {
  factory AcceptKeyRequest({
    $core.int? key,
    $core.int? wrappedType,
    $0.WrapContext? context,
    $core.List<$core.int>? wrap,
    $core.List<$core.int>? signedSha256,
  }) {
    final result = AcceptKeyRequest._();
    if (key != null) result.key = key;
    if (wrappedType != null) result.wrappedType = wrappedType;
    if (context != null) result.context = context;
    if (wrap != null) result.wrap = wrap;
    if (signedSha256 != null) result.signedSha256 = signedSha256;
    return result;
  }

  AcceptKeyRequest._();

  factory AcceptKeyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AcceptKeyRequest()..mergeFromBuffer(data, registry);
  factory AcceptKeyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AcceptKeyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AcceptKeyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: AcceptKeyRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'wrappedType',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<$0.WrapContext>(3, _omitFieldNames ? '' : 'context',
        subBuilder: $0.WrapContext.$_createMessage)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'wrap', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'signedSha256', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceptKeyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceptKeyRequest copyWith(void Function(AcceptKeyRequest) updates) =>
      super.copyWith((message) => updates(message as AcceptKeyRequest))
          as AcceptKeyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AcceptKeyRequest() / AcceptKeyRequest.new instead')
  static AcceptKeyRequest create() => AcceptKeyRequest._();
  static $pb.GeneratedMessage $_createMessage() => AcceptKeyRequest._();
  @$core.override
  AcceptKeyRequest createEmptyInstance() => AcceptKeyRequest._();
  @$core.pragma('dart2js:noInline')
  static AcceptKeyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AcceptKeyRequest>(
          AcceptKeyRequest.$_createMessage);
  static AcceptKeyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get wrappedType => $_getIZ(1);
  @$pb.TagNumber(2)
  set wrappedType($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWrappedType() => $_has(1);
  @$pb.TagNumber(2)
  void clearWrappedType() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.WrapContext get context => $_getN(2);
  @$pb.TagNumber(3)
  set context($0.WrapContext value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasContext() => $_has(2);
  @$pb.TagNumber(3)
  void clearContext() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.WrapContext ensureContext() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get wrap => $_getN(3);
  @$pb.TagNumber(4)
  set wrap($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasWrap() => $_has(3);
  @$pb.TagNumber(4)
  void clearWrap() => $_clearField(4);

  /// The SHA-256 that the verified log entry delivering the wrap names for this recipient (a SignedWrap).
  @$pb.TagNumber(5)
  $core.List<$core.int> get signedSha256 => $_getN(4);
  @$pb.TagNumber(5)
  set signedSha256($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSignedSha256() => $_has(4);
  @$pb.TagNumber(5)
  void clearSignedSha256() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
