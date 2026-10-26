// This is a generated file - do not edit.
//
// Generated from photolib/sync/v1/mutation.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

import 'sync.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// A hybrid logical clock reading: wall-clock milliseconds plus a counter that orders events within one millisecond.
class Hlc extends $pb.GeneratedMessage {
  factory Hlc({
    $fixnum.Int64? physicalMs,
    $core.int? counter,
    $core.String? deviceId,
  }) {
    final result = Hlc._();
    if (physicalMs != null) result.physicalMs = physicalMs;
    if (counter != null) result.counter = counter;
    if (deviceId != null) result.deviceId = deviceId;
    return result;
  }

  Hlc._();

  factory Hlc.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Hlc()..mergeFromBuffer(data, registry);
  factory Hlc.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Hlc()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Hlc',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: Hlc.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'physicalMs')
    ..aI(2, _omitFieldNames ? '' : 'counter', fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'deviceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hlc clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Hlc copyWith(void Function(Hlc) updates) =>
      super.copyWith((message) => updates(message as Hlc)) as Hlc;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Hlc() / Hlc.new instead')
  static Hlc create() => Hlc._();
  static $pb.GeneratedMessage $_createMessage() => Hlc._();
  @$core.override
  Hlc createEmptyInstance() => Hlc._();
  @$core.pragma('dart2js:noInline')
  static Hlc getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Hlc>(Hlc.$_createMessage);
  static Hlc? _defaultInstance;

  /// Milliseconds since the Unix epoch, UTC.
  @$pb.TagNumber(1)
  $fixnum.Int64 get physicalMs => $_getI64(0);
  @$pb.TagNumber(1)
  set physicalMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhysicalMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhysicalMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get counter => $_getIZ(1);
  @$pb.TagNumber(2)
  set counter($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCounter() => $_has(1);
  @$pb.TagNumber(2)
  void clearCounter() => $_clearField(2);

  /// Device that produced the reading (UUIDv7); breaks ties between equal readings.
  @$pb.TagNumber(3)
  $core.String get deviceId => $_getSZ(2);
  @$pb.TagNumber(3)
  set deviceId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeviceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceId() => $_clearField(3);
}

enum Mutation_Change { edit, member, version, notSet }

/// The envelope of one user action sent from a device's outbox.
class Mutation extends $pb.GeneratedMessage {
  factory Mutation({
    $core.String? mutationId,
    Hlc? hlc,
    $0.Timestamp? recordedAt,
    FieldEdit? edit,
    MemberEdit? member,
    VersionEdit? version,
  }) {
    final result = Mutation._();
    if (mutationId != null) result.mutationId = mutationId;
    if (hlc != null) result.hlc = hlc;
    if (recordedAt != null) result.recordedAt = recordedAt;
    if (edit != null) result.edit = edit;
    if (member != null) result.member = member;
    if (version != null) result.version = version;
    return result;
  }

  Mutation._();

  factory Mutation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Mutation()..mergeFromBuffer(data, registry);
  factory Mutation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Mutation()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Mutation_Change> _Mutation_ChangeByTag = {
    4: Mutation_Change.edit,
    5: Mutation_Change.member,
    6: Mutation_Change.version,
    0: Mutation_Change.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Mutation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: Mutation.$_createMessage)
    ..oo(0, [4, 5, 6])
    ..aOS(1, _omitFieldNames ? '' : 'mutationId')
    ..aOM<Hlc>(2, _omitFieldNames ? '' : 'hlc', subBuilder: Hlc.$_createMessage)
    ..aOM<$0.Timestamp>(3, _omitFieldNames ? '' : 'recordedAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<FieldEdit>(4, _omitFieldNames ? '' : 'edit',
        subBuilder: FieldEdit.$_createMessage)
    ..aOM<MemberEdit>(5, _omitFieldNames ? '' : 'member',
        subBuilder: MemberEdit.$_createMessage)
    ..aOM<VersionEdit>(6, _omitFieldNames ? '' : 'version',
        subBuilder: VersionEdit.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Mutation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Mutation copyWith(void Function(Mutation) updates) =>
      super.copyWith((message) => updates(message as Mutation)) as Mutation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Mutation() / Mutation.new instead')
  static Mutation create() => Mutation._();
  static $pb.GeneratedMessage $_createMessage() => Mutation._();
  @$core.override
  Mutation createEmptyInstance() => Mutation._();
  @$core.pragma('dart2js:noInline')
  static Mutation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Mutation>(Mutation.$_createMessage);
  static Mutation? _defaultInstance;

  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  Mutation_Change whichChange() => _Mutation_ChangeByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  void clearChange() => $_clearField($_whichOneof(0));

  /// Idempotency key (UUIDv7): the server ignores a mutation_id it has already applied.
  @$pb.TagNumber(1)
  $core.String get mutationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set mutationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMutationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMutationId() => $_clearField(1);

  @$pb.TagNumber(2)
  Hlc get hlc => $_getN(1);
  @$pb.TagNumber(2)
  set hlc(Hlc value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHlc() => $_has(1);
  @$pb.TagNumber(2)
  void clearHlc() => $_clearField(2);
  @$pb.TagNumber(2)
  Hlc ensureHlc() => $_ensure(1);

  /// When the device recorded the action, for audit trails; ordering always uses hlc.
  @$pb.TagNumber(3)
  $0.Timestamp get recordedAt => $_getN(2);
  @$pb.TagNumber(3)
  set recordedAt($0.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasRecordedAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearRecordedAt() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Timestamp ensureRecordedAt() => $_ensure(2);

  @$pb.TagNumber(4)
  FieldEdit get edit => $_getN(3);
  @$pb.TagNumber(4)
  set edit(FieldEdit value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasEdit() => $_has(3);
  @$pb.TagNumber(4)
  void clearEdit() => $_clearField(4);
  @$pb.TagNumber(4)
  FieldEdit ensureEdit() => $_ensure(3);

  @$pb.TagNumber(5)
  MemberEdit get member => $_getN(4);
  @$pb.TagNumber(5)
  set member(MemberEdit value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasMember() => $_has(4);
  @$pb.TagNumber(5)
  void clearMember() => $_clearField(5);
  @$pb.TagNumber(5)
  MemberEdit ensureMember() => $_ensure(4);

  @$pb.TagNumber(6)
  VersionEdit get version => $_getN(5);
  @$pb.TagNumber(6)
  set version(VersionEdit value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasVersion() => $_has(5);
  @$pb.TagNumber(6)
  void clearVersion() => $_clearField(6);
  @$pb.TagNumber(6)
  VersionEdit ensureVersion() => $_ensure(5);
}

/// Sets user fields of one row. Each field keeps the value of its latest edit by hlc, wherever and in whatever order
/// the edits arrive (per-field last-writer-wins, design 05 §5).
class FieldEdit extends $pb.GeneratedMessage {
  factory FieldEdit({
    $core.String? entity,
    $core.String? id,
    $core.Iterable<$core.MapEntry<$core.String, $1.Value>>? fields,
  }) {
    final result = FieldEdit._();
    if (entity != null) result.entity = entity;
    if (id != null) result.id = id;
    if (fields != null) result.fields.addEntries(fields);
    return result;
  }

  FieldEdit._();

  factory FieldEdit.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FieldEdit()..mergeFromBuffer(data, registry);
  factory FieldEdit.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FieldEdit()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FieldEdit',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: FieldEdit.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'entity')
    ..aOS(2, _omitFieldNames ? '' : 'id')
    ..m<$core.String, $1.Value>(3, _omitFieldNames ? '' : 'fields',
        entryClassName: 'FieldEdit.FieldsEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OM,
        valueCreator: $1.Value.$_createMessage,
        valueDefaultOrMaker: $1.Value.getDefault,
        packageName: const $pb.PackageName('photolib.sync.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FieldEdit clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FieldEdit copyWith(void Function(FieldEdit) updates) =>
      super.copyWith((message) => updates(message as FieldEdit)) as FieldEdit;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FieldEdit() / FieldEdit.new instead')
  static FieldEdit create() => FieldEdit._();
  static $pb.GeneratedMessage $_createMessage() => FieldEdit._();
  @$core.override
  FieldEdit createEmptyInstance() => FieldEdit._();
  @$core.pragma('dart2js:noInline')
  static FieldEdit getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FieldEdit>(FieldEdit.$_createMessage);
  static FieldEdit? _defaultInstance;

  /// The table, as sync names it: "assets" (title, description, rating, color_label, archived, trashed_at,
  /// current_version_id: the id of one of the asset's versions, which makes a revert one edit),
  /// "asset_user_state" (favorite, hidden_from_memories), "album_items" (sort_key) or "albums" (title, description).
  /// The first edit of an id no album has creates it for the caller under that id.
  @$pb.TagNumber(1)
  $core.String get entity => $_getSZ(0);
  @$pb.TagNumber(1)
  set entity($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEntity() => $_has(0);
  @$pb.TagNumber(1)
  void clearEntity() => $_clearField(1);

  /// The row's id; of asset_user_state, the asset's.
  @$pb.TagNumber(2)
  $core.String get id => $_getSZ(1);
  @$pb.TagNumber(2)
  set id($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasId() => $_has(1);
  @$pb.TagNumber(2)
  void clearId() => $_clearField(2);

  /// The new value of each field, typed as sync sends it; a value of no kind is NULL. A trashed_at of any time trashes
  /// the asset at the edit's hlc, NULL restores it.
  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $1.Value> get fields => $_getMap(2);
}

/// Adds an element to a set or removes it. The latest operation on an element by hlc decides, so an add and a remove
/// made offline on two devices end the same everywhere (OR-set semantics, design 05 §5).
class MemberEdit extends $pb.GeneratedMessage {
  factory MemberEdit({
    $core.String? entity,
    $core.String? setId,
    $core.String? elementId,
    $core.bool? present,
    $core.String? sortKey,
  }) {
    final result = MemberEdit._();
    if (entity != null) result.entity = entity;
    if (setId != null) result.setId = setId;
    if (elementId != null) result.elementId = elementId;
    if (present != null) result.present = present;
    if (sortKey != null) result.sortKey = sortKey;
    return result;
  }

  MemberEdit._();

  factory MemberEdit.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MemberEdit()..mergeFromBuffer(data, registry);
  factory MemberEdit.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MemberEdit()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MemberEdit',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: MemberEdit.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'entity')
    ..aOS(2, _omitFieldNames ? '' : 'setId')
    ..aOS(3, _omitFieldNames ? '' : 'elementId')
    ..aOB(4, _omitFieldNames ? '' : 'present')
    ..aOS(5, _omitFieldNames ? '' : 'sortKey')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MemberEdit clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MemberEdit copyWith(void Function(MemberEdit) updates) =>
      super.copyWith((message) => updates(message as MemberEdit)) as MemberEdit;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MemberEdit() / MemberEdit.new instead')
  static MemberEdit create() => MemberEdit._();
  static $pb.GeneratedMessage $_createMessage() => MemberEdit._();
  @$core.override
  MemberEdit createEmptyInstance() => MemberEdit._();
  @$core.pragma('dart2js:noInline')
  static MemberEdit getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MemberEdit>(MemberEdit.$_createMessage);
  static MemberEdit? _defaultInstance;

  /// The set's table, as sync names it: "album_items", the assets of an album. An asset's item in an album has the
  /// UUIDv8 of the first 16 bytes of SHA-256("photolib.album_item" ‖ album id ‖ asset id), ids as 16 bytes, so that
  /// every device names it alike.
  @$pb.TagNumber(1)
  $core.String get entity => $_getSZ(0);
  @$pb.TagNumber(1)
  set entity($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEntity() => $_has(0);
  @$pb.TagNumber(1)
  void clearEntity() => $_clearField(1);

  /// The set: the album.
  @$pb.TagNumber(2)
  $core.String get setId => $_getSZ(1);
  @$pb.TagNumber(2)
  set setId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSetId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSetId() => $_clearField(2);

  /// The element: the asset.
  @$pb.TagNumber(3)
  $core.String get elementId => $_getSZ(2);
  @$pb.TagNumber(3)
  set elementId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasElementId() => $_has(2);
  @$pb.TagNumber(3)
  void clearElementId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get present => $_getBF(3);
  @$pb.TagNumber(4)
  set present($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPresent() => $_has(3);
  @$pb.TagNumber(4)
  void clearPresent() => $_clearField(4);

  /// Where an added element goes in the set's custom order: a fractional index key of digits and ASCII letters,
  /// ordered bytewise, ties by the item's id.
  @$pb.TagNumber(5)
  $core.String get sortKey => $_getSZ(4);
  @$pb.TagNumber(5)
  set sortKey($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSortKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearSortKey() => $_clearField(5);
}

/// Adds an immutable version to an asset's history: the recipe of one edit of the asset's picture (roadmap M8-01,
/// ADR-0391). It is an insert, never merged: a version id the server holds already is the same version (its recipe must
/// be the same) and nothing happens. Making the version the asset's current one is a separate `FieldEdit` of
/// `assets.current_version_id`, sent after it, so that a revert to any version is the same edit.
class VersionEdit extends $pb.GeneratedMessage {
  factory VersionEdit({
    $core.String? assetId,
    $core.String? versionId,
    $core.String? parentId,
    $core.String? label,
    $core.List<$core.int>? recipe,
  }) {
    final result = VersionEdit._();
    if (assetId != null) result.assetId = assetId;
    if (versionId != null) result.versionId = versionId;
    if (parentId != null) result.parentId = parentId;
    if (label != null) result.label = label;
    if (recipe != null) result.recipe = recipe;
    return result;
  }

  VersionEdit._();

  factory VersionEdit.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VersionEdit()..mergeFromBuffer(data, registry);
  factory VersionEdit.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VersionEdit()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VersionEdit',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: VersionEdit.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'assetId')
    ..aOS(2, _omitFieldNames ? '' : 'versionId')
    ..aOS(3, _omitFieldNames ? '' : 'parentId')
    ..aOS(4, _omitFieldNames ? '' : 'label')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'recipe', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VersionEdit clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VersionEdit copyWith(void Function(VersionEdit) updates) =>
      super.copyWith((message) => updates(message as VersionEdit))
          as VersionEdit;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use VersionEdit() / VersionEdit.new instead')
  static VersionEdit create() => VersionEdit._();
  static $pb.GeneratedMessage $_createMessage() => VersionEdit._();
  @$core.override
  VersionEdit createEmptyInstance() => VersionEdit._();
  @$core.pragma('dart2js:noInline')
  static VersionEdit getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VersionEdit>(
          VersionEdit.$_createMessage);
  static VersionEdit? _defaultInstance;

  /// The asset edited (UUIDv7); a standard library's, since a private library keeps its recipes on devices.
  @$pb.TagNumber(1)
  $core.String get assetId => $_getSZ(0);
  @$pb.TagNumber(1)
  set assetId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAssetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAssetId() => $_clearField(1);

  /// The new version's id (UUIDv7), made by the device so that it can name the version offline.
  @$pb.TagNumber(2)
  $core.String get versionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set versionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVersionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearVersionId() => $_clearField(2);

  /// The version this edit continues, one of the asset's; empty for none.
  @$pb.TagNumber(3)
  $core.String get parentId => $_getSZ(2);
  @$pb.TagNumber(3)
  set parentId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasParentId() => $_has(2);
  @$pb.TagNumber(3)
  void clearParentId() => $_clearField(3);

  /// What the user called it; at most 200 characters.
  @$pb.TagNumber(4)
  $core.String get label => $_getSZ(3);
  @$pb.TagNumber(4)
  set label($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLabel() => $_has(3);
  @$pb.TagNumber(4)
  void clearLabel() => $_clearField(4);

  /// The `photolib.model.v1.EditRecipe`, encoded; the server checks it with the kernel and keeps its canonical form.
  @$pb.TagNumber(5)
  $core.List<$core.int> get recipe => $_getN(4);
  @$pb.TagNumber(5)
  set recipe($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRecipe() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecipe() => $_clearField(5);
}

/// Mutations drained from a device's outbox in causal order.
class MutationBatch extends $pb.GeneratedMessage {
  factory MutationBatch({
    $core.Iterable<Mutation>? mutations,
  }) {
    final result = MutationBatch._();
    if (mutations != null) result.mutations.addAll(mutations);
    return result;
  }

  MutationBatch._();

  factory MutationBatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MutationBatch()..mergeFromBuffer(data, registry);
  factory MutationBatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MutationBatch()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MutationBatch',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: MutationBatch.$_createMessage)
    ..pPM<Mutation>(1, _omitFieldNames ? '' : 'mutations',
        subBuilder: Mutation.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MutationBatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MutationBatch copyWith(void Function(MutationBatch) updates) =>
      super.copyWith((message) => updates(message as MutationBatch))
          as MutationBatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MutationBatch() / MutationBatch.new instead')
  static MutationBatch create() => MutationBatch._();
  static $pb.GeneratedMessage $_createMessage() => MutationBatch._();
  @$core.override
  MutationBatch createEmptyInstance() => MutationBatch._();
  @$core.pragma('dart2js:noInline')
  static MutationBatch getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MutationBatch>(
          MutationBatch.$_createMessage);
  static MutationBatch? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Mutation> get mutations => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
