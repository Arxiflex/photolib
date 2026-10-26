// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/heif.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Whether a file's coded images were found, and if not why.
class HeifStatus extends $pb.ProtobufEnum {
  static const HeifStatus HEIF_STATUS_UNSPECIFIED =
      HeifStatus._(0, _omitEnumNames ? '' : 'HEIF_STATUS_UNSPECIFIED');
  static const HeifStatus HEIF_STATUS_OK =
      HeifStatus._(1, _omitEnumNames ? '' : 'HEIF_STATUS_OK');

  /// The bytes are no HEIF file, or the meta box is not (yet) all there: see missing.
  static const HeifStatus HEIF_STATUS_NOT_HEIF =
      HeifStatus._(2, _omitEnumNames ? '' : 'HEIF_STATUS_NOT_HEIF');

  /// The primary item is not coded as HEVC, AV1 or AVC (nor a grid or tmap of such).
  static const HeifStatus HEIF_STATUS_UNSUPPORTED_CODEC =
      HeifStatus._(3, _omitEnumNames ? '' : 'HEIF_STATUS_UNSUPPORTED_CODEC');

  /// An image item has no hvcC, av1C or avcC, so a decoder cannot be configured.
  static const HeifStatus HEIF_STATUS_NO_CONFIG =
      HeifStatus._(4, _omitEnumNames ? '' : 'HEIF_STATUS_NO_CONFIG');

  static const $core.List<HeifStatus> values = <HeifStatus>[
    HEIF_STATUS_UNSPECIFIED,
    HEIF_STATUS_OK,
    HEIF_STATUS_NOT_HEIF,
    HEIF_STATUS_UNSUPPORTED_CODEC,
    HEIF_STATUS_NO_CONFIG,
  ];

  static final $core.List<HeifStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static HeifStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const HeifStatus._(super.value, super.name);
}

/// The codec of a coded image, by its HEIF item type.
class HeifCodec extends $pb.ProtobufEnum {
  static const HeifCodec HEIF_CODEC_UNSPECIFIED =
      HeifCodec._(0, _omitEnumNames ? '' : 'HEIF_CODEC_UNSPECIFIED');
  static const HeifCodec HEIF_CODEC_HEVC =
      HeifCodec._(1, _omitEnumNames ? '' : 'HEIF_CODEC_HEVC');
  static const HeifCodec HEIF_CODEC_AV1 =
      HeifCodec._(2, _omitEnumNames ? '' : 'HEIF_CODEC_AV1');
  static const HeifCodec HEIF_CODEC_AVC =
      HeifCodec._(3, _omitEnumNames ? '' : 'HEIF_CODEC_AVC');

  static const $core.List<HeifCodec> values = <HeifCodec>[
    HEIF_CODEC_UNSPECIFIED,
    HEIF_CODEC_HEVC,
    HEIF_CODEC_AV1,
    HEIF_CODEC_AVC,
  ];

  static final $core.List<HeifCodec?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static HeifCodec? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const HeifCodec._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
