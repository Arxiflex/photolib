// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/call.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'call.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'call.pbenum.dart';

/// One call into the kernel, whose whole ABI is call(method_id, request) -> response over protobuf bytes.
class CallRequest extends $pb.GeneratedMessage {
  factory CallRequest({
    $core.int? methodId,
    $core.List<$core.int>? request,
  }) {
    final result = CallRequest._();
    if (methodId != null) result.methodId = methodId;
    if (request != null) result.request = request;
    return result;
  }

  CallRequest._();

  factory CallRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CallRequest()..mergeFromBuffer(data, registry);
  factory CallRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CallRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CallRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: CallRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'methodId', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'request', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CallRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CallRequest copyWith(void Function(CallRequest) updates) =>
      super.copyWith((message) => updates(message as CallRequest))
          as CallRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CallRequest() / CallRequest.new instead')
  static CallRequest create() => CallRequest._();
  static $pb.GeneratedMessage $_createMessage() => CallRequest._();
  @$core.override
  CallRequest createEmptyInstance() => CallRequest._();
  @$core.pragma('dart2js:noInline')
  static CallRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallRequest>(
          CallRequest.$_createMessage);
  static CallRequest? _defaultInstance;

  /// Selects the kernel function.
  @$pb.TagNumber(1)
  $core.int get methodId => $_getIZ(0);
  @$pb.TagNumber(1)
  set methodId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMethodId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMethodId() => $_clearField(1);

  /// The protobuf encoding of that function's request message.
  @$pb.TagNumber(2)
  $core.List<$core.int> get request => $_getN(1);
  @$pb.TagNumber(2)
  set request($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequest() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequest() => $_clearField(2);
}

enum CallResponse_Result { response, error, notSet }

/// The result of a kernel call.
class CallResponse extends $pb.GeneratedMessage {
  factory CallResponse({
    $core.List<$core.int>? response,
    CallError? error,
  }) {
    final result = CallResponse._();
    if (response != null) result.response = response;
    if (error != null) result.error = error;
    return result;
  }

  CallResponse._();

  factory CallResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CallResponse()..mergeFromBuffer(data, registry);
  factory CallResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CallResponse()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, CallResponse_Result>
      _CallResponse_ResultByTag = {
    1: CallResponse_Result.response,
    2: CallResponse_Result.error,
    0: CallResponse_Result.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CallResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: CallResponse.$_createMessage)
    ..oo(0, [1, 2])
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'response', $pb.PbFieldType.OY)
    ..aOM<CallError>(2, _omitFieldNames ? '' : 'error',
        subBuilder: CallError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CallResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CallResponse copyWith(void Function(CallResponse) updates) =>
      super.copyWith((message) => updates(message as CallResponse))
          as CallResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CallResponse() / CallResponse.new instead')
  static CallResponse create() => CallResponse._();
  static $pb.GeneratedMessage $_createMessage() => CallResponse._();
  @$core.override
  CallResponse createEmptyInstance() => CallResponse._();
  @$core.pragma('dart2js:noInline')
  static CallResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallResponse>(
          CallResponse.$_createMessage);
  static CallResponse? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  CallResponse_Result whichResult() =>
      _CallResponse_ResultByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearResult() => $_clearField($_whichOneof(0));

  /// The protobuf encoding of the function's response message.
  @$pb.TagNumber(1)
  $core.List<$core.int> get response => $_getN(0);
  @$pb.TagNumber(1)
  set response($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasResponse() => $_has(0);
  @$pb.TagNumber(1)
  void clearResponse() => $_clearField(1);

  @$pb.TagNumber(2)
  CallError get error => $_getN(1);
  @$pb.TagNumber(2)
  set error(CallError value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasError() => $_has(1);
  @$pb.TagNumber(2)
  void clearError() => $_clearField(2);
  @$pb.TagNumber(2)
  CallError ensureError() => $_ensure(1);
}

/// Why a call failed: a code and parameters, never prose, so that clients can localise it.
class CallError extends $pb.GeneratedMessage {
  factory CallError({
    CallErrorCode? code,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? params,
  }) {
    final result = CallError._();
    if (code != null) result.code = code;
    if (params != null) result.params.addEntries(params);
    return result;
  }

  CallError._();

  factory CallError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CallError()..mergeFromBuffer(data, registry);
  factory CallError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CallError()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CallError',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: CallError.$_createMessage)
    ..aE<CallErrorCode>(1, _omitFieldNames ? '' : 'code',
        enumValues: CallErrorCode.values)
    ..m<$core.String, $core.String>(2, _omitFieldNames ? '' : 'params',
        entryClassName: 'CallError.ParamsEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('photolib.kernel.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CallError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CallError copyWith(void Function(CallError) updates) =>
      super.copyWith((message) => updates(message as CallError)) as CallError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CallError() / CallError.new instead')
  static CallError create() => CallError._();
  static $pb.GeneratedMessage $_createMessage() => CallError._();
  @$core.override
  CallError createEmptyInstance() => CallError._();
  @$core.pragma('dart2js:noInline')
  static CallError getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CallError>(CallError.$_createMessage);
  static CallError? _defaultInstance;

  @$pb.TagNumber(1)
  CallErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(CallErrorCode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbMap<$core.String, $core.String> get params => $_getMap(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
