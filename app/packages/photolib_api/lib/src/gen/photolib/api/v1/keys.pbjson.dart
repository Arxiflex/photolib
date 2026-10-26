// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/keys.proto.

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
    as $0;

@$core.Deprecated('Use unlockKindDescriptor instead')
const UnlockKind$json = {
  '1': 'UnlockKind',
  '2': [
    {'1': 'UNLOCK_KIND_UNSPECIFIED', '2': 0},
    {'1': 'UNLOCK_KIND_PASSWORD', '2': 1},
    {'1': 'UNLOCK_KIND_RECOVERY', '2': 2},
  ],
};

/// Descriptor for `UnlockKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List unlockKindDescriptor = $convert.base64Decode(
    'CgpVbmxvY2tLaW5kEhsKF1VOTE9DS19LSU5EX1VOU1BFQ0lGSUVEEAASGAoUVU5MT0NLX0tJTk'
    'RfUEFTU1dPUkQQARIYChRVTkxPQ0tfS0lORF9SRUNPVkVSWRAC');

@$core.Deprecated('Use unlockPathDescriptor instead')
const UnlockPath$json = {
  '1': 'UnlockPath',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.photolib.api.v1.UnlockKind',
      '10': 'kind'
    },
    {'1': 'wrap', '3': 2, '4': 1, '5': 12, '10': 'wrap'},
    {'1': 'params', '3': 3, '4': 1, '5': 12, '10': 'params'},
    {
      '1': 'created_at',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
  ],
};

/// Descriptor for `UnlockPath`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List unlockPathDescriptor = $convert.base64Decode(
    'CgpVbmxvY2tQYXRoEi8KBGtpbmQYASABKA4yGy5waG90b2xpYi5hcGkudjEuVW5sb2NrS2luZF'
    'IEa2luZBISCgR3cmFwGAIgASgMUgR3cmFwEhYKBnBhcmFtcxgDIAEoDFIGcGFyYW1zEjkKCmNy'
    'ZWF0ZWRfYXQYBCABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgljcmVhdGVkQXQ=');

@$core.Deprecated('Use accountKeysDescriptor instead')
const AccountKeys$json = {
  '1': 'AccountKeys',
  '2': [
    {'1': 'identity', '3': 1, '4': 1, '5': 12, '10': 'identity'},
    {'1': 'signing_key', '3': 2, '4': 1, '5': 12, '10': 'signingKey'},
    {'1': 'decryption_key', '3': 3, '4': 1, '5': 12, '10': 'decryptionKey'},
    {
      '1': 'paths',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.UnlockPath',
      '10': 'paths'
    },
    {
      '1': 'recovery_verified_at',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'recoveryVerifiedAt'
    },
    {
      '1': 'drill_due_at',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'drillDueAt'
    },
    {'1': 'ready', '3': 7, '4': 1, '5': 8, '10': 'ready'},
  ],
};

/// Descriptor for `AccountKeys`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accountKeysDescriptor = $convert.base64Decode(
    'CgtBY2NvdW50S2V5cxIaCghpZGVudGl0eRgBIAEoDFIIaWRlbnRpdHkSHwoLc2lnbmluZ19rZX'
    'kYAiABKAxSCnNpZ25pbmdLZXkSJQoOZGVjcnlwdGlvbl9rZXkYAyABKAxSDWRlY3J5cHRpb25L'
    'ZXkSMQoFcGF0aHMYBCADKAsyGy5waG90b2xpYi5hcGkudjEuVW5sb2NrUGF0aFIFcGF0aHMSTA'
    'oUcmVjb3ZlcnlfdmVyaWZpZWRfYXQYBSABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1w'
    'UhJyZWNvdmVyeVZlcmlmaWVkQXQSPAoMZHJpbGxfZHVlX2F0GAYgASgLMhouZ29vZ2xlLnByb3'
    'RvYnVmLlRpbWVzdGFtcFIKZHJpbGxEdWVBdBIUCgVyZWFkeRgHIAEoCFIFcmVhZHk=');

@$core.Deprecated('Use getKeysRequestDescriptor instead')
const GetKeysRequest$json = {
  '1': 'GetKeysRequest',
};

/// Descriptor for `GetKeysRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getKeysRequestDescriptor =
    $convert.base64Decode('Cg5HZXRLZXlzUmVxdWVzdA==');

@$core.Deprecated('Use getKeysResponseDescriptor instead')
const GetKeysResponse$json = {
  '1': 'GetKeysResponse',
  '2': [
    {
      '1': 'keys',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.AccountKeys',
      '10': 'keys'
    },
    {'1': 'password', '3': 2, '4': 1, '5': 8, '10': 'password'},
    {'1': 'user_id', '3': 3, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `GetKeysResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getKeysResponseDescriptor = $convert.base64Decode(
    'Cg9HZXRLZXlzUmVzcG9uc2USMAoEa2V5cxgBIAEoCzIcLnBob3RvbGliLmFwaS52MS5BY2NvdW'
    '50S2V5c1IEa2V5cxIaCghwYXNzd29yZBgCIAEoCFIIcGFzc3dvcmQSFwoHdXNlcl9pZBgDIAEo'
    'CVIGdXNlcklk');

@$core.Deprecated('Use createKeysRequestDescriptor instead')
const CreateKeysRequest$json = {
  '1': 'CreateKeysRequest',
  '2': [
    {'1': 'identity', '3': 1, '4': 1, '5': 12, '10': 'identity'},
    {'1': 'signing_key', '3': 2, '4': 1, '5': 12, '10': 'signingKey'},
    {'1': 'decryption_key', '3': 3, '4': 1, '5': 12, '10': 'decryptionKey'},
    {
      '1': 'paths',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.UnlockPath',
      '10': 'paths'
    },
  ],
};

/// Descriptor for `CreateKeysRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createKeysRequestDescriptor = $convert.base64Decode(
    'ChFDcmVhdGVLZXlzUmVxdWVzdBIaCghpZGVudGl0eRgBIAEoDFIIaWRlbnRpdHkSHwoLc2lnbm'
    'luZ19rZXkYAiABKAxSCnNpZ25pbmdLZXkSJQoOZGVjcnlwdGlvbl9rZXkYAyABKAxSDWRlY3J5'
    'cHRpb25LZXkSMQoFcGF0aHMYBCADKAsyGy5waG90b2xpYi5hcGkudjEuVW5sb2NrUGF0aFIFcG'
    'F0aHM=');

@$core.Deprecated('Use createKeysResponseDescriptor instead')
const CreateKeysResponse$json = {
  '1': 'CreateKeysResponse',
  '2': [
    {
      '1': 'keys',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.AccountKeys',
      '10': 'keys'
    },
  ],
};

/// Descriptor for `CreateKeysResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createKeysResponseDescriptor = $convert.base64Decode(
    'ChJDcmVhdGVLZXlzUmVzcG9uc2USMAoEa2V5cxgBIAEoCzIcLnBob3RvbGliLmFwaS52MS5BY2'
    'NvdW50S2V5c1IEa2V5cw==');

@$core.Deprecated('Use putUnlockPathRequestDescriptor instead')
const PutUnlockPathRequest$json = {
  '1': 'PutUnlockPathRequest',
  '2': [
    {
      '1': 'path',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.UnlockPath',
      '10': 'path'
    },
  ],
};

/// Descriptor for `PutUnlockPathRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putUnlockPathRequestDescriptor = $convert.base64Decode(
    'ChRQdXRVbmxvY2tQYXRoUmVxdWVzdBIvCgRwYXRoGAEgASgLMhsucGhvdG9saWIuYXBpLnYxLl'
    'VubG9ja1BhdGhSBHBhdGg=');

@$core.Deprecated('Use putUnlockPathResponseDescriptor instead')
const PutUnlockPathResponse$json = {
  '1': 'PutUnlockPathResponse',
  '2': [
    {
      '1': 'keys',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.AccountKeys',
      '10': 'keys'
    },
  ],
};

/// Descriptor for `PutUnlockPathResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List putUnlockPathResponseDescriptor = $convert.base64Decode(
    'ChVQdXRVbmxvY2tQYXRoUmVzcG9uc2USMAoEa2V5cxgBIAEoCzIcLnBob3RvbGliLmFwaS52MS'
    '5BY2NvdW50S2V5c1IEa2V5cw==');

@$core.Deprecated('Use verifyRecoveryKitRequestDescriptor instead')
const VerifyRecoveryKitRequest$json = {
  '1': 'VerifyRecoveryKitRequest',
  '2': [
    {'1': 'kit_id', '3': 1, '4': 1, '5': 12, '10': 'kitId'},
  ],
};

/// Descriptor for `VerifyRecoveryKitRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verifyRecoveryKitRequestDescriptor =
    $convert.base64Decode(
        'ChhWZXJpZnlSZWNvdmVyeUtpdFJlcXVlc3QSFQoGa2l0X2lkGAEgASgMUgVraXRJZA==');

@$core.Deprecated('Use verifyRecoveryKitResponseDescriptor instead')
const VerifyRecoveryKitResponse$json = {
  '1': 'VerifyRecoveryKitResponse',
  '2': [
    {
      '1': 'keys',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.AccountKeys',
      '10': 'keys'
    },
  ],
};

/// Descriptor for `VerifyRecoveryKitResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verifyRecoveryKitResponseDescriptor =
    $convert.base64Decode(
        'ChlWZXJpZnlSZWNvdmVyeUtpdFJlc3BvbnNlEjAKBGtleXMYASABKAsyHC5waG90b2xpYi5hcG'
        'kudjEuQWNjb3VudEtleXNSBGtleXM=');

const $core.Map<$core.String, $core.dynamic> KeyServiceBase$json = {
  '1': 'KeyService',
  '2': [
    {
      '1': 'GetKeys',
      '2': '.photolib.api.v1.GetKeysRequest',
      '3': '.photolib.api.v1.GetKeysResponse'
    },
    {
      '1': 'CreateKeys',
      '2': '.photolib.api.v1.CreateKeysRequest',
      '3': '.photolib.api.v1.CreateKeysResponse'
    },
    {
      '1': 'PutUnlockPath',
      '2': '.photolib.api.v1.PutUnlockPathRequest',
      '3': '.photolib.api.v1.PutUnlockPathResponse'
    },
    {
      '1': 'VerifyRecoveryKit',
      '2': '.photolib.api.v1.VerifyRecoveryKitRequest',
      '3': '.photolib.api.v1.VerifyRecoveryKitResponse'
    },
  ],
};

@$core.Deprecated('Use keyServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    KeyServiceBase$messageJson = {
  '.photolib.api.v1.GetKeysRequest': GetKeysRequest$json,
  '.photolib.api.v1.GetKeysResponse': GetKeysResponse$json,
  '.photolib.api.v1.AccountKeys': AccountKeys$json,
  '.photolib.api.v1.UnlockPath': UnlockPath$json,
  '.google.protobuf.Timestamp': $0.Timestamp$json,
  '.photolib.api.v1.CreateKeysRequest': CreateKeysRequest$json,
  '.photolib.api.v1.CreateKeysResponse': CreateKeysResponse$json,
  '.photolib.api.v1.PutUnlockPathRequest': PutUnlockPathRequest$json,
  '.photolib.api.v1.PutUnlockPathResponse': PutUnlockPathResponse$json,
  '.photolib.api.v1.VerifyRecoveryKitRequest': VerifyRecoveryKitRequest$json,
  '.photolib.api.v1.VerifyRecoveryKitResponse': VerifyRecoveryKitResponse$json,
};

/// Descriptor for `KeyService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List keyServiceDescriptor = $convert.base64Decode(
    'CgpLZXlTZXJ2aWNlEkwKB0dldEtleXMSHy5waG90b2xpYi5hcGkudjEuR2V0S2V5c1JlcXVlc3'
    'QaIC5waG90b2xpYi5hcGkudjEuR2V0S2V5c1Jlc3BvbnNlElUKCkNyZWF0ZUtleXMSIi5waG90'
    'b2xpYi5hcGkudjEuQ3JlYXRlS2V5c1JlcXVlc3QaIy5waG90b2xpYi5hcGkudjEuQ3JlYXRlS2'
    'V5c1Jlc3BvbnNlEl4KDVB1dFVubG9ja1BhdGgSJS5waG90b2xpYi5hcGkudjEuUHV0VW5sb2Nr'
    'UGF0aFJlcXVlc3QaJi5waG90b2xpYi5hcGkudjEuUHV0VW5sb2NrUGF0aFJlc3BvbnNlEmoKEV'
    'ZlcmlmeVJlY292ZXJ5S2l0EikucGhvdG9saWIuYXBpLnYxLlZlcmlmeVJlY292ZXJ5S2l0UmVx'
    'dWVzdBoqLnBob3RvbGliLmFwaS52MS5WZXJpZnlSZWNvdmVyeUtpdFJlc3BvbnNl');
