// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/metadata.proto.

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

@$core.Deprecated('Use paceDescriptor instead')
const Pace$json = {
  '1': 'Pace',
  '2': [
    {'1': 'PACE_UNSPECIFIED', '2': 0},
    {'1': 'PACE_SLOW_MOTION', '2': 1},
    {'1': 'PACE_TIME_LAPSE', '2': 2},
  ],
};

/// Descriptor for `Pace`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List paceDescriptor = $convert.base64Decode(
    'CgRQYWNlEhQKEFBBQ0VfVU5TUEVDSUZJRUQQABIUChBQQUNFX1NMT1dfTU9USU9OEAESEwoPUE'
    'FDRV9USU1FX0xBUFNFEAI=');

@$core.Deprecated('Use fileFormatDescriptor instead')
const FileFormat$json = {
  '1': 'FileFormat',
  '2': [
    {'1': 'FILE_FORMAT_UNSPECIFIED', '2': 0},
    {'1': 'FILE_FORMAT_JPEG', '2': 1},
    {'1': 'FILE_FORMAT_TIFF', '2': 2},
    {'1': 'FILE_FORMAT_HEIF', '2': 3},
    {'1': 'FILE_FORMAT_PNG', '2': 4},
    {'1': 'FILE_FORMAT_WEBP', '2': 5},
    {'1': 'FILE_FORMAT_GIF', '2': 6},
    {'1': 'FILE_FORMAT_XMP', '2': 7},
    {'1': 'FILE_FORMAT_RAF', '2': 8},
    {'1': 'FILE_FORMAT_QUICKTIME', '2': 9},
    {'1': 'FILE_FORMAT_AVI', '2': 10},
    {'1': 'FILE_FORMAT_CR3', '2': 11},
  ],
};

/// Descriptor for `FileFormat`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List fileFormatDescriptor = $convert.base64Decode(
    'CgpGaWxlRm9ybWF0EhsKF0ZJTEVfRk9STUFUX1VOU1BFQ0lGSUVEEAASFAoQRklMRV9GT1JNQV'
    'RfSlBFRxABEhQKEEZJTEVfRk9STUFUX1RJRkYQAhIUChBGSUxFX0ZPUk1BVF9IRUlGEAMSEwoP'
    'RklMRV9GT1JNQVRfUE5HEAQSFAoQRklMRV9GT1JNQVRfV0VCUBAFEhMKD0ZJTEVfRk9STUFUX0'
    'dJRhAGEhMKD0ZJTEVfRk9STUFUX1hNUBAHEhMKD0ZJTEVfRk9STUFUX1JBRhAIEhkKFUZJTEVf'
    'Rk9STUFUX1FVSUNLVElNRRAJEhMKD0ZJTEVfRk9STUFUX0FWSRAKEhMKD0ZJTEVfRk9STUFUX0'
    'NSMxAL');

@$core.Deprecated('Use stereoModeDescriptor instead')
const StereoMode$json = {
  '1': 'StereoMode',
  '2': [
    {'1': 'STEREO_MODE_UNSPECIFIED', '2': 0},
    {'1': 'STEREO_MODE_TOP_BOTTOM', '2': 1},
    {'1': 'STEREO_MODE_LEFT_RIGHT', '2': 2},
    {'1': 'STEREO_MODE_CUSTOM', '2': 3},
    {'1': 'STEREO_MODE_RIGHT_LEFT', '2': 4},
  ],
};

/// Descriptor for `StereoMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List stereoModeDescriptor = $convert.base64Decode(
    'CgpTdGVyZW9Nb2RlEhsKF1NURVJFT19NT0RFX1VOU1BFQ0lGSUVEEAASGgoWU1RFUkVPX01PRE'
    'VfVE9QX0JPVFRPTRABEhoKFlNURVJFT19NT0RFX0xFRlRfUklHSFQQAhIWChJTVEVSRU9fTU9E'
    'RV9DVVNUT00QAxIaChZTVEVSRU9fTU9ERV9SSUdIVF9MRUZUEAQ=');

@$core.Deprecated('Use readMetadataRequestDescriptor instead')
const ReadMetadataRequest$json = {
  '1': 'ReadMetadataRequest',
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

/// Descriptor for `ReadMetadataRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readMetadataRequestDescriptor = $convert.base64Decode(
    'ChNSZWFkTWV0YWRhdGFSZXF1ZXN0EjUKBnJhbmdlcxgBIAMoCzIdLnBob3RvbGliLmtlcm5lbC'
    '52MS5GaWxlUmFuZ2VSBnJhbmdlcxISCgRzaXplGAIgASgEUgRzaXpl');

@$core.Deprecated('Use fileRangeDescriptor instead')
const FileRange$json = {
  '1': 'FileRange',
  '2': [
    {'1': 'offset', '3': 1, '4': 1, '5': 4, '10': 'offset'},
    {'1': 'data', '3': 2, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `FileRange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileRangeDescriptor = $convert.base64Decode(
    'CglGaWxlUmFuZ2USFgoGb2Zmc2V0GAEgASgEUgZvZmZzZXQSEgoEZGF0YRgCIAEoDFIEZGF0YQ'
    '==');

@$core.Deprecated('Use byteSpanDescriptor instead')
const ByteSpan$json = {
  '1': 'ByteSpan',
  '2': [
    {'1': 'offset', '3': 1, '4': 1, '5': 4, '10': 'offset'},
    {'1': 'length', '3': 2, '4': 1, '5': 4, '10': 'length'},
  ],
};

/// Descriptor for `ByteSpan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List byteSpanDescriptor = $convert.base64Decode(
    'CghCeXRlU3BhbhIWCgZvZmZzZXQYASABKARSBm9mZnNldBIWCgZsZW5ndGgYAiABKARSBmxlbm'
    'd0aA==');

@$core.Deprecated('Use readMetadataResponseDescriptor instead')
const ReadMetadataResponse$json = {
  '1': 'ReadMetadataResponse',
  '2': [
    {
      '1': 'format',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.FileFormat',
      '10': 'format'
    },
    {'1': 'width', '3': 2, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 3, '4': 1, '5': 13, '10': 'height'},
    {'1': 'orientation', '3': 4, '4': 1, '5': 13, '10': 'orientation'},
    {'1': 'make', '3': 5, '4': 1, '5': 9, '10': 'make'},
    {'1': 'model', '3': 6, '4': 1, '5': 9, '10': 'model'},
    {
      '1': 'location',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.GeoPoint',
      '10': 'location'
    },
    {
      '1': 'times',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.photolib.model.v1.CaptureTime',
      '10': 'times'
    },
    {'1': 'title', '3': 9, '4': 1, '5': 9, '10': 'title'},
    {'1': 'description', '3': 10, '4': 1, '5': 9, '10': 'description'},
    {'1': 'keywords', '3': 11, '4': 3, '5': 9, '10': 'keywords'},
    {
      '1': 'keyword_paths',
      '3': 12,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.KeywordPath',
      '10': 'keywordPaths'
    },
    {
      '1': 'rating',
      '3': 13,
      '4': 1,
      '5': 17,
      '9': 0,
      '10': 'rating',
      '17': true
    },
    {'1': 'label', '3': 14, '4': 1, '5': 9, '10': 'label'},
    {'1': 'creators', '3': 15, '4': 3, '5': 9, '10': 'creators'},
    {'1': 'copyright', '3': 16, '4': 1, '5': 9, '10': 'copyright'},
    {'1': 'city', '3': 17, '4': 1, '5': 9, '10': 'city'},
    {'1': 'state', '3': 18, '4': 1, '5': 9, '10': 'state'},
    {'1': 'country', '3': 19, '4': 1, '5': 9, '10': 'country'},
    {
      '1': 'regions',
      '3': 20,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.ImageRegion',
      '10': 'regions'
    },
    {
      '1': 'panorama',
      '3': 21,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Panorama',
      '10': 'panorama'
    },
    {
      '1': 'motion_photo',
      '3': 22,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.MotionPhotoMarkers',
      '10': 'motionPhoto'
    },
    {
      '1': 'missing',
      '3': 23,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.ByteSpan',
      '10': 'missing'
    },
    {'1': 'duration_ms', '3': 24, '4': 1, '5': 4, '10': 'durationMs'},
    {'1': 'codec', '3': 25, '4': 1, '5': 9, '10': 'codec'},
    {'1': 'transfer', '3': 26, '4': 1, '5': 13, '10': 'transfer'},
    {'1': 'dolby_vision', '3': 27, '4': 1, '5': 8, '10': 'dolbyVision'},
    {
      '1': 'stereo_mode',
      '3': 28,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.StereoMode',
      '10': 'stereoMode'
    },
    {
      '1': 'content_identifier',
      '3': 29,
      '4': 1,
      '5': 9,
      '10': 'contentIdentifier'
    },
    {'1': 'burst_id', '3': 30, '4': 1, '5': 9, '10': 'burstId'},
    {
      '1': 'motion_video',
      '3': 31,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.ByteSpan',
      '10': 'motionVideo'
    },
    {
      '1': 'preview',
      '3': 32,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.ByteSpan',
      '10': 'preview'
    },
    {'1': 'frame_rate', '3': 33, '4': 1, '5': 1, '10': 'frameRate'},
    {'1': 'spatial', '3': 34, '4': 1, '5': 8, '10': 'spatial'},
    {'1': 'depth', '3': 35, '4': 1, '5': 8, '10': 'depth'},
    {
      '1': 'pace',
      '3': 36,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.Pace',
      '10': 'pace'
    },
    {
      '1': 'largest_preview',
      '3': 37,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.ByteSpan',
      '10': 'largestPreview'
    },
    {'1': 'gain_map', '3': 38, '4': 1, '5': 8, '10': 'gainMap'},
  ],
  '8': [
    {'1': '_rating'},
  ],
};

/// Descriptor for `ReadMetadataResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readMetadataResponseDescriptor = $convert.base64Decode(
    'ChRSZWFkTWV0YWRhdGFSZXNwb25zZRI2CgZmb3JtYXQYASABKA4yHi5waG90b2xpYi5rZXJuZW'
    'wudjEuRmlsZUZvcm1hdFIGZm9ybWF0EhQKBXdpZHRoGAIgASgNUgV3aWR0aBIWCgZoZWlnaHQY'
    'AyABKA1SBmhlaWdodBIgCgtvcmllbnRhdGlvbhgEIAEoDVILb3JpZW50YXRpb24SEgoEbWFrZR'
    'gFIAEoCVIEbWFrZRIUCgVtb2RlbBgGIAEoCVIFbW9kZWwSOAoIbG9jYXRpb24YByABKAsyHC5w'
    'aG90b2xpYi5rZXJuZWwudjEuR2VvUG9pbnRSCGxvY2F0aW9uEjQKBXRpbWVzGAggAygLMh4ucG'
    'hvdG9saWIubW9kZWwudjEuQ2FwdHVyZVRpbWVSBXRpbWVzEhQKBXRpdGxlGAkgASgJUgV0aXRs'
    'ZRIgCgtkZXNjcmlwdGlvbhgKIAEoCVILZGVzY3JpcHRpb24SGgoIa2V5d29yZHMYCyADKAlSCG'
    'tleXdvcmRzEkQKDWtleXdvcmRfcGF0aHMYDCADKAsyHy5waG90b2xpYi5rZXJuZWwudjEuS2V5'
    'd29yZFBhdGhSDGtleXdvcmRQYXRocxIbCgZyYXRpbmcYDSABKBFIAFIGcmF0aW5niAEBEhQKBW'
    'xhYmVsGA4gASgJUgVsYWJlbBIaCghjcmVhdG9ycxgPIAMoCVIIY3JlYXRvcnMSHAoJY29weXJp'
    'Z2h0GBAgASgJUgljb3B5cmlnaHQSEgoEY2l0eRgRIAEoCVIEY2l0eRIUCgVzdGF0ZRgSIAEoCV'
    'IFc3RhdGUSGAoHY291bnRyeRgTIAEoCVIHY291bnRyeRI5CgdyZWdpb25zGBQgAygLMh8ucGhv'
    'dG9saWIua2VybmVsLnYxLkltYWdlUmVnaW9uUgdyZWdpb25zEjgKCHBhbm9yYW1hGBUgASgLMh'
    'wucGhvdG9saWIua2VybmVsLnYxLlBhbm9yYW1hUghwYW5vcmFtYRJJCgxtb3Rpb25fcGhvdG8Y'
    'FiABKAsyJi5waG90b2xpYi5rZXJuZWwudjEuTW90aW9uUGhvdG9NYXJrZXJzUgttb3Rpb25QaG'
    '90bxI2CgdtaXNzaW5nGBcgAygLMhwucGhvdG9saWIua2VybmVsLnYxLkJ5dGVTcGFuUgdtaXNz'
    'aW5nEh8KC2R1cmF0aW9uX21zGBggASgEUgpkdXJhdGlvbk1zEhQKBWNvZGVjGBkgASgJUgVjb2'
    'RlYxIaCgh0cmFuc2ZlchgaIAEoDVIIdHJhbnNmZXISIQoMZG9sYnlfdmlzaW9uGBsgASgIUgtk'
    'b2xieVZpc2lvbhI/CgtzdGVyZW9fbW9kZRgcIAEoDjIeLnBob3RvbGliLmtlcm5lbC52MS5TdG'
    'VyZW9Nb2RlUgpzdGVyZW9Nb2RlEi0KEmNvbnRlbnRfaWRlbnRpZmllchgdIAEoCVIRY29udGVu'
    'dElkZW50aWZpZXISGQoIYnVyc3RfaWQYHiABKAlSB2J1cnN0SWQSPwoMbW90aW9uX3ZpZGVvGB'
    '8gASgLMhwucGhvdG9saWIua2VybmVsLnYxLkJ5dGVTcGFuUgttb3Rpb25WaWRlbxI2CgdwcmV2'
    'aWV3GCAgASgLMhwucGhvdG9saWIua2VybmVsLnYxLkJ5dGVTcGFuUgdwcmV2aWV3Eh0KCmZyYW'
    '1lX3JhdGUYISABKAFSCWZyYW1lUmF0ZRIYCgdzcGF0aWFsGCIgASgIUgdzcGF0aWFsEhQKBWRl'
    'cHRoGCMgASgIUgVkZXB0aBIsCgRwYWNlGCQgASgOMhgucGhvdG9saWIua2VybmVsLnYxLlBhY2'
    'VSBHBhY2USRQoPbGFyZ2VzdF9wcmV2aWV3GCUgASgLMhwucGhvdG9saWIua2VybmVsLnYxLkJ5'
    'dGVTcGFuUg5sYXJnZXN0UHJldmlldxIZCghnYWluX21hcBgmIAEoCFIHZ2Fpbk1hcEIJCgdfcm'
    'F0aW5n');

@$core.Deprecated('Use geoPointDescriptor instead')
const GeoPoint$json = {
  '1': 'GeoPoint',
  '2': [
    {'1': 'latitude', '3': 1, '4': 1, '5': 1, '10': 'latitude'},
    {'1': 'longitude', '3': 2, '4': 1, '5': 1, '10': 'longitude'},
    {
      '1': 'altitude_m',
      '3': 3,
      '4': 1,
      '5': 1,
      '9': 0,
      '10': 'altitudeM',
      '17': true
    },
  ],
  '8': [
    {'1': '_altitude_m'},
  ],
};

/// Descriptor for `GeoPoint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List geoPointDescriptor = $convert.base64Decode(
    'CghHZW9Qb2ludBIaCghsYXRpdHVkZRgBIAEoAVIIbGF0aXR1ZGUSHAoJbG9uZ2l0dWRlGAIgAS'
    'gBUglsb25naXR1ZGUSIgoKYWx0aXR1ZGVfbRgDIAEoAUgAUglhbHRpdHVkZU2IAQFCDQoLX2Fs'
    'dGl0dWRlX20=');

@$core.Deprecated('Use keywordPathDescriptor instead')
const KeywordPath$json = {
  '1': 'KeywordPath',
  '2': [
    {'1': 'nodes', '3': 1, '4': 3, '5': 9, '10': 'nodes'},
  ],
};

/// Descriptor for `KeywordPath`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keywordPathDescriptor =
    $convert.base64Decode('CgtLZXl3b3JkUGF0aBIUCgVub2RlcxgBIAMoCVIFbm9kZXM=');

@$core.Deprecated('Use imageRegionDescriptor instead')
const ImageRegion$json = {
  '1': 'ImageRegion',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'type', '3': 2, '4': 1, '5': 9, '10': 'type'},
    {'1': 'x', '3': 3, '4': 1, '5': 1, '10': 'x'},
    {'1': 'y', '3': 4, '4': 1, '5': 1, '10': 'y'},
    {'1': 'width', '3': 5, '4': 1, '5': 1, '10': 'width'},
    {'1': 'height', '3': 6, '4': 1, '5': 1, '10': 'height'},
  ],
};

/// Descriptor for `ImageRegion`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageRegionDescriptor = $convert.base64Decode(
    'CgtJbWFnZVJlZ2lvbhISCgRuYW1lGAEgASgJUgRuYW1lEhIKBHR5cGUYAiABKAlSBHR5cGUSDA'
    'oBeBgDIAEoAVIBeBIMCgF5GAQgASgBUgF5EhQKBXdpZHRoGAUgASgBUgV3aWR0aBIWCgZoZWln'
    'aHQYBiABKAFSBmhlaWdodA==');

@$core.Deprecated('Use panoramaDescriptor instead')
const Panorama$json = {
  '1': 'Panorama',
  '2': [
    {'1': 'projection', '3': 1, '4': 1, '5': 9, '10': 'projection'},
    {
      '1': 'use_panorama_viewer',
      '3': 2,
      '4': 1,
      '5': 8,
      '9': 0,
      '10': 'usePanoramaViewer',
      '17': true
    },
    {'1': 'full_width', '3': 3, '4': 1, '5': 13, '10': 'fullWidth'},
    {'1': 'full_height', '3': 4, '4': 1, '5': 13, '10': 'fullHeight'},
    {'1': 'cropped_left', '3': 5, '4': 1, '5': 13, '10': 'croppedLeft'},
    {'1': 'cropped_top', '3': 6, '4': 1, '5': 13, '10': 'croppedTop'},
    {'1': 'cropped_width', '3': 7, '4': 1, '5': 13, '10': 'croppedWidth'},
    {'1': 'cropped_height', '3': 8, '4': 1, '5': 13, '10': 'croppedHeight'},
    {
      '1': 'pose_heading_degrees',
      '3': 9,
      '4': 1,
      '5': 1,
      '9': 1,
      '10': 'poseHeadingDegrees',
      '17': true
    },
  ],
  '8': [
    {'1': '_use_panorama_viewer'},
    {'1': '_pose_heading_degrees'},
  ],
};

/// Descriptor for `Panorama`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List panoramaDescriptor = $convert.base64Decode(
    'CghQYW5vcmFtYRIeCgpwcm9qZWN0aW9uGAEgASgJUgpwcm9qZWN0aW9uEjMKE3VzZV9wYW5vcm'
    'FtYV92aWV3ZXIYAiABKAhIAFIRdXNlUGFub3JhbWFWaWV3ZXKIAQESHQoKZnVsbF93aWR0aBgD'
    'IAEoDVIJZnVsbFdpZHRoEh8KC2Z1bGxfaGVpZ2h0GAQgASgNUgpmdWxsSGVpZ2h0EiEKDGNyb3'
    'BwZWRfbGVmdBgFIAEoDVILY3JvcHBlZExlZnQSHwoLY3JvcHBlZF90b3AYBiABKA1SCmNyb3Bw'
    'ZWRUb3ASIwoNY3JvcHBlZF93aWR0aBgHIAEoDVIMY3JvcHBlZFdpZHRoEiUKDmNyb3BwZWRfaG'
    'VpZ2h0GAggASgNUg1jcm9wcGVkSGVpZ2h0EjUKFHBvc2VfaGVhZGluZ19kZWdyZWVzGAkgASgB'
    'SAFSEnBvc2VIZWFkaW5nRGVncmVlc4gBAUIWChRfdXNlX3Bhbm9yYW1hX3ZpZXdlckIXChVfcG'
    '9zZV9oZWFkaW5nX2RlZ3JlZXM=');

@$core.Deprecated('Use motionPhotoMarkersDescriptor instead')
const MotionPhotoMarkers$json = {
  '1': 'MotionPhotoMarkers',
  '2': [
    {'1': 'motion_photo', '3': 1, '4': 1, '5': 8, '10': 'motionPhoto'},
    {'1': 'version', '3': 2, '4': 1, '5': 13, '10': 'version'},
    {
      '1': 'presentation_timestamp_us',
      '3': 3,
      '4': 1,
      '5': 3,
      '9': 0,
      '10': 'presentationTimestampUs',
      '17': true
    },
    {'1': 'micro_video', '3': 4, '4': 1, '5': 8, '10': 'microVideo'},
    {
      '1': 'micro_video_offset_bytes',
      '3': 5,
      '4': 1,
      '5': 4,
      '10': 'microVideoOffsetBytes'
    },
    {
      '1': 'items',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.ContainerItem',
      '10': 'items'
    },
  ],
  '8': [
    {'1': '_presentation_timestamp_us'},
  ],
};

/// Descriptor for `MotionPhotoMarkers`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List motionPhotoMarkersDescriptor = $convert.base64Decode(
    'ChJNb3Rpb25QaG90b01hcmtlcnMSIQoMbW90aW9uX3Bob3RvGAEgASgIUgttb3Rpb25QaG90bx'
    'IYCgd2ZXJzaW9uGAIgASgNUgd2ZXJzaW9uEj8KGXByZXNlbnRhdGlvbl90aW1lc3RhbXBfdXMY'
    'AyABKANIAFIXcHJlc2VudGF0aW9uVGltZXN0YW1wVXOIAQESHwoLbWljcm9fdmlkZW8YBCABKA'
    'hSCm1pY3JvVmlkZW8SNwoYbWljcm9fdmlkZW9fb2Zmc2V0X2J5dGVzGAUgASgEUhVtaWNyb1Zp'
    'ZGVvT2Zmc2V0Qnl0ZXMSNwoFaXRlbXMYBiADKAsyIS5waG90b2xpYi5rZXJuZWwudjEuQ29udG'
    'FpbmVySXRlbVIFaXRlbXNCHAoaX3ByZXNlbnRhdGlvbl90aW1lc3RhbXBfdXM=');

@$core.Deprecated('Use containerItemDescriptor instead')
const ContainerItem$json = {
  '1': 'ContainerItem',
  '2': [
    {'1': 'mime', '3': 1, '4': 1, '5': 9, '10': 'mime'},
    {'1': 'semantic', '3': 2, '4': 1, '5': 9, '10': 'semantic'},
    {'1': 'length_bytes', '3': 3, '4': 1, '5': 4, '10': 'lengthBytes'},
    {'1': 'padding_bytes', '3': 4, '4': 1, '5': 4, '10': 'paddingBytes'},
  ],
};

/// Descriptor for `ContainerItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List containerItemDescriptor = $convert.base64Decode(
    'Cg1Db250YWluZXJJdGVtEhIKBG1pbWUYASABKAlSBG1pbWUSGgoIc2VtYW50aWMYAiABKAlSCH'
    'NlbWFudGljEiEKDGxlbmd0aF9ieXRlcxgDIAEoBFILbGVuZ3RoQnl0ZXMSIwoNcGFkZGluZ19i'
    'eXRlcxgEIAEoBFIMcGFkZGluZ0J5dGVz');
