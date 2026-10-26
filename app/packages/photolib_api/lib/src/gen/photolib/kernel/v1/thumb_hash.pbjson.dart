// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/thumb_hash.proto.

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

@$core.Deprecated('Use encodeThumbHashRequestDescriptor instead')
const EncodeThumbHashRequest$json = {
  '1': 'EncodeThumbHashRequest',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {'1': 'rgba', '3': 3, '4': 1, '5': 12, '10': 'rgba'},
  ],
};

/// Descriptor for `EncodeThumbHashRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List encodeThumbHashRequestDescriptor =
    $convert.base64Decode(
        'ChZFbmNvZGVUaHVtYkhhc2hSZXF1ZXN0EhQKBXdpZHRoGAEgASgNUgV3aWR0aBIWCgZoZWlnaH'
        'QYAiABKA1SBmhlaWdodBISCgRyZ2JhGAMgASgMUgRyZ2Jh');

@$core.Deprecated('Use encodeThumbHashResponseDescriptor instead')
const EncodeThumbHashResponse$json = {
  '1': 'EncodeThumbHashResponse',
  '2': [
    {'1': 'hash', '3': 1, '4': 1, '5': 12, '10': 'hash'},
  ],
};

/// Descriptor for `EncodeThumbHashResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List encodeThumbHashResponseDescriptor =
    $convert.base64Decode(
        'ChdFbmNvZGVUaHVtYkhhc2hSZXNwb25zZRISCgRoYXNoGAEgASgMUgRoYXNo');
