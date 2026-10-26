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

import 'package:protobuf/protobuf.dart' as $pb;

import 'sync.pb.dart' as $5;
import 'sync.pbjson.dart';

export 'sync.pb.dart';

abstract class SyncServiceBase extends $pb.GeneratedService {
  $async.Future<$5.SyncResponse> sync(
      $pb.ServerContext ctx, $5.SyncRequest request);
  $async.Future<$5.GetTimelineSummaryResponse> getTimelineSummary(
      $pb.ServerContext ctx, $5.GetTimelineSummaryRequest request);
  $async.Future<$5.CheckHashesResponse> checkHashes(
      $pb.ServerContext ctx, $5.CheckHashesRequest request);
  $async.Future<$5.PushMutationsResponse> pushMutations(
      $pb.ServerContext ctx, $5.PushMutationsRequest request);
  $async.Future<$5.EmptyTrashResponse> emptyTrash(
      $pb.ServerContext ctx, $5.EmptyTrashRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'Sync':
        return $5.SyncRequest();
      case 'GetTimelineSummary':
        return $5.GetTimelineSummaryRequest();
      case 'CheckHashes':
        return $5.CheckHashesRequest();
      case 'PushMutations':
        return $5.PushMutationsRequest();
      case 'EmptyTrash':
        return $5.EmptyTrashRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'Sync':
        return sync(ctx, request as $5.SyncRequest);
      case 'GetTimelineSummary':
        return getTimelineSummary(ctx, request as $5.GetTimelineSummaryRequest);
      case 'CheckHashes':
        return checkHashes(ctx, request as $5.CheckHashesRequest);
      case 'PushMutations':
        return pushMutations(ctx, request as $5.PushMutationsRequest);
      case 'EmptyTrash':
        return emptyTrash(ctx, request as $5.EmptyTrashRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => SyncServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => SyncServiceBase$messageJson;
}
