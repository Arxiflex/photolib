// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/capture_time.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $1;

import '../../model/v1/capture_time.pb.dart' as $0;
import 'capture_time.pbenum.dart';
import 'metadata.pb.dart' as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'capture_time.pbenum.dart';

/// Resolves when a file was captured from every claim about it: its embedded metadata, its name and folders, and what
/// the host read elsewhere (design doc 13 §4). Pure: the current time and the time zones are inputs.
class ResolveCaptureTimeRequest extends $pb.GeneratedMessage {
  factory ResolveCaptureTimeRequest({
    $core.List<$core.int>? head,
    $core.String? fileName,
    $core.String? folder,
    $core.Iterable<$0.CaptureTime>? claims,
    TimeZone? gpsZone,
    TimeZone? deviceZone,
    $1.Timestamp? resolvedAt,
    $core.Iterable<$2.FileRange>? ranges,
    $fixnum.Int64? size,
    TimeZone? defaultZone,
  }) {
    final result = ResolveCaptureTimeRequest._();
    if (head != null) result.head = head;
    if (fileName != null) result.fileName = fileName;
    if (folder != null) result.folder = folder;
    if (claims != null) result.claims.addAll(claims);
    if (gpsZone != null) result.gpsZone = gpsZone;
    if (deviceZone != null) result.deviceZone = deviceZone;
    if (resolvedAt != null) result.resolvedAt = resolvedAt;
    if (ranges != null) result.ranges.addAll(ranges);
    if (size != null) result.size = size;
    if (defaultZone != null) result.defaultZone = defaultZone;
    return result;
  }

  ResolveCaptureTimeRequest._();

  factory ResolveCaptureTimeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResolveCaptureTimeRequest()..mergeFromBuffer(data, registry);
  factory ResolveCaptureTimeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResolveCaptureTimeRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResolveCaptureTimeRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ResolveCaptureTimeRequest.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'head', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'fileName')
    ..aOS(3, _omitFieldNames ? '' : 'folder')
    ..pPM<$0.CaptureTime>(4, _omitFieldNames ? '' : 'claims',
        subBuilder: $0.CaptureTime.$_createMessage)
    ..aOM<TimeZone>(5, _omitFieldNames ? '' : 'gpsZone',
        subBuilder: TimeZone.$_createMessage)
    ..aOM<TimeZone>(6, _omitFieldNames ? '' : 'deviceZone',
        subBuilder: TimeZone.$_createMessage)
    ..aOM<$1.Timestamp>(7, _omitFieldNames ? '' : 'resolvedAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..pPM<$2.FileRange>(8, _omitFieldNames ? '' : 'ranges',
        subBuilder: $2.FileRange.$_createMessage)
    ..a<$fixnum.Int64>(9, _omitFieldNames ? '' : 'size', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<TimeZone>(10, _omitFieldNames ? '' : 'defaultZone',
        subBuilder: TimeZone.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolveCaptureTimeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolveCaptureTimeRequest copyWith(
          void Function(ResolveCaptureTimeRequest) updates) =>
      super.copyWith((message) => updates(message as ResolveCaptureTimeRequest))
          as ResolveCaptureTimeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ResolveCaptureTimeRequest() / ResolveCaptureTimeRequest.new instead')
  static ResolveCaptureTimeRequest create() => ResolveCaptureTimeRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      ResolveCaptureTimeRequest._();
  @$core.override
  ResolveCaptureTimeRequest createEmptyInstance() =>
      ResolveCaptureTimeRequest._();
  @$core.pragma('dart2js:noInline')
  static ResolveCaptureTimeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResolveCaptureTimeRequest>(
          ResolveCaptureTimeRequest.$_createMessage);
  static ResolveCaptureTimeRequest? _defaultInstance;

  /// The start of the file up to the end of its metadata; for a JPEG, up to the end of the EXIF segment. Unused when
  /// ranges are given.
  @$pb.TagNumber(1)
  $core.List<$core.int> get head => $_getN(0);
  @$pb.TagNumber(1)
  set head($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHead() => $_has(0);
  @$pb.TagNumber(1)
  void clearHead() => $_clearField(1);

  /// The original file name without its directory, as the source named it (a Takeout title, PhotoKit's
  /// originalFilename), e.g. "IMG_20250714_160309.jpg".
  @$pb.TagNumber(2)
  $core.String get fileName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFileName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileName() => $_clearField(2);

  /// The folders above the file below the import root, "/"-separated, e.g. "2019/05/09".
  @$pb.TagNumber(3)
  $core.String get folder => $_getSZ(2);
  @$pb.TagNumber(3)
  set folder($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFolder() => $_has(2);
  @$pb.TagNumber(3)
  void clearFolder() => $_clearField(3);

  /// Claims the host read elsewhere, as ISO 8601 wall clocks: "quicktime:creationdate" (local with its offset),
  /// "quicktime:mvhd" (UTC with offset 0 from a phone, a camera's local clock without one) and
  /// "takeout:photoTakenTime" (UTC, offset 0). Other sources are rejected. A movie's own dates are claims of these
  /// sources too: its mvhd time is UTC unless its make is a camera maker's; a host claim replaces the file's own of the
  /// same source.
  @$pb.TagNumber(4)
  $pb.PbList<$0.CaptureTime> get claims => $_getList(3);

  /// The zone at the file's GPS position, which the host looked up; absent when it has none.
  @$pb.TagNumber(5)
  TimeZone get gpsZone => $_getN(4);
  @$pb.TagNumber(5)
  set gpsZone(TimeZone value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasGpsZone() => $_has(4);
  @$pb.TagNumber(5)
  void clearGpsZone() => $_clearField(5);
  @$pb.TagNumber(5)
  TimeZone ensureGpsZone() => $_ensure(4);

  /// The capturing device's zone over time, from its zone journal; only for files this device captured.
  @$pb.TagNumber(6)
  TimeZone get deviceZone => $_getN(5);
  @$pb.TagNumber(6)
  set deviceZone(TimeZone value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasDeviceZone() => $_has(5);
  @$pb.TagNumber(6)
  void clearDeviceZone() => $_clearField(6);
  @$pb.TagNumber(6)
  TimeZone ensureDeviceZone() => $_ensure(5);

  /// When the resolver runs: a claim more than two days later is implausible. Absent, no claim is too late.
  @$pb.TagNumber(7)
  $1.Timestamp get resolvedAt => $_getN(6);
  @$pb.TagNumber(7)
  set resolvedAt($1.Timestamp value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasResolvedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearResolvedAt() => $_clearField(7);
  @$pb.TagNumber(7)
  $1.Timestamp ensureResolvedAt() => $_ensure(6);

  /// The pieces of the file that ReadMetadata read, with the file's size, instead of head: a host that reads files in
  /// ranges resolves from the bytes it already has.
  @$pb.TagNumber(8)
  $pb.PbList<$2.FileRange> get ranges => $_getList(7);

  @$pb.TagNumber(9)
  $fixnum.Int64 get size => $_getI64(8);
  @$pb.TagNumber(9)
  set size($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSize() => $_has(8);
  @$pb.TagNumber(9)
  void clearSize() => $_clearField(9);

  /// The zone to assume when no evidence fixes one, which the host chose: the import run's, a rule for the device or
  /// camera, or the library's (the owner's home zone); never the server's zone or UTC for want of one.
  @$pb.TagNumber(10)
  TimeZone get defaultZone => $_getN(9);
  @$pb.TagNumber(10)
  set defaultZone(TimeZone value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasDefaultZone() => $_has(9);
  @$pb.TagNumber(10)
  void clearDefaultZone() => $_clearField(10);
  @$pb.TagNumber(10)
  TimeZone ensureDefaultZone() => $_ensure(9);
}

/// A time zone as a table of UTC offsets, which the host takes from the IANA database.
class TimeZone extends $pb.GeneratedMessage {
  factory TimeZone({
    $core.String? name,
    $core.Iterable<ZoneOffset>? offsets,
  }) {
    final result = TimeZone._();
    if (name != null) result.name = name;
    if (offsets != null) result.offsets.addAll(offsets);
    return result;
  }

  TimeZone._();

  factory TimeZone.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TimeZone()..mergeFromBuffer(data, registry);
  factory TimeZone.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TimeZone()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TimeZone',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: TimeZone.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..pPM<ZoneOffset>(2, _omitFieldNames ? '' : 'offsets',
        subBuilder: ZoneOffset.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimeZone clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimeZone copyWith(void Function(TimeZone) updates) =>
      super.copyWith((message) => updates(message as TimeZone)) as TimeZone;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TimeZone() / TimeZone.new instead')
  static TimeZone create() => TimeZone._();
  static $pb.GeneratedMessage $_createMessage() => TimeZone._();
  @$core.override
  TimeZone createEmptyInstance() => TimeZone._();
  @$core.pragma('dart2js:noInline')
  static TimeZone getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TimeZone>(TimeZone.$_createMessage);
  static TimeZone? _defaultInstance;

  /// IANA name, e.g. "Europe/Paris".
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// In time order; each offset holds until the next one starts, and the first one also before it starts.
  @$pb.TagNumber(2)
  $pb.PbList<ZoneOffset> get offsets => $_getList(1);
}

/// An offset of a time zone from UTC and when it starts.
class ZoneOffset extends $pb.GeneratedMessage {
  factory ZoneOffset({
    $1.Timestamp? startsAt,
    $core.int? offsetMinutes,
  }) {
    final result = ZoneOffset._();
    if (startsAt != null) result.startsAt = startsAt;
    if (offsetMinutes != null) result.offsetMinutes = offsetMinutes;
    return result;
  }

  ZoneOffset._();

  factory ZoneOffset.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ZoneOffset()..mergeFromBuffer(data, registry);
  factory ZoneOffset.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ZoneOffset()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ZoneOffset',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ZoneOffset.$_createMessage)
    ..aOM<$1.Timestamp>(1, _omitFieldNames ? '' : 'startsAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'offsetMinutes',
        fieldType: $pb.PbFieldType.OS3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ZoneOffset clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ZoneOffset copyWith(void Function(ZoneOffset) updates) =>
      super.copyWith((message) => updates(message as ZoneOffset)) as ZoneOffset;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ZoneOffset() / ZoneOffset.new instead')
  static ZoneOffset create() => ZoneOffset._();
  static $pb.GeneratedMessage $_createMessage() => ZoneOffset._();
  @$core.override
  ZoneOffset createEmptyInstance() => ZoneOffset._();
  @$core.pragma('dart2js:noInline')
  static ZoneOffset getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ZoneOffset>(ZoneOffset.$_createMessage);
  static ZoneOffset? _defaultInstance;

  @$pb.TagNumber(1)
  $1.Timestamp get startsAt => $_getN(0);
  @$pb.TagNumber(1)
  set startsAt($1.Timestamp value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStartsAt() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartsAt() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Timestamp ensureStartsAt() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.int get offsetMinutes => $_getIZ(1);
  @$pb.TagNumber(2)
  set offsetMinutes($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffsetMinutes() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffsetMinutes() => $_clearField(2);
}

/// The resolved capture time and why ("why this date?").
class ResolveCaptureTimeResponse extends $pb.GeneratedMessage {
  factory ResolveCaptureTimeResponse({
    $0.CaptureTime? captureTime,
    $1.Timestamp? takenAt,
    ZoneSource? zoneSource,
    $core.bool? upperBound,
    $core.Iterable<CaptureTimeFlag>? flags,
    $core.Iterable<TimeClaim>? claims,
    CaptureTimeRule? rule,
  }) {
    final result = ResolveCaptureTimeResponse._();
    if (captureTime != null) result.captureTime = captureTime;
    if (takenAt != null) result.takenAt = takenAt;
    if (zoneSource != null) result.zoneSource = zoneSource;
    if (upperBound != null) result.upperBound = upperBound;
    if (flags != null) result.flags.addAll(flags);
    if (claims != null) result.claims.addAll(claims);
    if (rule != null) result.rule = rule;
    return result;
  }

  ResolveCaptureTimeResponse._();

  factory ResolveCaptureTimeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResolveCaptureTimeResponse()..mergeFromBuffer(data, registry);
  factory ResolveCaptureTimeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResolveCaptureTimeResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResolveCaptureTimeResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ResolveCaptureTimeResponse.$_createMessage)
    ..aOM<$0.CaptureTime>(1, _omitFieldNames ? '' : 'captureTime',
        subBuilder: $0.CaptureTime.$_createMessage)
    ..aOM<$1.Timestamp>(2, _omitFieldNames ? '' : 'takenAt',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aE<ZoneSource>(3, _omitFieldNames ? '' : 'zoneSource',
        enumValues: ZoneSource.values)
    ..aOB(4, _omitFieldNames ? '' : 'upperBound')
    ..pc<CaptureTimeFlag>(5, _omitFieldNames ? '' : 'flags', $pb.PbFieldType.KE,
        valueOf: CaptureTimeFlag.valueOf,
        enumValues: CaptureTimeFlag.values,
        defaultEnumValue: CaptureTimeFlag.CAPTURE_TIME_FLAG_UNSPECIFIED)
    ..pPM<TimeClaim>(6, _omitFieldNames ? '' : 'claims',
        subBuilder: TimeClaim.$_createMessage)
    ..aE<CaptureTimeRule>(7, _omitFieldNames ? '' : 'rule',
        enumValues: CaptureTimeRule.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolveCaptureTimeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResolveCaptureTimeResponse copyWith(
          void Function(ResolveCaptureTimeResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ResolveCaptureTimeResponse))
          as ResolveCaptureTimeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ResolveCaptureTimeResponse() / ResolveCaptureTimeResponse.new instead')
  static ResolveCaptureTimeResponse create() => ResolveCaptureTimeResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      ResolveCaptureTimeResponse._();
  @$core.override
  ResolveCaptureTimeResponse createEmptyInstance() =>
      ResolveCaptureTimeResponse._();
  @$core.pragma('dart2js:noInline')
  static ResolveCaptureTimeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResolveCaptureTimeResponse>(
          ResolveCaptureTimeResponse.$_createMessage);
  static ResolveCaptureTimeResponse? _defaultInstance;

  /// The winning claim's wall clock, the offset and zone found for it, its precision, source and confidence; the
  /// source is "unknown" when nothing dates the file. local_datetime is empty when only the instant is known and the
  /// offset absent when the wall clock floats.
  @$pb.TagNumber(1)
  $0.CaptureTime get captureTime => $_getN(0);
  @$pb.TagNumber(1)
  set captureTime($0.CaptureTime value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCaptureTime() => $_has(0);
  @$pb.TagNumber(1)
  void clearCaptureTime() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.CaptureTime ensureCaptureTime() => $_ensure(0);

  /// The instant; absent when the wall clock floats or the date has no time of day.
  @$pb.TagNumber(2)
  $1.Timestamp get takenAt => $_getN(1);
  @$pb.TagNumber(2)
  set takenAt($1.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasTakenAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearTakenAt() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Timestamp ensureTakenAt() => $_ensure(1);

  @$pb.TagNumber(3)
  ZoneSource get zoneSource => $_getN(2);
  @$pb.TagNumber(3)
  set zoneSource(ZoneSource value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasZoneSource() => $_has(2);
  @$pb.TagNumber(3)
  void clearZoneSource() => $_clearField(3);

  /// The file was taken on or before this time: the winner is a receive, save or transfer date.
  @$pb.TagNumber(4)
  $core.bool get upperBound => $_getBF(3);
  @$pb.TagNumber(4)
  set upperBound($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUpperBound() => $_has(3);
  @$pb.TagNumber(4)
  void clearUpperBound() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<CaptureTimeFlag> get flags => $_getList(4);

  /// Every claim considered, in the order read: embedded metadata, the host's, the file name's, the folders'.
  @$pb.TagNumber(6)
  $pb.PbList<TimeClaim> get claims => $_getList(5);

  @$pb.TagNumber(7)
  CaptureTimeRule get rule => $_getN(6);
  @$pb.TagNumber(7)
  set rule(CaptureTimeRule value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasRule() => $_has(6);
  @$pb.TagNumber(7)
  void clearRule() => $_clearField(7);
}

/// One claim about when a file was taken, as the resolver read and judged it.
class TimeClaim extends $pb.GeneratedMessage {
  factory TimeClaim({
    $0.CaptureTime? time,
    TimeEvent? event,
    ClaimVerdict? verdict,
  }) {
    final result = TimeClaim._();
    if (time != null) result.time = time;
    if (event != null) result.event = event;
    if (verdict != null) result.verdict = verdict;
    return result;
  }

  TimeClaim._();

  factory TimeClaim.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TimeClaim()..mergeFromBuffer(data, registry);
  factory TimeClaim.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TimeClaim()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TimeClaim',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: TimeClaim.$_createMessage)
    ..aOM<$0.CaptureTime>(1, _omitFieldNames ? '' : 'time',
        subBuilder: $0.CaptureTime.$_createMessage)
    ..aE<TimeEvent>(2, _omitFieldNames ? '' : 'event',
        enumValues: TimeEvent.values)
    ..aE<ClaimVerdict>(3, _omitFieldNames ? '' : 'verdict',
        enumValues: ClaimVerdict.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimeClaim clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimeClaim copyWith(void Function(TimeClaim) updates) =>
      super.copyWith((message) => updates(message as TimeClaim)) as TimeClaim;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TimeClaim() / TimeClaim.new instead')
  static TimeClaim create() => TimeClaim._();
  static $pb.GeneratedMessage $_createMessage() => TimeClaim._();
  @$core.override
  TimeClaim createEmptyInstance() => TimeClaim._();
  @$core.pragma('dart2js:noInline')
  static TimeClaim getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TimeClaim>(TimeClaim.$_createMessage);
  static TimeClaim? _defaultInstance;

  /// Source, wall clock (a UTC reading with offset 0), precision, and the confidence after the checks, 0 if rejected.
  @$pb.TagNumber(1)
  $0.CaptureTime get time => $_getN(0);
  @$pb.TagNumber(1)
  set time($0.CaptureTime value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTime() => $_has(0);
  @$pb.TagNumber(1)
  void clearTime() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.CaptureTime ensureTime() => $_ensure(0);

  @$pb.TagNumber(2)
  TimeEvent get event => $_getN(1);
  @$pb.TagNumber(2)
  set event(TimeEvent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEvent() => $_has(1);
  @$pb.TagNumber(2)
  void clearEvent() => $_clearField(2);

  @$pb.TagNumber(3)
  ClaimVerdict get verdict => $_getN(2);
  @$pb.TagNumber(3)
  set verdict(ClaimVerdict value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasVerdict() => $_has(2);
  @$pb.TagNumber(3)
  void clearVerdict() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
