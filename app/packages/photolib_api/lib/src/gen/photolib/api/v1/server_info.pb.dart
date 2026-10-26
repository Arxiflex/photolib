// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/server_info.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'server_info.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'server_info.pbenum.dart';

/// Asks for the server information.
class GetServerInfoRequest extends $pb.GeneratedMessage {
  factory GetServerInfoRequest() => GetServerInfoRequest._();

  GetServerInfoRequest._();

  factory GetServerInfoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetServerInfoRequest()..mergeFromBuffer(data, registry);
  factory GetServerInfoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetServerInfoRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetServerInfoRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetServerInfoRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetServerInfoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetServerInfoRequest copyWith(void Function(GetServerInfoRequest) updates) =>
      super.copyWith((message) => updates(message as GetServerInfoRequest))
          as GetServerInfoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetServerInfoRequest() / GetServerInfoRequest.new instead')
  static GetServerInfoRequest create() => GetServerInfoRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetServerInfoRequest._();
  @$core.override
  GetServerInfoRequest createEmptyInstance() => GetServerInfoRequest._();
  @$core.pragma('dart2js:noInline')
  static GetServerInfoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetServerInfoRequest>(
          GetServerInfoRequest.$_createMessage);
  static GetServerInfoRequest? _defaultInstance;
}

/// The server information.
class GetServerInfoResponse extends $pb.GeneratedMessage {
  factory GetServerInfoResponse({
    $core.String? apiVersion,
    $core.String? minClientVersion,
    $core.Iterable<$core.String>? capabilities,
    $core.String? epoch,
    $core.Iterable<AuthMethod>? authMethods,
    $core.Iterable<OidcProvider>? oidcProviders,
  }) {
    final result = GetServerInfoResponse._();
    if (apiVersion != null) result.apiVersion = apiVersion;
    if (minClientVersion != null) result.minClientVersion = minClientVersion;
    if (capabilities != null) result.capabilities.addAll(capabilities);
    if (epoch != null) result.epoch = epoch;
    if (authMethods != null) result.authMethods.addAll(authMethods);
    if (oidcProviders != null) result.oidcProviders.addAll(oidcProviders);
    return result;
  }

  GetServerInfoResponse._();

  factory GetServerInfoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetServerInfoResponse()..mergeFromBuffer(data, registry);
  factory GetServerInfoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetServerInfoResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetServerInfoResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetServerInfoResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'apiVersion')
    ..aOS(2, _omitFieldNames ? '' : 'minClientVersion')
    ..pPS(3, _omitFieldNames ? '' : 'capabilities')
    ..aOS(4, _omitFieldNames ? '' : 'epoch')
    ..pc<AuthMethod>(
        5, _omitFieldNames ? '' : 'authMethods', $pb.PbFieldType.KE,
        valueOf: AuthMethod.valueOf,
        enumValues: AuthMethod.values,
        defaultEnumValue: AuthMethod.AUTH_METHOD_UNSPECIFIED)
    ..pPM<OidcProvider>(6, _omitFieldNames ? '' : 'oidcProviders',
        subBuilder: OidcProvider.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetServerInfoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetServerInfoResponse copyWith(
          void Function(GetServerInfoResponse) updates) =>
      super.copyWith((message) => updates(message as GetServerInfoResponse))
          as GetServerInfoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetServerInfoResponse() / GetServerInfoResponse.new instead')
  static GetServerInfoResponse create() => GetServerInfoResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetServerInfoResponse._();
  @$core.override
  GetServerInfoResponse createEmptyInstance() => GetServerInfoResponse._();
  @$core.pragma('dart2js:noInline')
  static GetServerInfoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetServerInfoResponse>(
          GetServerInfoResponse.$_createMessage);
  static GetServerInfoResponse? _defaultInstance;

  /// Version of the API the server implements, e.g. "1.0".
  @$pb.TagNumber(1)
  $core.String get apiVersion => $_getSZ(0);
  @$pb.TagNumber(1)
  set apiVersion($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApiVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearApiVersion() => $_clearField(1);

  /// Oldest app version the server still serves.
  @$pb.TagNumber(2)
  $core.String get minClientVersion => $_getSZ(1);
  @$pb.TagNumber(2)
  set minClientVersion($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinClientVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinClientVersion() => $_clearField(2);

  /// Behaviours the server supports, e.g. "sync.stream.v2"; clients feature-detect on these.
  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get capabilities => $_getList(2);

  /// Changes when the server is restored from a backup, so clients re-verify their backup state.
  @$pb.TagNumber(4)
  $core.String get epoch => $_getSZ(3);
  @$pb.TagNumber(4)
  set epoch($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEpoch() => $_has(3);
  @$pb.TagNumber(4)
  void clearEpoch() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<AuthMethod> get authMethods => $_getList(4);

  /// The OpenID Connect providers people sign in with, for AUTH_METHOD_OIDC.
  @$pb.TagNumber(6)
  $pb.PbList<OidcProvider> get oidcProviders => $_getList(5);
}

/// An OpenID Connect provider of this server.
class OidcProvider extends $pb.GeneratedMessage {
  factory OidcProvider({
    $core.String? id,
    $core.String? name,
  }) {
    final result = OidcProvider._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    return result;
  }

  OidcProvider._();

  factory OidcProvider.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OidcProvider()..mergeFromBuffer(data, registry);
  factory OidcProvider.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OidcProvider()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OidcProvider',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: OidcProvider.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OidcProvider clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OidcProvider copyWith(void Function(OidcProvider) updates) =>
      super.copyWith((message) => updates(message as OidcProvider))
          as OidcProvider;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use OidcProvider() / OidcProvider.new instead')
  static OidcProvider create() => OidcProvider._();
  static $pb.GeneratedMessage $_createMessage() => OidcProvider._();
  @$core.override
  OidcProvider createEmptyInstance() => OidcProvider._();
  @$core.pragma('dart2js:noInline')
  static OidcProvider getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OidcProvider>(
          OidcProvider.$_createMessage);
  static OidcProvider? _defaultInstance;

  /// What AuthService.StartOidc names.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// What the sign-in button says, such as "Authentik".
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);
}

/// What a client needs to know before it talks to a server.
class ServerInfoServiceApi {
  final $pb.RpcClient _client;

  ServerInfoServiceApi(this._client);

  /// Returns the server's API version, capabilities and sign-in methods; needs no authentication.
  $async.Future<GetServerInfoResponse> getServerInfo(
          $pb.ClientContext? ctx, GetServerInfoRequest request) =>
      _client.invoke<GetServerInfoResponse>(ctx, 'ServerInfoService',
          'GetServerInfo', request, GetServerInfoResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
