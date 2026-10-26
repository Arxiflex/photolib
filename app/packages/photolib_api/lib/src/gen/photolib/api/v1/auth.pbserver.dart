// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/auth.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'auth.pb.dart' as $2;
import 'auth.pbjson.dart';

export 'auth.pb.dart';

abstract class AuthServiceBase extends $pb.GeneratedService {
  $async.Future<$2.StartPasswordSetupResponse> startPasswordSetup(
      $pb.ServerContext ctx, $2.StartPasswordSetupRequest request);
  $async.Future<$2.FinishPasswordSetupResponse> finishPasswordSetup(
      $pb.ServerContext ctx, $2.FinishPasswordSetupRequest request);
  $async.Future<$2.StartLoginResponse> startLogin(
      $pb.ServerContext ctx, $2.StartLoginRequest request);
  $async.Future<$2.FinishLoginResponse> finishLogin(
      $pb.ServerContext ctx, $2.FinishLoginRequest request);
  $async.Future<$2.RotateSessionResponse> rotateSession(
      $pb.ServerContext ctx, $2.RotateSessionRequest request);
  $async.Future<$2.ListDevicesResponse> listDevices(
      $pb.ServerContext ctx, $2.ListDevicesRequest request);
  $async.Future<$2.RevokeDeviceResponse> revokeDevice(
      $pb.ServerContext ctx, $2.RevokeDeviceRequest request);
  $async.Future<$2.ReportBackupResponse> reportBackup(
      $pb.ServerContext ctx, $2.ReportBackupRequest request);
  $async.Future<$2.StartOidcResponse> startOidc(
      $pb.ServerContext ctx, $2.StartOidcRequest request);
  $async.Future<$2.CompleteOidcResponse> completeOidc(
      $pb.ServerContext ctx, $2.CompleteOidcRequest request);
  $async.Future<$2.FinishSecondFactorResponse> finishSecondFactor(
      $pb.ServerContext ctx, $2.FinishSecondFactorRequest request);
  $async.Future<$2.StartPasskeyLoginResponse> startPasskeyLogin(
      $pb.ServerContext ctx, $2.StartPasskeyLoginRequest request);
  $async.Future<$2.FinishPasskeyLoginResponse> finishPasskeyLogin(
      $pb.ServerContext ctx, $2.FinishPasskeyLoginRequest request);
  $async.Future<$2.StartPasskeySetupResponse> startPasskeySetup(
      $pb.ServerContext ctx, $2.StartPasskeySetupRequest request);
  $async.Future<$2.FinishPasskeySetupResponse> finishPasskeySetup(
      $pb.ServerContext ctx, $2.FinishPasskeySetupRequest request);
  $async.Future<$2.StartTotpSetupResponse> startTotpSetup(
      $pb.ServerContext ctx, $2.StartTotpSetupRequest request);
  $async.Future<$2.FinishTotpSetupResponse> finishTotpSetup(
      $pb.ServerContext ctx, $2.FinishTotpSetupRequest request);
  $async.Future<$2.ListSecondFactorsResponse> listSecondFactors(
      $pb.ServerContext ctx, $2.ListSecondFactorsRequest request);
  $async.Future<$2.DeletePasskeyResponse> deletePasskey(
      $pb.ServerContext ctx, $2.DeletePasskeyRequest request);
  $async.Future<$2.DeleteTotpResponse> deleteTotp(
      $pb.ServerContext ctx, $2.DeleteTotpRequest request);
  $async.Future<$2.CreateRecoveryCodesResponse> createRecoveryCodes(
      $pb.ServerContext ctx, $2.CreateRecoveryCodesRequest request);
  $async.Future<$2.StartStepUpResponse> startStepUp(
      $pb.ServerContext ctx, $2.StartStepUpRequest request);
  $async.Future<$2.FinishStepUpResponse> finishStepUp(
      $pb.ServerContext ctx, $2.FinishStepUpRequest request);

  $pb.GeneratedMessage createRequest($core.String methodName) {
    switch (methodName) {
      case 'StartPasswordSetup':
        return $2.StartPasswordSetupRequest();
      case 'FinishPasswordSetup':
        return $2.FinishPasswordSetupRequest();
      case 'StartLogin':
        return $2.StartLoginRequest();
      case 'FinishLogin':
        return $2.FinishLoginRequest();
      case 'RotateSession':
        return $2.RotateSessionRequest();
      case 'ListDevices':
        return $2.ListDevicesRequest();
      case 'RevokeDevice':
        return $2.RevokeDeviceRequest();
      case 'ReportBackup':
        return $2.ReportBackupRequest();
      case 'StartOidc':
        return $2.StartOidcRequest();
      case 'CompleteOidc':
        return $2.CompleteOidcRequest();
      case 'FinishSecondFactor':
        return $2.FinishSecondFactorRequest();
      case 'StartPasskeyLogin':
        return $2.StartPasskeyLoginRequest();
      case 'FinishPasskeyLogin':
        return $2.FinishPasskeyLoginRequest();
      case 'StartPasskeySetup':
        return $2.StartPasskeySetupRequest();
      case 'FinishPasskeySetup':
        return $2.FinishPasskeySetupRequest();
      case 'StartTotpSetup':
        return $2.StartTotpSetupRequest();
      case 'FinishTotpSetup':
        return $2.FinishTotpSetupRequest();
      case 'ListSecondFactors':
        return $2.ListSecondFactorsRequest();
      case 'DeletePasskey':
        return $2.DeletePasskeyRequest();
      case 'DeleteTotp':
        return $2.DeleteTotpRequest();
      case 'CreateRecoveryCodes':
        return $2.CreateRecoveryCodesRequest();
      case 'StartStepUp':
        return $2.StartStepUpRequest();
      case 'FinishStepUp':
        return $2.FinishStepUpRequest();
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $async.Future<$pb.GeneratedMessage> handleCall($pb.ServerContext ctx,
      $core.String methodName, $pb.GeneratedMessage request) {
    switch (methodName) {
      case 'StartPasswordSetup':
        return startPasswordSetup(ctx, request as $2.StartPasswordSetupRequest);
      case 'FinishPasswordSetup':
        return finishPasswordSetup(
            ctx, request as $2.FinishPasswordSetupRequest);
      case 'StartLogin':
        return startLogin(ctx, request as $2.StartLoginRequest);
      case 'FinishLogin':
        return finishLogin(ctx, request as $2.FinishLoginRequest);
      case 'RotateSession':
        return rotateSession(ctx, request as $2.RotateSessionRequest);
      case 'ListDevices':
        return listDevices(ctx, request as $2.ListDevicesRequest);
      case 'RevokeDevice':
        return revokeDevice(ctx, request as $2.RevokeDeviceRequest);
      case 'ReportBackup':
        return reportBackup(ctx, request as $2.ReportBackupRequest);
      case 'StartOidc':
        return startOidc(ctx, request as $2.StartOidcRequest);
      case 'CompleteOidc':
        return completeOidc(ctx, request as $2.CompleteOidcRequest);
      case 'FinishSecondFactor':
        return finishSecondFactor(ctx, request as $2.FinishSecondFactorRequest);
      case 'StartPasskeyLogin':
        return startPasskeyLogin(ctx, request as $2.StartPasskeyLoginRequest);
      case 'FinishPasskeyLogin':
        return finishPasskeyLogin(ctx, request as $2.FinishPasskeyLoginRequest);
      case 'StartPasskeySetup':
        return startPasskeySetup(ctx, request as $2.StartPasskeySetupRequest);
      case 'FinishPasskeySetup':
        return finishPasskeySetup(ctx, request as $2.FinishPasskeySetupRequest);
      case 'StartTotpSetup':
        return startTotpSetup(ctx, request as $2.StartTotpSetupRequest);
      case 'FinishTotpSetup':
        return finishTotpSetup(ctx, request as $2.FinishTotpSetupRequest);
      case 'ListSecondFactors':
        return listSecondFactors(ctx, request as $2.ListSecondFactorsRequest);
      case 'DeletePasskey':
        return deletePasskey(ctx, request as $2.DeletePasskeyRequest);
      case 'DeleteTotp':
        return deleteTotp(ctx, request as $2.DeleteTotpRequest);
      case 'CreateRecoveryCodes':
        return createRecoveryCodes(
            ctx, request as $2.CreateRecoveryCodesRequest);
      case 'StartStepUp':
        return startStepUp(ctx, request as $2.StartStepUpRequest);
      case 'FinishStepUp':
        return finishStepUp(ctx, request as $2.FinishStepUpRequest);
      default:
        throw $core.ArgumentError('Unknown method: $methodName');
    }
  }

  $core.Map<$core.String, $core.dynamic> get $json => AuthServiceBase$json;
  $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
      get $messageJson => AuthServiceBase$messageJson;
}
