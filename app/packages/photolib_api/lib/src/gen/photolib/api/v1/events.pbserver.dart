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

import 'events.pb.dart' as $1;
import 'events.pbjson.dart';

export 'events.pb.dart';

abstract class EventServiceBase extends $pb.GeneratedService {
  $async.Future<$1.ListEventsResponse> listEvents(
      $pb.ServerContext ctx, $1.ListEventsRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'ListEvents':
        return $1.ListEventsRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'ListEvents':
        return listEvents(ctx, request as $1.ListEventsRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => EventServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => EventServiceBase$messageJson;
}

abstract class WebhookServiceBase extends $pb.GeneratedService {
  $async.Future<$1.ListWebhooksResponse> listWebhooks(
      $pb.ServerContext ctx, $1.ListWebhooksRequest request);
  $async.Future<$1.CreateWebhookResponse> createWebhook(
      $pb.ServerContext ctx, $1.CreateWebhookRequest request);
  $async.Future<$1.DeleteWebhookResponse> deleteWebhook(
      $pb.ServerContext ctx, $1.DeleteWebhookRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'ListWebhooks':
        return $1.ListWebhooksRequest();
      case 'CreateWebhook':
        return $1.CreateWebhookRequest();
      case 'DeleteWebhook':
        return $1.DeleteWebhookRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'ListWebhooks':
        return listWebhooks(ctx, request as $1.ListWebhooksRequest);
      case 'CreateWebhook':
        return createWebhook(ctx, request as $1.CreateWebhookRequest);
      case 'DeleteWebhook':
        return deleteWebhook(ctx, request as $1.DeleteWebhookRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => WebhookServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => WebhookServiceBase$messageJson;
}
