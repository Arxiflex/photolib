// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/heif.proto.

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

@$core.Deprecated('Use heifStatusDescriptor instead')
const HeifStatus$json = {
  '1': 'HeifStatus',
  '2': [
    {'1': 'HEIF_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'HEIF_STATUS_OK', '2': 1},
    {'1': 'HEIF_STATUS_NOT_HEIF', '2': 2},
    {'1': 'HEIF_STATUS_UNSUPPORTED_CODEC', '2': 3},
    {'1': 'HEIF_STATUS_NO_CONFIG', '2': 4},
  ],
};

/// Descriptor for `HeifStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List heifStatusDescriptor = $convert.base64Decode(
    'CgpIZWlmU3RhdHVzEhsKF0hFSUZfU1RBVFVTX1VOU1BFQ0lGSUVEEAASEgoOSEVJRl9TVEFUVV'
    'NfT0sQARIYChRIRUlGX1NUQVRVU19OT1RfSEVJRhACEiEKHUhFSUZfU1RBVFVTX1VOU1VQUE9S'
    'VEVEX0NPREVDEAMSGQoVSEVJRl9TVEFUVVNfTk9fQ09ORklHEAQ=');

@$core.Deprecated('Use heifCodecDescriptor instead')
const HeifCodec$json = {
  '1': 'HeifCodec',
  '2': [
    {'1': 'HEIF_CODEC_UNSPECIFIED', '2': 0},
    {'1': 'HEIF_CODEC_HEVC', '2': 1},
    {'1': 'HEIF_CODEC_AV1', '2': 2},
    {'1': 'HEIF_CODEC_AVC', '2': 3},
  ],
};

/// Descriptor for `HeifCodec`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List heifCodecDescriptor = $convert.base64Decode(
    'CglIZWlmQ29kZWMSGgoWSEVJRl9DT0RFQ19VTlNQRUNJRklFRBAAEhMKD0hFSUZfQ09ERUNfSE'
    'VWQxABEhIKDkhFSUZfQ09ERUNfQVYxEAISEgoOSEVJRl9DT0RFQ19BVkMQAw==');

@$core.Deprecated('Use readHeifRequestDescriptor instead')
const ReadHeifRequest$json = {
  '1': 'ReadHeifRequest',
  '2': [
    {
      '1': 'ranges',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.FileRange',
      '10': 'ranges'
    },
    {'1': 'size', '3': 2, '4': 1, '5': 4, '10': 'size'},
  ],
};

/// Descriptor for `ReadHeifRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readHeifRequestDescriptor = $convert.base64Decode(
    'Cg9SZWFkSGVpZlJlcXVlc3QSNQoGcmFuZ2VzGAEgAygLMh0ucGhvdG9saWIua2VybmVsLnYxLk'
    'ZpbGVSYW5nZVIGcmFuZ2VzEhIKBHNpemUYAiABKARSBHNpemU=');

@$core.Deprecated('Use readHeifResponseDescriptor instead')
const ReadHeifResponse$json = {
  '1': 'ReadHeifResponse',
  '2': [
    {
      '1': 'missing',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.ByteSpan',
      '10': 'missing'
    },
    {
      '1': 'status',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.HeifStatus',
      '10': 'status'
    },
    {'1': 'item_type', '3': 3, '4': 1, '5': 9, '10': 'itemType'},
    {
      '1': 'picture',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.HeifPicture',
      '10': 'picture'
    },
    {
      '1': 'thumbnail',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.HeifPicture',
      '9': 0,
      '10': 'thumbnail',
      '17': true
    },
  ],
  '8': [
    {'1': '_thumbnail'},
  ],
};

/// Descriptor for `ReadHeifResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readHeifResponseDescriptor = $convert.base64Decode(
    'ChBSZWFkSGVpZlJlc3BvbnNlEjYKB21pc3NpbmcYASADKAsyHC5waG90b2xpYi5rZXJuZWwudj'
    'EuQnl0ZVNwYW5SB21pc3NpbmcSNgoGc3RhdHVzGAIgASgOMh4ucGhvdG9saWIua2VybmVsLnYx'
    'LkhlaWZTdGF0dXNSBnN0YXR1cxIbCglpdGVtX3R5cGUYAyABKAlSCGl0ZW1UeXBlEjkKB3BpY3'
    'R1cmUYBCABKAsyHy5waG90b2xpYi5rZXJuZWwudjEuSGVpZlBpY3R1cmVSB3BpY3R1cmUSQgoJ'
    'dGh1bWJuYWlsGAUgASgLMh8ucGhvdG9saWIua2VybmVsLnYxLkhlaWZQaWN0dXJlSABSCXRodW'
    '1ibmFpbIgBAUIMCgpfdGh1bWJuYWls');

@$core.Deprecated('Use heifPictureDescriptor instead')
const HeifPicture$json = {
  '1': 'HeifPicture',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {
      '1': 'image',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.HeifImage',
      '9': 0,
      '10': 'image',
      '17': true
    },
    {'1': 'rows', '3': 4, '4': 1, '5': 13, '10': 'rows'},
    {'1': 'columns', '3': 5, '4': 1, '5': 13, '10': 'columns'},
    {
      '1': 'tiles',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.HeifImage',
      '10': 'tiles'
    },
    {
      '1': 'clap',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.HeifClap',
      '9': 1,
      '10': 'clap',
      '17': true
    },
    {'1': 'rotation', '3': 8, '4': 1, '5': 13, '10': 'rotation'},
    {
      '1': 'mirror',
      '3': 9,
      '4': 1,
      '5': 13,
      '9': 2,
      '10': 'mirror',
      '17': true
    },
  ],
  '8': [
    {'1': '_image'},
    {'1': '_clap'},
    {'1': '_mirror'},
  ],
};

/// Descriptor for `HeifPicture`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heifPictureDescriptor = $convert.base64Decode(
    'CgtIZWlmUGljdHVyZRIUCgV3aWR0aBgBIAEoDVIFd2lkdGgSFgoGaGVpZ2h0GAIgASgNUgZoZW'
    'lnaHQSOAoFaW1hZ2UYAyABKAsyHS5waG90b2xpYi5rZXJuZWwudjEuSGVpZkltYWdlSABSBWlt'
    'YWdliAEBEhIKBHJvd3MYBCABKA1SBHJvd3MSGAoHY29sdW1ucxgFIAEoDVIHY29sdW1ucxIzCg'
    'V0aWxlcxgGIAMoCzIdLnBob3RvbGliLmtlcm5lbC52MS5IZWlmSW1hZ2VSBXRpbGVzEjUKBGNs'
    'YXAYByABKAsyHC5waG90b2xpYi5rZXJuZWwudjEuSGVpZkNsYXBIAVIEY2xhcIgBARIaCghyb3'
    'RhdGlvbhgIIAEoDVIIcm90YXRpb24SGwoGbWlycm9yGAkgASgNSAJSBm1pcnJvcogBAUIICgZf'
    'aW1hZ2VCBwoFX2NsYXBCCQoHX21pcnJvcg==');

@$core.Deprecated('Use heifImageDescriptor instead')
const HeifImage$json = {
  '1': 'HeifImage',
  '2': [
    {
      '1': 'codec',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.HeifCodec',
      '10': 'codec'
    },
    {'1': 'codec_string', '3': 2, '4': 1, '5': 9, '10': 'codecString'},
    {'1': 'config', '3': 3, '4': 1, '5': 12, '10': 'config'},
    {'1': 'width', '3': 4, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 5, '4': 1, '5': 13, '10': 'height'},
    {
      '1': 'spans',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.ByteSpan',
      '10': 'spans'
    },
  ],
};

/// Descriptor for `HeifImage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heifImageDescriptor = $convert.base64Decode(
    'CglIZWlmSW1hZ2USMwoFY29kZWMYASABKA4yHS5waG90b2xpYi5rZXJuZWwudjEuSGVpZkNvZG'
    'VjUgVjb2RlYxIhCgxjb2RlY19zdHJpbmcYAiABKAlSC2NvZGVjU3RyaW5nEhYKBmNvbmZpZxgD'
    'IAEoDFIGY29uZmlnEhQKBXdpZHRoGAQgASgNUgV3aWR0aBIWCgZoZWlnaHQYBSABKA1SBmhlaW'
    'dodBIyCgVzcGFucxgGIAMoCzIcLnBob3RvbGliLmtlcm5lbC52MS5CeXRlU3BhblIFc3BhbnM=');

@$core.Deprecated('Use heifClapDescriptor instead')
const HeifClap$json = {
  '1': 'HeifClap',
  '2': [
    {'1': 'width_num', '3': 1, '4': 1, '5': 13, '10': 'widthNum'},
    {'1': 'width_den', '3': 2, '4': 1, '5': 13, '10': 'widthDen'},
    {'1': 'height_num', '3': 3, '4': 1, '5': 13, '10': 'heightNum'},
    {'1': 'height_den', '3': 4, '4': 1, '5': 13, '10': 'heightDen'},
    {'1': 'x_num', '3': 5, '4': 1, '5': 5, '10': 'xNum'},
    {'1': 'x_den', '3': 6, '4': 1, '5': 13, '10': 'xDen'},
    {'1': 'y_num', '3': 7, '4': 1, '5': 5, '10': 'yNum'},
    {'1': 'y_den', '3': 8, '4': 1, '5': 13, '10': 'yDen'},
  ],
};

/// Descriptor for `HeifClap`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heifClapDescriptor = $convert.base64Decode(
    'CghIZWlmQ2xhcBIbCgl3aWR0aF9udW0YASABKA1SCHdpZHRoTnVtEhsKCXdpZHRoX2RlbhgCIA'
    'EoDVIId2lkdGhEZW4SHQoKaGVpZ2h0X251bRgDIAEoDVIJaGVpZ2h0TnVtEh0KCmhlaWdodF9k'
    'ZW4YBCABKA1SCWhlaWdodERlbhITCgV4X251bRgFIAEoBVIEeE51bRITCgV4X2RlbhgGIAEoDV'
    'IEeERlbhITCgV5X251bRgHIAEoBVIEeU51bRITCgV5X2RlbhgIIAEoDVIEeURlbg==');
