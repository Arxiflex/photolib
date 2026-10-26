// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/map.proto.

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

@$core.Deprecated('Use mapIndexBuildRequestDescriptor instead')
const MapIndexBuildRequest$json = {
  '1': 'MapIndexBuildRequest',
  '2': [
    {
      '1': 'latitudes',
      '3': 1,
      '4': 3,
      '5': 1,
      '8': {'2': true},
      '10': 'latitudes',
    },
    {
      '1': 'longitudes',
      '3': 2,
      '4': 3,
      '5': 1,
      '8': {'2': true},
      '10': 'longitudes',
    },
    {
      '1': 'times',
      '3': 3,
      '4': 3,
      '5': 18,
      '8': {'2': true},
      '10': 'times',
    },
  ],
};

/// Descriptor for `MapIndexBuildRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapIndexBuildRequestDescriptor = $convert.base64Decode(
    'ChRNYXBJbmRleEJ1aWxkUmVxdWVzdBIgCglsYXRpdHVkZXMYASADKAFCAhABUglsYXRpdHVkZX'
    'MSIgoKbG9uZ2l0dWRlcxgCIAMoAUICEAFSCmxvbmdpdHVkZXMSGAoFdGltZXMYAyADKBJCAhAB'
    'UgV0aW1lcw==');

@$core.Deprecated('Use mapIndexBuildResponseDescriptor instead')
const MapIndexBuildResponse$json = {
  '1': 'MapIndexBuildResponse',
  '2': [
    {'1': 'index', '3': 1, '4': 1, '5': 13, '10': 'index'},
    {'1': 'mapped', '3': 2, '4': 1, '5': 13, '10': 'mapped'},
  ],
};

/// Descriptor for `MapIndexBuildResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapIndexBuildResponseDescriptor = $convert.base64Decode(
    'ChVNYXBJbmRleEJ1aWxkUmVzcG9uc2USFAoFaW5kZXgYASABKA1SBWluZGV4EhYKBm1hcHBlZB'
    'gCIAEoDVIGbWFwcGVk');

@$core.Deprecated('Use mapFilterDescriptor instead')
const MapFilter$json = {
  '1': 'MapFilter',
  '2': [
    {
      '1': 'time_from',
      '3': 1,
      '4': 1,
      '5': 18,
      '9': 0,
      '10': 'timeFrom',
      '17': true
    },
    {
      '1': 'time_to',
      '3': 2,
      '4': 1,
      '5': 18,
      '9': 1,
      '10': 'timeTo',
      '17': true
    },
    {
      '1': 'polygon',
      '3': 3,
      '4': 3,
      '5': 1,
      '8': {'2': true},
      '10': 'polygon',
    },
  ],
  '8': [
    {'1': '_time_from'},
    {'1': '_time_to'},
  ],
};

/// Descriptor for `MapFilter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapFilterDescriptor = $convert.base64Decode(
    'CglNYXBGaWx0ZXISIAoJdGltZV9mcm9tGAEgASgSSABSCHRpbWVGcm9tiAEBEhwKB3RpbWVfdG'
    '8YAiABKBJIAVIGdGltZVRviAEBEhwKB3BvbHlnb24YAyADKAFCAhABUgdwb2x5Z29uQgwKCl90'
    'aW1lX2Zyb21CCgoIX3RpbWVfdG8=');

@$core.Deprecated('Use mapQueryRequestDescriptor instead')
const MapQueryRequest$json = {
  '1': 'MapQueryRequest',
  '2': [
    {'1': 'index', '3': 1, '4': 1, '5': 13, '10': 'index'},
    {'1': 'west', '3': 2, '4': 1, '5': 1, '10': 'west'},
    {'1': 'south', '3': 3, '4': 1, '5': 1, '10': 'south'},
    {'1': 'east', '3': 4, '4': 1, '5': 1, '10': 'east'},
    {'1': 'north', '3': 5, '4': 1, '5': 1, '10': 'north'},
    {'1': 'zoom', '3': 6, '4': 1, '5': 13, '10': 'zoom'},
    {
      '1': 'filter',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.MapFilter',
      '10': 'filter'
    },
  ],
};

/// Descriptor for `MapQueryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapQueryRequestDescriptor = $convert.base64Decode(
    'Cg9NYXBRdWVyeVJlcXVlc3QSFAoFaW5kZXgYASABKA1SBWluZGV4EhIKBHdlc3QYAiABKAFSBH'
    'dlc3QSFAoFc291dGgYAyABKAFSBXNvdXRoEhIKBGVhc3QYBCABKAFSBGVhc3QSFAoFbm9ydGgY'
    'BSABKAFSBW5vcnRoEhIKBHpvb20YBiABKA1SBHpvb20SNQoGZmlsdGVyGAcgASgLMh0ucGhvdG'
    '9saWIua2VybmVsLnYxLk1hcEZpbHRlclIGZmlsdGVy');

@$core.Deprecated('Use mapQueryResponseDescriptor instead')
const MapQueryResponse$json = {
  '1': 'MapQueryResponse',
  '2': [
    {
      '1': 'clusters',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.MapCluster',
      '10': 'clusters'
    },
  ],
};

/// Descriptor for `MapQueryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapQueryResponseDescriptor = $convert.base64Decode(
    'ChBNYXBRdWVyeVJlc3BvbnNlEjoKCGNsdXN0ZXJzGAEgAygLMh4ucGhvdG9saWIua2VybmVsLn'
    'YxLk1hcENsdXN0ZXJSCGNsdXN0ZXJz');

@$core.Deprecated('Use mapClusterDescriptor instead')
const MapCluster$json = {
  '1': 'MapCluster',
  '2': [
    {'1': 'latitude', '3': 1, '4': 1, '5': 1, '10': 'latitude'},
    {'1': 'longitude', '3': 2, '4': 1, '5': 1, '10': 'longitude'},
    {'1': 'count', '3': 3, '4': 1, '5': 13, '10': 'count'},
    {'1': 'asset', '3': 4, '4': 1, '5': 13, '9': 0, '10': 'asset', '17': true},
  ],
  '8': [
    {'1': '_asset'},
  ],
};

/// Descriptor for `MapCluster`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapClusterDescriptor = $convert.base64Decode(
    'CgpNYXBDbHVzdGVyEhoKCGxhdGl0dWRlGAEgASgBUghsYXRpdHVkZRIcCglsb25naXR1ZGUYAi'
    'ABKAFSCWxvbmdpdHVkZRIUCgVjb3VudBgDIAEoDVIFY291bnQSGQoFYXNzZXQYBCABKA1IAFIF'
    'YXNzZXSIAQFCCAoGX2Fzc2V0');

@$core.Deprecated('Use mapAssetsRequestDescriptor instead')
const MapAssetsRequest$json = {
  '1': 'MapAssetsRequest',
  '2': [
    {'1': 'index', '3': 1, '4': 1, '5': 13, '10': 'index'},
    {'1': 'west', '3': 2, '4': 1, '5': 1, '10': 'west'},
    {'1': 'south', '3': 3, '4': 1, '5': 1, '10': 'south'},
    {'1': 'east', '3': 4, '4': 1, '5': 1, '10': 'east'},
    {'1': 'north', '3': 5, '4': 1, '5': 1, '10': 'north'},
    {
      '1': 'filter',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.MapFilter',
      '10': 'filter'
    },
    {'1': 'limit', '3': 7, '4': 1, '5': 13, '10': 'limit'},
  ],
};

/// Descriptor for `MapAssetsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapAssetsRequestDescriptor = $convert.base64Decode(
    'ChBNYXBBc3NldHNSZXF1ZXN0EhQKBWluZGV4GAEgASgNUgVpbmRleBISCgR3ZXN0GAIgASgBUg'
    'R3ZXN0EhQKBXNvdXRoGAMgASgBUgVzb3V0aBISCgRlYXN0GAQgASgBUgRlYXN0EhQKBW5vcnRo'
    'GAUgASgBUgVub3J0aBI1CgZmaWx0ZXIYBiABKAsyHS5waG90b2xpYi5rZXJuZWwudjEuTWFwRm'
    'lsdGVyUgZmaWx0ZXISFAoFbGltaXQYByABKA1SBWxpbWl0');

@$core.Deprecated('Use mapAssetsResponseDescriptor instead')
const MapAssetsResponse$json = {
  '1': 'MapAssetsResponse',
  '2': [
    {
      '1': 'assets',
      '3': 1,
      '4': 3,
      '5': 13,
      '8': {'2': true},
      '10': 'assets',
    },
    {'1': 'total', '3': 2, '4': 1, '5': 13, '10': 'total'},
  ],
};

/// Descriptor for `MapAssetsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapAssetsResponseDescriptor = $convert.base64Decode(
    'ChFNYXBBc3NldHNSZXNwb25zZRIaCgZhc3NldHMYASADKA1CAhABUgZhc3NldHMSFAoFdG90YW'
    'wYAiABKA1SBXRvdGFs');

@$core.Deprecated('Use mapIndexDropRequestDescriptor instead')
const MapIndexDropRequest$json = {
  '1': 'MapIndexDropRequest',
  '2': [
    {'1': 'index', '3': 1, '4': 1, '5': 13, '10': 'index'},
  ],
};

/// Descriptor for `MapIndexDropRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapIndexDropRequestDescriptor =
    $convert.base64Decode(
        'ChNNYXBJbmRleERyb3BSZXF1ZXN0EhQKBWluZGV4GAEgASgNUgVpbmRleA==');

@$core.Deprecated('Use mapIndexDropResponseDescriptor instead')
const MapIndexDropResponse$json = {
  '1': 'MapIndexDropResponse',
};

/// Descriptor for `MapIndexDropResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapIndexDropResponseDescriptor =
    $convert.base64Decode('ChRNYXBJbmRleERyb3BSZXNwb25zZQ==');
