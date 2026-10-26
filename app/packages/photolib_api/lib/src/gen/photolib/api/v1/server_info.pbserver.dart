// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/server_info.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'server_info.pb.dart' as $0;
import 'server_info.pbjson.dart';

export 'server_info.pb.dart';

abstract class ServerInfoServiceBase extends $pb.GeneratedService {
  $async.Future<$0.GetServerInfoResponse> getServerInfo(
      $pb.ServerContext ctx, $0.GetServerInfoRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'GetServerInfo':
        return $0.GetServerInfoRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'GetServerInfo':
        return getServerInfo(ctx, request as $0.GetServerInfoRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json =>
      ServerInfoServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => ServerInfoServiceBase$messageJson;
}
