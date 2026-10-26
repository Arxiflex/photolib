// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/auth.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// A way to prove a sign-in besides the password.
class SecondFactor extends $pb.ProtobufEnum {
  static const SecondFactor SECOND_FACTOR_UNSPECIFIED =
      SecondFactor._(0, _omitEnumNames ? '' : 'SECOND_FACTOR_UNSPECIFIED');

  /// A six-digit code from an authenticator app (RFC 6238).
  static const SecondFactor SECOND_FACTOR_TOTP =
      SecondFactor._(1, _omitEnumNames ? '' : 'SECOND_FACTOR_TOTP');
  static const SecondFactor SECOND_FACTOR_PASSKEY =
      SecondFactor._(2, _omitEnumNames ? '' : 'SECOND_FACTOR_PASSKEY');

  /// One of the codes the account was given when it enrolled; each works once.
  static const SecondFactor SECOND_FACTOR_RECOVERY_CODE =
      SecondFactor._(3, _omitEnumNames ? '' : 'SECOND_FACTOR_RECOVERY_CODE');

  static const $core.List<SecondFactor> values = <SecondFactor>[
    SECOND_FACTOR_UNSPECIFIED,
    SECOND_FACTOR_TOTP,
    SECOND_FACTOR_PASSKEY,
    SECOND_FACTOR_RECOVERY_CODE,
  ];

  static final $core.List<SecondFactor?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static SecondFactor? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SecondFactor._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
