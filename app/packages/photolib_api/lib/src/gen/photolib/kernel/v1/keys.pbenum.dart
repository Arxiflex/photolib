// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/keys.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// The policies an Argon2id parameter set is held to before it is used.
class KdfPolicy extends $pb.ProtobufEnum {
  static const KdfPolicy KDF_POLICY_UNSPECIFIED =
      KdfPolicy._(0, _omitEnumNames ? '' : 'KDF_POLICY_UNSPECIFIED');

  /// An account's parameters, as a server sends them.
  static const KdfPolicy KDF_POLICY_ACCOUNT =
      KdfPolicy._(1, _omitEnumNames ? '' : 'KDF_POLICY_ACCOUNT');

  /// A device's passcode parameters.
  static const KdfPolicy KDF_POLICY_DEVICE =
      KdfPolicy._(2, _omitEnumNames ? '' : 'KDF_POLICY_DEVICE');

  static const $core.List<KdfPolicy> values = <KdfPolicy>[
    KDF_POLICY_UNSPECIFIED,
    KDF_POLICY_ACCOUNT,
    KDF_POLICY_DEVICE,
  ];

  static final $core.List<KdfPolicy?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static KdfPolicy? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const KdfPolicy._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
