// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/api_keys.proto.

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

@$core.Deprecated('Use apiKeyScopeDescriptor instead')
const ApiKeyScope$json = {
  '1': 'ApiKeyScope',
  '2': [
    {'1': 'API_KEY_SCOPE_UNSPECIFIED', '2': 0},
    {'1': 'API_KEY_SCOPE_VIEW', '2': 1},
    {'1': 'API_KEY_SCOPE_DOWNLOAD', '2': 2},
    {'1': 'API_KEY_SCOPE_CONTRIBUTE', '2': 3},
    {'1': 'API_KEY_SCOPE_EDIT', '2': 4},
    {'1': 'API_KEY_SCOPE_DELETE', '2': 5},
    {'1': 'API_KEY_SCOPE_SHARE', '2': 6},
    {'1': 'API_KEY_SCOPE_MANAGE_USERS', '2': 7},
    {'1': 'API_KEY_SCOPE_MANAGE_SERVER', '2': 8},
  ],
};

/// Descriptor for `ApiKeyScope`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List apiKeyScopeDescriptor = $convert.base64Decode(
    'CgtBcGlLZXlTY29wZRIdChlBUElfS0VZX1NDT1BFX1VOU1BFQ0lGSUVEEAASFgoSQVBJX0tFWV'
    '9TQ09QRV9WSUVXEAESGgoWQVBJX0tFWV9TQ09QRV9ET1dOTE9BRBACEhwKGEFQSV9LRVlfU0NP'
    'UEVfQ09OVFJJQlVURRADEhYKEkFQSV9LRVlfU0NPUEVfRURJVBAEEhgKFEFQSV9LRVlfU0NPUE'
    'VfREVMRVRFEAUSFwoTQVBJX0tFWV9TQ09QRV9TSEFSRRAGEh4KGkFQSV9LRVlfU0NPUEVfTUFO'
    'QUdFX1VTRVJTEAcSHwobQVBJX0tFWV9TQ09QRV9NQU5BR0VfU0VSVkVSEAg=');

@$core.Deprecated('Use apiKeyDescriptor instead')
const ApiKey$json = {
  '1': 'ApiKey',
  '2': [
    {'1': 'api_key_id', '3': 1, '4': 1, '5': 9, '10': 'apiKeyId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'scopes',
      '3': 3,
      '4': 3,
      '5': 14,
      '6': '.photolib.api.v1.ApiKeyScope',
      '10': 'scopes'
    },
    {
      '1': 'expires_at',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'expiresAt'
    },
    {
      '1': 'requests_per_minute',
      '3': 5,
      '4': 1,
      '5': 13,
      '10': 'requestsPerMinute'
    },
    {
      '1': 'created_at',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
    {
      '1': 'last_used_at',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'lastUsedAt'
    },
    {
      '1': 'revoked_at',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'revokedAt'
    },
  ],
};

/// Descriptor for `ApiKey`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List apiKeyDescriptor = $convert.base64Decode(
    'CgZBcGlLZXkSHAoKYXBpX2tleV9pZBgBIAEoCVIIYXBpS2V5SWQSEgoEbmFtZRgCIAEoCVIEbm'
    'FtZRI0CgZzY29wZXMYAyADKA4yHC5waG90b2xpYi5hcGkudjEuQXBpS2V5U2NvcGVSBnNjb3Bl'
    'cxI5CgpleHBpcmVzX2F0GAQgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIJZXhwaX'
    'Jlc0F0Ei4KE3JlcXVlc3RzX3Blcl9taW51dGUYBSABKA1SEXJlcXVlc3RzUGVyTWludXRlEjkK'
    'CmNyZWF0ZWRfYXQYBiABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgljcmVhdGVkQX'
    'QSPAoMbGFzdF91c2VkX2F0GAcgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIKbGFz'
    'dFVzZWRBdBI5CgpyZXZva2VkX2F0GAggASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcF'
    'IJcmV2b2tlZEF0');

@$core.Deprecated('Use listApiKeysRequestDescriptor instead')
const ListApiKeysRequest$json = {
  '1': 'ListApiKeysRequest',
};

/// Descriptor for `ListApiKeysRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listApiKeysRequestDescriptor =
    $convert.base64Decode('ChJMaXN0QXBpS2V5c1JlcXVlc3Q=');

@$core.Deprecated('Use listApiKeysResponseDescriptor instead')
const ListApiKeysResponse$json = {
  '1': 'ListApiKeysResponse',
  '2': [
    {
      '1': 'api_keys',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.ApiKey',
      '10': 'apiKeys'
    },
  ],
};

/// Descriptor for `ListApiKeysResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listApiKeysResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0QXBpS2V5c1Jlc3BvbnNlEjIKCGFwaV9rZXlzGAEgAygLMhcucGhvdG9saWIuYXBpLn'
    'YxLkFwaUtleVIHYXBpS2V5cw==');

@$core.Deprecated('Use createApiKeyRequestDescriptor instead')
const CreateApiKeyRequest$json = {
  '1': 'CreateApiKeyRequest',
  '2': [
    {
      '1': 'api_key',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.ApiKey',
      '10': 'apiKey'
    },
  ],
};

/// Descriptor for `CreateApiKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createApiKeyRequestDescriptor = $convert.base64Decode(
    'ChNDcmVhdGVBcGlLZXlSZXF1ZXN0EjAKB2FwaV9rZXkYASABKAsyFy5waG90b2xpYi5hcGkudj'
    'EuQXBpS2V5UgZhcGlLZXk=');

@$core.Deprecated('Use createApiKeyResponseDescriptor instead')
const CreateApiKeyResponse$json = {
  '1': 'CreateApiKeyResponse',
  '2': [
    {
      '1': 'api_key',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.ApiKey',
      '10': 'apiKey'
    },
    {'1': 'secret', '3': 2, '4': 1, '5': 9, '10': 'secret'},
  ],
};

/// Descriptor for `CreateApiKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createApiKeyResponseDescriptor = $convert.base64Decode(
    'ChRDcmVhdGVBcGlLZXlSZXNwb25zZRIwCgdhcGlfa2V5GAEgASgLMhcucGhvdG9saWIuYXBpLn'
    'YxLkFwaUtleVIGYXBpS2V5EhYKBnNlY3JldBgCIAEoCVIGc2VjcmV0');

@$core.Deprecated('Use revokeApiKeyRequestDescriptor instead')
const RevokeApiKeyRequest$json = {
  '1': 'RevokeApiKeyRequest',
  '2': [
    {'1': 'api_key_id', '3': 1, '4': 1, '5': 9, '10': 'apiKeyId'},
  ],
};

/// Descriptor for `RevokeApiKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeApiKeyRequestDescriptor =
    $convert.base64Decode(
        'ChNSZXZva2VBcGlLZXlSZXF1ZXN0EhwKCmFwaV9rZXlfaWQYASABKAlSCGFwaUtleUlk');

@$core.Deprecated('Use revokeApiKeyResponseDescriptor instead')
const RevokeApiKeyResponse$json = {
  '1': 'RevokeApiKeyResponse',
  '2': [
    {
      '1': 'api_key',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.ApiKey',
      '10': 'apiKey'
    },
  ],
};

/// Descriptor for `RevokeApiKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeApiKeyResponseDescriptor = $convert.base64Decode(
    'ChRSZXZva2VBcGlLZXlSZXNwb25zZRIwCgdhcGlfa2V5GAEgASgLMhcucGhvdG9saWIuYXBpLn'
    'YxLkFwaUtleVIGYXBpS2V5');

const $core.Map<$core.String, $core.dynamic> ApiKeyServiceBase$json = {
  '1': 'ApiKeyService',
  '2': [
    {
      '1': 'ListApiKeys',
      '2': '.photolib.api.v1.ListApiKeysRequest',
      '3': '.photolib.api.v1.ListApiKeysResponse'
    },
    {
      '1': 'CreateApiKey',
      '2': '.photolib.api.v1.CreateApiKeyRequest',
      '3': '.photolib.api.v1.CreateApiKeyResponse'
    },
    {
      '1': 'RevokeApiKey',
      '2': '.photolib.api.v1.RevokeApiKeyRequest',
      '3': '.photolib.api.v1.RevokeApiKeyResponse'
    },
  ],
};

@$core.Deprecated('Use apiKeyServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    ApiKeyServiceBase$messageJson = {
  '.photolib.api.v1.ListApiKeysRequest': ListApiKeysRequest$json,
  '.photolib.api.v1.ListApiKeysResponse': ListApiKeysResponse$json,
  '.photolib.api.v1.ApiKey': ApiKey$json,
  '.google.protobuf.Timestamp': $0.Timestamp$json,
  '.photolib.api.v1.CreateApiKeyRequest': CreateApiKeyRequest$json,
  '.photolib.api.v1.CreateApiKeyResponse': CreateApiKeyResponse$json,
  '.photolib.api.v1.RevokeApiKeyRequest': RevokeApiKeyRequest$json,
  '.photolib.api.v1.RevokeApiKeyResponse': RevokeApiKeyResponse$json,
};

/// Descriptor for `ApiKeyService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List apiKeyServiceDescriptor = $convert.base64Decode(
    'Cg1BcGlLZXlTZXJ2aWNlElgKC0xpc3RBcGlLZXlzEiMucGhvdG9saWIuYXBpLnYxLkxpc3RBcG'
    'lLZXlzUmVxdWVzdBokLnBob3RvbGliLmFwaS52MS5MaXN0QXBpS2V5c1Jlc3BvbnNlElsKDENy'
    'ZWF0ZUFwaUtleRIkLnBob3RvbGliLmFwaS52MS5DcmVhdGVBcGlLZXlSZXF1ZXN0GiUucGhvdG'
    '9saWIuYXBpLnYxLkNyZWF0ZUFwaUtleVJlc3BvbnNlElsKDFJldm9rZUFwaUtleRIkLnBob3Rv'
    'bGliLmFwaS52MS5SZXZva2VBcGlLZXlSZXF1ZXN0GiUucGhvdG9saWIuYXBpLnYxLlJldm9rZU'
    'FwaUtleVJlc3BvbnNl');
