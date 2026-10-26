// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/develop.proto.

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

@$core.Deprecated('Use developRequestDescriptor instead')
const DevelopRequest$json = {
  '1': 'DevelopRequest',
  '2': [
    {
      '1': 'develop',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Develop',
      '10': 'develop'
    },
    {
      '1': 'image',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Image',
      '10': 'image'
    },
    {
      '1': 'gain_map',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.GainMap',
      '10': 'gainMap'
    },
    {
      '1': 'guide',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Guide',
      '10': 'guide'
    },
    {'1': 'full_width', '3': 5, '4': 1, '5': 13, '10': 'fullWidth'},
    {'1': 'full_height', '3': 6, '4': 1, '5': 13, '10': 'fullHeight'},
    {'1': 'tile_x', '3': 7, '4': 1, '5': 13, '10': 'tileX'},
    {'1': 'tile_y', '3': 8, '4': 1, '5': 13, '10': 'tileY'},
  ],
};

/// Descriptor for `DevelopRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List developRequestDescriptor = $convert.base64Decode(
    'Cg5EZXZlbG9wUmVxdWVzdBI1CgdkZXZlbG9wGAEgASgLMhsucGhvdG9saWIua2VybmVsLnYxLk'
    'RldmVsb3BSB2RldmVsb3ASLwoFaW1hZ2UYAiABKAsyGS5waG90b2xpYi5rZXJuZWwudjEuSW1h'
    'Z2VSBWltYWdlEjYKCGdhaW5fbWFwGAMgASgLMhsucGhvdG9saWIua2VybmVsLnYxLkdhaW5NYX'
    'BSB2dhaW5NYXASLwoFZ3VpZGUYBCABKAsyGS5waG90b2xpYi5rZXJuZWwudjEuR3VpZGVSBWd1'
    'aWRlEh0KCmZ1bGxfd2lkdGgYBSABKA1SCWZ1bGxXaWR0aBIfCgtmdWxsX2hlaWdodBgGIAEoDV'
    'IKZnVsbEhlaWdodBIVCgZ0aWxlX3gYByABKA1SBXRpbGVYEhUKBnRpbGVfeRgIIAEoDVIFdGls'
    'ZVk=');

@$core.Deprecated('Use developResponseDescriptor instead')
const DevelopResponse$json = {
  '1': 'DevelopResponse',
  '2': [
    {
      '1': 'image',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Image',
      '10': 'image'
    },
    {
      '1': 'gain_map',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.GainMap',
      '10': 'gainMap'
    },
    {
      '1': 'guide',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Guide',
      '10': 'guide'
    },
  ],
};

/// Descriptor for `DevelopResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List developResponseDescriptor = $convert.base64Decode(
    'Cg9EZXZlbG9wUmVzcG9uc2USLwoFaW1hZ2UYASABKAsyGS5waG90b2xpYi5rZXJuZWwudjEuSW'
    '1hZ2VSBWltYWdlEjYKCGdhaW5fbWFwGAIgASgLMhsucGhvdG9saWIua2VybmVsLnYxLkdhaW5N'
    'YXBSB2dhaW5NYXASLwoFZ3VpZGUYAyABKAsyGS5waG90b2xpYi5rZXJuZWwudjEuR3VpZGVSBW'
    'd1aWRl');

@$core.Deprecated('Use developDescriptor instead')
const Develop$json = {
  '1': 'Develop',
  '2': [
    {'1': 'temperature', '3': 1, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'tint', '3': 2, '4': 1, '5': 2, '10': 'tint'},
    {'1': 'exposure', '3': 3, '4': 1, '5': 2, '10': 'exposure'},
    {'1': 'contrast', '3': 4, '4': 1, '5': 2, '10': 'contrast'},
    {'1': 'clarity', '3': 5, '4': 1, '5': 2, '10': 'clarity'},
    {'1': 'saturation', '3': 6, '4': 1, '5': 2, '10': 'saturation'},
    {
      '1': 'lut',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Lut',
      '10': 'lut'
    },
    {'1': 'quarter_turns', '3': 8, '4': 1, '5': 13, '10': 'quarterTurns'},
    {
      '1': 'crop',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Rect',
      '10': 'crop'
    },
    {'1': 'flip', '3': 10, '4': 1, '5': 8, '10': 'flip'},
  ],
};

/// Descriptor for `Develop`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List developDescriptor = $convert.base64Decode(
    'CgdEZXZlbG9wEiAKC3RlbXBlcmF0dXJlGAEgASgCUgt0ZW1wZXJhdHVyZRISCgR0aW50GAIgAS'
    'gCUgR0aW50EhoKCGV4cG9zdXJlGAMgASgCUghleHBvc3VyZRIaCghjb250cmFzdBgEIAEoAlII'
    'Y29udHJhc3QSGAoHY2xhcml0eRgFIAEoAlIHY2xhcml0eRIeCgpzYXR1cmF0aW9uGAYgASgCUg'
    'pzYXR1cmF0aW9uEikKA2x1dBgHIAEoCzIXLnBob3RvbGliLmtlcm5lbC52MS5MdXRSA2x1dBIj'
    'Cg1xdWFydGVyX3R1cm5zGAggASgNUgxxdWFydGVyVHVybnMSLAoEY3JvcBgJIAEoCzIYLnBob3'
    'RvbGliLmtlcm5lbC52MS5SZWN0UgRjcm9wEhIKBGZsaXAYCiABKAhSBGZsaXA=');

@$core.Deprecated('Use lutDescriptor instead')
const Lut$json = {
  '1': 'Lut',
  '2': [
    {'1': 'size', '3': 1, '4': 1, '5': 13, '10': 'size'},
    {'1': 'rgb16', '3': 2, '4': 1, '5': 12, '10': 'rgb16'},
  ],
};

/// Descriptor for `Lut`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lutDescriptor = $convert.base64Decode(
    'CgNMdXQSEgoEc2l6ZRgBIAEoDVIEc2l6ZRIUCgVyZ2IxNhgCIAEoDFIFcmdiMTY=');

@$core.Deprecated('Use rectDescriptor instead')
const Rect$json = {
  '1': 'Rect',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 13, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 13, '10': 'y'},
    {'1': 'width', '3': 3, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 13, '10': 'height'},
  ],
};

/// Descriptor for `Rect`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rectDescriptor = $convert.base64Decode(
    'CgRSZWN0EgwKAXgYASABKA1SAXgSDAoBeRgCIAEoDVIBeRIUCgV3aWR0aBgDIAEoDVIFd2lkdG'
    'gSFgoGaGVpZ2h0GAQgASgNUgZoZWlnaHQ=');

@$core.Deprecated('Use imageDescriptor instead')
const Image$json = {
  '1': 'Image',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {'1': 'rgba', '3': 3, '4': 1, '5': 12, '10': 'rgba'},
  ],
};

/// Descriptor for `Image`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageDescriptor = $convert.base64Decode(
    'CgVJbWFnZRIUCgV3aWR0aBgBIAEoDVIFd2lkdGgSFgoGaGVpZ2h0GAIgASgNUgZoZWlnaHQSEg'
    'oEcmdiYRgDIAEoDFIEcmdiYQ==');

@$core.Deprecated('Use guideDescriptor instead')
const Guide$json = {
  '1': 'Guide',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 13, '10': 'height'},
    {'1': 'log2_luminance', '3': 3, '4': 3, '5': 2, '10': 'log2Luminance'},
  ],
};

/// Descriptor for `Guide`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List guideDescriptor = $convert.base64Decode(
    'CgVHdWlkZRIUCgV3aWR0aBgBIAEoDVIFd2lkdGgSFgoGaGVpZ2h0GAIgASgNUgZoZWlnaHQSJQ'
    'oObG9nMl9sdW1pbmFuY2UYAyADKAJSDWxvZzJMdW1pbmFuY2U=');

@$core.Deprecated('Use gainMapDescriptor instead')
const GainMap$json = {
  '1': 'GainMap',
  '2': [
    {
      '1': 'image',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Image',
      '10': 'image'
    },
    {'1': 'min_log2', '3': 2, '4': 1, '5': 2, '10': 'minLog2'},
    {'1': 'max_log2', '3': 3, '4': 1, '5': 2, '10': 'maxLog2'},
    {'1': 'gamma', '3': 4, '4': 1, '5': 2, '10': 'gamma'},
    {'1': 'offset_sdr', '3': 5, '4': 1, '5': 2, '10': 'offsetSdr'},
    {'1': 'offset_hdr', '3': 6, '4': 1, '5': 2, '10': 'offsetHdr'},
    {'1': 'hdr_capacity_min', '3': 7, '4': 1, '5': 2, '10': 'hdrCapacityMin'},
    {'1': 'hdr_capacity_max', '3': 8, '4': 1, '5': 2, '10': 'hdrCapacityMax'},
  ],
};

/// Descriptor for `GainMap`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List gainMapDescriptor = $convert.base64Decode(
    'CgdHYWluTWFwEi8KBWltYWdlGAEgASgLMhkucGhvdG9saWIua2VybmVsLnYxLkltYWdlUgVpbW'
    'FnZRIZCghtaW5fbG9nMhgCIAEoAlIHbWluTG9nMhIZCghtYXhfbG9nMhgDIAEoAlIHbWF4TG9n'
    'MhIUCgVnYW1tYRgEIAEoAlIFZ2FtbWESHQoKb2Zmc2V0X3NkchgFIAEoAlIJb2Zmc2V0U2RyEh'
    '0KCm9mZnNldF9oZHIYBiABKAJSCW9mZnNldEhkchIoChBoZHJfY2FwYWNpdHlfbWluGAcgASgC'
    'Ug5oZHJDYXBhY2l0eU1pbhIoChBoZHJfY2FwYWNpdHlfbWF4GAggASgCUg5oZHJDYXBhY2l0eU'
    '1heA==');

@$core.Deprecated('Use editCopyRequestDescriptor instead')
const EditCopyRequest$json = {
  '1': 'EditCopyRequest',
  '2': [
    {'1': 'original', '3': 1, '4': 1, '5': 12, '10': 'original'},
    {
      '1': 'develop',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Develop',
      '10': 'develop'
    },
    {
      '1': 'image',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Image',
      '10': 'image'
    },
    {
      '1': 'capture_time',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.CaptureTime',
      '10': 'captureTime'
    },
    {'1': 'original_blake3', '3': 5, '4': 1, '5': 9, '10': 'originalBlake3'},
    {
      '1': 'recipe',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'recipe'
    },
    {'1': 'rendered', '3': 7, '4': 1, '5': 8, '10': 'rendered'},
    {'1': 'metadata_from', '3': 8, '4': 1, '5': 12, '10': 'metadataFrom'},
  ],
};

/// Descriptor for `EditCopyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List editCopyRequestDescriptor = $convert.base64Decode(
    'Cg9FZGl0Q29weVJlcXVlc3QSGgoIb3JpZ2luYWwYASABKAxSCG9yaWdpbmFsEjUKB2RldmVsb3'
    'AYAiABKAsyGy5waG90b2xpYi5rZXJuZWwudjEuRGV2ZWxvcFIHZGV2ZWxvcBIvCgVpbWFnZRgD'
    'IAEoCzIZLnBob3RvbGliLmtlcm5lbC52MS5JbWFnZVIFaW1hZ2USQQoMY2FwdHVyZV90aW1lGA'
    'QgASgLMh4ucGhvdG9saWIubW9kZWwudjEuQ2FwdHVyZVRpbWVSC2NhcHR1cmVUaW1lEicKD29y'
    'aWdpbmFsX2JsYWtlMxgFIAEoCVIOb3JpZ2luYWxCbGFrZTMSNQoGcmVjaXBlGAYgASgLMh0ucG'
    'hvdG9saWIubW9kZWwudjEuRWRpdFJlY2lwZVIGcmVjaXBlEhoKCHJlbmRlcmVkGAcgASgIUghy'
    'ZW5kZXJlZBIjCg1tZXRhZGF0YV9mcm9tGAggASgMUgxtZXRhZGF0YUZyb20=');

@$core.Deprecated('Use editCopyResponseDescriptor instead')
const EditCopyResponse$json = {
  '1': 'EditCopyResponse',
  '2': [
    {'1': 'jpeg', '3': 1, '4': 1, '5': 12, '10': 'jpeg'},
    {'1': 'lossless', '3': 2, '4': 1, '5': 8, '10': 'lossless'},
    {
      '1': 'crop',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Rect',
      '10': 'crop'
    },
  ],
};

/// Descriptor for `EditCopyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List editCopyResponseDescriptor = $convert.base64Decode(
    'ChBFZGl0Q29weVJlc3BvbnNlEhIKBGpwZWcYASABKAxSBGpwZWcSGgoIbG9zc2xlc3MYAiABKA'
    'hSCGxvc3NsZXNzEiwKBGNyb3AYAyABKAsyGC5waG90b2xpYi5rZXJuZWwudjEuUmVjdFIEY3Jv'
    'cA==');
