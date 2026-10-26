// This is a generated file - do not edit.
//
// Generated from photolib/sync/v1/sync.proto.

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

@$core.Deprecated('Use streamStatusDescriptor instead')
const StreamStatus$json = {
  '1': 'StreamStatus',
  '2': [
    {'1': 'STREAM_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'STREAM_STATUS_OK', '2': 1},
    {'1': 'STREAM_STATUS_RESET_REQUIRED', '2': 2},
    {'1': 'STREAM_STATUS_FORBIDDEN', '2': 3},
  ],
};

/// Descriptor for `StreamStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List streamStatusDescriptor = $convert.base64Decode(
    'CgxTdHJlYW1TdGF0dXMSHQoZU1RSRUFNX1NUQVRVU19VTlNQRUNJRklFRBAAEhQKEFNUUkVBTV'
    '9TVEFUVVNfT0sQARIgChxTVFJFQU1fU1RBVFVTX1JFU0VUX1JFUVVJUkVEEAISGwoXU1RSRUFN'
    'X1NUQVRVU19GT1JCSURERU4QAw==');

@$core.Deprecated('Use streamCursorDescriptor instead')
const StreamCursor$json = {
  '1': 'StreamCursor',
  '2': [
    {'1': 'stream', '3': 1, '4': 1, '5': 9, '10': 'stream'},
    {'1': 'cursor', '3': 2, '4': 1, '5': 12, '10': 'cursor'},
  ],
};

/// Descriptor for `StreamCursor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamCursorDescriptor = $convert.base64Decode(
    'CgxTdHJlYW1DdXJzb3ISFgoGc3RyZWFtGAEgASgJUgZzdHJlYW0SFgoGY3Vyc29yGAIgASgMUg'
    'ZjdXJzb3I=');

@$core.Deprecated('Use valueDescriptor instead')
const Value$json = {
  '1': 'Value',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'text'},
    {'1': 'integer', '3': 2, '4': 1, '5': 18, '9': 0, '10': 'integer'},
    {'1': 'real', '3': 3, '4': 1, '5': 1, '9': 0, '10': 'real'},
    {'1': 'boolean', '3': 4, '4': 1, '5': 8, '9': 0, '10': 'boolean'},
    {'1': 'blob', '3': 5, '4': 1, '5': 12, '9': 0, '10': 'blob'},
  ],
  '8': [
    {'1': 'kind'},
  ],
};

/// Descriptor for `Value`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List valueDescriptor = $convert.base64Decode(
    'CgVWYWx1ZRIUCgR0ZXh0GAEgASgJSABSBHRleHQSGgoHaW50ZWdlchgCIAEoEkgAUgdpbnRlZ2'
    'VyEhQKBHJlYWwYAyABKAFIAFIEcmVhbBIaCgdib29sZWFuGAQgASgISABSB2Jvb2xlYW4SFAoE'
    'YmxvYhgFIAEoDEgAUgRibG9iQgYKBGtpbmQ=');

@$core.Deprecated('Use rowDescriptor instead')
const Row$json = {
  '1': 'Row',
  '2': [
    {
      '1': 'values',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.sync.v1.Value',
      '10': 'values'
    },
  ],
};

/// Descriptor for `Row`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rowDescriptor = $convert.base64Decode(
    'CgNSb3cSLwoGdmFsdWVzGAEgAygLMhcucGhvdG9saWIuc3luYy52MS5WYWx1ZVIGdmFsdWVz');

@$core.Deprecated('Use rowsDescriptor instead')
const Rows$json = {
  '1': 'Rows',
  '2': [
    {'1': 'entity', '3': 1, '4': 1, '5': 9, '10': 'entity'},
    {'1': 'columns', '3': 2, '4': 3, '5': 9, '10': 'columns'},
    {
      '1': 'rows',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.sync.v1.Row',
      '10': 'rows'
    },
    {'1': 'deleted', '3': 4, '4': 1, '5': 8, '10': 'deleted'},
  ],
};

/// Descriptor for `Rows`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rowsDescriptor = $convert.base64Decode(
    'CgRSb3dzEhYKBmVudGl0eRgBIAEoCVIGZW50aXR5EhgKB2NvbHVtbnMYAiADKAlSB2NvbHVtbn'
    'MSKQoEcm93cxgDIAMoCzIVLnBob3RvbGliLnN5bmMudjEuUm93UgRyb3dzEhgKB2RlbGV0ZWQY'
    'BCABKAhSB2RlbGV0ZWQ=');

@$core.Deprecated('Use syncBatchDescriptor instead')
const SyncBatch$json = {
  '1': 'SyncBatch',
  '2': [
    {'1': 'stream', '3': 1, '4': 1, '5': 9, '10': 'stream'},
    {
      '1': 'status',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.photolib.sync.v1.StreamStatus',
      '10': 'status'
    },
    {
      '1': 'changes',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.sync.v1.Rows',
      '10': 'changes'
    },
    {'1': 'cursor', '3': 4, '4': 1, '5': 12, '10': 'cursor'},
    {'1': 'caught_up', '3': 5, '4': 1, '5': 8, '10': 'caughtUp'},
  ],
};

/// Descriptor for `SyncBatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncBatchDescriptor = $convert.base64Decode(
    'CglTeW5jQmF0Y2gSFgoGc3RyZWFtGAEgASgJUgZzdHJlYW0SNgoGc3RhdHVzGAIgASgOMh4ucG'
    'hvdG9saWIuc3luYy52MS5TdHJlYW1TdGF0dXNSBnN0YXR1cxIwCgdjaGFuZ2VzGAMgAygLMhYu'
    'cGhvdG9saWIuc3luYy52MS5Sb3dzUgdjaGFuZ2VzEhYKBmN1cnNvchgEIAEoDFIGY3Vyc29yEh'
    'sKCWNhdWdodF91cBgFIAEoCFIIY2F1Z2h0VXA=');
