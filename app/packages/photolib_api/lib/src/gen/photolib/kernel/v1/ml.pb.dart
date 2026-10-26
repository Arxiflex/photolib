// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/ml.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The input of an image model (design 09 §2.2), the same code on the server and every device so that their vectors
/// compare (ADR-0254): the whole image resized with a triangle filter to `size` × `size` (or, with `crop`, until its
/// short side is `size`, then its centred square), each channel scaled to [0, 1], less `mean` and over `std`.
class PrepareImageRequest extends $pb.GeneratedMessage {
  factory PrepareImageRequest({
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? rgba,
    $core.int? size,
    $core.Iterable<$core.double>? mean,
    $core.Iterable<$core.double>? std,
    $core.bool? crop,
  }) {
    final result = PrepareImageRequest._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (rgba != null) result.rgba = rgba;
    if (size != null) result.size = size;
    if (mean != null) result.mean.addAll(mean);
    if (std != null) result.std.addAll(std);
    if (crop != null) result.crop = crop;
    return result;
  }

  PrepareImageRequest._();

  factory PrepareImageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareImageRequest()..mergeFromBuffer(data, registry);
  factory PrepareImageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareImageRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrepareImageRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: PrepareImageRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'rgba', $pb.PbFieldType.OY)
    ..aI(4, _omitFieldNames ? '' : 'size', fieldType: $pb.PbFieldType.OU3)
    ..p<$core.double>(5, _omitFieldNames ? '' : 'mean', $pb.PbFieldType.KF)
    ..p<$core.double>(6, _omitFieldNames ? '' : 'std', $pb.PbFieldType.KF)
    ..aOB(7, _omitFieldNames ? '' : 'crop')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareImageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareImageRequest copyWith(void Function(PrepareImageRequest) updates) =>
      super.copyWith((message) => updates(message as PrepareImageRequest))
          as PrepareImageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use PrepareImageRequest() / PrepareImageRequest.new instead')
  static PrepareImageRequest create() => PrepareImageRequest._();
  static $pb.GeneratedMessage $_createMessage() => PrepareImageRequest._();
  @$core.override
  PrepareImageRequest createEmptyInstance() => PrepareImageRequest._();
  @$core.pragma('dart2js:noInline')
  static PrepareImageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrepareImageRequest>(
          PrepareImageRequest.$_createMessage);
  static PrepareImageRequest? _defaultInstance;

  /// 8-bit sRGB RGBA, upright, row by row; alpha is ignored.
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

  @$pb.TagNumber(3)
  $core.List<$core.int> get rgba => $_getN(2);
  @$pb.TagNumber(3)
  set rgba($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRgba() => $_has(2);
  @$pb.TagNumber(3)
  void clearRgba() => $_clearField(3);

  /// At most 1024.
  @$pb.TagNumber(4)
  $core.int get size => $_getIZ(3);
  @$pb.TagNumber(4)
  set size($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSize() => $_has(3);
  @$pb.TagNumber(4)
  void clearSize() => $_clearField(4);

  /// Red, green and blue: three each, every std non-zero.
  @$pb.TagNumber(5)
  $pb.PbList<$core.double> get mean => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.double> get std => $_getList(5);

  /// Keep the proportions and crop, for a model whose own processor crops.
  @$pb.TagNumber(7)
  $core.bool get crop => $_getBF(6);
  @$pb.TagNumber(7)
  set crop($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCrop() => $_has(6);
  @$pb.TagNumber(7)
  void clearCrop() => $_clearField(7);
}

/// The tensor of a PrepareImageRequest.
class PrepareImageResponse extends $pb.GeneratedMessage {
  factory PrepareImageResponse({
    $core.List<$core.int>? tensor,
  }) {
    final result = PrepareImageResponse._();
    if (tensor != null) result.tensor = tensor;
    return result;
  }

  PrepareImageResponse._();

  factory PrepareImageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareImageResponse()..mergeFromBuffer(data, registry);
  factory PrepareImageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareImageResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrepareImageResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: PrepareImageResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'tensor', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareImageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareImageResponse copyWith(void Function(PrepareImageResponse) updates) =>
      super.copyWith((message) => updates(message as PrepareImageResponse))
          as PrepareImageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PrepareImageResponse() / PrepareImageResponse.new instead')
  static PrepareImageResponse create() => PrepareImageResponse._();
  static $pb.GeneratedMessage $_createMessage() => PrepareImageResponse._();
  @$core.override
  PrepareImageResponse createEmptyInstance() => PrepareImageResponse._();
  @$core.pragma('dart2js:noInline')
  static PrepareImageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrepareImageResponse>(
          PrepareImageResponse.$_createMessage);
  static PrepareImageResponse? _defaultInstance;

  /// 3 × size × size float32 values, little-endian: the red plane, then green, then blue, each row by row.
  @$pb.TagNumber(1)
  $core.List<$core.int> get tensor => $_getN(0);
  @$pb.TagNumber(1)
  set tensor($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTensor() => $_has(0);
  @$pb.TagNumber(1)
  void clearTensor() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
