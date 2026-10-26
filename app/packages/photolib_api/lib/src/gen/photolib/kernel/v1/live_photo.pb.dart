// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/live_photo.proto.

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

/// Pairs the stills and videos of Live Photos among files (design doc 08 §3.4): equal content identifiers first; else a
/// still and a clip of at most 4 s in the same folder whose names agree up to the first dot in any case, captured
/// within 2 s of each other, the closest first, unless both have identifiers. Each file is in one pair at most.
class PairLivePhotosRequest extends $pb.GeneratedMessage {
  factory PairLivePhotosRequest({
    $core.Iterable<LivePhotoPart>? files,
  }) {
    final result = PairLivePhotosRequest._();
    if (files != null) result.files.addAll(files);
    return result;
  }

  PairLivePhotosRequest._();

  factory PairLivePhotosRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PairLivePhotosRequest()..mergeFromBuffer(data, registry);
  factory PairLivePhotosRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PairLivePhotosRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PairLivePhotosRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: PairLivePhotosRequest.$_createMessage)
    ..pPM<LivePhotoPart>(1, _omitFieldNames ? '' : 'files',
        subBuilder: LivePhotoPart.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairLivePhotosRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairLivePhotosRequest copyWith(
          void Function(PairLivePhotosRequest) updates) =>
      super.copyWith((message) => updates(message as PairLivePhotosRequest))
          as PairLivePhotosRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PairLivePhotosRequest() / PairLivePhotosRequest.new instead')
  static PairLivePhotosRequest create() => PairLivePhotosRequest._();
  static $pb.GeneratedMessage $_createMessage() => PairLivePhotosRequest._();
  @$core.override
  PairLivePhotosRequest createEmptyInstance() => PairLivePhotosRequest._();
  @$core.pragma('dart2js:noInline')
  static PairLivePhotosRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PairLivePhotosRequest>(
          PairLivePhotosRequest.$_createMessage);
  static PairLivePhotosRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<LivePhotoPart> get files => $_getList(0);
}

/// A still or a video that may be part of a Live Photo.
class LivePhotoPart extends $pb.GeneratedMessage {
  factory LivePhotoPart({
    $core.String? path,
    $core.bool? video,
    $core.String? contentIdentifier,
    $fixnum.Int64? capturedMs,
    $fixnum.Int64? durationMs,
  }) {
    final result = LivePhotoPart._();
    if (path != null) result.path = path;
    if (video != null) result.video = video;
    if (contentIdentifier != null) result.contentIdentifier = contentIdentifier;
    if (capturedMs != null) result.capturedMs = capturedMs;
    if (durationMs != null) result.durationMs = durationMs;
    return result;
  }

  LivePhotoPart._();

  factory LivePhotoPart.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LivePhotoPart()..mergeFromBuffer(data, registry);
  factory LivePhotoPart.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LivePhotoPart()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LivePhotoPart',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: LivePhotoPart.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOB(2, _omitFieldNames ? '' : 'video')
    ..aOS(3, _omitFieldNames ? '' : 'contentIdentifier')
    ..aInt64(4, _omitFieldNames ? '' : 'capturedMs')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'durationMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LivePhotoPart clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LivePhotoPart copyWith(void Function(LivePhotoPart) updates) =>
      super.copyWith((message) => updates(message as LivePhotoPart))
          as LivePhotoPart;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LivePhotoPart() / LivePhotoPart.new instead')
  static LivePhotoPart create() => LivePhotoPart._();
  static $pb.GeneratedMessage $_createMessage() => LivePhotoPart._();
  @$core.override
  LivePhotoPart createEmptyInstance() => LivePhotoPart._();
  @$core.pragma('dart2js:noInline')
  static LivePhotoPart getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LivePhotoPart>(
          LivePhotoPart.$_createMessage);
  static LivePhotoPart? _defaultInstance;

  /// Its path in the library, folders separated by "/", e.g. "DCIM/IMG_2001.HEIC".
  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  /// A video rather than a still.
  @$pb.TagNumber(2)
  $core.bool get video => $_getBF(1);
  @$pb.TagNumber(2)
  set video($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVideo() => $_has(1);
  @$pb.TagNumber(2)
  void clearVideo() => $_clearField(2);

  /// ReadMetadataResponse.content_identifier.
  @$pb.TagNumber(3)
  $core.String get contentIdentifier => $_getSZ(2);
  @$pb.TagNumber(3)
  set contentIdentifier($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContentIdentifier() => $_has(2);
  @$pb.TagNumber(3)
  void clearContentIdentifier() => $_clearField(3);

  /// The capture instant in milliseconds since the Unix epoch; absent when unknown.
  @$pb.TagNumber(4)
  $fixnum.Int64 get capturedMs => $_getI64(3);
  @$pb.TagNumber(4)
  set capturedMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCapturedMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearCapturedMs() => $_clearField(4);

  /// A video's ReadMetadataResponse.duration_ms.
  @$pb.TagNumber(5)
  $fixnum.Int64 get durationMs => $_getI64(4);
  @$pb.TagNumber(5)
  set durationMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearDurationMs() => $_clearField(5);
}

/// The pairs found.
class PairLivePhotosResponse extends $pb.GeneratedMessage {
  factory PairLivePhotosResponse({
    $core.Iterable<LivePhotoPair>? pairs,
  }) {
    final result = PairLivePhotosResponse._();
    if (pairs != null) result.pairs.addAll(pairs);
    return result;
  }

  PairLivePhotosResponse._();

  factory PairLivePhotosResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PairLivePhotosResponse()..mergeFromBuffer(data, registry);
  factory PairLivePhotosResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PairLivePhotosResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PairLivePhotosResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: PairLivePhotosResponse.$_createMessage)
    ..pPM<LivePhotoPair>(1, _omitFieldNames ? '' : 'pairs',
        subBuilder: LivePhotoPair.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairLivePhotosResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PairLivePhotosResponse copyWith(
          void Function(PairLivePhotosResponse) updates) =>
      super.copyWith((message) => updates(message as PairLivePhotosResponse))
          as PairLivePhotosResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PairLivePhotosResponse() / PairLivePhotosResponse.new instead')
  static PairLivePhotosResponse create() => PairLivePhotosResponse._();
  static $pb.GeneratedMessage $_createMessage() => PairLivePhotosResponse._();
  @$core.override
  PairLivePhotosResponse createEmptyInstance() => PairLivePhotosResponse._();
  @$core.pragma('dart2js:noInline')
  static PairLivePhotosResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PairLivePhotosResponse>(
          PairLivePhotosResponse.$_createMessage);
  static PairLivePhotosResponse? _defaultInstance;

  /// In the order of their stills.
  @$pb.TagNumber(1)
  $pb.PbList<LivePhotoPair> get pairs => $_getList(0);
}

/// A still and its video, as indexes into the request's files.
class LivePhotoPair extends $pb.GeneratedMessage {
  factory LivePhotoPair({
    $core.int? still,
    $core.int? video,
  }) {
    final result = LivePhotoPair._();
    if (still != null) result.still = still;
    if (video != null) result.video = video;
    return result;
  }

  LivePhotoPair._();

  factory LivePhotoPair.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LivePhotoPair()..mergeFromBuffer(data, registry);
  factory LivePhotoPair.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LivePhotoPair()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LivePhotoPair',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: LivePhotoPair.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'still', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'video', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LivePhotoPair clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LivePhotoPair copyWith(void Function(LivePhotoPair) updates) =>
      super.copyWith((message) => updates(message as LivePhotoPair))
          as LivePhotoPair;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LivePhotoPair() / LivePhotoPair.new instead')
  static LivePhotoPair create() => LivePhotoPair._();
  static $pb.GeneratedMessage $_createMessage() => LivePhotoPair._();
  @$core.override
  LivePhotoPair createEmptyInstance() => LivePhotoPair._();
  @$core.pragma('dart2js:noInline')
  static LivePhotoPair getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LivePhotoPair>(
          LivePhotoPair.$_createMessage);
  static LivePhotoPair? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get still => $_getIZ(0);
  @$pb.TagNumber(1)
  set still($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStill() => $_has(0);
  @$pb.TagNumber(1)
  void clearStill() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get video => $_getIZ(1);
  @$pb.TagNumber(2)
  set video($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVideo() => $_has(1);
  @$pb.TagNumber(2)
  void clearVideo() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
