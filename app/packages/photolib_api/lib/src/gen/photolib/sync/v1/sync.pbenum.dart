// This is a generated file - do not edit.
//
// Generated from photolib/sync/v1/sync.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// What became of a stream.
class StreamStatus extends $pb.ProtobufEnum {
  static const StreamStatus STREAM_STATUS_UNSPECIFIED =
      StreamStatus._(0, _omitEnumNames ? '' : 'STREAM_STATUS_UNSPECIFIED');

  /// Changes follow; the device applies them.
  static const StreamStatus STREAM_STATUS_OK =
      StreamStatus._(1, _omitEnumNames ? '' : 'STREAM_STATUS_OK');

  /// The cursor is from another epoch, too old or unreadable: drop what the stream delivered and start it again with
  /// an empty cursor.
  static const StreamStatus STREAM_STATUS_RESET_REQUIRED =
      StreamStatus._(2, _omitEnumNames ? '' : 'STREAM_STATUS_RESET_REQUIRED');

  /// The stream does not exist or is not the caller's: drop what it delivered.
  static const StreamStatus STREAM_STATUS_FORBIDDEN =
      StreamStatus._(3, _omitEnumNames ? '' : 'STREAM_STATUS_FORBIDDEN');

  static const $core.List<StreamStatus> values = <StreamStatus>[
    STREAM_STATUS_UNSPECIFIED,
    STREAM_STATUS_OK,
    STREAM_STATUS_RESET_REQUIRED,
    STREAM_STATUS_FORBIDDEN,
  ];

  static final $core.List<StreamStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static StreamStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const StreamStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
