// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/events.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// What happened to an asset (ADR-0263).
class EventType extends $pb.ProtobufEnum {
  static const EventType EVENT_TYPE_UNSPECIFIED =
      EventType._(0, _omitEnumNames ? '' : 'EVENT_TYPE_UNSPECIFIED');

  /// Uploaded, imported or found by a scan.
  static const EventType EVENT_TYPE_ASSET_CREATED =
      EventType._(1, _omitEnumNames ? '' : 'EVENT_TYPE_ASSET_CREATED');

  /// Moved to the trash.
  static const EventType EVENT_TYPE_ASSET_TRASHED =
      EventType._(2, _omitEnumNames ? '' : 'EVENT_TYPE_ASSET_TRASHED');

  /// Taken out of the trash.
  static const EventType EVENT_TYPE_ASSET_RESTORED =
      EventType._(3, _omitEnumNames ? '' : 'EVENT_TYPE_ASSET_RESTORED');

  /// Deleted for good.
  static const EventType EVENT_TYPE_ASSET_DELETED =
      EventType._(4, _omitEnumNames ? '' : 'EVENT_TYPE_ASSET_DELETED');

  static const $core.List<EventType> values = <EventType>[
    EVENT_TYPE_UNSPECIFIED,
    EVENT_TYPE_ASSET_CREATED,
    EVENT_TYPE_ASSET_TRASHED,
    EVENT_TYPE_ASSET_RESTORED,
    EVENT_TYPE_ASSET_DELETED,
  ];

  static final $core.List<EventType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static EventType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EventType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
