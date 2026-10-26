// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/recipe.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import '../../model/v1/edit_recipe.pb.dart' as $0;
import 'develop.pb.dart' as $1;
import 'recipe.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'recipe.pbenum.dart';

/// Checks an edit recipe and returns it in its canonical form with what a renderer or a database needs of it (roadmap
/// M8-01, ADR-0391). The canonical form has the derived provenance filled in and negative zeros made zero, so that equal
/// edits have equal bytes and one hash.
class ResolveRecipeRequest extends $pb.GeneratedMessage {
  factory ResolveRecipeRequest({
    $0.EditRecipe? recipe,
    $core.int? width,
    $core.int? height,
  }) {
    final result = ResolveRecipeRequest._();
    if (recipe != null) result.recipe = recipe;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    return result;
  }

  ResolveRecipeRequest._();

  factory ResolveRecipeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResolveRecipeRequest()..mergeFromBuffer(data, registry);
  factory ResolveRecipeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResolveRecipeRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResolveRecipeRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ResolveRecipeRequest.$_createMessage)
    ..aOM<$0.EditRecipe>(1, _omitFieldNames ? '' : 'recipe',
        subBuilder: $0.EditRecipe.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolveRecipeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolveRecipeRequest copyWith(void Function(ResolveRecipeRequest) updates) =>
      super.copyWith((message) => updates(message as ResolveRecipeRequest))
          as ResolveRecipeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ResolveRecipeRequest() / ResolveRecipeRequest.new instead')
  static ResolveRecipeRequest create() => ResolveRecipeRequest._();
  static $pb.GeneratedMessage $_createMessage() => ResolveRecipeRequest._();
  @$core.override
  ResolveRecipeRequest createEmptyInstance() => ResolveRecipeRequest._();
  @$core.pragma('dart2js:noInline')
  static ResolveRecipeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResolveRecipeRequest>(
          ResolveRecipeRequest.$_createMessage);
  static ResolveRecipeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.EditRecipe get recipe => $_getN(0);
  @$pb.TagNumber(1)
  set recipe($0.EditRecipe value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRecipe() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecipe() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.EditRecipe ensureRecipe() => $_ensure(0);

  /// The original as shown (EXIF orientation applied), in pixels; without it the sizes and the crop are not computed.
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
}

/// The canonical recipe and what follows from it.
class ResolveRecipeResponse extends $pb.GeneratedMessage {
  factory ResolveRecipeResponse({
    $0.EditRecipe? recipe,
    $core.List<$core.int>? sha256,
    $core.int? width,
    $core.int? height,
    $1.Develop? develop,
    $core.bool? geometryOnly,
    $core.bool? identity,
  }) {
    final result = ResolveRecipeResponse._();
    if (recipe != null) result.recipe = recipe;
    if (sha256 != null) result.sha256 = sha256;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (develop != null) result.develop = develop;
    if (geometryOnly != null) result.geometryOnly = geometryOnly;
    if (identity != null) result.identity = identity;
    return result;
  }

  ResolveRecipeResponse._();

  factory ResolveRecipeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResolveRecipeResponse()..mergeFromBuffer(data, registry);
  factory ResolveRecipeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResolveRecipeResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResolveRecipeResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ResolveRecipeResponse.$_createMessage)
    ..aOM<$0.EditRecipe>(1, _omitFieldNames ? '' : 'recipe',
        subBuilder: $0.EditRecipe.$_createMessage)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'sha256', $pb.PbFieldType.OY)
    ..aI(3, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aOM<$1.Develop>(5, _omitFieldNames ? '' : 'develop',
        subBuilder: $1.Develop.$_createMessage)
    ..aOB(6, _omitFieldNames ? '' : 'geometryOnly')
    ..aOB(7, _omitFieldNames ? '' : 'identity')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolveRecipeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolveRecipeResponse copyWith(
          void Function(ResolveRecipeResponse) updates) =>
      super.copyWith((message) => updates(message as ResolveRecipeResponse))
          as ResolveRecipeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ResolveRecipeResponse() / ResolveRecipeResponse.new instead')
  static ResolveRecipeResponse create() => ResolveRecipeResponse._();
  static $pb.GeneratedMessage $_createMessage() => ResolveRecipeResponse._();
  @$core.override
  ResolveRecipeResponse createEmptyInstance() => ResolveRecipeResponse._();
  @$core.pragma('dart2js:noInline')
  static ResolveRecipeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResolveRecipeResponse>(
          ResolveRecipeResponse.$_createMessage);
  static ResolveRecipeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $0.EditRecipe get recipe => $_getN(0);
  @$pb.TagNumber(1)
  set recipe($0.EditRecipe value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRecipe() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecipe() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.EditRecipe ensureRecipe() => $_ensure(0);

  /// SHA-256 of the canonical recipe's encoding: `versions.recipe_hash`.
  @$pb.TagNumber(2)
  $core.List<$core.int> get sha256 => $_getN(1);
  @$pb.TagNumber(2)
  set sha256($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSha256() => $_has(1);
  @$pb.TagNumber(2)
  void clearSha256() => $_clearField(2);

  /// The edited image's size in pixels, when the request had the original's.
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

  /// The geometry as the kernel's `Develop` has it (turns, mirror, then a crop in pixels of the turned image) and the
  /// global adjustments summed: what `METHOD_DEVELOP` and `METHOD_EDIT_COPY` take. Its crop and size need the
  /// original's size.
  @$pb.TagNumber(5)
  $1.Develop get develop => $_getN(4);
  @$pb.TagNumber(5)
  set develop($1.Develop value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasDevelop() => $_has(4);
  @$pb.TagNumber(5)
  void clearDevelop() => $_clearField(5);
  @$pb.TagNumber(5)
  $1.Develop ensureDevelop() => $_ensure(4);

  /// Whether the recipe changes the geometry alone, so that a JPEG can be edited without decoding it.
  @$pb.TagNumber(6)
  $core.bool get geometryOnly => $_getBF(5);
  @$pb.TagNumber(6)
  set geometryOnly($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasGeometryOnly() => $_has(5);
  @$pb.TagNumber(6)
  void clearGeometryOnly() => $_clearField(6);

  /// Whether it changes nothing: no enabled operation does anything.
  @$pb.TagNumber(7)
  $core.bool get identity => $_getBF(6);
  @$pb.TagNumber(7)
  set identity($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIdentity() => $_has(6);
  @$pb.TagNumber(7)
  void clearIdentity() => $_clearField(7);
}

/// Compares two recipes step by step, by operation id.
class CompareRecipesRequest extends $pb.GeneratedMessage {
  factory CompareRecipesRequest({
    $0.EditRecipe? before,
    $0.EditRecipe? after,
  }) {
    final result = CompareRecipesRequest._();
    if (before != null) result.before = before;
    if (after != null) result.after = after;
    return result;
  }

  CompareRecipesRequest._();

  factory CompareRecipesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CompareRecipesRequest()..mergeFromBuffer(data, registry);
  factory CompareRecipesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CompareRecipesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompareRecipesRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: CompareRecipesRequest.$_createMessage)
    ..aOM<$0.EditRecipe>(1, _omitFieldNames ? '' : 'before',
        subBuilder: $0.EditRecipe.$_createMessage)
    ..aOM<$0.EditRecipe>(2, _omitFieldNames ? '' : 'after',
        subBuilder: $0.EditRecipe.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompareRecipesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompareRecipesRequest copyWith(
          void Function(CompareRecipesRequest) updates) =>
      super.copyWith((message) => updates(message as CompareRecipesRequest))
          as CompareRecipesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CompareRecipesRequest() / CompareRecipesRequest.new instead')
  static CompareRecipesRequest create() => CompareRecipesRequest._();
  static $pb.GeneratedMessage $_createMessage() => CompareRecipesRequest._();
  @$core.override
  CompareRecipesRequest createEmptyInstance() => CompareRecipesRequest._();
  @$core.pragma('dart2js:noInline')
  static CompareRecipesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompareRecipesRequest>(
          CompareRecipesRequest.$_createMessage);
  static CompareRecipesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.EditRecipe get before => $_getN(0);
  @$pb.TagNumber(1)
  set before($0.EditRecipe value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBefore() => $_has(0);
  @$pb.TagNumber(1)
  void clearBefore() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.EditRecipe ensureBefore() => $_ensure(0);

  @$pb.TagNumber(2)
  $0.EditRecipe get after => $_getN(1);
  @$pb.TagNumber(2)
  set after($0.EditRecipe value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAfter() => $_has(1);
  @$pb.TagNumber(2)
  void clearAfter() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.EditRecipe ensureAfter() => $_ensure(1);
}

/// One difference between two recipes.
class RecipeChange extends $pb.GeneratedMessage {
  factory RecipeChange({
    $core.String? subject,
    RecipeChangeKind? kind,
    $core.String? what,
    $core.Iterable<$core.String>? fields,
  }) {
    final result = RecipeChange._();
    if (subject != null) result.subject = subject;
    if (kind != null) result.kind = kind;
    if (what != null) result.what = what;
    if (fields != null) result.fields.addAll(fields);
    return result;
  }

  RecipeChange._();

  factory RecipeChange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecipeChange()..mergeFromBuffer(data, registry);
  factory RecipeChange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecipeChange()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecipeChange',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: RecipeChange.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'subject')
    ..aE<RecipeChangeKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: RecipeChangeKind.values)
    ..aOS(3, _omitFieldNames ? '' : 'what')
    ..pPS(4, _omitFieldNames ? '' : 'fields')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecipeChange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecipeChange copyWith(void Function(RecipeChange) updates) =>
      super.copyWith((message) => updates(message as RecipeChange))
          as RecipeChange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RecipeChange() / RecipeChange.new instead')
  static RecipeChange create() => RecipeChange._();
  static $pb.GeneratedMessage $_createMessage() => RecipeChange._();
  @$core.override
  RecipeChange createEmptyInstance() => RecipeChange._();
  @$core.pragma('dart2js:noInline')
  static RecipeChange getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RecipeChange>(
          RecipeChange.$_createMessage);
  static RecipeChange? _defaultInstance;

  /// The operation's id, an output's id, or "provenance".
  @$pb.TagNumber(1)
  $core.String get subject => $_getSZ(0);
  @$pb.TagNumber(1)
  set subject($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSubject() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubject() => $_clearField(1);

  @$pb.TagNumber(2)
  RecipeChangeKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(RecipeChangeKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  /// What the subject is: "turn", "flip", "crop", "adjust", "lut", "local_adjust", "inpaint", "output", "provenance".
  @$pb.TagNumber(3)
  $core.String get what => $_getSZ(2);
  @$pb.TagNumber(3)
  set what($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWhat() => $_has(2);
  @$pb.TagNumber(3)
  void clearWhat() => $_clearField(3);

  /// For a change, the fields that differ ("x", "disabled", "data").
  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get fields => $_getList(3);
}

/// The differences, in the order of the steps (those of `before` first).
class CompareRecipesResponse extends $pb.GeneratedMessage {
  factory CompareRecipesResponse({
    $core.Iterable<RecipeChange>? changes,
  }) {
    final result = CompareRecipesResponse._();
    if (changes != null) result.changes.addAll(changes);
    return result;
  }

  CompareRecipesResponse._();

  factory CompareRecipesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CompareRecipesResponse()..mergeFromBuffer(data, registry);
  factory CompareRecipesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CompareRecipesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CompareRecipesResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: CompareRecipesResponse.$_createMessage)
    ..pPM<RecipeChange>(1, _omitFieldNames ? '' : 'changes',
        subBuilder: RecipeChange.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompareRecipesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CompareRecipesResponse copyWith(
          void Function(CompareRecipesResponse) updates) =>
      super.copyWith((message) => updates(message as CompareRecipesResponse))
          as CompareRecipesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CompareRecipesResponse() / CompareRecipesResponse.new instead')
  static CompareRecipesResponse create() => CompareRecipesResponse._();
  static $pb.GeneratedMessage $_createMessage() => CompareRecipesResponse._();
  @$core.override
  CompareRecipesResponse createEmptyInstance() => CompareRecipesResponse._();
  @$core.pragma('dart2js:noInline')
  static CompareRecipesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CompareRecipesResponse>(
          CompareRecipesResponse.$_createMessage);
  static CompareRecipesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<RecipeChange> get changes => $_getList(0);
}

/// A rectangle in fractions of an image's width and height.
class Region extends $pb.GeneratedMessage {
  factory Region({
    $core.double? x,
    $core.double? y,
    $core.double? width,
    $core.double? height,
  }) {
    final result = Region._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    return result;
  }

  Region._();

  factory Region.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Region()..mergeFromBuffer(data, registry);
  factory Region.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Region()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Region',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: Region.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Region clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Region copyWith(void Function(Region) updates) =>
      super.copyWith((message) => updates(message as Region)) as Region;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Region() / Region.new instead')
  static Region create() => Region._();
  static $pb.GeneratedMessage $_createMessage() => Region._();
  @$core.override
  Region createEmptyInstance() => Region._();
  @$core.pragma('dart2js:noInline')
  static Region getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Region>(Region.$_createMessage);
  static Region? _defaultInstance;

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

/// Moves regions found in one version of a photo (a face's box, a line of text) to another version of it.
class MapRegionsRequest extends $pb.GeneratedMessage {
  factory MapRegionsRequest({
    $0.EditRecipe? from,
    $0.EditRecipe? to,
    $core.Iterable<Region>? regions,
  }) {
    final result = MapRegionsRequest._();
    if (from != null) result.from = from;
    if (to != null) result.to = to;
    if (regions != null) result.regions.addAll(regions);
    return result;
  }

  MapRegionsRequest._();

  factory MapRegionsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapRegionsRequest()..mergeFromBuffer(data, registry);
  factory MapRegionsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapRegionsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapRegionsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapRegionsRequest.$_createMessage)
    ..aOM<$0.EditRecipe>(1, _omitFieldNames ? '' : 'from',
        subBuilder: $0.EditRecipe.$_createMessage)
    ..aOM<$0.EditRecipe>(2, _omitFieldNames ? '' : 'to',
        subBuilder: $0.EditRecipe.$_createMessage)
    ..pPM<Region>(3, _omitFieldNames ? '' : 'regions',
        subBuilder: Region.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapRegionsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapRegionsRequest copyWith(void Function(MapRegionsRequest) updates) =>
      super.copyWith((message) => updates(message as MapRegionsRequest))
          as MapRegionsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapRegionsRequest() / MapRegionsRequest.new instead')
  static MapRegionsRequest create() => MapRegionsRequest._();
  static $pb.GeneratedMessage $_createMessage() => MapRegionsRequest._();
  @$core.override
  MapRegionsRequest createEmptyInstance() => MapRegionsRequest._();
  @$core.pragma('dart2js:noInline')
  static MapRegionsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MapRegionsRequest>(
          MapRegionsRequest.$_createMessage);
  static MapRegionsRequest? _defaultInstance;

  /// The recipe of the version the regions are in; absent for the original.
  @$pb.TagNumber(1)
  $0.EditRecipe get from => $_getN(0);
  @$pb.TagNumber(1)
  set from($0.EditRecipe value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrom() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.EditRecipe ensureFrom() => $_ensure(0);

  /// The recipe of the version they go to.
  @$pb.TagNumber(2)
  $0.EditRecipe get to => $_getN(1);
  @$pb.TagNumber(2)
  set to($0.EditRecipe value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTo() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.EditRecipe ensureTo() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbList<Region> get regions => $_getList(2);
}

/// A region where it is in the other version.
class MappedRegion extends $pb.GeneratedMessage {
  factory MappedRegion({
    Region? region,
    $core.double? visible,
  }) {
    final result = MappedRegion._();
    if (region != null) result.region = region;
    if (visible != null) result.visible = visible;
    return result;
  }

  MappedRegion._();

  factory MappedRegion.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MappedRegion()..mergeFromBuffer(data, registry);
  factory MappedRegion.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MappedRegion()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MappedRegion',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MappedRegion.$_createMessage)
    ..aOM<Region>(1, _omitFieldNames ? '' : 'region',
        subBuilder: Region.$_createMessage)
    ..aD(2, _omitFieldNames ? '' : 'visible', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MappedRegion clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MappedRegion copyWith(void Function(MappedRegion) updates) =>
      super.copyWith((message) => updates(message as MappedRegion))
          as MappedRegion;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MappedRegion() / MappedRegion.new instead')
  static MappedRegion create() => MappedRegion._();
  static $pb.GeneratedMessage $_createMessage() => MappedRegion._();
  @$core.override
  MappedRegion createEmptyInstance() => MappedRegion._();
  @$core.pragma('dart2js:noInline')
  static MappedRegion getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MappedRegion>(
          MappedRegion.$_createMessage);
  static MappedRegion? _defaultInstance;

  /// The part of the region inside the other version's frame; empty when none is.
  @$pb.TagNumber(1)
  Region get region => $_getN(0);
  @$pb.TagNumber(1)
  set region(Region value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRegion() => $_has(0);
  @$pb.TagNumber(1)
  void clearRegion() => $_clearField(1);
  @$pb.TagNumber(1)
  Region ensureRegion() => $_ensure(0);

  /// The part of the region's area that is inside it, 0 to 1.
  @$pb.TagNumber(2)
  $core.double get visible => $_getN(1);
  @$pb.TagNumber(2)
  set visible($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVisible() => $_has(1);
  @$pb.TagNumber(2)
  void clearVisible() => $_clearField(2);
}

/// One result per request region, in order.
class MapRegionsResponse extends $pb.GeneratedMessage {
  factory MapRegionsResponse({
    $core.Iterable<MappedRegion>? regions,
  }) {
    final result = MapRegionsResponse._();
    if (regions != null) result.regions.addAll(regions);
    return result;
  }

  MapRegionsResponse._();

  factory MapRegionsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapRegionsResponse()..mergeFromBuffer(data, registry);
  factory MapRegionsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapRegionsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapRegionsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapRegionsResponse.$_createMessage)
    ..pPM<MappedRegion>(1, _omitFieldNames ? '' : 'regions',
        subBuilder: MappedRegion.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapRegionsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapRegionsResponse copyWith(void Function(MapRegionsResponse) updates) =>
      super.copyWith((message) => updates(message as MapRegionsResponse))
          as MapRegionsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapRegionsResponse() / MapRegionsResponse.new instead')
  static MapRegionsResponse create() => MapRegionsResponse._();
  static $pb.GeneratedMessage $_createMessage() => MapRegionsResponse._();
  @$core.override
  MapRegionsResponse createEmptyInstance() => MapRegionsResponse._();
  @$core.pragma('dart2js:noInline')
  static MapRegionsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MapRegionsResponse>(
          MapRegionsResponse.$_createMessage);
  static MapRegionsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MappedRegion> get regions => $_getList(0);
}

/// Renders a recipe on the CPU, the reference of every renderer: the local operations, the geometry, then the global
/// adjustments (`METHOD_DEVELOP`'s). Stored outputs are used as they are; no model runs.
class RenderRecipeRequest extends $pb.GeneratedMessage {
  factory RenderRecipeRequest({
    $0.EditRecipe? recipe,
    $1.Image? image,
  }) {
    final result = RenderRecipeRequest._();
    if (recipe != null) result.recipe = recipe;
    if (image != null) result.image = image;
    return result;
  }

  RenderRecipeRequest._();

  factory RenderRecipeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenderRecipeRequest()..mergeFromBuffer(data, registry);
  factory RenderRecipeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenderRecipeRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RenderRecipeRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: RenderRecipeRequest.$_createMessage)
    ..aOM<$0.EditRecipe>(1, _omitFieldNames ? '' : 'recipe',
        subBuilder: $0.EditRecipe.$_createMessage)
    ..aOM<$1.Image>(2, _omitFieldNames ? '' : 'image',
        subBuilder: $1.Image.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenderRecipeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenderRecipeRequest copyWith(void Function(RenderRecipeRequest) updates) =>
      super.copyWith((message) => updates(message as RenderRecipeRequest))
          as RenderRecipeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use RenderRecipeRequest() / RenderRecipeRequest.new instead')
  static RenderRecipeRequest create() => RenderRecipeRequest._();
  static $pb.GeneratedMessage $_createMessage() => RenderRecipeRequest._();
  @$core.override
  RenderRecipeRequest createEmptyInstance() => RenderRecipeRequest._();
  @$core.pragma('dart2js:noInline')
  static RenderRecipeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RenderRecipeRequest>(
          RenderRecipeRequest.$_createMessage);
  static RenderRecipeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $0.EditRecipe get recipe => $_getN(0);
  @$pb.TagNumber(1)
  set recipe($0.EditRecipe value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRecipe() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecipe() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.EditRecipe ensureRecipe() => $_ensure(0);

  /// The original as shown, or a proxy of it (the operations are fractions), 8-bit sRGB RGBA, opaque.
  @$pb.TagNumber(2)
  $1.Image get image => $_getN(1);
  @$pb.TagNumber(2)
  set image($1.Image value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasImage() => $_has(1);
  @$pb.TagNumber(2)
  void clearImage() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Image ensureImage() => $_ensure(1);
}

/// The edited image.
class RenderRecipeResponse extends $pb.GeneratedMessage {
  factory RenderRecipeResponse({
    $1.Image? image,
  }) {
    final result = RenderRecipeResponse._();
    if (image != null) result.image = image;
    return result;
  }

  RenderRecipeResponse._();

  factory RenderRecipeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenderRecipeResponse()..mergeFromBuffer(data, registry);
  factory RenderRecipeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenderRecipeResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RenderRecipeResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: RenderRecipeResponse.$_createMessage)
    ..aOM<$1.Image>(1, _omitFieldNames ? '' : 'image',
        subBuilder: $1.Image.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenderRecipeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenderRecipeResponse copyWith(void Function(RenderRecipeResponse) updates) =>
      super.copyWith((message) => updates(message as RenderRecipeResponse))
          as RenderRecipeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RenderRecipeResponse() / RenderRecipeResponse.new instead')
  static RenderRecipeResponse create() => RenderRecipeResponse._();
  static $pb.GeneratedMessage $_createMessage() => RenderRecipeResponse._();
  @$core.override
  RenderRecipeResponse createEmptyInstance() => RenderRecipeResponse._();
  @$core.pragma('dart2js:noInline')
  static RenderRecipeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RenderRecipeResponse>(
          RenderRecipeResponse.$_createMessage);
  static RenderRecipeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $1.Image get image => $_getN(0);
  @$pb.TagNumber(1)
  set image($1.Image value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasImage() => $_has(0);
  @$pb.TagNumber(1)
  void clearImage() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Image ensureImage() => $_ensure(0);
}

/// Turns the `Develop` of an alpha copy's XMP (ADR-0331) into a recipe.
class RecipeFromDevelopRequest extends $pb.GeneratedMessage {
  factory RecipeFromDevelopRequest({
    $1.Develop? develop,
    $core.int? width,
    $core.int? height,
    $core.String? tool,
  }) {
    final result = RecipeFromDevelopRequest._();
    if (develop != null) result.develop = develop;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (tool != null) result.tool = tool;
    return result;
  }

  RecipeFromDevelopRequest._();

  factory RecipeFromDevelopRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecipeFromDevelopRequest()..mergeFromBuffer(data, registry);
  factory RecipeFromDevelopRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecipeFromDevelopRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecipeFromDevelopRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: RecipeFromDevelopRequest.$_createMessage)
    ..aOM<$1.Develop>(1, _omitFieldNames ? '' : 'develop',
        subBuilder: $1.Develop.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'tool')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecipeFromDevelopRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecipeFromDevelopRequest copyWith(
          void Function(RecipeFromDevelopRequest) updates) =>
      super.copyWith((message) => updates(message as RecipeFromDevelopRequest))
          as RecipeFromDevelopRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RecipeFromDevelopRequest() / RecipeFromDevelopRequest.new instead')
  static RecipeFromDevelopRequest create() => RecipeFromDevelopRequest._();
  static $pb.GeneratedMessage $_createMessage() => RecipeFromDevelopRequest._();
  @$core.override
  RecipeFromDevelopRequest createEmptyInstance() =>
      RecipeFromDevelopRequest._();
  @$core.pragma('dart2js:noInline')
  static RecipeFromDevelopRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RecipeFromDevelopRequest>(
          RecipeFromDevelopRequest.$_createMessage);
  static RecipeFromDevelopRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $1.Develop get develop => $_getN(0);
  @$pb.TagNumber(1)
  set develop($1.Develop value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDevelop() => $_has(0);
  @$pb.TagNumber(1)
  void clearDevelop() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Develop ensureDevelop() => $_ensure(0);

  /// The size in pixels of the original as shown, which the `Develop`'s crop is in.
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

  /// The tool to record, e.g. "photolib-alpha".
  @$pb.TagNumber(4)
  $core.String get tool => $_getSZ(3);
  @$pb.TagNumber(4)
  set tool($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTool() => $_has(3);
  @$pb.TagNumber(4)
  void clearTool() => $_clearField(4);
}

/// The recipe.
class RecipeFromDevelopResponse extends $pb.GeneratedMessage {
  factory RecipeFromDevelopResponse({
    $0.EditRecipe? recipe,
  }) {
    final result = RecipeFromDevelopResponse._();
    if (recipe != null) result.recipe = recipe;
    return result;
  }

  RecipeFromDevelopResponse._();

  factory RecipeFromDevelopResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecipeFromDevelopResponse()..mergeFromBuffer(data, registry);
  factory RecipeFromDevelopResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecipeFromDevelopResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecipeFromDevelopResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: RecipeFromDevelopResponse.$_createMessage)
    ..aOM<$0.EditRecipe>(1, _omitFieldNames ? '' : 'recipe',
        subBuilder: $0.EditRecipe.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecipeFromDevelopResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecipeFromDevelopResponse copyWith(
          void Function(RecipeFromDevelopResponse) updates) =>
      super.copyWith((message) => updates(message as RecipeFromDevelopResponse))
          as RecipeFromDevelopResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RecipeFromDevelopResponse() / RecipeFromDevelopResponse.new instead')
  static RecipeFromDevelopResponse create() => RecipeFromDevelopResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      RecipeFromDevelopResponse._();
  @$core.override
  RecipeFromDevelopResponse createEmptyInstance() =>
      RecipeFromDevelopResponse._();
  @$core.pragma('dart2js:noInline')
  static RecipeFromDevelopResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RecipeFromDevelopResponse>(
          RecipeFromDevelopResponse.$_createMessage);
  static RecipeFromDevelopResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $0.EditRecipe get recipe => $_getN(0);
  @$pb.TagNumber(1)
  set recipe($0.EditRecipe value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRecipe() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecipe() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.EditRecipe ensureRecipe() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
