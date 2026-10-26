// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/faces.proto.

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

@$core.Deprecated('Use faceDescriptor instead')
const Face$json = {
  '1': 'Face',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 2, '10': 'y'},
    {'1': 'width', '3': 3, '4': 1, '5': 2, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 2, '10': 'height'},
    {'1': 'landmarks', '3': 5, '4': 3, '5': 2, '10': 'landmarks'},
    {'1': 'score', '3': 6, '4': 1, '5': 2, '10': 'score'},
  ],
};

/// Descriptor for `Face`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List faceDescriptor = $convert.base64Decode(
    'CgRGYWNlEgwKAXgYASABKAJSAXgSDAoBeRgCIAEoAlIBeRIUCgV3aWR0aBgDIAEoAlIFd2lkdG'
    'gSFgoGaGVpZ2h0GAQgASgCUgZoZWlnaHQSHAoJbGFuZG1hcmtzGAUgAygCUglsYW5kbWFya3MS'
    'FAoFc2NvcmUYBiABKAJSBXNjb3Jl');

@$core.Deprecated('Use prepareFaceDetectionRequestDescriptor instead')
const PrepareFaceDetectionRequest$json = {
  '1': 'PrepareFaceDetectionRequest',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {'1': 'rgba', '3': 3, '4': 1, '5': 12, '10': 'rgba'},
    {'1': 'max_side', '3': 4, '4': 1, '5': 13, '10': 'maxSide'},
  ],
};

/// Descriptor for `PrepareFaceDetectionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareFaceDetectionRequestDescriptor =
    $convert.base64Decode(
        'ChtQcmVwYXJlRmFjZURldGVjdGlvblJlcXVlc3QSFAoFd2lkdGgYASABKA1SBXdpZHRoEhYKBm'
        'hlaWdodBgCIAEoDVIGaGVpZ2h0EhIKBHJnYmEYAyABKAxSBHJnYmESGQoIbWF4X3NpZGUYBCAB'
        'KA1SB21heFNpZGU=');

@$core.Deprecated('Use prepareFaceDetectionResponseDescriptor instead')
const PrepareFaceDetectionResponse$json = {
  '1': 'PrepareFaceDetectionResponse',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {'1': 'tensor', '3': 3, '4': 1, '5': 12, '10': 'tensor'},
  ],
};

/// Descriptor for `PrepareFaceDetectionResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareFaceDetectionResponseDescriptor =
    $convert.base64Decode(
        'ChxQcmVwYXJlRmFjZURldGVjdGlvblJlc3BvbnNlEhQKBXdpZHRoGAEgASgNUgV3aWR0aBIWCg'
        'ZoZWlnaHQYAiABKA1SBmhlaWdodBIWCgZ0ZW5zb3IYAyABKAxSBnRlbnNvcg==');

@$core.Deprecated('Use decodeFacesRequestDescriptor instead')
const DecodeFacesRequest$json = {
  '1': 'DecodeFacesRequest',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {'1': 'outputs', '3': 3, '4': 3, '5': 12, '10': 'outputs'},
    {'1': 'min_score', '3': 4, '4': 1, '5': 2, '10': 'minScore'},
    {'1': 'max_overlap', '3': 5, '4': 1, '5': 2, '10': 'maxOverlap'},
    {'1': 'max_faces', '3': 6, '4': 1, '5': 13, '10': 'maxFaces'},
  ],
};

/// Descriptor for `DecodeFacesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List decodeFacesRequestDescriptor = $convert.base64Decode(
    'ChJEZWNvZGVGYWNlc1JlcXVlc3QSFAoFd2lkdGgYASABKA1SBXdpZHRoEhYKBmhlaWdodBgCIA'
    'EoDVIGaGVpZ2h0EhgKB291dHB1dHMYAyADKAxSB291dHB1dHMSGwoJbWluX3Njb3JlGAQgASgC'
    'UghtaW5TY29yZRIfCgttYXhfb3ZlcmxhcBgFIAEoAlIKbWF4T3ZlcmxhcBIbCgltYXhfZmFjZX'
    'MYBiABKA1SCG1heEZhY2Vz');

@$core.Deprecated('Use decodeFacesResponseDescriptor instead')
const DecodeFacesResponse$json = {
  '1': 'DecodeFacesResponse',
  '2': [
    {
      '1': 'faces',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Face',
      '10': 'faces'
    },
  ],
};

/// Descriptor for `DecodeFacesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List decodeFacesResponseDescriptor = $convert.base64Decode(
    'ChNEZWNvZGVGYWNlc1Jlc3BvbnNlEi4KBWZhY2VzGAEgAygLMhgucGhvdG9saWIua2VybmVsLn'
    'YxLkZhY2VSBWZhY2Vz');

@$core.Deprecated('Use alignFaceRequestDescriptor instead')
const AlignFaceRequest$json = {
  '1': 'AlignFaceRequest',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {'1': 'rgba', '3': 3, '4': 1, '5': 12, '10': 'rgba'},
    {'1': 'landmarks', '3': 4, '4': 3, '5': 2, '10': 'landmarks'},
    {'1': 'mean', '3': 5, '4': 3, '5': 2, '10': 'mean'},
    {'1': 'std', '3': 6, '4': 3, '5': 2, '10': 'std'},
  ],
};

/// Descriptor for `AlignFaceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List alignFaceRequestDescriptor = $convert.base64Decode(
    'ChBBbGlnbkZhY2VSZXF1ZXN0EhQKBXdpZHRoGAEgASgNUgV3aWR0aBIWCgZoZWlnaHQYAiABKA'
    '1SBmhlaWdodBISCgRyZ2JhGAMgASgMUgRyZ2JhEhwKCWxhbmRtYXJrcxgEIAMoAlIJbGFuZG1h'
    'cmtzEhIKBG1lYW4YBSADKAJSBG1lYW4SEAoDc3RkGAYgAygCUgNzdGQ=');

@$core.Deprecated('Use alignFaceResponseDescriptor instead')
const AlignFaceResponse$json = {
  '1': 'AlignFaceResponse',
  '2': [
    {'1': 'tensor', '3': 1, '4': 1, '5': 12, '10': 'tensor'},
  ],
};

/// Descriptor for `AlignFaceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List alignFaceResponseDescriptor = $convert.base64Decode(
    'ChFBbGlnbkZhY2VSZXNwb25zZRIWCgZ0ZW5zb3IYASABKAxSBnRlbnNvcg==');

@$core.Deprecated('Use normalizeFaceEmbeddingRequestDescriptor instead')
const NormalizeFaceEmbeddingRequest$json = {
  '1': 'NormalizeFaceEmbeddingRequest',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 2, '10': 'values'},
  ],
};

/// Descriptor for `NormalizeFaceEmbeddingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List normalizeFaceEmbeddingRequestDescriptor =
    $convert.base64Decode(
        'Ch1Ob3JtYWxpemVGYWNlRW1iZWRkaW5nUmVxdWVzdBIWCgZ2YWx1ZXMYASADKAJSBnZhbHVlcw'
        '==');

@$core.Deprecated('Use normalizeFaceEmbeddingResponseDescriptor instead')
const NormalizeFaceEmbeddingResponse$json = {
  '1': 'NormalizeFaceEmbeddingResponse',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 2, '10': 'values'},
  ],
};

/// Descriptor for `NormalizeFaceEmbeddingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List normalizeFaceEmbeddingResponseDescriptor =
    $convert.base64Decode(
        'Ch5Ob3JtYWxpemVGYWNlRW1iZWRkaW5nUmVzcG9uc2USFgoGdmFsdWVzGAEgAygCUgZ2YWx1ZX'
        'M=');

@$core.Deprecated('Use mapFacesRequestDescriptor instead')
const MapFacesRequest$json = {
  '1': 'MapFacesRequest',
  '2': [
    {
      '1': 'faces',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Face',
      '10': 'faces'
    },
    {'1': 'width', '3': 2, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 3, '4': 1, '5': 13, '10': 'height'},
    {
      '1': 'edit',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Develop',
      '10': 'edit'
    },
    {'1': 'to_original', '3': 5, '4': 1, '5': 8, '10': 'toOriginal'},
  ],
};

/// Descriptor for `MapFacesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapFacesRequestDescriptor = $convert.base64Decode(
    'Cg9NYXBGYWNlc1JlcXVlc3QSLgoFZmFjZXMYASADKAsyGC5waG90b2xpYi5rZXJuZWwudjEuRm'
    'FjZVIFZmFjZXMSFAoFd2lkdGgYAiABKA1SBXdpZHRoEhYKBmhlaWdodBgDIAEoDVIGaGVpZ2h0'
    'Ei8KBGVkaXQYBCABKAsyGy5waG90b2xpYi5rZXJuZWwudjEuRGV2ZWxvcFIEZWRpdBIfCgt0b1'
    '9vcmlnaW5hbBgFIAEoCFIKdG9PcmlnaW5hbA==');

@$core.Deprecated('Use mapFacesResponseDescriptor instead')
const MapFacesResponse$json = {
  '1': 'MapFacesResponse',
  '2': [
    {
      '1': 'faces',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Face',
      '10': 'faces'
    },
    {'1': 'visible', '3': 2, '4': 3, '5': 8, '10': 'visible'},
  ],
};

/// Descriptor for `MapFacesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapFacesResponseDescriptor = $convert.base64Decode(
    'ChBNYXBGYWNlc1Jlc3BvbnNlEi4KBWZhY2VzGAEgAygLMhgucGhvdG9saWIua2VybmVsLnYxLk'
    'ZhY2VSBWZhY2VzEhgKB3Zpc2libGUYAiADKAhSB3Zpc2libGU=');
