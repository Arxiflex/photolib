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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/field_mask.pb.dart'
    as $1;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

import 'users.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'users.pbenum.dart';

/// An account on this server.
class User extends $pb.GeneratedMessage {
  factory User({
    $core.String? userId,
    $core.String? handle,
    $core.String? displayName,
    $core.String? email,
    UserRole? role,
    UserStatus? status,
    $fixnum.Int64? quotaBytes,
    $core.String? locale,
    $0.Timestamp? createdAt,
    $0.Timestamp? purgeAt,
  }) {
    final result = User._();
    if (userId != null) result.userId = userId;
    if (handle != null) result.handle = handle;
    if (displayName != null) result.displayName = displayName;
    if (email != null) result.email = email;
    if (role != null) result.role = role;
    if (status != null) result.status = status;
    if (quotaBytes != null) result.quotaBytes = quotaBytes;
    if (locale != null) result.locale = locale;
    if (createdAt != null) result.createdAt = createdAt;
    if (purgeAt != null) result.purgeAt = purgeAt;
    return result;
  }

  User._();

  factory User.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      User()..mergeFromBuffer(data, registry);
  factory User.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      User()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'User',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: User.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'handle')
    ..aOS(3, _omitFieldNames ? '' : 'displayName')
    ..aOS(4, _omitFieldNames ? '' : 'email')
    ..aE<UserRole>(5, _omitFieldNames ? '' : 'role',
        enumValues: UserRole.values)
    ..aE<UserStatus>(6, _omitFieldNames ? '' : 'status',
        enumValues: UserStatus.values)
    ..aInt64(7, _omitFieldNames ? '' : 'quotaBytes')
    ..aOS(8, _omitFieldNames ? '' : 'locale')
    ..aOM<$0.Timestamp>(9, _omitFieldNames ? '' : 'createdAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOM<$0.Timestamp>(10, _omitFieldNames ? '' : 'purgeAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  User clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  User copyWith(void Function(User) updates) =>
      super.copyWith((message) => updates(message as User)) as User;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use User() / User.new instead')
  static User create() => User._();
  static $pb.GeneratedMessage $_createMessage() => User._();
  @$core.override
  User createEmptyInstance() => User._();
  @$core.pragma('dart2js:noInline')
  static User getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<User>(User.$_createMessage);
  static User? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  /// Unique sign-in name: 1 to 64 of a-z, 0-9, ".", "_" and "-", starting with a letter or digit; never changes.
  @$pb.TagNumber(2)
  $core.String get handle => $_getSZ(1);
  @$pb.TagNumber(2)
  set handle($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHandle() => $_has(1);
  @$pb.TagNumber(2)
  void clearHandle() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get displayName => $_getSZ(2);
  @$pb.TagNumber(3)
  set displayName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDisplayName() => $_has(2);
  @$pb.TagNumber(3)
  void clearDisplayName() => $_clearField(3);

  /// Unique when set; empty means none.
  @$pb.TagNumber(4)
  $core.String get email => $_getSZ(3);
  @$pb.TagNumber(4)
  set email($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEmail() => $_has(3);
  @$pb.TagNumber(4)
  void clearEmail() => $_clearField(4);

  @$pb.TagNumber(5)
  UserRole get role => $_getN(4);
  @$pb.TagNumber(5)
  set role(UserRole value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasRole() => $_has(4);
  @$pb.TagNumber(5)
  void clearRole() => $_clearField(5);

  @$pb.TagNumber(6)
  UserStatus get status => $_getN(5);
  @$pb.TagNumber(6)
  set status(UserStatus value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasStatus() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatus() => $_clearField(6);

  /// Storage the account may use; absent means unlimited.
  @$pb.TagNumber(7)
  $fixnum.Int64 get quotaBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set quotaBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasQuotaBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearQuotaBytes() => $_clearField(7);

  /// BCP 47 language tag, e.g. "de-CH"; empty means the server's default.
  @$pb.TagNumber(8)
  $core.String get locale => $_getSZ(7);
  @$pb.TagNumber(8)
  set locale($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLocale() => $_has(7);
  @$pb.TagNumber(8)
  void clearLocale() => $_clearField(8);

  @$pb.TagNumber(9)
  $0.Timestamp get createdAt => $_getN(8);
  @$pb.TagNumber(9)
  set createdAt($0.Timestamp value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasCreatedAt() => $_has(8);
  @$pb.TagNumber(9)
  void clearCreatedAt() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.Timestamp ensureCreatedAt() => $_ensure(8);

  /// When a deleted account is purged; absent for any other status.
  @$pb.TagNumber(10)
  $0.Timestamp get purgeAt => $_getN(9);
  @$pb.TagNumber(10)
  set purgeAt($0.Timestamp value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasPurgeAt() => $_has(9);
  @$pb.TagNumber(10)
  void clearPurgeAt() => $_clearField(10);
  @$pb.TagNumber(10)
  $0.Timestamp ensurePurgeAt() => $_ensure(9);
}

/// The first administrator and the token that allows it.
class CreateFirstAdminRequest extends $pb.GeneratedMessage {
  factory CreateFirstAdminRequest({
    $core.String? setupToken,
    User? user,
  }) {
    final result = CreateFirstAdminRequest._();
    if (setupToken != null) result.setupToken = setupToken;
    if (user != null) result.user = user;
    return result;
  }

  CreateFirstAdminRequest._();

  factory CreateFirstAdminRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateFirstAdminRequest()..mergeFromBuffer(data, registry);
  factory CreateFirstAdminRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateFirstAdminRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateFirstAdminRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateFirstAdminRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'setupToken')
    ..aOM<User>(2, _omitFieldNames ? '' : 'user',
        subBuilder: User.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateFirstAdminRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateFirstAdminRequest copyWith(
          void Function(CreateFirstAdminRequest) updates) =>
      super.copyWith((message) => updates(message as CreateFirstAdminRequest))
          as CreateFirstAdminRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateFirstAdminRequest() / CreateFirstAdminRequest.new instead')
  static CreateFirstAdminRequest create() => CreateFirstAdminRequest._();
  static $pb.GeneratedMessage $_createMessage() => CreateFirstAdminRequest._();
  @$core.override
  CreateFirstAdminRequest createEmptyInstance() => CreateFirstAdminRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateFirstAdminRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateFirstAdminRequest>(
          CreateFirstAdminRequest.$_createMessage);
  static CreateFirstAdminRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get setupToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set setupToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSetupToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearSetupToken() => $_clearField(1);

  /// The administrator; only handle, display_name, email and locale are read.
  @$pb.TagNumber(2)
  User get user => $_getN(1);
  @$pb.TagNumber(2)
  set user(User value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasUser() => $_has(1);
  @$pb.TagNumber(2)
  void clearUser() => $_clearField(2);
  @$pb.TagNumber(2)
  User ensureUser() => $_ensure(1);
}

/// The administrator created.
class CreateFirstAdminResponse extends $pb.GeneratedMessage {
  factory CreateFirstAdminResponse({
    User? user,
    PasswordSetup? passwordSetup,
  }) {
    final result = CreateFirstAdminResponse._();
    if (user != null) result.user = user;
    if (passwordSetup != null) result.passwordSetup = passwordSetup;
    return result;
  }

  CreateFirstAdminResponse._();

  factory CreateFirstAdminResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateFirstAdminResponse()..mergeFromBuffer(data, registry);
  factory CreateFirstAdminResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateFirstAdminResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateFirstAdminResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateFirstAdminResponse.$_createMessage)
    ..aOM<User>(1, _omitFieldNames ? '' : 'user',
        subBuilder: User.$_createMessage)
    ..aOM<PasswordSetup>(2, _omitFieldNames ? '' : 'passwordSetup',
        subBuilder: PasswordSetup.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateFirstAdminResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateFirstAdminResponse copyWith(
          void Function(CreateFirstAdminResponse) updates) =>
      super.copyWith((message) => updates(message as CreateFirstAdminResponse))
          as CreateFirstAdminResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateFirstAdminResponse() / CreateFirstAdminResponse.new instead')
  static CreateFirstAdminResponse create() => CreateFirstAdminResponse._();
  static $pb.GeneratedMessage $_createMessage() => CreateFirstAdminResponse._();
  @$core.override
  CreateFirstAdminResponse createEmptyInstance() =>
      CreateFirstAdminResponse._();
  @$core.pragma('dart2js:noInline')
  static CreateFirstAdminResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateFirstAdminResponse>(
          CreateFirstAdminResponse.$_createMessage);
  static CreateFirstAdminResponse? _defaultInstance;

  @$pb.TagNumber(1)
  User get user => $_getN(0);
  @$pb.TagNumber(1)
  set user(User value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearUser() => $_clearField(1);
  @$pb.TagNumber(1)
  User ensureUser() => $_ensure(0);

  /// Lets the administrator set their password.
  @$pb.TagNumber(2)
  PasswordSetup get passwordSetup => $_getN(1);
  @$pb.TagNumber(2)
  set passwordSetup(PasswordSetup value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPasswordSetup() => $_has(1);
  @$pb.TagNumber(2)
  void clearPasswordSetup() => $_clearField(2);
  @$pb.TagNumber(2)
  PasswordSetup ensurePasswordSetup() => $_ensure(1);
}

/// A one-time token with which a person sets their own password through AuthService, so nobody else learns it. It
/// replaces any earlier token of the account.
class PasswordSetup extends $pb.GeneratedMessage {
  factory PasswordSetup({
    $core.String? token,
    $0.Timestamp? expiresAt,
  }) {
    final result = PasswordSetup._();
    if (token != null) result.token = token;
    if (expiresAt != null) result.expiresAt = expiresAt;
    return result;
  }

  PasswordSetup._();

  factory PasswordSetup.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PasswordSetup()..mergeFromBuffer(data, registry);
  factory PasswordSetup.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PasswordSetup()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PasswordSetup',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: PasswordSetup.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'token')
    ..aOM<$0.Timestamp>(2, _omitFieldNames ? '' : 'expiresAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PasswordSetup clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PasswordSetup copyWith(void Function(PasswordSetup) updates) =>
      super.copyWith((message) => updates(message as PasswordSetup))
          as PasswordSetup;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PasswordSetup() / PasswordSetup.new instead')
  static PasswordSetup create() => PasswordSetup._();
  static $pb.GeneratedMessage $_createMessage() => PasswordSetup._();
  @$core.override
  PasswordSetup createEmptyInstance() => PasswordSetup._();
  @$core.pragma('dart2js:noInline')
  static PasswordSetup getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PasswordSetup>(
          PasswordSetup.$_createMessage);
  static PasswordSetup? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get token => $_getSZ(0);
  @$pb.TagNumber(1)
  set token($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearToken() => $_clearField(1);

  /// Seven days after it was made.
  @$pb.TagNumber(2)
  $0.Timestamp get expiresAt => $_getN(1);
  @$pb.TagNumber(2)
  set expiresAt($0.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasExpiresAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresAt() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Timestamp ensureExpiresAt() => $_ensure(1);
}

/// Asks for every account.
class ListUsersRequest extends $pb.GeneratedMessage {
  factory ListUsersRequest() => ListUsersRequest._();

  ListUsersRequest._();

  factory ListUsersRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListUsersRequest()..mergeFromBuffer(data, registry);
  factory ListUsersRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListUsersRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListUsersRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListUsersRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListUsersRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListUsersRequest copyWith(void Function(ListUsersRequest) updates) =>
      super.copyWith((message) => updates(message as ListUsersRequest))
          as ListUsersRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListUsersRequest() / ListUsersRequest.new instead')
  static ListUsersRequest create() => ListUsersRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListUsersRequest._();
  @$core.override
  ListUsersRequest createEmptyInstance() => ListUsersRequest._();
  @$core.pragma('dart2js:noInline')
  static ListUsersRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListUsersRequest>(
          ListUsersRequest.$_createMessage);
  static ListUsersRequest? _defaultInstance;
}

/// Every account.
class ListUsersResponse extends $pb.GeneratedMessage {
  factory ListUsersResponse({
    $core.Iterable<User>? users,
  }) {
    final result = ListUsersResponse._();
    if (users != null) result.users.addAll(users);
    return result;
  }

  ListUsersResponse._();

  factory ListUsersResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListUsersResponse()..mergeFromBuffer(data, registry);
  factory ListUsersResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListUsersResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListUsersResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListUsersResponse.$_createMessage)
    ..pPM<User>(1, _omitFieldNames ? '' : 'users',
        subBuilder: User.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListUsersResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListUsersResponse copyWith(void Function(ListUsersResponse) updates) =>
      super.copyWith((message) => updates(message as ListUsersResponse))
          as ListUsersResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListUsersResponse() / ListUsersResponse.new instead')
  static ListUsersResponse create() => ListUsersResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListUsersResponse._();
  @$core.override
  ListUsersResponse createEmptyInstance() => ListUsersResponse._();
  @$core.pragma('dart2js:noInline')
  static ListUsersResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListUsersResponse>(
          ListUsersResponse.$_createMessage);
  static ListUsersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<User> get users => $_getList(0);
}

/// The account to create.
class CreateUserRequest extends $pb.GeneratedMessage {
  factory CreateUserRequest({
    User? user,
  }) {
    final result = CreateUserRequest._();
    if (user != null) result.user = user;
    return result;
  }

  CreateUserRequest._();

  factory CreateUserRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateUserRequest()..mergeFromBuffer(data, registry);
  factory CreateUserRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateUserRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateUserRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateUserRequest.$_createMessage)
    ..aOM<User>(1, _omitFieldNames ? '' : 'user',
        subBuilder: User.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateUserRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateUserRequest copyWith(void Function(CreateUserRequest) updates) =>
      super.copyWith((message) => updates(message as CreateUserRequest))
          as CreateUserRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CreateUserRequest() / CreateUserRequest.new instead')
  static CreateUserRequest create() => CreateUserRequest._();
  static $pb.GeneratedMessage $_createMessage() => CreateUserRequest._();
  @$core.override
  CreateUserRequest createEmptyInstance() => CreateUserRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateUserRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateUserRequest>(
          CreateUserRequest.$_createMessage);
  static CreateUserRequest? _defaultInstance;

  /// Only handle, display_name, email, role, quota_bytes and locale are read; role is required.
  @$pb.TagNumber(1)
  User get user => $_getN(0);
  @$pb.TagNumber(1)
  set user(User value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearUser() => $_clearField(1);
  @$pb.TagNumber(1)
  User ensureUser() => $_ensure(0);
}

/// The account created.
class CreateUserResponse extends $pb.GeneratedMessage {
  factory CreateUserResponse({
    User? user,
  }) {
    final result = CreateUserResponse._();
    if (user != null) result.user = user;
    return result;
  }

  CreateUserResponse._();

  factory CreateUserResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateUserResponse()..mergeFromBuffer(data, registry);
  factory CreateUserResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateUserResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateUserResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreateUserResponse.$_createMessage)
    ..aOM<User>(1, _omitFieldNames ? '' : 'user',
        subBuilder: User.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateUserResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateUserResponse copyWith(void Function(CreateUserResponse) updates) =>
      super.copyWith((message) => updates(message as CreateUserResponse))
          as CreateUserResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CreateUserResponse() / CreateUserResponse.new instead')
  static CreateUserResponse create() => CreateUserResponse._();
  static $pb.GeneratedMessage $_createMessage() => CreateUserResponse._();
  @$core.override
  CreateUserResponse createEmptyInstance() => CreateUserResponse._();
  @$core.pragma('dart2js:noInline')
  static CreateUserResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateUserResponse>(
          CreateUserResponse.$_createMessage);
  static CreateUserResponse? _defaultInstance;

  @$pb.TagNumber(1)
  User get user => $_getN(0);
  @$pb.TagNumber(1)
  set user(User value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearUser() => $_clearField(1);
  @$pb.TagNumber(1)
  User ensureUser() => $_ensure(0);
}

/// The changes to an account.
class UpdateUserRequest extends $pb.GeneratedMessage {
  factory UpdateUserRequest({
    User? user,
    $1.FieldMask? updateMask,
  }) {
    final result = UpdateUserRequest._();
    if (user != null) result.user = user;
    if (updateMask != null) result.updateMask = updateMask;
    return result;
  }

  UpdateUserRequest._();

  factory UpdateUserRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UpdateUserRequest()..mergeFromBuffer(data, registry);
  factory UpdateUserRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UpdateUserRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateUserRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: UpdateUserRequest.$_createMessage)
    ..aOM<User>(1, _omitFieldNames ? '' : 'user',
        subBuilder: User.$_createMessage)
    ..aOM<$1.FieldMask>(2, _omitFieldNames ? '' : 'updateMask',
        subBuilder: $1.FieldMask.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateUserRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateUserRequest copyWith(void Function(UpdateUserRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateUserRequest))
          as UpdateUserRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UpdateUserRequest() / UpdateUserRequest.new instead')
  static UpdateUserRequest create() => UpdateUserRequest._();
  static $pb.GeneratedMessage $_createMessage() => UpdateUserRequest._();
  @$core.override
  UpdateUserRequest createEmptyInstance() => UpdateUserRequest._();
  @$core.pragma('dart2js:noInline')
  static UpdateUserRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UpdateUserRequest>(
          UpdateUserRequest.$_createMessage);
  static UpdateUserRequest? _defaultInstance;

  /// The account `user.user_id`, with the new values of the fields that `update_mask` names.
  @$pb.TagNumber(1)
  User get user => $_getN(0);
  @$pb.TagNumber(1)
  set user(User value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearUser() => $_clearField(1);
  @$pb.TagNumber(1)
  User ensureUser() => $_ensure(0);

  /// Some of display_name, email, role, status (active or disabled), quota_bytes and locale.
  @$pb.TagNumber(2)
  $1.FieldMask get updateMask => $_getN(1);
  @$pb.TagNumber(2)
  set updateMask($1.FieldMask value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasUpdateMask() => $_has(1);
  @$pb.TagNumber(2)
  void clearUpdateMask() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.FieldMask ensureUpdateMask() => $_ensure(1);
}

/// The account after the change.
class UpdateUserResponse extends $pb.GeneratedMessage {
  factory UpdateUserResponse({
    User? user,
  }) {
    final result = UpdateUserResponse._();
    if (user != null) result.user = user;
    return result;
  }

  UpdateUserResponse._();

  factory UpdateUserResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UpdateUserResponse()..mergeFromBuffer(data, registry);
  factory UpdateUserResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UpdateUserResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateUserResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: UpdateUserResponse.$_createMessage)
    ..aOM<User>(1, _omitFieldNames ? '' : 'user',
        subBuilder: User.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateUserResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateUserResponse copyWith(void Function(UpdateUserResponse) updates) =>
      super.copyWith((message) => updates(message as UpdateUserResponse))
          as UpdateUserResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UpdateUserResponse() / UpdateUserResponse.new instead')
  static UpdateUserResponse create() => UpdateUserResponse._();
  static $pb.GeneratedMessage $_createMessage() => UpdateUserResponse._();
  @$core.override
  UpdateUserResponse createEmptyInstance() => UpdateUserResponse._();
  @$core.pragma('dart2js:noInline')
  static UpdateUserResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateUserResponse>(
          UpdateUserResponse.$_createMessage);
  static UpdateUserResponse? _defaultInstance;

  @$pb.TagNumber(1)
  User get user => $_getN(0);
  @$pb.TagNumber(1)
  set user(User value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearUser() => $_clearField(1);
  @$pb.TagNumber(1)
  User ensureUser() => $_ensure(0);
}

/// The account to delete.
class DeleteUserRequest extends $pb.GeneratedMessage {
  factory DeleteUserRequest({
    $core.String? userId,
  }) {
    final result = DeleteUserRequest._();
    if (userId != null) result.userId = userId;
    return result;
  }

  DeleteUserRequest._();

  factory DeleteUserRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteUserRequest()..mergeFromBuffer(data, registry);
  factory DeleteUserRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteUserRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteUserRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: DeleteUserRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteUserRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteUserRequest copyWith(void Function(DeleteUserRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteUserRequest))
          as DeleteUserRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeleteUserRequest() / DeleteUserRequest.new instead')
  static DeleteUserRequest create() => DeleteUserRequest._();
  static $pb.GeneratedMessage $_createMessage() => DeleteUserRequest._();
  @$core.override
  DeleteUserRequest createEmptyInstance() => DeleteUserRequest._();
  @$core.pragma('dart2js:noInline')
  static DeleteUserRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeleteUserRequest>(
          DeleteUserRequest.$_createMessage);
  static DeleteUserRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);
}

/// The deleted account, with the time it will be purged.
class DeleteUserResponse extends $pb.GeneratedMessage {
  factory DeleteUserResponse({
    User? user,
  }) {
    final result = DeleteUserResponse._();
    if (user != null) result.user = user;
    return result;
  }

  DeleteUserResponse._();

  factory DeleteUserResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteUserResponse()..mergeFromBuffer(data, registry);
  factory DeleteUserResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteUserResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteUserResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: DeleteUserResponse.$_createMessage)
    ..aOM<User>(1, _omitFieldNames ? '' : 'user',
        subBuilder: User.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteUserResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteUserResponse copyWith(void Function(DeleteUserResponse) updates) =>
      super.copyWith((message) => updates(message as DeleteUserResponse))
          as DeleteUserResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeleteUserResponse() / DeleteUserResponse.new instead')
  static DeleteUserResponse create() => DeleteUserResponse._();
  static $pb.GeneratedMessage $_createMessage() => DeleteUserResponse._();
  @$core.override
  DeleteUserResponse createEmptyInstance() => DeleteUserResponse._();
  @$core.pragma('dart2js:noInline')
  static DeleteUserResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteUserResponse>(
          DeleteUserResponse.$_createMessage);
  static DeleteUserResponse? _defaultInstance;

  @$pb.TagNumber(1)
  User get user => $_getN(0);
  @$pb.TagNumber(1)
  set user(User value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearUser() => $_clearField(1);
  @$pb.TagNumber(1)
  User ensureUser() => $_ensure(0);
}

/// The account that needs a password.
class CreatePasswordSetupRequest extends $pb.GeneratedMessage {
  factory CreatePasswordSetupRequest({
    $core.String? userId,
  }) {
    final result = CreatePasswordSetupRequest._();
    if (userId != null) result.userId = userId;
    return result;
  }

  CreatePasswordSetupRequest._();

  factory CreatePasswordSetupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreatePasswordSetupRequest()..mergeFromBuffer(data, registry);
  factory CreatePasswordSetupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreatePasswordSetupRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreatePasswordSetupRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreatePasswordSetupRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePasswordSetupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePasswordSetupRequest copyWith(
          void Function(CreatePasswordSetupRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CreatePasswordSetupRequest))
          as CreatePasswordSetupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreatePasswordSetupRequest() / CreatePasswordSetupRequest.new instead')
  static CreatePasswordSetupRequest create() => CreatePasswordSetupRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      CreatePasswordSetupRequest._();
  @$core.override
  CreatePasswordSetupRequest createEmptyInstance() =>
      CreatePasswordSetupRequest._();
  @$core.pragma('dart2js:noInline')
  static CreatePasswordSetupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreatePasswordSetupRequest>(
          CreatePasswordSetupRequest.$_createMessage);
  static CreatePasswordSetupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);
}

/// The token to hand to the account's owner.
class CreatePasswordSetupResponse extends $pb.GeneratedMessage {
  factory CreatePasswordSetupResponse({
    PasswordSetup? passwordSetup,
  }) {
    final result = CreatePasswordSetupResponse._();
    if (passwordSetup != null) result.passwordSetup = passwordSetup;
    return result;
  }

  CreatePasswordSetupResponse._();

  factory CreatePasswordSetupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreatePasswordSetupResponse()..mergeFromBuffer(data, registry);
  factory CreatePasswordSetupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreatePasswordSetupResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreatePasswordSetupResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: CreatePasswordSetupResponse.$_createMessage)
    ..aOM<PasswordSetup>(1, _omitFieldNames ? '' : 'passwordSetup',
        subBuilder: PasswordSetup.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePasswordSetupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePasswordSetupResponse copyWith(
          void Function(CreatePasswordSetupResponse) updates) =>
      super.copyWith(
              (message) => updates(message as CreatePasswordSetupResponse))
          as CreatePasswordSetupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreatePasswordSetupResponse() / CreatePasswordSetupResponse.new instead')
  static CreatePasswordSetupResponse create() =>
      CreatePasswordSetupResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      CreatePasswordSetupResponse._();
  @$core.override
  CreatePasswordSetupResponse createEmptyInstance() =>
      CreatePasswordSetupResponse._();
  @$core.pragma('dart2js:noInline')
  static CreatePasswordSetupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreatePasswordSetupResponse>(
          CreatePasswordSetupResponse.$_createMessage);
  static CreatePasswordSetupResponse? _defaultInstance;

  @$pb.TagNumber(1)
  PasswordSetup get passwordSetup => $_getN(0);
  @$pb.TagNumber(1)
  set passwordSetup(PasswordSetup value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPasswordSetup() => $_has(0);
  @$pb.TagNumber(1)
  void clearPasswordSetup() => $_clearField(1);
  @$pb.TagNumber(1)
  PasswordSetup ensurePasswordSetup() => $_ensure(0);
}

/// The account whose second factors to remove.
class ResetSecondFactorsRequest extends $pb.GeneratedMessage {
  factory ResetSecondFactorsRequest({
    $core.String? userId,
  }) {
    final result = ResetSecondFactorsRequest._();
    if (userId != null) result.userId = userId;
    return result;
  }

  ResetSecondFactorsRequest._();

  factory ResetSecondFactorsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetSecondFactorsRequest()..mergeFromBuffer(data, registry);
  factory ResetSecondFactorsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetSecondFactorsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResetSecondFactorsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ResetSecondFactorsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetSecondFactorsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetSecondFactorsRequest copyWith(
          void Function(ResetSecondFactorsRequest) updates) =>
      super.copyWith((message) => updates(message as ResetSecondFactorsRequest))
          as ResetSecondFactorsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ResetSecondFactorsRequest() / ResetSecondFactorsRequest.new instead')
  static ResetSecondFactorsRequest create() => ResetSecondFactorsRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      ResetSecondFactorsRequest._();
  @$core.override
  ResetSecondFactorsRequest createEmptyInstance() =>
      ResetSecondFactorsRequest._();
  @$core.pragma('dart2js:noInline')
  static ResetSecondFactorsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResetSecondFactorsRequest>(
          ResetSecondFactorsRequest.$_createMessage);
  static ResetSecondFactorsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);
}

/// The account has no second factor left.
class ResetSecondFactorsResponse extends $pb.GeneratedMessage {
  factory ResetSecondFactorsResponse() => ResetSecondFactorsResponse._();

  ResetSecondFactorsResponse._();

  factory ResetSecondFactorsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetSecondFactorsResponse()..mergeFromBuffer(data, registry);
  factory ResetSecondFactorsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetSecondFactorsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResetSecondFactorsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ResetSecondFactorsResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetSecondFactorsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetSecondFactorsResponse copyWith(
          void Function(ResetSecondFactorsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ResetSecondFactorsResponse))
          as ResetSecondFactorsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ResetSecondFactorsResponse() / ResetSecondFactorsResponse.new instead')
  static ResetSecondFactorsResponse create() => ResetSecondFactorsResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      ResetSecondFactorsResponse._();
  @$core.override
  ResetSecondFactorsResponse createEmptyInstance() =>
      ResetSecondFactorsResponse._();
  @$core.pragma('dart2js:noInline')
  static ResetSecondFactorsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResetSecondFactorsResponse>(
          ResetSecondFactorsResponse.$_createMessage);
  static ResetSecondFactorsResponse? _defaultInstance;
}

/// Turns a new server into a working one. Needs no sign-in.
class SetupServiceApi {
  final $pb.RpcClient _client;

  SetupServiceApi(this._client);

  /// Creates the first administrator. The caller proves that they operate the server with the one-time setup token
  /// that photolibd printed in its log; there are no default credentials. Fails once an administrator exists.
  $async.Future<CreateFirstAdminResponse> createFirstAdmin(
          $pb.ClientContext? ctx, CreateFirstAdminRequest request) =>
      _client.invoke<CreateFirstAdminResponse>(ctx, 'SetupService',
          'CreateFirstAdmin', request, CreateFirstAdminResponse());
}

/// The accounts of this server, for its administrators. Every change is recorded in the audit log.
class UserServiceApi {
  final $pb.RpcClient _client;

  UserServiceApi(this._client);

  /// Returns every account, deleted ones included, by handle.
  $async.Future<ListUsersResponse> listUsers(
          $pb.ClientContext? ctx, ListUsersRequest request) =>
      _client.invoke<ListUsersResponse>(
          ctx, 'UserService', 'ListUsers', request, ListUsersResponse());

  /// Creates an active account.
  $async.Future<CreateUserResponse> createUser(
          $pb.ClientContext? ctx, CreateUserRequest request) =>
      _client.invoke<CreateUserResponse>(
          ctx, 'UserService', 'CreateUser', request, CreateUserResponse());

  /// Changes the fields of an account that `update_mask` names.
  $async.Future<UpdateUserResponse> updateUser(
          $pb.ClientContext? ctx, UpdateUserRequest request) =>
      _client.invoke<UpdateUserResponse>(
          ctx, 'UserService', 'UpdateUser', request, UpdateUserResponse());

  /// Deletes an account: it signs in no more and is purged after a delay, until which UpdateUser restores it (OPS-22).
  $async.Future<DeleteUserResponse> deleteUser(
          $pb.ClientContext? ctx, DeleteUserRequest request) =>
      _client.invoke<DeleteUserResponse>(
          ctx, 'UserService', 'DeleteUser', request, DeleteUserResponse());

  /// Makes a password setup token for an account, to hand to its owner: for a new account or a forgotten password.
  /// The old password works until the new one is set.
  $async.Future<CreatePasswordSetupResponse> createPasswordSetup(
          $pb.ClientContext? ctx, CreatePasswordSetupRequest request) =>
      _client.invoke<CreatePasswordSetupResponse>(ctx, 'UserService',
          'CreatePasswordSetup', request, CreatePasswordSetupResponse());

  /// Removes an account's passkeys, TOTP and recovery codes, for an owner who lost them all: the password alone signs
  /// in again, and where the instance requires a second factor, the account enrols a new one.
  $async.Future<ResetSecondFactorsResponse> resetSecondFactors(
          $pb.ClientContext? ctx, ResetSecondFactorsRequest request) =>
      _client.invoke<ResetSecondFactorsResponse>(ctx, 'UserService',
          'ResetSecondFactors', request, ResetSecondFactorsResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
