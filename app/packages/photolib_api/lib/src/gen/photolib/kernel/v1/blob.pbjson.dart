// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/blob.proto.

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

@$core.Deprecated('Use encryptBlobRequestDescriptor instead')
const EncryptBlobRequest$json = {
  '1': 'EncryptBlobRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'kind', '3': 2, '4': 1, '5': 13, '10': 'kind'},
    {'1': 'manifest', '3': 3, '4': 1, '5': 8, '10': 'manifest'},
    {'1': 'padded', '3': 4, '4': 1, '5': 8, '10': 'padded'},
    {'1': 'salt', '3': 5, '4': 1, '5': 12, '10': 'salt'},
    {'1': 'plaintext', '3': 6, '4': 1, '5': 12, '10': 'plaintext'},
  ],
};

/// Descriptor for `EncryptBlobRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List encryptBlobRequestDescriptor = $convert.base64Decode(
    'ChJFbmNyeXB0QmxvYlJlcXVlc3QSEAoDa2V5GAEgASgNUgNrZXkSEgoEa2luZBgCIAEoDVIEa2'
    'luZBIaCghtYW5pZmVzdBgDIAEoCFIIbWFuaWZlc3QSFgoGcGFkZGVkGAQgASgIUgZwYWRkZWQS'
    'EgoEc2FsdBgFIAEoDFIEc2FsdBIcCglwbGFpbnRleHQYBiABKAxSCXBsYWludGV4dA==');

@$core.Deprecated('Use encryptBlobResponseDescriptor instead')
const EncryptBlobResponse$json = {
  '1': 'EncryptBlobResponse',
  '2': [
    {'1': 'envelope', '3': 1, '4': 1, '5': 12, '10': 'envelope'},
  ],
};

/// Descriptor for `EncryptBlobResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List encryptBlobResponseDescriptor =
    $convert.base64Decode(
        'ChNFbmNyeXB0QmxvYlJlc3BvbnNlEhoKCGVudmVsb3BlGAEgASgMUghlbnZlbG9wZQ==');

@$core.Deprecated('Use decryptBlobRequestDescriptor instead')
const DecryptBlobRequest$json = {
  '1': 'DecryptBlobRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'kind', '3': 2, '4': 1, '5': 13, '10': 'kind'},
    {'1': 'manifest', '3': 3, '4': 1, '5': 8, '10': 'manifest'},
    {'1': 'envelope', '3': 4, '4': 1, '5': 12, '10': 'envelope'},
    {'1': 'first_chunk', '3': 5, '4': 1, '5': 4, '10': 'firstChunk'},
    {'1': 'more', '3': 6, '4': 1, '5': 8, '10': 'more'},
  ],
};

/// Descriptor for `DecryptBlobRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List decryptBlobRequestDescriptor = $convert.base64Decode(
    'ChJEZWNyeXB0QmxvYlJlcXVlc3QSEAoDa2V5GAEgASgNUgNrZXkSEgoEa2luZBgCIAEoDVIEa2'
    'luZBIaCghtYW5pZmVzdBgDIAEoCFIIbWFuaWZlc3QSGgoIZW52ZWxvcGUYBCABKAxSCGVudmVs'
    'b3BlEh8KC2ZpcnN0X2NodW5rGAUgASgEUgpmaXJzdENodW5rEhIKBG1vcmUYBiABKAhSBG1vcm'
    'U=');

@$core.Deprecated('Use decryptBlobResponseDescriptor instead')
const DecryptBlobResponse$json = {
  '1': 'DecryptBlobResponse',
  '2': [
    {'1': 'plaintext', '3': 1, '4': 1, '5': 12, '10': 'plaintext'},
  ],
};

/// Descriptor for `DecryptBlobResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List decryptBlobResponseDescriptor =
    $convert.base64Decode(
        'ChNEZWNyeXB0QmxvYlJlc3BvbnNlEhwKCXBsYWludGV4dBgBIAEoDFIJcGxhaW50ZXh0');
