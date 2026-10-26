// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/api_keys.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// What an API key may do as its account, and only what the account itself may do. No scope manages keys.
class ApiKeyScope extends $pb.ProtobufEnum {
  static const ApiKeyScope API_KEY_SCOPE_UNSPECIFIED =
      ApiKeyScope._(0, _omitEnumNames ? '' : 'API_KEY_SCOPE_UNSPECIFIED');

  /// See metadata, thumbnails and previews, and sync.
  static const ApiKeyScope API_KEY_SCOPE_VIEW =
      ApiKeyScope._(1, _omitEnumNames ? '' : 'API_KEY_SCOPE_VIEW');

  /// Fetch originals.
  static const ApiKeyScope API_KEY_SCOPE_DOWNLOAD =
      ApiKeyScope._(2, _omitEnumNames ? '' : 'API_KEY_SCOPE_DOWNLOAD');

  /// Upload, and add to albums.
  static const ApiKeyScope API_KEY_SCOPE_CONTRIBUTE =
      ApiKeyScope._(3, _omitEnumNames ? '' : 'API_KEY_SCOPE_CONTRIBUTE');

  /// Change metadata, albums and libraries.
  static const ApiKeyScope API_KEY_SCOPE_EDIT =
      ApiKeyScope._(4, _omitEnumNames ? '' : 'API_KEY_SCOPE_EDIT');

  /// Trash and delete.
  static const ApiKeyScope API_KEY_SCOPE_DELETE =
      ApiKeyScope._(5, _omitEnumNames ? '' : 'API_KEY_SCOPE_DELETE');

  /// Give others access.
  static const ApiKeyScope API_KEY_SCOPE_SHARE =
      ApiKeyScope._(6, _omitEnumNames ? '' : 'API_KEY_SCOPE_SHARE');

  /// Manage the server's accounts, with an administrator's key.
  static const ApiKeyScope API_KEY_SCOPE_MANAGE_USERS =
      ApiKeyScope._(7, _omitEnumNames ? '' : 'API_KEY_SCOPE_MANAGE_USERS');

  /// Run the server (the admin console), with an administrator's key; never pause maintenance jobs.
  static const ApiKeyScope API_KEY_SCOPE_MANAGE_SERVER =
      ApiKeyScope._(8, _omitEnumNames ? '' : 'API_KEY_SCOPE_MANAGE_SERVER');

  static const $core.List<ApiKeyScope> values = <ApiKeyScope>[
    API_KEY_SCOPE_UNSPECIFIED,
    API_KEY_SCOPE_VIEW,
    API_KEY_SCOPE_DOWNLOAD,
    API_KEY_SCOPE_CONTRIBUTE,
    API_KEY_SCOPE_EDIT,
    API_KEY_SCOPE_DELETE,
    API_KEY_SCOPE_SHARE,
    API_KEY_SCOPE_MANAGE_USERS,
    API_KEY_SCOPE_MANAGE_SERVER,
  ];

  static final $core.List<ApiKeyScope?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 8);
  static ApiKeyScope? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ApiKeyScope._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
