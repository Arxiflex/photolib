// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/live_photo.proto.

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

@$core.Deprecated('Use pairLivePhotosRequestDescriptor instead')
const PairLivePhotosRequest$json = {
  '1': 'PairLivePhotosRequest',
  '2': [
    {
      '1': 'files',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.LivePhotoPart',
      '10': 'files'
    },
  ],
};

/// Descriptor for `PairLivePhotosRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairLivePhotosRequestDescriptor = $convert.base64Decode(
    'ChVQYWlyTGl2ZVBob3Rvc1JlcXVlc3QSNwoFZmlsZXMYASADKAsyIS5waG90b2xpYi5rZXJuZW'
    'wudjEuTGl2ZVBob3RvUGFydFIFZmlsZXM=');

@$core.Deprecated('Use livePhotoPartDescriptor instead')
const LivePhotoPart$json = {
  '1': 'LivePhotoPart',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'video', '3': 2, '4': 1, '5': 8, '10': 'video'},
    {
      '1': 'content_identifier',
      '3': 3,
      '4': 1,
      '5': 9,
      '10': 'contentIdentifier'
    },
    {
      '1': 'captured_ms',
      '3': 4,
      '4': 1,
      '5': 3,
      '9': 0,
      '10': 'capturedMs',
      '17': true
    },
    {'1': 'duration_ms', '3': 5, '4': 1, '5': 4, '10': 'durationMs'},
  ],
  '8': [
    {'1': '_captured_ms'},
  ],
};

/// Descriptor for `LivePhotoPart`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List livePhotoPartDescriptor = $convert.base64Decode(
    'Cg1MaXZlUGhvdG9QYXJ0EhIKBHBhdGgYASABKAlSBHBhdGgSFAoFdmlkZW8YAiABKAhSBXZpZG'
    'VvEi0KEmNvbnRlbnRfaWRlbnRpZmllchgDIAEoCVIRY29udGVudElkZW50aWZpZXISJAoLY2Fw'
    'dHVyZWRfbXMYBCABKANIAFIKY2FwdHVyZWRNc4gBARIfCgtkdXJhdGlvbl9tcxgFIAEoBFIKZH'
    'VyYXRpb25Nc0IOCgxfY2FwdHVyZWRfbXM=');

@$core.Deprecated('Use pairLivePhotosResponseDescriptor instead')
const PairLivePhotosResponse$json = {
  '1': 'PairLivePhotosResponse',
  '2': [
    {
      '1': 'pairs',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.LivePhotoPair',
      '10': 'pairs'
    },
  ],
};

/// Descriptor for `PairLivePhotosResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pairLivePhotosResponseDescriptor =
    $convert.base64Decode(
        'ChZQYWlyTGl2ZVBob3Rvc1Jlc3BvbnNlEjcKBXBhaXJzGAEgAygLMiEucGhvdG9saWIua2Vybm'
        'VsLnYxLkxpdmVQaG90b1BhaXJSBXBhaXJz');

@$core.Deprecated('Use livePhotoPairDescriptor instead')
const LivePhotoPair$json = {
  '1': 'LivePhotoPair',
  '2': [
    {'1': 'still', '3': 1, '4': 1, '5': 13, '10': 'still'},
    {'1': 'video', '3': 2, '4': 1, '5': 13, '10': 'video'},
  ],
};

/// Descriptor for `LivePhotoPair`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List livePhotoPairDescriptor = $convert.base64Decode(
    'Cg1MaXZlUGhvdG9QYWlyEhQKBXN0aWxsGAEgASgNUgVzdGlsbBIUCgV2aWRlbxgCIAEoDVIFdm'
    'lkZW8=');
