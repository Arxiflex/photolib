// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/keys.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// A way into the AMK.
class UnlockKind extends $pb.ProtobufEnum {
  static const UnlockKind UNLOCK_KIND_UNSPECIFIED =
      UnlockKind._(0, _omitEnumNames ? '' : 'UNLOCK_KIND_UNSPECIFIED');

  /// The account's password, a vault passphrase for one that signs in with OpenID Connect: KEK_pw.
  static const UnlockKind UNLOCK_KIND_PASSWORD =
      UnlockKind._(1, _omitEnumNames ? '' : 'UNLOCK_KIND_PASSWORD');

  /// The recovery kit's phrase: KEK_rec.
  static const UnlockKind UNLOCK_KIND_RECOVERY =
      UnlockKind._(2, _omitEnumNames ? '' : 'UNLOCK_KIND_RECOVERY');

  static const $core.List<UnlockKind> values = <UnlockKind>[
    UNLOCK_KIND_UNSPECIFIED,
    UNLOCK_KIND_PASSWORD,
    UNLOCK_KIND_RECOVERY,
  ];

  static final $core.List<UnlockKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static UnlockKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const UnlockKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
