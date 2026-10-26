// This is a generated file - do not edit.
//
// Generated from photolib/model/v1/capture_time.proto.

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

@$core.Deprecated('Use captureTimePrecisionDescriptor instead')
const CaptureTimePrecision$json = {
  '1': 'CaptureTimePrecision',
  '2': [
    {'1': 'CAPTURE_TIME_PRECISION_UNSPECIFIED', '2': 0},
    {'1': 'CAPTURE_TIME_PRECISION_YEAR', '2': 1},
    {'1': 'CAPTURE_TIME_PRECISION_MONTH', '2': 2},
    {'1': 'CAPTURE_TIME_PRECISION_DAY', '2': 3},
    {'1': 'CAPTURE_TIME_PRECISION_MINUTE', '2': 4},
    {'1': 'CAPTURE_TIME_PRECISION_SECOND', '2': 5},
    {'1': 'CAPTURE_TIME_PRECISION_MILLISECOND', '2': 6},
  ],
};

/// Descriptor for `CaptureTimePrecision`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List captureTimePrecisionDescriptor = $convert.base64Decode(
    'ChRDYXB0dXJlVGltZVByZWNpc2lvbhImCiJDQVBUVVJFX1RJTUVfUFJFQ0lTSU9OX1VOU1BFQ0'
    'lGSUVEEAASHwobQ0FQVFVSRV9USU1FX1BSRUNJU0lPTl9ZRUFSEAESIAocQ0FQVFVSRV9USU1F'
    'X1BSRUNJU0lPTl9NT05USBACEh4KGkNBUFRVUkVfVElNRV9QUkVDSVNJT05fREFZEAMSIQodQ0'
    'FQVFVSRV9USU1FX1BSRUNJU0lPTl9NSU5VVEUQBBIhCh1DQVBUVVJFX1RJTUVfUFJFQ0lTSU9O'
    'X1NFQ09ORBAFEiYKIkNBUFRVUkVfVElNRV9QUkVDSVNJT05fTUlMTElTRUNPTkQQBg==');

@$core.Deprecated('Use captureTimeDescriptor instead')
const CaptureTime$json = {
  '1': 'CaptureTime',
  '2': [
    {'1': 'local_datetime', '3': 1, '4': 1, '5': 9, '10': 'localDatetime'},
    {
      '1': 'offset_minutes',
      '3': 2,
      '4': 1,
      '5': 17,
      '9': 0,
      '10': 'offsetMinutes',
      '17': true
    },
    {'1': 'zone', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'zone', '17': true},
    {
      '1': 'precision',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.photolib.model.v1.CaptureTimePrecision',
      '10': 'precision'
    },
    {'1': 'source', '3': 5, '4': 1, '5': 9, '10': 'source'},
    {'1': 'confidence', '3': 6, '4': 1, '5': 13, '10': 'confidence'},
  ],
  '8': [
    {'1': '_offset_minutes'},
    {'1': '_zone'},
  ],
};

/// Descriptor for `CaptureTime`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List captureTimeDescriptor = $convert.base64Decode(
    'CgtDYXB0dXJlVGltZRIlCg5sb2NhbF9kYXRldGltZRgBIAEoCVINbG9jYWxEYXRldGltZRIqCg'
    '5vZmZzZXRfbWludXRlcxgCIAEoEUgAUg1vZmZzZXRNaW51dGVziAEBEhcKBHpvbmUYAyABKAlI'
    'AVIEem9uZYgBARJFCglwcmVjaXNpb24YBCABKA4yJy5waG90b2xpYi5tb2RlbC52MS5DYXB0dX'
    'JlVGltZVByZWNpc2lvblIJcHJlY2lzaW9uEhYKBnNvdXJjZRgFIAEoCVIGc291cmNlEh4KCmNv'
    'bmZpZGVuY2UYBiABKA1SCmNvbmZpZGVuY2VCEQoPX29mZnNldF9taW51dGVzQgcKBV96b25l');
