// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/search.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// What to find.
class SearchTextRequest extends $pb.GeneratedMessage {
  factory SearchTextRequest({
    $core.String? query,
    $core.int? pageSize,
  }) {
    final result = SearchTextRequest._();
    if (query != null) result.query = query;
    if (pageSize != null) result.pageSize = pageSize;
    return result;
  }

  SearchTextRequest._();

  factory SearchTextRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchTextRequest()..mergeFromBuffer(data, registry);
  factory SearchTextRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchTextRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchTextRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: SearchTextRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'query')
    ..aI(2, _omitFieldNames ? '' : 'pageSize', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchTextRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchTextRequest copyWith(void Function(SearchTextRequest) updates) =>
      super.copyWith((message) => updates(message as SearchTextRequest))
          as SearchTextRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SearchTextRequest() / SearchTextRequest.new instead')
  static SearchTextRequest create() => SearchTextRequest._();
  static $pb.GeneratedMessage $_createMessage() => SearchTextRequest._();
  @$core.override
  SearchTextRequest createEmptyInstance() => SearchTextRequest._();
  @$core.pragma('dart2js:noInline')
  static SearchTextRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SearchTextRequest>(
          SearchTextRequest.$_createMessage);
  static SearchTextRequest? _defaultInstance;

  /// The text to find in pictures, in any case; `%`, `_` and `\` are characters. A blank query finds nothing.
  @$pb.TagNumber(1)
  $core.String get query => $_getSZ(0);
  @$pb.TagNumber(1)
  set query($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => $_clearField(1);

  /// At most this many hits: 1 to 200; 0 means 50.
  @$pb.TagNumber(2)
  $core.int get pageSize => $_getIZ(1);
  @$pb.TagNumber(2)
  set pageSize($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPageSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageSize() => $_clearField(2);
}

/// An asset whose picture holds the text.
class SearchHit extends $pb.GeneratedMessage {
  factory SearchHit({
    $core.String? assetId,
    $core.String? libraryId,
    $core.String? text,
  }) {
    final result = SearchHit._();
    if (assetId != null) result.assetId = assetId;
    if (libraryId != null) result.libraryId = libraryId;
    if (text != null) result.text = text;
    return result;
  }

  SearchHit._();

  factory SearchHit.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchHit()..mergeFromBuffer(data, registry);
  factory SearchHit.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchHit()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchHit',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: SearchHit.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'assetId')
    ..aOS(2, _omitFieldNames ? '' : 'libraryId')
    ..aOS(3, _omitFieldNames ? '' : 'text')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchHit clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchHit copyWith(void Function(SearchHit) updates) =>
      super.copyWith((message) => updates(message as SearchHit)) as SearchHit;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SearchHit() / SearchHit.new instead')
  static SearchHit create() => SearchHit._();
  static $pb.GeneratedMessage $_createMessage() => SearchHit._();
  @$core.override
  SearchHit createEmptyInstance() => SearchHit._();
  @$core.pragma('dart2js:noInline')
  static SearchHit getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SearchHit>(SearchHit.$_createMessage);
  static SearchHit? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get assetId => $_getSZ(0);
  @$pb.TagNumber(1)
  set assetId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAssetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAssetId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get libraryId => $_getSZ(1);
  @$pb.TagNumber(2)
  set libraryId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLibraryId() => $_has(1);
  @$pb.TagNumber(2)
  void clearLibraryId() => $_clearField(2);

  /// All the text OCR read from the picture, lines separated by line breaks.
  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => $_clearField(3);
}

/// The assets that hold the text.
class SearchTextResponse extends $pb.GeneratedMessage {
  factory SearchTextResponse({
    $core.Iterable<SearchHit>? hits,
  }) {
    final result = SearchTextResponse._();
    if (hits != null) result.hits.addAll(hits);
    return result;
  }

  SearchTextResponse._();

  factory SearchTextResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchTextResponse()..mergeFromBuffer(data, registry);
  factory SearchTextResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchTextResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchTextResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: SearchTextResponse.$_createMessage)
    ..pPM<SearchHit>(1, _omitFieldNames ? '' : 'hits',
        subBuilder: SearchHit.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchTextResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchTextResponse copyWith(void Function(SearchTextResponse) updates) =>
      super.copyWith((message) => updates(message as SearchTextResponse))
          as SearchTextResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SearchTextResponse() / SearchTextResponse.new instead')
  static SearchTextResponse create() => SearchTextResponse._();
  static $pb.GeneratedMessage $_createMessage() => SearchTextResponse._();
  @$core.override
  SearchTextResponse createEmptyInstance() => SearchTextResponse._();
  @$core.pragma('dart2js:noInline')
  static SearchTextResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SearchTextResponse>(
          SearchTextResponse.$_createMessage);
  static SearchTextResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SearchHit> get hits => $_getList(0);
}

/// Which picture.
class GetTextRequest extends $pb.GeneratedMessage {
  factory GetTextRequest({
    $core.String? assetId,
  }) {
    final result = GetTextRequest._();
    if (assetId != null) result.assetId = assetId;
    return result;
  }

  GetTextRequest._();

  factory GetTextRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTextRequest()..mergeFromBuffer(data, registry);
  factory GetTextRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTextRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTextRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetTextRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'assetId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTextRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTextRequest copyWith(void Function(GetTextRequest) updates) =>
      super.copyWith((message) => updates(message as GetTextRequest))
          as GetTextRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetTextRequest() / GetTextRequest.new instead')
  static GetTextRequest create() => GetTextRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetTextRequest._();
  @$core.override
  GetTextRequest createEmptyInstance() => GetTextRequest._();
  @$core.pragma('dart2js:noInline')
  static GetTextRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetTextRequest>(
          GetTextRequest.$_createMessage);
  static GetTextRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get assetId => $_getSZ(0);
  @$pb.TagNumber(1)
  set assetId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAssetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAssetId() => $_clearField(1);
}

/// What OCR read from a picture.
class GetTextResponse extends $pb.GeneratedMessage {
  factory GetTextResponse({
    $core.String? text,
    $core.bool? read,
    $core.Iterable<TextRegion>? regions,
  }) {
    final result = GetTextResponse._();
    if (text != null) result.text = text;
    if (read != null) result.read = read;
    if (regions != null) result.regions.addAll(regions);
    return result;
  }

  GetTextResponse._();

  factory GetTextResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTextResponse()..mergeFromBuffer(data, registry);
  factory GetTextResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetTextResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTextResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: GetTextResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'read')
    ..pPM<TextRegion>(3, _omitFieldNames ? '' : 'regions',
        subBuilder: TextRegion.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTextResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTextResponse copyWith(void Function(GetTextResponse) updates) =>
      super.copyWith((message) => updates(message as GetTextResponse))
          as GetTextResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetTextResponse() / GetTextResponse.new instead')
  static GetTextResponse create() => GetTextResponse._();
  static $pb.GeneratedMessage $_createMessage() => GetTextResponse._();
  @$core.override
  GetTextResponse createEmptyInstance() => GetTextResponse._();
  @$core.pragma('dart2js:noInline')
  static GetTextResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetTextResponse>(
          GetTextResponse.$_createMessage);
  static GetTextResponse? _defaultInstance;

  /// Lines separated by line breaks; empty when the picture has no text or has not been read yet.
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  /// Whether OCR has read the picture.
  @$pb.TagNumber(2)
  $core.bool get read => $_getBF(1);
  @$pb.TagNumber(2)
  set read($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRead() => $_has(1);
  @$pb.TagNumber(2)
  void clearRead() => $_clearField(2);

  /// Where each line is in the version of the picture that is current (the edited one after an edit), in reading
  /// order; empty when the picture has no text, has not been read, or was read before regions were kept.
  @$pb.TagNumber(3)
  $pb.PbList<TextRegion> get regions => $_getList(2);
}

/// A line of text and its box, as fractions of the width and height of the current version of the picture.
class TextRegion extends $pb.GeneratedMessage {
  factory TextRegion({
    $core.String? text,
    $core.double? x,
    $core.double? y,
    $core.double? width,
    $core.double? height,
  }) {
    final result = TextRegion._();
    if (text != null) result.text = text;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    return result;
  }

  TextRegion._();

  factory TextRegion.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TextRegion()..mergeFromBuffer(data, registry);
  factory TextRegion.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TextRegion()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TextRegion',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.api.v1'),
      createEmptyInstance: TextRegion.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aD(2, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextRegion clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextRegion copyWith(void Function(TextRegion) updates) =>
      super.copyWith((message) => updates(message as TextRegion)) as TextRegion;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TextRegion() / TextRegion.new instead')
  static TextRegion create() => TextRegion._();
  static $pb.GeneratedMessage $_createMessage() => TextRegion._();
  @$core.override
  TextRegion createEmptyInstance() => TextRegion._();
  @$core.pragma('dart2js:noInline')
  static TextRegion getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TextRegion>(TextRegion.$_createMessage);
  static TextRegion? _defaultInstance;

  /// The line, as data (never markup).
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  /// The box's left and top edges, 0 to 1.
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

  /// Its width and height, 0 to 1.
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
}

/// Search over what the server knows of the assets the caller may view.
class SearchServiceApi {
  final $pb.RpcClient _client;

  SearchServiceApi(this._client);

  /// Returns the assets whose picture holds the text, newest first. The text is what OCR read (M5-08): data from a
  /// picture anyone could have made, so clients show it as text and never as markup.
  $async.Future<SearchTextResponse> searchText(
          $pb.ClientContext? ctx, SearchTextRequest request) =>
      _client.invoke<SearchTextResponse>(
          ctx, 'SearchService', 'SearchText', request, SearchTextResponse());

  /// Returns the text OCR read from one picture, for the viewer to show and copy.
  $async.Future<GetTextResponse> getText(
          $pb.ClientContext? ctx, GetTextRequest request) =>
      _client.invoke<GetTextResponse>(
          ctx, 'SearchService', 'GetText', request, GetTextResponse());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
