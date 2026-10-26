// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/users.proto.

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

import 'package:protobuf/well_known_types/google/protobuf/field_mask.pbjson.dart'
    as $1;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pbjson.dart'
    as $0;

@$core.Deprecated('Use userRoleDescriptor instead')
const UserRole$json = {
  '1': 'UserRole',
  '2': [
    {'1': 'USER_ROLE_UNSPECIFIED', '2': 0},
    {'1': 'USER_ROLE_ADMIN', '2': 1},
    {'1': 'USER_ROLE_USER', '2': 2},
    {'1': 'USER_ROLE_VIEWER', '2': 3},
  ],
};

/// Descriptor for `UserRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List userRoleDescriptor = $convert.base64Decode(
    'CghVc2VyUm9sZRIZChVVU0VSX1JPTEVfVU5TUEVDSUZJRUQQABITCg9VU0VSX1JPTEVfQURNSU'
    '4QARISCg5VU0VSX1JPTEVfVVNFUhACEhQKEFVTRVJfUk9MRV9WSUVXRVIQAw==');

@$core.Deprecated('Use userStatusDescriptor instead')
const UserStatus$json = {
  '1': 'UserStatus',
  '2': [
    {'1': 'USER_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'USER_STATUS_ACTIVE', '2': 1},
    {'1': 'USER_STATUS_DISABLED', '2': 2},
    {'1': 'USER_STATUS_INVITED', '2': 3},
    {'1': 'USER_STATUS_DELETED', '2': 4},
  ],
};

/// Descriptor for `UserStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List userStatusDescriptor = $convert.base64Decode(
    'CgpVc2VyU3RhdHVzEhsKF1VTRVJfU1RBVFVTX1VOU1BFQ0lGSUVEEAASFgoSVVNFUl9TVEFUVV'
    'NfQUNUSVZFEAESGAoUVVNFUl9TVEFUVVNfRElTQUJMRUQQAhIXChNVU0VSX1NUQVRVU19JTlZJ'
    'VEVEEAMSFwoTVVNFUl9TVEFUVVNfREVMRVRFRBAE');

@$core.Deprecated('Use userDescriptor instead')
const User$json = {
  '1': 'User',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'handle', '3': 2, '4': 1, '5': 9, '10': 'handle'},
    {'1': 'display_name', '3': 3, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'email', '3': 4, '4': 1, '5': 9, '10': 'email'},
    {
      '1': 'role',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.photolib.api.v1.UserRole',
      '10': 'role'
    },
    {
      '1': 'status',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.photolib.api.v1.UserStatus',
      '10': 'status'
    },
    {
      '1': 'quota_bytes',
      '3': 7,
      '4': 1,
      '5': 3,
      '9': 0,
      '10': 'quotaBytes',
      '17': true
    },
    {'1': 'locale', '3': 8, '4': 1, '5': 9, '10': 'locale'},
    {
      '1': 'created_at',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'createdAt'
    },
    {
      '1': 'purge_at',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'purgeAt'
    },
  ],
  '8': [
    {'1': '_quota_bytes'},
  ],
};

/// Descriptor for `User`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userDescriptor = $convert.base64Decode(
    'CgRVc2VyEhcKB3VzZXJfaWQYASABKAlSBnVzZXJJZBIWCgZoYW5kbGUYAiABKAlSBmhhbmRsZR'
    'IhCgxkaXNwbGF5X25hbWUYAyABKAlSC2Rpc3BsYXlOYW1lEhQKBWVtYWlsGAQgASgJUgVlbWFp'
    'bBItCgRyb2xlGAUgASgOMhkucGhvdG9saWIuYXBpLnYxLlVzZXJSb2xlUgRyb2xlEjMKBnN0YX'
    'R1cxgGIAEoDjIbLnBob3RvbGliLmFwaS52MS5Vc2VyU3RhdHVzUgZzdGF0dXMSJAoLcXVvdGFf'
    'Ynl0ZXMYByABKANIAFIKcXVvdGFCeXRlc4gBARIWCgZsb2NhbGUYCCABKAlSBmxvY2FsZRI5Cg'
    'pjcmVhdGVkX2F0GAkgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIJY3JlYXRlZEF0'
    'EjUKCHB1cmdlX2F0GAogASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIHcHVyZ2VBdE'
    'IOCgxfcXVvdGFfYnl0ZXM=');

@$core.Deprecated('Use createFirstAdminRequestDescriptor instead')
const CreateFirstAdminRequest$json = {
  '1': 'CreateFirstAdminRequest',
  '2': [
    {'1': 'setup_token', '3': 1, '4': 1, '5': 9, '10': 'setupToken'},
    {
      '1': 'user',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.User',
      '10': 'user'
    },
  ],
};

/// Descriptor for `CreateFirstAdminRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createFirstAdminRequestDescriptor =
    $convert.base64Decode(
        'ChdDcmVhdGVGaXJzdEFkbWluUmVxdWVzdBIfCgtzZXR1cF90b2tlbhgBIAEoCVIKc2V0dXBUb2'
        'tlbhIpCgR1c2VyGAIgASgLMhUucGhvdG9saWIuYXBpLnYxLlVzZXJSBHVzZXI=');

@$core.Deprecated('Use createFirstAdminResponseDescriptor instead')
const CreateFirstAdminResponse$json = {
  '1': 'CreateFirstAdminResponse',
  '2': [
    {
      '1': 'user',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.User',
      '10': 'user'
    },
    {
      '1': 'password_setup',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.PasswordSetup',
      '10': 'passwordSetup'
    },
  ],
};

/// Descriptor for `CreateFirstAdminResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createFirstAdminResponseDescriptor = $convert.base64Decode(
    'ChhDcmVhdGVGaXJzdEFkbWluUmVzcG9uc2USKQoEdXNlchgBIAEoCzIVLnBob3RvbGliLmFwaS'
    '52MS5Vc2VyUgR1c2VyEkUKDnBhc3N3b3JkX3NldHVwGAIgASgLMh4ucGhvdG9saWIuYXBpLnYx'
    'LlBhc3N3b3JkU2V0dXBSDXBhc3N3b3JkU2V0dXA=');

@$core.Deprecated('Use passwordSetupDescriptor instead')
const PasswordSetup$json = {
  '1': 'PasswordSetup',
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
  ],
};

/// Descriptor for `PasswordSetup`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List passwordSetupDescriptor = $convert.base64Decode(
    'Cg1QYXNzd29yZFNldHVwEhQKBXRva2VuGAEgASgJUgV0b2tlbhI5CgpleHBpcmVzX2F0GAIgAS'
    'gLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIJZXhwaXJlc0F0');

@$core.Deprecated('Use listUsersRequestDescriptor instead')
const ListUsersRequest$json = {
  '1': 'ListUsersRequest',
};

/// Descriptor for `ListUsersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listUsersRequestDescriptor =
    $convert.base64Decode('ChBMaXN0VXNlcnNSZXF1ZXN0');

@$core.Deprecated('Use listUsersResponseDescriptor instead')
const ListUsersResponse$json = {
  '1': 'ListUsersResponse',
  '2': [
    {
      '1': 'users',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.User',
      '10': 'users'
    },
  ],
};

/// Descriptor for `ListUsersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listUsersResponseDescriptor = $convert.base64Decode(
    'ChFMaXN0VXNlcnNSZXNwb25zZRIrCgV1c2VycxgBIAMoCzIVLnBob3RvbGliLmFwaS52MS5Vc2'
    'VyUgV1c2Vycw==');

@$core.Deprecated('Use createUserRequestDescriptor instead')
const CreateUserRequest$json = {
  '1': 'CreateUserRequest',
  '2': [
    {
      '1': 'user',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.User',
      '10': 'user'
    },
  ],
};

/// Descriptor for `CreateUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createUserRequestDescriptor = $convert.base64Decode(
    'ChFDcmVhdGVVc2VyUmVxdWVzdBIpCgR1c2VyGAEgASgLMhUucGhvdG9saWIuYXBpLnYxLlVzZX'
    'JSBHVzZXI=');

@$core.Deprecated('Use createUserResponseDescriptor instead')
const CreateUserResponse$json = {
  '1': 'CreateUserResponse',
  '2': [
    {
      '1': 'user',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.User',
      '10': 'user'
    },
  ],
};

/// Descriptor for `CreateUserResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createUserResponseDescriptor = $convert.base64Decode(
    'ChJDcmVhdGVVc2VyUmVzcG9uc2USKQoEdXNlchgBIAEoCzIVLnBob3RvbGliLmFwaS52MS5Vc2'
    'VyUgR1c2Vy');

@$core.Deprecated('Use updateUserRequestDescriptor instead')
const UpdateUserRequest$json = {
  '1': 'UpdateUserRequest',
  '2': [
    {
      '1': 'user',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.User',
      '10': 'user'
    },
    {
      '1': 'update_mask',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.FieldMask',
      '10': 'updateMask'
    },
  ],
};

/// Descriptor for `UpdateUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateUserRequestDescriptor = $convert.base64Decode(
    'ChFVcGRhdGVVc2VyUmVxdWVzdBIpCgR1c2VyGAEgASgLMhUucGhvdG9saWIuYXBpLnYxLlVzZX'
    'JSBHVzZXISOwoLdXBkYXRlX21hc2sYAiABKAsyGi5nb29nbGUucHJvdG9idWYuRmllbGRNYXNr'
    'Ugp1cGRhdGVNYXNr');

@$core.Deprecated('Use updateUserResponseDescriptor instead')
const UpdateUserResponse$json = {
  '1': 'UpdateUserResponse',
  '2': [
    {
      '1': 'user',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.User',
      '10': 'user'
    },
  ],
};

/// Descriptor for `UpdateUserResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateUserResponseDescriptor = $convert.base64Decode(
    'ChJVcGRhdGVVc2VyUmVzcG9uc2USKQoEdXNlchgBIAEoCzIVLnBob3RvbGliLmFwaS52MS5Vc2'
    'VyUgR1c2Vy');

@$core.Deprecated('Use deleteUserRequestDescriptor instead')
const DeleteUserRequest$json = {
  '1': 'DeleteUserRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `DeleteUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteUserRequestDescriptor = $convert.base64Decode(
    'ChFEZWxldGVVc2VyUmVxdWVzdBIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQ=');

@$core.Deprecated('Use deleteUserResponseDescriptor instead')
const DeleteUserResponse$json = {
  '1': 'DeleteUserResponse',
  '2': [
    {
      '1': 'user',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.User',
      '10': 'user'
    },
  ],
};

/// Descriptor for `DeleteUserResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteUserResponseDescriptor = $convert.base64Decode(
    'ChJEZWxldGVVc2VyUmVzcG9uc2USKQoEdXNlchgBIAEoCzIVLnBob3RvbGliLmFwaS52MS5Vc2'
    'VyUgR1c2Vy');

@$core.Deprecated('Use createPasswordSetupRequestDescriptor instead')
const CreatePasswordSetupRequest$json = {
  '1': 'CreatePasswordSetupRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `CreatePasswordSetupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createPasswordSetupRequestDescriptor =
    $convert.base64Decode(
        'ChpDcmVhdGVQYXNzd29yZFNldHVwUmVxdWVzdBIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQ=');

@$core.Deprecated('Use createPasswordSetupResponseDescriptor instead')
const CreatePasswordSetupResponse$json = {
  '1': 'CreatePasswordSetupResponse',
  '2': [
    {
      '1': 'password_setup',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.api.v1.PasswordSetup',
      '10': 'passwordSetup'
    },
  ],
};

/// Descriptor for `CreatePasswordSetupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createPasswordSetupResponseDescriptor =
    $convert.base64Decode(
        'ChtDcmVhdGVQYXNzd29yZFNldHVwUmVzcG9uc2USRQoOcGFzc3dvcmRfc2V0dXAYASABKAsyHi'
        '5waG90b2xpYi5hcGkudjEuUGFzc3dvcmRTZXR1cFINcGFzc3dvcmRTZXR1cA==');

@$core.Deprecated('Use resetSecondFactorsRequestDescriptor instead')
const ResetSecondFactorsRequest$json = {
  '1': 'ResetSecondFactorsRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `ResetSecondFactorsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resetSecondFactorsRequestDescriptor =
    $convert.base64Decode(
        'ChlSZXNldFNlY29uZEZhY3RvcnNSZXF1ZXN0EhcKB3VzZXJfaWQYASABKAlSBnVzZXJJZA==');

@$core.Deprecated('Use resetSecondFactorsResponseDescriptor instead')
const ResetSecondFactorsResponse$json = {
  '1': 'ResetSecondFactorsResponse',
};

/// Descriptor for `ResetSecondFactorsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resetSecondFactorsResponseDescriptor =
    $convert.base64Decode('ChpSZXNldFNlY29uZEZhY3RvcnNSZXNwb25zZQ==');

const $core.Map<$core.String, $core.dynamic> SetupServiceBase$json = {
  '1': 'SetupService',
  '2': [
    {
      '1': 'CreateFirstAdmin',
      '2': '.photolib.api.v1.CreateFirstAdminRequest',
      '3': '.photolib.api.v1.CreateFirstAdminResponse'
    },
  ],
};

@$core.Deprecated('Use setupServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    SetupServiceBase$messageJson = {
  '.photolib.api.v1.CreateFirstAdminRequest': CreateFirstAdminRequest$json,
  '.photolib.api.v1.User': User$json,
  '.google.protobuf.Timestamp': $0.Timestamp$json,
  '.photolib.api.v1.CreateFirstAdminResponse': CreateFirstAdminResponse$json,
  '.photolib.api.v1.PasswordSetup': PasswordSetup$json,
};

/// Descriptor for `SetupService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List setupServiceDescriptor = $convert.base64Decode(
    'CgxTZXR1cFNlcnZpY2USZwoQQ3JlYXRlRmlyc3RBZG1pbhIoLnBob3RvbGliLmFwaS52MS5Dcm'
    'VhdGVGaXJzdEFkbWluUmVxdWVzdBopLnBob3RvbGliLmFwaS52MS5DcmVhdGVGaXJzdEFkbWlu'
    'UmVzcG9uc2U=');

const $core.Map<$core.String, $core.dynamic> UserServiceBase$json = {
  '1': 'UserService',
  '2': [
    {
      '1': 'ListUsers',
      '2': '.photolib.api.v1.ListUsersRequest',
      '3': '.photolib.api.v1.ListUsersResponse'
    },
    {
      '1': 'CreateUser',
      '2': '.photolib.api.v1.CreateUserRequest',
      '3': '.photolib.api.v1.CreateUserResponse'
    },
    {
      '1': 'UpdateUser',
      '2': '.photolib.api.v1.UpdateUserRequest',
      '3': '.photolib.api.v1.UpdateUserResponse'
    },
    {
      '1': 'DeleteUser',
      '2': '.photolib.api.v1.DeleteUserRequest',
      '3': '.photolib.api.v1.DeleteUserResponse'
    },
    {
      '1': 'CreatePasswordSetup',
      '2': '.photolib.api.v1.CreatePasswordSetupRequest',
      '3': '.photolib.api.v1.CreatePasswordSetupResponse'
    },
    {
      '1': 'ResetSecondFactors',
      '2': '.photolib.api.v1.ResetSecondFactorsRequest',
      '3': '.photolib.api.v1.ResetSecondFactorsResponse'
    },
  ],
};

@$core.Deprecated('Use userServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    UserServiceBase$messageJson = {
  '.photolib.api.v1.ListUsersRequest': ListUsersRequest$json,
  '.photolib.api.v1.ListUsersResponse': ListUsersResponse$json,
  '.photolib.api.v1.User': User$json,
  '.google.protobuf.Timestamp': $0.Timestamp$json,
  '.photolib.api.v1.CreateUserRequest': CreateUserRequest$json,
  '.photolib.api.v1.CreateUserResponse': CreateUserResponse$json,
  '.photolib.api.v1.UpdateUserRequest': UpdateUserRequest$json,
  '.google.protobuf.FieldMask': $1.FieldMask$json,
  '.photolib.api.v1.UpdateUserResponse': UpdateUserResponse$json,
  '.photolib.api.v1.DeleteUserRequest': DeleteUserRequest$json,
  '.photolib.api.v1.DeleteUserResponse': DeleteUserResponse$json,
  '.photolib.api.v1.CreatePasswordSetupRequest':
      CreatePasswordSetupRequest$json,
  '.photolib.api.v1.CreatePasswordSetupResponse':
      CreatePasswordSetupResponse$json,
  '.photolib.api.v1.PasswordSetup': PasswordSetup$json,
  '.photolib.api.v1.ResetSecondFactorsRequest': ResetSecondFactorsRequest$json,
  '.photolib.api.v1.ResetSecondFactorsResponse':
      ResetSecondFactorsResponse$json,
};

/// Descriptor for `UserService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List userServiceDescriptor = $convert.base64Decode(
    'CgtVc2VyU2VydmljZRJSCglMaXN0VXNlcnMSIS5waG90b2xpYi5hcGkudjEuTGlzdFVzZXJzUm'
    'VxdWVzdBoiLnBob3RvbGliLmFwaS52MS5MaXN0VXNlcnNSZXNwb25zZRJVCgpDcmVhdGVVc2Vy'
    'EiIucGhvdG9saWIuYXBpLnYxLkNyZWF0ZVVzZXJSZXF1ZXN0GiMucGhvdG9saWIuYXBpLnYxLk'
    'NyZWF0ZVVzZXJSZXNwb25zZRJVCgpVcGRhdGVVc2VyEiIucGhvdG9saWIuYXBpLnYxLlVwZGF0'
    'ZVVzZXJSZXF1ZXN0GiMucGhvdG9saWIuYXBpLnYxLlVwZGF0ZVVzZXJSZXNwb25zZRJVCgpEZW'
    'xldGVVc2VyEiIucGhvdG9saWIuYXBpLnYxLkRlbGV0ZVVzZXJSZXF1ZXN0GiMucGhvdG9saWIu'
    'YXBpLnYxLkRlbGV0ZVVzZXJSZXNwb25zZRJwChNDcmVhdGVQYXNzd29yZFNldHVwEisucGhvdG'
    '9saWIuYXBpLnYxLkNyZWF0ZVBhc3N3b3JkU2V0dXBSZXF1ZXN0GiwucGhvdG9saWIuYXBpLnYx'
    'LkNyZWF0ZVBhc3N3b3JkU2V0dXBSZXNwb25zZRJtChJSZXNldFNlY29uZEZhY3RvcnMSKi5waG'
    '90b2xpYi5hcGkudjEuUmVzZXRTZWNvbmRGYWN0b3JzUmVxdWVzdBorLnBob3RvbGliLmFwaS52'
    'MS5SZXNldFNlY29uZEZhY3RvcnNSZXNwb25zZQ==');
