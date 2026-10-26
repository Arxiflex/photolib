// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/logs.proto.

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

@$core.Deprecated('Use signEntryRequestDescriptor instead')
const SignEntryRequest$json = {
  '1': 'SignEntryRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'log_type', '3': 2, '4': 1, '5': 13, '10': 'logType'},
    {'1': 'body_type', '3': 3, '4': 1, '5': 13, '10': 'bodyType'},
    {'1': 'log_id', '3': 4, '4': 1, '5': 12, '10': 'logId'},
    {'1': 'seq', '3': 5, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'prev_hash', '3': 6, '4': 1, '5': 12, '10': 'prevHash'},
    {'1': 'time_ms', '3': 7, '4': 1, '5': 4, '10': 'timeMs'},
    {'1': 'body', '3': 8, '4': 1, '5': 12, '10': 'body'},
  ],
};

/// Descriptor for `SignEntryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signEntryRequestDescriptor = $convert.base64Decode(
    'ChBTaWduRW50cnlSZXF1ZXN0EhAKA2tleRgBIAEoDVIDa2V5EhkKCGxvZ190eXBlGAIgASgNUg'
    'dsb2dUeXBlEhsKCWJvZHlfdHlwZRgDIAEoDVIIYm9keVR5cGUSFQoGbG9nX2lkGAQgASgMUgVs'
    'b2dJZBIQCgNzZXEYBSABKARSA3NlcRIbCglwcmV2X2hhc2gYBiABKAxSCHByZXZIYXNoEhcKB3'
    'RpbWVfbXMYByABKARSBnRpbWVNcxISCgRib2R5GAggASgMUgRib2R5');

@$core.Deprecated('Use signEntryResponseDescriptor instead')
const SignEntryResponse$json = {
  '1': 'SignEntryResponse',
  '2': [
    {'1': 'entry', '3': 1, '4': 1, '5': 12, '10': 'entry'},
  ],
};

/// Descriptor for `SignEntryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signEntryResponseDescriptor = $convert
    .base64Decode('ChFTaWduRW50cnlSZXNwb25zZRIUCgVlbnRyeRgBIAEoDFIFZW50cnk=');

@$core.Deprecated('Use checkpointDescriptor instead')
const Checkpoint$json = {
  '1': 'Checkpoint',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'entry_hash', '3': 2, '4': 1, '5': 12, '10': 'entryHash'},
  ],
};

/// Descriptor for `Checkpoint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkpointDescriptor = $convert.base64Decode(
    'CgpDaGVja3BvaW50EhAKA3NlcRgBIAEoBFIDc2VxEh0KCmVudHJ5X2hhc2gYAiABKAxSCWVudH'
    'J5SGFzaA==');

@$core.Deprecated('Use signedWrapDescriptor instead')
const SignedWrap$json = {
  '1': 'SignedWrap',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'recipient_id', '3': 2, '4': 1, '5': 12, '10': 'recipientId'},
    {'1': 'sha256', '3': 3, '4': 1, '5': 12, '10': 'sha256'},
  ],
};

/// Descriptor for `SignedWrap`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signedWrapDescriptor = $convert.base64Decode(
    'CgpTaWduZWRXcmFwEhAKA3NlcRgBIAEoBFIDc2VxEiEKDHJlY2lwaWVudF9pZBgCIAEoDFILcm'
    'VjaXBpZW50SWQSFgoGc2hhMjU2GAMgASgMUgZzaGEyNTY=');

@$core.Deprecated('Use verifyIdentityLogRequestDescriptor instead')
const VerifyIdentityLogRequest$json = {
  '1': 'VerifyIdentityLogRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'entries', '3': 2, '4': 3, '5': 12, '10': 'entries'},
    {
      '1': 'checkpoint',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Checkpoint',
      '10': 'checkpoint'
    },
  ],
};

/// Descriptor for `VerifyIdentityLogRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verifyIdentityLogRequestDescriptor = $convert.base64Decode(
    'ChhWZXJpZnlJZGVudGl0eUxvZ1JlcXVlc3QSFwoHdXNlcl9pZBgBIAEoDFIGdXNlcklkEhgKB2'
    'VudHJpZXMYAiADKAxSB2VudHJpZXMSPgoKY2hlY2twb2ludBgDIAEoCzIeLnBob3RvbGliLmtl'
    'cm5lbC52MS5DaGVja3BvaW50UgpjaGVja3BvaW50');

@$core.Deprecated('Use deviceDescriptor instead')
const Device$json = {
  '1': 'Device',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'public_key', '3': 2, '4': 1, '5': 12, '10': 'publicKey'},
  ],
};

/// Descriptor for `Device`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceDescriptor = $convert.base64Decode(
    'CgZEZXZpY2USGwoJZGV2aWNlX2lkGAEgASgMUghkZXZpY2VJZBIdCgpwdWJsaWNfa2V5GAIgAS'
    'gMUglwdWJsaWNLZXk=');

@$core.Deprecated('Use verifyIdentityLogResponseDescriptor instead')
const VerifyIdentityLogResponse$json = {
  '1': 'VerifyIdentityLogResponse',
  '2': [
    {'1': 'signing_keys', '3': 1, '4': 3, '5': 12, '10': 'signingKeys'},
    {'1': 'encryption_key', '3': 2, '4': 1, '5': 12, '10': 'encryptionKey'},
    {
      '1': 'devices',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Device',
      '10': 'devices'
    },
    {'1': 'amk_generation', '3': 4, '4': 1, '5': 13, '10': 'amkGeneration'},
    {
      '1': 'head',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Checkpoint',
      '10': 'head'
    },
    {
      '1': 'wraps',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.SignedWrap',
      '10': 'wraps'
    },
  ],
};

/// Descriptor for `VerifyIdentityLogResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verifyIdentityLogResponseDescriptor = $convert.base64Decode(
    'ChlWZXJpZnlJZGVudGl0eUxvZ1Jlc3BvbnNlEiEKDHNpZ25pbmdfa2V5cxgBIAMoDFILc2lnbm'
    'luZ0tleXMSJQoOZW5jcnlwdGlvbl9rZXkYAiABKAxSDWVuY3J5cHRpb25LZXkSNAoHZGV2aWNl'
    'cxgDIAMoCzIaLnBob3RvbGliLmtlcm5lbC52MS5EZXZpY2VSB2RldmljZXMSJQoOYW1rX2dlbm'
    'VyYXRpb24YBCABKA1SDWFta0dlbmVyYXRpb24SMgoEaGVhZBgFIAEoCzIeLnBob3RvbGliLmtl'
    'cm5lbC52MS5DaGVja3BvaW50UgRoZWFkEjQKBXdyYXBzGAYgAygLMh4ucGhvdG9saWIua2Vybm'
    'VsLnYxLlNpZ25lZFdyYXBSBXdyYXBz');

@$core.Deprecated('Use identityDescriptor instead')
const Identity$json = {
  '1': 'Identity',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'signing_keys', '3': 2, '4': 3, '5': 12, '10': 'signingKeys'},
  ],
};

/// Descriptor for `Identity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List identityDescriptor = $convert.base64Decode(
    'CghJZGVudGl0eRIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySWQSIQoMc2lnbmluZ19rZXlzGAIgAy'
    'gMUgtzaWduaW5nS2V5cw==');

@$core.Deprecated('Use verifyMembershipLogRequestDescriptor instead')
const VerifyMembershipLogRequest$json = {
  '1': 'VerifyMembershipLogRequest',
  '2': [
    {'1': 'log_type', '3': 1, '4': 1, '5': 13, '10': 'logType'},
    {'1': 'log_id', '3': 2, '4': 1, '5': 12, '10': 'logId'},
    {'1': 'entries', '3': 3, '4': 3, '5': 12, '10': 'entries'},
    {
      '1': 'checkpoint',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Checkpoint',
      '10': 'checkpoint'
    },
    {
      '1': 'identities',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Identity',
      '10': 'identities'
    },
    {'1': 'statements', '3': 6, '4': 3, '5': 12, '10': 'statements'},
  ],
};

/// Descriptor for `VerifyMembershipLogRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verifyMembershipLogRequestDescriptor = $convert.base64Decode(
    'ChpWZXJpZnlNZW1iZXJzaGlwTG9nUmVxdWVzdBIZCghsb2dfdHlwZRgBIAEoDVIHbG9nVHlwZR'
    'IVCgZsb2dfaWQYAiABKAxSBWxvZ0lkEhgKB2VudHJpZXMYAyADKAxSB2VudHJpZXMSPgoKY2hl'
    'Y2twb2ludBgEIAEoCzIeLnBob3RvbGliLmtlcm5lbC52MS5DaGVja3BvaW50UgpjaGVja3BvaW'
    '50EjwKCmlkZW50aXRpZXMYBSADKAsyHC5waG90b2xpYi5rZXJuZWwudjEuSWRlbnRpdHlSCmlk'
    'ZW50aXRpZXMSHgoKc3RhdGVtZW50cxgGIAMoDFIKc3RhdGVtZW50cw==');

@$core.Deprecated('Use memberDescriptor instead')
const Member$json = {
  '1': 'Member',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'role', '3': 2, '4': 1, '5': 13, '10': 'role'},
    {'1': 'signing_key_id', '3': 3, '4': 1, '5': 12, '10': 'signingKeyId'},
  ],
};

/// Descriptor for `Member`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List memberDescriptor = $convert.base64Decode(
    'CgZNZW1iZXISFwoHdXNlcl9pZBgBIAEoDFIGdXNlcklkEhIKBHJvbGUYAiABKA1SBHJvbGUSJA'
    'oOc2lnbmluZ19rZXlfaWQYAyABKAxSDHNpZ25pbmdLZXlJZA==');

@$core.Deprecated('Use linkDescriptor instead')
const Link$json = {
  '1': 'Link',
  '2': [
    {'1': 'link_id', '3': 1, '4': 1, '5': 12, '10': 'linkId'},
    {'1': 'drop_key', '3': 2, '4': 1, '5': 12, '10': 'dropKey'},
  ],
};

/// Descriptor for `Link`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linkDescriptor = $convert.base64Decode(
    'CgRMaW5rEhcKB2xpbmtfaWQYASABKAxSBmxpbmtJZBIZCghkcm9wX2tleRgCIAEoDFIHZHJvcE'
    'tleQ==');

@$core.Deprecated('Use uploadDescriptor instead')
const Upload$json = {
  '1': 'Upload',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 12, '10': 'fileId'},
    {'1': 'uploader', '3': 2, '4': 1, '5': 12, '10': 'uploader'},
    {'1': 'objects_hash', '3': 3, '4': 1, '5': 12, '10': 'objectsHash'},
    {'1': 'rejected', '3': 4, '4': 1, '5': 9, '10': 'rejected'},
  ],
};

/// Descriptor for `Upload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadDescriptor = $convert.base64Decode(
    'CgZVcGxvYWQSFwoHZmlsZV9pZBgBIAEoDFIGZmlsZUlkEhoKCHVwbG9hZGVyGAIgASgMUgh1cG'
    'xvYWRlchIhCgxvYmplY3RzX2hhc2gYAyABKAxSC29iamVjdHNIYXNoEhoKCHJlamVjdGVkGAQg'
    'ASgJUghyZWplY3RlZA==');

@$core.Deprecated('Use verifyMembershipLogResponseDescriptor instead')
const VerifyMembershipLogResponse$json = {
  '1': 'VerifyMembershipLogResponse',
  '2': [
    {'1': 'owner', '3': 1, '4': 1, '5': 12, '10': 'owner'},
    {
      '1': 'members',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Member',
      '10': 'members'
    },
    {'1': 'epoch', '3': 3, '4': 1, '5': 13, '10': 'epoch'},
    {'1': 'rotation_due', '3': 4, '4': 1, '5': 8, '10': 'rotationDue'},
    {
      '1': 'links',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Link',
      '10': 'links'
    },
    {
      '1': 'head',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Checkpoint',
      '10': 'head'
    },
    {
      '1': 'wraps',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.SignedWrap',
      '10': 'wraps'
    },
    {
      '1': 'uploads',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Upload',
      '10': 'uploads'
    },
  ],
};

/// Descriptor for `VerifyMembershipLogResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verifyMembershipLogResponseDescriptor = $convert.base64Decode(
    'ChtWZXJpZnlNZW1iZXJzaGlwTG9nUmVzcG9uc2USFAoFb3duZXIYASABKAxSBW93bmVyEjQKB2'
    '1lbWJlcnMYAiADKAsyGi5waG90b2xpYi5rZXJuZWwudjEuTWVtYmVyUgdtZW1iZXJzEhQKBWVw'
    'b2NoGAMgASgNUgVlcG9jaBIhCgxyb3RhdGlvbl9kdWUYBCABKAhSC3JvdGF0aW9uRHVlEi4KBW'
    'xpbmtzGAUgAygLMhgucGhvdG9saWIua2VybmVsLnYxLkxpbmtSBWxpbmtzEjIKBGhlYWQYBiAB'
    'KAsyHi5waG90b2xpYi5rZXJuZWwudjEuQ2hlY2twb2ludFIEaGVhZBI0CgV3cmFwcxgHIAMoCz'
    'IeLnBob3RvbGliLmtlcm5lbC52MS5TaWduZWRXcmFwUgV3cmFwcxI0Cgd1cGxvYWRzGAggAygL'
    'MhoucGhvdG9saWIua2VybmVsLnYxLlVwbG9hZFIHdXBsb2Fkcw==');

@$core.Deprecated('Use safetyNumberRequestDescriptor instead')
const SafetyNumberRequest$json = {
  '1': 'SafetyNumberRequest',
  '2': [
    {'1': 'user_a', '3': 1, '4': 1, '5': 12, '10': 'userA'},
    {'1': 'signing_key_a', '3': 2, '4': 1, '5': 12, '10': 'signingKeyA'},
    {'1': 'user_b', '3': 3, '4': 1, '5': 12, '10': 'userB'},
    {'1': 'signing_key_b', '3': 4, '4': 1, '5': 12, '10': 'signingKeyB'},
  ],
};

/// Descriptor for `SafetyNumberRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List safetyNumberRequestDescriptor = $convert.base64Decode(
    'ChNTYWZldHlOdW1iZXJSZXF1ZXN0EhUKBnVzZXJfYRgBIAEoDFIFdXNlckESIgoNc2lnbmluZ1'
    '9rZXlfYRgCIAEoDFILc2lnbmluZ0tleUESFQoGdXNlcl9iGAMgASgMUgV1c2VyQhIiCg1zaWdu'
    'aW5nX2tleV9iGAQgASgMUgtzaWduaW5nS2V5Qg==');

@$core.Deprecated('Use epochCodeRequestDescriptor instead')
const EpochCodeRequest$json = {
  '1': 'EpochCodeRequest',
  '2': [
    {'1': 'log_id', '3': 1, '4': 1, '5': 12, '10': 'logId'},
    {'1': 'head', '3': 2, '4': 1, '5': 12, '10': 'head'},
  ],
};

/// Descriptor for `EpochCodeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List epochCodeRequestDescriptor = $convert.base64Decode(
    'ChBFcG9jaENvZGVSZXF1ZXN0EhUKBmxvZ19pZBgBIAEoDFIFbG9nSWQSEgoEaGVhZBgCIAEoDF'
    'IEaGVhZA==');

@$core.Deprecated('Use codeResponseDescriptor instead')
const CodeResponse$json = {
  '1': 'CodeResponse',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 9, '10': 'code'},
  ],
};

/// Descriptor for `CodeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List codeResponseDescriptor =
    $convert.base64Decode('CgxDb2RlUmVzcG9uc2USEgoEY29kZRgBIAEoCVIEY29kZQ==');
