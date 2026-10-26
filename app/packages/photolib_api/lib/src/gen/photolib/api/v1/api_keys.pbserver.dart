// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/api_keys.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'api_keys.pb.dart' as $1;
import 'api_keys.pbjson.dart';

export 'api_keys.pb.dart';

abstract class ApiKeyServiceBase extends $pb.GeneratedService {
  $async.Future<$1.ListApiKeysResponse> listApiKeys(
      $pb.ServerContext ctx, $1.ListApiKeysRequest request);
  $async.Future<$1.CreateApiKeyResponse> createApiKey(
      $pb.ServerContext ctx, $1.CreateApiKeyRequest request);
  $async.Future<$1.RevokeApiKeyResponse> revokeApiKey(
      $pb.ServerContext ctx, $1.RevokeApiKeyRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'ListApiKeys':
        return $1.ListApiKeysRequest();
      case 'CreateApiKey':
        return $1.CreateApiKeyRequest();
      case 'RevokeApiKey':
        return $1.RevokeApiKeyRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'ListApiKeys':
        return listApiKeys(ctx, request as $1.ListApiKeysRequest);
      case 'CreateApiKey':
        return createApiKey(ctx, request as $1.CreateApiKeyRequest);
      case 'RevokeApiKey':
        return revokeApiKey(ctx, request as $1.RevokeApiKeyRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => ApiKeyServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => ApiKeyServiceBase$messageJson;
}
