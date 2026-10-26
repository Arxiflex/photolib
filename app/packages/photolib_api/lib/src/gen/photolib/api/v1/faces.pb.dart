// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/faces.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The question.
class GetFaceConsentRequest extends $pb.GeneratedMessage {
  factory GetFaceConsentRequest() => GetFaceConsentRequest._();

  GetFaceConsentRequest._();

  factory GetFaceConsentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFaceConsentRequest()..mergeFromBuffer(data, registry);
  factory GetFaceConsentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFaceConsentRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetFaceConsentRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetFaceConsentRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFaceConsentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFaceConsentRequest copyWith(
          void Function(GetFaceConsentRequest) updates) =>
      super.copyWith((message) => updates(message as GetFaceConsentRequest))
          as GetFaceConsentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetFaceConsentRequest() / GetFaceConsentRequest.new instead')
  static GetFaceConsentRequest create() => GetFaceConsentRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetFaceConsentRequest._();
  @$core.override
  GetFaceConsentRequest createEmptyInstance() => GetFaceConsentRequest._();
  @$core.pragma('dart2js:noInline')
  static GetFaceConsentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetFaceConsentRequest>(
          GetFaceConsentRequest.$_createMessage);
  static GetFaceConsentRequest? _defaultInstance;
}

/// Where the account stands.
class FaceConsentState extends $pb.GeneratedMessage {
  factory FaceConsentState({
    $core.int? noticeVersion,
    $core.bool? granted,
    $core.int? grantedVersion,
    $0.Timestamp? grantedAt,
    $core.bool? available,
  }) {
    final result = FaceConsentState._();
    if (noticeVersion != null) result.noticeVersion = noticeVersion;
    if (granted != null) result.granted = granted;
    if (grantedVersion != null) result.grantedVersion = grantedVersion;
    if (grantedAt != null) result.grantedAt = grantedAt;
    if (available != null) result.available = available;
    return result;
  }

  FaceConsentState._();

  factory FaceConsentState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FaceConsentState()..mergeFromBuffer(data, registry);
  factory FaceConsentState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FaceConsentState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FaceConsentState',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: FaceConsentState.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'noticeVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(2, _omitFieldNames ? '' : 'granted')
    ..aI(3, _omitFieldNames ? '' : 'grantedVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<$0.Timestamp>(4, _omitFieldNames ? '' : 'grantedAt',
        subBuilder: $0.Timestamp.$_createMessage)
    ..aOB(5, _omitFieldNames ? '' : 'available')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FaceConsentState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FaceConsentState copyWith(void Function(FaceConsentState) updates) =>
      super.copyWith((message) => updates(message as FaceConsentState))
          as FaceConsentState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FaceConsentState() / FaceConsentState.new instead')
  static FaceConsentState create() => FaceConsentState._();
  static $pb.GeneratedMessage $_createMessage() => FaceConsentState._();
  @$core.override
  FaceConsentState createEmptyInstance() => FaceConsentState._();
  @$core.pragma('dart2js:noInline')
  static FaceConsentState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FaceConsentState>(
          FaceConsentState.$_createMessage);
  static FaceConsentState? _defaultInstance;

  /// The version of the consent notice this server asks for; apps show the text of that version.
  @$pb.TagNumber(1)
  $core.int get noticeVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set noticeVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNoticeVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearNoticeVersion() => $_clearField(1);

  /// Whether the account agreed, and to which version of the notice (0 while it has not).
  @$pb.TagNumber(2)
  $core.bool get granted => $_getBF(1);
  @$pb.TagNumber(2)
  set granted($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGranted() => $_has(1);
  @$pb.TagNumber(2)
  void clearGranted() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get grantedVersion => $_getIZ(2);
  @$pb.TagNumber(3)
  set grantedVersion($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGrantedVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearGrantedVersion() => $_clearField(3);

  /// When it agreed; absent while it has not.
  @$pb.TagNumber(4)
  $0.Timestamp get grantedAt => $_getN(3);
  @$pb.TagNumber(4)
  set grantedAt($0.Timestamp value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasGrantedAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearGrantedAt() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.Timestamp ensureGrantedAt() => $_ensure(3);

  /// Whether the server's policy allows face recognition for the account at all. When it does not, agreeing changes
  /// nothing and no face is found.
  @$pb.TagNumber(5)
  $core.bool get available => $_getBF(4);
  @$pb.TagNumber(5)
  set available($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAvailable() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvailable() => $_clearField(5);
}

/// The answer.
class GetFaceConsentResponse extends $pb.GeneratedMessage {
  factory GetFaceConsentResponse({
    FaceConsentState? state,
  }) {
    final result = GetFaceConsentResponse._();
    if (state != null) result.state = state;
    return result;
  }

  GetFaceConsentResponse._();

  factory GetFaceConsentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFaceConsentResponse()..mergeFromBuffer(data, registry);
  factory GetFaceConsentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFaceConsentResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetFaceConsentResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetFaceConsentResponse.$_createMessage)
    ..aOM<FaceConsentState>(1, _omitFieldNames ? '' : 'state',
        subBuilder: FaceConsentState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFaceConsentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFaceConsentResponse copyWith(
          void Function(GetFaceConsentResponse) updates) =>
      super.copyWith((message) => updates(message as GetFaceConsentResponse))
          as GetFaceConsentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetFaceConsentResponse() / GetFaceConsentResponse.new instead')
  static GetFaceConsentResponse create() => GetFaceConsentResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetFaceConsentResponse._();
  @$core.override
  GetFaceConsentResponse createEmptyInstance() => GetFaceConsentResponse._();
  @$core.pragma('dart2js:noInline')
  static GetFaceConsentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetFaceConsentResponse>(
          GetFaceConsentResponse.$_createMessage);
  static GetFaceConsentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  FaceConsentState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(FaceConsentState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);
  @$pb.TagNumber(1)
  FaceConsentState ensureState() => $_ensure(0);
}

/// Agrees or withdraws.
class SetFaceConsentRequest extends $pb.GeneratedMessage {
  factory SetFaceConsentRequest({
    $core.bool? granted,
    $core.int? noticeVersion,
  }) {
    final result = SetFaceConsentRequest._();
    if (granted != null) result.granted = granted;
    if (noticeVersion != null) result.noticeVersion = noticeVersion;
    return result;
  }

  SetFaceConsentRequest._();

  factory SetFaceConsentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetFaceConsentRequest()..mergeFromBuffer(data, registry);
  factory SetFaceConsentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetFaceConsentRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetFaceConsentRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: SetFaceConsentRequest.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'granted')
    ..aI(2, _omitFieldNames ? '' : 'noticeVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFaceConsentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFaceConsentRequest copyWith(
          void Function(SetFaceConsentRequest) updates) =>
      super.copyWith((message) => updates(message as SetFaceConsentRequest))
          as SetFaceConsentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetFaceConsentRequest() / SetFaceConsentRequest.new instead')
  static SetFaceConsentRequest create() => SetFaceConsentRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetFaceConsentRequest._();
  @$core.override
  SetFaceConsentRequest createEmptyInstance() => SetFaceConsentRequest._();
  @$core.pragma('dart2js:noInline')
  static SetFaceConsentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetFaceConsentRequest>(
          SetFaceConsentRequest.$_createMessage);
  static SetFaceConsentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get granted => $_getBF(0);
  @$pb.TagNumber(1)
  set granted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGranted() => $_has(0);
  @$pb.TagNumber(1)
  void clearGranted() => $_clearField(1);

  /// The version of the notice the account was shown: required, and the current one, when `granted`.
  @$pb.TagNumber(2)
  $core.int get noticeVersion => $_getIZ(1);
  @$pb.TagNumber(2)
  set noticeVersion($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNoticeVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearNoticeVersion() => $_clearField(2);
}

/// The account's state after the change.
class SetFaceConsentResponse extends $pb.GeneratedMessage {
  factory SetFaceConsentResponse({
    FaceConsentState? state,
  }) {
    final result = SetFaceConsentResponse._();
    if (state != null) result.state = state;
    return result;
  }

  SetFaceConsentResponse._();

  factory SetFaceConsentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetFaceConsentResponse()..mergeFromBuffer(data, registry);
  factory SetFaceConsentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetFaceConsentResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetFaceConsentResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: SetFaceConsentResponse.$_createMessage)
    ..aOM<FaceConsentState>(1, _omitFieldNames ? '' : 'state',
        subBuilder: FaceConsentState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFaceConsentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFaceConsentResponse copyWith(
          void Function(SetFaceConsentResponse) updates) =>
      super.copyWith((message) => updates(message as SetFaceConsentResponse))
          as SetFaceConsentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetFaceConsentResponse() / SetFaceConsentResponse.new instead')
  static SetFaceConsentResponse create() => SetFaceConsentResponse._();
  static $pb.GeneratedMessage $_createMessage() => SetFaceConsentResponse._();
  @$core.override
  SetFaceConsentResponse createEmptyInstance() => SetFaceConsentResponse._();
  @$core.pragma('dart2js:noInline')
  static SetFaceConsentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetFaceConsentResponse>(
          SetFaceConsentResponse.$_createMessage);
  static SetFaceConsentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  FaceConsentState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(FaceConsentState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);
  @$pb.TagNumber(1)
  FaceConsentState ensureState() => $_ensure(0);
}

/// The asset to list the faces of.
class ListFacesRequest extends $pb.GeneratedMessage {
  factory ListFacesRequest({
    $core.String? assetId,
  }) {
    final result = ListFacesRequest._();
    if (assetId != null) result.assetId = assetId;
    return result;
  }

  ListFacesRequest._();

  factory ListFacesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListFacesRequest()..mergeFromBuffer(data, registry);
  factory ListFacesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListFacesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListFacesRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListFacesRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'assetId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListFacesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListFacesRequest copyWith(void Function(ListFacesRequest) updates) =>
      super.copyWith((message) => updates(message as ListFacesRequest))
          as ListFacesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListFacesRequest() / ListFacesRequest.new instead')
  static ListFacesRequest create() => ListFacesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListFacesRequest._();
  @$core.override
  ListFacesRequest createEmptyInstance() => ListFacesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListFacesRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListFacesRequest>(
          ListFacesRequest.$_createMessage);
  static ListFacesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get assetId => $_getSZ(0);
  @$pb.TagNumber(1)
  set assetId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAssetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAssetId() => $_clearField(1);
}

/// A face of an asset: where it is, in fractions of the original photo or video frame (upright, as shown).
class AssetFace extends $pb.GeneratedMessage {
  factory AssetFace({
    $core.String? faceId,
    $core.double? x,
    $core.double? y,
    $core.double? width,
    $core.double? height,
    $core.Iterable<$core.double>? landmarks,
    $core.double? score,
    $core.int? timeMs,
    $core.String? modelId,
  }) {
    final result = AssetFace._();
    if (faceId != null) result.faceId = faceId;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (landmarks != null) result.landmarks.addAll(landmarks);
    if (score != null) result.score = score;
    if (timeMs != null) result.timeMs = timeMs;
    if (modelId != null) result.modelId = modelId;
    return result;
  }

  AssetFace._();

  factory AssetFace.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AssetFace()..mergeFromBuffer(data, registry);
  factory AssetFace.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AssetFace()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AssetFace',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: AssetFace.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'faceId')
    ..aD(2, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OF)
    ..p<$core.double>(6, _omitFieldNames ? '' : 'landmarks', $pb.PbFieldType.KF)
    ..aD(7, _omitFieldNames ? '' : 'score', fieldType: $pb.PbFieldType.OF)
    ..aI(8, _omitFieldNames ? '' : 'timeMs', fieldType: $pb.PbFieldType.OU3)
    ..aOS(9, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AssetFace clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AssetFace copyWith(void Function(AssetFace) updates) =>
      super.copyWith((message) => updates(message as AssetFace)) as AssetFace;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AssetFace() / AssetFace.new instead')
  static AssetFace create() => AssetFace._();
  static $pb.GeneratedMessage $_createMessage() => AssetFace._();
  @$core.override
  AssetFace createEmptyInstance() => AssetFace._();
  @$core.pragma('dart2js:noInline')
  static AssetFace getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AssetFace>(AssetFace.$_createMessage);
  static AssetFace? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get faceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set faceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFaceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFaceId() => $_clearField(1);

  /// The box: its top left corner and size.
  @$pb.TagNumber(2)
  $core.double get x => $_getN(1);
  @$pb.TagNumber(2)
  set x($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasX() => $_has(1);
  @$pb.TagNumber(2)
  void clearX() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get y => $_getN(2);
  @$pb.TagNumber(3)
  set y($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasY() => $_has(2);
  @$pb.TagNumber(3)
  void clearY() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get width => $_getN(3);
  @$pb.TagNumber(4)
  set width($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasWidth() => $_has(3);
  @$pb.TagNumber(4)
  void clearWidth() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get height => $_getN(4);
  @$pb.TagNumber(5)
  set height($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeight() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeight() => $_clearField(5);

  /// The right eye, left eye, nose and right and left mouth corners as x, y pairs; empty when not kept.
  @$pb.TagNumber(6)
  $pb.PbList<$core.double> get landmarks => $_getList(5);

  /// The detector's confidence, 0 to 1.
  @$pb.TagNumber(7)
  $core.double get score => $_getN(6);
  @$pb.TagNumber(7)
  set score($core.double value) => $_setFloat(6, value);
  @$pb.TagNumber(7)
  $core.bool hasScore() => $_has(6);
  @$pb.TagNumber(7)
  void clearScore() => $_clearField(7);

  /// For a video, the moment of the keyframe the face was found in, in milliseconds.
  @$pb.TagNumber(8)
  $core.int get timeMs => $_getIZ(7);
  @$pb.TagNumber(8)
  set timeMs($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTimeMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimeMs() => $_clearField(8);

  /// The embedding model, such as `sface@2021dec`.
  @$pb.TagNumber(9)
  $core.String get modelId => $_getSZ(8);
  @$pb.TagNumber(9)
  set modelId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasModelId() => $_has(8);
  @$pb.TagNumber(9)
  void clearModelId() => $_clearField(9);
}

/// The faces found in the asset, best first; empty while none are, or the account has not agreed.
class ListFacesResponse extends $pb.GeneratedMessage {
  factory ListFacesResponse({
    $core.Iterable<AssetFace>? faces,
  }) {
    final result = ListFacesResponse._();
    if (faces != null) result.faces.addAll(faces);
    return result;
  }

  ListFacesResponse._();

  factory ListFacesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListFacesResponse()..mergeFromBuffer(data, registry);
  factory ListFacesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListFacesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListFacesResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: ListFacesResponse.$_createMessage)
    ..pPM<AssetFace>(1, _omitFieldNames ? '' : 'faces',
        subBuilder: AssetFace.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListFacesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListFacesResponse copyWith(void Function(ListFacesResponse) updates) =>
      super.copyWith((message) => updates(message as ListFacesResponse))
          as ListFacesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListFacesResponse() / ListFacesResponse.new instead')
  static ListFacesResponse create() => ListFacesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListFacesResponse._();
  @$core.override
  ListFacesResponse createEmptyInstance() => ListFacesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListFacesResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ListFacesResponse>(
          ListFacesResponse.$_createMessage);
  static ListFacesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<AssetFace> get faces => $_getList(0);
}

/// Faces in photos and videos (ADR-0389). Nothing is found, stored or computed about faces for an account that has not
/// agreed to the notice: the account's consent is the one switch, and withdrawing it deletes what was found.
class FaceServiceApi {
  final $pb.RpcClient _client;

  FaceServiceApi(this._client);

  /// Returns whether the account agreed to face recognition, and the version of the notice apps show.
  $async.Future<GetFaceConsentResponse> getFaceConsent(
          $pb.ClientContext? ctx, GetFaceConsentRequest request) =>
      _client.invoke<GetFaceConsentResponse>(ctx, 'FaceService',
          'GetFaceConsent', request, GetFaceConsentResponse());

  /// Agrees to the notice, or withdraws: withdrawing deletes the faces and embeddings found for the account's assets in
  /// the same transaction. Only the account signed in decides, never an API key.
  $async.Future<SetFaceConsentResponse> setFaceConsent(
          $pb.ClientContext? ctx, SetFaceConsentRequest request) =>
      _client.invoke<SetFaceConsentResponse>(ctx, 'FaceService',
          'SetFaceConsent', request, SetFaceConsentResponse());

  /// Returns the faces found in an asset the caller may view, relative to the original, without their embeddings.
  $async.Future<ListFacesResponse> listFaces(
          $pb.ClientContext? ctx, ListFacesRequest request) =>
      _client.invoke<ListFacesResponse>(
          ctx, 'FaceService', 'ListFaces', request, ListFacesResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
