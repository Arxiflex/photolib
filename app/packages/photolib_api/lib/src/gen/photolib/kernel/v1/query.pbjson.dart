// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/query.proto.

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

@$core.Deprecated('Use parseQueryRequestDescriptor instead')
const ParseQueryRequest$json = {
  '1': 'ParseQueryRequest',
  '2': [
    {'1': 'query', '3': 1, '4': 1, '5': 9, '10': 'query'},
  ],
};

/// Descriptor for `ParseQueryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List parseQueryRequestDescriptor = $convert
    .base64Decode('ChFQYXJzZVF1ZXJ5UmVxdWVzdBIUCgVxdWVyeRgBIAEoCVIFcXVlcnk=');

@$core.Deprecated('Use parseQueryResponseDescriptor instead')
const ParseQueryResponse$json = {
  '1': 'ParseQueryResponse',
  '2': [
    {
      '1': 'root',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.QueryNode',
      '10': 'root'
    },
  ],
};

/// Descriptor for `ParseQueryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List parseQueryResponseDescriptor = $convert.base64Decode(
    'ChJQYXJzZVF1ZXJ5UmVzcG9uc2USMQoEcm9vdBgBIAEoCzIdLnBob3RvbGliLmtlcm5lbC52MS'
    '5RdWVyeU5vZGVSBHJvb3Q=');

@$core.Deprecated('Use queryNodeDescriptor instead')
const QueryNode$json = {
  '1': 'QueryNode',
  '2': [
    {
      '1': 'term',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.QueryTerm',
      '9': 0,
      '10': 'term'
    },
    {
      '1': 'negated',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.QueryNode',
      '9': 0,
      '10': 'negated'
    },
    {
      '1': 'all',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.QueryNodeList',
      '9': 0,
      '10': 'all'
    },
    {
      '1': 'any',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.QueryNodeList',
      '9': 0,
      '10': 'any'
    },
  ],
  '8': [
    {'1': 'node'},
  ],
};

/// Descriptor for `QueryNode`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List queryNodeDescriptor = $convert.base64Decode(
    'CglRdWVyeU5vZGUSMwoEdGVybRgBIAEoCzIdLnBob3RvbGliLmtlcm5lbC52MS5RdWVyeVRlcm'
    '1IAFIEdGVybRI5CgduZWdhdGVkGAIgASgLMh0ucGhvdG9saWIua2VybmVsLnYxLlF1ZXJ5Tm9k'
    'ZUgAUgduZWdhdGVkEjUKA2FsbBgDIAEoCzIhLnBob3RvbGliLmtlcm5lbC52MS5RdWVyeU5vZG'
    'VMaXN0SABSA2FsbBI1CgNhbnkYBCABKAsyIS5waG90b2xpYi5rZXJuZWwudjEuUXVlcnlOb2Rl'
    'TGlzdEgAUgNhbnlCBgoEbm9kZQ==');

@$core.Deprecated('Use queryNodeListDescriptor instead')
const QueryNodeList$json = {
  '1': 'QueryNodeList',
  '2': [
    {
      '1': 'nodes',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.QueryNode',
      '10': 'nodes'
    },
  ],
};

/// Descriptor for `QueryNodeList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List queryNodeListDescriptor = $convert.base64Decode(
    'Cg1RdWVyeU5vZGVMaXN0EjMKBW5vZGVzGAEgAygLMh0ucGhvdG9saWIua2VybmVsLnYxLlF1ZX'
    'J5Tm9kZVIFbm9kZXM=');

@$core.Deprecated('Use queryTermDescriptor instead')
const QueryTerm$json = {
  '1': 'QueryTerm',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
    {'1': 'phrase', '3': 3, '4': 1, '5': 8, '10': 'phrase'},
  ],
};

/// Descriptor for `QueryTerm`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List queryTermDescriptor = $convert.base64Decode(
    'CglRdWVyeVRlcm0SEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlEhYKBn'
    'BocmFzZRgDIAEoCFIGcGhyYXNl');
