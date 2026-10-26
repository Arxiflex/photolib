// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/recipe.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// How one step differs.
class RecipeChangeKind extends $pb.ProtobufEnum {
  static const RecipeChangeKind RECIPE_CHANGE_KIND_UNSPECIFIED =
      RecipeChangeKind._(
          0, _omitEnumNames ? '' : 'RECIPE_CHANGE_KIND_UNSPECIFIED');

  /// Only in `after`.
  static const RecipeChangeKind RECIPE_CHANGE_KIND_ADDED =
      RecipeChangeKind._(1, _omitEnumNames ? '' : 'RECIPE_CHANGE_KIND_ADDED');

  /// Only in `before`.
  static const RecipeChangeKind RECIPE_CHANGE_KIND_REMOVED =
      RecipeChangeKind._(2, _omitEnumNames ? '' : 'RECIPE_CHANGE_KIND_REMOVED');

  /// In both with other parameters, or switched on or off.
  static const RecipeChangeKind RECIPE_CHANGE_KIND_CHANGED =
      RecipeChangeKind._(3, _omitEnumNames ? '' : 'RECIPE_CHANGE_KIND_CHANGED');

  /// In both, unchanged, but at another place among the steps of its kind.
  static const RecipeChangeKind RECIPE_CHANGE_KIND_MOVED =
      RecipeChangeKind._(4, _omitEnumNames ? '' : 'RECIPE_CHANGE_KIND_MOVED');

  static const $core.List<RecipeChangeKind> values = <RecipeChangeKind>[
    RECIPE_CHANGE_KIND_UNSPECIFIED,
    RECIPE_CHANGE_KIND_ADDED,
    RECIPE_CHANGE_KIND_REMOVED,
    RECIPE_CHANGE_KIND_CHANGED,
    RECIPE_CHANGE_KIND_MOVED,
  ];

  static final $core.List<RecipeChangeKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static RecipeChangeKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RecipeChangeKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
