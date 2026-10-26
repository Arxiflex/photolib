// This is a generated file - do not edit.
//
// Generated from photolib/model/v1/capture_time.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'capture_time.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'capture_time.pbenum.dart';

/// When a photo or video was taken. The wall clock is always kept and the zone is explicit; an unknown zone is
/// absent, never UTC, so a bare instant is not a capture time.
class CaptureTime extends $pb.GeneratedMessage {
  factory CaptureTime({
    $core.String? localDatetime,
    $core.int? offsetMinutes,
    $core.String? zone,
    CaptureTimePrecision? precision,
    $core.String? source,
    $core.int? confidence,
  }) {
    final result = CaptureTime._();
    if (localDatetime != null) result.localDatetime = localDatetime;
    if (offsetMinutes != null) result.offsetMinutes = offsetMinutes;
    if (zone != null) result.zone = zone;
    if (precision != null) result.precision = precision;
    if (source != null) result.source = source;
    if (confidence != null) result.confidence = confidence;
    return result;
  }

  CaptureTime._();

  factory CaptureTime.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CaptureTime()..mergeFromBuffer(data, registry);
  factory CaptureTime.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CaptureTime()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CaptureTime',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: CaptureTime.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'localDatetime')
    ..aI(2, _omitFieldNames ? '' : 'offsetMinutes',
        fieldType: $pb.PbFieldType.OS3)
    ..aOS(3, _omitFieldNames ? '' : 'zone')
    ..aE<CaptureTimePrecision>(4, _omitFieldNames ? '' : 'precision',
        enumValues: CaptureTimePrecision.values)
    ..aOS(5, _omitFieldNames ? '' : 'source')
    ..aI(6, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CaptureTime clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CaptureTime copyWith(void Function(CaptureTime) updates) =>
      super.copyWith((message) => updates(message as CaptureTime))
          as CaptureTime;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CaptureTime() / CaptureTime.new instead')
  static CaptureTime create() => CaptureTime._();
  static $pb.GeneratedMessage $_createMessage() => CaptureTime._();
  @$core.override
  CaptureTime createEmptyInstance() => CaptureTime._();
  @$core.pragma('dart2js:noInline')
  static CaptureTime getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CaptureTime>(
          CaptureTime.$_createMessage);
  static CaptureTime? _defaultInstance;

  /// Wall-clock time as the camera showed it, ISO 8601 without a zone, e.g. "2025-07-14T16:03:09.250".
  @$pb.TagNumber(1)
  $core.String get localDatetime => $_getSZ(0);
  @$pb.TagNumber(1)
  set localDatetime($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLocalDatetime() => $_has(0);
  @$pb.TagNumber(1)
  void clearLocalDatetime() => $_clearField(1);

  /// Offset of the wall clock from UTC in minutes, e.g. 120 for UTC+02:00; absent when unknown.
  @$pb.TagNumber(2)
  $core.int get offsetMinutes => $_getIZ(1);
  @$pb.TagNumber(2)
  set offsetMinutes($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffsetMinutes() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffsetMinutes() => $_clearField(2);

  /// IANA zone name, e.g. "Europe/Berlin"; absent when unknown.
  @$pb.TagNumber(3)
  $core.String get zone => $_getSZ(2);
  @$pb.TagNumber(3)
  set zone($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasZone() => $_has(2);
  @$pb.TagNumber(3)
  void clearZone() => $_clearField(3);

  @$pb.TagNumber(4)
  CaptureTimePrecision get precision => $_getN(3);
  @$pb.TagNumber(4)
  set precision(CaptureTimePrecision value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPrecision() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrecision() => $_clearField(4);

  /// The winning evidence, e.g. "exif:DateTimeOriginal", "filename:F03" or "unknown".
  @$pb.TagNumber(5)
  $core.String get source => $_getSZ(4);
  @$pb.TagNumber(5)
  set source($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSource() => $_has(4);
  @$pb.TagNumber(5)
  void clearSource() => $_clearField(5);

  /// Confidence in the time from 0 to 100.
  @$pb.TagNumber(6)
  $core.int get confidence => $_getIZ(5);
  @$pb.TagNumber(6)
  set confidence($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasConfidence() => $_has(5);
  @$pb.TagNumber(6)
  void clearConfidence() => $_clearField(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
