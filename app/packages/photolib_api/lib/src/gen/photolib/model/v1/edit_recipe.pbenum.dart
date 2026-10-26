// This is a generated file - do not edit.
//
// Generated from photolib/model/v1/edit_recipe.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// What a stored output is.
class StoredOutputKind extends $pb.ProtobufEnum {
  static const StoredOutputKind STORED_OUTPUT_KIND_UNSPECIFIED =
      StoredOutputKind._(
          0, _omitEnumNames ? '' : 'STORED_OUTPUT_KIND_UNSPECIFIED');

  /// 8-bit weights, one byte per pixel, 0 (untouched) to 255 (fully adjusted).
  static const StoredOutputKind STORED_OUTPUT_KIND_MASK =
      StoredOutputKind._(1, _omitEnumNames ? '' : 'STORED_OUTPUT_KIND_MASK');

  /// 8-bit RGBA, sRGB, straight alpha, four bytes per pixel.
  static const StoredOutputKind STORED_OUTPUT_KIND_PATCH =
      StoredOutputKind._(2, _omitEnumNames ? '' : 'STORED_OUTPUT_KIND_PATCH');

  static const $core.List<StoredOutputKind> values = <StoredOutputKind>[
    STORED_OUTPUT_KIND_UNSPECIFIED,
    STORED_OUTPUT_KIND_MASK,
    STORED_OUTPUT_KIND_PATCH,
  ];

  static final $core.List<StoredOutputKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static StoredOutputKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const StoredOutputKind._(super.value, super.name);
}

/// IPTC's DigitalSourceType vocabulary, the values an export can state (cv.iptc.org/newscodes/digitalsourcetype).
class DigitalSourceType extends $pb.ProtobufEnum {
  static const DigitalSourceType DIGITAL_SOURCE_TYPE_UNSPECIFIED =
      DigitalSourceType._(
          0, _omitEnumNames ? '' : 'DIGITAL_SOURCE_TYPE_UNSPECIFIED');

  /// Edited by a person with tools that apply no model: `humanEdits`.
  static const DigitalSourceType DIGITAL_SOURCE_TYPE_HUMAN_EDITS =
      DigitalSourceType._(
          1, _omitEnumNames ? '' : 'DIGITAL_SOURCE_TYPE_HUMAN_EDITS');

  /// A model enhanced it, e.g. a mask made by a segmentation model: `algorithmicallyEnhanced`.
  static const DigitalSourceType DIGITAL_SOURCE_TYPE_ALGORITHMICALLY_ENHANCED =
      DigitalSourceType._(2,
          _omitEnumNames ? '' : 'DIGITAL_SOURCE_TYPE_ALGORITHMICALLY_ENHANCED');

  /// Content a generative model made was composited into it, e.g. an inpainting patch:
  /// `compositeWithTrainedAlgorithmicMedia`.
  static const DigitalSourceType
      DIGITAL_SOURCE_TYPE_COMPOSITE_WITH_TRAINED_ALGORITHMIC_MEDIA =
      DigitalSourceType._(
          3,
          _omitEnumNames
              ? ''
              : 'DIGITAL_SOURCE_TYPE_COMPOSITE_WITH_TRAINED_ALGORITHMIC_MEDIA');

  static const $core.List<DigitalSourceType> values = <DigitalSourceType>[
    DIGITAL_SOURCE_TYPE_UNSPECIFIED,
    DIGITAL_SOURCE_TYPE_HUMAN_EDITS,
    DIGITAL_SOURCE_TYPE_ALGORITHMICALLY_ENHANCED,
    DIGITAL_SOURCE_TYPE_COMPOSITE_WITH_TRAINED_ALGORITHMIC_MEDIA,
  ];

  static final $core.List<DigitalSourceType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static DigitalSourceType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DigitalSourceType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
