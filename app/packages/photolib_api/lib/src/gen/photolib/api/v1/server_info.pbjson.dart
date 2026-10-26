// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/server_info.proto.

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

@$core.Deprecated('Use authMethodDescriptor instead')
const AuthMethod$json = {
  '1': 'AuthMethod',
  '2': [
    {'1': 'AUTH_METHOD_UNSPECIFIED', '2': 0},
    {'1': 'AUTH_METHOD_OPAQUE', '2': 1},
    {'1': 'AUTH_METHOD_OIDC', '2': 2},
    {'1': 'AUTH_METHOD_PASSKEY', '2': 3},
  ],
};

/// Descriptor for `AuthMethod`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List authMethodDescriptor = $convert.base64Decode(
    'CgpBdXRoTWV0aG9kEhsKF0FVVEhfTUVUSE9EX1VOU1BFQ0lGSUVEEAASFgoSQVVUSF9NRVRIT0'
    'RfT1BBUVVFEAESFAoQQVVUSF9NRVRIT0RfT0lEQxACEhcKE0FVVEhfTUVUSE9EX1BBU1NLRVkQ'
    'Aw==');

@$core.Deprecated('Use getServerInfoRequestDescriptor instead')
const GetServerInfoRequest$json = {
  '1': 'GetServerInfoRequest',
};

/// Descriptor for `GetServerInfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getServerInfoRequestDescriptor =
    $convert.base64Decode('ChRHZXRTZXJ2ZXJJbmZvUmVxdWVzdA==');

@$core.Deprecated('Use getServerInfoResponseDescriptor instead')
const GetServerInfoResponse$json = {
  '1': 'GetServerInfoResponse',
  '2': [
    {'1': 'api_version', '3': 1, '4': 1, '5': 9, '10': 'apiVersion'},
    {
      '1': 'min_client_version',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'minClientVersion'
    },
    {'1': 'capabilities', '3': 3, '4': 3, '5': 9, '10': 'capabilities'},
    {'1': 'epoch', '3': 4, '4': 1, '5': 9, '10': 'epoch'},
    {
      '1': 'auth_methods',
      '3': 5,
      '4': 3,
      '5': 14,
      '6': '.photolib.api.v1.AuthMethod',
      '10': 'authMethods'
    },
    {
      '1': 'oidc_providers',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.OidcProvider',
      '10': 'oidcProviders'
    },
  ],
};

/// Descriptor for `GetServerInfoResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getServerInfoResponseDescriptor = $convert.base64Decode(
    'ChVHZXRTZXJ2ZXJJbmZvUmVzcG9uc2USHwoLYXBpX3ZlcnNpb24YASABKAlSCmFwaVZlcnNpb2'
    '4SLAoSbWluX2NsaWVudF92ZXJzaW9uGAIgASgJUhBtaW5DbGllbnRWZXJzaW9uEiIKDGNhcGFi'
    'aWxpdGllcxgDIAMoCVIMY2FwYWJpbGl0aWVzEhQKBWVwb2NoGAQgASgJUgVlcG9jaBI+CgxhdX'
    'RoX21ldGhvZHMYBSADKA4yGy5waG90b2xpYi5hcGkudjEuQXV0aE1ldGhvZFILYXV0aE1ldGhv'
    'ZHMSRAoOb2lkY19wcm92aWRlcnMYBiADKAsyHS5waG90b2xpYi5hcGkudjEuT2lkY1Byb3ZpZG'
    'VyUg1vaWRjUHJvdmlkZXJz');

@$core.Deprecated('Use oidcProviderDescriptor instead')
const OidcProvider$json = {
  '1': 'OidcProvider',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `OidcProvider`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List oidcProviderDescriptor = $convert.base64Decode(
    'CgxPaWRjUHJvdmlkZXISDgoCaWQYASABKAlSAmlkEhIKBG5hbWUYAiABKAlSBG5hbWU=');

const $core.Map<$core.String, $core.dynamic> ServerInfoServiceBase$json = {
  '1': 'ServerInfoService',
  '2': [
    {
      '1': 'GetServerInfo',
      '2': '.photolib.api.v1.GetServerInfoRequest',
      '3': '.photolib.api.v1.GetServerInfoResponse'
    },
  ],
};

@$core.Deprecated('Use serverInfoServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    ServerInfoServiceBase$messageJson = {
  '.photolib.api.v1.GetServerInfoRequest': GetServerInfoRequest$json,
  '.photolib.api.v1.GetServerInfoResponse': GetServerInfoResponse$json,
  '.photolib.api.v1.OidcProvider': OidcProvider$json,
};

/// Descriptor for `ServerInfoService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List serverInfoServiceDescriptor = $convert.base64Decode(
    'ChFTZXJ2ZXJJbmZvU2VydmljZRJeCg1HZXRTZXJ2ZXJJbmZvEiUucGhvdG9saWIuYXBpLnYxLk'
    'dldFNlcnZlckluZm9SZXF1ZXN0GiYucGhvdG9saWIuYXBpLnYxLkdldFNlcnZlckluZm9SZXNw'
    'b25zZQ==');
