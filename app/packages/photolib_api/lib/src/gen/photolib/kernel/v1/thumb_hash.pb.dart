// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/thumb_hash.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Encodes the ThumbHash of a small image (https://evanw.github.io/thumbhash/): the one encoder of the server and the
/// device indexers, held to testdata/thumbhash.json; clients decode in their own code (ADR-0070).
class EncodeThumbHashRequest extends $pb.GeneratedMessage {
  factory EncodeThumbHashRequest({
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? rgba,
  }) {
    final result = EncodeThumbHashRequest._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (rgba != null) result.rgba = rgba;
    return result;
  }

  EncodeThumbHashRequest._();

  factory EncodeThumbHashRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncodeThumbHashRequest()..mergeFromBuffer(data, registry);
  factory EncodeThumbHashRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncodeThumbHashRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EncodeThumbHashRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: EncodeThumbHashRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'rgba', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncodeThumbHashRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncodeThumbHashRequest copyWith(
          void Function(EncodeThumbHashRequest) updates) =>
      super.copyWith((message) => updates(message as EncodeThumbHashRequest))
          as EncodeThumbHashRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use EncodeThumbHashRequest() / EncodeThumbHashRequest.new instead')
  static EncodeThumbHashRequest create() => EncodeThumbHashRequest._();
  static $pb.GeneratedMessage $_createMessage() => EncodeThumbHashRequest._();
  @$core.override
  EncodeThumbHashRequest createEmptyInstance() => EncodeThumbHashRequest._();
  @$core.pragma('dart2js:noInline')
  static EncodeThumbHashRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EncodeThumbHashRequest>(
          EncodeThumbHashRequest.$_createMessage);
  static EncodeThumbHashRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get width => $_getIZ(0);
  @$pb.TagNumber(1)
  set width($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWidth() => $_has(0);
  @$pb.TagNumber(1)
  void clearWidth() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get height => $_getIZ(1);
  @$pb.TagNumber(2)
  set height($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeight() => $_clearField(2);

  /// Unpremultiplied 8-bit RGBA, width × height pixels, at most 100 a side.
  @$pb.TagNumber(3)
  $core.List<$core.int> get rgba => $_getN(2);
  @$pb.TagNumber(3)
  set rgba($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRgba() => $_has(2);
  @$pb.TagNumber(3)
  void clearRgba() => $_clearField(3);
}

/// The hash, about 25 bytes.
class EncodeThumbHashResponse extends $pb.GeneratedMessage {
  factory EncodeThumbHashResponse({
    $core.List<$core.int>? hash,
  }) {
    final result = EncodeThumbHashResponse._();
    if (hash != null) result.hash = hash;
    return result;
  }

  EncodeThumbHashResponse._();

  factory EncodeThumbHashResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncodeThumbHashResponse()..mergeFromBuffer(data, registry);
  factory EncodeThumbHashResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncodeThumbHashResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EncodeThumbHashResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: EncodeThumbHashResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'hash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncodeThumbHashResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncodeThumbHashResponse copyWith(
          void Function(EncodeThumbHashResponse) updates) =>
      super.copyWith((message) => updates(message as EncodeThumbHashResponse))
          as EncodeThumbHashResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use EncodeThumbHashResponse() / EncodeThumbHashResponse.new instead')
  static EncodeThumbHashResponse create() => EncodeThumbHashResponse._();
  static $pb.GeneratedMessage $_createMessage() => EncodeThumbHashResponse._();
  @$core.override
  EncodeThumbHashResponse createEmptyInstance() => EncodeThumbHashResponse._();
  @$core.pragma('dart2js:noInline')
  static EncodeThumbHashResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EncodeThumbHashResponse>(
          EncodeThumbHashResponse.$_createMessage);
  static EncodeThumbHashResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get hash => $_getN(0);
  @$pb.TagNumber(1)
  set hash($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHash() => $_has(0);
  @$pb.TagNumber(1)
  void clearHash() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
