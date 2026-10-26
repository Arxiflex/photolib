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

import 'package:protobuf/protobuf.dart' as $pb;

/// Where the zone of a capture time came from.
class ZoneSource extends $pb.ProtobufEnum {
  /// No evidence: the wall clock floats, or only the instant is known.
  static const ZoneSource ZONE_SOURCE_UNSPECIFIED =
      ZoneSource._(0, _omitEnumNames ? '' : 'ZONE_SOURCE_UNSPECIFIED');

  /// The offset written with the winning wall clock, or with one that agrees with it.
  static const ZoneSource ZONE_SOURCE_EXPLICIT_OFFSET =
      ZoneSource._(1, _omitEnumNames ? '' : 'ZONE_SOURCE_EXPLICIT_OFFSET');

  /// The GPS time (UTC) against the wall clock, a whole number of quarter hours apart; a zero delta only where the
  /// host's zone agrees, as it may be one clock read twice.
  static const ZoneSource ZONE_SOURCE_GPS_DELTA =
      ZoneSource._(2, _omitEnumNames ? '' : 'ZONE_SOURCE_GPS_DELTA');

  /// Another UTC claim, such as a Pixel file name or a Takeout time, against the wall clock, as for GPS_DELTA.
  static const ZoneSource ZONE_SOURCE_PAIRED_UTC_DELTA =
      ZoneSource._(3, _omitEnumNames ? '' : 'ZONE_SOURCE_PAIRED_UTC_DELTA');

  /// The host's zone at the GPS position; also over a measured offset it disagrees with (ZONE_MISMATCH).
  static const ZoneSource ZONE_SOURCE_GPS_ZONE =
      ZoneSource._(4, _omitEnumNames ? '' : 'ZONE_SOURCE_GPS_ZONE');

  /// The host's device zone journal.
  static const ZoneSource ZONE_SOURCE_DEVICE_ZONE =
      ZoneSource._(5, _omitEnumNames ? '' : 'ZONE_SOURCE_DEVICE_ZONE');

  /// Assumed: the host's default zone, as no evidence fixed one.
  static const ZoneSource ZONE_SOURCE_DEFAULT_ZONE =
      ZoneSource._(6, _omitEnumNames ? '' : 'ZONE_SOURCE_DEFAULT_ZONE');

  static const $core.List<ZoneSource> values = <ZoneSource>[
    ZONE_SOURCE_UNSPECIFIED,
    ZONE_SOURCE_EXPLICIT_OFFSET,
    ZONE_SOURCE_GPS_DELTA,
    ZONE_SOURCE_PAIRED_UTC_DELTA,
    ZONE_SOURCE_GPS_ZONE,
    ZONE_SOURCE_DEVICE_ZONE,
    ZONE_SOURCE_DEFAULT_ZONE,
  ];

  static final $core.List<ZoneSource?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static ZoneSource? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ZoneSource._(super.value, super.name);
}

/// Something about a capture time the user may want to check.
class CaptureTimeFlag extends $pb.ProtobufEnum {
  static const CaptureTimeFlag CAPTURE_TIME_FLAG_UNSPECIFIED =
      CaptureTimeFlag._(
          0, _omitEnumNames ? '' : 'CAPTURE_TIME_FLAG_UNSPECIFIED');

  /// Claims disagree, or the time is later than a receive date: queue for review.
  static const CaptureTimeFlag CAPTURE_TIME_FLAG_NEEDS_REVIEW =
      CaptureTimeFlag._(
          1, _omitEnumNames ? '' : 'CAPTURE_TIME_FLAG_NEEDS_REVIEW');

  /// Taken after the file was received, saved or transferred.
  static const CaptureTimeFlag CAPTURE_TIME_FLAG_CAPTURE_AFTER_RECEIVE =
      CaptureTimeFlag._(
          2, _omitEnumNames ? '' : 'CAPTURE_TIME_FLAG_CAPTURE_AFTER_RECEIVE');

  /// The wall clock falls in a daylight-saving gap or overlap: the earlier instant was taken.
  static const CaptureTimeFlag CAPTURE_TIME_FLAG_DST_AMBIGUOUS =
      CaptureTimeFlag._(
          3, _omitEnumNames ? '' : 'CAPTURE_TIME_FLAG_DST_AMBIGUOUS');

  /// Only the instant is known, and the wall clock shown comes from the default zone: confirm the zone.
  static const CaptureTimeFlag CAPTURE_TIME_FLAG_ASSUMED_ZONE =
      CaptureTimeFlag._(
          4, _omitEnumNames ? '' : 'CAPTURE_TIME_FLAG_ASSUMED_ZONE');

  /// A measured offset fixed the instant but differs from the zone at the GPS position then (a camera left on home
  /// time, or a stale fix): the wall clock shown is that zone's, the winning claim keeps the camera's. With
  /// NEEDS_REVIEW, where the user may keep the camera's zone.
  static const CaptureTimeFlag CAPTURE_TIME_FLAG_ZONE_MISMATCH =
      CaptureTimeFlag._(
          5, _omitEnumNames ? '' : 'CAPTURE_TIME_FLAG_ZONE_MISMATCH');

  static const $core.List<CaptureTimeFlag> values = <CaptureTimeFlag>[
    CAPTURE_TIME_FLAG_UNSPECIFIED,
    CAPTURE_TIME_FLAG_NEEDS_REVIEW,
    CAPTURE_TIME_FLAG_CAPTURE_AFTER_RECEIVE,
    CAPTURE_TIME_FLAG_DST_AMBIGUOUS,
    CAPTURE_TIME_FLAG_ASSUMED_ZONE,
    CAPTURE_TIME_FLAG_ZONE_MISMATCH,
  ];

  static final $core.List<CaptureTimeFlag?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static CaptureTimeFlag? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CaptureTimeFlag._(super.value, super.name);
}

/// How the winner was chosen.
class CaptureTimeRule extends $pb.ProtobufEnum {
  static const CaptureTimeRule CAPTURE_TIME_RULE_UNSPECIFIED =
      CaptureTimeRule._(
          0, _omitEnumNames ? '' : 'CAPTURE_TIME_RULE_UNSPECIFIED');

  /// Nothing dates the file.
  static const CaptureTimeRule CAPTURE_TIME_RULE_NO_EVIDENCE =
      CaptureTimeRule._(
          1, _omitEnumNames ? '' : 'CAPTURE_TIME_RULE_NO_EVIDENCE');

  /// Every claim that counts agrees.
  static const CaptureTimeRule CAPTURE_TIME_RULE_AGREEMENT =
      CaptureTimeRule._(2, _omitEnumNames ? '' : 'CAPTURE_TIME_RULE_AGREEMENT');

  /// Claims disagree: the most confident group of agreeing claims won.
  static const CaptureTimeRule CAPTURE_TIME_RULE_MOST_CONFIDENT =
      CaptureTimeRule._(
          3, _omitEnumNames ? '' : 'CAPTURE_TIME_RULE_MOST_CONFIDENT');

  static const $core.List<CaptureTimeRule> values = <CaptureTimeRule>[
    CAPTURE_TIME_RULE_UNSPECIFIED,
    CAPTURE_TIME_RULE_NO_EVIDENCE,
    CAPTURE_TIME_RULE_AGREEMENT,
    CAPTURE_TIME_RULE_MOST_CONFIDENT,
  ];

  static final $core.List<CaptureTimeRule?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static CaptureTimeRule? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CaptureTimeRule._(super.value, super.name);
}

/// What a claimed time is the time of.
class TimeEvent extends $pb.ProtobufEnum {
  static const TimeEvent TIME_EVENT_UNSPECIFIED =
      TimeEvent._(0, _omitEnumNames ? '' : 'TIME_EVENT_UNSPECIFIED');

  /// Taking the photo or starting the recording.
  static const TimeEvent TIME_EVENT_CAPTURE =
      TimeEvent._(1, _omitEnumNames ? '' : 'TIME_EVENT_CAPTURE');

  /// Receiving it in a messenger: the file was taken on or before.
  static const TimeEvent TIME_EVENT_RECEIVE =
      TimeEvent._(2, _omitEnumNames ? '' : 'TIME_EVENT_RECEIVE');

  /// Saving it from an app.
  static const TimeEvent TIME_EVENT_SAVE =
      TimeEvent._(3, _omitEnumNames ? '' : 'TIME_EVENT_SAVE');

  /// Copying it off a device or out of a service.
  static const TimeEvent TIME_EVENT_TRANSFER =
      TimeEvent._(4, _omitEnumNames ? '' : 'TIME_EVENT_TRANSFER');

  /// Scanning a print, never the capture time.
  static const TimeEvent TIME_EVENT_SCAN =
      TimeEvent._(5, _omitEnumNames ? '' : 'TIME_EVENT_SCAN');

  static const $core.List<TimeEvent> values = <TimeEvent>[
    TIME_EVENT_UNSPECIFIED,
    TIME_EVENT_CAPTURE,
    TIME_EVENT_RECEIVE,
    TIME_EVENT_SAVE,
    TIME_EVENT_TRANSFER,
    TIME_EVENT_SCAN,
  ];

  static final $core.List<TimeEvent?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static TimeEvent? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TimeEvent._(super.value, super.name);
}

/// The resolver's judgement of one claim.
class ClaimVerdict extends $pb.ProtobufEnum {
  static const ClaimVerdict CLAIM_VERDICT_UNSPECIFIED =
      ClaimVerdict._(0, _omitEnumNames ? '' : 'CLAIM_VERDICT_UNSPECIFIED');

  /// The winner: its wall clock or instant is the capture time.
  static const ClaimVerdict CLAIM_VERDICT_WON =
      ClaimVerdict._(1, _omitEnumNames ? '' : 'CLAIM_VERDICT_WON');

  /// Agrees with the winner and raises its confidence.
  static const ClaimVerdict CLAIM_VERDICT_AGREES =
      ClaimVerdict._(2, _omitEnumNames ? '' : 'CLAIM_VERDICT_AGREES');

  /// Disagrees and is strong enough to need a review.
  static const ClaimVerdict CLAIM_VERDICT_CONFLICTS =
      ClaimVerdict._(3, _omitEnumNames ? '' : 'CLAIM_VERDICT_CONFLICTS');

  /// Disagrees and is too weak to matter.
  static const ClaimVerdict CLAIM_VERDICT_OUTVOTED =
      ClaimVerdict._(4, _omitEnumNames ? '' : 'CLAIM_VERDICT_OUTVOTED');

  /// A receive, save or transfer time that bounds the capture time from above.
  static const ClaimVerdict CLAIM_VERDICT_BOUND =
      ClaimVerdict._(5, _omitEnumNames ? '' : 'CLAIM_VERDICT_BOUND');

  /// A GPS time before the capture: the last fix of the receiver.
  static const ClaimVerdict CLAIM_VERDICT_STALE =
      ClaimVerdict._(6, _omitEnumNames ? '' : 'CLAIM_VERDICT_STALE');

  /// The scan of a print: kept, never a capture time.
  static const ClaimVerdict CLAIM_VERDICT_SCAN_TIME =
      ClaimVerdict._(7, _omitEnumNames ? '' : 'CLAIM_VERDICT_SCAN_TIME');

  /// No date, or one that does not exist, such as 2023-02-29.
  static const ClaimVerdict CLAIM_VERDICT_INVALID =
      ClaimVerdict._(8, _omitEnumNames ? '' : 'CLAIM_VERDICT_INVALID');

  /// A placeholder date of a camera or encoder, such as 1970-01-01 or 0000:00:00.
  static const ClaimVerdict CLAIM_VERDICT_SENTINEL =
      ClaimVerdict._(9, _omitEnumNames ? '' : 'CLAIM_VERDICT_SENTINEL');

  /// Before 1826 or the rule's earliest year, or more than two days after the resolver runs.
  static const ClaimVerdict CLAIM_VERDICT_OUT_OF_RANGE =
      ClaimVerdict._(10, _omitEnumNames ? '' : 'CLAIM_VERDICT_OUT_OF_RANGE');

  /// Day and month could be either way round, as in 04.05.2019.
  static const ClaimVerdict CLAIM_VERDICT_AMBIGUOUS_ORDER =
      ClaimVerdict._(11, _omitEnumNames ? '' : 'CLAIM_VERDICT_AMBIGUOUS_ORDER');

  /// The name has a month and day but no year.
  static const ClaimVerdict CLAIM_VERDICT_NO_YEAR =
      ClaimVerdict._(12, _omitEnumNames ? '' : 'CLAIM_VERDICT_NO_YEAR');

  /// A host claim from a source the resolver does not know.
  static const ClaimVerdict CLAIM_VERDICT_UNKNOWN_SOURCE =
      ClaimVerdict._(13, _omitEnumNames ? '' : 'CLAIM_VERDICT_UNKNOWN_SOURCE');

  static const $core.List<ClaimVerdict> values = <ClaimVerdict>[
    CLAIM_VERDICT_UNSPECIFIED,
    CLAIM_VERDICT_WON,
    CLAIM_VERDICT_AGREES,
    CLAIM_VERDICT_CONFLICTS,
    CLAIM_VERDICT_OUTVOTED,
    CLAIM_VERDICT_BOUND,
    CLAIM_VERDICT_STALE,
    CLAIM_VERDICT_SCAN_TIME,
    CLAIM_VERDICT_INVALID,
    CLAIM_VERDICT_SENTINEL,
    CLAIM_VERDICT_OUT_OF_RANGE,
    CLAIM_VERDICT_AMBIGUOUS_ORDER,
    CLAIM_VERDICT_NO_YEAR,
    CLAIM_VERDICT_UNKNOWN_SOURCE,
  ];

  static final $core.List<ClaimVerdict?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 13);
  static ClaimVerdict? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ClaimVerdict._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
