// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/users.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'users.pb.dart' as $2;
import 'users.pbjson.dart';

export 'users.pb.dart';

abstract class SetupServiceBase extends $pb.GeneratedService {
  $async.Future<$2.CreateFirstAdminResponse> createFirstAdmin(
      $pb.ServerContext ctx, $2.CreateFirstAdminRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'CreateFirstAdmin':
        return $2.CreateFirstAdminRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'CreateFirstAdmin':
        return createFirstAdmin(ctx, request as $2.CreateFirstAdminRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => SetupServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => SetupServiceBase$messageJson;
}

abstract class UserServiceBase extends $pb.GeneratedService {
  $async.Future<$2.ListUsersResponse> listUsers(
      $pb.ServerContext ctx, $2.ListUsersRequest request);
  $async.Future<$2.CreateUserResponse> createUser(
      $pb.ServerContext ctx, $2.CreateUserRequest request);
  $async.Future<$2.UpdateUserResponse> updateUser(
      $pb.ServerContext ctx, $2.UpdateUserRequest request);
  $async.Future<$2.DeleteUserResponse> deleteUser(
      $pb.ServerContext ctx, $2.DeleteUserRequest request);
  $async.Future<$2.CreatePasswordSetupResponse> createPasswordSetup(
      $pb.ServerContext ctx, $2.CreatePasswordSetupRequest request);
  $async.Future<$2.ResetSecondFactorsResponse> resetSecondFactors(
      $pb.ServerContext ctx, $2.ResetSecondFactorsRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'ListUsers':
        return $2.ListUsersRequest();
      case 'CreateUser':
        return $2.CreateUserRequest();
      case 'UpdateUser':
        return $2.UpdateUserRequest();
      case 'DeleteUser':
        return $2.DeleteUserRequest();
      case 'CreatePasswordSetup':
        return $2.CreatePasswordSetupRequest();
      case 'ResetSecondFactors':
        return $2.ResetSecondFactorsRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'ListUsers':
        return listUsers(ctx, request as $2.ListUsersRequest);
      case 'CreateUser':
        return createUser(ctx, request as $2.CreateUserRequest);
      case 'UpdateUser':
        return updateUser(ctx, request as $2.UpdateUserRequest);
      case 'DeleteUser':
        return deleteUser(ctx, request as $2.DeleteUserRequest);
      case 'CreatePasswordSetup':
        return createPasswordSetup(
            ctx, request as $2.CreatePasswordSetupRequest);
      case 'ResetSecondFactors':
        return resetSecondFactors(ctx, request as $2.ResetSecondFactorsRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => UserServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => UserServiceBase$messageJson;
}
