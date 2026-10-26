// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/share.proto.

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

@$core.Deprecated('Use keyPairDescriptor instead')
const KeyPair$json = {
  '1': 'KeyPair',
  '2': [
    {'1': 'KEY_PAIR_UNSPECIFIED', '2': 0},
    {'1': 'KEY_PAIR_ED25519', '2': 1},
    {'1': 'KEY_PAIR_X_WING', '2': 2},
  ],
};

/// Descriptor for `KeyPair`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List keyPairDescriptor = $convert.base64Decode(
    'CgdLZXlQYWlyEhgKFEtFWV9QQUlSX1VOU1BFQ0lGSUVEEAASFAoQS0VZX1BBSVJfRUQyNTUxOR'
    'ABEhMKD0tFWV9QQUlSX1hfV0lORxAC');

@$core.Deprecated('Use publicKeyRequestDescriptor instead')
const PublicKeyRequest$json = {
  '1': 'PublicKeyRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {
      '1': 'key_pair',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.KeyPair',
      '10': 'keyPair'
    },
  ],
};

/// Descriptor for `PublicKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List publicKeyRequestDescriptor = $convert.base64Decode(
    'ChBQdWJsaWNLZXlSZXF1ZXN0EhAKA2tleRgBIAEoDVIDa2V5EjYKCGtleV9wYWlyGAIgASgOMh'
    'sucGhvdG9saWIua2VybmVsLnYxLktleVBhaXJSB2tleVBhaXI=');

@$core.Deprecated('Use publicKeyResponseDescriptor instead')
const PublicKeyResponse$json = {
  '1': 'PublicKeyResponse',
  '2': [
    {'1': 'public_key', '3': 1, '4': 1, '5': 12, '10': 'publicKey'},
    {'1': 'key_id', '3': 2, '4': 1, '5': 12, '10': 'keyId'},
  ],
};

/// Descriptor for `PublicKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List publicKeyResponseDescriptor = $convert.base64Decode(
    'ChFQdWJsaWNLZXlSZXNwb25zZRIdCgpwdWJsaWNfa2V5GAEgASgMUglwdWJsaWNLZXkSFQoGa2'
    'V5X2lkGAIgASgMUgVrZXlJZA==');

@$core.Deprecated('Use shareKeyRequestDescriptor instead')
const ShareKeyRequest$json = {
  '1': 'ShareKeyRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'public_key', '3': 2, '4': 1, '5': 12, '10': 'publicKey'},
    {'1': 'wrapped_type', '3': 3, '4': 1, '5': 13, '10': 'wrappedType'},
    {
      '1': 'context',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.WrapContext',
      '10': 'context'
    },
    {'1': 'sender_key_id', '3': 5, '4': 1, '5': 12, '10': 'senderKeyId'},
    {'1': 'randomness', '3': 6, '4': 1, '5': 12, '10': 'randomness'},
  ],
};

/// Descriptor for `ShareKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List shareKeyRequestDescriptor = $convert.base64Decode(
    'Cg9TaGFyZUtleVJlcXVlc3QSEAoDa2V5GAEgASgNUgNrZXkSHQoKcHVibGljX2tleRgCIAEoDF'
    'IJcHVibGljS2V5EiEKDHdyYXBwZWRfdHlwZRgDIAEoDVILd3JhcHBlZFR5cGUSOQoHY29udGV4'
    'dBgEIAEoCzIfLnBob3RvbGliLmtlcm5lbC52MS5XcmFwQ29udGV4dFIHY29udGV4dBIiCg1zZW'
    '5kZXJfa2V5X2lkGAUgASgMUgtzZW5kZXJLZXlJZBIeCgpyYW5kb21uZXNzGAYgASgMUgpyYW5k'
    'b21uZXNz');

@$core.Deprecated('Use shareKeyResponseDescriptor instead')
const ShareKeyResponse$json = {
  '1': 'ShareKeyResponse',
  '2': [
    {'1': 'wrap', '3': 1, '4': 1, '5': 12, '10': 'wrap'},
  ],
};

/// Descriptor for `ShareKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List shareKeyResponseDescriptor = $convert
    .base64Decode('ChBTaGFyZUtleVJlc3BvbnNlEhIKBHdyYXAYASABKAxSBHdyYXA=');

@$core.Deprecated('Use acceptKeyRequestDescriptor instead')
const AcceptKeyRequest$json = {
  '1': 'AcceptKeyRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
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
    {'1': 'signed_sha256', '3': 5, '4': 1, '5': 12, '10': 'signedSha256'},
  ],
};

/// Descriptor for `AcceptKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List acceptKeyRequestDescriptor = $convert.base64Decode(
    'ChBBY2NlcHRLZXlSZXF1ZXN0EhAKA2tleRgBIAEoDVIDa2V5EiEKDHdyYXBwZWRfdHlwZRgCIA'
    'EoDVILd3JhcHBlZFR5cGUSOQoHY29udGV4dBgDIAEoCzIfLnBob3RvbGliLmtlcm5lbC52MS5X'
    'cmFwQ29udGV4dFIHY29udGV4dBISCgR3cmFwGAQgASgMUgR3cmFwEiMKDXNpZ25lZF9zaGEyNT'
    'YYBSABKAxSDHNpZ25lZFNoYTI1Ng==');
