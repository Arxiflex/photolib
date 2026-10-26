// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/faces.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'develop.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// A face in an upright image, in fractions of its width and height so that it holds at any size of the image.
class Face extends $pb.GeneratedMessage {
  factory Face({
    $core.double? x,
    $core.double? y,
    $core.double? width,
    $core.double? height,
    $core.Iterable<$core.double>? landmarks,
    $core.double? score,
  }) {
    final result = Face._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (landmarks != null) result.landmarks.addAll(landmarks);
    if (score != null) result.score = score;
    return result;
  }

  Face._();

  factory Face.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Face()..mergeFromBuffer(data, registry);
  factory Face.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Face()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Face',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Face.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OF)
    ..p<$core.double>(5, _omitFieldNames ? '' : 'landmarks', $pb.PbFieldType.KF)
    ..aD(6, _omitFieldNames ? '' : 'score', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Face clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Face copyWith(void Function(Face) updates) =>
      super.copyWith((message) => updates(message as Face)) as Face;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Face() / Face.new instead')
  static Face create() => Face._();
  static $pb.GeneratedMessage $_createMessage() => Face._();
  @$core.override
  Face createEmptyInstance() => Face._();
  @$core.pragma('dart2js:noInline')
  static Face getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Face>(Face.$_createMessage);
  static Face? _defaultInstance;

  /// The box, inside the image: its top left corner and size.
  @$pb.TagNumber(1)
  $core.double get x => $_getN(0);
  @$pb.TagNumber(1)
  set x($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get y => $_getN(1);
  @$pb.TagNumber(2)
  set y($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get width => $_getN(2);
  @$pb.TagNumber(3)
  set width($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWidth() => $_has(2);
  @$pb.TagNumber(3)
  void clearWidth() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get height => $_getN(3);
  @$pb.TagNumber(4)
  set height($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeight() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeight() => $_clearField(4);

  /// The face's right eye, left eye, nose tip and right and left mouth corners as x, y pairs (ten values, in the
  /// order of the face's own sides, so that the right eye is the left one in the picture). They may lie outside the
  /// image.
  @$pb.TagNumber(5)
  $pb.PbList<$core.double> get landmarks => $_getList(4);

  /// YuNet's confidence, 0 to 1.
  @$pb.TagNumber(6)
  $core.double get score => $_getN(5);
  @$pb.TagNumber(6)
  set score($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasScore() => $_has(5);
  @$pb.TagNumber(6)
  void clearScore() => $_clearField(6);
}

/// The input of YuNet: the image stretched to a size YuNet takes (multiples of 32), as blue, green and red planes of
/// values 0 to 255.
class PrepareFaceDetectionRequest extends $pb.GeneratedMessage {
  factory PrepareFaceDetectionRequest({
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? rgba,
    $core.int? maxSide,
  }) {
    final result = PrepareFaceDetectionRequest._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (rgba != null) result.rgba = rgba;
    if (maxSide != null) result.maxSide = maxSide;
    return result;
  }

  PrepareFaceDetectionRequest._();

  factory PrepareFaceDetectionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareFaceDetectionRequest()..mergeFromBuffer(data, registry);
  factory PrepareFaceDetectionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareFaceDetectionRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrepareFaceDetectionRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: PrepareFaceDetectionRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'rgba', $pb.PbFieldType.OY)
    ..aI(4, _omitFieldNames ? '' : 'maxSide', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareFaceDetectionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareFaceDetectionRequest copyWith(
          void Function(PrepareFaceDetectionRequest) updates) =>
      super.copyWith(
              (message) => updates(message as PrepareFaceDetectionRequest))
          as PrepareFaceDetectionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PrepareFaceDetectionRequest() / PrepareFaceDetectionRequest.new instead')
  static PrepareFaceDetectionRequest create() =>
      PrepareFaceDetectionRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      PrepareFaceDetectionRequest._();
  @$core.override
  PrepareFaceDetectionRequest createEmptyInstance() =>
      PrepareFaceDetectionRequest._();
  @$core.pragma('dart2js:noInline')
  static PrepareFaceDetectionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrepareFaceDetectionRequest>(
          PrepareFaceDetectionRequest.$_createMessage);
  static PrepareFaceDetectionRequest? _defaultInstance;

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

  /// The longer side of the tensor, 32 to 1,280 (640 if 0); the shorter keeps the proportions, to a multiple of 32.
  @$pb.TagNumber(4)
  $core.int get maxSide => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxSide($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxSide() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxSide() => $_clearField(4);
}

/// The tensor of a PrepareFaceDetectionRequest.
class PrepareFaceDetectionResponse extends $pb.GeneratedMessage {
  factory PrepareFaceDetectionResponse({
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? tensor,
  }) {
    final result = PrepareFaceDetectionResponse._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (tensor != null) result.tensor = tensor;
    return result;
  }

  PrepareFaceDetectionResponse._();

  factory PrepareFaceDetectionResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareFaceDetectionResponse()..mergeFromBuffer(data, registry);
  factory PrepareFaceDetectionResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareFaceDetectionResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrepareFaceDetectionResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: PrepareFaceDetectionResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'tensor', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareFaceDetectionResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareFaceDetectionResponse copyWith(
          void Function(PrepareFaceDetectionResponse) updates) =>
      super.copyWith(
              (message) => updates(message as PrepareFaceDetectionResponse))
          as PrepareFaceDetectionResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PrepareFaceDetectionResponse() / PrepareFaceDetectionResponse.new instead')
  static PrepareFaceDetectionResponse create() =>
      PrepareFaceDetectionResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      PrepareFaceDetectionResponse._();
  @$core.override
  PrepareFaceDetectionResponse createEmptyInstance() =>
      PrepareFaceDetectionResponse._();
  @$core.pragma('dart2js:noInline')
  static PrepareFaceDetectionResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrepareFaceDetectionResponse>(
          PrepareFaceDetectionResponse.$_createMessage);
  static PrepareFaceDetectionResponse? _defaultInstance;

  /// The tensor's size.
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

  /// 3 × height × width float32 values, little-endian.
  @$pb.TagNumber(3)
  $core.List<$core.int> get tensor => $_getN(2);
  @$pb.TagNumber(3)
  set tensor($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTensor() => $_has(2);
  @$pb.TagNumber(3)
  void clearTensor() => $_clearField(3);
}

/// Reads YuNet's outputs for a tensor of `width` × `height`.
class DecodeFacesRequest extends $pb.GeneratedMessage {
  factory DecodeFacesRequest({
    $core.int? width,
    $core.int? height,
    $core.Iterable<$core.List<$core.int>>? outputs,
    $core.double? minScore,
    $core.double? maxOverlap,
    $core.int? maxFaces,
  }) {
    final result = DecodeFacesRequest._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (outputs != null) result.outputs.addAll(outputs);
    if (minScore != null) result.minScore = minScore;
    if (maxOverlap != null) result.maxOverlap = maxOverlap;
    if (maxFaces != null) result.maxFaces = maxFaces;
    return result;
  }

  DecodeFacesRequest._();

  factory DecodeFacesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DecodeFacesRequest()..mergeFromBuffer(data, registry);
  factory DecodeFacesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DecodeFacesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DecodeFacesRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DecodeFacesRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..p<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'outputs', $pb.PbFieldType.PY)
    ..aD(4, _omitFieldNames ? '' : 'minScore', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'maxOverlap', fieldType: $pb.PbFieldType.OF)
    ..aI(6, _omitFieldNames ? '' : 'maxFaces', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecodeFacesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecodeFacesRequest copyWith(void Function(DecodeFacesRequest) updates) =>
      super.copyWith((message) => updates(message as DecodeFacesRequest))
          as DecodeFacesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DecodeFacesRequest() / DecodeFacesRequest.new instead')
  static DecodeFacesRequest create() => DecodeFacesRequest._();
  static $pb.GeneratedMessage $_createMessage() => DecodeFacesRequest._();
  @$core.override
  DecodeFacesRequest createEmptyInstance() => DecodeFacesRequest._();
  @$core.pragma('dart2js:noInline')
  static DecodeFacesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DecodeFacesRequest>(
          DecodeFacesRequest.$_createMessage);
  static DecodeFacesRequest? _defaultInstance;

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

  /// The twelve outputs in the model's order, each float32 little-endian: cls, obj, bbox and kps at strides 8, 16
  /// and 32 (cls_8, cls_16, cls_32, obj_8, ..., kps_32).
  @$pb.TagNumber(3)
  $pb.PbList<$core.List<$core.int>> get outputs => $_getList(2);

  /// 0 to 1; 0.7 if 0.
  @$pb.TagNumber(4)
  $core.double get minScore => $_getN(3);
  @$pb.TagNumber(4)
  set minScore($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMinScore() => $_has(3);
  @$pb.TagNumber(4)
  void clearMinScore() => $_clearField(4);

  /// Boxes that overlap a better one by more than this fraction are dropped; 0.3 if 0.
  @$pb.TagNumber(5)
  $core.double get maxOverlap => $_getN(4);
  @$pb.TagNumber(5)
  set maxOverlap($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxOverlap() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxOverlap() => $_clearField(5);

  /// At most this many faces, the best first; 64 if 0.
  @$pb.TagNumber(6)
  $core.int get maxFaces => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxFaces($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxFaces() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxFaces() => $_clearField(6);
}

/// The faces YuNet found, best first.
class DecodeFacesResponse extends $pb.GeneratedMessage {
  factory DecodeFacesResponse({
    $core.Iterable<Face>? faces,
  }) {
    final result = DecodeFacesResponse._();
    if (faces != null) result.faces.addAll(faces);
    return result;
  }

  DecodeFacesResponse._();

  factory DecodeFacesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DecodeFacesResponse()..mergeFromBuffer(data, registry);
  factory DecodeFacesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DecodeFacesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DecodeFacesResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DecodeFacesResponse.$_createMessage)
    ..pPM<Face>(1, _omitFieldNames ? '' : 'faces',
        subBuilder: Face.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecodeFacesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DecodeFacesResponse copyWith(void Function(DecodeFacesResponse) updates) =>
      super.copyWith((message) => updates(message as DecodeFacesResponse))
          as DecodeFacesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use DecodeFacesResponse() / DecodeFacesResponse.new instead')
  static DecodeFacesResponse create() => DecodeFacesResponse._();
  static $pb.GeneratedMessage $_createMessage() => DecodeFacesResponse._();
  @$core.override
  DecodeFacesResponse createEmptyInstance() => DecodeFacesResponse._();
  @$core.pragma('dart2js:noInline')
  static DecodeFacesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DecodeFacesResponse>(
          DecodeFacesResponse.$_createMessage);
  static DecodeFacesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Face> get faces => $_getList(0);
}

/// The input of SFace: the face turned, scaled and cut to 112 × 112 by the similarity transform that puts its
/// landmarks on ArcFace's template.
class AlignFaceRequest extends $pb.GeneratedMessage {
  factory AlignFaceRequest({
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? rgba,
    $core.Iterable<$core.double>? landmarks,
    $core.Iterable<$core.double>? mean,
    $core.Iterable<$core.double>? std,
  }) {
    final result = AlignFaceRequest._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (rgba != null) result.rgba = rgba;
    if (landmarks != null) result.landmarks.addAll(landmarks);
    if (mean != null) result.mean.addAll(mean);
    if (std != null) result.std.addAll(std);
    return result;
  }

  AlignFaceRequest._();

  factory AlignFaceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AlignFaceRequest()..mergeFromBuffer(data, registry);
  factory AlignFaceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AlignFaceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AlignFaceRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: AlignFaceRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'rgba', $pb.PbFieldType.OY)
    ..p<$core.double>(4, _omitFieldNames ? '' : 'landmarks', $pb.PbFieldType.KF)
    ..p<$core.double>(5, _omitFieldNames ? '' : 'mean', $pb.PbFieldType.KF)
    ..p<$core.double>(6, _omitFieldNames ? '' : 'std', $pb.PbFieldType.KF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AlignFaceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AlignFaceRequest copyWith(void Function(AlignFaceRequest) updates) =>
      super.copyWith((message) => updates(message as AlignFaceRequest))
          as AlignFaceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AlignFaceRequest() / AlignFaceRequest.new instead')
  static AlignFaceRequest create() => AlignFaceRequest._();
  static $pb.GeneratedMessage $_createMessage() => AlignFaceRequest._();
  @$core.override
  AlignFaceRequest createEmptyInstance() => AlignFaceRequest._();
  @$core.pragma('dart2js:noInline')
  static AlignFaceRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AlignFaceRequest>(
          AlignFaceRequest.$_createMessage);
  static AlignFaceRequest? _defaultInstance;

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

  /// The face's ten landmark values, as in Face.
  @$pb.TagNumber(4)
  $pb.PbList<$core.double> get landmarks => $_getList(3);

  /// The model's own scaling, as PrepareImageRequest has it: each value scaled to [0, 1], less `mean` and over `std`
  /// (red, green and blue: three each, every std non-zero). Both empty leaves the values 0 to 255, as SFace takes them.
  @$pb.TagNumber(5)
  $pb.PbList<$core.double> get mean => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.double> get std => $_getList(5);
}

/// The tensor of an AlignFaceRequest.
class AlignFaceResponse extends $pb.GeneratedMessage {
  factory AlignFaceResponse({
    $core.List<$core.int>? tensor,
  }) {
    final result = AlignFaceResponse._();
    if (tensor != null) result.tensor = tensor;
    return result;
  }

  AlignFaceResponse._();

  factory AlignFaceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AlignFaceResponse()..mergeFromBuffer(data, registry);
  factory AlignFaceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AlignFaceResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AlignFaceResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: AlignFaceResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'tensor', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AlignFaceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AlignFaceResponse copyWith(void Function(AlignFaceResponse) updates) =>
      super.copyWith((message) => updates(message as AlignFaceResponse))
          as AlignFaceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AlignFaceResponse() / AlignFaceResponse.new instead')
  static AlignFaceResponse create() => AlignFaceResponse._();
  static $pb.GeneratedMessage $_createMessage() => AlignFaceResponse._();
  @$core.override
  AlignFaceResponse createEmptyInstance() => AlignFaceResponse._();
  @$core.pragma('dart2js:noInline')
  static AlignFaceResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AlignFaceResponse>(
          AlignFaceResponse.$_createMessage);
  static AlignFaceResponse? _defaultInstance;

  /// 3 × 112 × 112 float32 values, little-endian: red, green and blue planes.
  @$pb.TagNumber(1)
  $core.List<$core.int> get tensor => $_getN(0);
  @$pb.TagNumber(1)
  set tensor($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTensor() => $_has(0);
  @$pb.TagNumber(1)
  void clearTensor() => $_clearField(1);
}

/// SFace's 128 values as a unit vector, which compares by dot product.
class NormalizeFaceEmbeddingRequest extends $pb.GeneratedMessage {
  factory NormalizeFaceEmbeddingRequest({
    $core.Iterable<$core.double>? values,
  }) {
    final result = NormalizeFaceEmbeddingRequest._();
    if (values != null) result.values.addAll(values);
    return result;
  }

  NormalizeFaceEmbeddingRequest._();

  factory NormalizeFaceEmbeddingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NormalizeFaceEmbeddingRequest()..mergeFromBuffer(data, registry);
  factory NormalizeFaceEmbeddingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NormalizeFaceEmbeddingRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NormalizeFaceEmbeddingRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: NormalizeFaceEmbeddingRequest.$_createMessage)
    ..p<$core.double>(1, _omitFieldNames ? '' : 'values', $pb.PbFieldType.KF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NormalizeFaceEmbeddingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NormalizeFaceEmbeddingRequest copyWith(
          void Function(NormalizeFaceEmbeddingRequest) updates) =>
      super.copyWith(
              (message) => updates(message as NormalizeFaceEmbeddingRequest))
          as NormalizeFaceEmbeddingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NormalizeFaceEmbeddingRequest() / NormalizeFaceEmbeddingRequest.new instead')
  static NormalizeFaceEmbeddingRequest create() =>
      NormalizeFaceEmbeddingRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      NormalizeFaceEmbeddingRequest._();
  @$core.override
  NormalizeFaceEmbeddingRequest createEmptyInstance() =>
      NormalizeFaceEmbeddingRequest._();
  @$core.pragma('dart2js:noInline')
  static NormalizeFaceEmbeddingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NormalizeFaceEmbeddingRequest>(
          NormalizeFaceEmbeddingRequest.$_createMessage);
  static NormalizeFaceEmbeddingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.double> get values => $_getList(0);
}

/// The embedding as a unit vector.
class NormalizeFaceEmbeddingResponse extends $pb.GeneratedMessage {
  factory NormalizeFaceEmbeddingResponse({
    $core.Iterable<$core.double>? values,
  }) {
    final result = NormalizeFaceEmbeddingResponse._();
    if (values != null) result.values.addAll(values);
    return result;
  }

  NormalizeFaceEmbeddingResponse._();

  factory NormalizeFaceEmbeddingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NormalizeFaceEmbeddingResponse()..mergeFromBuffer(data, registry);
  factory NormalizeFaceEmbeddingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      NormalizeFaceEmbeddingResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NormalizeFaceEmbeddingResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: NormalizeFaceEmbeddingResponse.$_createMessage)
    ..p<$core.double>(1, _omitFieldNames ? '' : 'values', $pb.PbFieldType.KF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NormalizeFaceEmbeddingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NormalizeFaceEmbeddingResponse copyWith(
          void Function(NormalizeFaceEmbeddingResponse) updates) =>
      super.copyWith(
              (message) => updates(message as NormalizeFaceEmbeddingResponse))
          as NormalizeFaceEmbeddingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use NormalizeFaceEmbeddingResponse() / NormalizeFaceEmbeddingResponse.new instead')
  static NormalizeFaceEmbeddingResponse create() =>
      NormalizeFaceEmbeddingResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      NormalizeFaceEmbeddingResponse._();
  @$core.override
  NormalizeFaceEmbeddingResponse createEmptyInstance() =>
      NormalizeFaceEmbeddingResponse._();
  @$core.pragma('dart2js:noInline')
  static NormalizeFaceEmbeddingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NormalizeFaceEmbeddingResponse>(
          NormalizeFaceEmbeddingResponse.$_createMessage);
  static NormalizeFaceEmbeddingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.double> get values => $_getList(0);
}

/// Moves faces between an upright original and a copy of it that has had a geometry edit (the same turns, mirror and
/// crop as Develop and EditCopyResponse.crop), so that boxes stored against the original stay right on the copy.
class MapFacesRequest extends $pb.GeneratedMessage {
  factory MapFacesRequest({
    $core.Iterable<Face>? faces,
    $core.int? width,
    $core.int? height,
    $0.Develop? edit,
    $core.bool? toOriginal,
  }) {
    final result = MapFacesRequest._();
    if (faces != null) result.faces.addAll(faces);
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (edit != null) result.edit = edit;
    if (toOriginal != null) result.toOriginal = toOriginal;
    return result;
  }

  MapFacesRequest._();

  factory MapFacesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapFacesRequest()..mergeFromBuffer(data, registry);
  factory MapFacesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapFacesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapFacesRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapFacesRequest.$_createMessage)
    ..pPM<Face>(1, _omitFieldNames ? '' : 'faces',
        subBuilder: Face.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aOM<$0.Develop>(4, _omitFieldNames ? '' : 'edit',
        subBuilder: $0.Develop.$_createMessage)
    ..aOB(5, _omitFieldNames ? '' : 'toOriginal')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapFacesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapFacesRequest copyWith(void Function(MapFacesRequest) updates) =>
      super.copyWith((message) => updates(message as MapFacesRequest))
          as MapFacesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapFacesRequest() / MapFacesRequest.new instead')
  static MapFacesRequest create() => MapFacesRequest._();
  static $pb.GeneratedMessage $_createMessage() => MapFacesRequest._();
  @$core.override
  MapFacesRequest createEmptyInstance() => MapFacesRequest._();
  @$core.pragma('dart2js:noInline')
  static MapFacesRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MapFacesRequest>(
          MapFacesRequest.$_createMessage);
  static MapFacesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Face> get faces => $_getList(0);

  /// The original's size in pixels, whichever way the faces move.
  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidth() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeight() => $_clearField(3);

  /// The edit; only its quarter turns, flip and crop count. The crop is in pixels of the turned and mirrored original.
  @$pb.TagNumber(4)
  $0.Develop get edit => $_getN(3);
  @$pb.TagNumber(4)
  set edit($0.Develop value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasEdit() => $_has(3);
  @$pb.TagNumber(4)
  void clearEdit() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.Develop ensureEdit() => $_ensure(3);

  /// False: from the original to the copy; true: from the copy back to the original.
  @$pb.TagNumber(5)
  $core.bool get toOriginal => $_getBF(4);
  @$pb.TagNumber(5)
  set toOriginal($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasToOriginal() => $_has(4);
  @$pb.TagNumber(5)
  void clearToOriginal() => $_clearField(5);
}

/// The faces moved by the edit.
class MapFacesResponse extends $pb.GeneratedMessage {
  factory MapFacesResponse({
    $core.Iterable<Face>? faces,
    $core.Iterable<$core.bool>? visible,
  }) {
    final result = MapFacesResponse._();
    if (faces != null) result.faces.addAll(faces);
    if (visible != null) result.visible.addAll(visible);
    return result;
  }

  MapFacesResponse._();

  factory MapFacesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapFacesResponse()..mergeFromBuffer(data, registry);
  factory MapFacesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapFacesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapFacesResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapFacesResponse.$_createMessage)
    ..pPM<Face>(1, _omitFieldNames ? '' : 'faces',
        subBuilder: Face.$_createMessage)
    ..p<$core.bool>(2, _omitFieldNames ? '' : 'visible', $pb.PbFieldType.KB)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapFacesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapFacesResponse copyWith(void Function(MapFacesResponse) updates) =>
      super.copyWith((message) => updates(message as MapFacesResponse))
          as MapFacesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapFacesResponse() / MapFacesResponse.new instead')
  static MapFacesResponse create() => MapFacesResponse._();
  static $pb.GeneratedMessage $_createMessage() => MapFacesResponse._();
  @$core.override
  MapFacesResponse createEmptyInstance() => MapFacesResponse._();
  @$core.pragma('dart2js:noInline')
  static MapFacesResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MapFacesResponse>(
          MapFacesResponse.$_createMessage);
  static MapFacesResponse? _defaultInstance;

  /// One for each face of the request, in the other image's fractions.
  @$pb.TagNumber(1)
  $pb.PbList<Face> get faces => $_getList(0);

  /// Whether at least half of the face's box is in the copy; false only from the original, for a face the crop cuts
  /// away. Its box is then clipped to the copy.
  @$pb.TagNumber(2)
  $pb.PbList<$core.bool> get visible => $_getList(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
