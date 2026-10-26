// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/events.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

import 'package:protobuf/well_known_types/google/protobuf/timestamp.pbjson.dart'
    as $0;

@$core.Deprecated('Use eventTypeDescriptor instead')
const EventType$json = {
  '1': 'EventType',
  '2': [
    {'1': 'EVENT_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'EVENT_TYPE_ASSET_CREATED', '2': 1},
    {'1': 'EVENT_TYPE_ASSET_TRASHED', '2': 2},
    {'1': 'EVENT_TYPE_ASSET_RESTORED', '2': 3},
    {'1': 'EVENT_TYPE_ASSET_DELETED', '2': 4},
  ],
};

/// Descriptor for `EventType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List eventTypeDescriptor = $convert.base64Decode(
    'CglFdmVudFR5cGUSGgoWRVZFTlRfVFlQRV9VTlNQRUNJRklFRBAAEhwKGEVWRU5UX1RZUEVfQV'
    'NTRVRfQ1JFQVRFRBABEhwKGEVWRU5UX1RZUEVfQVNTRVRfVFJBU0hFRBACEh0KGUVWRU5UX1RZ'
    'UEVfQVNTRVRfUkVTVE9SRUQQAxIcChhFVkVOVF9UWVBFX0FTU0VUX0RFTEVURUQQBA==');

@$core.Deprecated('Use eventDescriptor instead')
const Event$json = {
  '1': 'Event',
  '2': [
    {'1': 'event_id', '3': 1, '4': 1, '5': 9, '10': 'eventId'},
    {
      '1': 'type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.photolib.api.v1.EventType',
      '10': 'type'
    },
    {
      '1': 'recorded_at',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'recordedAt'
    },
    {'1': 'library_id', '3': 4, '4': 1, '5': 9, '10': 'libraryId'},
    {'1': 'asset_id', '3': 5, '4': 1, '5': 9, '10': 'assetId'},
  ],
};

/// Descriptor for `Event`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List eventDescriptor = $convert.base64Decode(
    'CgVFdmVudBIZCghldmVudF9pZBgBIAEoCVIHZXZlbnRJZBIuCgR0eXBlGAIgASgOMhoucGhvdG'
    '9saWIuYXBpLnYxLkV2ZW50VHlwZVIEdHlwZRI7CgtyZWNvcmRlZF9hdBgDIAEoCzIaLmdvb2ds'
    'ZS5wcm90b2J1Zi5UaW1lc3RhbXBSCnJlY29yZGVkQXQSHQoKbGlicmFyeV9pZBgEIAEoCVIJbG'
    'licmFyeUlkEhkKCGFzc2V0X2lkGAUgASgJUgdhc3NldElk');

@$core.Deprecated('Use listEventsRequestDescriptor instead')
const ListEventsRequest$json = {
  '1': 'ListEventsRequest',
  '2': [
    {'1': 'after', '3': 1, '4': 1, '5': 9, '10': 'after'},
    {'1': 'page_size', '3': 2, '4': 1, '5': 13, '10': 'pageSize'},
  ],
};

/// Descriptor for `ListEventsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listEventsRequestDescriptor = $convert.base64Decode(
    'ChFMaXN0RXZlbnRzUmVxdWVzdBIUCgVhZnRlchgBIAEoCVIFYWZ0ZXISGwoJcGFnZV9zaXplGA'
    'IgASgNUghwYWdlU2l6ZQ==');

@$core.Deprecated('Use listEventsResponseDescriptor instead')
const ListEventsResponse$json = {
  '1': 'ListEventsResponse',
  '2': [
    {
      '1': 'events',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.Event',
      '10': 'events'
    },
    {'1': 'next_after', '3': 2, '4': 1, '5': 9, '10': 'nextAfter'},
  ],
};

/// Descriptor for `ListEventsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listEventsResponseDescriptor = $convert.base64Decode(
    'ChJMaXN0RXZlbnRzUmVzcG9uc2USLgoGZXZlbnRzGAEgAygLMhYucGhvdG9saWIuYXBpLnYxLk'
    'V2ZW50UgZldmVudHMSHQoKbmV4dF9hZnRlchgCIAEoCVIJbmV4dEFmdGVy');

@$core.Deprecated('Use webhookDescriptor instead')
const Webhook$json = {
  '1': 'Webhook',
  '2': [
    {'1': 'webhook_id', '3': 1, '4': 1, '5': 9, '10': 'webhookId'},
    {'1': 'url', '3': 2, '4': 1, '5': 9, '10': 'url'},
    {
      '1': 'created_at',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
    {
      '1': 'delivered_at',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'deliveredAt'
    },
    {
      '1': 'failing_since',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'failingSince'
    },
    {'1': 'last_status', '3': 6, '4': 1, '5': 13, '10': 'lastStatus'},
  ],
};

/// Descriptor for `Webhook`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List webhookDescriptor = $convert.base64Decode(
    'CgdXZWJob29rEh0KCndlYmhvb2tfaWQYASABKAlSCXdlYmhvb2tJZBIQCgN1cmwYAiABKAlSA3'
    'VybBI5CgpjcmVhdGVkX2F0GAMgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIJY3Jl'
    'YXRlZEF0Ej0KDGRlbGl2ZXJlZF9hdBgEIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbX'
    'BSC2RlbGl2ZXJlZEF0Ej8KDWZhaWxpbmdfc2luY2UYBSABKAsyGi5nb29nbGUucHJvdG9idWYu'
    'VGltZXN0YW1wUgxmYWlsaW5nU2luY2USHwoLbGFzdF9zdGF0dXMYBiABKA1SCmxhc3RTdGF0dX'
    'M=');

@$core.Deprecated('Use listWebhooksRequestDescriptor instead')
const ListWebhooksRequest$json = {
  '1': 'ListWebhooksRequest',
};

/// Descriptor for `ListWebhooksRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listWebhooksRequestDescriptor =
    $convert.base64Decode('ChNMaXN0V2ViaG9va3NSZXF1ZXN0');

@$core.Deprecated('Use listWebhooksResponseDescriptor instead')
const ListWebhooksResponse$json = {
  '1': 'ListWebhooksResponse',
  '2': [
    {
      '1': 'webhooks',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.Webhook',
      '10': 'webhooks'
    },
  ],
};

/// Descriptor for `ListWebhooksResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listWebhooksResponseDescriptor = $convert.base64Decode(
    'ChRMaXN0V2ViaG9va3NSZXNwb25zZRI0Cgh3ZWJob29rcxgBIAMoCzIYLnBob3RvbGliLmFwaS'
    '52MS5XZWJob29rUgh3ZWJob29rcw==');

@$core.Deprecated('Use createWebhookRequestDescriptor instead')
const CreateWebhookRequest$json = {
  '1': 'CreateWebhookRequest',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
  ],
};

/// Descriptor for `CreateWebhookRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createWebhookRequestDescriptor = $convert
    .base64Decode('ChRDcmVhdGVXZWJob29rUmVxdWVzdBIQCgN1cmwYASABKAlSA3VybA==');

@$core.Deprecated('Use createWebhookResponseDescriptor instead')
const CreateWebhookResponse$json = {
  '1': 'CreateWebhookResponse',
  '2': [
    {
      '1': 'webhook',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Webhook',
      '10': 'webhook'
    },
    {'1': 'secret', '3': 2, '4': 1, '5': 9, '10': 'secret'},
  ],
};

/// Descriptor for `CreateWebhookResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createWebhookResponseDescriptor = $convert.base64Decode(
    'ChVDcmVhdGVXZWJob29rUmVzcG9uc2USMgoHd2ViaG9vaxgBIAEoCzIYLnBob3RvbGliLmFwaS'
    '52MS5XZWJob29rUgd3ZWJob29rEhYKBnNlY3JldBgCIAEoCVIGc2VjcmV0');

@$core.Deprecated('Use deleteWebhookRequestDescriptor instead')
const DeleteWebhookRequest$json = {
  '1': 'DeleteWebhookRequest',
  '2': [
    {'1': 'webhook_id', '3': 1, '4': 1, '5': 9, '10': 'webhookId'},
  ],
};

/// Descriptor for `DeleteWebhookRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteWebhookRequestDescriptor = $convert.base64Decode(
    'ChREZWxldGVXZWJob29rUmVxdWVzdBIdCgp3ZWJob29rX2lkGAEgASgJUgl3ZWJob29rSWQ=');

@$core.Deprecated('Use deleteWebhookResponseDescriptor instead')
const DeleteWebhookResponse$json = {
  '1': 'DeleteWebhookResponse',
};

/// Descriptor for `DeleteWebhookResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteWebhookResponseDescriptor =
    $convert.base64Decode('ChVEZWxldGVXZWJob29rUmVzcG9uc2U=');

const $core.Map<$core.String, $core.dynamic> EventServiceBase$json = {
  '1': 'EventService',
  '2': [
    {
      '1': 'ListEvents',
      '2': '.photolib.api.v1.ListEventsRequest',
      '3': '.photolib.api.v1.ListEventsResponse'
    },
  ],
};

@$core.Deprecated('Use eventServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    EventServiceBase$messageJson = {
  '.photolib.api.v1.ListEventsRequest': ListEventsRequest$json,
  '.photolib.api.v1.ListEventsResponse': ListEventsResponse$json,
  '.photolib.api.v1.Event': Event$json,
  '.google.protobuf.Timestamp': $0.Timestamp$json,
};

/// Descriptor for `EventService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List eventServiceDescriptor = $convert.base64Decode(
    'CgxFdmVudFNlcnZpY2USVQoKTGlzdEV2ZW50cxIiLnBob3RvbGliLmFwaS52MS5MaXN0RXZlbn'
    'RzUmVxdWVzdBojLnBob3RvbGliLmFwaS52MS5MaXN0RXZlbnRzUmVzcG9uc2U=');

const $core.Map<$core.String, $core.dynamic> WebhookServiceBase$json = {
  '1': 'WebhookService',
  '2': [
    {
      '1': 'ListWebhooks',
      '2': '.photolib.api.v1.ListWebhooksRequest',
      '3': '.photolib.api.v1.ListWebhooksResponse'
    },
    {
      '1': 'CreateWebhook',
      '2': '.photolib.api.v1.CreateWebhookRequest',
      '3': '.photolib.api.v1.CreateWebhookResponse'
    },
    {
      '1': 'DeleteWebhook',
      '2': '.photolib.api.v1.DeleteWebhookRequest',
      '3': '.photolib.api.v1.DeleteWebhookResponse'
    },
  ],
};

@$core.Deprecated('Use webhookServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    WebhookServiceBase$messageJson = {
  '.photolib.api.v1.ListWebhooksRequest': ListWebhooksRequest$json,
  '.photolib.api.v1.ListWebhooksResponse': ListWebhooksResponse$json,
  '.photolib.api.v1.Webhook': Webhook$json,
  '.google.protobuf.Timestamp': $0.Timestamp$json,
  '.photolib.api.v1.CreateWebhookRequest': CreateWebhookRequest$json,
  '.photolib.api.v1.CreateWebhookResponse': CreateWebhookResponse$json,
  '.photolib.api.v1.DeleteWebhookRequest': DeleteWebhookRequest$json,
  '.photolib.api.v1.DeleteWebhookResponse': DeleteWebhookResponse$json,
};

/// Descriptor for `WebhookService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List webhookServiceDescriptor = $convert.base64Decode(
    'Cg5XZWJob29rU2VydmljZRJbCgxMaXN0V2ViaG9va3MSJC5waG90b2xpYi5hcGkudjEuTGlzdF'
    'dlYmhvb2tzUmVxdWVzdBolLnBob3RvbGliLmFwaS52MS5MaXN0V2ViaG9va3NSZXNwb25zZRJe'
    'Cg1DcmVhdGVXZWJob29rEiUucGhvdG9saWIuYXBpLnYxLkNyZWF0ZVdlYmhvb2tSZXF1ZXN0Gi'
    'YucGhvdG9saWIuYXBpLnYxLkNyZWF0ZVdlYmhvb2tSZXNwb25zZRJeCg1EZWxldGVXZWJob29r'
    'EiUucGhvdG9saWIuYXBpLnYxLkRlbGV0ZVdlYmhvb2tSZXF1ZXN0GiYucGhvdG9saWIuYXBpLn'
    'YxLkRlbGV0ZVdlYmhvb2tSZXNwb25zZQ==');
