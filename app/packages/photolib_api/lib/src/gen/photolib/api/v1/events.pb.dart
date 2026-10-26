// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/events.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

import 'events.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'events.pbenum.dart';

/// A hint that an asset of a standard library changed: ids only, never its content. Webhooks POST it as JSON.
class Event extends $pb.GeneratedMessage {
  factory Event({
    $core.String? eventId,
    EventType? type,
    $0.Timestamp? recordedAt,
    $core.String? libraryId,
    $core.String? assetId,
  }) {
    final result = Event._();
    if (eventId != null) result.eventId = eventId;
    if (type != null) result.type = type;
    if (recordedAt != null) result.recordedAt = recordedAt;
    if (libraryId != null) result.libraryId = libraryId;
    if (assetId != null) result.assetId = assetId;
    return result;
  }

  Event._();

  factory Event.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Event()..mergeFromBuffer(data, registry);
  factory Event.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Event()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Event',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: Event.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'eventId')
    ..aE<EventType>(2, _omitFieldNames ? '' : 'type',
        enumValues: EventType.values)
    ..aOM<$0.Timestamp>(3, _omitFieldNames ? '' : 'recordedAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'libraryId')
    ..aOS(5, _omitFieldNames ? '' : 'assetId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Event clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Event copyWith(void Function(Event) updates) =>
      super.copyWith((message) => updates(message as Event)) as Event;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Event() / Event.new instead')
  static Event create() => Event._();
  static $pb.GeneratedMessage $_createMessage() => Event._();
  @$core.override
  Event createEmptyInstance() => Event._();
  @$core.pragma('dart2js:noInline')
  static Event getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Event>(Event.$_createMessage);
  static Event? _defaultInstance;

  /// Opaque and unique; listing events after it continues from this one.
  @$pb.TagNumber(1)
  $core.String get eventId => $_getSZ(0);
  @$pb.TagNumber(1)
  set eventId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEventId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventId() => $_clearField(1);

  @$pb.TagNumber(2)
  EventType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(EventType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

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
  $core.String get libraryId => $_getSZ(3);
  @$pb.TagNumber(4)
  set libraryId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLibraryId() => $_has(3);
  @$pb.TagNumber(4)
  void clearLibraryId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get assetId => $_getSZ(4);
  @$pb.TagNumber(5)
  set assetId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAssetId() => $_has(4);
  @$pb.TagNumber(5)
  void clearAssetId() => $_clearField(5);
}

/// Where to read from.
class ListEventsRequest extends $pb.GeneratedMessage {
  factory ListEventsRequest({
    $core.String? after,
    $core.int? pageSize,
  }) {
    final result = ListEventsRequest._();
    if (after != null) result.after = after;
    if (pageSize != null) result.pageSize = pageSize;
    return result;
  }

  ListEventsRequest._();

  factory ListEventsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListEventsRequest()..mergeFromBuffer(data, registry);
  factory ListEventsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListEventsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListEventsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListEventsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'after')
    ..aI(2, _omitFieldNames ? '' : 'pageSize', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventsRequest copyWith(void Function(ListEventsRequest) updates) =>
      super.copyWith((message) => updates(message as ListEventsRequest))
          as ListEventsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListEventsRequest() / ListEventsRequest.new instead')
  static ListEventsRequest create() => ListEventsRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListEventsRequest._();
  @$core.override
  ListEventsRequest createEmptyInstance() => ListEventsRequest._();
  @$core.pragma('dart2js:noInline')
  static ListEventsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListEventsRequest>(
          ListEventsRequest.$_createMessage);
  static ListEventsRequest? _defaultInstance;

  /// A `next_after` or an `event_id` read before; empty starts at the oldest event kept.
  @$pb.TagNumber(1)
  $core.String get after => $_getSZ(0);
  @$pb.TagNumber(1)
  set after($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAfter() => $_has(0);
  @$pb.TagNumber(1)
  void clearAfter() => $_clearField(1);

  /// At most this many events: 1 to 1000; 0 means 100.
  @$pb.TagNumber(2)
  $core.int get pageSize => $_getIZ(1);
  @$pb.TagNumber(2)
  set pageSize($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPageSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageSize() => $_clearField(2);
}

/// A page of events.
class ListEventsResponse extends $pb.GeneratedMessage {
  factory ListEventsResponse({
    $core.Iterable<Event>? events,
    $core.String? nextAfter,
  }) {
    final result = ListEventsResponse._();
    if (events != null) result.events.addAll(events);
    if (nextAfter != null) result.nextAfter = nextAfter;
    return result;
  }

  ListEventsResponse._();

  factory ListEventsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListEventsResponse()..mergeFromBuffer(data, registry);
  factory ListEventsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListEventsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListEventsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListEventsResponse.$_createMessage)
    ..pPM<Event>(1, _omitFieldNames ? '' : 'events',
        subBuilder: Event.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'nextAfter')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventsResponse copyWith(void Function(ListEventsResponse) updates) =>
      super.copyWith((message) => updates(message as ListEventsResponse))
          as ListEventsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListEventsResponse() / ListEventsResponse.new instead')
  static ListEventsResponse create() => ListEventsResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListEventsResponse._();
  @$core.override
  ListEventsResponse createEmptyInstance() => ListEventsResponse._();
  @$core.pragma('dart2js:noInline')
  static ListEventsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListEventsResponse>(
          ListEventsResponse.$_createMessage);
  static ListEventsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Event> get events => $_getList(0);

  /// Pass as `after` to read on: past the last event listed, and past those the caller cannot see.
  @$pb.TagNumber(2)
  $core.String get nextAfter => $_getSZ(1);
  @$pb.TagNumber(2)
  set nextAfter($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNextAfter() => $_has(1);
  @$pb.TagNumber(2)
  void clearNextAfter() => $_clearField(2);
}

/// A URL that the account's events are POSTed to, signed as Standard Webhooks sign them.
class Webhook extends $pb.GeneratedMessage {
  factory Webhook({
    $core.String? webhookId,
    $core.String? url,
    $0.Timestamp? createdAt,
    $0.Timestamp? deliveredAt,
    $0.Timestamp? failingSince,
    $core.int? lastStatus,
  }) {
    final result = Webhook._();
    if (webhookId != null) result.webhookId = webhookId;
    if (url != null) result.url = url;
    if (createdAt != null) result.createdAt = createdAt;
    if (deliveredAt != null) result.deliveredAt = deliveredAt;
    if (failingSince != null) result.failingSince = failingSince;
    if (lastStatus != null) result.lastStatus = lastStatus;
    return result;
  }

  Webhook._();

  factory Webhook.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Webhook()..mergeFromBuffer(data, registry);
  factory Webhook.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Webhook()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Webhook',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: Webhook.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'webhookId')
    ..aOS(2, _omitFieldNames ? '' : 'url')
    ..aOM<$0.Timestamp>(3, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<$0.Timestamp>(4, _omitFieldNames ? '' : 'deliveredAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<$0.Timestamp>(5, _omitFieldNames ? '' : 'failingSince',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aI(6, _omitFieldNames ? '' : 'lastStatus', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Webhook clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Webhook copyWith(void Function(Webhook) updates) =>
      super.copyWith((message) => updates(message as Webhook)) as Webhook;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Webhook() / Webhook.new instead')
  static Webhook create() => Webhook._();
  static $pb.GeneratedMessage $_createMessage() => Webhook._();
  @$core.override
  Webhook createEmptyInstance() => Webhook._();
  @$core.pragma('dart2js:noInline')
  static Webhook getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Webhook>(Webhook.$_createMessage);
  static Webhook? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get webhookId => $_getSZ(0);
  @$pb.TagNumber(1)
  set webhookId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWebhookId() => $_has(0);
  @$pb.TagNumber(1)
  void clearWebhookId() => $_clearField(1);

  /// http or https, at most 2000 characters, never at a loopback, link-local, unspecified, broadcast or multicast
  /// address.
  @$pb.TagNumber(2)
  $core.String get url => $_getSZ(1);
  @$pb.TagNumber(2)
  set url($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUrl() => $_has(1);
  @$pb.TagNumber(2)
  void clearUrl() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.Timestamp get createdAt => $_getN(2);
  @$pb.TagNumber(3)
  set createdAt($0.Timestamp value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCreatedAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreatedAt() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.Timestamp ensureCreatedAt() => $_ensure(2);

  /// The last delivery that succeeded; absent until then.
  @$pb.TagNumber(4)
  $0.Timestamp get deliveredAt => $_getN(3);
  @$pb.TagNumber(4)
  set deliveredAt($0.Timestamp value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasDeliveredAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeliveredAt() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.Timestamp ensureDeliveredAt() => $_ensure(3);

  /// Since when its deliveries fail; absent while they succeed.
  @$pb.TagNumber(5)
  $0.Timestamp get failingSince => $_getN(4);
  @$pb.TagNumber(5)
  set failingSince($0.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasFailingSince() => $_has(4);
  @$pb.TagNumber(5)
  void clearFailingSince() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.Timestamp ensureFailingSince() => $_ensure(4);

  /// The HTTP status of the last failed delivery; 0 when none came.
  @$pb.TagNumber(6)
  $core.int get lastStatus => $_getIZ(5);
  @$pb.TagNumber(6)
  set lastStatus($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLastStatus() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastStatus() => $_clearField(6);
}

/// Asks for the caller's webhooks.
class ListWebhooksRequest extends $pb.GeneratedMessage {
  factory ListWebhooksRequest() => ListWebhooksRequest._();

  ListWebhooksRequest._();

  factory ListWebhooksRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListWebhooksRequest()..mergeFromBuffer(data, registry);
  factory ListWebhooksRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListWebhooksRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListWebhooksRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListWebhooksRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListWebhooksRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListWebhooksRequest copyWith(void Function(ListWebhooksRequest) updates) =>
      super.copyWith((message) => updates(message as ListWebhooksRequest))
          as ListWebhooksRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListWebhooksRequest() / ListWebhooksRequest.new instead')
  static ListWebhooksRequest create() => ListWebhooksRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListWebhooksRequest._();
  @$core.override
  ListWebhooksRequest createEmptyInstance() => ListWebhooksRequest._();
  @$core.pragma('dart2js:noInline')
  static ListWebhooksRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListWebhooksRequest>(
          ListWebhooksRequest.$_createMessage);
  static ListWebhooksRequest? _defaultInstance;
}

/// The caller's webhooks.
class ListWebhooksResponse extends $pb.GeneratedMessage {
  factory ListWebhooksResponse({
    $core.Iterable<Webhook>? webhooks,
  }) {
    final result = ListWebhooksResponse._();
    if (webhooks != null) result.webhooks.addAll(webhooks);
    return result;
  }

  ListWebhooksResponse._();

  factory ListWebhooksResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListWebhooksResponse()..mergeFromBuffer(data, registry);
  factory ListWebhooksResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListWebhooksResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListWebhooksResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListWebhooksResponse.$_createMessage)
    ..pPM<Webhook>(1, _omitFieldNames ? '' : 'webhooks',
        subBuilder: Webhook.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListWebhooksResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListWebhooksResponse copyWith(void Function(ListWebhooksResponse) updates) =>
      super.copyWith((message) => updates(message as ListWebhooksResponse))
          as ListWebhooksResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListWebhooksResponse() / ListWebhooksResponse.new instead')
  static ListWebhooksResponse create() => ListWebhooksResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListWebhooksResponse._();
  @$core.override
  ListWebhooksResponse createEmptyInstance() => ListWebhooksResponse._();
  @$core.pragma('dart2js:noInline')
  static ListWebhooksResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListWebhooksResponse>(
          ListWebhooksResponse.$_createMessage);
  static ListWebhooksResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Webhook> get webhooks => $_getList(0);
}

/// The webhook to create.
class CreateWebhookRequest extends $pb.GeneratedMessage {
  factory CreateWebhookRequest({
    $core.String? url,
  }) {
    final result = CreateWebhookRequest._();
    if (url != null) result.url = url;
    return result;
  }

  CreateWebhookRequest._();

  factory CreateWebhookRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateWebhookRequest()..mergeFromBuffer(data, registry);
  factory CreateWebhookRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateWebhookRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateWebhookRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateWebhookRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateWebhookRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateWebhookRequest copyWith(void Function(CreateWebhookRequest) updates) =>
      super.copyWith((message) => updates(message as CreateWebhookRequest))
          as CreateWebhookRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateWebhookRequest() / CreateWebhookRequest.new instead')
  static CreateWebhookRequest create() => CreateWebhookRequest._();
  static $pb.GeneratedMessage $_createMessage() => CreateWebhookRequest._();
  @$core.override
  CreateWebhookRequest createEmptyInstance() => CreateWebhookRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateWebhookRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateWebhookRequest>(
          CreateWebhookRequest.$_createMessage);
  static CreateWebhookRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);
}

/// The webhook created, and its secret.
class CreateWebhookResponse extends $pb.GeneratedMessage {
  factory CreateWebhookResponse({
    Webhook? webhook,
    $core.String? secret,
  }) {
    final result = CreateWebhookResponse._();
    if (webhook != null) result.webhook = webhook;
    if (secret != null) result.secret = secret;
    return result;
  }

  CreateWebhookResponse._();

  factory CreateWebhookResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateWebhookResponse()..mergeFromBuffer(data, registry);
  factory CreateWebhookResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateWebhookResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateWebhookResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateWebhookResponse.$_createMessage)
    ..aOM<Webhook>(1, _omitFieldNames ? '' : 'webhook',
        subBuilder: Webhook.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'secret')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateWebhookResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateWebhookResponse copyWith(
          void Function(CreateWebhookResponse) updates) =>
      super.copyWith((message) => updates(message as CreateWebhookResponse))
          as CreateWebhookResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateWebhookResponse() / CreateWebhookResponse.new instead')
  static CreateWebhookResponse create() => CreateWebhookResponse._();
  static $pb.GeneratedMessage $_createMessage() => CreateWebhookResponse._();
  @$core.override
  CreateWebhookResponse createEmptyInstance() => CreateWebhookResponse._();
  @$core.pragma('dart2js:noInline')
  static CreateWebhookResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateWebhookResponse>(
          CreateWebhookResponse.$_createMessage);
  static CreateWebhookResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Webhook get webhook => $_getN(0);
  @$pb.TagNumber(1)
  set webhook(Webhook value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasWebhook() => $_has(0);
  @$pb.TagNumber(1)
  void clearWebhook() => $_clearField(1);
  @$pb.TagNumber(1)
  Webhook ensureWebhook() => $_ensure(0);

  /// `whsec_` and the base64 of 32 bytes: the key of the HMAC-SHA256 in each delivery's `webhook-signature`.
  @$pb.TagNumber(2)
  $core.String get secret => $_getSZ(1);
  @$pb.TagNumber(2)
  set secret($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearSecret() => $_clearField(2);
}

/// The webhook to delete.
class DeleteWebhookRequest extends $pb.GeneratedMessage {
  factory DeleteWebhookRequest({
    $core.String? webhookId,
  }) {
    final result = DeleteWebhookRequest._();
    if (webhookId != null) result.webhookId = webhookId;
    return result;
  }

  DeleteWebhookRequest._();

  factory DeleteWebhookRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteWebhookRequest()..mergeFromBuffer(data, registry);
  factory DeleteWebhookRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteWebhookRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteWebhookRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: DeleteWebhookRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'webhookId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteWebhookRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteWebhookRequest copyWith(void Function(DeleteWebhookRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteWebhookRequest))
          as DeleteWebhookRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeleteWebhookRequest() / DeleteWebhookRequest.new instead')
  static DeleteWebhookRequest create() => DeleteWebhookRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeleteWebhookRequest._();
  @$core.override
  DeleteWebhookRequest createEmptyInstance() => DeleteWebhookRequest._();
  @$core.pragma('dart2js:noInline')
  static DeleteWebhookRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteWebhookRequest>(
          DeleteWebhookRequest.$_createMessage);
  static DeleteWebhookRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get webhookId => $_getSZ(0);
  @$pb.TagNumber(1)
  set webhookId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWebhookId() => $_has(0);
  @$pb.TagNumber(1)
  void clearWebhookId() => $_clearField(1);
}

/// The webhook is gone.
class DeleteWebhookResponse extends $pb.GeneratedMessage {
  factory DeleteWebhookResponse() => DeleteWebhookResponse._();

  DeleteWebhookResponse._();

  factory DeleteWebhookResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteWebhookResponse()..mergeFromBuffer(data, registry);
  factory DeleteWebhookResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteWebhookResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteWebhookResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: DeleteWebhookResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteWebhookResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteWebhookResponse copyWith(
          void Function(DeleteWebhookResponse) updates) =>
      super.copyWith((message) => updates(message as DeleteWebhookResponse))
          as DeleteWebhookResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DeleteWebhookResponse() / DeleteWebhookResponse.new instead')
  static DeleteWebhookResponse create() => DeleteWebhookResponse._();
  static $pb.GeneratedMessage $_createMessage() => DeleteWebhookResponse._();
  @$core.override
  DeleteWebhookResponse createEmptyInstance() => DeleteWebhookResponse._();
  @$core.pragma('dart2js:noInline')
  static DeleteWebhookResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteWebhookResponse>(
          DeleteWebhookResponse.$_createMessage);
  static DeleteWebhookResponse? _defaultInstance;
}

/// The events of the assets the caller may view, in order, kept for 7 days. Integrations poll it with a key.
class EventServiceApi {
  final $pb.RpcClient _client;

  EventServiceApi(this._client);

  /// Returns the events after a cursor, oldest first.
  $async.Future<ListEventsResponse> listEvents(
          $pb.ClientContext? ctx, ListEventsRequest request) =>
      _client.invoke<ListEventsResponse>(
          ctx, 'EventService', 'ListEvents', request, ListEventsResponse());
}

/// The caller's webhooks, which only the account signed in, never an API key, manages; at most 10.
class WebhookServiceApi {
  final $pb.RpcClient _client;

  WebhookServiceApi(this._client);

  /// Returns the caller's webhooks, oldest first.
  $async.Future<ListWebhooksResponse> listWebhooks(
          $pb.ClientContext? ctx, ListWebhooksRequest request) =>
      _client.invoke<ListWebhooksResponse>(ctx, 'WebhookService',
          'ListWebhooks', request, ListWebhooksResponse());

  /// Registers a webhook and returns its signing secret, which is never shown again.
  $async.Future<CreateWebhookResponse> createWebhook(
          $pb.ClientContext? ctx, CreateWebhookRequest request) =>
      _client.invoke<CreateWebhookResponse>(ctx, 'WebhookService',
          'CreateWebhook', request, CreateWebhookResponse());

  /// Deletes one of the caller's webhooks; it gets nothing more.
  $async.Future<DeleteWebhookResponse> deleteWebhook(
          $pb.ClientContext? ctx, DeleteWebhookRequest request) =>
      _client.invoke<DeleteWebhookResponse>(ctx, 'WebhookService',
          'DeleteWebhook', request, DeleteWebhookResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
