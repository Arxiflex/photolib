// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/metadata.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import '../../model/v1/capture_time.pb.dart' as $0;
import 'metadata.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'metadata.pbenum.dart';

/// Reads the metadata embedded in an image or a video, or an XMP sidecar on its own: EXIF, XMP and IPTC IIM in JPEG,
/// TIFF (DNG and the TIFF-based RAW formats among them), HEIC, AVIF, PNG, WebP and GIF; the boxes of ISOBMFF and
/// QuickTime movies; AVI's headers. Damaged data is skipped, never an error.
class ReadMetadataRequest extends $pb.GeneratedMessage {
  factory ReadMetadataRequest({
    $core.Iterable<FileRange>? ranges,
    $fixnum.Int64? size,
  }) {
    final result = ReadMetadataRequest._();
    if (ranges != null) result.ranges.addAll(ranges);
    if (size != null) result.size = size;
    return result;
  }

  ReadMetadataRequest._();

  factory ReadMetadataRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadMetadataRequest()..mergeFromBuffer(data, registry);
  factory ReadMetadataRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadMetadataRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadMetadataRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ReadMetadataRequest.$_createMessage)
    ..pPM<FileRange>(1, _omitFieldNames ? '' : 'ranges',
        subBuilder: FileRange.$_createMessage)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'size', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadMetadataRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadMetadataRequest copyWith(void Function(ReadMetadataRequest) updates) =>
      super.copyWith((message) => updates(message as ReadMetadataRequest))
          as ReadMetadataRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ReadMetadataRequest() / ReadMetadataRequest.new instead')
  static ReadMetadataRequest create() => ReadMetadataRequest._();
  static $pb.GeneratedMessage $_createMessage() => ReadMetadataRequest._();
  @$core.override
  ReadMetadataRequest createEmptyInstance() => ReadMetadataRequest._();
  @$core.pragma('dart2js:noInline')
  static ReadMetadataRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadMetadataRequest>(
          ReadMetadataRequest.$_createMessage);
  static ReadMetadataRequest? _defaultInstance;

  /// Pieces of the file at their offsets, usually just its first 64 KiB; nothing is assumed about the bytes between.
  @$pb.TagNumber(1)
  $pb.PbList<FileRange> get ranges => $_getList(0);

  /// The file's length in bytes, 0 when unknown: what is found from the end of a file, such as a motion photo's video,
  /// needs it.
  @$pb.TagNumber(2)
  $fixnum.Int64 get size => $_getI64(1);
  @$pb.TagNumber(2)
  set size($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearSize() => $_clearField(2);
}

/// Bytes of a file from an offset.
class FileRange extends $pb.GeneratedMessage {
  factory FileRange({
    $fixnum.Int64? offset,
    $core.List<$core.int>? data,
  }) {
    final result = FileRange._();
    if (offset != null) result.offset = offset;
    if (data != null) result.data = data;
    return result;
  }

  FileRange._();

  factory FileRange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FileRange()..mergeFromBuffer(data, registry);
  factory FileRange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FileRange()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FileRange',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: FileRange.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileRange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FileRange copyWith(void Function(FileRange) updates) =>
      super.copyWith((message) => updates(message as FileRange)) as FileRange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FileRange() / FileRange.new instead')
  static FileRange create() => FileRange._();
  static $pb.GeneratedMessage $_createMessage() => FileRange._();
  @$core.override
  FileRange createEmptyInstance() => FileRange._();
  @$core.pragma('dart2js:noInline')
  static FileRange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FileRange>(FileRange.$_createMessage);
  static FileRange? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get offset => $_getI64(0);
  @$pb.TagNumber(1)
  set offset($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOffset() => $_has(0);
  @$pb.TagNumber(1)
  void clearOffset() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get data => $_getN(1);
  @$pb.TagNumber(2)
  set data($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => $_clearField(2);
}

/// A span of a file.
class ByteSpan extends $pb.GeneratedMessage {
  factory ByteSpan({
    $fixnum.Int64? offset,
    $fixnum.Int64? length,
  }) {
    final result = ByteSpan._();
    if (offset != null) result.offset = offset;
    if (length != null) result.length = length;
    return result;
  }

  ByteSpan._();

  factory ByteSpan.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ByteSpan()..mergeFromBuffer(data, registry);
  factory ByteSpan.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ByteSpan()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ByteSpan',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ByteSpan.$_createMessage)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'length', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ByteSpan clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ByteSpan copyWith(void Function(ByteSpan) updates) =>
      super.copyWith((message) => updates(message as ByteSpan)) as ByteSpan;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ByteSpan() / ByteSpan.new instead')
  static ByteSpan create() => ByteSpan._();
  static $pb.GeneratedMessage $_createMessage() => ByteSpan._();
  @$core.override
  ByteSpan createEmptyInstance() => ByteSpan._();
  @$core.pragma('dart2js:noInline')
  static ByteSpan getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ByteSpan>(ByteSpan.$_createMessage);
  static ByteSpan? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get offset => $_getI64(0);
  @$pb.TagNumber(1)
  set offset($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOffset() => $_has(0);
  @$pb.TagNumber(1)
  void clearOffset() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get length => $_getI64(1);
  @$pb.TagNumber(2)
  set length($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLength() => $_has(1);
  @$pb.TagNumber(2)
  void clearLength() => $_clearField(2);
}

/// What the file says about itself. Where its EXIF, XMP and IIM disagree, the rules of the Metadata Working Group
/// pick one value: EXIF first, then XMP or IIM as the IPTC digest decides. Every date is kept.
class ReadMetadataResponse extends $pb.GeneratedMessage {
  factory ReadMetadataResponse({
    FileFormat? format,
    $core.int? width,
    $core.int? height,
    $core.int? orientation,
    $core.String? make,
    $core.String? model,
    GeoPoint? location,
    $core.Iterable<$0.CaptureTime>? times,
    $core.String? title,
    $core.String? description,
    $core.Iterable<$core.String>? keywords,
    $core.Iterable<KeywordPath>? keywordPaths,
    $core.int? rating,
    $core.String? label,
    $core.Iterable<$core.String>? creators,
    $core.String? copyright,
    $core.String? city,
    $core.String? state,
    $core.String? country,
    $core.Iterable<ImageRegion>? regions,
    Panorama? panorama,
    MotionPhotoMarkers? motionPhoto,
    $core.Iterable<ByteSpan>? missing,
    $fixnum.Int64? durationMs,
    $core.String? codec,
    $core.int? transfer,
    $core.bool? dolbyVision,
    StereoMode? stereoMode,
    $core.String? contentIdentifier,
    $core.String? burstId,
    ByteSpan? motionVideo,
    ByteSpan? preview,
    $core.double? frameRate,
    $core.bool? spatial,
    $core.bool? depth,
    Pace? pace,
    ByteSpan? largestPreview,
    $core.bool? gainMap,
  }) {
    final result = ReadMetadataResponse._();
    if (format != null) result.format = format;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (orientation != null) result.orientation = orientation;
    if (make != null) result.make = make;
    if (model != null) result.model = model;
    if (location != null) result.location = location;
    if (times != null) result.times.addAll(times);
    if (title != null) result.title = title;
    if (description != null) result.description = description;
    if (keywords != null) result.keywords.addAll(keywords);
    if (keywordPaths != null) result.keywordPaths.addAll(keywordPaths);
    if (rating != null) result.rating = rating;
    if (label != null) result.label = label;
    if (creators != null) result.creators.addAll(creators);
    if (copyright != null) result.copyright = copyright;
    if (city != null) result.city = city;
    if (state != null) result.state = state;
    if (country != null) result.country = country;
    if (regions != null) result.regions.addAll(regions);
    if (panorama != null) result.panorama = panorama;
    if (motionPhoto != null) result.motionPhoto = motionPhoto;
    if (missing != null) result.missing.addAll(missing);
    if (durationMs != null) result.durationMs = durationMs;
    if (codec != null) result.codec = codec;
    if (transfer != null) result.transfer = transfer;
    if (dolbyVision != null) result.dolbyVision = dolbyVision;
    if (stereoMode != null) result.stereoMode = stereoMode;
    if (contentIdentifier != null) result.contentIdentifier = contentIdentifier;
    if (burstId != null) result.burstId = burstId;
    if (motionVideo != null) result.motionVideo = motionVideo;
    if (preview != null) result.preview = preview;
    if (frameRate != null) result.frameRate = frameRate;
    if (spatial != null) result.spatial = spatial;
    if (depth != null) result.depth = depth;
    if (pace != null) result.pace = pace;
    if (largestPreview != null) result.largestPreview = largestPreview;
    if (gainMap != null) result.gainMap = gainMap;
    return result;
  }

  ReadMetadataResponse._();

  factory ReadMetadataResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadMetadataResponse()..mergeFromBuffer(data, registry);
  factory ReadMetadataResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadMetadataResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadMetadataResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ReadMetadataResponse.$_createMessage)
    ..aE<FileFormat>(1, _omitFieldNames ? '' : 'format',
        enumValues: FileFormat.values)
    ..aI(2, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'orientation',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(5, _omitFieldNames ? '' : 'make')
    ..aOS(6, _omitFieldNames ? '' : 'model')
    ..aOM<GeoPoint>(7, _omitFieldNames ? '' : 'location',
        subBuilder: GeoPoint.$_createMessage)
    ..pPM<$0.CaptureTime>(8, _omitFieldNames ? '' : 'times',
        subBuilder: $0.CaptureTime.$_createMessage)
    ..aOS(9, _omitFieldNames ? '' : 'title')
    ..aOS(10, _omitFieldNames ? '' : 'description')
    ..pPS(11, _omitFieldNames ? '' : 'keywords')
    ..pPM<KeywordPath>(12, _omitFieldNames ? '' : 'keywordPaths',
        subBuilder: KeywordPath.$_createMessage)
    ..aI(13, _omitFieldNames ? '' : 'rating', fieldType: $pb.PbFieldType.OS3)
    ..aOS(14, _omitFieldNames ? '' : 'label')
    ..pPS(15, _omitFieldNames ? '' : 'creators')
    ..aOS(16, _omitFieldNames ? '' : 'copyright')
    ..aOS(17, _omitFieldNames ? '' : 'city')
    ..aOS(18, _omitFieldNames ? '' : 'state')
    ..aOS(19, _omitFieldNames ? '' : 'country')
    ..pPM<ImageRegion>(20, _omitFieldNames ? '' : 'regions',
        subBuilder: ImageRegion.$_createMessage)
    ..aOM<Panorama>(21, _omitFieldNames ? '' : 'panorama',
        subBuilder: Panorama.$_createMessage)
    ..aOM<MotionPhotoMarkers>(22, _omitFieldNames ? '' : 'motionPhoto',
        subBuilder: MotionPhotoMarkers.$_createMessage)
    ..pPM<ByteSpan>(23, _omitFieldNames ? '' : 'missing',
        subBuilder: ByteSpan.$_createMessage)
    ..a<$fixnum.Int64>(
        24, _omitFieldNames ? '' : 'durationMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(25, _omitFieldNames ? '' : 'codec')
    ..aI(26, _omitFieldNames ? '' : 'transfer', fieldType: $pb.PbFieldType.OU3)
    ..aOB(27, _omitFieldNames ? '' : 'dolbyVision')
    ..aE<StereoMode>(28, _omitFieldNames ? '' : 'stereoMode',
        enumValues: StereoMode.values)
    ..aOS(29, _omitFieldNames ? '' : 'contentIdentifier')
    ..aOS(30, _omitFieldNames ? '' : 'burstId')
    ..aOM<ByteSpan>(31, _omitFieldNames ? '' : 'motionVideo',
        subBuilder: ByteSpan.$_createMessage)
    ..aOM<ByteSpan>(32, _omitFieldNames ? '' : 'preview',
        subBuilder: ByteSpan.$_createMessage)
    ..aD(33, _omitFieldNames ? '' : 'frameRate')
    ..aOB(34, _omitFieldNames ? '' : 'spatial')
    ..aOB(35, _omitFieldNames ? '' : 'depth')
    ..aE<Pace>(36, _omitFieldNames ? '' : 'pace', enumValues: Pace.values)
    ..aOM<ByteSpan>(37, _omitFieldNames ? '' : 'largestPreview',
        subBuilder: ByteSpan.$_createMessage)
    ..aOB(38, _omitFieldNames ? '' : 'gainMap')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadMetadataResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadMetadataResponse copyWith(void Function(ReadMetadataResponse) updates) =>
      super.copyWith((message) => updates(message as ReadMetadataResponse))
          as ReadMetadataResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReadMetadataResponse() / ReadMetadataResponse.new instead')
  static ReadMetadataResponse create() => ReadMetadataResponse._();
  static $pb.GeneratedMessage $_createMessage() => ReadMetadataResponse._();
  @$core.override
  ReadMetadataResponse createEmptyInstance() => ReadMetadataResponse._();
  @$core.pragma('dart2js:noInline')
  static ReadMetadataResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadMetadataResponse>(
          ReadMetadataResponse.$_createMessage);
  static ReadMetadataResponse? _defaultInstance;

  /// The container the magic bytes name, whatever the file's extension.
  @$pb.TagNumber(1)
  FileFormat get format => $_getN(0);
  @$pb.TagNumber(1)
  set format(FileFormat value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFormat() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormat() => $_clearField(1);

  /// Stored pixels, before orientation (a video's sample size); 0 when unknown.
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

  /// EXIF numbering, 1 to 8, which HEIF's irot and imir and a video track's matrix also map onto; 0 when the file has
  /// none, and for a video that is not turned.
  @$pb.TagNumber(4)
  $core.int get orientation => $_getIZ(3);
  @$pb.TagNumber(4)
  set orientation($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOrientation() => $_has(3);
  @$pb.TagNumber(4)
  void clearOrientation() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get make => $_getSZ(4);
  @$pb.TagNumber(5)
  set make($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMake() => $_has(4);
  @$pb.TagNumber(5)
  void clearMake() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get model => $_getSZ(5);
  @$pb.TagNumber(6)
  set model($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasModel() => $_has(5);
  @$pb.TagNumber(6)
  void clearModel() => $_clearField(6);

  /// Absent when the file has none, and for 0,0.
  @$pb.TagNumber(7)
  GeoPoint get location => $_getN(6);
  @$pb.TagNumber(7)
  set location(GeoPoint value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasLocation() => $_has(6);
  @$pb.TagNumber(7)
  void clearLocation() => $_clearField(7);
  @$pb.TagNumber(7)
  GeoPoint ensureLocation() => $_ensure(6);

  /// Every date in the file as written, unchecked and unrated (confidence 0), for the capture-time resolver: values
  /// such as "0000-00-00T00:00:00" pass through, and local_datetime is empty when the text is no date at all. The
  /// source names the tag: "exif:DateTimeOriginal", "exif:CreateDate" and "exif:ModifyDate" with their SubSecTime and
  /// OffsetTime tags, "exif:GPSDateTime" (UTC, so offset 0), "xmp-exif:DateTimeOriginal", "xmp-photoshop:DateCreated",
  /// "xmp-xmp:CreateDate", "xmp-xmp:ModifyDate", "xmp-xmp:MetadataDate" and "iptc:DateCreated"; in movies
  /// "quicktime:CreationDate" (the key com.apple.quicktime.creationdate, with its offset), "quicktime:ContentCreateDate"
  /// (©day) and "quicktime:CreateDate" (mvhd, unless 0), which has no offset: UTC by the specification, it is the wall
  /// clock on many cameras.
  @$pb.TagNumber(8)
  $pb.PbList<$0.CaptureTime> get times => $_getList(7);

  @$pb.TagNumber(9)
  $core.String get title => $_getSZ(8);
  @$pb.TagNumber(9)
  set title($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTitle() => $_has(8);
  @$pb.TagNumber(9)
  void clearTitle() => $_clearField(9);

  /// Camera boilerplate such as "OLYMPUS DIGITAL CAMERA" counts as no description.
  @$pb.TagNumber(10)
  $core.String get description => $_getSZ(9);
  @$pb.TagNumber(10)
  set description($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDescription() => $_has(9);
  @$pb.TagNumber(10)
  void clearDescription() => $_clearField(10);

  /// Flat keywords: dc:subject or IIM Keywords.
  @$pb.TagNumber(11)
  $pb.PbList<$core.String> get keywords => $_getList(10);

  /// Hierarchical keywords from lr:hierarchicalSubject and digiKam:TagsList, without duplicates.
  @$pb.TagNumber(12)
  $pb.PbList<KeywordPath> get keywordPaths => $_getList(11);

  /// xmp:Rating: -1 for rejected, else 0 to 5 stars.
  @$pb.TagNumber(13)
  $core.int get rating => $_getIZ(12);
  @$pb.TagNumber(13)
  set rating($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasRating() => $_has(12);
  @$pb.TagNumber(13)
  void clearRating() => $_clearField(13);

  /// xmp:Label, the colour label, e.g. "Red".
  @$pb.TagNumber(14)
  $core.String get label => $_getSZ(13);
  @$pb.TagNumber(14)
  set label($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasLabel() => $_has(13);
  @$pb.TagNumber(14)
  void clearLabel() => $_clearField(14);

  @$pb.TagNumber(15)
  $pb.PbList<$core.String> get creators => $_getList(14);

  @$pb.TagNumber(16)
  $core.String get copyright => $_getSZ(15);
  @$pb.TagNumber(16)
  set copyright($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasCopyright() => $_has(15);
  @$pb.TagNumber(16)
  void clearCopyright() => $_clearField(16);

  /// Where the photo was taken, as text: photoshop:City, State and Country, or their IIM datasets.
  @$pb.TagNumber(17)
  $core.String get city => $_getSZ(16);
  @$pb.TagNumber(17)
  set city($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasCity() => $_has(16);
  @$pb.TagNumber(17)
  void clearCity() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get state => $_getSZ(17);
  @$pb.TagNumber(18)
  set state($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasState() => $_has(17);
  @$pb.TagNumber(18)
  void clearState() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get country => $_getSZ(18);
  @$pb.TagNumber(19)
  set country($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasCountry() => $_has(18);
  @$pb.TagNumber(19)
  void clearCountry() => $_clearField(19);

  /// mwg-rs regions, such as faces.
  @$pb.TagNumber(20)
  $pb.PbList<ImageRegion> get regions => $_getList(19);

  /// Present for photo spheres and 360° videos whose metadata says so (GPano, Spherical Video V2 or else V1), never
  /// guessed from the aspect ratio.
  @$pb.TagNumber(21)
  Panorama get panorama => $_getN(20);
  @$pb.TagNumber(21)
  set panorama(Panorama value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasPanorama() => $_has(20);
  @$pb.TagNumber(21)
  void clearPanorama() => $_clearField(21);
  @$pb.TagNumber(21)
  Panorama ensurePanorama() => $_ensure(20);

  /// Present when the XMP marks a motion photo.
  @$pb.TagNumber(22)
  MotionPhotoMarkers get motionPhoto => $_getN(21);
  @$pb.TagNumber(22)
  set motionPhoto(MotionPhotoMarkers value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasMotionPhoto() => $_has(21);
  @$pb.TagNumber(22)
  void clearMotionPhoto() => $_clearField(22);
  @$pb.TagNumber(22)
  MotionPhotoMarkers ensureMotionPhoto() => $_ensure(21);

  /// Spans the reader needed but was not given. Read them, as far as the file goes, and call again with every range,
  /// until no span that the file holds is missing.
  @$pb.TagNumber(23)
  $pb.PbList<ByteSpan> get missing => $_getList(22);

  /// A video's length; 0 for stills and when unknown.
  @$pb.TagNumber(24)
  $fixnum.Int64 get durationMs => $_getI64(23);
  @$pb.TagNumber(24)
  set durationMs($fixnum.Int64 value) => $_setInt64(23, value);
  @$pb.TagNumber(24)
  $core.bool hasDurationMs() => $_has(23);
  @$pb.TagNumber(24)
  void clearDurationMs() => $_clearField(24);

  /// A video's codec: "h264", "hevc", "av1", "vp9", "h263", "mjpeg", "prores", "xvid" (MPEG-4 Part 2) or "dv"; empty
  /// when unknown.
  @$pb.TagNumber(25)
  $core.String get codec => $_getSZ(24);
  @$pb.TagNumber(25)
  set codec($core.String value) => $_setString(24, value);
  @$pb.TagNumber(25)
  $core.bool hasCodec() => $_has(24);
  @$pb.TagNumber(25)
  void clearCodec() => $_clearField(25);

  /// The colour's transfer characteristics as ITU-T H.273 numbers them, from a colr box: 16 is PQ and 18 is HLG, the HDR
  /// ones; 0 when the file does not say.
  @$pb.TagNumber(26)
  $core.int get transfer => $_getIZ(25);
  @$pb.TagNumber(26)
  set transfer($core.int value) => $_setUnsignedInt32(25, value);
  @$pb.TagNumber(26)
  $core.bool hasTransfer() => $_has(25);
  @$pb.TagNumber(26)
  void clearTransfer() => $_clearField(26);

  /// A video track has a Dolby Vision configuration.
  @$pb.TagNumber(27)
  $core.bool get dolbyVision => $_getBF(26);
  @$pb.TagNumber(27)
  set dolbyVision($core.bool value) => $_setBool(26, value);
  @$pb.TagNumber(27)
  $core.bool hasDolbyVision() => $_has(26);
  @$pb.TagNumber(27)
  void clearDolbyVision() => $_clearField(27);

  /// How a stereoscopic video packs its two views (Spherical Video V2's st3d, or V1's StereoMode).
  @$pb.TagNumber(28)
  StereoMode get stereoMode => $_getN(27);
  @$pb.TagNumber(28)
  set stereoMode(StereoMode value) => $_setField(28, value);
  @$pb.TagNumber(28)
  $core.bool hasStereoMode() => $_has(27);
  @$pb.TagNumber(28)
  void clearStereoMode() => $_clearField(28);

  /// The identifier that a Live Photo's still and video share: Apple's MakerNote ContentIdentifier, or the QuickTime
  /// key com.apple.quicktime.content.identifier.
  @$pb.TagNumber(29)
  $core.String get contentIdentifier => $_getSZ(28);
  @$pb.TagNumber(29)
  set contentIdentifier($core.String value) => $_setString(28, value);
  @$pb.TagNumber(29)
  $core.bool hasContentIdentifier() => $_has(28);
  @$pb.TagNumber(29)
  void clearContentIdentifier() => $_clearField(29);

  /// The burst the photo belongs to: Apple's MakerNote BurstUUID or Google's Camera:BurstID.
  @$pb.TagNumber(30)
  $core.String get burstId => $_getSZ(29);
  @$pb.TagNumber(30)
  set burstId($core.String value) => $_setString(29, value);
  @$pb.TagNumber(30)
  $core.bool hasBurstId() => $_has(29);
  @$pb.TagNumber(30)
  void clearBurstId() => $_clearField(30);

  /// Where a motion photo's video is, once found there: from the Container directory, MicroVideoOffset, HEIF's mpvd box
  /// or Samsung's trailer. It needs the request's size, and the markers alone are not enough: they can be stale.
  @$pb.TagNumber(31)
  ByteSpan get motionVideo => $_getN(30);
  @$pb.TagNumber(31)
  set motionVideo(ByteSpan value) => $_setField(31, value);
  @$pb.TagNumber(31)
  $core.bool hasMotionVideo() => $_has(30);
  @$pb.TagNumber(31)
  void clearMotionVideo() => $_clearField(31);
  @$pb.TagNumber(31)
  ByteSpan ensureMotionVideo() => $_ensure(30);

  /// The smallest JPEG the file holds as a picture of itself, which a host decodes long before the original (the
  /// thumbnails' T2.5): EXIF IFD1's thumbnail, a TIFF-based RAW's preview, RAF's JPEG or a HEIF thumbnail item coded as
  /// JPEG. Absent when there is none, or it does not fit in the request's size; its bytes are not asked for.
  @$pb.TagNumber(32)
  ByteSpan get preview => $_getN(31);
  @$pb.TagNumber(32)
  set preview(ByteSpan value) => $_setField(32, value);
  @$pb.TagNumber(32)
  $core.bool hasPreview() => $_has(31);
  @$pb.TagNumber(32)
  void clearPreview() => $_clearField(32);
  @$pb.TagNumber(32)
  ByteSpan ensurePreview() => $_ensure(31);

  /// A video's frames a second, on average: its first video track's samples over the track's length (stts and mdhd),
  /// or a million over AVI's microseconds a frame; 0 for stills and when unknown, as in a fragmented movie.
  @$pb.TagNumber(33)
  $core.double get frameRate => $_getN(32);
  @$pb.TagNumber(33)
  set frameRate($core.double value) => $_setDouble(32, value);
  @$pb.TagNumber(33)
  $core.bool hasFrameRate() => $_has(32);
  @$pb.TagNumber(33)
  void clearFrameRate() => $_clearField(33);

  /// The file holds a stereo pair, shown in 2D by its first view: a spatial photo (HEIF's ster entity group) or a
  /// spatial video (MV-HEVC, which Apple's vexu box or an lhvC configuration marks).
  @$pb.TagNumber(34)
  $core.bool get spatial => $_getBF(33);
  @$pb.TagNumber(34)
  set spatial($core.bool value) => $_setBool(33, value);
  @$pb.TagNumber(34)
  $core.bool hasSpatial() => $_has(33);
  @$pb.TagNumber(34)
  void clearSpatial() => $_clearField(34);

  /// The file keeps a depth map or a portrait matte beside its picture, for a refocus later: a HEIF auxiliary image of
  /// depth or Apple's portrait matte, GDepth's XMP, a Dynamic Depth item (a Container:Directory item of semantic
  /// "Depth") or Samsung's DepthMap_Data trailer block.
  @$pb.TagNumber(35)
  $core.bool get depth => $_getBF(34);
  @$pb.TagNumber(35)
  set depth($core.bool value) => $_setBool(34, value);
  @$pb.TagNumber(35)
  $core.bool hasDepth() => $_has(34);
  @$pb.TagNumber(35)
  void clearDepth() => $_clearField(35);

  /// How a video's time runs against the time it recorded.
  @$pb.TagNumber(36)
  Pace get pace => $_getN(35);
  @$pb.TagNumber(36)
  set pace(Pace value) => $_setField(36, value);
  @$pb.TagNumber(36)
  $core.bool hasPace() => $_has(35);
  @$pb.TagNumber(36)
  void clearPace() => $_clearField(36);

  /// The largest of the JPEGs that preview is the smallest of: a RAW's full-size preview or CR3's PRVW, which a host
  /// shows, turned by the file's orientation, where nothing decodes the RAW (docs/08 §2.1). Its bytes are not asked for.
  @$pb.TagNumber(37)
  ByteSpan get largestPreview => $_getN(36);
  @$pb.TagNumber(37)
  set largestPreview(ByteSpan value) => $_setField(37, value);
  @$pb.TagNumber(37)
  $core.bool hasLargestPreview() => $_has(36);
  @$pb.TagNumber(37)
  void clearLargestPreview() => $_clearField(37);
  @$pb.TagNumber(37)
  ByteSpan ensureLargestPreview() => $_ensure(36);

  /// The still carries a gain map that platform decoders apply for HDR headroom: Ultra HDR's (hdrgm:Version in the
  /// XMP), ISO 21496-1's (a JPEG's APP2, HEIF's tmap item) or Apple's (HEIF's auxiliary image). Samsung's SEF one is
  /// not: no platform applies it.
  @$pb.TagNumber(38)
  $core.bool get gainMap => $_getBF(37);
  @$pb.TagNumber(38)
  set gainMap($core.bool value) => $_setBool(37, value);
  @$pb.TagNumber(38)
  $core.bool hasGainMap() => $_has(37);
  @$pb.TagNumber(38)
  void clearGainMap() => $_clearField(38);
}

/// A position on the WGS 84 ellipsoid.
class GeoPoint extends $pb.GeneratedMessage {
  factory GeoPoint({
    $core.double? latitude,
    $core.double? longitude,
    $core.double? altitudeM,
  }) {
    final result = GeoPoint._();
    if (latitude != null) result.latitude = latitude;
    if (longitude != null) result.longitude = longitude;
    if (altitudeM != null) result.altitudeM = altitudeM;
    return result;
  }

  GeoPoint._();

  factory GeoPoint.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GeoPoint()..mergeFromBuffer(data, registry);
  factory GeoPoint.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GeoPoint()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GeoPoint',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: GeoPoint.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'latitude')
    ..aD(2, _omitFieldNames ? '' : 'longitude')
    ..aD(3, _omitFieldNames ? '' : 'altitudeM')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GeoPoint clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GeoPoint copyWith(void Function(GeoPoint) updates) =>
      super.copyWith((message) => updates(message as GeoPoint)) as GeoPoint;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GeoPoint() / GeoPoint.new instead')
  static GeoPoint create() => GeoPoint._();
  static $pb.GeneratedMessage $_createMessage() => GeoPoint._();
  @$core.override
  GeoPoint createEmptyInstance() => GeoPoint._();
  @$core.pragma('dart2js:noInline')
  static GeoPoint getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GeoPoint>(GeoPoint.$_createMessage);
  static GeoPoint? _defaultInstance;

  /// Degrees north, -90 to 90.
  @$pb.TagNumber(1)
  $core.double get latitude => $_getN(0);
  @$pb.TagNumber(1)
  set latitude($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatitude() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatitude() => $_clearField(1);

  /// Degrees east, -180 to 180.
  @$pb.TagNumber(2)
  $core.double get longitude => $_getN(1);
  @$pb.TagNumber(2)
  set longitude($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLongitude() => $_has(1);
  @$pb.TagNumber(2)
  void clearLongitude() => $_clearField(2);

  /// Metres above sea level.
  @$pb.TagNumber(3)
  $core.double get altitudeM => $_getN(2);
  @$pb.TagNumber(3)
  set altitudeM($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAltitudeM() => $_has(2);
  @$pb.TagNumber(3)
  void clearAltitudeM() => $_clearField(3);
}

/// One hierarchical keyword, root first: "Places|France|Paris" is ["Places", "France", "Paris"].
class KeywordPath extends $pb.GeneratedMessage {
  factory KeywordPath({
    $core.Iterable<$core.String>? nodes,
  }) {
    final result = KeywordPath._();
    if (nodes != null) result.nodes.addAll(nodes);
    return result;
  }

  KeywordPath._();

  factory KeywordPath.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KeywordPath()..mergeFromBuffer(data, registry);
  factory KeywordPath.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KeywordPath()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KeywordPath',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: KeywordPath.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'nodes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeywordPath clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeywordPath copyWith(void Function(KeywordPath) updates) =>
      super.copyWith((message) => updates(message as KeywordPath))
          as KeywordPath;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use KeywordPath() / KeywordPath.new instead')
  static KeywordPath create() => KeywordPath._();
  static $pb.GeneratedMessage $_createMessage() => KeywordPath._();
  @$core.override
  KeywordPath createEmptyInstance() => KeywordPath._();
  @$core.pragma('dart2js:noInline')
  static KeywordPath getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KeywordPath>(
          KeywordPath.$_createMessage);
  static KeywordPath? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get nodes => $_getList(0);
}

/// A named area of the image, in the displayed frame (orientation applied), from the top-left corner and normalised
/// to the image's width and height.
class ImageRegion extends $pb.GeneratedMessage {
  factory ImageRegion({
    $core.String? name,
    $core.String? type,
    $core.double? x,
    $core.double? y,
    $core.double? width,
    $core.double? height,
  }) {
    final result = ImageRegion._();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    return result;
  }

  ImageRegion._();

  factory ImageRegion.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageRegion()..mergeFromBuffer(data, registry);
  factory ImageRegion.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageRegion()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageRegion',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ImageRegion.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'type')
    ..aD(3, _omitFieldNames ? '' : 'x')
    ..aD(4, _omitFieldNames ? '' : 'y')
    ..aD(5, _omitFieldNames ? '' : 'width')
    ..aD(6, _omitFieldNames ? '' : 'height')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageRegion clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageRegion copyWith(void Function(ImageRegion) updates) =>
      super.copyWith((message) => updates(message as ImageRegion))
          as ImageRegion;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageRegion() / ImageRegion.new instead')
  static ImageRegion create() => ImageRegion._();
  static $pb.GeneratedMessage $_createMessage() => ImageRegion._();
  @$core.override
  ImageRegion createEmptyInstance() => ImageRegion._();
  @$core.pragma('dart2js:noInline')
  static ImageRegion getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ImageRegion>(
          ImageRegion.$_createMessage);
  static ImageRegion? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// The mwg-rs type: "Face", "Pet", "Focus" or "BarCode".
  @$pb.TagNumber(2)
  $core.String get type => $_getSZ(1);
  @$pb.TagNumber(2)
  set type($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get x => $_getN(2);
  @$pb.TagNumber(3)
  set x($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasX() => $_has(2);
  @$pb.TagNumber(3)
  void clearX() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get y => $_getN(3);
  @$pb.TagNumber(4)
  set y($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasY() => $_has(3);
  @$pb.TagNumber(4)
  void clearY() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get width => $_getN(4);
  @$pb.TagNumber(5)
  set width($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasWidth() => $_has(4);
  @$pb.TagNumber(5)
  void clearWidth() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get height => $_getN(5);
  @$pb.TagNumber(6)
  set height($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHeight() => $_has(5);
  @$pb.TagNumber(6)
  void clearHeight() => $_clearField(6);
}

/// A photo sphere's or 360° video's projection; for a sphere, where its pixels lie in the full panorama (GPano).
class Panorama extends $pb.GeneratedMessage {
  factory Panorama({
    $core.String? projection,
    $core.bool? usePanoramaViewer,
    $core.int? fullWidth,
    $core.int? fullHeight,
    $core.int? croppedLeft,
    $core.int? croppedTop,
    $core.int? croppedWidth,
    $core.int? croppedHeight,
    $core.double? poseHeadingDegrees,
  }) {
    final result = Panorama._();
    if (projection != null) result.projection = projection;
    if (usePanoramaViewer != null) result.usePanoramaViewer = usePanoramaViewer;
    if (fullWidth != null) result.fullWidth = fullWidth;
    if (fullHeight != null) result.fullHeight = fullHeight;
    if (croppedLeft != null) result.croppedLeft = croppedLeft;
    if (croppedTop != null) result.croppedTop = croppedTop;
    if (croppedWidth != null) result.croppedWidth = croppedWidth;
    if (croppedHeight != null) result.croppedHeight = croppedHeight;
    if (poseHeadingDegrees != null)
      result.poseHeadingDegrees = poseHeadingDegrees;
    return result;
  }

  Panorama._();

  factory Panorama.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Panorama()..mergeFromBuffer(data, registry);
  factory Panorama.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Panorama()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Panorama',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Panorama.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'projection')
    ..aOB(2, _omitFieldNames ? '' : 'usePanoramaViewer')
    ..aI(3, _omitFieldNames ? '' : 'fullWidth', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'fullHeight', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'croppedLeft',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'croppedTop', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'croppedWidth',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(8, _omitFieldNames ? '' : 'croppedHeight',
        fieldType: $pb.PbFieldType.OU3)
    ..aD(9, _omitFieldNames ? '' : 'poseHeadingDegrees')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Panorama clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Panorama copyWith(void Function(Panorama) updates) =>
      super.copyWith((message) => updates(message as Panorama)) as Panorama;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Panorama() / Panorama.new instead')
  static Panorama create() => Panorama._();
  static $pb.GeneratedMessage $_createMessage() => Panorama._();
  @$core.override
  Panorama createEmptyInstance() => Panorama._();
  @$core.pragma('dart2js:noInline')
  static Panorama getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Panorama>(Panorama.$_createMessage);
  static Panorama? _defaultInstance;

  /// GPano:ProjectionType, e.g. "equirectangular"; for a video "equirectangular", "cubemap" or "mesh".
  @$pb.TagNumber(1)
  $core.String get projection => $_getSZ(0);
  @$pb.TagNumber(1)
  set projection($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProjection() => $_has(0);
  @$pb.TagNumber(1)
  void clearProjection() => $_clearField(1);

  /// GPano:UsePanoramaViewer; absent when not set, which viewers read as true.
  @$pb.TagNumber(2)
  $core.bool get usePanoramaViewer => $_getBF(1);
  @$pb.TagNumber(2)
  set usePanoramaViewer($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsePanoramaViewer() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsePanoramaViewer() => $_clearField(2);

  /// GPano's pixels; for a video, from its Spherical Video V2 projection bounds, and 0 when it has none.
  @$pb.TagNumber(3)
  $core.int get fullWidth => $_getIZ(2);
  @$pb.TagNumber(3)
  set fullWidth($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFullWidth() => $_has(2);
  @$pb.TagNumber(3)
  void clearFullWidth() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get fullHeight => $_getIZ(3);
  @$pb.TagNumber(4)
  set fullHeight($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFullHeight() => $_has(3);
  @$pb.TagNumber(4)
  void clearFullHeight() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get croppedLeft => $_getIZ(4);
  @$pb.TagNumber(5)
  set croppedLeft($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCroppedLeft() => $_has(4);
  @$pb.TagNumber(5)
  void clearCroppedLeft() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get croppedTop => $_getIZ(5);
  @$pb.TagNumber(6)
  set croppedTop($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCroppedTop() => $_has(5);
  @$pb.TagNumber(6)
  void clearCroppedTop() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get croppedWidth => $_getIZ(6);
  @$pb.TagNumber(7)
  set croppedWidth($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCroppedWidth() => $_has(6);
  @$pb.TagNumber(7)
  void clearCroppedWidth() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get croppedHeight => $_getIZ(7);
  @$pb.TagNumber(8)
  set croppedHeight($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCroppedHeight() => $_has(7);
  @$pb.TagNumber(8)
  void clearCroppedHeight() => $_clearField(8);

  /// GPano:PoseHeadingDegrees: the compass heading of the full panorama's middle, in degrees clockwise from true north,
  /// in [0, 360); absent when not given.
  @$pb.TagNumber(9)
  $core.double get poseHeadingDegrees => $_getN(8);
  @$pb.TagNumber(9)
  set poseHeadingDegrees($core.double value) => $_setDouble(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPoseHeadingDegrees() => $_has(8);
  @$pb.TagNumber(9)
  void clearPoseHeadingDegrees() => $_clearField(9);
}

/// The XMP markers of a Google or Samsung motion photo, which say where its video is. They can be stale: the video
/// must still be found.
class MotionPhotoMarkers extends $pb.GeneratedMessage {
  factory MotionPhotoMarkers({
    $core.bool? motionPhoto,
    $core.int? version,
    $fixnum.Int64? presentationTimestampUs,
    $core.bool? microVideo,
    $fixnum.Int64? microVideoOffsetBytes,
    $core.Iterable<ContainerItem>? items,
  }) {
    final result = MotionPhotoMarkers._();
    if (motionPhoto != null) result.motionPhoto = motionPhoto;
    if (version != null) result.version = version;
    if (presentationTimestampUs != null)
      result.presentationTimestampUs = presentationTimestampUs;
    if (microVideo != null) result.microVideo = microVideo;
    if (microVideoOffsetBytes != null)
      result.microVideoOffsetBytes = microVideoOffsetBytes;
    if (items != null) result.items.addAll(items);
    return result;
  }

  MotionPhotoMarkers._();

  factory MotionPhotoMarkers.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MotionPhotoMarkers()..mergeFromBuffer(data, registry);
  factory MotionPhotoMarkers.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MotionPhotoMarkers()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MotionPhotoMarkers',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MotionPhotoMarkers.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'motionPhoto')
    ..aI(2, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..aInt64(3, _omitFieldNames ? '' : 'presentationTimestampUs')
    ..aOB(4, _omitFieldNames ? '' : 'microVideo')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'microVideoOffsetBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<ContainerItem>(6, _omitFieldNames ? '' : 'items',
        subBuilder: ContainerItem.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MotionPhotoMarkers clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MotionPhotoMarkers copyWith(void Function(MotionPhotoMarkers) updates) =>
      super.copyWith((message) => updates(message as MotionPhotoMarkers))
          as MotionPhotoMarkers;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MotionPhotoMarkers() / MotionPhotoMarkers.new instead')
  static MotionPhotoMarkers create() => MotionPhotoMarkers._();
  static $pb.GeneratedMessage $_createMessage() => MotionPhotoMarkers._();
  @$core.override
  MotionPhotoMarkers createEmptyInstance() => MotionPhotoMarkers._();
  @$core.pragma('dart2js:noInline')
  static MotionPhotoMarkers getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MotionPhotoMarkers>(
          MotionPhotoMarkers.$_createMessage);
  static MotionPhotoMarkers? _defaultInstance;

  /// Camera:MotionPhoto is 1.
  @$pb.TagNumber(1)
  $core.bool get motionPhoto => $_getBF(0);
  @$pb.TagNumber(1)
  set motionPhoto($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMotionPhoto() => $_has(0);
  @$pb.TagNumber(1)
  void clearMotionPhoto() => $_clearField(1);

  /// Camera:MotionPhotoVersion.
  @$pb.TagNumber(2)
  $core.int get version => $_getIZ(1);
  @$pb.TagNumber(2)
  set version($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearVersion() => $_clearField(2);

  /// Camera:MotionPhotoPresentationTimestampUs or MicroVideoPresentationTimestampUs: the frame the still shows.
  @$pb.TagNumber(3)
  $fixnum.Int64 get presentationTimestampUs => $_getI64(2);
  @$pb.TagNumber(3)
  set presentationTimestampUs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPresentationTimestampUs() => $_has(2);
  @$pb.TagNumber(3)
  void clearPresentationTimestampUs() => $_clearField(3);

  /// The legacy Camera:MicroVideo is 1.
  @$pb.TagNumber(4)
  $core.bool get microVideo => $_getBF(3);
  @$pb.TagNumber(4)
  set microVideo($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMicroVideo() => $_has(3);
  @$pb.TagNumber(4)
  void clearMicroVideo() => $_clearField(4);

  /// Camera:MicroVideoOffset: where the video starts, counted back from the end of the file.
  @$pb.TagNumber(5)
  $fixnum.Int64 get microVideoOffsetBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set microVideoOffsetBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMicroVideoOffsetBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearMicroVideoOffsetBytes() => $_clearField(5);

  /// Container:Directory, in file order, the primary image first.
  @$pb.TagNumber(6)
  $pb.PbList<ContainerItem> get items => $_getList(5);
}

/// A file appended to the primary image, from a Container:Directory.
class ContainerItem extends $pb.GeneratedMessage {
  factory ContainerItem({
    $core.String? mime,
    $core.String? semantic,
    $fixnum.Int64? lengthBytes,
    $fixnum.Int64? paddingBytes,
  }) {
    final result = ContainerItem._();
    if (mime != null) result.mime = mime;
    if (semantic != null) result.semantic = semantic;
    if (lengthBytes != null) result.lengthBytes = lengthBytes;
    if (paddingBytes != null) result.paddingBytes = paddingBytes;
    return result;
  }

  ContainerItem._();

  factory ContainerItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ContainerItem()..mergeFromBuffer(data, registry);
  factory ContainerItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ContainerItem()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ContainerItem',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ContainerItem.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'mime')
    ..aOS(2, _omitFieldNames ? '' : 'semantic')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'lengthBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'paddingBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ContainerItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ContainerItem copyWith(void Function(ContainerItem) updates) =>
      super.copyWith((message) => updates(message as ContainerItem))
          as ContainerItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ContainerItem() / ContainerItem.new instead')
  static ContainerItem create() => ContainerItem._();
  static $pb.GeneratedMessage $_createMessage() => ContainerItem._();
  @$core.override
  ContainerItem createEmptyInstance() => ContainerItem._();
  @$core.pragma('dart2js:noInline')
  static ContainerItem getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContainerItem>(
          ContainerItem.$_createMessage);
  static ContainerItem? _defaultInstance;

  /// Item:Mime, e.g. "video/mp4".
  @$pb.TagNumber(1)
  $core.String get mime => $_getSZ(0);
  @$pb.TagNumber(1)
  set mime($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMime() => $_has(0);
  @$pb.TagNumber(1)
  void clearMime() => $_clearField(1);

  /// Item:Semantic, e.g. "Primary", "MotionPhoto" or "GainMap".
  @$pb.TagNumber(2)
  $core.String get semantic => $_getSZ(1);
  @$pb.TagNumber(2)
  set semantic($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSemantic() => $_has(1);
  @$pb.TagNumber(2)
  void clearSemantic() => $_clearField(2);

  /// Item:Length; 0 for the primary image.
  @$pb.TagNumber(3)
  $fixnum.Int64 get lengthBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set lengthBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLengthBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearLengthBytes() => $_clearField(3);

  /// Item:Padding, the bytes before the next item.
  @$pb.TagNumber(4)
  $fixnum.Int64 get paddingBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set paddingBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPaddingBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearPaddingBytes() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
