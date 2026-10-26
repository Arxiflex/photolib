// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/faces.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'faces.pb.dart' as $1;
import 'faces.pbjson.dart';

export 'faces.pb.dart';

abstract class FaceServiceBase extends $pb.GeneratedService {
  $async.Future<$1.GetFaceConsentResponse> getFaceConsent(
      $pb.ServerContext ctx, $1.GetFaceConsentRequest request);
  $async.Future<$1.SetFaceConsentResponse> setFaceConsent(
      $pb.ServerContext ctx, $1.SetFaceConsentRequest request);
  $async.Future<$1.ListFacesResponse> listFaces(
      $pb.ServerContext ctx, $1.ListFacesRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'GetFaceConsent':
        return $1.GetFaceConsentRequest();
      case 'SetFaceConsent':
        return $1.SetFaceConsentRequest();
      case 'ListFaces':
        return $1.ListFacesRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'GetFaceConsent':
        return getFaceConsent(ctx, request as $1.GetFaceConsentRequest);
      case 'SetFaceConsent':
        return setFaceConsent(ctx, request as $1.SetFaceConsentRequest);
      case 'ListFaces':
        return listFaces(ctx, request as $1.ListFacesRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => FaceServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => FaceServiceBase$messageJson;
}
