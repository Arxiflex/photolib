// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/opaque.proto.

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

@$core.Deprecated('Use opaqueRegisterRequestDescriptor instead')
const OpaqueRegisterRequest$json = {
  '1': 'OpaqueRegisterRequest',
  '2': [
    {'1': 'password', '3': 1, '4': 1, '5': 9, '10': 'password'},
    {'1': 'params', '3': 2, '4': 1, '5': 12, '10': 'params'},
    {'1': 'randomness', '3': 3, '4': 1, '5': 12, '10': 'randomness'},
    {'1': 'response', '3': 4, '4': 1, '5': 12, '10': 'response'},
  ],
};

/// Descriptor for `OpaqueRegisterRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List opaqueRegisterRequestDescriptor = $convert.base64Decode(
    'ChVPcGFxdWVSZWdpc3RlclJlcXVlc3QSGgoIcGFzc3dvcmQYASABKAlSCHBhc3N3b3JkEhYKBn'
    'BhcmFtcxgCIAEoDFIGcGFyYW1zEh4KCnJhbmRvbW5lc3MYAyABKAxSCnJhbmRvbW5lc3MSGgoI'
    'cmVzcG9uc2UYBCABKAxSCHJlc3BvbnNl');

@$core.Deprecated('Use opaqueLoginRequestDescriptor instead')
const OpaqueLoginRequest$json = {
  '1': 'OpaqueLoginRequest',
  '2': [
    {'1': 'password', '3': 1, '4': 1, '5': 9, '10': 'password'},
    {'1': 'params', '3': 2, '4': 1, '5': 12, '10': 'params'},
    {'1': 'randomness', '3': 3, '4': 1, '5': 12, '10': 'randomness'},
    {'1': 'ke2', '3': 4, '4': 1, '5': 12, '10': 'ke2'},
  ],
};

/// Descriptor for `OpaqueLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List opaqueLoginRequestDescriptor = $convert.base64Decode(
    'ChJPcGFxdWVMb2dpblJlcXVlc3QSGgoIcGFzc3dvcmQYASABKAlSCHBhc3N3b3JkEhYKBnBhcm'
    'FtcxgCIAEoDFIGcGFyYW1zEh4KCnJhbmRvbW5lc3MYAyABKAxSCnJhbmRvbW5lc3MSEAoDa2Uy'
    'GAQgASgMUgNrZTI=');

@$core.Deprecated('Use opaqueClientResponseDescriptor instead')
const OpaqueClientResponse$json = {
  '1': 'OpaqueClientResponse',
  '2': [
    {'1': 'message', '3': 1, '4': 1, '5': 12, '10': 'message'},
    {'1': 'session_key', '3': 2, '4': 1, '5': 12, '10': 'sessionKey'},
    {'1': 'export_key', '3': 3, '4': 1, '5': 12, '10': 'exportKey'},
  ],
};

/// Descriptor for `OpaqueClientResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List opaqueClientResponseDescriptor = $convert.base64Decode(
    'ChRPcGFxdWVDbGllbnRSZXNwb25zZRIYCgdtZXNzYWdlGAEgASgMUgdtZXNzYWdlEh8KC3Nlc3'
    'Npb25fa2V5GAIgASgMUgpzZXNzaW9uS2V5Eh0KCmV4cG9ydF9rZXkYAyABKAxSCWV4cG9ydEtl'
    'eQ==');

@$core.Deprecated('Use opaqueServerRegisterRequestDescriptor instead')
const OpaqueServerRegisterRequest$json = {
  '1': 'OpaqueServerRegisterRequest',
  '2': [
    {'1': 'oprf_seed', '3': 1, '4': 1, '5': 12, '10': 'oprfSeed'},
    {'1': 'private_key', '3': 2, '4': 1, '5': 12, '10': 'privateKey'},
    {'1': 'credential_id', '3': 3, '4': 1, '5': 12, '10': 'credentialId'},
    {'1': 'request', '3': 4, '4': 1, '5': 12, '10': 'request'},
  ],
};

/// Descriptor for `OpaqueServerRegisterRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List opaqueServerRegisterRequestDescriptor =
    $convert.base64Decode(
        'ChtPcGFxdWVTZXJ2ZXJSZWdpc3RlclJlcXVlc3QSGwoJb3ByZl9zZWVkGAEgASgMUghvcHJmU2'
        'VlZBIfCgtwcml2YXRlX2tleRgCIAEoDFIKcHJpdmF0ZUtleRIjCg1jcmVkZW50aWFsX2lkGAMg'
        'ASgMUgxjcmVkZW50aWFsSWQSGAoHcmVxdWVzdBgEIAEoDFIHcmVxdWVzdA==');

@$core.Deprecated('Use opaqueServerLoginRequestDescriptor instead')
const OpaqueServerLoginRequest$json = {
  '1': 'OpaqueServerLoginRequest',
  '2': [
    {'1': 'oprf_seed', '3': 1, '4': 1, '5': 12, '10': 'oprfSeed'},
    {'1': 'private_key', '3': 2, '4': 1, '5': 12, '10': 'privateKey'},
    {'1': 'credential_id', '3': 3, '4': 1, '5': 12, '10': 'credentialId'},
    {'1': 'record', '3': 4, '4': 1, '5': 12, '10': 'record'},
    {'1': 'randomness', '3': 5, '4': 1, '5': 12, '10': 'randomness'},
    {'1': 'ke1', '3': 6, '4': 1, '5': 12, '10': 'ke1'},
    {'1': 'ke3', '3': 7, '4': 1, '5': 12, '10': 'ke3'},
  ],
};

/// Descriptor for `OpaqueServerLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List opaqueServerLoginRequestDescriptor = $convert.base64Decode(
    'ChhPcGFxdWVTZXJ2ZXJMb2dpblJlcXVlc3QSGwoJb3ByZl9zZWVkGAEgASgMUghvcHJmU2VlZB'
    'IfCgtwcml2YXRlX2tleRgCIAEoDFIKcHJpdmF0ZUtleRIjCg1jcmVkZW50aWFsX2lkGAMgASgM'
    'UgxjcmVkZW50aWFsSWQSFgoGcmVjb3JkGAQgASgMUgZyZWNvcmQSHgoKcmFuZG9tbmVzcxgFIA'
    'EoDFIKcmFuZG9tbmVzcxIQCgNrZTEYBiABKAxSA2tlMRIQCgNrZTMYByABKAxSA2tlMw==');

@$core.Deprecated('Use opaqueServerResponseDescriptor instead')
const OpaqueServerResponse$json = {
  '1': 'OpaqueServerResponse',
  '2': [
    {'1': 'message', '3': 1, '4': 1, '5': 12, '10': 'message'},
    {'1': 'session_key', '3': 2, '4': 1, '5': 12, '10': 'sessionKey'},
  ],
};

/// Descriptor for `OpaqueServerResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List opaqueServerResponseDescriptor = $convert.base64Decode(
    'ChRPcGFxdWVTZXJ2ZXJSZXNwb25zZRIYCgdtZXNzYWdlGAEgASgMUgdtZXNzYWdlEh8KC3Nlc3'
    'Npb25fa2V5GAIgASgMUgpzZXNzaW9uS2V5');
