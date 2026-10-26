// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/server_info.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// How a client can prove who it is to this server.
class AuthMethod extends $pb.ProtobufEnum {
  static const AuthMethod AUTH_METHOD_UNSPECIFIED =
      AuthMethod._(0, _omitEnumNames ? '' : 'AUTH_METHOD_UNSPECIFIED');
  static const AuthMethod AUTH_METHOD_OPAQUE =
      AuthMethod._(1, _omitEnumNames ? '' : 'AUTH_METHOD_OPAQUE');
  static const AuthMethod AUTH_METHOD_OIDC =
      AuthMethod._(2, _omitEnumNames ? '' : 'AUTH_METHOD_OIDC');
  static const AuthMethod AUTH_METHOD_PASSKEY =
      AuthMethod._(3, _omitEnumNames ? '' : 'AUTH_METHOD_PASSKEY');

  static const $core.List<AuthMethod> values = <AuthMethod>[
    AUTH_METHOD_UNSPECIFIED,
    AUTH_METHOD_OPAQUE,
    AUTH_METHOD_OIDC,
    AUTH_METHOD_PASSKEY,
  ];

  static final $core.List<AuthMethod?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static AuthMethod? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AuthMethod._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
