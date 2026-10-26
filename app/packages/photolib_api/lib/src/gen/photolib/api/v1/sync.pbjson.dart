// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/sync.proto.

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

import 'package:protobuf/well_known_types/google/protobuf/timestamp.pbjson.dart'
    as $4;

import '../../sync/v1/mutation.pbjson.dart' as $2;
import '../../sync/v1/sync.pbjson.dart' as $1;
import 'admin.pbjson.dart' as $0;
import 'error.pbjson.dart' as $3;

@$core.Deprecated('Use emptyTrashRequestDescriptor instead')
const EmptyTrashRequest$json = {
  '1': 'EmptyTrashRequest',
  '2': [
    {'1': 'confirm_token', '3': 1, '4': 1, '5': 9, '10': 'confirmToken'},
  ],
};

/// Descriptor for `EmptyTrashRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emptyTrashRequestDescriptor = $convert.base64Decode(
    'ChFFbXB0eVRyYXNoUmVxdWVzdBIjCg1jb25maXJtX3Rva2VuGAEgASgJUgxjb25maXJtVG9rZW'
    '4=');

@$core.Deprecated('Use emptyTrashResponseDescriptor instead')
const EmptyTrashResponse$json = {
  '1': 'EmptyTrashResponse',
  '2': [
    {
      '1': 'held',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Confirmation',
      '10': 'held'
    },
    {'1': 'queued', '3': 2, '4': 1, '5': 3, '10': 'queued'},
  ],
};

/// Descriptor for `EmptyTrashResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emptyTrashResponseDescriptor = $convert.base64Decode(
    'ChJFbXB0eVRyYXNoUmVzcG9uc2USMQoEaGVsZBgBIAEoCzIdLnBob3RvbGliLmFwaS52MS5Db2'
    '5maXJtYXRpb25SBGhlbGQSFgoGcXVldWVkGAIgASgDUgZxdWV1ZWQ=');

@$core.Deprecated('Use syncRequestDescriptor instead')
const SyncRequest$json = {
  '1': 'SyncRequest',
  '2': [
    {
      '1': 'streams',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.sync.v1.StreamCursor',
      '10': 'streams'
    },
  ],
};

/// Descriptor for `SyncRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncRequestDescriptor = $convert.base64Decode(
    'CgtTeW5jUmVxdWVzdBI4CgdzdHJlYW1zGAEgAygLMh4ucGhvdG9saWIuc3luYy52MS5TdHJlYW'
    '1DdXJzb3JSB3N0cmVhbXM=');

@$core.Deprecated('Use syncResponseDescriptor instead')
const SyncResponse$json = {
  '1': 'SyncResponse',
  '2': [
    {
      '1': 'batch',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.sync.v1.SyncBatch',
      '10': 'batch'
    },
  ],
};

/// Descriptor for `SyncResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncResponseDescriptor = $convert.base64Decode(
    'CgxTeW5jUmVzcG9uc2USMQoFYmF0Y2gYASABKAsyGy5waG90b2xpYi5zeW5jLnYxLlN5bmNCYX'
    'RjaFIFYmF0Y2g=');

@$core.Deprecated('Use getTimelineSummaryRequestDescriptor instead')
const GetTimelineSummaryRequest$json = {
  '1': 'GetTimelineSummaryRequest',
};

/// Descriptor for `GetTimelineSummaryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTimelineSummaryRequestDescriptor =
    $convert.base64Decode('ChlHZXRUaW1lbGluZVN1bW1hcnlSZXF1ZXN0');

@$core.Deprecated('Use getTimelineSummaryResponseDescriptor instead')
const GetTimelineSummaryResponse$json = {
  '1': 'GetTimelineSummaryResponse',
  '2': [
    {
      '1': 'days',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.TimelineDay',
      '10': 'days'
    },
  ],
};

/// Descriptor for `GetTimelineSummaryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTimelineSummaryResponseDescriptor =
    $convert.base64Decode(
        'ChpHZXRUaW1lbGluZVN1bW1hcnlSZXNwb25zZRIwCgRkYXlzGAEgAygLMhwucGhvdG9saWIuYX'
        'BpLnYxLlRpbWVsaW5lRGF5UgRkYXlz');

@$core.Deprecated('Use timelineDayDescriptor instead')
const TimelineDay$json = {
  '1': 'TimelineDay',
  '2': [
    {'1': 'library_id', '3': 1, '4': 1, '5': 9, '10': 'libraryId'},
    {'1': 'date', '3': 2, '4': 1, '5': 9, '10': 'date'},
    {'1': 'count', '3': 3, '4': 1, '5': 13, '10': 'count'},
  ],
};

/// Descriptor for `TimelineDay`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List timelineDayDescriptor = $convert.base64Decode(
    'CgtUaW1lbGluZURheRIdCgpsaWJyYXJ5X2lkGAEgASgJUglsaWJyYXJ5SWQSEgoEZGF0ZRgCIA'
    'EoCVIEZGF0ZRIUCgVjb3VudBgDIAEoDVIFY291bnQ=');

@$core.Deprecated('Use checkHashesRequestDescriptor instead')
const CheckHashesRequest$json = {
  '1': 'CheckHashesRequest',
  '2': [
    {'1': 'hashes', '3': 1, '4': 3, '5': 12, '10': 'hashes'},
  ],
};

/// Descriptor for `CheckHashesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkHashesRequestDescriptor =
    $convert.base64Decode(
        'ChJDaGVja0hhc2hlc1JlcXVlc3QSFgoGaGFzaGVzGAEgAygMUgZoYXNoZXM=');

@$core.Deprecated('Use checkHashesResponseDescriptor instead')
const CheckHashesResponse$json = {
  '1': 'CheckHashesResponse',
  '2': [
    {'1': 'asset_ids', '3': 1, '4': 3, '5': 9, '10': 'assetIds'},
  ],
};

/// Descriptor for `CheckHashesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkHashesResponseDescriptor =
    $convert.base64Decode(
        'ChNDaGVja0hhc2hlc1Jlc3BvbnNlEhsKCWFzc2V0X2lkcxgBIAMoCVIIYXNzZXRJZHM=');

@$core.Deprecated('Use pushMutationsRequestDescriptor instead')
const PushMutationsRequest$json = {
  '1': 'PushMutationsRequest',
  '2': [
    {
      '1': 'mutations',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.sync.v1.Mutation',
      '10': 'mutations'
    },
  ],
};

/// Descriptor for `PushMutationsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pushMutationsRequestDescriptor = $convert.base64Decode(
    'ChRQdXNoTXV0YXRpb25zUmVxdWVzdBI4CgltdXRhdGlvbnMYASADKAsyGi5waG90b2xpYi5zeW'
    '5jLnYxLk11dGF0aW9uUgltdXRhdGlvbnM=');

@$core.Deprecated('Use pushMutationsResponseDescriptor instead')
const PushMutationsResponse$json = {
  '1': 'PushMutationsResponse',
  '2': [
    {
      '1': 'results',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.MutationResult',
      '10': 'results'
    },
    {
      '1': 'rows',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.photolib.sync.v1.Rows',
      '10': 'rows'
    },
    {
      '1': 'clock',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.sync.v1.Hlc',
      '10': 'clock'
    },
  ],
};

/// Descriptor for `PushMutationsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pushMutationsResponseDescriptor = $convert.base64Decode(
    'ChVQdXNoTXV0YXRpb25zUmVzcG9uc2USOQoHcmVzdWx0cxgBIAMoCzIfLnBob3RvbGliLmFwaS'
    '52MS5NdXRhdGlvblJlc3VsdFIHcmVzdWx0cxIqCgRyb3dzGAIgAygLMhYucGhvdG9saWIuc3lu'
    'Yy52MS5Sb3dzUgRyb3dzEisKBWNsb2NrGAMgASgLMhUucGhvdG9saWIuc3luYy52MS5IbGNSBW'
    'Nsb2Nr');

@$core.Deprecated('Use mutationResultDescriptor instead')
const MutationResult$json = {
  '1': 'MutationResult',
  '2': [
    {'1': 'mutation_id', '3': 1, '4': 1, '5': 9, '10': 'mutationId'},
    {
      '1': 'rejected',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.ErrorDetail',
      '10': 'rejected'
    },
  ],
};

/// Descriptor for `MutationResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mutationResultDescriptor = $convert.base64Decode(
    'Cg5NdXRhdGlvblJlc3VsdBIfCgttdXRhdGlvbl9pZBgBIAEoCVIKbXV0YXRpb25JZBI4CghyZW'
    'plY3RlZBgCIAEoCzIcLnBob3RvbGliLmFwaS52MS5FcnJvckRldGFpbFIIcmVqZWN0ZWQ=');

const $core.Map<$core.String, $core.dynamic> SyncServiceBase$json = {
  '1': 'SyncService',
  '2': [
    {
      '1': 'Sync',
      '2': '.photolib.api.v1.SyncRequest',
      '3': '.photolib.api.v1.SyncResponse',
      '6': true
    },
    {
      '1': 'GetTimelineSummary',
      '2': '.photolib.api.v1.GetTimelineSummaryRequest',
      '3': '.photolib.api.v1.GetTimelineSummaryResponse'
    },
    {
      '1': 'CheckHashes',
      '2': '.photolib.api.v1.CheckHashesRequest',
      '3': '.photolib.api.v1.CheckHashesResponse'
    },
    {
      '1': 'PushMutations',
      '2': '.photolib.api.v1.PushMutationsRequest',
      '3': '.photolib.api.v1.PushMutationsResponse'
    },
    {
      '1': 'EmptyTrash',
      '2': '.photolib.api.v1.EmptyTrashRequest',
      '3': '.photolib.api.v1.EmptyTrashResponse'
    },
  ],
};

@$core.Deprecated('Use syncServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    SyncServiceBase$messageJson = {
  '.photolib.api.v1.SyncRequest': SyncRequest$json,
  '.photolib.sync.v1.StreamCursor': $1.StreamCursor$json,
  '.photolib.api.v1.SyncResponse': SyncResponse$json,
  '.photolib.sync.v1.SyncBatch': $1.SyncBatch$json,
  '.photolib.sync.v1.Rows': $1.Rows$json,
  '.photolib.sync.v1.Row': $1.Row$json,
  '.photolib.sync.v1.Value': $1.Value$json,
  '.photolib.api.v1.GetTimelineSummaryRequest': GetTimelineSummaryRequest$json,
  '.photolib.api.v1.GetTimelineSummaryResponse':
      GetTimelineSummaryResponse$json,
  '.photolib.api.v1.TimelineDay': TimelineDay$json,
  '.photolib.api.v1.CheckHashesRequest': CheckHashesRequest$json,
  '.photolib.api.v1.CheckHashesResponse': CheckHashesResponse$json,
  '.photolib.api.v1.PushMutationsRequest': PushMutationsRequest$json,
  '.photolib.sync.v1.Mutation': $2.Mutation$json,
  '.photolib.sync.v1.Hlc': $2.Hlc$json,
  '.google.protobuf.Timestamp': $4.Timestamp$json,
  '.photolib.sync.v1.FieldEdit': $2.FieldEdit$json,
  '.photolib.sync.v1.FieldEdit.FieldsEntry': $2.FieldEdit_FieldsEntry$json,
  '.photolib.sync.v1.MemberEdit': $2.MemberEdit$json,
  '.photolib.sync.v1.VersionEdit': $2.VersionEdit$json,
  '.photolib.api.v1.PushMutationsResponse': PushMutationsResponse$json,
  '.photolib.api.v1.MutationResult': MutationResult$json,
  '.photolib.api.v1.ErrorDetail': $3.ErrorDetail$json,
  '.photolib.api.v1.ErrorDetail.ParamsEntry': $3.ErrorDetail_ParamsEntry$json,
  '.photolib.api.v1.EmptyTrashRequest': EmptyTrashRequest$json,
  '.photolib.api.v1.EmptyTrashResponse': EmptyTrashResponse$json,
  '.photolib.api.v1.Confirmation': $0.Confirmation$json,
};

/// Descriptor for `SyncService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List syncServiceDescriptor = $convert.base64Decode(
    'CgtTeW5jU2VydmljZRJFCgRTeW5jEhwucGhvdG9saWIuYXBpLnYxLlN5bmNSZXF1ZXN0Gh0ucG'
    'hvdG9saWIuYXBpLnYxLlN5bmNSZXNwb25zZTABEm0KEkdldFRpbWVsaW5lU3VtbWFyeRIqLnBo'
    'b3RvbGliLmFwaS52MS5HZXRUaW1lbGluZVN1bW1hcnlSZXF1ZXN0GisucGhvdG9saWIuYXBpLn'
    'YxLkdldFRpbWVsaW5lU3VtbWFyeVJlc3BvbnNlElgKC0NoZWNrSGFzaGVzEiMucGhvdG9saWIu'
    'YXBpLnYxLkNoZWNrSGFzaGVzUmVxdWVzdBokLnBob3RvbGliLmFwaS52MS5DaGVja0hhc2hlc1'
    'Jlc3BvbnNlEl4KDVB1c2hNdXRhdGlvbnMSJS5waG90b2xpYi5hcGkudjEuUHVzaE11dGF0aW9u'
    'c1JlcXVlc3QaJi5waG90b2xpYi5hcGkudjEuUHVzaE11dGF0aW9uc1Jlc3BvbnNlElUKCkVtcH'
    'R5VHJhc2gSIi5waG90b2xpYi5hcGkudjEuRW1wdHlUcmFzaFJlcXVlc3QaIy5waG90b2xpYi5h'
    'cGkudjEuRW1wdHlUcmFzaFJlc3BvbnNl');
