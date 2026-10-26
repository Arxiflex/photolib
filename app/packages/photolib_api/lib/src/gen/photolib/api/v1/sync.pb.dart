// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/sync.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import '../../sync/v1/mutation.pb.dart' as $2;
import '../../sync/v1/sync.pb.dart' as $1;
import 'admin.pb.dart' as $0;
import 'error.pb.dart' as $3;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Empties the trash.
class EmptyTrashRequest extends $pb.GeneratedMessage {
  factory EmptyTrashRequest({
    $core.String? confirmToken,
  }) {
    final result = EmptyTrashRequest._();
    if (confirmToken != null) result.confirmToken = confirmToken;
    return result;
  }

  EmptyTrashRequest._();

  factory EmptyTrashRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EmptyTrashRequest()..mergeFromBuffer(data, registry);
  factory EmptyTrashRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EmptyTrashRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmptyTrashRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: EmptyTrashRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'confirmToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmptyTrashRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmptyTrashRequest copyWith(void Function(EmptyTrashRequest) updates) =>
      super.copyWith((message) => updates(message as EmptyTrashRequest))
          as EmptyTrashRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EmptyTrashRequest() / EmptyTrashRequest.new instead')
  static EmptyTrashRequest create() => EmptyTrashRequest._();
  static $pb.GeneratedMessage $_createMessage() => EmptyTrashRequest._();
  @$core.override
  EmptyTrashRequest createEmptyInstance() => EmptyTrashRequest._();
  @$core.pragma('dart2js:noInline')
  static EmptyTrashRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EmptyTrashRequest>(
          EmptyTrashRequest.$_createMessage);
  static EmptyTrashRequest? _defaultInstance;

  /// The token of the confirmation a first call answered; empty on the first.
  @$pb.TagNumber(1)
  $core.String get confirmToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set confirmToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConfirmToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfirmToken() => $_clearField(1);
}

/// Whether the trash is being emptied.
class EmptyTrashResponse extends $pb.GeneratedMessage {
  factory EmptyTrashResponse({
    $0.Confirmation? held,
    $fixnum.Int64? queued,
  }) {
    final result = EmptyTrashResponse._();
    if (held != null) result.held = held;
    if (queued != null) result.queued = queued;
    return result;
  }

  EmptyTrashResponse._();

  factory EmptyTrashResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EmptyTrashResponse()..mergeFromBuffer(data, registry);
  factory EmptyTrashResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EmptyTrashResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmptyTrashResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: EmptyTrashResponse.$_createMessage)
    ..aOM<$0.Confirmation>(1, _omitFieldNames ? '' : 'held',
        subBuilder: $0.Confirmation.$_createMessage)
    ..aInt64(2, _omitFieldNames ? '' : 'queued')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmptyTrashResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmptyTrashResponse copyWith(void Function(EmptyTrashResponse) updates) =>
      super.copyWith((message) => updates(message as EmptyTrashResponse))
          as EmptyTrashResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EmptyTrashResponse() / EmptyTrashResponse.new instead')
  static EmptyTrashResponse create() => EmptyTrashResponse._();
  static $pb.GeneratedMessage $_createMessage() => EmptyTrashResponse._();
  @$core.override
  EmptyTrashResponse createEmptyInstance() => EmptyTrashResponse._();
  @$core.pragma('dart2js:noInline')
  static EmptyTrashResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmptyTrashResponse>(
          EmptyTrashResponse.$_createMessage);
  static EmptyTrashResponse? _defaultInstance;

  /// The count to show the user and the token that confirms it, when emptying waits for that; nothing was deleted.
  @$pb.TagNumber(1)
  $0.Confirmation get held => $_getN(0);
  @$pb.TagNumber(1)
  set held($0.Confirmation value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasHeld() => $_has(0);
  @$pb.TagNumber(1)
  void clearHeld() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.Confirmation ensureHeld() => $_ensure(0);

  /// The assets that were in the trash when the job was queued, which deletes them and their files in the background;
  /// the devices learn of each deletion through sync. Zero when held or when the trash was empty.
  @$pb.TagNumber(2)
  $fixnum.Int64 get queued => $_getI64(1);
  @$pb.TagNumber(2)
  set queued($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasQueued() => $_has(1);
  @$pb.TagNumber(2)
  void clearQueued() => $_clearField(2);
}

/// The streams to sync, each with its cursor.
class SyncRequest extends $pb.GeneratedMessage {
  factory SyncRequest({
    $core.Iterable<$1.StreamCursor>? streams,
  }) {
    final result = SyncRequest._();
    if (streams != null) result.streams.addAll(streams);
    return result;
  }

  SyncRequest._();

  factory SyncRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncRequest()..mergeFromBuffer(data, registry);
  factory SyncRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SyncRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: SyncRequest.$_createMessage)
    ..pPM<$1.StreamCursor>(1, _omitFieldNames ? '' : 'streams',
        subBuilder: $1.StreamCursor.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncRequest copyWith(void Function(SyncRequest) updates) =>
      super.copyWith((message) => updates(message as SyncRequest))
          as SyncRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SyncRequest() / SyncRequest.new instead')
  static SyncRequest create() => SyncRequest._();
  static $pb.GeneratedMessage $_createMessage() => SyncRequest._();
  @$core.override
  SyncRequest createEmptyInstance() => SyncRequest._();
  @$core.pragma('dart2js:noInline')
  static SyncRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncRequest>(
          SyncRequest.$_createMessage);
  static SyncRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$1.StreamCursor> get streams => $_getList(0);
}

/// One batch of one stream.
class SyncResponse extends $pb.GeneratedMessage {
  factory SyncResponse({
    $1.SyncBatch? batch,
  }) {
    final result = SyncResponse._();
    if (batch != null) result.batch = batch;
    return result;
  }

  SyncResponse._();

  factory SyncResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncResponse()..mergeFromBuffer(data, registry);
  factory SyncResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SyncResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: SyncResponse.$_createMessage)
    ..aOM<$1.SyncBatch>(1, _omitFieldNames ? '' : 'batch',
        subBuilder: $1.SyncBatch.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncResponse copyWith(void Function(SyncResponse) updates) =>
      super.copyWith((message) => updates(message as SyncResponse))
          as SyncResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SyncResponse() / SyncResponse.new instead')
  static SyncResponse create() => SyncResponse._();
  static $pb.GeneratedMessage $_createMessage() => SyncResponse._();
  @$core.override
  SyncResponse createEmptyInstance() => SyncResponse._();
  @$core.pragma('dart2js:noInline')
  static SyncResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncResponse>(
          SyncResponse.$_createMessage);
  static SyncResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $1.SyncBatch get batch => $_getN(0);
  @$pb.TagNumber(1)
  set batch($1.SyncBatch value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBatch() => $_has(0);
  @$pb.TagNumber(1)
  void clearBatch() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.SyncBatch ensureBatch() => $_ensure(0);
}

/// Asks for the timeline summary of the caller's standard libraries.
class GetTimelineSummaryRequest extends $pb.GeneratedMessage {
  factory GetTimelineSummaryRequest() => GetTimelineSummaryRequest._();

  GetTimelineSummaryRequest._();

  factory GetTimelineSummaryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTimelineSummaryRequest()..mergeFromBuffer(data, registry);
  factory GetTimelineSummaryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTimelineSummaryRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTimelineSummaryRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetTimelineSummaryRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTimelineSummaryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTimelineSummaryRequest copyWith(
          void Function(GetTimelineSummaryRequest) updates) =>
      super.copyWith((message) => updates(message as GetTimelineSummaryRequest))
          as GetTimelineSummaryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetTimelineSummaryRequest() / GetTimelineSummaryRequest.new instead')
  static GetTimelineSummaryRequest create() => GetTimelineSummaryRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetTimelineSummaryRequest._();
  @$core.override
  GetTimelineSummaryRequest createEmptyInstance() =>
      GetTimelineSummaryRequest._();
  @$core.pragma('dart2js:noInline')
  static GetTimelineSummaryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetTimelineSummaryRequest>(
          GetTimelineSummaryRequest.$_createMessage);
  static GetTimelineSummaryRequest? _defaultInstance;
}

/// The timeline's days, by library and newest first; assets without a capture time last.
class GetTimelineSummaryResponse extends $pb.GeneratedMessage {
  factory GetTimelineSummaryResponse({
    $core.Iterable<TimelineDay>? days,
  }) {
    final result = GetTimelineSummaryResponse._();
    if (days != null) result.days.addAll(days);
    return result;
  }

  GetTimelineSummaryResponse._();

  factory GetTimelineSummaryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTimelineSummaryResponse()..mergeFromBuffer(data, registry);
  factory GetTimelineSummaryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTimelineSummaryResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTimelineSummaryResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetTimelineSummaryResponse.$_createMessage)
    ..pPM<TimelineDay>(1, _omitFieldNames ? '' : 'days',
        subBuilder: TimelineDay.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTimelineSummaryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTimelineSummaryResponse copyWith(
          void Function(GetTimelineSummaryResponse) updates) =>
      super.copyWith(
              (message) => updates(message as GetTimelineSummaryResponse))
          as GetTimelineSummaryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetTimelineSummaryResponse() / GetTimelineSummaryResponse.new instead')
  static GetTimelineSummaryResponse create() => GetTimelineSummaryResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetTimelineSummaryResponse._();
  @$core.override
  GetTimelineSummaryResponse createEmptyInstance() =>
      GetTimelineSummaryResponse._();
  @$core.pragma('dart2js:noInline')
  static GetTimelineSummaryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetTimelineSummaryResponse>(
          GetTimelineSummaryResponse.$_createMessage);
  static GetTimelineSummaryResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<TimelineDay> get days => $_getList(0);
}

/// How many assets of a library the timeline shows on one local capture day.
class TimelineDay extends $pb.GeneratedMessage {
  factory TimelineDay({
    $core.String? libraryId,
    $core.String? date,
    $core.int? count,
  }) {
    final result = TimelineDay._();
    if (libraryId != null) result.libraryId = libraryId;
    if (date != null) result.date = date;
    if (count != null) result.count = count;
    return result;
  }

  TimelineDay._();

  factory TimelineDay.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TimelineDay()..mergeFromBuffer(data, registry);
  factory TimelineDay.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TimelineDay()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TimelineDay',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: TimelineDay.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'libraryId')
    ..aOS(2, _omitFieldNames ? '' : 'date')
    ..aI(3, _omitFieldNames ? '' : 'count', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimelineDay clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimelineDay copyWith(void Function(TimelineDay) updates) =>
      super.copyWith((message) => updates(message as TimelineDay))
          as TimelineDay;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TimelineDay() / TimelineDay.new instead')
  static TimelineDay create() => TimelineDay._();
  static $pb.GeneratedMessage $_createMessage() => TimelineDay._();
  @$core.override
  TimelineDay createEmptyInstance() => TimelineDay._();
  @$core.pragma('dart2js:noInline')
  static TimelineDay getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TimelineDay>(
          TimelineDay.$_createMessage);
  static TimelineDay? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get libraryId => $_getSZ(0);
  @$pb.TagNumber(1)
  set libraryId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLibraryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLibraryId() => $_clearField(1);

  /// The local capture date, e.g. "2025-07-14"; empty for assets without a capture time.
  @$pb.TagNumber(2)
  $core.String get date => $_getSZ(1);
  @$pb.TagNumber(2)
  set date($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDate() => $_has(1);
  @$pb.TagNumber(2)
  void clearDate() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get count => $_getIZ(2);
  @$pb.TagNumber(3)
  set count($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearCount() => $_clearField(3);
}

/// The files to look for.
class CheckHashesRequest extends $pb.GeneratedMessage {
  factory CheckHashesRequest({
    $core.Iterable<$core.List<$core.int>>? hashes,
  }) {
    final result = CheckHashesRequest._();
    if (hashes != null) result.hashes.addAll(hashes);
    return result;
  }

  CheckHashesRequest._();

  factory CheckHashesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckHashesRequest()..mergeFromBuffer(data, registry);
  factory CheckHashesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckHashesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckHashesRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CheckHashesRequest.$_createMessage)
    ..p<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'hashes', $pb.PbFieldType.PY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckHashesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckHashesRequest copyWith(void Function(CheckHashesRequest) updates) =>
      super.copyWith((message) => updates(message as CheckHashesRequest))
          as CheckHashesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CheckHashesRequest() / CheckHashesRequest.new instead')
  static CheckHashesRequest create() => CheckHashesRequest._();
  static $pb.GeneratedMessage $_createMessage() => CheckHashesRequest._();
  @$core.override
  CheckHashesRequest createEmptyInstance() => CheckHashesRequest._();
  @$core.pragma('dart2js:noInline')
  static CheckHashesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckHashesRequest>(
          CheckHashesRequest.$_createMessage);
  static CheckHashesRequest? _defaultInstance;

  /// The BLAKE3 hash of each file, 32 bytes; at most 1000.
  @$pb.TagNumber(1)
  $pb.PbList<$core.List<$core.int>> get hashes => $_getList(0);
}

/// Where each file already is.
class CheckHashesResponse extends $pb.GeneratedMessage {
  factory CheckHashesResponse({
    $core.Iterable<$core.String>? assetIds,
  }) {
    final result = CheckHashesResponse._();
    if (assetIds != null) result.assetIds.addAll(assetIds);
    return result;
  }

  CheckHashesResponse._();

  factory CheckHashesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckHashesResponse()..mergeFromBuffer(data, registry);
  factory CheckHashesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CheckHashesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckHashesResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CheckHashesResponse.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'assetIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckHashesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckHashesResponse copyWith(void Function(CheckHashesResponse) updates) =>
      super.copyWith((message) => updates(message as CheckHashesResponse))
          as CheckHashesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use CheckHashesResponse() / CheckHashesResponse.new instead')
  static CheckHashesResponse create() => CheckHashesResponse._();
  static $pb.GeneratedMessage $_createMessage() => CheckHashesResponse._();
  @$core.override
  CheckHashesResponse createEmptyInstance() => CheckHashesResponse._();
  @$core.pragma('dart2js:noInline')
  static CheckHashesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckHashesResponse>(
          CheckHashesResponse.$_createMessage);
  static CheckHashesResponse? _defaultInstance;

  /// In the order of the hashes: the asset whose original, RAW or JPEG partner or Live Photo video has the hash, is
  /// present and not in the trash, the earliest when several have it; empty when none has.
  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get assetIds => $_getList(0);
}

/// Mutations from a device's outbox.
class PushMutationsRequest extends $pb.GeneratedMessage {
  factory PushMutationsRequest({
    $core.Iterable<$2.Mutation>? mutations,
  }) {
    final result = PushMutationsRequest._();
    if (mutations != null) result.mutations.addAll(mutations);
    return result;
  }

  PushMutationsRequest._();

  factory PushMutationsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PushMutationsRequest()..mergeFromBuffer(data, registry);
  factory PushMutationsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PushMutationsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PushMutationsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: PushMutationsRequest.$_createMessage)
    ..pPM<$2.Mutation>(1, _omitFieldNames ? '' : 'mutations',
        subBuilder: $2.Mutation.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PushMutationsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PushMutationsRequest copyWith(void Function(PushMutationsRequest) updates) =>
      super.copyWith((message) => updates(message as PushMutationsRequest))
          as PushMutationsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PushMutationsRequest() / PushMutationsRequest.new instead')
  static PushMutationsRequest create() => PushMutationsRequest._();
  static $pb.GeneratedMessage $_createMessage() => PushMutationsRequest._();
  @$core.override
  PushMutationsRequest createEmptyInstance() => PushMutationsRequest._();
  @$core.pragma('dart2js:noInline')
  static PushMutationsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PushMutationsRequest>(
          PushMutationsRequest.$_createMessage);
  static PushMutationsRequest? _defaultInstance;

  /// In the order the device recorded them; at most 500.
  @$pb.TagNumber(1)
  $pb.PbList<$2.Mutation> get mutations => $_getList(0);
}

/// What became of the mutations, and of what they touched.
class PushMutationsResponse extends $pb.GeneratedMessage {
  factory PushMutationsResponse({
    $core.Iterable<MutationResult>? results,
    $core.Iterable<$1.Rows>? rows,
    $2.Hlc? clock,
  }) {
    final result = PushMutationsResponse._();
    if (results != null) result.results.addAll(results);
    if (rows != null) result.rows.addAll(rows);
    if (clock != null) result.clock = clock;
    return result;
  }

  PushMutationsResponse._();

  factory PushMutationsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PushMutationsResponse()..mergeFromBuffer(data, registry);
  factory PushMutationsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PushMutationsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PushMutationsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: PushMutationsResponse.$_createMessage)
    ..pPM<MutationResult>(1, _omitFieldNames ? '' : 'results',
        subBuilder: MutationResult.$_createMessage)
    ..pPM<$1.Rows>(2, _omitFieldNames ? '' : 'rows',
        subBuilder: $1.Rows.$_createMessage)
    ..aOM<$2.Hlc>(3, _omitFieldNames ? '' : 'clock',
        subBuilder: $2.Hlc.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PushMutationsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PushMutationsResponse copyWith(
          void Function(PushMutationsResponse) updates) =>
      super.copyWith((message) => updates(message as PushMutationsResponse))
          as PushMutationsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PushMutationsResponse() / PushMutationsResponse.new instead')
  static PushMutationsResponse create() => PushMutationsResponse._();
  static $pb.GeneratedMessage $_createMessage() => PushMutationsResponse._();
  @$core.override
  PushMutationsResponse createEmptyInstance() => PushMutationsResponse._();
  @$core.pragma('dart2js:noInline')
  static PushMutationsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PushMutationsResponse>(
          PushMutationsResponse.$_createMessage);
  static PushMutationsResponse? _defaultInstance;

  /// One per mutation, in their order.
  @$pb.TagNumber(1)
  $pb.PbList<MutationResult> get results => $_getList(0);

  /// The rows the mutations touched as they are now, as sync sends them; a row that is gone or that the caller cannot
  /// see is a deletion. The device applies them as it applies a sync batch, then its mutations still unsent.
  @$pb.TagNumber(2)
  $pb.PbList<$1.Rows> get rows => $_getList(1);

  /// The server's clock: the device's catches up with it, so that its next edits are later than those it has seen.
  @$pb.TagNumber(3)
  $2.Hlc get clock => $_getN(2);
  @$pb.TagNumber(3)
  set clock($2.Hlc value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasClock() => $_has(2);
  @$pb.TagNumber(3)
  void clearClock() => $_clearField(3);
  @$pb.TagNumber(3)
  $2.Hlc ensureClock() => $_ensure(2);
}

/// What became of one mutation: applied, which includes losing to a later edit of the same field, or rejected for good.
class MutationResult extends $pb.GeneratedMessage {
  factory MutationResult({
    $core.String? mutationId,
    $3.ErrorDetail? rejected,
  }) {
    final result = MutationResult._();
    if (mutationId != null) result.mutationId = mutationId;
    if (rejected != null) result.rejected = rejected;
    return result;
  }

  MutationResult._();

  factory MutationResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MutationResult()..mergeFromBuffer(data, registry);
  factory MutationResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MutationResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MutationResult',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: MutationResult.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'mutationId')
    ..aOM<$3.ErrorDetail>(2, _omitFieldNames ? '' : 'rejected',
        subBuilder: $3.ErrorDetail.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MutationResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MutationResult copyWith(void Function(MutationResult) updates) =>
      super.copyWith((message) => updates(message as MutationResult))
          as MutationResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MutationResult() / MutationResult.new instead')
  static MutationResult create() => MutationResult._();
  static $pb.GeneratedMessage $_createMessage() => MutationResult._();
  @$core.override
  MutationResult createEmptyInstance() => MutationResult._();
  @$core.pragma('dart2js:noInline')
  static MutationResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MutationResult>(
          MutationResult.$_createMessage);
  static MutationResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mutationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set mutationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMutationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMutationId() => $_clearField(1);

  /// Why the server refused the mutation: "mutation.not_found" (what it changes is gone or not the caller's to see),
  /// "mutation.forbidden" (the caller may see but not change it) or "mutation.invalid". The device rolls it back and
  /// tells its user. Absent when it was applied.
  @$pb.TagNumber(2)
  $3.ErrorDetail get rejected => $_getN(1);
  @$pb.TagNumber(2)
  set rejected($3.ErrorDetail value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRejected() => $_has(1);
  @$pb.TagNumber(2)
  void clearRejected() => $_clearField(2);
  @$pb.TagNumber(2)
  $3.ErrorDetail ensureRejected() => $_ensure(1);
}

/// Replicates what an account may see to its devices, and tells a backup what is already there (design 05).
class SyncServiceApi {
  final $pb.RpcClient _client;

  SyncServiceApi(this._client);

  /// Streams the changes of each named stream after its cursor, until every stream has caught up.
  $async.Future<SyncResponse> sync(
          $pb.ClientContext? ctx, SyncRequest request) =>
      _client.invoke<SyncResponse>(
          ctx, 'SyncService', 'Sync', request, SyncResponse());

  /// Counts the assets the timeline shows, per library and capture day, for placeholders before the first sync.
  $async.Future<GetTimelineSummaryResponse> getTimelineSummary(
          $pb.ClientContext? ctx, GetTimelineSummaryRequest request) =>
      _client.invoke<GetTimelineSummaryResponse>(ctx, 'SyncService',
          'GetTimelineSummary', request, GetTimelineSummaryResponse());

  /// Returns the asset of the caller's own libraries, external ones included, that already holds each file, so that a
  /// backup links to it instead of uploading the file again. Another account's files are never found (design 07 §7).
  $async.Future<CheckHashesResponse> checkHashes(
          $pb.ClientContext? ctx, CheckHashesRequest request) =>
      _client.invoke<CheckHashesResponse>(
          ctx, 'SyncService', 'CheckHashes', request, CheckHashesResponse());

  /// Applies the mutations of a device's outbox in order, each at most once, and answers how the rows they touched
  /// stand now (design 05 §5).
  $async.Future<PushMutationsResponse> pushMutations(
          $pb.ClientContext? ctx, PushMutationsRequest request) =>
      _client.invoke<PushMutationsResponse>(ctx, 'SyncService', 'PushMutations',
          request, PushMutationsResponse());

  /// Deletes the caller's own trashed assets, files and objects included, through the intent log (design 07 §6). More
  /// than 1,000 of them or 5 % of the caller's assets wait for the token of their own count (ADR-0257).
  $async.Future<EmptyTrashResponse> emptyTrash(
          $pb.ClientContext? ctx, EmptyTrashRequest request) =>
      _client.invoke<EmptyTrashResponse>(
          ctx, 'SyncService', 'EmptyTrash', request, EmptyTrashResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
