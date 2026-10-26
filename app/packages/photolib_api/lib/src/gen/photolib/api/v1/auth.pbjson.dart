// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/auth.proto.

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

import 'keys.pbjson.dart' as $1;

@$core.Deprecated('Use secondFactorDescriptor instead')
const SecondFactor$json = {
  '1': 'SecondFactor',
  '2': [
    {'1': 'SECOND_FACTOR_UNSPECIFIED', '2': 0},
    {'1': 'SECOND_FACTOR_TOTP', '2': 1},
    {'1': 'SECOND_FACTOR_PASSKEY', '2': 2},
    {'1': 'SECOND_FACTOR_RECOVERY_CODE', '2': 3},
  ],
};

/// Descriptor for `SecondFactor`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List secondFactorDescriptor = $convert.base64Decode(
    'CgxTZWNvbmRGYWN0b3ISHQoZU0VDT05EX0ZBQ1RPUl9VTlNQRUNJRklFRBAAEhYKElNFQ09ORF'
    '9GQUNUT1JfVE9UUBABEhkKFVNFQ09ORF9GQUNUT1JfUEFTU0tFWRACEh8KG1NFQ09ORF9GQUNU'
    'T1JfUkVDT1ZFUllfQ09ERRAD');

@$core.Deprecated('Use passkeyDescriptor instead')
const Passkey$json = {
  '1': 'Passkey',
  '2': [
    {'1': 'passkey_id', '3': 1, '4': 1, '5': 9, '10': 'passkeyId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'created_at',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
    {
      '1': 'last_used_at',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'lastUsedAt'
    },
  ],
};

/// Descriptor for `Passkey`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List passkeyDescriptor = $convert.base64Decode(
    'CgdQYXNza2V5Eh0KCnBhc3NrZXlfaWQYASABKAlSCXBhc3NrZXlJZBISCgRuYW1lGAIgASgJUg'
    'RuYW1lEjkKCmNyZWF0ZWRfYXQYAyABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUglj'
    'cmVhdGVkQXQSPAoMbGFzdF91c2VkX2F0GAQgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdG'
    'FtcFIKbGFzdFVzZWRBdA==');

@$core.Deprecated('Use secondFactorChallengeDescriptor instead')
const SecondFactorChallenge$json = {
  '1': 'SecondFactorChallenge',
  '2': [
    {'1': 'login_id', '3': 1, '4': 1, '5': 9, '10': 'loginId'},
    {
      '1': 'factors',
      '3': 2,
      '4': 3,
      '5': 14,
      '6': '.photolib.api.v1.SecondFactor',
      '10': 'factors'
    },
    {
      '1': 'passkey_options_json',
      '3': 3,
      '4': 1,
      '5': 9,
      '10': 'passkeyOptionsJson'
    },
  ],
};

/// Descriptor for `SecondFactorChallenge`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List secondFactorChallengeDescriptor = $convert.base64Decode(
    'ChVTZWNvbmRGYWN0b3JDaGFsbGVuZ2USGQoIbG9naW5faWQYASABKAlSB2xvZ2luSWQSNwoHZm'
    'FjdG9ycxgCIAMoDjIdLnBob3RvbGliLmFwaS52MS5TZWNvbmRGYWN0b3JSB2ZhY3RvcnMSMAoU'
    'cGFzc2tleV9vcHRpb25zX2pzb24YAyABKAlSEnBhc3NrZXlPcHRpb25zSnNvbg==');

@$core.Deprecated('Use deviceDescriptor instead')
const Device$json = {
  '1': 'Device',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'platform', '3': 3, '4': 1, '5': 9, '10': 'platform'},
    {'1': 'app_version', '3': 4, '4': 1, '5': 9, '10': 'appVersion'},
    {
      '1': 'created_at',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
    {
      '1': 'last_seen_at',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'lastSeenAt'
    },
    {'1': 'current', '3': 7, '4': 1, '5': 8, '10': 'current'},
  ],
};

/// Descriptor for `Device`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceDescriptor = $convert.base64Decode(
    'CgZEZXZpY2USGwoJZGV2aWNlX2lkGAEgASgJUghkZXZpY2VJZBISCgRuYW1lGAIgASgJUgRuYW'
    '1lEhoKCHBsYXRmb3JtGAMgASgJUghwbGF0Zm9ybRIfCgthcHBfdmVyc2lvbhgEIAEoCVIKYXBw'
    'VmVyc2lvbhI5CgpjcmVhdGVkX2F0GAUgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcF'
    'IJY3JlYXRlZEF0EjwKDGxhc3Rfc2Vlbl9hdBgGIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1l'
    'c3RhbXBSCmxhc3RTZWVuQXQSGAoHY3VycmVudBgHIAEoCFIHY3VycmVudA==');

@$core.Deprecated('Use sessionDescriptor instead')
const Session$json = {
  '1': 'Session',
  '2': [
    {'1': 'token', '3': 1, '4': 1, '5': 9, '10': 'token'},
    {
      '1': 'expires_at',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'expiresAt'
    },
    {'1': 'device_id', '3': 3, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'user_id', '3': 4, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'device_secret', '3': 5, '4': 1, '5': 9, '10': 'deviceSecret'},
  ],
};

/// Descriptor for `Session`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionDescriptor = $convert.base64Decode(
    'CgdTZXNzaW9uEhQKBXRva2VuGAEgASgJUgV0b2tlbhI5CgpleHBpcmVzX2F0GAIgASgLMhouZ2'
    '9vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIJZXhwaXJlc0F0EhsKCWRldmljZV9pZBgDIAEoCVII'
    'ZGV2aWNlSWQSFwoHdXNlcl9pZBgEIAEoCVIGdXNlcklkEiMKDWRldmljZV9zZWNyZXQYBSABKA'
    'lSDGRldmljZVNlY3JldA==');

@$core.Deprecated('Use startPasswordSetupRequestDescriptor instead')
const StartPasswordSetupRequest$json = {
  '1': 'StartPasswordSetupRequest',
  '2': [
    {
      '1': 'registration_request',
      '3': 1,
      '4': 1,
      '5': 12,
      '10': 'registrationRequest'
    },
    {
      '1': 'password_setup_token',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'passwordSetupToken'
    },
  ],
};

/// Descriptor for `StartPasswordSetupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startPasswordSetupRequestDescriptor = $convert.base64Decode(
    'ChlTdGFydFBhc3N3b3JkU2V0dXBSZXF1ZXN0EjEKFHJlZ2lzdHJhdGlvbl9yZXF1ZXN0GAEgAS'
    'gMUhNyZWdpc3RyYXRpb25SZXF1ZXN0EjAKFHBhc3N3b3JkX3NldHVwX3Rva2VuGAIgASgJUhJw'
    'YXNzd29yZFNldHVwVG9rZW4=');

@$core.Deprecated('Use startPasswordSetupResponseDescriptor instead')
const StartPasswordSetupResponse$json = {
  '1': 'StartPasswordSetupResponse',
  '2': [
    {
      '1': 'registration_response',
      '3': 1,
      '4': 1,
      '5': 12,
      '10': 'registrationResponse'
    },
    {'1': 'registration_id', '3': 2, '4': 1, '5': 12, '10': 'registrationId'},
    {
      '1': 'private_libraries',
      '3': 3,
      '4': 1,
      '5': 8,
      '10': 'privateLibraries'
    },
  ],
};

/// Descriptor for `StartPasswordSetupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startPasswordSetupResponseDescriptor = $convert.base64Decode(
    'ChpTdGFydFBhc3N3b3JkU2V0dXBSZXNwb25zZRIzChVyZWdpc3RyYXRpb25fcmVzcG9uc2UYAS'
    'ABKAxSFHJlZ2lzdHJhdGlvblJlc3BvbnNlEicKD3JlZ2lzdHJhdGlvbl9pZBgCIAEoDFIOcmVn'
    'aXN0cmF0aW9uSWQSKwoRcHJpdmF0ZV9saWJyYXJpZXMYAyABKAhSEHByaXZhdGVMaWJyYXJpZX'
    'M=');

@$core.Deprecated('Use finishPasswordSetupRequestDescriptor instead')
const FinishPasswordSetupRequest$json = {
  '1': 'FinishPasswordSetupRequest',
  '2': [
    {
      '1': 'registration_record',
      '3': 1,
      '4': 1,
      '5': 12,
      '10': 'registrationRecord'
    },
    {'1': 'ksf_params', '3': 2, '4': 1, '5': 12, '10': 'ksfParams'},
    {
      '1': 'password_setup_token',
      '3': 3,
      '4': 1,
      '5': 9,
      '10': 'passwordSetupToken'
    },
    {'1': 'registration_id', '3': 4, '4': 1, '5': 12, '10': 'registrationId'},
    {
      '1': 'password_path',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.UnlockPath',
      '10': 'passwordPath'
    },
  ],
};

/// Descriptor for `FinishPasswordSetupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishPasswordSetupRequestDescriptor = $convert.base64Decode(
    'ChpGaW5pc2hQYXNzd29yZFNldHVwUmVxdWVzdBIvChNyZWdpc3RyYXRpb25fcmVjb3JkGAEgAS'
    'gMUhJyZWdpc3RyYXRpb25SZWNvcmQSHQoKa3NmX3BhcmFtcxgCIAEoDFIJa3NmUGFyYW1zEjAK'
    'FHBhc3N3b3JkX3NldHVwX3Rva2VuGAMgASgJUhJwYXNzd29yZFNldHVwVG9rZW4SJwoPcmVnaX'
    'N0cmF0aW9uX2lkGAQgASgMUg5yZWdpc3RyYXRpb25JZBJACg1wYXNzd29yZF9wYXRoGAUgASgL'
    'MhsucGhvdG9saWIuYXBpLnYxLlVubG9ja1BhdGhSDHBhc3N3b3JkUGF0aA==');

@$core.Deprecated('Use finishPasswordSetupResponseDescriptor instead')
const FinishPasswordSetupResponse$json = {
  '1': 'FinishPasswordSetupResponse',
};

/// Descriptor for `FinishPasswordSetupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishPasswordSetupResponseDescriptor =
    $convert.base64Decode('ChtGaW5pc2hQYXNzd29yZFNldHVwUmVzcG9uc2U=');

@$core.Deprecated('Use startLoginRequestDescriptor instead')
const StartLoginRequest$json = {
  '1': 'StartLoginRequest',
  '2': [
    {'1': 'handle', '3': 1, '4': 1, '5': 9, '10': 'handle'},
    {'1': 'ke1', '3': 2, '4': 1, '5': 12, '10': 'ke1'},
    {'1': 'device_id', '3': 3, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'device_secret', '3': 4, '4': 1, '5': 9, '10': 'deviceSecret'},
  ],
};

/// Descriptor for `StartLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startLoginRequestDescriptor = $convert.base64Decode(
    'ChFTdGFydExvZ2luUmVxdWVzdBIWCgZoYW5kbGUYASABKAlSBmhhbmRsZRIQCgNrZTEYAiABKA'
    'xSA2tlMRIbCglkZXZpY2VfaWQYAyABKAlSCGRldmljZUlkEiMKDWRldmljZV9zZWNyZXQYBCAB'
    'KAlSDGRldmljZVNlY3JldA==');

@$core.Deprecated('Use startLoginResponseDescriptor instead')
const StartLoginResponse$json = {
  '1': 'StartLoginResponse',
  '2': [
    {'1': 'login_id', '3': 1, '4': 1, '5': 9, '10': 'loginId'},
    {'1': 'ke2', '3': 2, '4': 1, '5': 12, '10': 'ke2'},
    {'1': 'ksf_params', '3': 3, '4': 1, '5': 12, '10': 'ksfParams'},
  ],
};

/// Descriptor for `StartLoginResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startLoginResponseDescriptor = $convert.base64Decode(
    'ChJTdGFydExvZ2luUmVzcG9uc2USGQoIbG9naW5faWQYASABKAlSB2xvZ2luSWQSEAoDa2UyGA'
    'IgASgMUgNrZTISHQoKa3NmX3BhcmFtcxgDIAEoDFIJa3NmUGFyYW1z');

@$core.Deprecated('Use finishLoginRequestDescriptor instead')
const FinishLoginRequest$json = {
  '1': 'FinishLoginRequest',
  '2': [
    {'1': 'login_id', '3': 1, '4': 1, '5': 9, '10': 'loginId'},
    {'1': 'ke3', '3': 2, '4': 1, '5': 12, '10': 'ke3'},
    {
      '1': 'device',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Device',
      '10': 'device'
    },
  ],
};

/// Descriptor for `FinishLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishLoginRequestDescriptor = $convert.base64Decode(
    'ChJGaW5pc2hMb2dpblJlcXVlc3QSGQoIbG9naW5faWQYASABKAlSB2xvZ2luSWQSEAoDa2UzGA'
    'IgASgMUgNrZTMSLwoGZGV2aWNlGAMgASgLMhcucGhvdG9saWIuYXBpLnYxLkRldmljZVIGZGV2'
    'aWNl');

@$core.Deprecated('Use finishLoginResponseDescriptor instead')
const FinishLoginResponse$json = {
  '1': 'FinishLoginResponse',
  '2': [
    {
      '1': 'session',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Session',
      '10': 'session'
    },
    {
      '1': 'second_factor',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.SecondFactorChallenge',
      '10': 'secondFactor'
    },
    {
      '1': 'password_path',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.UnlockPath',
      '10': 'passwordPath'
    },
  ],
};

/// Descriptor for `FinishLoginResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishLoginResponseDescriptor = $convert.base64Decode(
    'ChNGaW5pc2hMb2dpblJlc3BvbnNlEjIKB3Nlc3Npb24YASABKAsyGC5waG90b2xpYi5hcGkudj'
    'EuU2Vzc2lvblIHc2Vzc2lvbhJLCg1zZWNvbmRfZmFjdG9yGAIgASgLMiYucGhvdG9saWIuYXBp'
    'LnYxLlNlY29uZEZhY3RvckNoYWxsZW5nZVIMc2Vjb25kRmFjdG9yEkAKDXBhc3N3b3JkX3BhdG'
    'gYAyABKAsyGy5waG90b2xpYi5hcGkudjEuVW5sb2NrUGF0aFIMcGFzc3dvcmRQYXRo');

@$core.Deprecated('Use rotateSessionRequestDescriptor instead')
const RotateSessionRequest$json = {
  '1': 'RotateSessionRequest',
};

/// Descriptor for `RotateSessionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rotateSessionRequestDescriptor =
    $convert.base64Decode('ChRSb3RhdGVTZXNzaW9uUmVxdWVzdA==');

@$core.Deprecated('Use rotateSessionResponseDescriptor instead')
const RotateSessionResponse$json = {
  '1': 'RotateSessionResponse',
  '2': [
    {
      '1': 'session',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Session',
      '10': 'session'
    },
  ],
};

/// Descriptor for `RotateSessionResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rotateSessionResponseDescriptor = $convert.base64Decode(
    'ChVSb3RhdGVTZXNzaW9uUmVzcG9uc2USMgoHc2Vzc2lvbhgBIAEoCzIYLnBob3RvbGliLmFwaS'
    '52MS5TZXNzaW9uUgdzZXNzaW9u');

@$core.Deprecated('Use listDevicesRequestDescriptor instead')
const ListDevicesRequest$json = {
  '1': 'ListDevicesRequest',
};

/// Descriptor for `ListDevicesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listDevicesRequestDescriptor =
    $convert.base64Decode('ChJMaXN0RGV2aWNlc1JlcXVlc3Q=');

@$core.Deprecated('Use listDevicesResponseDescriptor instead')
const ListDevicesResponse$json = {
  '1': 'ListDevicesResponse',
  '2': [
    {
      '1': 'devices',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.Device',
      '10': 'devices'
    },
  ],
};

/// Descriptor for `ListDevicesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listDevicesResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0RGV2aWNlc1Jlc3BvbnNlEjEKB2RldmljZXMYASADKAsyFy5waG90b2xpYi5hcGkudj'
    'EuRGV2aWNlUgdkZXZpY2Vz');

@$core.Deprecated('Use revokeDeviceRequestDescriptor instead')
const RevokeDeviceRequest$json = {
  '1': 'RevokeDeviceRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `RevokeDeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeDeviceRequestDescriptor =
    $convert.base64Decode(
        'ChNSZXZva2VEZXZpY2VSZXF1ZXN0EhsKCWRldmljZV9pZBgBIAEoCVIIZGV2aWNlSWQ=');

@$core.Deprecated('Use revokeDeviceResponseDescriptor instead')
const RevokeDeviceResponse$json = {
  '1': 'RevokeDeviceResponse',
};

/// Descriptor for `RevokeDeviceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeDeviceResponseDescriptor =
    $convert.base64Decode('ChRSZXZva2VEZXZpY2VSZXNwb25zZQ==');

@$core.Deprecated('Use reportBackupRequestDescriptor instead')
const ReportBackupRequest$json = {
  '1': 'ReportBackupRequest',
  '2': [
    {'1': 'pending_count', '3': 1, '4': 1, '5': 3, '10': 'pendingCount'},
  ],
};

/// Descriptor for `ReportBackupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reportBackupRequestDescriptor = $convert.base64Decode(
    'ChNSZXBvcnRCYWNrdXBSZXF1ZXN0EiMKDXBlbmRpbmdfY291bnQYASABKANSDHBlbmRpbmdDb3'
    'VudA==');

@$core.Deprecated('Use reportBackupResponseDescriptor instead')
const ReportBackupResponse$json = {
  '1': 'ReportBackupResponse',
};

/// Descriptor for `ReportBackupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reportBackupResponseDescriptor =
    $convert.base64Decode('ChRSZXBvcnRCYWNrdXBSZXNwb25zZQ==');

@$core.Deprecated('Use startOidcRequestDescriptor instead')
const StartOidcRequest$json = {
  '1': 'StartOidcRequest',
  '2': [
    {'1': 'provider', '3': 1, '4': 1, '5': 9, '10': 'provider'},
    {'1': 'redirect_uri', '3': 2, '4': 1, '5': 9, '10': 'redirectUri'},
    {'1': 'code_challenge', '3': 3, '4': 1, '5': 9, '10': 'codeChallenge'},
    {'1': 'link', '3': 4, '4': 1, '5': 8, '10': 'link'},
  ],
};

/// Descriptor for `StartOidcRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startOidcRequestDescriptor = $convert.base64Decode(
    'ChBTdGFydE9pZGNSZXF1ZXN0EhoKCHByb3ZpZGVyGAEgASgJUghwcm92aWRlchIhCgxyZWRpcm'
    'VjdF91cmkYAiABKAlSC3JlZGlyZWN0VXJpEiUKDmNvZGVfY2hhbGxlbmdlGAMgASgJUg1jb2Rl'
    'Q2hhbGxlbmdlEhIKBGxpbmsYBCABKAhSBGxpbms=');

@$core.Deprecated('Use startOidcResponseDescriptor instead')
const StartOidcResponse$json = {
  '1': 'StartOidcResponse',
  '2': [
    {
      '1': 'authorization_url',
      '3': 1,
      '4': 1,
      '5': 9,
      '10': 'authorizationUrl'
    },
  ],
};

/// Descriptor for `StartOidcResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startOidcResponseDescriptor = $convert.base64Decode(
    'ChFTdGFydE9pZGNSZXNwb25zZRIrChFhdXRob3JpemF0aW9uX3VybBgBIAEoCVIQYXV0aG9yaX'
    'phdGlvblVybA==');

@$core.Deprecated('Use completeOidcRequestDescriptor instead')
const CompleteOidcRequest$json = {
  '1': 'CompleteOidcRequest',
  '2': [
    {'1': 'state', '3': 1, '4': 1, '5': 9, '10': 'state'},
    {'1': 'code', '3': 2, '4': 1, '5': 9, '10': 'code'},
    {'1': 'code_verifier', '3': 3, '4': 1, '5': 9, '10': 'codeVerifier'},
    {
      '1': 'device',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Device',
      '10': 'device'
    },
  ],
};

/// Descriptor for `CompleteOidcRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List completeOidcRequestDescriptor = $convert.base64Decode(
    'ChNDb21wbGV0ZU9pZGNSZXF1ZXN0EhQKBXN0YXRlGAEgASgJUgVzdGF0ZRISCgRjb2RlGAIgAS'
    'gJUgRjb2RlEiMKDWNvZGVfdmVyaWZpZXIYAyABKAlSDGNvZGVWZXJpZmllchIvCgZkZXZpY2UY'
    'BCABKAsyFy5waG90b2xpYi5hcGkudjEuRGV2aWNlUgZkZXZpY2U=');

@$core.Deprecated('Use completeOidcResponseDescriptor instead')
const CompleteOidcResponse$json = {
  '1': 'CompleteOidcResponse',
  '2': [
    {
      '1': 'session',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Session',
      '10': 'session'
    },
  ],
};

/// Descriptor for `CompleteOidcResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List completeOidcResponseDescriptor = $convert.base64Decode(
    'ChRDb21wbGV0ZU9pZGNSZXNwb25zZRIyCgdzZXNzaW9uGAEgASgLMhgucGhvdG9saWIuYXBpLn'
    'YxLlNlc3Npb25SB3Nlc3Npb24=');

@$core.Deprecated('Use finishSecondFactorRequestDescriptor instead')
const FinishSecondFactorRequest$json = {
  '1': 'FinishSecondFactorRequest',
  '2': [
    {'1': 'login_id', '3': 1, '4': 1, '5': 9, '10': 'loginId'},
    {'1': 'totp_code', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'totpCode'},
    {
      '1': 'recovery_code',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'recoveryCode'
    },
    {
      '1': 'passkey_credential_json',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'passkeyCredentialJson'
    },
  ],
  '8': [
    {'1': 'answer'},
  ],
};

/// Descriptor for `FinishSecondFactorRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishSecondFactorRequestDescriptor = $convert.base64Decode(
    'ChlGaW5pc2hTZWNvbmRGYWN0b3JSZXF1ZXN0EhkKCGxvZ2luX2lkGAEgASgJUgdsb2dpbklkEh'
    '0KCXRvdHBfY29kZRgCIAEoCUgAUgh0b3RwQ29kZRIlCg1yZWNvdmVyeV9jb2RlGAMgASgJSABS'
    'DHJlY292ZXJ5Q29kZRI4ChdwYXNza2V5X2NyZWRlbnRpYWxfanNvbhgEIAEoCUgAUhVwYXNza2'
    'V5Q3JlZGVudGlhbEpzb25CCAoGYW5zd2Vy');

@$core.Deprecated('Use finishSecondFactorResponseDescriptor instead')
const FinishSecondFactorResponse$json = {
  '1': 'FinishSecondFactorResponse',
  '2': [
    {
      '1': 'session',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Session',
      '10': 'session'
    },
    {
      '1': 'password_path',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.UnlockPath',
      '10': 'passwordPath'
    },
  ],
};

/// Descriptor for `FinishSecondFactorResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishSecondFactorResponseDescriptor =
    $convert.base64Decode(
        'ChpGaW5pc2hTZWNvbmRGYWN0b3JSZXNwb25zZRIyCgdzZXNzaW9uGAEgASgLMhgucGhvdG9saW'
        'IuYXBpLnYxLlNlc3Npb25SB3Nlc3Npb24SQAoNcGFzc3dvcmRfcGF0aBgCIAEoCzIbLnBob3Rv'
        'bGliLmFwaS52MS5VbmxvY2tQYXRoUgxwYXNzd29yZFBhdGg=');

@$core.Deprecated('Use startPasskeyLoginRequestDescriptor instead')
const StartPasskeyLoginRequest$json = {
  '1': 'StartPasskeyLoginRequest',
};

/// Descriptor for `StartPasskeyLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startPasskeyLoginRequestDescriptor =
    $convert.base64Decode('ChhTdGFydFBhc3NrZXlMb2dpblJlcXVlc3Q=');

@$core.Deprecated('Use startPasskeyLoginResponseDescriptor instead')
const StartPasskeyLoginResponse$json = {
  '1': 'StartPasskeyLoginResponse',
  '2': [
    {'1': 'login_id', '3': 1, '4': 1, '5': 9, '10': 'loginId'},
    {'1': 'options_json', '3': 2, '4': 1, '5': 9, '10': 'optionsJson'},
  ],
};

/// Descriptor for `StartPasskeyLoginResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startPasskeyLoginResponseDescriptor =
    $convert.base64Decode(
        'ChlTdGFydFBhc3NrZXlMb2dpblJlc3BvbnNlEhkKCGxvZ2luX2lkGAEgASgJUgdsb2dpbklkEi'
        'EKDG9wdGlvbnNfanNvbhgCIAEoCVILb3B0aW9uc0pzb24=');

@$core.Deprecated('Use finishPasskeyLoginRequestDescriptor instead')
const FinishPasskeyLoginRequest$json = {
  '1': 'FinishPasskeyLoginRequest',
  '2': [
    {'1': 'login_id', '3': 1, '4': 1, '5': 9, '10': 'loginId'},
    {'1': 'credential_json', '3': 2, '4': 1, '5': 9, '10': 'credentialJson'},
    {
      '1': 'device',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Device',
      '10': 'device'
    },
  ],
};

/// Descriptor for `FinishPasskeyLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishPasskeyLoginRequestDescriptor = $convert.base64Decode(
    'ChlGaW5pc2hQYXNza2V5TG9naW5SZXF1ZXN0EhkKCGxvZ2luX2lkGAEgASgJUgdsb2dpbklkEi'
    'cKD2NyZWRlbnRpYWxfanNvbhgCIAEoCVIOY3JlZGVudGlhbEpzb24SLwoGZGV2aWNlGAMgASgL'
    'MhcucGhvdG9saWIuYXBpLnYxLkRldmljZVIGZGV2aWNl');

@$core.Deprecated('Use finishPasskeyLoginResponseDescriptor instead')
const FinishPasskeyLoginResponse$json = {
  '1': 'FinishPasskeyLoginResponse',
  '2': [
    {
      '1': 'session',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Session',
      '10': 'session'
    },
  ],
};

/// Descriptor for `FinishPasskeyLoginResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishPasskeyLoginResponseDescriptor =
    $convert.base64Decode(
        'ChpGaW5pc2hQYXNza2V5TG9naW5SZXNwb25zZRIyCgdzZXNzaW9uGAEgASgLMhgucGhvdG9saW'
        'IuYXBpLnYxLlNlc3Npb25SB3Nlc3Npb24=');

@$core.Deprecated('Use startPasskeySetupRequestDescriptor instead')
const StartPasskeySetupRequest$json = {
  '1': 'StartPasskeySetupRequest',
};

/// Descriptor for `StartPasskeySetupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startPasskeySetupRequestDescriptor =
    $convert.base64Decode('ChhTdGFydFBhc3NrZXlTZXR1cFJlcXVlc3Q=');

@$core.Deprecated('Use startPasskeySetupResponseDescriptor instead')
const StartPasskeySetupResponse$json = {
  '1': 'StartPasskeySetupResponse',
  '2': [
    {'1': 'setup_id', '3': 1, '4': 1, '5': 9, '10': 'setupId'},
    {'1': 'options_json', '3': 2, '4': 1, '5': 9, '10': 'optionsJson'},
  ],
};

/// Descriptor for `StartPasskeySetupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startPasskeySetupResponseDescriptor =
    $convert.base64Decode(
        'ChlTdGFydFBhc3NrZXlTZXR1cFJlc3BvbnNlEhkKCHNldHVwX2lkGAEgASgJUgdzZXR1cElkEi'
        'EKDG9wdGlvbnNfanNvbhgCIAEoCVILb3B0aW9uc0pzb24=');

@$core.Deprecated('Use finishPasskeySetupRequestDescriptor instead')
const FinishPasskeySetupRequest$json = {
  '1': 'FinishPasskeySetupRequest',
  '2': [
    {'1': 'setup_id', '3': 1, '4': 1, '5': 9, '10': 'setupId'},
    {'1': 'credential_json', '3': 2, '4': 1, '5': 9, '10': 'credentialJson'},
    {'1': 'name', '3': 3, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `FinishPasskeySetupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishPasskeySetupRequestDescriptor = $convert.base64Decode(
    'ChlGaW5pc2hQYXNza2V5U2V0dXBSZXF1ZXN0EhkKCHNldHVwX2lkGAEgASgJUgdzZXR1cElkEi'
    'cKD2NyZWRlbnRpYWxfanNvbhgCIAEoCVIOY3JlZGVudGlhbEpzb24SEgoEbmFtZRgDIAEoCVIE'
    'bmFtZQ==');

@$core.Deprecated('Use finishPasskeySetupResponseDescriptor instead')
const FinishPasskeySetupResponse$json = {
  '1': 'FinishPasskeySetupResponse',
  '2': [
    {
      '1': 'passkey',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.Passkey',
      '10': 'passkey'
    },
    {'1': 'recovery_codes', '3': 2, '4': 3, '5': 9, '10': 'recoveryCodes'},
  ],
};

/// Descriptor for `FinishPasskeySetupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishPasskeySetupResponseDescriptor =
    $convert.base64Decode(
        'ChpGaW5pc2hQYXNza2V5U2V0dXBSZXNwb25zZRIyCgdwYXNza2V5GAEgASgLMhgucGhvdG9saW'
        'IuYXBpLnYxLlBhc3NrZXlSB3Bhc3NrZXkSJQoOcmVjb3ZlcnlfY29kZXMYAiADKAlSDXJlY292'
        'ZXJ5Q29kZXM=');

@$core.Deprecated('Use startTotpSetupRequestDescriptor instead')
const StartTotpSetupRequest$json = {
  '1': 'StartTotpSetupRequest',
};

/// Descriptor for `StartTotpSetupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startTotpSetupRequestDescriptor =
    $convert.base64Decode('ChVTdGFydFRvdHBTZXR1cFJlcXVlc3Q=');

@$core.Deprecated('Use startTotpSetupResponseDescriptor instead')
const StartTotpSetupResponse$json = {
  '1': 'StartTotpSetupResponse',
  '2': [
    {'1': 'setup_id', '3': 1, '4': 1, '5': 9, '10': 'setupId'},
    {'1': 'secret', '3': 2, '4': 1, '5': 9, '10': 'secret'},
    {'1': 'uri', '3': 3, '4': 1, '5': 9, '10': 'uri'},
  ],
};

/// Descriptor for `StartTotpSetupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startTotpSetupResponseDescriptor =
    $convert.base64Decode(
        'ChZTdGFydFRvdHBTZXR1cFJlc3BvbnNlEhkKCHNldHVwX2lkGAEgASgJUgdzZXR1cElkEhYKBn'
        'NlY3JldBgCIAEoCVIGc2VjcmV0EhAKA3VyaRgDIAEoCVIDdXJp');

@$core.Deprecated('Use finishTotpSetupRequestDescriptor instead')
const FinishTotpSetupRequest$json = {
  '1': 'FinishTotpSetupRequest',
  '2': [
    {'1': 'setup_id', '3': 1, '4': 1, '5': 9, '10': 'setupId'},
    {'1': 'code', '3': 2, '4': 1, '5': 9, '10': 'code'},
  ],
};

/// Descriptor for `FinishTotpSetupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishTotpSetupRequestDescriptor =
    $convert.base64Decode(
        'ChZGaW5pc2hUb3RwU2V0dXBSZXF1ZXN0EhkKCHNldHVwX2lkGAEgASgJUgdzZXR1cElkEhIKBG'
        'NvZGUYAiABKAlSBGNvZGU=');

@$core.Deprecated('Use finishTotpSetupResponseDescriptor instead')
const FinishTotpSetupResponse$json = {
  '1': 'FinishTotpSetupResponse',
  '2': [
    {'1': 'recovery_codes', '3': 1, '4': 3, '5': 9, '10': 'recoveryCodes'},
  ],
};

/// Descriptor for `FinishTotpSetupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishTotpSetupResponseDescriptor =
    $convert.base64Decode(
        'ChdGaW5pc2hUb3RwU2V0dXBSZXNwb25zZRIlCg5yZWNvdmVyeV9jb2RlcxgBIAMoCVINcmVjb3'
        'ZlcnlDb2Rlcw==');

@$core.Deprecated('Use listSecondFactorsRequestDescriptor instead')
const ListSecondFactorsRequest$json = {
  '1': 'ListSecondFactorsRequest',
};

/// Descriptor for `ListSecondFactorsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSecondFactorsRequestDescriptor =
    $convert.base64Decode('ChhMaXN0U2Vjb25kRmFjdG9yc1JlcXVlc3Q=');

@$core.Deprecated('Use listSecondFactorsResponseDescriptor instead')
const ListSecondFactorsResponse$json = {
  '1': 'ListSecondFactorsResponse',
  '2': [
    {
      '1': 'passkeys',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.Passkey',
      '10': 'passkeys'
    },
    {'1': 'totp', '3': 2, '4': 1, '5': 8, '10': 'totp'},
    {
      '1': 'recovery_codes_left',
      '3': 3,
      '4': 1,
      '5': 13,
      '10': 'recoveryCodesLeft'
    },
  ],
};

/// Descriptor for `ListSecondFactorsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSecondFactorsResponseDescriptor = $convert.base64Decode(
    'ChlMaXN0U2Vjb25kRmFjdG9yc1Jlc3BvbnNlEjQKCHBhc3NrZXlzGAEgAygLMhgucGhvdG9saW'
    'IuYXBpLnYxLlBhc3NrZXlSCHBhc3NrZXlzEhIKBHRvdHAYAiABKAhSBHRvdHASLgoTcmVjb3Zl'
    'cnlfY29kZXNfbGVmdBgDIAEoDVIRcmVjb3ZlcnlDb2Rlc0xlZnQ=');

@$core.Deprecated('Use deletePasskeyRequestDescriptor instead')
const DeletePasskeyRequest$json = {
  '1': 'DeletePasskeyRequest',
  '2': [
    {'1': 'passkey_id', '3': 1, '4': 1, '5': 9, '10': 'passkeyId'},
  ],
};

/// Descriptor for `DeletePasskeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deletePasskeyRequestDescriptor = $convert.base64Decode(
    'ChREZWxldGVQYXNza2V5UmVxdWVzdBIdCgpwYXNza2V5X2lkGAEgASgJUglwYXNza2V5SWQ=');

@$core.Deprecated('Use deletePasskeyResponseDescriptor instead')
const DeletePasskeyResponse$json = {
  '1': 'DeletePasskeyResponse',
};

/// Descriptor for `DeletePasskeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deletePasskeyResponseDescriptor =
    $convert.base64Decode('ChVEZWxldGVQYXNza2V5UmVzcG9uc2U=');

@$core.Deprecated('Use deleteTotpRequestDescriptor instead')
const DeleteTotpRequest$json = {
  '1': 'DeleteTotpRequest',
};

/// Descriptor for `DeleteTotpRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteTotpRequestDescriptor =
    $convert.base64Decode('ChFEZWxldGVUb3RwUmVxdWVzdA==');

@$core.Deprecated('Use deleteTotpResponseDescriptor instead')
const DeleteTotpResponse$json = {
  '1': 'DeleteTotpResponse',
};

/// Descriptor for `DeleteTotpResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteTotpResponseDescriptor =
    $convert.base64Decode('ChJEZWxldGVUb3RwUmVzcG9uc2U=');

@$core.Deprecated('Use createRecoveryCodesRequestDescriptor instead')
const CreateRecoveryCodesRequest$json = {
  '1': 'CreateRecoveryCodesRequest',
};

/// Descriptor for `CreateRecoveryCodesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createRecoveryCodesRequestDescriptor =
    $convert.base64Decode('ChpDcmVhdGVSZWNvdmVyeUNvZGVzUmVxdWVzdA==');

@$core.Deprecated('Use createRecoveryCodesResponseDescriptor instead')
const CreateRecoveryCodesResponse$json = {
  '1': 'CreateRecoveryCodesResponse',
  '2': [
    {'1': 'recovery_codes', '3': 1, '4': 3, '5': 9, '10': 'recoveryCodes'},
  ],
};

/// Descriptor for `CreateRecoveryCodesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createRecoveryCodesResponseDescriptor =
    $convert.base64Decode(
        'ChtDcmVhdGVSZWNvdmVyeUNvZGVzUmVzcG9uc2USJQoOcmVjb3ZlcnlfY29kZXMYASADKAlSDX'
        'JlY292ZXJ5Q29kZXM=');

@$core.Deprecated('Use startStepUpRequestDescriptor instead')
const StartStepUpRequest$json = {
  '1': 'StartStepUpRequest',
  '2': [
    {'1': 'ke1', '3': 1, '4': 1, '5': 12, '10': 'ke1'},
  ],
};

/// Descriptor for `StartStepUpRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startStepUpRequestDescriptor = $convert
    .base64Decode('ChJTdGFydFN0ZXBVcFJlcXVlc3QSEAoDa2UxGAEgASgMUgNrZTE=');

@$core.Deprecated('Use startStepUpResponseDescriptor instead')
const StartStepUpResponse$json = {
  '1': 'StartStepUpResponse',
  '2': [
    {'1': 'step_up_id', '3': 1, '4': 1, '5': 9, '10': 'stepUpId'},
    {'1': 'ke2', '3': 2, '4': 1, '5': 12, '10': 'ke2'},
    {'1': 'ksf_params', '3': 3, '4': 1, '5': 12, '10': 'ksfParams'},
    {
      '1': 'factors',
      '3': 4,
      '4': 3,
      '5': 14,
      '6': '.photolib.api.v1.SecondFactor',
      '10': 'factors'
    },
    {
      '1': 'passkey_options_json',
      '3': 5,
      '4': 1,
      '5': 9,
      '10': 'passkeyOptionsJson'
    },
  ],
};

/// Descriptor for `StartStepUpResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startStepUpResponseDescriptor = $convert.base64Decode(
    'ChNTdGFydFN0ZXBVcFJlc3BvbnNlEhwKCnN0ZXBfdXBfaWQYASABKAlSCHN0ZXBVcElkEhAKA2'
    'tlMhgCIAEoDFIDa2UyEh0KCmtzZl9wYXJhbXMYAyABKAxSCWtzZlBhcmFtcxI3CgdmYWN0b3Jz'
    'GAQgAygOMh0ucGhvdG9saWIuYXBpLnYxLlNlY29uZEZhY3RvclIHZmFjdG9ycxIwChRwYXNza2'
    'V5X29wdGlvbnNfanNvbhgFIAEoCVIScGFzc2tleU9wdGlvbnNKc29u');

@$core.Deprecated('Use finishStepUpRequestDescriptor instead')
const FinishStepUpRequest$json = {
  '1': 'FinishStepUpRequest',
  '2': [
    {'1': 'step_up_id', '3': 1, '4': 1, '5': 9, '10': 'stepUpId'},
    {'1': 'ke3', '3': 2, '4': 1, '5': 12, '9': 0, '10': 'ke3'},
    {'1': 'totp_code', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'totpCode'},
    {
      '1': 'recovery_code',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'recoveryCode'
    },
    {
      '1': 'passkey_credential_json',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'passkeyCredentialJson'
    },
  ],
  '8': [
    {'1': 'answer'},
  ],
};

/// Descriptor for `FinishStepUpRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishStepUpRequestDescriptor = $convert.base64Decode(
    'ChNGaW5pc2hTdGVwVXBSZXF1ZXN0EhwKCnN0ZXBfdXBfaWQYASABKAlSCHN0ZXBVcElkEhIKA2'
    'tlMxgCIAEoDEgAUgNrZTMSHQoJdG90cF9jb2RlGAMgASgJSABSCHRvdHBDb2RlEiUKDXJlY292'
    'ZXJ5X2NvZGUYBCABKAlIAFIMcmVjb3ZlcnlDb2RlEjgKF3Bhc3NrZXlfY3JlZGVudGlhbF9qc2'
    '9uGAUgASgJSABSFXBhc3NrZXlDcmVkZW50aWFsSnNvbkIICgZhbnN3ZXI=');

@$core.Deprecated('Use finishStepUpResponseDescriptor instead')
const FinishStepUpResponse$json = {
  '1': 'FinishStepUpResponse',
};

/// Descriptor for `FinishStepUpResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishStepUpResponseDescriptor =
    $convert.base64Decode('ChRGaW5pc2hTdGVwVXBSZXNwb25zZQ==');

const $core.Map<$core.String, $core.dynamic> AuthServiceBase$json = {
  '1': 'AuthService',
  '2': [
    {
      '1': 'StartPasswordSetup',
      '2': '.photolib.api.v1.StartPasswordSetupRequest',
      '3': '.photolib.api.v1.StartPasswordSetupResponse'
    },
    {
      '1': 'FinishPasswordSetup',
      '2': '.photolib.api.v1.FinishPasswordSetupRequest',
      '3': '.photolib.api.v1.FinishPasswordSetupResponse'
    },
    {
      '1': 'StartLogin',
      '2': '.photolib.api.v1.StartLoginRequest',
      '3': '.photolib.api.v1.StartLoginResponse'
    },
    {
      '1': 'FinishLogin',
      '2': '.photolib.api.v1.FinishLoginRequest',
      '3': '.photolib.api.v1.FinishLoginResponse'
    },
    {
      '1': 'RotateSession',
      '2': '.photolib.api.v1.RotateSessionRequest',
      '3': '.photolib.api.v1.RotateSessionResponse'
    },
    {
      '1': 'ListDevices',
      '2': '.photolib.api.v1.ListDevicesRequest',
      '3': '.photolib.api.v1.ListDevicesResponse'
    },
    {
      '1': 'RevokeDevice',
      '2': '.photolib.api.v1.RevokeDeviceRequest',
      '3': '.photolib.api.v1.RevokeDeviceResponse'
    },
    {
      '1': 'ReportBackup',
      '2': '.photolib.api.v1.ReportBackupRequest',
      '3': '.photolib.api.v1.ReportBackupResponse'
    },
    {
      '1': 'StartOidc',
      '2': '.photolib.api.v1.StartOidcRequest',
      '3': '.photolib.api.v1.StartOidcResponse'
    },
    {
      '1': 'CompleteOidc',
      '2': '.photolib.api.v1.CompleteOidcRequest',
      '3': '.photolib.api.v1.CompleteOidcResponse'
    },
    {
      '1': 'FinishSecondFactor',
      '2': '.photolib.api.v1.FinishSecondFactorRequest',
      '3': '.photolib.api.v1.FinishSecondFactorResponse'
    },
    {
      '1': 'StartPasskeyLogin',
      '2': '.photolib.api.v1.StartPasskeyLoginRequest',
      '3': '.photolib.api.v1.StartPasskeyLoginResponse'
    },
    {
      '1': 'FinishPasskeyLogin',
      '2': '.photolib.api.v1.FinishPasskeyLoginRequest',
      '3': '.photolib.api.v1.FinishPasskeyLoginResponse'
    },
    {
      '1': 'StartPasskeySetup',
      '2': '.photolib.api.v1.StartPasskeySetupRequest',
      '3': '.photolib.api.v1.StartPasskeySetupResponse'
    },
    {
      '1': 'FinishPasskeySetup',
      '2': '.photolib.api.v1.FinishPasskeySetupRequest',
      '3': '.photolib.api.v1.FinishPasskeySetupResponse'
    },
    {
      '1': 'StartTotpSetup',
      '2': '.photolib.api.v1.StartTotpSetupRequest',
      '3': '.photolib.api.v1.StartTotpSetupResponse'
    },
    {
      '1': 'FinishTotpSetup',
      '2': '.photolib.api.v1.FinishTotpSetupRequest',
      '3': '.photolib.api.v1.FinishTotpSetupResponse'
    },
    {
      '1': 'ListSecondFactors',
      '2': '.photolib.api.v1.ListSecondFactorsRequest',
      '3': '.photolib.api.v1.ListSecondFactorsResponse'
    },
    {
      '1': 'DeletePasskey',
      '2': '.photolib.api.v1.DeletePasskeyRequest',
      '3': '.photolib.api.v1.DeletePasskeyResponse'
    },
    {
      '1': 'DeleteTotp',
      '2': '.photolib.api.v1.DeleteTotpRequest',
      '3': '.photolib.api.v1.DeleteTotpResponse'
    },
    {
      '1': 'CreateRecoveryCodes',
      '2': '.photolib.api.v1.CreateRecoveryCodesRequest',
      '3': '.photolib.api.v1.CreateRecoveryCodesResponse'
    },
    {
      '1': 'StartStepUp',
      '2': '.photolib.api.v1.StartStepUpRequest',
      '3': '.photolib.api.v1.StartStepUpResponse'
    },
    {
      '1': 'FinishStepUp',
      '2': '.photolib.api.v1.FinishStepUpRequest',
      '3': '.photolib.api.v1.FinishStepUpResponse'
    },
  ],
};

@$core.Deprecated('Use authServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    AuthServiceBase$messageJson = {
  '.photolib.api.v1.StartPasswordSetupRequest': StartPasswordSetupRequest$json,
  '.photolib.api.v1.StartPasswordSetupResponse':
      StartPasswordSetupResponse$json,
  '.photolib.api.v1.FinishPasswordSetupRequest':
      FinishPasswordSetupRequest$json,
  '.photolib.api.v1.UnlockPath': $1.UnlockPath$json,
  '.google.protobuf.Timestamp': $0.Timestamp$json,
  '.photolib.api.v1.FinishPasswordSetupResponse':
      FinishPasswordSetupResponse$json,
  '.photolib.api.v1.StartLoginRequest': StartLoginRequest$json,
  '.photolib.api.v1.StartLoginResponse': StartLoginResponse$json,
  '.photolib.api.v1.FinishLoginRequest': FinishLoginRequest$json,
  '.photolib.api.v1.Device': Device$json,
  '.photolib.api.v1.FinishLoginResponse': FinishLoginResponse$json,
  '.photolib.api.v1.Session': Session$json,
  '.photolib.api.v1.SecondFactorChallenge': SecondFactorChallenge$json,
  '.photolib.api.v1.RotateSessionRequest': RotateSessionRequest$json,
  '.photolib.api.v1.RotateSessionResponse': RotateSessionResponse$json,
  '.photolib.api.v1.ListDevicesRequest': ListDevicesRequest$json,
  '.photolib.api.v1.ListDevicesResponse': ListDevicesResponse$json,
  '.photolib.api.v1.RevokeDeviceRequest': RevokeDeviceRequest$json,
  '.photolib.api.v1.RevokeDeviceResponse': RevokeDeviceResponse$json,
  '.photolib.api.v1.ReportBackupRequest': ReportBackupRequest$json,
  '.photolib.api.v1.ReportBackupResponse': ReportBackupResponse$json,
  '.photolib.api.v1.StartOidcRequest': StartOidcRequest$json,
  '.photolib.api.v1.StartOidcResponse': StartOidcResponse$json,
  '.photolib.api.v1.CompleteOidcRequest': CompleteOidcRequest$json,
  '.photolib.api.v1.CompleteOidcResponse': CompleteOidcResponse$json,
  '.photolib.api.v1.FinishSecondFactorRequest': FinishSecondFactorRequest$json,
  '.photolib.api.v1.FinishSecondFactorResponse':
      FinishSecondFactorResponse$json,
  '.photolib.api.v1.StartPasskeyLoginRequest': StartPasskeyLoginRequest$json,
  '.photolib.api.v1.StartPasskeyLoginResponse': StartPasskeyLoginResponse$json,
  '.photolib.api.v1.FinishPasskeyLoginRequest': FinishPasskeyLoginRequest$json,
  '.photolib.api.v1.FinishPasskeyLoginResponse':
      FinishPasskeyLoginResponse$json,
  '.photolib.api.v1.StartPasskeySetupRequest': StartPasskeySetupRequest$json,
  '.photolib.api.v1.StartPasskeySetupResponse': StartPasskeySetupResponse$json,
  '.photolib.api.v1.FinishPasskeySetupRequest': FinishPasskeySetupRequest$json,
  '.photolib.api.v1.FinishPasskeySetupResponse':
      FinishPasskeySetupResponse$json,
  '.photolib.api.v1.Passkey': Passkey$json,
  '.photolib.api.v1.StartTotpSetupRequest': StartTotpSetupRequest$json,
  '.photolib.api.v1.StartTotpSetupResponse': StartTotpSetupResponse$json,
  '.photolib.api.v1.FinishTotpSetupRequest': FinishTotpSetupRequest$json,
  '.photolib.api.v1.FinishTotpSetupResponse': FinishTotpSetupResponse$json,
  '.photolib.api.v1.ListSecondFactorsRequest': ListSecondFactorsRequest$json,
  '.photolib.api.v1.ListSecondFactorsResponse': ListSecondFactorsResponse$json,
  '.photolib.api.v1.DeletePasskeyRequest': DeletePasskeyRequest$json,
  '.photolib.api.v1.DeletePasskeyResponse': DeletePasskeyResponse$json,
  '.photolib.api.v1.DeleteTotpRequest': DeleteTotpRequest$json,
  '.photolib.api.v1.DeleteTotpResponse': DeleteTotpResponse$json,
  '.photolib.api.v1.CreateRecoveryCodesRequest':
      CreateRecoveryCodesRequest$json,
  '.photolib.api.v1.CreateRecoveryCodesResponse':
      CreateRecoveryCodesResponse$json,
  '.photolib.api.v1.StartStepUpRequest': StartStepUpRequest$json,
  '.photolib.api.v1.StartStepUpResponse': StartStepUpResponse$json,
  '.photolib.api.v1.FinishStepUpRequest': FinishStepUpRequest$json,
  '.photolib.api.v1.FinishStepUpResponse': FinishStepUpResponse$json,
};

/// Descriptor for `AuthService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List authServiceDescriptor = $convert.base64Decode(
    'CgtBdXRoU2VydmljZRJtChJTdGFydFBhc3N3b3JkU2V0dXASKi5waG90b2xpYi5hcGkudjEuU3'
    'RhcnRQYXNzd29yZFNldHVwUmVxdWVzdBorLnBob3RvbGliLmFwaS52MS5TdGFydFBhc3N3b3Jk'
    'U2V0dXBSZXNwb25zZRJwChNGaW5pc2hQYXNzd29yZFNldHVwEisucGhvdG9saWIuYXBpLnYxLk'
    'ZpbmlzaFBhc3N3b3JkU2V0dXBSZXF1ZXN0GiwucGhvdG9saWIuYXBpLnYxLkZpbmlzaFBhc3N3'
    'b3JkU2V0dXBSZXNwb25zZRJVCgpTdGFydExvZ2luEiIucGhvdG9saWIuYXBpLnYxLlN0YXJ0TG'
    '9naW5SZXF1ZXN0GiMucGhvdG9saWIuYXBpLnYxLlN0YXJ0TG9naW5SZXNwb25zZRJYCgtGaW5p'
    'c2hMb2dpbhIjLnBob3RvbGliLmFwaS52MS5GaW5pc2hMb2dpblJlcXVlc3QaJC5waG90b2xpYi'
    '5hcGkudjEuRmluaXNoTG9naW5SZXNwb25zZRJeCg1Sb3RhdGVTZXNzaW9uEiUucGhvdG9saWIu'
    'YXBpLnYxLlJvdGF0ZVNlc3Npb25SZXF1ZXN0GiYucGhvdG9saWIuYXBpLnYxLlJvdGF0ZVNlc3'
    'Npb25SZXNwb25zZRJYCgtMaXN0RGV2aWNlcxIjLnBob3RvbGliLmFwaS52MS5MaXN0RGV2aWNl'
    'c1JlcXVlc3QaJC5waG90b2xpYi5hcGkudjEuTGlzdERldmljZXNSZXNwb25zZRJbCgxSZXZva2'
    'VEZXZpY2USJC5waG90b2xpYi5hcGkudjEuUmV2b2tlRGV2aWNlUmVxdWVzdBolLnBob3RvbGli'
    'LmFwaS52MS5SZXZva2VEZXZpY2VSZXNwb25zZRJbCgxSZXBvcnRCYWNrdXASJC5waG90b2xpYi'
    '5hcGkudjEuUmVwb3J0QmFja3VwUmVxdWVzdBolLnBob3RvbGliLmFwaS52MS5SZXBvcnRCYWNr'
    'dXBSZXNwb25zZRJSCglTdGFydE9pZGMSIS5waG90b2xpYi5hcGkudjEuU3RhcnRPaWRjUmVxdW'
    'VzdBoiLnBob3RvbGliLmFwaS52MS5TdGFydE9pZGNSZXNwb25zZRJbCgxDb21wbGV0ZU9pZGMS'
    'JC5waG90b2xpYi5hcGkudjEuQ29tcGxldGVPaWRjUmVxdWVzdBolLnBob3RvbGliLmFwaS52MS'
    '5Db21wbGV0ZU9pZGNSZXNwb25zZRJtChJGaW5pc2hTZWNvbmRGYWN0b3ISKi5waG90b2xpYi5h'
    'cGkudjEuRmluaXNoU2Vjb25kRmFjdG9yUmVxdWVzdBorLnBob3RvbGliLmFwaS52MS5GaW5pc2'
    'hTZWNvbmRGYWN0b3JSZXNwb25zZRJqChFTdGFydFBhc3NrZXlMb2dpbhIpLnBob3RvbGliLmFw'
    'aS52MS5TdGFydFBhc3NrZXlMb2dpblJlcXVlc3QaKi5waG90b2xpYi5hcGkudjEuU3RhcnRQYX'
    'Nza2V5TG9naW5SZXNwb25zZRJtChJGaW5pc2hQYXNza2V5TG9naW4SKi5waG90b2xpYi5hcGku'
    'djEuRmluaXNoUGFzc2tleUxvZ2luUmVxdWVzdBorLnBob3RvbGliLmFwaS52MS5GaW5pc2hQYX'
    'Nza2V5TG9naW5SZXNwb25zZRJqChFTdGFydFBhc3NrZXlTZXR1cBIpLnBob3RvbGliLmFwaS52'
    'MS5TdGFydFBhc3NrZXlTZXR1cFJlcXVlc3QaKi5waG90b2xpYi5hcGkudjEuU3RhcnRQYXNza2'
    'V5U2V0dXBSZXNwb25zZRJtChJGaW5pc2hQYXNza2V5U2V0dXASKi5waG90b2xpYi5hcGkudjEu'
    'RmluaXNoUGFzc2tleVNldHVwUmVxdWVzdBorLnBob3RvbGliLmFwaS52MS5GaW5pc2hQYXNza2'
    'V5U2V0dXBSZXNwb25zZRJhCg5TdGFydFRvdHBTZXR1cBImLnBob3RvbGliLmFwaS52MS5TdGFy'
    'dFRvdHBTZXR1cFJlcXVlc3QaJy5waG90b2xpYi5hcGkudjEuU3RhcnRUb3RwU2V0dXBSZXNwb2'
    '5zZRJkCg9GaW5pc2hUb3RwU2V0dXASJy5waG90b2xpYi5hcGkudjEuRmluaXNoVG90cFNldHVw'
    'UmVxdWVzdBooLnBob3RvbGliLmFwaS52MS5GaW5pc2hUb3RwU2V0dXBSZXNwb25zZRJqChFMaX'
    'N0U2Vjb25kRmFjdG9ycxIpLnBob3RvbGliLmFwaS52MS5MaXN0U2Vjb25kRmFjdG9yc1JlcXVl'
    'c3QaKi5waG90b2xpYi5hcGkudjEuTGlzdFNlY29uZEZhY3RvcnNSZXNwb25zZRJeCg1EZWxldG'
    'VQYXNza2V5EiUucGhvdG9saWIuYXBpLnYxLkRlbGV0ZVBhc3NrZXlSZXF1ZXN0GiYucGhvdG9s'
    'aWIuYXBpLnYxLkRlbGV0ZVBhc3NrZXlSZXNwb25zZRJVCgpEZWxldGVUb3RwEiIucGhvdG9saW'
    'IuYXBpLnYxLkRlbGV0ZVRvdHBSZXF1ZXN0GiMucGhvdG9saWIuYXBpLnYxLkRlbGV0ZVRvdHBS'
    'ZXNwb25zZRJwChNDcmVhdGVSZWNvdmVyeUNvZGVzEisucGhvdG9saWIuYXBpLnYxLkNyZWF0ZV'
    'JlY292ZXJ5Q29kZXNSZXF1ZXN0GiwucGhvdG9saWIuYXBpLnYxLkNyZWF0ZVJlY292ZXJ5Q29k'
    'ZXNSZXNwb25zZRJYCgtTdGFydFN0ZXBVcBIjLnBob3RvbGliLmFwaS52MS5TdGFydFN0ZXBVcF'
    'JlcXVlc3QaJC5waG90b2xpYi5hcGkudjEuU3RhcnRTdGVwVXBSZXNwb25zZRJbCgxGaW5pc2hT'
    'dGVwVXASJC5waG90b2xpYi5hcGkudjEuRmluaXNoU3RlcFVwUmVxdWVzdBolLnBob3RvbGliLm'
    'FwaS52MS5GaW5pc2hTdGVwVXBSZXNwb25zZQ==');
