// This is a generated file - do not edit.
//
// Generated from photolib/sync/v1/mutation.proto.

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

@$core.Deprecated('Use hlcDescriptor instead')
const Hlc$json = {
  '1': 'Hlc',
  '2': [
    {'1': 'physical_ms', '3': 1, '4': 1, '5': 3, '10': 'physicalMs'},
    {'1': 'counter', '3': 2, '4': 1, '5': 13, '10': 'counter'},
    {'1': 'device_id', '3': 3, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `Hlc`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hlcDescriptor = $convert.base64Decode(
    'CgNIbGMSHwoLcGh5c2ljYWxfbXMYASABKANSCnBoeXNpY2FsTXMSGAoHY291bnRlchgCIAEoDV'
    'IHY291bnRlchIbCglkZXZpY2VfaWQYAyABKAlSCGRldmljZUlk');

@$core.Deprecated('Use mutationDescriptor instead')
const Mutation$json = {
  '1': 'Mutation',
  '2': [
    {'1': 'mutation_id', '3': 1, '4': 1, '5': 9, '10': 'mutationId'},
    {
      '1': 'hlc',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.sync.v1.Hlc',
      '10': 'hlc'
    },
    {
      '1': 'recorded_at',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'recordedAt'
    },
    {
      '1': 'edit',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.sync.v1.FieldEdit',
      '9': 0,
      '10': 'edit'
    },
    {
      '1': 'member',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.photolib.sync.v1.MemberEdit',
      '9': 0,
      '10': 'member'
    },
    {
      '1': 'version',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.photolib.sync.v1.VersionEdit',
      '9': 0,
      '10': 'version'
    },
  ],
  '8': [
    {'1': 'change'},
  ],
};

/// Descriptor for `Mutation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mutationDescriptor = $convert.base64Decode(
    'CghNdXRhdGlvbhIfCgttdXRhdGlvbl9pZBgBIAEoCVIKbXV0YXRpb25JZBInCgNobGMYAiABKA'
    'syFS5waG90b2xpYi5zeW5jLnYxLkhsY1IDaGxjEjsKC3JlY29yZGVkX2F0GAMgASgLMhouZ29v'
    'Z2xlLnByb3RvYnVmLlRpbWVzdGFtcFIKcmVjb3JkZWRBdBIxCgRlZGl0GAQgASgLMhsucGhvdG'
    '9saWIuc3luYy52MS5GaWVsZEVkaXRIAFIEZWRpdBI2CgZtZW1iZXIYBSABKAsyHC5waG90b2xp'
    'Yi5zeW5jLnYxLk1lbWJlckVkaXRIAFIGbWVtYmVyEjkKB3ZlcnNpb24YBiABKAsyHS5waG90b2'
    'xpYi5zeW5jLnYxLlZlcnNpb25FZGl0SABSB3ZlcnNpb25CCAoGY2hhbmdl');

@$core.Deprecated('Use fieldEditDescriptor instead')
const FieldEdit$json = {
  '1': 'FieldEdit',
  '2': [
    {'1': 'entity', '3': 1, '4': 1, '5': 9, '10': 'entity'},
    {'1': 'id', '3': 2, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'fields',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.sync.v1.FieldEdit.FieldsEntry',
      '10': 'fields'
    },
  ],
  '3': [FieldEdit_FieldsEntry$json],
};

@$core.Deprecated('Use fieldEditDescriptor instead')
const FieldEdit_FieldsEntry$json = {
  '1': 'FieldsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {
      '1': 'value',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.sync.v1.Value',
      '10': 'value'
    },
  ],
  '7': {'7': true},
};

/// Descriptor for `FieldEdit`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fieldEditDescriptor = $convert.base64Decode(
    'CglGaWVsZEVkaXQSFgoGZW50aXR5GAEgASgJUgZlbnRpdHkSDgoCaWQYAiABKAlSAmlkEj8KBm'
    'ZpZWxkcxgDIAMoCzInLnBob3RvbGliLnN5bmMudjEuRmllbGRFZGl0LkZpZWxkc0VudHJ5UgZm'
    'aWVsZHMaUgoLRmllbGRzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSLQoFdmFsdWUYAiABKAsyFy'
    '5waG90b2xpYi5zeW5jLnYxLlZhbHVlUgV2YWx1ZToCOAE=');

@$core.Deprecated('Use memberEditDescriptor instead')
const MemberEdit$json = {
  '1': 'MemberEdit',
  '2': [
    {'1': 'entity', '3': 1, '4': 1, '5': 9, '10': 'entity'},
    {'1': 'set_id', '3': 2, '4': 1, '5': 9, '10': 'setId'},
    {'1': 'element_id', '3': 3, '4': 1, '5': 9, '10': 'elementId'},
    {'1': 'present', '3': 4, '4': 1, '5': 8, '10': 'present'},
    {'1': 'sort_key', '3': 5, '4': 1, '5': 9, '10': 'sortKey'},
  ],
};

/// Descriptor for `MemberEdit`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List memberEditDescriptor = $convert.base64Decode(
    'CgpNZW1iZXJFZGl0EhYKBmVudGl0eRgBIAEoCVIGZW50aXR5EhUKBnNldF9pZBgCIAEoCVIFc2'
    'V0SWQSHQoKZWxlbWVudF9pZBgDIAEoCVIJZWxlbWVudElkEhgKB3ByZXNlbnQYBCABKAhSB3By'
    'ZXNlbnQSGQoIc29ydF9rZXkYBSABKAlSB3NvcnRLZXk=');

@$core.Deprecated('Use versionEditDescriptor instead')
const VersionEdit$json = {
  '1': 'VersionEdit',
  '2': [
    {'1': 'asset_id', '3': 1, '4': 1, '5': 9, '10': 'assetId'},
    {'1': 'version_id', '3': 2, '4': 1, '5': 9, '10': 'versionId'},
    {'1': 'parent_id', '3': 3, '4': 1, '5': 9, '10': 'parentId'},
    {'1': 'label', '3': 4, '4': 1, '5': 9, '10': 'label'},
    {'1': 'recipe', '3': 5, '4': 1, '5': 12, '10': 'recipe'},
  ],
};

/// Descriptor for `VersionEdit`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List versionEditDescriptor = $convert.base64Decode(
    'CgtWZXJzaW9uRWRpdBIZCghhc3NldF9pZBgBIAEoCVIHYXNzZXRJZBIdCgp2ZXJzaW9uX2lkGA'
    'IgASgJUgl2ZXJzaW9uSWQSGwoJcGFyZW50X2lkGAMgASgJUghwYXJlbnRJZBIUCgVsYWJlbBgE'
    'IAEoCVIFbGFiZWwSFgoGcmVjaXBlGAUgASgMUgZyZWNpcGU=');

@$core.Deprecated('Use mutationBatchDescriptor instead')
const MutationBatch$json = {
  '1': 'MutationBatch',
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

/// Descriptor for `MutationBatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mutationBatchDescriptor = $convert.base64Decode(
    'Cg1NdXRhdGlvbkJhdGNoEjgKCW11dGF0aW9ucxgBIAMoCzIaLnBob3RvbGliLnN5bmMudjEuTX'
    'V0YXRpb25SCW11dGF0aW9ucw==');
