// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/develop.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../model/v1/capture_time.pb.dart' as $0;
import '../../model/v1/edit_recipe.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Renders an image with the adjustments of the editor rendering spike (roadmap M0-36, ADR-0054) on the CPU: the
/// reference renderer that every GPU path must match. The edit recipe of design 11 §2.2 replaces these messages.
class DevelopRequest extends $pb.GeneratedMessage {
  factory DevelopRequest({
    Develop? develop,
    Image? image,
    GainMap? gainMap,
    Guide? guide,
    $core.int? fullWidth,
    $core.int? fullHeight,
    $core.int? tileX,
    $core.int? tileY,
  }) {
    final result = DevelopRequest._();
    if (develop != null) result.develop = develop;
    if (image != null) result.image = image;
    if (gainMap != null) result.gainMap = gainMap;
    if (guide != null) result.guide = guide;
    if (fullWidth != null) result.fullWidth = fullWidth;
    if (fullHeight != null) result.fullHeight = fullHeight;
    if (tileX != null) result.tileX = tileX;
    if (tileY != null) result.tileY = tileY;
    return result;
  }

  DevelopRequest._();

  factory DevelopRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DevelopRequest()..mergeFromBuffer(data, registry);
  factory DevelopRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DevelopRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DevelopRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DevelopRequest.$_createMessage)
    ..aOM<Develop>(1, _omitFieldNames ? '' : 'develop',
        subBuilder: Develop.$_createMessage)
    ..aOM<Image>(2, _omitFieldNames ? '' : 'image',
        subBuilder: Image.$_createMessage)
    ..aOM<GainMap>(3, _omitFieldNames ? '' : 'gainMap',
        subBuilder: GainMap.$_createMessage)
    ..aOM<Guide>(4, _omitFieldNames ? '' : 'guide',
        subBuilder: Guide.$_createMessage)
    ..aI(5, _omitFieldNames ? '' : 'fullWidth', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'fullHeight', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'tileX', fieldType: $pb.PbFieldType.OU3)
    ..aI(8, _omitFieldNames ? '' : 'tileY', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DevelopRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DevelopRequest copyWith(void Function(DevelopRequest) updates) =>
      super.copyWith((message) => updates(message as DevelopRequest))
          as DevelopRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DevelopRequest() / DevelopRequest.new instead')
  static DevelopRequest create() => DevelopRequest._();
  static $pb.GeneratedMessage $_createMessage() => DevelopRequest._();
  @$core.override
  DevelopRequest createEmptyInstance() => DevelopRequest._();
  @$core.pragma('dart2js:noInline')
  static DevelopRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DevelopRequest>(
          DevelopRequest.$_createMessage);
  static DevelopRequest? _defaultInstance;

  @$pb.TagNumber(1)
  Develop get develop => $_getN(0);
  @$pb.TagNumber(1)
  set develop(Develop value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDevelop() => $_has(0);
  @$pb.TagNumber(1)
  void clearDevelop() => $_clearField(1);
  @$pb.TagNumber(1)
  Develop ensureDevelop() => $_ensure(0);

  /// The image, or one tile of it: 8-bit sRGB RGBA, opaque.
  @$pb.TagNumber(2)
  Image get image => $_getN(1);
  @$pb.TagNumber(2)
  set image(Image value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasImage() => $_has(1);
  @$pb.TagNumber(2)
  void clearImage() => $_clearField(2);
  @$pb.TagNumber(2)
  Image ensureImage() => $_ensure(1);

  /// The image's Ultra HDR gain map, which is returned edited.
  @$pb.TagNumber(3)
  GainMap get gainMap => $_getN(2);
  @$pb.TagNumber(3)
  set gainMap(GainMap value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasGainMap() => $_has(2);
  @$pb.TagNumber(3)
  void clearGainMap() => $_clearField(3);
  @$pb.TagNumber(3)
  GainMap ensureGainMap() => $_ensure(2);

  /// For a tile: the guide of the whole image (the guide of a response for its proxy), the size of the whole image
  /// and where the tile starts in it. Without it the image is whole and its own proxy.
  @$pb.TagNumber(4)
  Guide get guide => $_getN(3);
  @$pb.TagNumber(4)
  set guide(Guide value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasGuide() => $_has(3);
  @$pb.TagNumber(4)
  void clearGuide() => $_clearField(4);
  @$pb.TagNumber(4)
  Guide ensureGuide() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.int get fullWidth => $_getIZ(4);
  @$pb.TagNumber(5)
  set fullWidth($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFullWidth() => $_has(4);
  @$pb.TagNumber(5)
  void clearFullWidth() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get fullHeight => $_getIZ(5);
  @$pb.TagNumber(6)
  set fullHeight($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFullHeight() => $_has(5);
  @$pb.TagNumber(6)
  void clearFullHeight() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get tileX => $_getIZ(6);
  @$pb.TagNumber(7)
  set tileX($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTileX() => $_has(6);
  @$pb.TagNumber(7)
  void clearTileX() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get tileY => $_getIZ(7);
  @$pb.TagNumber(8)
  set tileY($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTileY() => $_has(7);
  @$pb.TagNumber(8)
  void clearTileY() => $_clearField(8);
}

/// The rendered image, its gain map if the request had one, and the guide it used.
class DevelopResponse extends $pb.GeneratedMessage {
  factory DevelopResponse({
    Image? image,
    GainMap? gainMap,
    Guide? guide,
  }) {
    final result = DevelopResponse._();
    if (image != null) result.image = image;
    if (gainMap != null) result.gainMap = gainMap;
    if (guide != null) result.guide = guide;
    return result;
  }

  DevelopResponse._();

  factory DevelopResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DevelopResponse()..mergeFromBuffer(data, registry);
  factory DevelopResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DevelopResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DevelopResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: DevelopResponse.$_createMessage)
    ..aOM<Image>(1, _omitFieldNames ? '' : 'image',
        subBuilder: Image.$_createMessage)
    ..aOM<GainMap>(2, _omitFieldNames ? '' : 'gainMap',
        subBuilder: GainMap.$_createMessage)
    ..aOM<Guide>(3, _omitFieldNames ? '' : 'guide',
        subBuilder: Guide.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DevelopResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DevelopResponse copyWith(void Function(DevelopResponse) updates) =>
      super.copyWith((message) => updates(message as DevelopResponse))
          as DevelopResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DevelopResponse() / DevelopResponse.new instead')
  static DevelopResponse create() => DevelopResponse._();
  static $pb.GeneratedMessage $_createMessage() => DevelopResponse._();
  @$core.override
  DevelopResponse createEmptyInstance() => DevelopResponse._();
  @$core.pragma('dart2js:noInline')
  static DevelopResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DevelopResponse>(
          DevelopResponse.$_createMessage);
  static DevelopResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Image get image => $_getN(0);
  @$pb.TagNumber(1)
  set image(Image value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasImage() => $_has(0);
  @$pb.TagNumber(1)
  void clearImage() => $_clearField(1);
  @$pb.TagNumber(1)
  Image ensureImage() => $_ensure(0);

  @$pb.TagNumber(2)
  GainMap get gainMap => $_getN(1);
  @$pb.TagNumber(2)
  set gainMap(GainMap value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasGainMap() => $_has(1);
  @$pb.TagNumber(2)
  void clearGainMap() => $_clearField(2);
  @$pb.TagNumber(2)
  GainMap ensureGainMap() => $_ensure(1);

  @$pb.TagNumber(3)
  Guide get guide => $_getN(2);
  @$pb.TagNumber(3)
  set guide(Guide value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasGuide() => $_has(2);
  @$pb.TagNumber(3)
  void clearGuide() => $_clearField(3);
  @$pb.TagNumber(3)
  Guide ensureGuide() => $_ensure(2);
}

/// The adjustments, each neutral at 0.
class Develop extends $pb.GeneratedMessage {
  factory Develop({
    $core.double? temperature,
    $core.double? tint,
    $core.double? exposure,
    $core.double? contrast,
    $core.double? clarity,
    $core.double? saturation,
    Lut? lut,
    $core.int? quarterTurns,
    Rect? crop,
    $core.bool? flip,
  }) {
    final result = Develop._();
    if (temperature != null) result.temperature = temperature;
    if (tint != null) result.tint = tint;
    if (exposure != null) result.exposure = exposure;
    if (contrast != null) result.contrast = contrast;
    if (clarity != null) result.clarity = clarity;
    if (saturation != null) result.saturation = saturation;
    if (lut != null) result.lut = lut;
    if (quarterTurns != null) result.quarterTurns = quarterTurns;
    if (crop != null) result.crop = crop;
    if (flip != null) result.flip = flip;
    return result;
  }

  Develop._();

  factory Develop.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Develop()..mergeFromBuffer(data, registry);
  factory Develop.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Develop()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Develop',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Develop.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'tint', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'exposure', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'contrast', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'clarity', fieldType: $pb.PbFieldType.OF)
    ..aD(6, _omitFieldNames ? '' : 'saturation', fieldType: $pb.PbFieldType.OF)
    ..aOM<Lut>(7, _omitFieldNames ? '' : 'lut', subBuilder: Lut.$_createMessage)
    ..aI(8, _omitFieldNames ? '' : 'quarterTurns',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<Rect>(9, _omitFieldNames ? '' : 'crop',
        subBuilder: Rect.$_createMessage)
    ..aOB(10, _omitFieldNames ? '' : 'flip')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Develop clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Develop copyWith(void Function(Develop) updates) =>
      super.copyWith((message) => updates(message as Develop)) as Develop;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Develop() / Develop.new instead')
  static Develop create() => Develop._();
  static $pb.GeneratedMessage $_createMessage() => Develop._();
  @$core.override
  Develop createEmptyInstance() => Develop._();
  @$core.pragma('dart2js:noInline')
  static Develop getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Develop>(Develop.$_createMessage);
  static Develop? _defaultInstance;

  /// White balance, -1 (cool, green) to 1 (warm, magenta).
  @$pb.TagNumber(1)
  $core.double get temperature => $_getN(0);
  @$pb.TagNumber(1)
  set temperature($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTemperature() => $_has(0);
  @$pb.TagNumber(1)
  void clearTemperature() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get tint => $_getN(1);
  @$pb.TagNumber(2)
  set tint($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTint() => $_has(1);
  @$pb.TagNumber(2)
  void clearTint() => $_clearField(2);

  /// Exposure in EV.
  @$pb.TagNumber(3)
  $core.double get exposure => $_getN(2);
  @$pb.TagNumber(3)
  set exposure($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExposure() => $_has(2);
  @$pb.TagNumber(3)
  void clearExposure() => $_clearField(3);

  /// An S-curve (positive) or its inverse (negative), -1 to 1.
  @$pb.TagNumber(4)
  $core.double get contrast => $_getN(3);
  @$pb.TagNumber(4)
  set contrast($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContrast() => $_has(3);
  @$pb.TagNumber(4)
  void clearContrast() => $_clearField(4);

  /// Local contrast against the guide (clarity), -1 to 1.
  @$pb.TagNumber(5)
  $core.double get clarity => $_getN(4);
  @$pb.TagNumber(5)
  set clarity($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasClarity() => $_has(4);
  @$pb.TagNumber(5)
  void clearClarity() => $_clearField(5);

  /// -1 (monochrome) to 1.
  @$pb.TagNumber(6)
  $core.double get saturation => $_getN(5);
  @$pb.TagNumber(6)
  set saturation($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSaturation() => $_has(5);
  @$pb.TagNumber(6)
  void clearSaturation() => $_clearField(6);

  /// Applied last, to sRGB-encoded values.
  @$pb.TagNumber(7)
  Lut get lut => $_getN(6);
  @$pb.TagNumber(7)
  set lut(Lut value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasLut() => $_has(6);
  @$pb.TagNumber(7)
  void clearLut() => $_clearField(7);
  @$pb.TagNumber(7)
  Lut ensureLut() => $_ensure(6);

  /// Geometry, applied first and without resampling: clockwise quarter turns, a mirror left to right if `flip`, then
  /// a crop in the turned and mirrored image.
  @$pb.TagNumber(8)
  $core.int get quarterTurns => $_getIZ(7);
  @$pb.TagNumber(8)
  set quarterTurns($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasQuarterTurns() => $_has(7);
  @$pb.TagNumber(8)
  void clearQuarterTurns() => $_clearField(8);

  @$pb.TagNumber(9)
  Rect get crop => $_getN(8);
  @$pb.TagNumber(9)
  set crop(Rect value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasCrop() => $_has(8);
  @$pb.TagNumber(9)
  void clearCrop() => $_clearField(9);
  @$pb.TagNumber(9)
  Rect ensureCrop() => $_ensure(8);

  @$pb.TagNumber(10)
  $core.bool get flip => $_getBF(9);
  @$pb.TagNumber(10)
  set flip($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasFlip() => $_has(9);
  @$pb.TagNumber(10)
  void clearFlip() => $_clearField(10);
}

/// A 3D colour lookup table: size³ sRGB-encoded RGB entries, red fastest, as 16-bit little-endian unsigned values.
class Lut extends $pb.GeneratedMessage {
  factory Lut({
    $core.int? size,
    $core.List<$core.int>? rgb16,
  }) {
    final result = Lut._();
    if (size != null) result.size = size;
    if (rgb16 != null) result.rgb16 = rgb16;
    return result;
  }

  Lut._();

  factory Lut.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Lut()..mergeFromBuffer(data, registry);
  factory Lut.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Lut()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Lut',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Lut.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'size', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'rgb16', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Lut clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Lut copyWith(void Function(Lut) updates) =>
      super.copyWith((message) => updates(message as Lut)) as Lut;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Lut() / Lut.new instead')
  static Lut create() => Lut._();
  static $pb.GeneratedMessage $_createMessage() => Lut._();
  @$core.override
  Lut createEmptyInstance() => Lut._();
  @$core.pragma('dart2js:noInline')
  static Lut getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Lut>(Lut.$_createMessage);
  static Lut? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get size => $_getIZ(0);
  @$pb.TagNumber(1)
  set size($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSize() => $_has(0);
  @$pb.TagNumber(1)
  void clearSize() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get rgb16 => $_getN(1);
  @$pb.TagNumber(2)
  set rgb16($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRgb16() => $_has(1);
  @$pb.TagNumber(2)
  void clearRgb16() => $_clearField(2);
}

/// A rectangle in pixels; an empty one means the whole image.
class Rect extends $pb.GeneratedMessage {
  factory Rect({
    $core.int? x,
    $core.int? y,
    $core.int? width,
    $core.int? height,
  }) {
    final result = Rect._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    return result;
  }

  Rect._();

  factory Rect.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Rect()..mergeFromBuffer(data, registry);
  factory Rect.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Rect()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Rect',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Rect.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Rect clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Rect copyWith(void Function(Rect) updates) =>
      super.copyWith((message) => updates(message as Rect)) as Rect;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Rect() / Rect.new instead')
  static Rect create() => Rect._();
  static $pb.GeneratedMessage $_createMessage() => Rect._();
  @$core.override
  Rect createEmptyInstance() => Rect._();
  @$core.pragma('dart2js:noInline')
  static Rect getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Rect>(Rect.$_createMessage);
  static Rect? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get x => $_getIZ(0);
  @$pb.TagNumber(1)
  set x($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get y => $_getIZ(1);
  @$pb.TagNumber(2)
  set y($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get width => $_getIZ(2);
  @$pb.TagNumber(3)
  set width($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWidth() => $_has(2);
  @$pb.TagNumber(3)
  void clearWidth() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get height => $_getIZ(3);
  @$pb.TagNumber(4)
  set height($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeight() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeight() => $_clearField(4);
}

/// An 8-bit RGBA raster, row by row.
class Image extends $pb.GeneratedMessage {
  factory Image({
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? rgba,
  }) {
    final result = Image._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (rgba != null) result.rgba = rgba;
    return result;
  }

  Image._();

  factory Image.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Image()..mergeFromBuffer(data, registry);
  factory Image.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Image()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Image',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Image.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'rgba', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Image clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Image copyWith(void Function(Image) updates) =>
      super.copyWith((message) => updates(message as Image)) as Image;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Image() / Image.new instead')
  static Image create() => Image._();
  static $pb.GeneratedMessage $_createMessage() => Image._();
  @$core.override
  Image createEmptyInstance() => Image._();
  @$core.pragma('dart2js:noInline')
  static Image getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Image>(Image.$_createMessage);
  static Image? _defaultInstance;

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
}

/// A low-resolution grid of the image's mean log2 luminance, blurred, that local contrast compares each pixel with,
/// so that a preview and a tiled export get the same local adjustments.
class Guide extends $pb.GeneratedMessage {
  factory Guide({
    $core.int? width,
    $core.int? height,
    $core.Iterable<$core.double>? log2Luminance,
  }) {
    final result = Guide._();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (log2Luminance != null) result.log2Luminance.addAll(log2Luminance);
    return result;
  }

  Guide._();

  factory Guide.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Guide()..mergeFromBuffer(data, registry);
  factory Guide.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Guide()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Guide',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Guide.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..p<$core.double>(
        3, _omitFieldNames ? '' : 'log2Luminance', $pb.PbFieldType.KF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Guide clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Guide copyWith(void Function(Guide) updates) =>
      super.copyWith((message) => updates(message as Guide)) as Guide;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Guide() / Guide.new instead')
  static Guide create() => Guide._();
  static $pb.GeneratedMessage $_createMessage() => Guide._();
  @$core.override
  Guide createEmptyInstance() => Guide._();
  @$core.pragma('dart2js:noInline')
  static Guide getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Guide>(Guide.$_createMessage);
  static Guide? _defaultInstance;

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
  $pb.PbList<$core.double> get log2Luminance => $_getList(2);
}

/// A gain map (Ultra HDR, ISO 21496-1) with its metadata, for full HDR headroom: the HDR rendition is
/// (sdr + offset_sdr) * 2^(min_log2 + (max_log2 - min_log2) * (map / 255)^(1 / gamma)) - offset_hdr per channel, each
/// map pixel covering a block of the image (the map's size divides the image's).
class GainMap extends $pb.GeneratedMessage {
  factory GainMap({
    Image? image,
    $core.double? minLog2,
    $core.double? maxLog2,
    $core.double? gamma,
    $core.double? offsetSdr,
    $core.double? offsetHdr,
    $core.double? hdrCapacityMin,
    $core.double? hdrCapacityMax,
  }) {
    final result = GainMap._();
    if (image != null) result.image = image;
    if (minLog2 != null) result.minLog2 = minLog2;
    if (maxLog2 != null) result.maxLog2 = maxLog2;
    if (gamma != null) result.gamma = gamma;
    if (offsetSdr != null) result.offsetSdr = offsetSdr;
    if (offsetHdr != null) result.offsetHdr = offsetHdr;
    if (hdrCapacityMin != null) result.hdrCapacityMin = hdrCapacityMin;
    if (hdrCapacityMax != null) result.hdrCapacityMax = hdrCapacityMax;
    return result;
  }

  GainMap._();

  factory GainMap.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GainMap()..mergeFromBuffer(data, registry);
  factory GainMap.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GainMap()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GainMap',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: GainMap.$_createMessage)
    ..aOM<Image>(1, _omitFieldNames ? '' : 'image',
        subBuilder: Image.$_createMessage)
    ..aD(2, _omitFieldNames ? '' : 'minLog2', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'maxLog2', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'gamma', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'offsetSdr', fieldType: $pb.PbFieldType.OF)
    ..aD(6, _omitFieldNames ? '' : 'offsetHdr', fieldType: $pb.PbFieldType.OF)
    ..aD(7, _omitFieldNames ? '' : 'hdrCapacityMin',
        fieldType: $pb.PbFieldType.OF)
    ..aD(8, _omitFieldNames ? '' : 'hdrCapacityMax',
        fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GainMap clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GainMap copyWith(void Function(GainMap) updates) =>
      super.copyWith((message) => updates(message as GainMap)) as GainMap;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GainMap() / GainMap.new instead')
  static GainMap create() => GainMap._();
  static $pb.GeneratedMessage $_createMessage() => GainMap._();
  @$core.override
  GainMap createEmptyInstance() => GainMap._();
  @$core.pragma('dart2js:noInline')
  static GainMap getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GainMap>(GainMap.$_createMessage);
  static GainMap? _defaultInstance;

  @$pb.TagNumber(1)
  Image get image => $_getN(0);
  @$pb.TagNumber(1)
  set image(Image value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasImage() => $_has(0);
  @$pb.TagNumber(1)
  void clearImage() => $_clearField(1);
  @$pb.TagNumber(1)
  Image ensureImage() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.double get minLog2 => $_getN(1);
  @$pb.TagNumber(2)
  set minLog2($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinLog2() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinLog2() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get maxLog2 => $_getN(2);
  @$pb.TagNumber(3)
  set maxLog2($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxLog2() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxLog2() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get gamma => $_getN(3);
  @$pb.TagNumber(4)
  set gamma($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasGamma() => $_has(3);
  @$pb.TagNumber(4)
  void clearGamma() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get offsetSdr => $_getN(4);
  @$pb.TagNumber(5)
  set offsetSdr($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOffsetSdr() => $_has(4);
  @$pb.TagNumber(5)
  void clearOffsetSdr() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get offsetHdr => $_getN(5);
  @$pb.TagNumber(6)
  set offsetHdr($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOffsetHdr() => $_has(5);
  @$pb.TagNumber(6)
  void clearOffsetHdr() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get hdrCapacityMin => $_getN(6);
  @$pb.TagNumber(7)
  set hdrCapacityMin($core.double value) => $_setFloat(6, value);
  @$pb.TagNumber(7)
  $core.bool hasHdrCapacityMin() => $_has(6);
  @$pb.TagNumber(7)
  void clearHdrCapacityMin() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get hdrCapacityMax => $_getN(7);
  @$pb.TagNumber(8)
  set hdrCapacityMax($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHdrCapacityMax() => $_has(7);
  @$pb.TagNumber(8)
  void clearHdrCapacityMax() => $_clearField(8);
}

/// Writes an edited copy of a JPEG photo, never changing the original (design 11 §2.5, ADR-0331). An edit of geometry
/// alone keeps the original's compressed pixels: turns and mirrors become the copy's EXIF orientation, and a crop of a
/// sequential JPEG keeps whole blocks, its top left corner moved up and left onto a block boundary, as jpegtran's is.
/// Any other edit, or one of a progressive JPEG, encodes the rendered image. The copy keeps the original's EXIF, XMP,
/// ICC profile and IPTC, with its new orientation and size, and records the edit and the original in its XMP.
class EditCopyRequest extends $pb.GeneratedMessage {
  factory EditCopyRequest({
    $core.List<$core.int>? original,
    Develop? develop,
    Image? image,
    $0.CaptureTime? captureTime,
    $core.String? originalBlake3,
    $1.EditRecipe? recipe,
    $core.bool? rendered,
    $core.List<$core.int>? metadataFrom,
  }) {
    final result = EditCopyRequest._();
    if (original != null) result.original = original;
    if (develop != null) result.develop = develop;
    if (image != null) result.image = image;
    if (captureTime != null) result.captureTime = captureTime;
    if (originalBlake3 != null) result.originalBlake3 = originalBlake3;
    if (recipe != null) result.recipe = recipe;
    if (rendered != null) result.rendered = rendered;
    if (metadataFrom != null) result.metadataFrom = metadataFrom;
    return result;
  }

  EditCopyRequest._();

  factory EditCopyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EditCopyRequest()..mergeFromBuffer(data, registry);
  factory EditCopyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EditCopyRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EditCopyRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: EditCopyRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'original', $pb.PbFieldType.OY)
    ..aOM<Develop>(2, _omitFieldNames ? '' : 'develop',
        subBuilder: Develop.$_createMessage)
    ..aOM<Image>(3, _omitFieldNames ? '' : 'image',
        subBuilder: Image.$_createMessage)
    ..aOM<$0.CaptureTime>(4, _omitFieldNames ? '' : 'captureTime',
        subBuilder: $0.CaptureTime.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'originalBlake3')
    ..aOM<$1.EditRecipe>(6, _omitFieldNames ? '' : 'recipe',
        subBuilder: $1.EditRecipe.$_createMessage)
    ..aOB(7, _omitFieldNames ? '' : 'rendered')
    ..a<$core.List<$core.int>>(
        8, _omitFieldNames ? '' : 'metadataFrom', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EditCopyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EditCopyRequest copyWith(void Function(EditCopyRequest) updates) =>
      super.copyWith((message) => updates(message as EditCopyRequest))
          as EditCopyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EditCopyRequest() / EditCopyRequest.new instead')
  static EditCopyRequest create() => EditCopyRequest._();
  static $pb.GeneratedMessage $_createMessage() => EditCopyRequest._();
  @$core.override
  EditCopyRequest createEmptyInstance() => EditCopyRequest._();
  @$core.pragma('dart2js:noInline')
  static EditCopyRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EditCopyRequest>(
          EditCopyRequest.$_createMessage);
  static EditCopyRequest? _defaultInstance;

  /// The original, a whole JPEG file.
  @$pb.TagNumber(1)
  $core.List<$core.int> get original => $_getN(0);
  @$pb.TagNumber(1)
  set original($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOriginal() => $_has(0);
  @$pb.TagNumber(1)
  void clearOriginal() => $_clearField(1);

  /// The edit of the original as shown, its EXIF orientation applied.
  @$pb.TagNumber(2)
  Develop get develop => $_getN(1);
  @$pb.TagNumber(2)
  set develop(Develop value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDevelop() => $_has(1);
  @$pb.TagNumber(2)
  void clearDevelop() => $_clearField(2);
  @$pb.TagNumber(2)
  Develop ensureDevelop() => $_ensure(1);

  /// The original decoded as shown, its EXIF orientation applied: needed unless the edit is lossless, else the call
  /// fails naming this field.
  @$pb.TagNumber(3)
  Image get image => $_getN(2);
  @$pb.TagNumber(3)
  set image(Image value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasImage() => $_has(2);
  @$pb.TagNumber(3)
  void clearImage() => $_clearField(3);
  @$pb.TagNumber(3)
  Image ensureImage() => $_ensure(2);

  /// The original's capture time, which the copy's XMP records when the original's metadata holds none.
  @$pb.TagNumber(4)
  $0.CaptureTime get captureTime => $_getN(3);
  @$pb.TagNumber(4)
  set captureTime($0.CaptureTime value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCaptureTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearCaptureTime() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.CaptureTime ensureCaptureTime() => $_ensure(3);

  /// The original's BLAKE3 in lowercase hex, which the copy's XMP names as its source (xmpMM:DerivedFrom).
  @$pb.TagNumber(5)
  $core.String get originalBlake3 => $_getSZ(4);
  @$pb.TagNumber(5)
  set originalBlake3($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOriginalBlake3() => $_has(4);
  @$pb.TagNumber(5)
  void clearOriginalBlake3() => $_clearField(5);

  /// The edit as a recipe (ADR-0391), which replaces `develop`: its geometry and adjustments as `develop` has them, its
  /// local operations rendered into `image`. The copy's XMP records a summary of it (no pixels of masks or patches)
  /// with its SHA-256, the models and parameters it came from, and IPTC's DigitalSourceType.
  @$pb.TagNumber(6)
  $1.EditRecipe get recipe => $_getN(5);
  @$pb.TagNumber(6)
  set recipe($1.EditRecipe value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasRecipe() => $_has(5);
  @$pb.TagNumber(6)
  void clearRecipe() => $_clearField(6);
  @$pb.TagNumber(6)
  $1.EditRecipe ensureRecipe() => $_ensure(5);

  /// With a recipe: `original` is already the picture the recipe makes, rendered by the host (for a format that this
  /// call cannot edit, such as a HEIC): it is kept as it is, and only the recipe is recorded.
  @$pb.TagNumber(7)
  $core.bool get rendered => $_getBF(6);
  @$pb.TagNumber(7)
  set rendered($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRendered() => $_has(6);
  @$pb.TagNumber(7)
  void clearRendered() => $_clearField(7);

  /// With `rendered`: a JPEG whose EXIF, XMP and IPTC the copy keeps, for a `rendered` picture that the host made from
  /// that file (so that a copy edited in the host's renderer keeps where and when it was taken); the host's picture is
  /// in sRGB, so the file's colour profile is left out, and its orientation is the host's pixels'.
  @$pb.TagNumber(8)
  $core.List<$core.int> get metadataFrom => $_getN(7);
  @$pb.TagNumber(8)
  set metadataFrom($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMetadataFrom() => $_has(7);
  @$pb.TagNumber(8)
  void clearMetadataFrom() => $_clearField(8);
}

/// The copy, a JPEG file.
class EditCopyResponse extends $pb.GeneratedMessage {
  factory EditCopyResponse({
    $core.List<$core.int>? jpeg,
    $core.bool? lossless,
    Rect? crop,
  }) {
    final result = EditCopyResponse._();
    if (jpeg != null) result.jpeg = jpeg;
    if (lossless != null) result.lossless = lossless;
    if (crop != null) result.crop = crop;
    return result;
  }

  EditCopyResponse._();

  factory EditCopyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EditCopyResponse()..mergeFromBuffer(data, registry);
  factory EditCopyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EditCopyResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EditCopyResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: EditCopyResponse.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'jpeg', $pb.PbFieldType.OY)
    ..aOB(2, _omitFieldNames ? '' : 'lossless')
    ..aOM<Rect>(3, _omitFieldNames ? '' : 'crop',
        subBuilder: Rect.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EditCopyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EditCopyResponse copyWith(void Function(EditCopyResponse) updates) =>
      super.copyWith((message) => updates(message as EditCopyResponse))
          as EditCopyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EditCopyResponse() / EditCopyResponse.new instead')
  static EditCopyResponse create() => EditCopyResponse._();
  static $pb.GeneratedMessage $_createMessage() => EditCopyResponse._();
  @$core.override
  EditCopyResponse createEmptyInstance() => EditCopyResponse._();
  @$core.pragma('dart2js:noInline')
  static EditCopyResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EditCopyResponse>(
          EditCopyResponse.$_createMessage);
  static EditCopyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get jpeg => $_getN(0);
  @$pb.TagNumber(1)
  set jpeg($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasJpeg() => $_has(0);
  @$pb.TagNumber(1)
  void clearJpeg() => $_clearField(1);

  /// Whether the copy keeps the original's compressed pixels.
  @$pb.TagNumber(2)
  $core.bool get lossless => $_getBF(1);
  @$pb.TagNumber(2)
  set lossless($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLossless() => $_has(1);
  @$pb.TagNumber(2)
  void clearLossless() => $_clearField(2);

  /// The part of the edited image (as turned and mirrored) that the copy shows, which a lossless crop moves up and
  /// left onto the JPEG's block grid; empty when the copy is whole. MapFaces takes it as the crop.
  @$pb.TagNumber(3)
  Rect get crop => $_getN(2);
  @$pb.TagNumber(3)
  set crop(Rect value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCrop() => $_has(2);
  @$pb.TagNumber(3)
  void clearCrop() => $_clearField(3);
  @$pb.TagNumber(3)
  Rect ensureCrop() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
