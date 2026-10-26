// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/keys.proto.

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

@$core.Deprecated('Use kdfPolicyDescriptor instead')
const KdfPolicy$json = {
  '1': 'KdfPolicy',
  '2': [
    {'1': 'KDF_POLICY_UNSPECIFIED', '2': 0},
    {'1': 'KDF_POLICY_ACCOUNT', '2': 1},
    {'1': 'KDF_POLICY_DEVICE', '2': 2},
  ],
};

/// Descriptor for `KdfPolicy`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List kdfPolicyDescriptor = $convert.base64Decode(
    'CglLZGZQb2xpY3kSGgoWS0RGX1BPTElDWV9VTlNQRUNJRklFRBAAEhYKEktERl9QT0xJQ1lfQU'
    'NDT1VOVBABEhUKEUtERl9QT0xJQ1lfREVWSUNFEAI=');

@$core.Deprecated('Use importKeyRequestDescriptor instead')
const ImportKeyRequest$json = {
  '1': 'ImportKeyRequest',
  '2': [
    {'1': 'secret', '3': 1, '4': 1, '5': 12, '10': 'secret'},
  ],
};

/// Descriptor for `ImportKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List importKeyRequestDescriptor = $convert
    .base64Decode('ChBJbXBvcnRLZXlSZXF1ZXN0EhYKBnNlY3JldBgBIAEoDFIGc2VjcmV0');

@$core.Deprecated('Use keyResponseDescriptor instead')
const KeyResponse$json = {
  '1': 'KeyResponse',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'key_id', '3': 2, '4': 1, '5': 12, '10': 'keyId'},
  ],
};

/// Descriptor for `KeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyResponseDescriptor = $convert.base64Decode(
    'CgtLZXlSZXNwb25zZRIQCgNrZXkYASABKA1SA2tleRIVCgZrZXlfaWQYAiABKAxSBWtleUlk');

@$core.Deprecated('Use dropKeyRequestDescriptor instead')
const DropKeyRequest$json = {
  '1': 'DropKeyRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
  ],
};

/// Descriptor for `DropKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dropKeyRequestDescriptor =
    $convert.base64Decode('Cg5Ecm9wS2V5UmVxdWVzdBIQCgNrZXkYASABKA1SA2tleQ==');

@$core.Deprecated('Use dropKeyResponseDescriptor instead')
const DropKeyResponse$json = {
  '1': 'DropKeyResponse',
};

/// Descriptor for `DropKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dropKeyResponseDescriptor =
    $convert.base64Decode('Cg9Ecm9wS2V5UmVzcG9uc2U=');

@$core.Deprecated('Use deriveKeyRequestDescriptor instead')
const DeriveKeyRequest$json = {
  '1': 'DeriveKeyRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'label', '3': 2, '4': 1, '5': 9, '10': 'label'},
    {'1': 'context', '3': 3, '4': 1, '5': 12, '10': 'context'},
  ],
};

/// Descriptor for `DeriveKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deriveKeyRequestDescriptor = $convert.base64Decode(
    'ChBEZXJpdmVLZXlSZXF1ZXN0EhAKA2tleRgBIAEoDVIDa2V5EhQKBWxhYmVsGAIgASgJUgVsYW'
    'JlbBIYCgdjb250ZXh0GAMgASgMUgdjb250ZXh0');

@$core.Deprecated('Use derivePasswordKeyRequestDescriptor instead')
const DerivePasswordKeyRequest$json = {
  '1': 'DerivePasswordKeyRequest',
  '2': [
    {'1': 'password', '3': 1, '4': 1, '5': 9, '10': 'password'},
    {'1': 'params', '3': 2, '4': 1, '5': 12, '10': 'params'},
    {'1': 'label', '3': 3, '4': 1, '5': 9, '10': 'label'},
    {'1': 'hardware', '3': 4, '4': 1, '5': 12, '10': 'hardware'},
  ],
};

/// Descriptor for `DerivePasswordKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List derivePasswordKeyRequestDescriptor = $convert.base64Decode(
    'ChhEZXJpdmVQYXNzd29yZEtleVJlcXVlc3QSGgoIcGFzc3dvcmQYASABKAlSCHBhc3N3b3JkEh'
    'YKBnBhcmFtcxgCIAEoDFIGcGFyYW1zEhQKBWxhYmVsGAMgASgJUgVsYWJlbBIaCghoYXJkd2Fy'
    'ZRgEIAEoDFIIaGFyZHdhcmU=');

@$core.Deprecated('Use checkKdfParamsRequestDescriptor instead')
const CheckKdfParamsRequest$json = {
  '1': 'CheckKdfParamsRequest',
  '2': [
    {'1': 'params', '3': 1, '4': 1, '5': 12, '10': 'params'},
    {
      '1': 'policy',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.KdfPolicy',
      '10': 'policy'
    },
  ],
};

/// Descriptor for `CheckKdfParamsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkKdfParamsRequestDescriptor = $convert.base64Decode(
    'ChVDaGVja0tkZlBhcmFtc1JlcXVlc3QSFgoGcGFyYW1zGAEgASgMUgZwYXJhbXMSNQoGcG9saW'
    'N5GAIgASgOMh0ucGhvdG9saWIua2VybmVsLnYxLktkZlBvbGljeVIGcG9saWN5');

@$core.Deprecated('Use checkKdfParamsResponseDescriptor instead')
const CheckKdfParamsResponse$json = {
  '1': 'CheckKdfParamsResponse',
};

/// Descriptor for `CheckKdfParamsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkKdfParamsResponseDescriptor =
    $convert.base64Decode('ChZDaGVja0tkZlBhcmFtc1Jlc3BvbnNl');

@$core.Deprecated('Use wrapContextDescriptor instead')
const WrapContext$json = {
  '1': 'WrapContext',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'container_id', '3': 2, '4': 1, '5': 12, '10': 'containerId'},
    {'1': 'subject_id', '3': 3, '4': 1, '5': 12, '10': 'subjectId'},
    {'1': 'number', '3': 4, '4': 1, '5': 13, '10': 'number'},
  ],
};

/// Descriptor for `WrapContext`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wrapContextDescriptor = $convert.base64Decode(
    'CgtXcmFwQ29udGV4dBIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySWQSIQoMY29udGFpbmVyX2lkGA'
    'IgASgMUgtjb250YWluZXJJZBIdCgpzdWJqZWN0X2lkGAMgASgMUglzdWJqZWN0SWQSFgoGbnVt'
    'YmVyGAQgASgNUgZudW1iZXI=');

@$core.Deprecated('Use wrapKeyRequestDescriptor instead')
const WrapKeyRequest$json = {
  '1': 'WrapKeyRequest',
  '2': [
    {'1': 'wrapping_key', '3': 1, '4': 1, '5': 13, '10': 'wrappingKey'},
    {'1': 'key', '3': 2, '4': 1, '5': 13, '10': 'key'},
    {'1': 'wrapped_type', '3': 3, '4': 1, '5': 13, '10': 'wrappedType'},
    {
      '1': 'context',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.WrapContext',
      '10': 'context'
    },
    {'1': 'nonce', '3': 5, '4': 1, '5': 12, '10': 'nonce'},
  ],
};

/// Descriptor for `WrapKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wrapKeyRequestDescriptor = $convert.base64Decode(
    'Cg5XcmFwS2V5UmVxdWVzdBIhCgx3cmFwcGluZ19rZXkYASABKA1SC3dyYXBwaW5nS2V5EhAKA2'
    'tleRgCIAEoDVIDa2V5EiEKDHdyYXBwZWRfdHlwZRgDIAEoDVILd3JhcHBlZFR5cGUSOQoHY29u'
    'dGV4dBgEIAEoCzIfLnBob3RvbGliLmtlcm5lbC52MS5XcmFwQ29udGV4dFIHY29udGV4dBIUCg'
    'Vub25jZRgFIAEoDFIFbm9uY2U=');

@$core.Deprecated('Use wrapKeyResponseDescriptor instead')
const WrapKeyResponse$json = {
  '1': 'WrapKeyResponse',
  '2': [
    {'1': 'wrap', '3': 1, '4': 1, '5': 12, '10': 'wrap'},
  ],
};

/// Descriptor for `WrapKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wrapKeyResponseDescriptor = $convert
    .base64Decode('Cg9XcmFwS2V5UmVzcG9uc2USEgoEd3JhcBgBIAEoDFIEd3JhcA==');

@$core.Deprecated('Use unwrapKeyRequestDescriptor instead')
const UnwrapKeyRequest$json = {
  '1': 'UnwrapKeyRequest',
  '2': [
    {'1': 'wrapping_key', '3': 1, '4': 1, '5': 13, '10': 'wrappingKey'},
    {'1': 'wrapped_type', '3': 2, '4': 1, '5': 13, '10': 'wrappedType'},
    {
      '1': 'context',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.WrapContext',
      '10': 'context'
    },
    {'1': 'wrap', '3': 4, '4': 1, '5': 12, '10': 'wrap'},
  ],
};

/// Descriptor for `UnwrapKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List unwrapKeyRequestDescriptor = $convert.base64Decode(
    'ChBVbndyYXBLZXlSZXF1ZXN0EiEKDHdyYXBwaW5nX2tleRgBIAEoDVILd3JhcHBpbmdLZXkSIQ'
    'oMd3JhcHBlZF90eXBlGAIgASgNUgt3cmFwcGVkVHlwZRI5Cgdjb250ZXh0GAMgASgLMh8ucGhv'
    'dG9saWIua2VybmVsLnYxLldyYXBDb250ZXh0Ugdjb250ZXh0EhIKBHdyYXAYBCABKAxSBHdyYX'
    'A=');

@$core.Deprecated('Use dedupTokenRequestDescriptor instead')
const DedupTokenRequest$json = {
  '1': 'DedupTokenRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'sha256', '3': 2, '4': 1, '5': 12, '10': 'sha256'},
  ],
};

/// Descriptor for `DedupTokenRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dedupTokenRequestDescriptor = $convert.base64Decode(
    'ChFEZWR1cFRva2VuUmVxdWVzdBIQCgNrZXkYASABKA1SA2tleRIWCgZzaGEyNTYYAiABKAxSBn'
    'NoYTI1Ng==');

@$core.Deprecated('Use dedupTokenResponseDescriptor instead')
const DedupTokenResponse$json = {
  '1': 'DedupTokenResponse',
  '2': [
    {'1': 'token', '3': 1, '4': 1, '5': 12, '10': 'token'},
  ],
};

/// Descriptor for `DedupTokenResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dedupTokenResponseDescriptor = $convert
    .base64Decode('ChJEZWR1cFRva2VuUmVzcG9uc2USFAoFdG9rZW4YASABKAxSBXRva2Vu');

@$core.Deprecated('Use linkKeysRequestDescriptor instead')
const LinkKeysRequest$json = {
  '1': 'LinkKeysRequest',
  '2': [
    {'1': 'secret', '3': 1, '4': 1, '5': 13, '10': 'secret'},
    {'1': 'link_id', '3': 2, '4': 1, '5': 12, '10': 'linkId'},
    {'1': 'password_hash', '3': 3, '4': 1, '5': 13, '10': 'passwordHash'},
  ],
};

/// Descriptor for `LinkKeysRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linkKeysRequestDescriptor = $convert.base64Decode(
    'Cg9MaW5rS2V5c1JlcXVlc3QSFgoGc2VjcmV0GAEgASgNUgZzZWNyZXQSFwoHbGlua19pZBgCIA'
    'EoDFIGbGlua0lkEiMKDXBhc3N3b3JkX2hhc2gYAyABKA1SDHBhc3N3b3JkSGFzaA==');

@$core.Deprecated('Use linkKeysResponseDescriptor instead')
const LinkKeysResponse$json = {
  '1': 'LinkKeysResponse',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'key_id', '3': 2, '4': 1, '5': 12, '10': 'keyId'},
    {'1': 'verifier', '3': 3, '4': 1, '5': 12, '10': 'verifier'},
  ],
};

/// Descriptor for `LinkKeysResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linkKeysResponseDescriptor = $convert.base64Decode(
    'ChBMaW5rS2V5c1Jlc3BvbnNlEhAKA2tleRgBIAEoDVIDa2V5EhUKBmtleV9pZBgCIAEoDFIFa2'
    'V5SWQSGgoIdmVyaWZpZXIYAyABKAxSCHZlcmlmaWVy');

@$core.Deprecated('Use linkFragmentRequestDescriptor instead')
const LinkFragmentRequest$json = {
  '1': 'LinkFragmentRequest',
  '2': [
    {'1': 'link_id', '3': 1, '4': 1, '5': 12, '10': 'linkId'},
    {'1': 'secret', '3': 2, '4': 1, '5': 12, '10': 'secret'},
    {'1': 'password', '3': 3, '4': 1, '5': 8, '10': 'password'},
    {'1': 'manifest', '3': 4, '4': 1, '5': 12, '10': 'manifest'},
  ],
};

/// Descriptor for `LinkFragmentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linkFragmentRequestDescriptor = $convert.base64Decode(
    'ChNMaW5rRnJhZ21lbnRSZXF1ZXN0EhcKB2xpbmtfaWQYASABKAxSBmxpbmtJZBIWCgZzZWNyZX'
    'QYAiABKAxSBnNlY3JldBIaCghwYXNzd29yZBgDIAEoCFIIcGFzc3dvcmQSGgoIbWFuaWZlc3QY'
    'BCABKAxSCG1hbmlmZXN0');

@$core.Deprecated('Use linkFragmentResponseDescriptor instead')
const LinkFragmentResponse$json = {
  '1': 'LinkFragmentResponse',
  '2': [
    {'1': 'fragment', '3': 1, '4': 1, '5': 9, '10': 'fragment'},
  ],
};

/// Descriptor for `LinkFragmentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linkFragmentResponseDescriptor =
    $convert.base64Decode(
        'ChRMaW5rRnJhZ21lbnRSZXNwb25zZRIaCghmcmFnbWVudBgBIAEoCVIIZnJhZ21lbnQ=');

@$core.Deprecated('Use recoveryPhraseRequestDescriptor instead')
const RecoveryPhraseRequest$json = {
  '1': 'RecoveryPhraseRequest',
  '2': [
    {'1': 'entropy', '3': 1, '4': 1, '5': 12, '10': 'entropy'},
  ],
};

/// Descriptor for `RecoveryPhraseRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recoveryPhraseRequestDescriptor =
    $convert.base64Decode(
        'ChVSZWNvdmVyeVBocmFzZVJlcXVlc3QSGAoHZW50cm9weRgBIAEoDFIHZW50cm9weQ==');

@$core.Deprecated('Use recoveryPhraseResponseDescriptor instead')
const RecoveryPhraseResponse$json = {
  '1': 'RecoveryPhraseResponse',
  '2': [
    {'1': 'phrase', '3': 1, '4': 1, '5': 9, '10': 'phrase'},
  ],
};

/// Descriptor for `RecoveryPhraseResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recoveryPhraseResponseDescriptor =
    $convert.base64Decode(
        'ChZSZWNvdmVyeVBocmFzZVJlc3BvbnNlEhYKBnBocmFzZRgBIAEoCVIGcGhyYXNl');

@$core.Deprecated('Use recoveryKeyRequestDescriptor instead')
const RecoveryKeyRequest$json = {
  '1': 'RecoveryKeyRequest',
  '2': [
    {'1': 'phrase', '3': 1, '4': 1, '5': 9, '10': 'phrase'},
  ],
};

/// Descriptor for `RecoveryKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recoveryKeyRequestDescriptor =
    $convert.base64Decode(
        'ChJSZWNvdmVyeUtleVJlcXVlc3QSFgoGcGhyYXNlGAEgASgJUgZwaHJhc2U=');
