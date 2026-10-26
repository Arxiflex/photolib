// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/faces.proto.

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

@$core.Deprecated('Use getFaceConsentRequestDescriptor instead')
const GetFaceConsentRequest$json = {
  '1': 'GetFaceConsentRequest',
};

/// Descriptor for `GetFaceConsentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFaceConsentRequestDescriptor =
    $convert.base64Decode('ChVHZXRGYWNlQ29uc2VudFJlcXVlc3Q=');

@$core.Deprecated('Use faceConsentStateDescriptor instead')
const FaceConsentState$json = {
  '1': 'FaceConsentState',
  '2': [
    {'1': 'notice_version', '3': 1, '4': 1, '5': 13, '10': 'noticeVersion'},
    {'1': 'granted', '3': 2, '4': 1, '5': 8, '10': 'granted'},
    {'1': 'granted_version', '3': 3, '4': 1, '5': 13, '10': 'grantedVersion'},
    {
      '1': 'granted_at',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'grantedAt'
    },
    {'1': 'available', '3': 5, '4': 1, '5': 8, '10': 'available'},
  ],
};

/// Descriptor for `FaceConsentState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List faceConsentStateDescriptor = $convert.base64Decode(
    'ChBGYWNlQ29uc2VudFN0YXRlEiUKDm5vdGljZV92ZXJzaW9uGAEgASgNUg1ub3RpY2VWZXJzaW'
    '9uEhgKB2dyYW50ZWQYAiABKAhSB2dyYW50ZWQSJwoPZ3JhbnRlZF92ZXJzaW9uGAMgASgNUg5n'
    'cmFudGVkVmVyc2lvbhI5CgpncmFudGVkX2F0GAQgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbW'
    'VzdGFtcFIJZ3JhbnRlZEF0EhwKCWF2YWlsYWJsZRgFIAEoCFIJYXZhaWxhYmxl');

@$core.Deprecated('Use getFaceConsentResponseDescriptor instead')
const GetFaceConsentResponse$json = {
  '1': 'GetFaceConsentResponse',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.FaceConsentState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `GetFaceConsentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFaceConsentResponseDescriptor =
    $convert.base64Decode(
        'ChZHZXRGYWNlQ29uc2VudFJlc3BvbnNlEjcKBXN0YXRlGAEgASgLMiEucGhvdG9saWIuYXBpLn'
        'YxLkZhY2VDb25zZW50U3RhdGVSBXN0YXRl');

@$core.Deprecated('Use setFaceConsentRequestDescriptor instead')
const SetFaceConsentRequest$json = {
  '1': 'SetFaceConsentRequest',
  '2': [
    {'1': 'granted', '3': 1, '4': 1, '5': 8, '10': 'granted'},
    {'1': 'notice_version', '3': 2, '4': 1, '5': 13, '10': 'noticeVersion'},
  ],
};

/// Descriptor for `SetFaceConsentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setFaceConsentRequestDescriptor = $convert.base64Decode(
    'ChVTZXRGYWNlQ29uc2VudFJlcXVlc3QSGAoHZ3JhbnRlZBgBIAEoCFIHZ3JhbnRlZBIlCg5ub3'
    'RpY2VfdmVyc2lvbhgCIAEoDVINbm90aWNlVmVyc2lvbg==');

@$core.Deprecated('Use setFaceConsentResponseDescriptor instead')
const SetFaceConsentResponse$json = {
  '1': 'SetFaceConsentResponse',
  '2': [
    {
      '1': 'state',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.FaceConsentState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `SetFaceConsentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setFaceConsentResponseDescriptor =
    $convert.base64Decode(
        'ChZTZXRGYWNlQ29uc2VudFJlc3BvbnNlEjcKBXN0YXRlGAEgASgLMiEucGhvdG9saWIuYXBpLn'
        'YxLkZhY2VDb25zZW50U3RhdGVSBXN0YXRl');

@$core.Deprecated('Use listFacesRequestDescriptor instead')
const ListFacesRequest$json = {
  '1': 'ListFacesRequest',
  '2': [
    {'1': 'asset_id', '3': 1, '4': 1, '5': 9, '10': 'assetId'},
  ],
};

/// Descriptor for `ListFacesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listFacesRequestDescriptor = $convert.base64Decode(
    'ChBMaXN0RmFjZXNSZXF1ZXN0EhkKCGFzc2V0X2lkGAEgASgJUgdhc3NldElk');

@$core.Deprecated('Use assetFaceDescriptor instead')
const AssetFace$json = {
  '1': 'AssetFace',
  '2': [
    {'1': 'face_id', '3': 1, '4': 1, '5': 9, '10': 'faceId'},
    {'1': 'x', '3': 2, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 3, '4': 1, '5': 2, '10': 'y'},
    {'1': 'width', '3': 4, '4': 1, '5': 2, '10': 'width'},
    {'1': 'height', '3': 5, '4': 1, '5': 2, '10': 'height'},
    {'1': 'landmarks', '3': 6, '4': 3, '5': 2, '10': 'landmarks'},
    {'1': 'score', '3': 7, '4': 1, '5': 2, '10': 'score'},
    {
      '1': 'time_ms',
      '3': 8,
      '4': 1,
      '5': 13,
      '9': 0,
      '10': 'timeMs',
      '17': true
    },
    {'1': 'model_id', '3': 9, '4': 1, '5': 9, '10': 'modelId'},
  ],
  '8': [
    {'1': '_time_ms'},
  ],
};

/// Descriptor for `AssetFace`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List assetFaceDescriptor = $convert.base64Decode(
    'CglBc3NldEZhY2USFwoHZmFjZV9pZBgBIAEoCVIGZmFjZUlkEgwKAXgYAiABKAJSAXgSDAoBeR'
    'gDIAEoAlIBeRIUCgV3aWR0aBgEIAEoAlIFd2lkdGgSFgoGaGVpZ2h0GAUgASgCUgZoZWlnaHQS'
    'HAoJbGFuZG1hcmtzGAYgAygCUglsYW5kbWFya3MSFAoFc2NvcmUYByABKAJSBXNjb3JlEhwKB3'
    'RpbWVfbXMYCCABKA1IAFIGdGltZU1ziAEBEhkKCG1vZGVsX2lkGAkgASgJUgdtb2RlbElkQgoK'
    'CF90aW1lX21z');

@$core.Deprecated('Use listFacesResponseDescriptor instead')
const ListFacesResponse$json = {
  '1': 'ListFacesResponse',
  '2': [
    {
      '1': 'faces',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.AssetFace',
      '10': 'faces'
    },
  ],
};

/// Descriptor for `ListFacesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listFacesResponseDescriptor = $convert.base64Decode(
    'ChFMaXN0RmFjZXNSZXNwb25zZRIwCgVmYWNlcxgBIAMoCzIaLnBob3RvbGliLmFwaS52MS5Bc3'
    'NldEZhY2VSBWZhY2Vz');

const $core.Map<$core.String, $core.dynamic> FaceServiceBase$json = {
  '1': 'FaceService',
  '2': [
    {
      '1': 'GetFaceConsent',
      '2': '.photolib.api.v1.GetFaceConsentRequest',
      '3': '.photolib.api.v1.GetFaceConsentResponse'
    },
    {
      '1': 'SetFaceConsent',
      '2': '.photolib.api.v1.SetFaceConsentRequest',
      '3': '.photolib.api.v1.SetFaceConsentResponse'
    },
    {
      '1': 'ListFaces',
      '2': '.photolib.api.v1.ListFacesRequest',
      '3': '.photolib.api.v1.ListFacesResponse'
    },
  ],
};

@$core.Deprecated('Use faceServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    FaceServiceBase$messageJson = {
  '.photolib.api.v1.GetFaceConsentRequest': GetFaceConsentRequest$json,
  '.photolib.api.v1.GetFaceConsentResponse': GetFaceConsentResponse$json,
  '.photolib.api.v1.FaceConsentState': FaceConsentState$json,
  '.google.protobuf.Timestamp': $0.Timestamp$json,
  '.photolib.api.v1.SetFaceConsentRequest': SetFaceConsentRequest$json,
  '.photolib.api.v1.SetFaceConsentResponse': SetFaceConsentResponse$json,
  '.photolib.api.v1.ListFacesRequest': ListFacesRequest$json,
  '.photolib.api.v1.ListFacesResponse': ListFacesResponse$json,
  '.photolib.api.v1.AssetFace': AssetFace$json,
};

/// Descriptor for `FaceService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List faceServiceDescriptor = $convert.base64Decode(
    'CgtGYWNlU2VydmljZRJhCg5HZXRGYWNlQ29uc2VudBImLnBob3RvbGliLmFwaS52MS5HZXRGYW'
    'NlQ29uc2VudFJlcXVlc3QaJy5waG90b2xpYi5hcGkudjEuR2V0RmFjZUNvbnNlbnRSZXNwb25z'
    'ZRJhCg5TZXRGYWNlQ29uc2VudBImLnBob3RvbGliLmFwaS52MS5TZXRGYWNlQ29uc2VudFJlcX'
    'Vlc3QaJy5waG90b2xpYi5hcGkudjEuU2V0RmFjZUNvbnNlbnRSZXNwb25zZRJSCglMaXN0RmFj'
    'ZXMSIS5waG90b2xpYi5hcGkudjEuTGlzdEZhY2VzUmVxdWVzdBoiLnBob3RvbGliLmFwaS52MS'
    '5MaXN0RmFjZXNSZXNwb25zZQ==');
