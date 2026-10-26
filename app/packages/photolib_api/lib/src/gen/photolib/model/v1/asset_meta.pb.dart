// This is a generated file - do not edit.
//
// Generated from photolib/model/v1/asset_meta.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'capture_time.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The core metadata of an asset. Private libraries store it as an encrypted blob, so it carries its own version.
class AssetMetaCore extends $pb.GeneratedMessage {
  factory AssetMetaCore({
    $core.int? schemaVersion,
    $core.String? assetId,
    $0.CaptureTime? captureTime,
  }) {
    final result = AssetMetaCore._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (assetId != null) result.assetId = assetId;
    if (captureTime != null) result.captureTime = captureTime;
    return result;
  }

  AssetMetaCore._();

  factory AssetMetaCore.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AssetMetaCore()..mergeFromBuffer(data, registry);
  factory AssetMetaCore.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AssetMetaCore()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AssetMetaCore',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.model.v1'),
      createEmptyInstance: AssetMetaCore.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'assetId')
    ..aOM<$0.CaptureTime>(3, _omitFieldNames ? '' : 'captureTime',
        subBuilder: $0.CaptureTime.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AssetMetaCore clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AssetMetaCore copyWith(void Function(AssetMetaCore) updates) =>
      super.copyWith((message) => updates(message as AssetMetaCore))
          as AssetMetaCore;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AssetMetaCore() / AssetMetaCore.new instead')
  static AssetMetaCore create() => AssetMetaCore._();
  static $pb.GeneratedMessage $_createMessage() => AssetMetaCore._();
  @$core.override
  AssetMetaCore createEmptyInstance() => AssetMetaCore._();
  @$core.pragma('dart2js:noInline')
  static AssetMetaCore getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AssetMetaCore>(
          AssetMetaCore.$_createMessage);
  static AssetMetaCore? _defaultInstance;

  /// Version of this message's meaning, bumped with a migration whenever a field's semantics change.
  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  /// Identifier of the asset (UUIDv7) the metadata belongs to.
  @$pb.TagNumber(2)
  $core.String get assetId => $_getSZ(1);
  @$pb.TagNumber(2)
  set assetId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAssetId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAssetId() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.CaptureTime get captureTime => $_getN(2);
  @$pb.TagNumber(3)
  set captureTime($0.CaptureTime value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCaptureTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearCaptureTime() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.CaptureTime ensureCaptureTime() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
