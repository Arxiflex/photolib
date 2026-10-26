// This is a generated file - do not edit.
//
// Generated from photolib/sync/v1/sync.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'sync.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'sync.pbenum.dart';

/// Where a device stands in one stream (design 05 §3).
class StreamCursor extends $pb.GeneratedMessage {
  factory StreamCursor({
    $core.String? stream,
    $core.List<$core.int>? cursor,
  }) {
    final result = StreamCursor._();
    if (stream != null) result.stream = stream;
    if (cursor != null) result.cursor = cursor;
    return result;
  }

  StreamCursor._();

  factory StreamCursor.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StreamCursor()..mergeFromBuffer(data, registry);
  factory StreamCursor.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StreamCursor()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamCursor',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: StreamCursor.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'stream')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'cursor', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamCursor clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamCursor copyWith(void Function(StreamCursor) updates) =>
      super.copyWith((message) => updates(message as StreamCursor))
          as StreamCursor;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StreamCursor() / StreamCursor.new instead')
  static StreamCursor create() => StreamCursor._();
  static $pb.GeneratedMessage $_createMessage() => StreamCursor._();
  @$core.override
  StreamCursor createEmptyInstance() => StreamCursor._();
  @$core.pragma('dart2js:noInline')
  static StreamCursor getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StreamCursor>(
          StreamCursor.$_createMessage);
  static StreamCursor? _defaultInstance;

  /// The stream, e.g. "account", "libraries" or "assets/<library id>".
  @$pb.TagNumber(1)
  $core.String get stream => $_getSZ(0);
  @$pb.TagNumber(1)
  set stream($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStream() => $_has(0);
  @$pb.TagNumber(1)
  void clearStream() => $_clearField(1);

  /// The cursor of the stream's last applied batch; empty starts it from scratch, with a snapshot.
  @$pb.TagNumber(2)
  $core.List<$core.int> get cursor => $_getN(1);
  @$pb.TagNumber(2)
  set cursor($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCursor() => $_has(1);
  @$pb.TagNumber(2)
  void clearCursor() => $_clearField(2);
}

enum Value_Kind { text, integer, real, boolean, blob, notSet }

/// One column of a row: uuids, text, dates, JSON and arrays (as JSON) are text, times are integer milliseconds since
/// the Unix epoch, UTC; no kind is NULL.
class Value extends $pb.GeneratedMessage {
  factory Value({
    $core.String? text,
    $fixnum.Int64? integer,
    $core.double? real,
    $core.bool? boolean,
    $core.List<$core.int>? blob,
  }) {
    final result = Value._();
    if (text != null) result.text = text;
    if (integer != null) result.integer = integer;
    if (real != null) result.real = real;
    if (boolean != null) result.boolean = boolean;
    if (blob != null) result.blob = blob;
    return result;
  }

  Value._();

  factory Value.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Value()..mergeFromBuffer(data, registry);
  factory Value.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Value()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Value_Kind> _Value_KindByTag = {
    1: Value_Kind.text,
    2: Value_Kind.integer,
    3: Value_Kind.real,
    4: Value_Kind.boolean,
    5: Value_Kind.blob,
    0: Value_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Value',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: Value.$_createMessage)
    ..oo(0, [1, 2, 3, 4, 5])
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'integer', $pb.PbFieldType.OS6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(3, _omitFieldNames ? '' : 'real')
    ..aOB(4, _omitFieldNames ? '' : 'boolean')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'blob', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Value clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Value copyWith(void Function(Value) updates) =>
      super.copyWith((message) => updates(message as Value)) as Value;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Value() / Value.new instead')
  static Value create() => Value._();
  static $pb.GeneratedMessage $_createMessage() => Value._();
  @$core.override
  Value createEmptyInstance() => Value._();
  @$core.pragma('dart2js:noInline')
  static Value getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Value>(Value.$_createMessage);
  static Value? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  Value_Kind whichKind() => _Value_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  void clearKind() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get integer => $_getI64(1);
  @$pb.TagNumber(2)
  set integer($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInteger() => $_has(1);
  @$pb.TagNumber(2)
  void clearInteger() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get real => $_getN(2);
  @$pb.TagNumber(3)
  set real($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReal() => $_has(2);
  @$pb.TagNumber(3)
  void clearReal() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get boolean => $_getBF(3);
  @$pb.TagNumber(4)
  set boolean($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBoolean() => $_has(3);
  @$pb.TagNumber(4)
  void clearBoolean() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get blob => $_getN(4);
  @$pb.TagNumber(5)
  set blob($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBlob() => $_has(4);
  @$pb.TagNumber(5)
  void clearBlob() => $_clearField(5);
}

/// The values of one row, in the order of its group's columns.
class Row extends $pb.GeneratedMessage {
  factory Row({
    $core.Iterable<Value>? values,
  }) {
    final result = Row._();
    if (values != null) result.values.addAll(values);
    return result;
  }

  Row._();

  factory Row.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Row()..mergeFromBuffer(data, registry);
  factory Row.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Row()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Row',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: Row.$_createMessage)
    ..pPM<Value>(1, _omitFieldNames ? '' : 'values',
        subBuilder: Value.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Row clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Row copyWith(void Function(Row) updates) =>
      super.copyWith((message) => updates(message as Row)) as Row;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Row() / Row.new instead')
  static Row create() => Row._();
  static $pb.GeneratedMessage $_createMessage() => Row._();
  @$core.override
  Row createEmptyInstance() => Row._();
  @$core.pragma('dart2js:noInline')
  static Row getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Row>(Row.$_createMessage);
  static Row? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Value> get values => $_getList(0);
}

/// Rows of one table: upserts, or deletions that carry only the key columns.
class Rows extends $pb.GeneratedMessage {
  factory Rows({
    $core.String? entity,
    $core.Iterable<$core.String>? columns,
    $core.Iterable<Row>? rows,
    $core.bool? deleted,
  }) {
    final result = Rows._();
    if (entity != null) result.entity = entity;
    if (columns != null) result.columns.addAll(columns);
    if (rows != null) result.rows.addAll(rows);
    if (deleted != null) result.deleted = deleted;
    return result;
  }

  Rows._();

  factory Rows.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Rows()..mergeFromBuffer(data, registry);
  factory Rows.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Rows()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Rows',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: Rows.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'entity')
    ..pPS(2, _omitFieldNames ? '' : 'columns')
    ..pPM<Row>(3, _omitFieldNames ? '' : 'rows',
        subBuilder: Row.$_createMessage)
    ..aOB(4, _omitFieldNames ? '' : 'deleted')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Rows clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Rows copyWith(void Function(Rows) updates) =>
      super.copyWith((message) => updates(message as Rows)) as Rows;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Rows() / Rows.new instead')
  static Rows create() => Rows._();
  static $pb.GeneratedMessage $_createMessage() => Rows._();
  @$core.override
  Rows createEmptyInstance() => Rows._();
  @$core.pragma('dart2js:noInline')
  static Rows getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Rows>(Rows.$_createMessage);
  static Rows? _defaultInstance;

  /// The table, e.g. "assets".
  @$pb.TagNumber(1)
  $core.String get entity => $_getSZ(0);
  @$pb.TagNumber(1)
  set entity($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEntity() => $_has(0);
  @$pb.TagNumber(1)
  void clearEntity() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get columns => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<Row> get rows => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get deleted => $_getBF(3);
  @$pb.TagNumber(4)
  set deleted($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDeleted() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeleted() => $_clearField(4);
}

/// Changes of one stream that a device applies in one transaction, then stores `cursor`.
class SyncBatch extends $pb.GeneratedMessage {
  factory SyncBatch({
    $core.String? stream,
    StreamStatus? status,
    $core.Iterable<Rows>? changes,
    $core.List<$core.int>? cursor,
    $core.bool? caughtUp,
  }) {
    final result = SyncBatch._();
    if (stream != null) result.stream = stream;
    if (status != null) result.status = status;
    if (changes != null) result.changes.addAll(changes);
    if (cursor != null) result.cursor = cursor;
    if (caughtUp != null) result.caughtUp = caughtUp;
    return result;
  }

  SyncBatch._();

  factory SyncBatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncBatch()..mergeFromBuffer(data, registry);
  factory SyncBatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncBatch()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SyncBatch',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.sync.v1'),
      createEmptyInstance: SyncBatch.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'stream')
    ..aE<StreamStatus>(2, _omitFieldNames ? '' : 'status',
        enumValues: StreamStatus.values)
    ..pPM<Rows>(3, _omitFieldNames ? '' : 'changes',
        subBuilder: Rows.$_createMessage)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'cursor', $pb.PbFieldType.OY)
    ..aOB(5, _omitFieldNames ? '' : 'caughtUp')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncBatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncBatch copyWith(void Function(SyncBatch) updates) =>
      super.copyWith((message) => updates(message as SyncBatch)) as SyncBatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SyncBatch() / SyncBatch.new instead')
  static SyncBatch create() => SyncBatch._();
  static $pb.GeneratedMessage $_createMessage() => SyncBatch._();
  @$core.override
  SyncBatch createEmptyInstance() => SyncBatch._();
  @$core.pragma('dart2js:noInline')
  static SyncBatch getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SyncBatch>(SyncBatch.$_createMessage);
  static SyncBatch? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stream => $_getSZ(0);
  @$pb.TagNumber(1)
  set stream($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStream() => $_has(0);
  @$pb.TagNumber(1)
  void clearStream() => $_clearField(1);

  @$pb.TagNumber(2)
  StreamStatus get status => $_getN(1);
  @$pb.TagNumber(2)
  set status(StreamStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<Rows> get changes => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get cursor => $_getN(3);
  @$pb.TagNumber(4)
  set cursor($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCursor() => $_has(3);
  @$pb.TagNumber(4)
  void clearCursor() => $_clearField(4);

  /// The stream has caught up: this is its last batch of the call.
  @$pb.TagNumber(5)
  $core.bool get caughtUp => $_getBF(4);
  @$pb.TagNumber(5)
  set caughtUp($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCaughtUp() => $_has(4);
  @$pb.TagNumber(5)
  void clearCaughtUp() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
