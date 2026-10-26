// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/users.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// What an account may do on its server.
class UserRole extends $pb.ProtobufEnum {
  static const UserRole USER_ROLE_UNSPECIFIED =
      UserRole._(0, _omitEnumNames ? '' : 'USER_ROLE_UNSPECIFIED');

  /// Manages the server and its accounts.
  static const UserRole USER_ROLE_ADMIN =
      UserRole._(1, _omitEnumNames ? '' : 'USER_ROLE_ADMIN');

  /// Backs up and organises their own photos.
  static const UserRole USER_ROLE_USER =
      UserRole._(2, _omitEnumNames ? '' : 'USER_ROLE_USER');

  /// Browses what others share with them and never uploads (OPS-27).
  static const UserRole USER_ROLE_VIEWER =
      UserRole._(3, _omitEnumNames ? '' : 'USER_ROLE_VIEWER');

  static const $core.List<UserRole> values = <UserRole>[
    USER_ROLE_UNSPECIFIED,
    USER_ROLE_ADMIN,
    USER_ROLE_USER,
    USER_ROLE_VIEWER,
  ];

  static final $core.List<UserRole?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static UserRole? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const UserRole._(super.value, super.name);
}

/// Whether an account may sign in.
class UserStatus extends $pb.ProtobufEnum {
  static const UserStatus USER_STATUS_UNSPECIFIED =
      UserStatus._(0, _omitEnumNames ? '' : 'USER_STATUS_UNSPECIFIED');
  static const UserStatus USER_STATUS_ACTIVE =
      UserStatus._(1, _omitEnumNames ? '' : 'USER_STATUS_ACTIVE');
  static const UserStatus USER_STATUS_DISABLED =
      UserStatus._(2, _omitEnumNames ? '' : 'USER_STATUS_DISABLED');

  /// Created but never signed in.
  static const UserStatus USER_STATUS_INVITED =
      UserStatus._(3, _omitEnumNames ? '' : 'USER_STATUS_INVITED');

  /// Signs in no more and is purged at `purge_at`; setting another status before then restores it.
  static const UserStatus USER_STATUS_DELETED =
      UserStatus._(4, _omitEnumNames ? '' : 'USER_STATUS_DELETED');

  static const $core.List<UserStatus> values = <UserStatus>[
    USER_STATUS_UNSPECIFIED,
    USER_STATUS_ACTIVE,
    USER_STATUS_DISABLED,
    USER_STATUS_INVITED,
    USER_STATUS_DELETED,
  ];

  static final $core.List<UserStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static UserStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const UserStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
