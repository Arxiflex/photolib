// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/local.proto.

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

@$core.Deprecated('Use lockboxSlotDescriptor instead')
const LockboxSlot$json = {
  '1': 'LockboxSlot',
  '2': [
    {'1': 'factor', '3': 1, '4': 1, '5': 13, '10': 'factor'},
    {'1': 'hardware', '3': 2, '4': 1, '5': 8, '10': 'hardware'},
    {'1': 'user_id', '3': 3, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'params', '3': 4, '4': 1, '5': 12, '10': 'params'},
    {'1': 'wrap', '3': 5, '4': 1, '5': 12, '10': 'wrap'},
    {'1': 'key', '3': 6, '4': 1, '5': 13, '10': 'key'},
    {'1': 'nonce', '3': 7, '4': 1, '5': 12, '10': 'nonce'},
  ],
};

/// Descriptor for `LockboxSlot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lockboxSlotDescriptor = $convert.base64Decode(
    'CgtMb2NrYm94U2xvdBIWCgZmYWN0b3IYASABKA1SBmZhY3RvchIaCghoYXJkd2FyZRgCIAEoCF'
    'IIaGFyZHdhcmUSFwoHdXNlcl9pZBgDIAEoDFIGdXNlcklkEhYKBnBhcmFtcxgEIAEoDFIGcGFy'
    'YW1zEhIKBHdyYXAYBSABKAxSBHdyYXASEAoDa2V5GAYgASgNUgNrZXkSFAoFbm9uY2UYByABKA'
    'xSBW5vbmNl');

@$core.Deprecated('Use sealLockboxRequestDescriptor instead')
const SealLockboxRequest$json = {
  '1': 'SealLockboxRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'device_id', '3': 2, '4': 1, '5': 12, '10': 'deviceId'},
    {
      '1': 'slots',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.LockboxSlot',
      '10': 'slots'
    },
  ],
};

/// Descriptor for `SealLockboxRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sealLockboxRequestDescriptor = $convert.base64Decode(
    'ChJTZWFsTG9ja2JveFJlcXVlc3QSEAoDa2V5GAEgASgNUgNrZXkSGwoJZGV2aWNlX2lkGAIgAS'
    'gMUghkZXZpY2VJZBI1CgVzbG90cxgDIAMoCzIfLnBob3RvbGliLmtlcm5lbC52MS5Mb2NrYm94'
    'U2xvdFIFc2xvdHM=');

@$core.Deprecated('Use sealLockboxResponseDescriptor instead')
const SealLockboxResponse$json = {
  '1': 'SealLockboxResponse',
  '2': [
    {'1': 'lockbox', '3': 1, '4': 1, '5': 12, '10': 'lockbox'},
  ],
};

/// Descriptor for `SealLockboxResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sealLockboxResponseDescriptor =
    $convert.base64Decode(
        'ChNTZWFsTG9ja2JveFJlc3BvbnNlEhgKB2xvY2tib3gYASABKAxSB2xvY2tib3g=');

@$core.Deprecated('Use readLockboxRequestDescriptor instead')
const ReadLockboxRequest$json = {
  '1': 'ReadLockboxRequest',
  '2': [
    {'1': 'lockbox', '3': 1, '4': 1, '5': 12, '10': 'lockbox'},
  ],
};

/// Descriptor for `ReadLockboxRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readLockboxRequestDescriptor =
    $convert.base64Decode(
        'ChJSZWFkTG9ja2JveFJlcXVlc3QSGAoHbG9ja2JveBgBIAEoDFIHbG9ja2JveA==');

@$core.Deprecated('Use readLockboxResponseDescriptor instead')
const ReadLockboxResponse$json = {
  '1': 'ReadLockboxResponse',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'key_id', '3': 2, '4': 1, '5': 12, '10': 'keyId'},
    {
      '1': 'slots',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.LockboxSlot',
      '10': 'slots'
    },
  ],
};

/// Descriptor for `ReadLockboxResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readLockboxResponseDescriptor = $convert.base64Decode(
    'ChNSZWFkTG9ja2JveFJlc3BvbnNlEhsKCWRldmljZV9pZBgBIAEoDFIIZGV2aWNlSWQSFQoGa2'
    'V5X2lkGAIgASgMUgVrZXlJZBI1CgVzbG90cxgDIAMoCzIfLnBob3RvbGliLmtlcm5lbC52MS5M'
    'b2NrYm94U2xvdFIFc2xvdHM=');

@$core.Deprecated('Use openLockboxRequestDescriptor instead')
const OpenLockboxRequest$json = {
  '1': 'OpenLockboxRequest',
  '2': [
    {'1': 'lockbox', '3': 1, '4': 1, '5': 12, '10': 'lockbox'},
    {'1': 'slot', '3': 2, '4': 1, '5': 13, '10': 'slot'},
    {'1': 'key', '3': 3, '4': 1, '5': 13, '10': 'key'},
  ],
};

/// Descriptor for `OpenLockboxRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List openLockboxRequestDescriptor = $convert.base64Decode(
    'ChJPcGVuTG9ja2JveFJlcXVlc3QSGAoHbG9ja2JveBgBIAEoDFIHbG9ja2JveBISCgRzbG90GA'
    'IgASgNUgRzbG90EhAKA2tleRgDIAEoDVIDa2V5');

@$core.Deprecated('Use inboxPublicKeyRequestDescriptor instead')
const InboxPublicKeyRequest$json = {
  '1': 'InboxPublicKeyRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
  ],
};

/// Descriptor for `InboxPublicKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List inboxPublicKeyRequestDescriptor = $convert
    .base64Decode('ChVJbmJveFB1YmxpY0tleVJlcXVlc3QSEAoDa2V5GAEgASgNUgNrZXk=');

@$core.Deprecated('Use inboxPublicKeyResponseDescriptor instead')
const InboxPublicKeyResponse$json = {
  '1': 'InboxPublicKeyResponse',
  '2': [
    {'1': 'public_key', '3': 1, '4': 1, '5': 12, '10': 'publicKey'},
  ],
};

/// Descriptor for `InboxPublicKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List inboxPublicKeyResponseDescriptor =
    $convert.base64Decode(
        'ChZJbmJveFB1YmxpY0tleVJlc3BvbnNlEh0KCnB1YmxpY19rZXkYASABKAxSCXB1YmxpY0tleQ'
        '==');

@$core.Deprecated('Use sealJournalEntryRequestDescriptor instead')
const SealJournalEntryRequest$json = {
  '1': 'SealJournalEntryRequest',
  '2': [
    {'1': 'public_key', '3': 1, '4': 1, '5': 12, '10': 'publicKey'},
    {'1': 'randomness', '3': 2, '4': 1, '5': 12, '10': 'randomness'},
    {'1': 'plaintext', '3': 3, '4': 1, '5': 12, '10': 'plaintext'},
  ],
};

/// Descriptor for `SealJournalEntryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sealJournalEntryRequestDescriptor = $convert.base64Decode(
    'ChdTZWFsSm91cm5hbEVudHJ5UmVxdWVzdBIdCgpwdWJsaWNfa2V5GAEgASgMUglwdWJsaWNLZX'
    'kSHgoKcmFuZG9tbmVzcxgCIAEoDFIKcmFuZG9tbmVzcxIcCglwbGFpbnRleHQYAyABKAxSCXBs'
    'YWludGV4dA==');

@$core.Deprecated('Use sealJournalEntryResponseDescriptor instead')
const SealJournalEntryResponse$json = {
  '1': 'SealJournalEntryResponse',
  '2': [
    {'1': 'entry', '3': 1, '4': 1, '5': 12, '10': 'entry'},
  ],
};

/// Descriptor for `SealJournalEntryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sealJournalEntryResponseDescriptor =
    $convert.base64Decode(
        'ChhTZWFsSm91cm5hbEVudHJ5UmVzcG9uc2USFAoFZW50cnkYASABKAxSBWVudHJ5');

@$core.Deprecated('Use openJournalEntryRequestDescriptor instead')
const OpenJournalEntryRequest$json = {
  '1': 'OpenJournalEntryRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'entry', '3': 2, '4': 1, '5': 12, '10': 'entry'},
  ],
};

/// Descriptor for `OpenJournalEntryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List openJournalEntryRequestDescriptor =
    $convert.base64Decode(
        'ChdPcGVuSm91cm5hbEVudHJ5UmVxdWVzdBIQCgNrZXkYASABKA1SA2tleRIUCgVlbnRyeRgCIA'
        'EoDFIFZW50cnk=');

@$core.Deprecated('Use openJournalEntryResponseDescriptor instead')
const OpenJournalEntryResponse$json = {
  '1': 'OpenJournalEntryResponse',
  '2': [
    {'1': 'plaintext', '3': 1, '4': 1, '5': 12, '10': 'plaintext'},
  ],
};

/// Descriptor for `OpenJournalEntryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List openJournalEntryResponseDescriptor =
    $convert.base64Decode(
        'ChhPcGVuSm91cm5hbEVudHJ5UmVzcG9uc2USHAoJcGxhaW50ZXh0GAEgASgMUglwbGFpbnRleH'
        'Q=');

@$core.Deprecated('Use databaseKeyRequestDescriptor instead')
const DatabaseKeyRequest$json = {
  '1': 'DatabaseKeyRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 13, '10': 'key'},
    {'1': 'file_id', '3': 2, '4': 1, '5': 12, '10': 'fileId'},
  ],
};

/// Descriptor for `DatabaseKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List databaseKeyRequestDescriptor = $convert.base64Decode(
    'ChJEYXRhYmFzZUtleVJlcXVlc3QSEAoDa2V5GAEgASgNUgNrZXkSFwoHZmlsZV9pZBgCIAEoDF'
    'IGZmlsZUlk');

@$core.Deprecated('Use databaseKeyResponseDescriptor instead')
const DatabaseKeyResponse$json = {
  '1': 'DatabaseKeyResponse',
  '2': [
    {'1': 'page_key', '3': 1, '4': 1, '5': 12, '10': 'pageKey'},
  ],
};

/// Descriptor for `DatabaseKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List databaseKeyResponseDescriptor =
    $convert.base64Decode(
        'ChNEYXRhYmFzZUtleVJlc3BvbnNlEhkKCHBhZ2Vfa2V5GAEgASgMUgdwYWdlS2V5');
