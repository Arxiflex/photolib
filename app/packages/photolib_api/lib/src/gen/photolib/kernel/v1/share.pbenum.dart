// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/share.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// The algorithm of a key pair whose 32-byte seed is in the keyring.
class KeyPair extends $pb.ProtobufEnum {
  static const KeyPair KEY_PAIR_UNSPECIFIED =
      KeyPair._(0, _omitEnumNames ? '' : 'KEY_PAIR_UNSPECIFIED');

  /// An Ed25519 signing key.
  static const KeyPair KEY_PAIR_ED25519 =
      KeyPair._(1, _omitEnumNames ? '' : 'KEY_PAIR_ED25519');

  /// An X-Wing decryption key: an identity, device or drop key.
  static const KeyPair KEY_PAIR_X_WING =
      KeyPair._(2, _omitEnumNames ? '' : 'KEY_PAIR_X_WING');

  static const $core.List<KeyPair> values = <KeyPair>[
    KEY_PAIR_UNSPECIFIED,
    KEY_PAIR_ED25519,
    KEY_PAIR_X_WING,
  ];

  static final $core.List<KeyPair?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static KeyPair? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const KeyPair._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
