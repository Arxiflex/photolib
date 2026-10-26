// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/heif.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'heif.pbenum.dart';
import 'metadata.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'heif.pbenum.dart';

/// Where a HEIF still keeps the coded images a platform decoder shows (ISO/IEC 23008-12), so that a host with a video
/// decoder, such as the browser's WebCodecs, can decode them without a HEIF library. Pure parsing: no pixel is decoded.
class ReadHeifRequest extends $pb.GeneratedMessage {
  factory ReadHeifRequest({
    $core.Iterable<$0.FileRange>? ranges,
    $fixnum.Int64? size,
  }) {
    final result = ReadHeifRequest._();
    if (ranges != null) result.ranges.addAll(ranges);
    if (size != null) result.size = size;
    return result;
  }

  ReadHeifRequest._();

  factory ReadHeifRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadHeifRequest()..mergeFromBuffer(data, registry);
  factory ReadHeifRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadHeifRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadHeifRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ReadHeifRequest.$_createMessage)
    ..pPM<$0.FileRange>(1, _omitFieldNames ? '' : 'ranges',
        subBuilder: $0.FileRange.$_createMessage)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'size', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadHeifRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadHeifRequest copyWith(void Function(ReadHeifRequest) updates) =>
      super.copyWith((message) => updates(message as ReadHeifRequest))
          as ReadHeifRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReadHeifRequest() / ReadHeifRequest.new instead')
  static ReadHeifRequest create() => ReadHeifRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReadHeifRequest._();
  @$core.override
  ReadHeifRequest createEmptyInstance() => ReadHeifRequest._();
  @$core.pragma('dart2js:noInline')
  static ReadHeifRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReadHeifRequest>(
          ReadHeifRequest.$_createMessage);
  static ReadHeifRequest? _defaultInstance;

  /// As ReadMetadataRequest.ranges: usually the first 64 KiB, which holds the meta box.
  @$pb.TagNumber(1)
  $pb.PbList<$0.FileRange> get ranges => $_getList(0);

  /// The file's length in bytes, 0 when unknown.
  @$pb.TagNumber(2)
  $fixnum.Int64 get size => $_getI64(1);
  @$pb.TagNumber(2)
  set size($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearSize() => $_clearField(2);
}

/// What a HEIF still's meta box says of its coded images.
class ReadHeifResponse extends $pb.GeneratedMessage {
  factory ReadHeifResponse({
    $core.Iterable<$0.ByteSpan>? missing,
    HeifStatus? status,
    $core.String? itemType,
    HeifPicture? picture,
    HeifPicture? thumbnail,
  }) {
    final result = ReadHeifResponse._();
    if (missing != null) result.missing.addAll(missing);
    if (status != null) result.status = status;
    if (itemType != null) result.itemType = itemType;
    if (picture != null) result.picture = picture;
    if (thumbnail != null) result.thumbnail = thumbnail;
    return result;
  }

  ReadHeifResponse._();

  factory ReadHeifResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadHeifResponse()..mergeFromBuffer(data, registry);
  factory ReadHeifResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadHeifResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadHeifResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ReadHeifResponse.$_createMessage)
    ..pPM<$0.ByteSpan>(1, _omitFieldNames ? '' : 'missing',
        subBuilder: $0.ByteSpan.$_createMessage)
    ..aE<HeifStatus>(2, _omitFieldNames ? '' : 'status',
        enumValues: HeifStatus.values)
    ..aOS(3, _omitFieldNames ? '' : 'itemType')
    ..aOM<HeifPicture>(4, _omitFieldNames ? '' : 'picture',
        subBuilder: HeifPicture.$_createMessage)
    ..aOM<HeifPicture>(5, _omitFieldNames ? '' : 'thumbnail',
        subBuilder: HeifPicture.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadHeifResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadHeifResponse copyWith(void Function(ReadHeifResponse) updates) =>
      super.copyWith((message) => updates(message as ReadHeifResponse))
          as ReadHeifResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReadHeifResponse() / ReadHeifResponse.new instead')
  static ReadHeifResponse create() => ReadHeifResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReadHeifResponse._();
  @$core.override
  ReadHeifResponse createEmptyInstance() => ReadHeifResponse._();
  @$core.pragma('dart2js:noInline')
  static ReadHeifResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReadHeifResponse>(
          ReadHeifResponse.$_createMessage);
  static ReadHeifResponse? _defaultInstance;

  /// Ranges of the file to send and call again with, as ReadMetadataResponse.missing.
  @$pb.TagNumber(1)
  $pb.PbList<$0.ByteSpan> get missing => $_getList(0);

  @$pb.TagNumber(2)
  HeifStatus get status => $_getN(1);
  @$pb.TagNumber(2)
  set status(HeifStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  /// The primary item's type when the status is HEIF_STATUS_UNSUPPORTED_CODEC, e.g. "jpeg" or "iovl".
  @$pb.TagNumber(3)
  $core.String get itemType => $_getSZ(2);
  @$pb.TagNumber(3)
  set itemType($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasItemType() => $_has(2);
  @$pb.TagNumber(3)
  void clearItemType() => $_clearField(3);

  /// The primary picture, when the status is HEIF_STATUS_OK.
  @$pb.TagNumber(4)
  HeifPicture get picture => $_getN(3);
  @$pb.TagNumber(4)
  set picture(HeifPicture value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPicture() => $_has(3);
  @$pb.TagNumber(4)
  void clearPicture() => $_clearField(4);
  @$pb.TagNumber(4)
  HeifPicture ensurePicture() => $_ensure(3);

  /// The picture of the thumbnail item (thmb), when it is coded in a codec of its own kind.
  @$pb.TagNumber(5)
  HeifPicture get thumbnail => $_getN(4);
  @$pb.TagNumber(5)
  set thumbnail(HeifPicture value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasThumbnail() => $_has(4);
  @$pb.TagNumber(5)
  void clearThumbnail() => $_clearField(5);
  @$pb.TagNumber(5)
  HeifPicture ensureThumbnail() => $_ensure(4);
}

/// A picture: one coded image, or a grid of them, and the transforms that make it the one shown, applied in the order
/// clap, irot, imir.
class HeifPicture extends $pb.GeneratedMessage {
  factory HeifPicture({
    $core.int? width,
    $core.int? height,
    HeifImage? image,
    $core.int? rows,
    $core.int? columns,
    $core.Iterable<HeifImage>? tiles,
    HeifClap? clap,
    $core.int? rotation,
    $core.int? mirror,
  }) {
    final result = HeifPicture._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (image != null) result.image = image;
    if (rows != null) result.rows = rows;
    if (columns != null) result.columns = columns;
    if (tiles != null) result.tiles.addAll(tiles);
    if (clap != null) result.clap = clap;
    if (rotation != null) result.rotation = rotation;
    if (mirror != null) result.mirror = mirror;
    return result;
  }

  HeifPicture._();

  factory HeifPicture.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeifPicture()..mergeFromBuffer(data, registry);
  factory HeifPicture.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeifPicture()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HeifPicture',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: HeifPicture.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aOM<HeifImage>(3, _omitFieldNames ? '' : 'image',
        subBuilder: HeifImage.$_createMessage)
    ..aI(4, _omitFieldNames ? '' : 'rows', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'columns', fieldType: $pb.PbFieldType.OU3)
    ..pPM<HeifImage>(6, _omitFieldNames ? '' : 'tiles',
        subBuilder: HeifImage.$_createMessage)
    ..aOM<HeifClap>(7, _omitFieldNames ? '' : 'clap',
        subBuilder: HeifClap.$_createMessage)
    ..aI(8, _omitFieldNames ? '' : 'rotation', fieldType: $pb.PbFieldType.OU3)
    ..aI(9, _omitFieldNames ? '' : 'mirror', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeifPicture clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeifPicture copyWith(void Function(HeifPicture) updates) =>
      super.copyWith((message) => updates(message as HeifPicture))
          as HeifPicture;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HeifPicture() / HeifPicture.new instead')
  static HeifPicture create() => HeifPicture._();
  static $pb.GeneratedMessage $_createMessage() => HeifPicture._();
  @$core.override
  HeifPicture createEmptyInstance() => HeifPicture._();
  @$core.pragma('dart2js:noInline')
  static HeifPicture getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HeifPicture>(
          HeifPicture.$_createMessage);
  static HeifPicture? _defaultInstance;

  /// The size before the transforms: the grid's output, or the image's ispe.
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

  /// The coded image, unless the picture is a grid.
  @$pb.TagNumber(3)
  HeifImage get image => $_getN(2);
  @$pb.TagNumber(3)
  set image(HeifImage value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasImage() => $_has(2);
  @$pb.TagNumber(3)
  void clearImage() => $_clearField(3);
  @$pb.TagNumber(3)
  HeifImage ensureImage() => $_ensure(2);

  /// A grid's tiles, row by row.
  @$pb.TagNumber(4)
  $core.int get rows => $_getIZ(3);
  @$pb.TagNumber(4)
  set rows($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRows() => $_has(3);
  @$pb.TagNumber(4)
  void clearRows() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get columns => $_getIZ(4);
  @$pb.TagNumber(5)
  set columns($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasColumns() => $_has(4);
  @$pb.TagNumber(5)
  void clearColumns() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<HeifImage> get tiles => $_getList(5);

  @$pb.TagNumber(7)
  HeifClap get clap => $_getN(6);
  @$pb.TagNumber(7)
  set clap(HeifClap value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasClap() => $_has(6);
  @$pb.TagNumber(7)
  void clearClap() => $_clearField(7);
  @$pb.TagNumber(7)
  HeifClap ensureClap() => $_ensure(6);

  /// irot: quarter turns anticlockwise.
  @$pb.TagNumber(8)
  $core.int get rotation => $_getIZ(7);
  @$pb.TagNumber(8)
  set rotation($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasRotation() => $_has(7);
  @$pb.TagNumber(8)
  void clearRotation() => $_clearField(8);

  /// imir: 0 mirrors top to bottom, 1 left to right.
  @$pb.TagNumber(9)
  $core.int get mirror => $_getIZ(8);
  @$pb.TagNumber(9)
  set mirror($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasMirror() => $_has(8);
  @$pb.TagNumber(9)
  void clearMirror() => $_clearField(9);
}

/// One coded image, a keyframe.
class HeifImage extends $pb.GeneratedMessage {
  factory HeifImage({
    HeifCodec? codec,
    $core.String? codecString,
    $core.List<$core.int>? config,
    $core.int? width,
    $core.int? height,
    $core.Iterable<$0.ByteSpan>? spans,
  }) {
    final result = HeifImage._();
    if (codec != null) result.codec = codec;
    if (codecString != null) result.codecString = codecString;
    if (config != null) result.config = config;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (spans != null) result.spans.addAll(spans);
    return result;
  }

  HeifImage._();

  factory HeifImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeifImage()..mergeFromBuffer(data, registry);
  factory HeifImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeifImage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HeifImage',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: HeifImage.$_createMessage)
    ..aE<HeifCodec>(1, _omitFieldNames ? '' : 'codec',
        enumValues: HeifCodec.values)
    ..aOS(2, _omitFieldNames ? '' : 'codecString')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'config', $pb.PbFieldType.OY)
    ..aI(4, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..pPM<$0.ByteSpan>(6, _omitFieldNames ? '' : 'spans',
        subBuilder: $0.ByteSpan.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeifImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeifImage copyWith(void Function(HeifImage) updates) =>
      super.copyWith((message) => updates(message as HeifImage)) as HeifImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HeifImage() / HeifImage.new instead')
  static HeifImage create() => HeifImage._();
  static $pb.GeneratedMessage $_createMessage() => HeifImage._();
  @$core.override
  HeifImage createEmptyInstance() => HeifImage._();
  @$core.pragma('dart2js:noInline')
  static HeifImage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HeifImage>(HeifImage.$_createMessage);
  static HeifImage? _defaultInstance;

  @$pb.TagNumber(1)
  HeifCodec get codec => $_getN(0);
  @$pb.TagNumber(1)
  set codec(HeifCodec value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCodec() => $_has(0);
  @$pb.TagNumber(1)
  void clearCodec() => $_clearField(1);

  /// The WebCodecs codec string, e.g. "hvc1.1.6.L93.B0", "av01.0.04M.08" or "avc1.640028".
  @$pb.TagNumber(2)
  $core.String get codecString => $_getSZ(1);
  @$pb.TagNumber(2)
  set codecString($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCodecString() => $_has(1);
  @$pb.TagNumber(2)
  void clearCodecString() => $_clearField(2);

  /// The payload of the hvcC, av1C or avcC box: WebCodecs' description.
  @$pb.TagNumber(3)
  $core.List<$core.int> get config => $_getN(2);
  @$pb.TagNumber(3)
  set config($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConfig() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfig() => $_clearField(3);

  /// The image's own size (ispe).
  @$pb.TagNumber(4)
  $core.int get width => $_getIZ(3);
  @$pb.TagNumber(4)
  set width($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasWidth() => $_has(3);
  @$pb.TagNumber(4)
  void clearWidth() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get height => $_getIZ(4);
  @$pb.TagNumber(5)
  set height($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeight() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeight() => $_clearField(5);

  /// Where its bytes are in the file (an item may have several extents; concatenate them).
  @$pb.TagNumber(6)
  $pb.PbList<$0.ByteSpan> get spans => $_getList(5);
}

/// Clean aperture (clap): the displayed size and the centre's offset from the image's centre, each a fraction.
class HeifClap extends $pb.GeneratedMessage {
  factory HeifClap({
    $core.int? widthNum,
    $core.int? widthDen,
    $core.int? heightNum,
    $core.int? heightDen,
    $core.int? xNum,
    $core.int? xDen,
    $core.int? yNum,
    $core.int? yDen,
  }) {
    final result = HeifClap._();
    if (widthNum != null) result.widthNum = widthNum;
    if (widthDen != null) result.widthDen = widthDen;
    if (heightNum != null) result.heightNum = heightNum;
    if (heightDen != null) result.heightDen = heightDen;
    if (xNum != null) result.xNum = xNum;
    if (xDen != null) result.xDen = xDen;
    if (yNum != null) result.yNum = yNum;
    if (yDen != null) result.yDen = yDen;
    return result;
  }

  HeifClap._();

  factory HeifClap.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeifClap()..mergeFromBuffer(data, registry);
  factory HeifClap.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HeifClap()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HeifClap',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: HeifClap.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'widthNum', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'widthDen', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'heightNum', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'heightDen', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'xNum')
    ..aI(6, _omitFieldNames ? '' : 'xDen', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'yNum')
    ..aI(8, _omitFieldNames ? '' : 'yDen', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeifClap clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeifClap copyWith(void Function(HeifClap) updates) =>
      super.copyWith((message) => updates(message as HeifClap)) as HeifClap;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HeifClap() / HeifClap.new instead')
  static HeifClap create() => HeifClap._();
  static $pb.GeneratedMessage $_createMessage() => HeifClap._();
  @$core.override
  HeifClap createEmptyInstance() => HeifClap._();
  @$core.pragma('dart2js:noInline')
  static HeifClap getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HeifClap>(HeifClap.$_createMessage);
  static HeifClap? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get widthNum => $_getIZ(0);
  @$pb.TagNumber(1)
  set widthNum($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWidthNum() => $_has(0);
  @$pb.TagNumber(1)
  void clearWidthNum() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get widthDen => $_getIZ(1);
  @$pb.TagNumber(2)
  set widthDen($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWidthDen() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidthDen() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get heightNum => $_getIZ(2);
  @$pb.TagNumber(3)
  set heightNum($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeightNum() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeightNum() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get heightDen => $_getIZ(3);
  @$pb.TagNumber(4)
  set heightDen($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeightDen() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeightDen() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get xNum => $_getIZ(4);
  @$pb.TagNumber(5)
  set xNum($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasXNum() => $_has(4);
  @$pb.TagNumber(5)
  void clearXNum() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get xDen => $_getIZ(5);
  @$pb.TagNumber(6)
  set xDen($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasXDen() => $_has(5);
  @$pb.TagNumber(6)
  void clearXDen() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get yNum => $_getIZ(6);
  @$pb.TagNumber(7)
  set yNum($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasYNum() => $_has(6);
  @$pb.TagNumber(7)
  void clearYNum() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get yDen => $_getIZ(7);
  @$pb.TagNumber(8)
  set yDen($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasYDen() => $_has(7);
  @$pb.TagNumber(8)
  void clearYDen() => $_clearField(8);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
