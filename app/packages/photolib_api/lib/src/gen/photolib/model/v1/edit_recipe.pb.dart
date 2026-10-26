// This is a generated file - do not edit.
//
// Generated from photolib/model/v1/edit_recipe.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'edit_recipe.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'edit_recipe.pbenum.dart';

/// How a photo is edited, as data: the ordered operations that turn an original into one version of it, the outputs of
/// models those operations use (so that a render never runs a model again) and where the edit came from (roadmap M8-01,
/// ADR-0391). It is the plaintext of `versions.recipe`; versions are immutable, an edit is a new version.
///
/// A render applies the operations in three stages, each in the order of the list: the local operations to the original
/// as shown (its EXIF orientation applied), then the geometry operations, then the global adjustments, summed. The
/// stored outputs are therefore in the original's frame, and a crop changed later keeps them valid.
class EditRecipe extends $pb.GeneratedMessage {
  factory EditRecipe({
    $core.int? schemaVersion,
    $core.Iterable<Operation>? operations,
    Provenance? provenance,
    $core.Iterable<StoredOutput>? outputs,
  }) {
    final result = EditRecipe._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (operations != null) result.operations.addAll(operations);
    if (provenance != null) result.provenance = provenance;
    if (outputs != null) result.outputs.addAll(outputs);
    return result;
  }

  EditRecipe._();

  factory EditRecipe.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EditRecipe()..mergeFromBuffer(data, registry);
  factory EditRecipe.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EditRecipe()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EditRecipe',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: EditRecipe.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<Operation>(2, _omitFieldNames ? '' : 'operations',
        subBuilder: Operation.$_createMessage)
    ..aOM<Provenance>(3, _omitFieldNames ? '' : 'provenance',
        subBuilder: Provenance.$_createMessage)
    ..pPM<StoredOutput>(4, _omitFieldNames ? '' : 'outputs',
        subBuilder: StoredOutput.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EditRecipe clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EditRecipe copyWith(void Function(EditRecipe) updates) =>
      super.copyWith((message) => updates(message as EditRecipe)) as EditRecipe;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EditRecipe() / EditRecipe.new instead')
  static EditRecipe create() => EditRecipe._();
  static $pb.GeneratedMessage $_createMessage() => EditRecipe._();
  @$core.override
  EditRecipe createEmptyInstance() => EditRecipe._();
  @$core.pragma('dart2js:noInline')
  static EditRecipe getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EditRecipe>(EditRecipe.$_createMessage);
  static EditRecipe? _defaultInstance;

  /// 1 for this layout; a reader refuses a number it does not know and migrates the older ones.
  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  /// At most 256.
  @$pb.TagNumber(2)
  $pb.PbList<Operation> get operations => $_getList(1);

  /// What the stored outputs and the edit's tool say about how it was made.
  @$pb.TagNumber(3)
  Provenance get provenance => $_getN(2);
  @$pb.TagNumber(3)
  set provenance(Provenance value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasProvenance() => $_has(2);
  @$pb.TagNumber(3)
  void clearProvenance() => $_clearField(3);
  @$pb.TagNumber(3)
  Provenance ensureProvenance() => $_ensure(2);

  /// The outputs of models that operations refer to by id; at most 64, each used by an operation.
  @$pb.TagNumber(4)
  $pb.PbList<StoredOutput> get outputs => $_getList(3);
}

enum Operation_Kind {
  turn,
  flip,
  crop,
  adjust,
  lut,
  localAdjust,
  inpaint,
  notSet
}

/// One step of an edit.
class Operation extends $pb.GeneratedMessage {
  factory Operation({
    $core.String? operationId,
    $core.bool? disabled,
    TurnOperation? turn,
    FlipOperation? flip,
    CropOperation? crop,
    AdjustOperation? adjust,
    LutOperation? lut,
    LocalAdjustOperation? localAdjust,
    InpaintOperation? inpaint,
  }) {
    final result = Operation._();
    if (operationId != null) result.operationId = operationId;
    if (disabled != null) result.disabled = disabled;
    if (turn != null) result.turn = turn;
    if (flip != null) result.flip = flip;
    if (crop != null) result.crop = crop;
    if (adjust != null) result.adjust = adjust;
    if (lut != null) result.lut = lut;
    if (localAdjust != null) result.localAdjust = localAdjust;
    if (inpaint != null) result.inpaint = inpaint;
    return result;
  }

  Operation._();

  factory Operation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Operation()..mergeFromBuffer(data, registry);
  factory Operation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Operation()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Operation_Kind> _Operation_KindByTag = {
    10: Operation_Kind.turn,
    11: Operation_Kind.flip,
    12: Operation_Kind.crop,
    13: Operation_Kind.adjust,
    14: Operation_Kind.lut,
    15: Operation_Kind.localAdjust,
    16: Operation_Kind.inpaint,
    0: Operation_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Operation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: Operation.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16])
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..aOB(2, _omitFieldNames ? '' : 'disabled')
    ..aOM<TurnOperation>(10, _omitFieldNames ? '' : 'turn',
        subBuilder: TurnOperation.$_createMessage)
    ..aOM<FlipOperation>(11, _omitFieldNames ? '' : 'flip',
        subBuilder: FlipOperation.$_createMessage)
    ..aOM<CropOperation>(12, _omitFieldNames ? '' : 'crop',
        subBuilder: CropOperation.$_createMessage)
    ..aOM<AdjustOperation>(13, _omitFieldNames ? '' : 'adjust',
        subBuilder: AdjustOperation.$_createMessage)
    ..aOM<LutOperation>(14, _omitFieldNames ? '' : 'lut',
        subBuilder: LutOperation.$_createMessage)
    ..aOM<LocalAdjustOperation>(15, _omitFieldNames ? '' : 'localAdjust',
        subBuilder: LocalAdjustOperation.$_createMessage)
    ..aOM<InpaintOperation>(16, _omitFieldNames ? '' : 'inpaint',
        subBuilder: InpaintOperation.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Operation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Operation copyWith(void Function(Operation) updates) =>
      super.copyWith((message) => updates(message as Operation)) as Operation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Operation() / Operation.new instead')
  static Operation create() => Operation._();
  static $pb.GeneratedMessage $_createMessage() => Operation._();
  @$core.override
  Operation createEmptyInstance() => Operation._();
  @$core.pragma('dart2js:noInline')
  static Operation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Operation>(Operation.$_createMessage);
  static Operation? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  Operation_Kind whichKind() => _Operation_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  void clearKind() => $_clearField($_whichOneof(0));

  /// Names the step within its recipe, so that two versions compare step by step: a UUIDv7 or any string of at most 64
  /// characters, unique in the recipe.
  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);

  /// A step kept in the recipe but not rendered.
  @$pb.TagNumber(2)
  $core.bool get disabled => $_getBF(1);
  @$pb.TagNumber(2)
  set disabled($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisabled() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisabled() => $_clearField(2);

  @$pb.TagNumber(10)
  TurnOperation get turn => $_getN(2);
  @$pb.TagNumber(10)
  set turn(TurnOperation value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasTurn() => $_has(2);
  @$pb.TagNumber(10)
  void clearTurn() => $_clearField(10);
  @$pb.TagNumber(10)
  TurnOperation ensureTurn() => $_ensure(2);

  @$pb.TagNumber(11)
  FlipOperation get flip => $_getN(3);
  @$pb.TagNumber(11)
  set flip(FlipOperation value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasFlip() => $_has(3);
  @$pb.TagNumber(11)
  void clearFlip() => $_clearField(11);
  @$pb.TagNumber(11)
  FlipOperation ensureFlip() => $_ensure(3);

  @$pb.TagNumber(12)
  CropOperation get crop => $_getN(4);
  @$pb.TagNumber(12)
  set crop(CropOperation value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasCrop() => $_has(4);
  @$pb.TagNumber(12)
  void clearCrop() => $_clearField(12);
  @$pb.TagNumber(12)
  CropOperation ensureCrop() => $_ensure(4);

  @$pb.TagNumber(13)
  AdjustOperation get adjust => $_getN(5);
  @$pb.TagNumber(13)
  set adjust(AdjustOperation value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasAdjust() => $_has(5);
  @$pb.TagNumber(13)
  void clearAdjust() => $_clearField(13);
  @$pb.TagNumber(13)
  AdjustOperation ensureAdjust() => $_ensure(5);

  @$pb.TagNumber(14)
  LutOperation get lut => $_getN(6);
  @$pb.TagNumber(14)
  set lut(LutOperation value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasLut() => $_has(6);
  @$pb.TagNumber(14)
  void clearLut() => $_clearField(14);
  @$pb.TagNumber(14)
  LutOperation ensureLut() => $_ensure(6);

  @$pb.TagNumber(15)
  LocalAdjustOperation get localAdjust => $_getN(7);
  @$pb.TagNumber(15)
  set localAdjust(LocalAdjustOperation value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasLocalAdjust() => $_has(7);
  @$pb.TagNumber(15)
  void clearLocalAdjust() => $_clearField(15);
  @$pb.TagNumber(15)
  LocalAdjustOperation ensureLocalAdjust() => $_ensure(7);

  @$pb.TagNumber(16)
  InpaintOperation get inpaint => $_getN(8);
  @$pb.TagNumber(16)
  set inpaint(InpaintOperation value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasInpaint() => $_has(8);
  @$pb.TagNumber(16)
  void clearInpaint() => $_clearField(16);
  @$pb.TagNumber(16)
  InpaintOperation ensureInpaint() => $_ensure(8);
}

/// Turns the image clockwise by quarter turns (geometry, without resampling).
class TurnOperation extends $pb.GeneratedMessage {
  factory TurnOperation({
    $core.int? quarterTurns,
  }) {
    final result = TurnOperation._();
    if (quarterTurns != null) result.quarterTurns = quarterTurns;
    return result;
  }

  TurnOperation._();

  factory TurnOperation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TurnOperation()..mergeFromBuffer(data, registry);
  factory TurnOperation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TurnOperation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TurnOperation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: TurnOperation.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'quarterTurns',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnOperation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnOperation copyWith(void Function(TurnOperation) updates) =>
      super.copyWith((message) => updates(message as TurnOperation))
          as TurnOperation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TurnOperation() / TurnOperation.new instead')
  static TurnOperation create() => TurnOperation._();
  static $pb.GeneratedMessage $_createMessage() => TurnOperation._();
  @$core.override
  TurnOperation createEmptyInstance() => TurnOperation._();
  @$core.pragma('dart2js:noInline')
  static TurnOperation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TurnOperation>(
          TurnOperation.$_createMessage);
  static TurnOperation? _defaultInstance;

  /// 1 to 3.
  @$pb.TagNumber(1)
  $core.int get quarterTurns => $_getIZ(0);
  @$pb.TagNumber(1)
  set quarterTurns($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuarterTurns() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuarterTurns() => $_clearField(1);
}

/// Mirrors the image left to right (geometry).
class FlipOperation extends $pb.GeneratedMessage {
  factory FlipOperation({
    $core.bool? vertical,
  }) {
    final result = FlipOperation._();
    if (vertical != null) result.vertical = vertical;
    return result;
  }

  FlipOperation._();

  factory FlipOperation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FlipOperation()..mergeFromBuffer(data, registry);
  factory FlipOperation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FlipOperation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FlipOperation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: FlipOperation.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'vertical')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FlipOperation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FlipOperation copyWith(void Function(FlipOperation) updates) =>
      super.copyWith((message) => updates(message as FlipOperation))
          as FlipOperation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FlipOperation() / FlipOperation.new instead')
  static FlipOperation create() => FlipOperation._();
  static $pb.GeneratedMessage $_createMessage() => FlipOperation._();
  @$core.override
  FlipOperation createEmptyInstance() => FlipOperation._();
  @$core.pragma('dart2js:noInline')
  static FlipOperation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FlipOperation>(
          FlipOperation.$_createMessage);
  static FlipOperation? _defaultInstance;

  /// Mirrors top to bottom instead.
  @$pb.TagNumber(1)
  $core.bool get vertical => $_getBF(0);
  @$pb.TagNumber(1)
  set vertical($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVertical() => $_has(0);
  @$pb.TagNumber(1)
  void clearVertical() => $_clearField(1);
}

/// Keeps a rectangle of the image as it is at this point of the geometry steps (geometry).
class CropOperation extends $pb.GeneratedMessage {
  factory CropOperation({
    $core.double? x,
    $core.double? y,
    $core.double? width,
    $core.double? height,
  }) {
    final result = CropOperation._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    return result;
  }

  CropOperation._();

  factory CropOperation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CropOperation()..mergeFromBuffer(data, registry);
  factory CropOperation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CropOperation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CropOperation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: CropOperation.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CropOperation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CropOperation copyWith(void Function(CropOperation) updates) =>
      super.copyWith((message) => updates(message as CropOperation))
          as CropOperation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CropOperation() / CropOperation.new instead')
  static CropOperation create() => CropOperation._();
  static $pb.GeneratedMessage $_createMessage() => CropOperation._();
  @$core.override
  CropOperation createEmptyInstance() => CropOperation._();
  @$core.pragma('dart2js:noInline')
  static CropOperation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CropOperation>(
          CropOperation.$_createMessage);
  static CropOperation? _defaultInstance;

  /// Fractions of the width and height, from 0 to 1: the rectangle's left and top, and its size; it lies inside the
  /// image and is not empty.
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
}

/// The adjustments of the editor, each neutral at 0 (design 11 §2.2; the definitions are the kernel's `develop.rs`).
/// The global adjustments of a recipe add up, each clamped to its range, after every other step.
class AdjustOperation extends $pb.GeneratedMessage {
  factory AdjustOperation({
    $core.double? temperature,
    $core.double? tint,
    $core.double? exposure,
    $core.double? contrast,
    $core.double? clarity,
    $core.double? saturation,
  }) {
    final result = AdjustOperation._();
    if (temperature != null) result.temperature = temperature;
    if (tint != null) result.tint = tint;
    if (exposure != null) result.exposure = exposure;
    if (contrast != null) result.contrast = contrast;
    if (clarity != null) result.clarity = clarity;
    if (saturation != null) result.saturation = saturation;
    return result;
  }

  AdjustOperation._();

  factory AdjustOperation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AdjustOperation()..mergeFromBuffer(data, registry);
  factory AdjustOperation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AdjustOperation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdjustOperation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: AdjustOperation.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'tint', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'exposure', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'contrast', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'clarity', fieldType: $pb.PbFieldType.OF)
    ..aD(6, _omitFieldNames ? '' : 'saturation', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdjustOperation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdjustOperation copyWith(void Function(AdjustOperation) updates) =>
      super.copyWith((message) => updates(message as AdjustOperation))
          as AdjustOperation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AdjustOperation() / AdjustOperation.new instead')
  static AdjustOperation create() => AdjustOperation._();
  static $pb.GeneratedMessage $_createMessage() => AdjustOperation._();
  @$core.override
  AdjustOperation createEmptyInstance() => AdjustOperation._();
  @$core.pragma('dart2js:noInline')
  static AdjustOperation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AdjustOperation>(
          AdjustOperation.$_createMessage);
  static AdjustOperation? _defaultInstance;

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

  /// In EV, -8 to 8.
  @$pb.TagNumber(3)
  $core.double get exposure => $_getN(2);
  @$pb.TagNumber(3)
  set exposure($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExposure() => $_has(2);
  @$pb.TagNumber(3)
  void clearExposure() => $_clearField(3);

  /// -1 to 1.
  @$pb.TagNumber(4)
  $core.double get contrast => $_getN(3);
  @$pb.TagNumber(4)
  set contrast($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContrast() => $_has(3);
  @$pb.TagNumber(4)
  void clearContrast() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get clarity => $_getN(4);
  @$pb.TagNumber(5)
  set clarity($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasClarity() => $_has(4);
  @$pb.TagNumber(5)
  void clearClarity() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get saturation => $_getN(5);
  @$pb.TagNumber(6)
  set saturation($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSaturation() => $_has(5);
  @$pb.TagNumber(6)
  void clearSaturation() => $_clearField(6);
}

/// A 3D colour lookup table applied after the adjustments; of several, the last one enabled counts.
class LutOperation extends $pb.GeneratedMessage {
  factory LutOperation({
    $core.int? size,
    $core.List<$core.int>? rgb16,
  }) {
    final result = LutOperation._();
    if (size != null) result.size = size;
    if (rgb16 != null) result.rgb16 = rgb16;
    return result;
  }

  LutOperation._();

  factory LutOperation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LutOperation()..mergeFromBuffer(data, registry);
  factory LutOperation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LutOperation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LutOperation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: LutOperation.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'size', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'rgb16', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LutOperation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LutOperation copyWith(void Function(LutOperation) updates) =>
      super.copyWith((message) => updates(message as LutOperation))
          as LutOperation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LutOperation() / LutOperation.new instead')
  static LutOperation create() => LutOperation._();
  static $pb.GeneratedMessage $_createMessage() => LutOperation._();
  @$core.override
  LutOperation createEmptyInstance() => LutOperation._();
  @$core.pragma('dart2js:noInline')
  static LutOperation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LutOperation>(
          LutOperation.$_createMessage);
  static LutOperation? _defaultInstance;

  /// Entries per side, 2 to 256.
  @$pb.TagNumber(1)
  $core.int get size => $_getIZ(0);
  @$pb.TagNumber(1)
  set size($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSize() => $_has(0);
  @$pb.TagNumber(1)
  void clearSize() => $_clearField(1);

  /// size³ sRGB-encoded RGB entries, red fastest, as 16-bit little-endian values.
  @$pb.TagNumber(2)
  $core.List<$core.int> get rgb16 => $_getN(1);
  @$pb.TagNumber(2)
  set rgb16($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRgb16() => $_has(1);
  @$pb.TagNumber(2)
  void clearRgb16() => $_clearField(2);
}

/// Adjusts only where a stored mask says so (local, in the original's frame).
class LocalAdjustOperation extends $pb.GeneratedMessage {
  factory LocalAdjustOperation({
    $core.String? outputId,
    AdjustOperation? adjust,
  }) {
    final result = LocalAdjustOperation._();
    if (outputId != null) result.outputId = outputId;
    if (adjust != null) result.adjust = adjust;
    return result;
  }

  LocalAdjustOperation._();

  factory LocalAdjustOperation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LocalAdjustOperation()..mergeFromBuffer(data, registry);
  factory LocalAdjustOperation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LocalAdjustOperation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LocalAdjustOperation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: LocalAdjustOperation.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'outputId')
    ..aOM<AdjustOperation>(2, _omitFieldNames ? '' : 'adjust',
        subBuilder: AdjustOperation.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocalAdjustOperation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocalAdjustOperation copyWith(void Function(LocalAdjustOperation) updates) =>
      super.copyWith((message) => updates(message as LocalAdjustOperation))
          as LocalAdjustOperation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use LocalAdjustOperation() / LocalAdjustOperation.new instead')
  static LocalAdjustOperation create() => LocalAdjustOperation._();
  static $pb.GeneratedMessage $_createMessage() => LocalAdjustOperation._();
  @$core.override
  LocalAdjustOperation createEmptyInstance() => LocalAdjustOperation._();
  @$core.pragma('dart2js:noInline')
  static LocalAdjustOperation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LocalAdjustOperation>(
          LocalAdjustOperation.$_createMessage);
  static LocalAdjustOperation? _defaultInstance;

  /// The `StoredOutput` of kind mask that weighs the adjustment.
  @$pb.TagNumber(1)
  $core.String get outputId => $_getSZ(0);
  @$pb.TagNumber(1)
  set outputId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOutputId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOutputId() => $_clearField(1);

  @$pb.TagNumber(2)
  AdjustOperation get adjust => $_getN(1);
  @$pb.TagNumber(2)
  set adjust(AdjustOperation value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAdjust() => $_has(1);
  @$pb.TagNumber(2)
  void clearAdjust() => $_clearField(2);
  @$pb.TagNumber(2)
  AdjustOperation ensureAdjust() => $_ensure(1);
}

/// Puts a stored patch over a rectangle of the original (local, in the original's frame): the result of an inpainting
/// model, kept so that the model never runs again.
class InpaintOperation extends $pb.GeneratedMessage {
  factory InpaintOperation({
    $core.String? outputId,
    $core.double? x,
    $core.double? y,
    $core.double? width,
    $core.double? height,
  }) {
    final result = InpaintOperation._();
    if (outputId != null) result.outputId = outputId;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    return result;
  }

  InpaintOperation._();

  factory InpaintOperation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InpaintOperation()..mergeFromBuffer(data, registry);
  factory InpaintOperation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InpaintOperation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InpaintOperation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: InpaintOperation.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'outputId')
    ..aD(2, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InpaintOperation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InpaintOperation copyWith(void Function(InpaintOperation) updates) =>
      super.copyWith((message) => updates(message as InpaintOperation))
          as InpaintOperation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use InpaintOperation() / InpaintOperation.new instead')
  static InpaintOperation create() => InpaintOperation._();
  static $pb.GeneratedMessage $_createMessage() => InpaintOperation._();
  @$core.override
  InpaintOperation createEmptyInstance() => InpaintOperation._();
  @$core.pragma('dart2js:noInline')
  static InpaintOperation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<InpaintOperation>(
          InpaintOperation.$_createMessage);
  static InpaintOperation? _defaultInstance;

  /// The `StoredOutput` of kind patch.
  @$pb.TagNumber(1)
  $core.String get outputId => $_getSZ(0);
  @$pb.TagNumber(1)
  set outputId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOutputId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOutputId() => $_clearField(1);

  /// Fractions of the original's width and height where the patch goes, inside the image.
  @$pb.TagNumber(2)
  $core.double get x => $_getN(1);
  @$pb.TagNumber(2)
  set x($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasX() => $_has(1);
  @$pb.TagNumber(2)
  void clearX() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get y => $_getN(2);
  @$pb.TagNumber(3)
  set y($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasY() => $_has(2);
  @$pb.TagNumber(3)
  void clearY() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get width => $_getN(3);
  @$pb.TagNumber(4)
  set width($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasWidth() => $_has(3);
  @$pb.TagNumber(4)
  void clearWidth() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get height => $_getN(4);
  @$pb.TagNumber(5)
  set height($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeight() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeight() => $_clearField(5);
}

/// A result of a model, stored with the recipe: a segmentation mask or an inpainting patch. Its bytes are untrusted
/// input to every reader (threat model T34): sizes are checked against the limits and against the dimensions.
class StoredOutput extends $pb.GeneratedMessage {
  factory StoredOutput({
    $core.String? outputId,
    StoredOutputKind? kind,
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? data,
    ModelUse? model,
  }) {
    final result = StoredOutput._();
    if (outputId != null) result.outputId = outputId;
    if (kind != null) result.kind = kind;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (data != null) result.data = data;
    if (model != null) result.model = model;
    return result;
  }

  StoredOutput._();

  factory StoredOutput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StoredOutput()..mergeFromBuffer(data, registry);
  factory StoredOutput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StoredOutput()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StoredOutput',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: StoredOutput.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'outputId')
    ..aE<StoredOutputKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: StoredOutputKind.values)
    ..aI(3, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOM<ModelUse>(6, _omitFieldNames ? '' : 'model',
        subBuilder: ModelUse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StoredOutput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StoredOutput copyWith(void Function(StoredOutput) updates) =>
      super.copyWith((message) => updates(message as StoredOutput))
          as StoredOutput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StoredOutput() / StoredOutput.new instead')
  static StoredOutput create() => StoredOutput._();
  static $pb.GeneratedMessage $_createMessage() => StoredOutput._();
  @$core.override
  StoredOutput createEmptyInstance() => StoredOutput._();
  @$core.pragma('dart2js:noInline')
  static StoredOutput getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StoredOutput>(
          StoredOutput.$_createMessage);
  static StoredOutput? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get outputId => $_getSZ(0);
  @$pb.TagNumber(1)
  set outputId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOutputId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOutputId() => $_clearField(1);

  @$pb.TagNumber(2)
  StoredOutputKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(StoredOutputKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  /// Pixels, 1 to 8192 each side.
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

  /// Raw pixels row by row: width × height bytes for a mask, ×4 for a patch.
  @$pb.TagNumber(5)
  $core.List<$core.int> get data => $_getN(4);
  @$pb.TagNumber(5)
  set data($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasData() => $_has(4);
  @$pb.TagNumber(5)
  void clearData() => $_clearField(5);

  /// The model that made it.
  @$pb.TagNumber(6)
  ModelUse get model => $_getN(5);
  @$pb.TagNumber(6)
  set model(ModelUse value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasModel() => $_has(5);
  @$pb.TagNumber(6)
  void clearModel() => $_clearField(6);
  @$pb.TagNumber(6)
  ModelUse ensureModel() => $_ensure(5);
}

/// A model and the parameters it ran with.
class ModelUse extends $pb.GeneratedMessage {
  factory ModelUse({
    $core.String? modelId,
    $core.String? modelVersion,
    $core.Iterable<Parameter>? parameters,
  }) {
    final result = ModelUse._();
    if (modelId != null) result.modelId = modelId;
    if (modelVersion != null) result.modelVersion = modelVersion;
    if (parameters != null) result.parameters.addAll(parameters);
    return result;
  }

  ModelUse._();

  factory ModelUse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ModelUse()..mergeFromBuffer(data, registry);
  factory ModelUse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ModelUse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelUse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: ModelUse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'modelVersion')
    ..pPM<Parameter>(3, _omitFieldNames ? '' : 'parameters',
        subBuilder: Parameter.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelUse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelUse copyWith(void Function(ModelUse) updates) =>
      super.copyWith((message) => updates(message as ModelUse)) as ModelUse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ModelUse() / ModelUse.new instead')
  static ModelUse create() => ModelUse._();
  static $pb.GeneratedMessage $_createMessage() => ModelUse._();
  @$core.override
  ModelUse createEmptyInstance() => ModelUse._();
  @$core.pragma('dart2js:noInline')
  static ModelUse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelUse>(ModelUse.$_createMessage);
  static ModelUse? _defaultInstance;

  /// The registry id of the model (ADR-0064), e.g. "sam2-tiny".
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelVersion => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelVersion($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelVersion() => $_clearField(2);

  /// The parameters it ran with (prompt, seed, thresholds), as pairs in the order recorded; at most 32.
  @$pb.TagNumber(3)
  $pb.PbList<Parameter> get parameters => $_getList(2);
}

/// One recorded parameter.
class Parameter extends $pb.GeneratedMessage {
  factory Parameter({
    $core.String? name,
    $core.String? value,
  }) {
    final result = Parameter._();
    if (name != null) result.name = name;
    if (value != null) result.value = value;
    return result;
  }

  Parameter._();

  factory Parameter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Parameter()..mergeFromBuffer(data, registry);
  factory Parameter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Parameter()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Parameter',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: Parameter.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Parameter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Parameter copyWith(void Function(Parameter) updates) =>
      super.copyWith((message) => updates(message as Parameter)) as Parameter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Parameter() / Parameter.new instead')
  static Parameter create() => Parameter._();
  static $pb.GeneratedMessage $_createMessage() => Parameter._();
  @$core.override
  Parameter createEmptyInstance() => Parameter._();
  @$core.pragma('dart2js:noInline')
  static Parameter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Parameter>(Parameter.$_createMessage);
  static Parameter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

/// Where an edit came from (feature EDP-30): recorded with every version and written to every export.
class Provenance extends $pb.GeneratedMessage {
  factory Provenance({
    $core.String? tool,
    $core.Iterable<ModelUse>? models,
    DigitalSourceType? digitalSourceType,
  }) {
    final result = Provenance._();
    if (tool != null) result.tool = tool;
    if (models != null) result.models.addAll(models);
    if (digitalSourceType != null) result.digitalSourceType = digitalSourceType;
    return result;
  }

  Provenance._();

  factory Provenance.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Provenance()..mergeFromBuffer(data, registry);
  factory Provenance.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Provenance()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Provenance',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: Provenance.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'tool')
    ..pPM<ModelUse>(2, _omitFieldNames ? '' : 'models',
        subBuilder: ModelUse.$_createMessage)
    ..aE<DigitalSourceType>(3, _omitFieldNames ? '' : 'digitalSourceType',
        enumValues: DigitalSourceType.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Provenance clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Provenance copyWith(void Function(Provenance) updates) =>
      super.copyWith((message) => updates(message as Provenance)) as Provenance;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Provenance() / Provenance.new instead')
  static Provenance create() => Provenance._();
  static $pb.GeneratedMessage $_createMessage() => Provenance._();
  @$core.override
  Provenance createEmptyInstance() => Provenance._();
  @$core.pragma('dart2js:noInline')
  static Provenance getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Provenance>(Provenance.$_createMessage);
  static Provenance? _defaultInstance;

  /// The editor, with its version, e.g. "photolib/1.4.0 (android)".
  @$pb.TagNumber(1)
  $core.String get tool => $_getSZ(0);
  @$pb.TagNumber(1)
  set tool($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTool() => $_has(0);
  @$pb.TagNumber(1)
  void clearTool() => $_clearField(1);

  /// Every model the recipe's outputs came from, once each; the kernel fills it from the outputs.
  @$pb.TagNumber(2)
  $pb.PbList<ModelUse> get models => $_getList(1);

  /// What the export states; the kernel derives it from the operations and the outputs, and replaces any other value.
  @$pb.TagNumber(3)
  DigitalSourceType get digitalSourceType => $_getN(2);
  @$pb.TagNumber(3)
  set digitalSourceType(DigitalSourceType value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDigitalSourceType() => $_has(2);
  @$pb.TagNumber(3)
  void clearDigitalSourceType() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
