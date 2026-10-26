// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/blob.proto.

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

/// Seals a PLB blob envelope, or a PLX manifest. Called as a stream, the plaintext may also follow in pieces: each step
/// returns the envelope bytes it completed, and finishing returns the rest.
class EncryptBlobRequest extends $pb.GeneratedMessage {
  factory EncryptBlobRequest({
    $core.int? key,
    $core.int? kind,
    $core.bool? manifest,
    $core.bool? padded,
    $core.List<$core.int>? salt,
    $core.List<$core.int>? plaintext,
  }) {
    final result = EncryptBlobRequest._();
    if (key != null) result.key = key;
    if (kind != null) result.kind = kind;
    if (manifest != null) result.manifest = manifest;
    if (padded != null) result.padded = padded;
    if (salt != null) result.salt = salt;
    if (plaintext != null) result.plaintext = plaintext;
    return result;
  }

  EncryptBlobRequest._();

  factory EncryptBlobRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncryptBlobRequest()..mergeFromBuffer(data, registry);
  factory EncryptBlobRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncryptBlobRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EncryptBlobRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: EncryptBlobRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'kind', fieldType: $pb.PbFieldType.OU3)
    ..aOB(3, _omitFieldNames ? '' : 'manifest')
    ..aOB(4, _omitFieldNames ? '' : 'padded')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'salt', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'plaintext', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncryptBlobRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncryptBlobRequest copyWith(void Function(EncryptBlobRequest) updates) =>
      super.copyWith((message) => updates(message as EncryptBlobRequest))
          as EncryptBlobRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EncryptBlobRequest() / EncryptBlobRequest.new instead')
  static EncryptBlobRequest create() => EncryptBlobRequest._();
  static $pb.GeneratedMessage $_createMessage() => EncryptBlobRequest._();
  @$core.override
  EncryptBlobRequest createEmptyInstance() => EncryptBlobRequest._();
  @$core.pragma('dart2js:noInline')
  static EncryptBlobRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EncryptBlobRequest>(
          EncryptBlobRequest.$_createMessage);
  static EncryptBlobRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get kind => $_getIZ(1);
  @$pb.TagNumber(2)
  set kind($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get manifest => $_getBF(2);
  @$pb.TagNumber(3)
  set manifest($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasManifest() => $_has(2);
  @$pb.TagNumber(3)
  void clearManifest() => $_clearField(3);

  /// Pads the plaintext to its Padmé length, so the envelope hides its exact size.
  @$pb.TagNumber(4)
  $core.bool get padded => $_getBF(3);
  @$pb.TagNumber(4)
  set padded($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPadded() => $_has(3);
  @$pb.TagNumber(4)
  void clearPadded() => $_clearField(4);

  /// 32 random bytes.
  @$pb.TagNumber(5)
  $core.List<$core.int> get salt => $_getN(4);
  @$pb.TagNumber(5)
  set salt($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSalt() => $_has(4);
  @$pb.TagNumber(5)
  void clearSalt() => $_clearField(5);

  /// The whole plaintext or, when streaming, its first bytes.
  @$pb.TagNumber(6)
  $core.List<$core.int> get plaintext => $_getN(5);
  @$pb.TagNumber(6)
  set plaintext($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPlaintext() => $_has(5);
  @$pb.TagNumber(6)
  void clearPlaintext() => $_clearField(6);
}

/// A sealed envelope, or when streaming the part of it a step completed.
class EncryptBlobResponse extends $pb.GeneratedMessage {
  factory EncryptBlobResponse({
    $core.List<$core.int>? envelope,
  }) {
    final result = EncryptBlobResponse._();
    if (envelope != null) result.envelope = envelope;
    return result;
  }

  EncryptBlobResponse._();

  factory EncryptBlobResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncryptBlobResponse()..mergeFromBuffer(data, registry);
  factory EncryptBlobResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncryptBlobResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EncryptBlobResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: EncryptBlobResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'envelope', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncryptBlobResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncryptBlobResponse copyWith(void Function(EncryptBlobResponse) updates) =>
      super.copyWith((message) => updates(message as EncryptBlobResponse))
          as EncryptBlobResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use EncryptBlobResponse() / EncryptBlobResponse.new instead')
  static EncryptBlobResponse create() => EncryptBlobResponse._();
  static $pb.GeneratedMessage $_createMessage() => EncryptBlobResponse._();
  @$core.override
  EncryptBlobResponse createEmptyInstance() => EncryptBlobResponse._();
  @$core.pragma('dart2js:noInline')
  static EncryptBlobResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EncryptBlobResponse>(
          EncryptBlobResponse.$_createMessage);
  static EncryptBlobResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get envelope => $_getN(0);
  @$pb.TagNumber(1)
  set envelope($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEnvelope() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnvelope() => $_clearField(1);
}

/// Opens a PLB blob envelope, or a PLX manifest, of the content kind asked for. Called as a stream, the envelope may also
/// follow in pieces: each step returns the plaintext of the chunks it completed. Any run of an unpadded envelope's chunks
/// also opens alone (random access, for seeking): the envelope's header followed by its chunks from first_chunk on.
class DecryptBlobRequest extends $pb.GeneratedMessage {
  factory DecryptBlobRequest({
    $core.int? key,
    $core.int? kind,
    $core.bool? manifest,
    $core.List<$core.int>? envelope,
    $fixnum.Int64? firstChunk,
    $core.bool? more,
  }) {
    final result = DecryptBlobRequest._();
    if (key != null) result.key = key;
    if (kind != null) result.kind = kind;
    if (manifest != null) result.manifest = manifest;
    if (envelope != null) result.envelope = envelope;
    if (firstChunk != null) result.firstChunk = firstChunk;
    if (more != null) result.more = more;
    return result;
  }

  DecryptBlobRequest._();

  factory DecryptBlobRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DecryptBlobRequest()..mergeFromBuffer(data, registry);
  factory DecryptBlobRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DecryptBlobRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DecryptBlobRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DecryptBlobRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'key', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'kind', fieldType: $pb.PbFieldType.OU3)
    ..aOB(3, _omitFieldNames ? '' : 'manifest')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'envelope', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'firstChunk', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(6, _omitFieldNames ? '' : 'more')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecryptBlobRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecryptBlobRequest copyWith(void Function(DecryptBlobRequest) updates) =>
      super.copyWith((message) => updates(message as DecryptBlobRequest))
          as DecryptBlobRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DecryptBlobRequest() / DecryptBlobRequest.new instead')
  static DecryptBlobRequest create() => DecryptBlobRequest._();
  static $pb.GeneratedMessage $_createMessage() => DecryptBlobRequest._();
  @$core.override
  DecryptBlobRequest createEmptyInstance() => DecryptBlobRequest._();
  @$core.pragma('dart2js:noInline')
  static DecryptBlobRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DecryptBlobRequest>(
          DecryptBlobRequest.$_createMessage);
  static DecryptBlobRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get key => $_getIZ(0);
  @$pb.TagNumber(1)
  set key($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get kind => $_getIZ(1);
  @$pb.TagNumber(2)
  set kind($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get manifest => $_getBF(2);
  @$pb.TagNumber(3)
  set manifest($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasManifest() => $_has(2);
  @$pb.TagNumber(3)
  void clearManifest() => $_clearField(3);

  /// The whole envelope or, when streaming, its first bytes.
  @$pb.TagNumber(4)
  $core.List<$core.int> get envelope => $_getN(3);
  @$pb.TagNumber(4)
  set envelope($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEnvelope() => $_has(3);
  @$pb.TagNumber(4)
  void clearEnvelope() => $_clearField(4);

  /// The index of the first chunk after the header.
  @$pb.TagNumber(5)
  $fixnum.Int64 get firstChunk => $_getI64(4);
  @$pb.TagNumber(5)
  set firstChunk($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFirstChunk() => $_has(4);
  @$pb.TagNumber(5)
  void clearFirstChunk() => $_clearField(5);

  /// The chunks given stop before the envelope's last one, so none of them is opened as the last.
  @$pb.TagNumber(6)
  $core.bool get more => $_getBF(5);
  @$pb.TagNumber(6)
  set more($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMore() => $_has(5);
  @$pb.TagNumber(6)
  void clearMore() => $_clearField(6);
}

/// The plaintext of an envelope.
class DecryptBlobResponse extends $pb.GeneratedMessage {
  factory DecryptBlobResponse({
    $core.List<$core.int>? plaintext,
  }) {
    final result = DecryptBlobResponse._();
    if (plaintext != null) result.plaintext = plaintext;
    return result;
  }

  DecryptBlobResponse._();

  factory DecryptBlobResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DecryptBlobResponse()..mergeFromBuffer(data, registry);
  factory DecryptBlobResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DecryptBlobResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DecryptBlobResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DecryptBlobResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'plaintext', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecryptBlobResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecryptBlobResponse copyWith(void Function(DecryptBlobResponse) updates) =>
      super.copyWith((message) => updates(message as DecryptBlobResponse))
          as DecryptBlobResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use DecryptBlobResponse() / DecryptBlobResponse.new instead')
  static DecryptBlobResponse create() => DecryptBlobResponse._();
  static $pb.GeneratedMessage $_createMessage() => DecryptBlobResponse._();
  @$core.override
  DecryptBlobResponse createEmptyInstance() => DecryptBlobResponse._();
  @$core.pragma('dart2js:noInline')
  static DecryptBlobResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DecryptBlobResponse>(
          DecryptBlobResponse.$_createMessage);
  static DecryptBlobResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get plaintext => $_getN(0);
  @$pb.TagNumber(1)
  set plaintext($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaintext() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaintext() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
