// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/ml.proto.

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

@$core.Deprecated('Use prepareImageRequestDescriptor instead')
const PrepareImageRequest$json = {
  '1': 'PrepareImageRequest',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {'1': 'rgba', '3': 3, '4': 1, '5': 12, '10': 'rgba'},
    {'1': 'size', '3': 4, '4': 1, '5': 13, '10': 'size'},
    {'1': 'mean', '3': 5, '4': 3, '5': 2, '10': 'mean'},
    {'1': 'std', '3': 6, '4': 3, '5': 2, '10': 'std'},
    {'1': 'crop', '3': 7, '4': 1, '5': 8, '10': 'crop'},
  ],
};

/// Descriptor for `PrepareImageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareImageRequestDescriptor = $convert.base64Decode(
    'ChNQcmVwYXJlSW1hZ2VSZXF1ZXN0EhQKBXdpZHRoGAEgASgNUgV3aWR0aBIWCgZoZWlnaHQYAi'
    'ABKA1SBmhlaWdodBISCgRyZ2JhGAMgASgMUgRyZ2JhEhIKBHNpemUYBCABKA1SBHNpemUSEgoE'
    'bWVhbhgFIAMoAlIEbWVhbhIQCgNzdGQYBiADKAJSA3N0ZBISCgRjcm9wGAcgASgIUgRjcm9w');

@$core.Deprecated('Use prepareImageResponseDescriptor instead')
const PrepareImageResponse$json = {
  '1': 'PrepareImageResponse',
  '2': [
    {'1': 'tensor', '3': 1, '4': 1, '5': 12, '10': 'tensor'},
  ],
};

/// Descriptor for `PrepareImageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prepareImageResponseDescriptor =
    $convert.base64Decode(
        'ChRQcmVwYXJlSW1hZ2VSZXNwb25zZRIWCgZ0ZW5zb3IYASABKAxSBnRlbnNvcg==');
