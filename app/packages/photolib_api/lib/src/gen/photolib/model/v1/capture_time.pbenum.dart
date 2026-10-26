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

/// How finely a capture time is known; a scan of a 1985 photo may only be known to the year.
class CaptureTimePrecision extends $pb.ProtobufEnum {
  static const CaptureTimePrecision CAPTURE_TIME_PRECISION_UNSPECIFIED =
      CaptureTimePrecision._(
          0, _omitEnumNames ? '' : 'CAPTURE_TIME_PRECISION_UNSPECIFIED');
  static const CaptureTimePrecision CAPTURE_TIME_PRECISION_YEAR =
      CaptureTimePrecision._(
          1, _omitEnumNames ? '' : 'CAPTURE_TIME_PRECISION_YEAR');
  static const CaptureTimePrecision CAPTURE_TIME_PRECISION_MONTH =
      CaptureTimePrecision._(
          2, _omitEnumNames ? '' : 'CAPTURE_TIME_PRECISION_MONTH');
  static const CaptureTimePrecision CAPTURE_TIME_PRECISION_DAY =
      CaptureTimePrecision._(
          3, _omitEnumNames ? '' : 'CAPTURE_TIME_PRECISION_DAY');
  static const CaptureTimePrecision CAPTURE_TIME_PRECISION_MINUTE =
      CaptureTimePrecision._(
          4, _omitEnumNames ? '' : 'CAPTURE_TIME_PRECISION_MINUTE');
  static const CaptureTimePrecision CAPTURE_TIME_PRECISION_SECOND =
      CaptureTimePrecision._(
          5, _omitEnumNames ? '' : 'CAPTURE_TIME_PRECISION_SECOND');
  static const CaptureTimePrecision CAPTURE_TIME_PRECISION_MILLISECOND =
      CaptureTimePrecision._(
          6, _omitEnumNames ? '' : 'CAPTURE_TIME_PRECISION_MILLISECOND');

  static const $core.List<CaptureTimePrecision> values = <CaptureTimePrecision>[
    CAPTURE_TIME_PRECISION_UNSPECIFIED,
    CAPTURE_TIME_PRECISION_YEAR,
    CAPTURE_TIME_PRECISION_MONTH,
    CAPTURE_TIME_PRECISION_DAY,
    CAPTURE_TIME_PRECISION_MINUTE,
    CAPTURE_TIME_PRECISION_SECOND,
    CAPTURE_TIME_PRECISION_MILLISECOND,
  ];

  static final $core.List<CaptureTimePrecision?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static CaptureTimePrecision? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CaptureTimePrecision._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
