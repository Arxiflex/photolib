// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/search.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'search.pb.dart' as $0;
import 'search.pbjson.dart';

export 'search.pb.dart';

abstract class SearchServiceBase extends $pb.GeneratedService {
  $async.Future<$0.SearchTextResponse> searchText(
      $pb.ServerContext ctx, $0.SearchTextRequest request);
  $async.Future<$0.GetTextResponse> getText(
      $pb.ServerContext ctx, $0.GetTextRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'SearchText':
        return $0.SearchTextRequest();
      case 'GetText':
        return $0.GetTextRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'SearchText':
        return searchText(ctx, request as $0.SearchTextRequest);
      case 'GetText':
        return getText(ctx, request as $0.GetTextRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => SearchServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => SearchServiceBase$messageJson;
}
