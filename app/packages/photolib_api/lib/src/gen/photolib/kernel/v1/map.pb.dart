// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/map.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Builds a map index of geotagged assets in the keyring; its handle is used by the other map calls until it is dropped.
/// An asset is named by its position in the lists. Assets whose coordinates are not finite or lie off the map are kept
/// out of every result, and times the list may omit.
class MapIndexBuildRequest extends $pb.GeneratedMessage {
  factory MapIndexBuildRequest({
    $core.Iterable<$core.double>? latitudes,
    $core.Iterable<$core.double>? longitudes,
    $core.Iterable<$fixnum.Int64>? times,
  }) {
    final result = MapIndexBuildRequest._();
    if (latitudes != null) result.latitudes.addAll(latitudes);
    if (longitudes != null) result.longitudes.addAll(longitudes);
    if (times != null) result.times.addAll(times);
    return result;
  }

  MapIndexBuildRequest._();

  factory MapIndexBuildRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapIndexBuildRequest()..mergeFromBuffer(data, registry);
  factory MapIndexBuildRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapIndexBuildRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapIndexBuildRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapIndexBuildRequest.$_createMessage)
    ..p<$core.double>(1, _omitFieldNames ? '' : 'latitudes', $pb.PbFieldType.KD)
    ..p<$core.double>(
        2, _omitFieldNames ? '' : 'longitudes', $pb.PbFieldType.KD)
    ..p<$fixnum.Int64>(3, _omitFieldNames ? '' : 'times', $pb.PbFieldType.KS6)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapIndexBuildRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapIndexBuildRequest copyWith(void Function(MapIndexBuildRequest) updates) =>
      super.copyWith((message) => updates(message as MapIndexBuildRequest))
          as MapIndexBuildRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use MapIndexBuildRequest() / MapIndexBuildRequest.new instead')
  static MapIndexBuildRequest create() => MapIndexBuildRequest._();
  static $pb.GeneratedMessage $_createMessage() => MapIndexBuildRequest._();
  @$core.override
  MapIndexBuildRequest createEmptyInstance() => MapIndexBuildRequest._();
  @$core.pragma('dart2js:noInline')
  static MapIndexBuildRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MapIndexBuildRequest>(
          MapIndexBuildRequest.$_createMessage);
  static MapIndexBuildRequest? _defaultInstance;

  /// Latitude in degrees, one per asset.
  @$pb.TagNumber(1)
  $pb.PbList<$core.double> get latitudes => $_getList(0);

  /// Longitude in degrees, one per asset; as many as latitudes, else the request is invalid.
  @$pb.TagNumber(2)
  $pb.PbList<$core.double> get longitudes => $_getList(1);

  /// Capture time in seconds since the epoch, one per asset, or none at all.
  @$pb.TagNumber(3)
  $pb.PbList<$fixnum.Int64> get times => $_getList(2);
}

/// The index the keyring now holds.
class MapIndexBuildResponse extends $pb.GeneratedMessage {
  factory MapIndexBuildResponse({
    $core.int? index,
    $core.int? mapped,
  }) {
    final result = MapIndexBuildResponse._();
    if (index != null) result.index = index;
    if (mapped != null) result.mapped = mapped;
    return result;
  }

  MapIndexBuildResponse._();

  factory MapIndexBuildResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapIndexBuildResponse()..mergeFromBuffer(data, registry);
  factory MapIndexBuildResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapIndexBuildResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapIndexBuildResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapIndexBuildResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'mapped', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapIndexBuildResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapIndexBuildResponse copyWith(
          void Function(MapIndexBuildResponse) updates) =>
      super.copyWith((message) => updates(message as MapIndexBuildResponse))
          as MapIndexBuildResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use MapIndexBuildResponse() / MapIndexBuildResponse.new instead')
  static MapIndexBuildResponse create() => MapIndexBuildResponse._();
  static $pb.GeneratedMessage $_createMessage() => MapIndexBuildResponse._();
  @$core.override
  MapIndexBuildResponse createEmptyInstance() => MapIndexBuildResponse._();
  @$core.pragma('dart2js:noInline')
  static MapIndexBuildResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MapIndexBuildResponse>(
          MapIndexBuildResponse.$_createMessage);
  static MapIndexBuildResponse? _defaultInstance;

  /// The handle of the index in the keyring.
  @$pb.TagNumber(1)
  $core.int get index => $_getIZ(0);
  @$pb.TagNumber(1)
  set index($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);

  /// How many assets the map shows (those with a position on the map).
  @$pb.TagNumber(2)
  $core.int get mapped => $_getIZ(1);
  @$pb.TagNumber(2)
  set mapped($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMapped() => $_has(1);
  @$pb.TagNumber(2)
  void clearMapped() => $_clearField(2);
}

/// Which assets a map call considers: all of them when nothing is set.
class MapFilter extends $pb.GeneratedMessage {
  factory MapFilter({
    $fixnum.Int64? timeFrom,
    $fixnum.Int64? timeTo,
    $core.Iterable<$core.double>? polygon,
  }) {
    final result = MapFilter._();
    if (timeFrom != null) result.timeFrom = timeFrom;
    if (timeTo != null) result.timeTo = timeTo;
    if (polygon != null) result.polygon.addAll(polygon);
    return result;
  }

  MapFilter._();

  factory MapFilter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapFilter()..mergeFromBuffer(data, registry);
  factory MapFilter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapFilter()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapFilter',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapFilter.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'timeFrom', $pb.PbFieldType.OS6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'timeTo', $pb.PbFieldType.OS6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..p<$core.double>(3, _omitFieldNames ? '' : 'polygon', $pb.PbFieldType.KD)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapFilter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapFilter copyWith(void Function(MapFilter) updates) =>
      super.copyWith((message) => updates(message as MapFilter)) as MapFilter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapFilter() / MapFilter.new instead')
  static MapFilter create() => MapFilter._();
  static $pb.GeneratedMessage $_createMessage() => MapFilter._();
  @$core.override
  MapFilter createEmptyInstance() => MapFilter._();
  @$core.pragma('dart2js:noInline')
  static MapFilter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MapFilter>(MapFilter.$_createMessage);
  static MapFilter? _defaultInstance;

  /// Capture time in seconds, both ends included; absent means unbounded.
  @$pb.TagNumber(1)
  $fixnum.Int64 get timeFrom => $_getI64(0);
  @$pb.TagNumber(1)
  set timeFrom($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimeFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimeFrom() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timeTo => $_getI64(1);
  @$pb.TagNumber(2)
  set timeTo($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimeTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimeTo() => $_clearField(2);

  /// A lasso: the vertices of a polygon as latitude, longitude pairs (at least three); empty means no polygon.
  @$pb.TagNumber(3)
  $pb.PbList<$core.double> get polygon => $_getList(2);
}

/// The clusters of a map viewport at an integer zoom; west > east means the box crosses the antimeridian.
class MapQueryRequest extends $pb.GeneratedMessage {
  factory MapQueryRequest({
    $core.int? index,
    $core.double? west,
    $core.double? south,
    $core.double? east,
    $core.double? north,
    $core.int? zoom,
    MapFilter? filter,
  }) {
    final result = MapQueryRequest._();
    if (index != null) result.index = index;
    if (west != null) result.west = west;
    if (south != null) result.south = south;
    if (east != null) result.east = east;
    if (north != null) result.north = north;
    if (zoom != null) result.zoom = zoom;
    if (filter != null) result.filter = filter;
    return result;
  }

  MapQueryRequest._();

  factory MapQueryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapQueryRequest()..mergeFromBuffer(data, registry);
  factory MapQueryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapQueryRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapQueryRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapQueryRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aD(2, _omitFieldNames ? '' : 'west')
    ..aD(3, _omitFieldNames ? '' : 'south')
    ..aD(4, _omitFieldNames ? '' : 'east')
    ..aD(5, _omitFieldNames ? '' : 'north')
    ..aI(6, _omitFieldNames ? '' : 'zoom', fieldType: $pb.PbFieldType.OU3)
    ..aOM<MapFilter>(7, _omitFieldNames ? '' : 'filter',
        subBuilder: MapFilter.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapQueryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapQueryRequest copyWith(void Function(MapQueryRequest) updates) =>
      super.copyWith((message) => updates(message as MapQueryRequest))
          as MapQueryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapQueryRequest() / MapQueryRequest.new instead')
  static MapQueryRequest create() => MapQueryRequest._();
  static $pb.GeneratedMessage $_createMessage() => MapQueryRequest._();
  @$core.override
  MapQueryRequest createEmptyInstance() => MapQueryRequest._();
  @$core.pragma('dart2js:noInline')
  static MapQueryRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MapQueryRequest>(
          MapQueryRequest.$_createMessage);
  static MapQueryRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get index => $_getIZ(0);
  @$pb.TagNumber(1)
  set index($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get west => $_getN(1);
  @$pb.TagNumber(2)
  set west($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWest() => $_has(1);
  @$pb.TagNumber(2)
  void clearWest() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get south => $_getN(2);
  @$pb.TagNumber(3)
  set south($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSouth() => $_has(2);
  @$pb.TagNumber(3)
  void clearSouth() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get east => $_getN(3);
  @$pb.TagNumber(4)
  set east($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEast() => $_has(3);
  @$pb.TagNumber(4)
  void clearEast() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get north => $_getN(4);
  @$pb.TagNumber(5)
  set north($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNorth() => $_has(4);
  @$pb.TagNumber(5)
  void clearNorth() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get zoom => $_getIZ(5);
  @$pb.TagNumber(6)
  set zoom($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasZoom() => $_has(5);
  @$pb.TagNumber(6)
  void clearZoom() => $_clearField(6);

  @$pb.TagNumber(7)
  MapFilter get filter => $_getN(6);
  @$pb.TagNumber(7)
  set filter(MapFilter value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFilter() => $_has(6);
  @$pb.TagNumber(7)
  void clearFilter() => $_clearField(7);
  @$pb.TagNumber(7)
  MapFilter ensureFilter() => $_ensure(6);
}

/// The markers of the viewport.
class MapQueryResponse extends $pb.GeneratedMessage {
  factory MapQueryResponse({
    $core.Iterable<MapCluster>? clusters,
  }) {
    final result = MapQueryResponse._();
    if (clusters != null) result.clusters.addAll(clusters);
    return result;
  }

  MapQueryResponse._();

  factory MapQueryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapQueryResponse()..mergeFromBuffer(data, registry);
  factory MapQueryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapQueryResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapQueryResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapQueryResponse.$_createMessage)
    ..pPM<MapCluster>(1, _omitFieldNames ? '' : 'clusters',
        subBuilder: MapCluster.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapQueryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapQueryResponse copyWith(void Function(MapQueryResponse) updates) =>
      super.copyWith((message) => updates(message as MapQueryResponse))
          as MapQueryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapQueryResponse() / MapQueryResponse.new instead')
  static MapQueryResponse create() => MapQueryResponse._();
  static $pb.GeneratedMessage $_createMessage() => MapQueryResponse._();
  @$core.override
  MapQueryResponse createEmptyInstance() => MapQueryResponse._();
  @$core.pragma('dart2js:noInline')
  static MapQueryResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MapQueryResponse>(
          MapQueryResponse.$_createMessage);
  static MapQueryResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MapCluster> get clusters => $_getList(0);
}

/// One marker: a group of assets, or one asset.
class MapCluster extends $pb.GeneratedMessage {
  factory MapCluster({
    $core.double? latitude,
    $core.double? longitude,
    $core.int? count,
    $core.int? asset,
  }) {
    final result = MapCluster._();
    if (latitude != null) result.latitude = latitude;
    if (longitude != null) result.longitude = longitude;
    if (count != null) result.count = count;
    if (asset != null) result.asset = asset;
    return result;
  }

  MapCluster._();

  factory MapCluster.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapCluster()..mergeFromBuffer(data, registry);
  factory MapCluster.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapCluster()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapCluster',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapCluster.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'latitude')
    ..aD(2, _omitFieldNames ? '' : 'longitude')
    ..aI(3, _omitFieldNames ? '' : 'count', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'asset', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapCluster clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapCluster copyWith(void Function(MapCluster) updates) =>
      super.copyWith((message) => updates(message as MapCluster)) as MapCluster;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapCluster() / MapCluster.new instead')
  static MapCluster create() => MapCluster._();
  static $pb.GeneratedMessage $_createMessage() => MapCluster._();
  @$core.override
  MapCluster createEmptyInstance() => MapCluster._();
  @$core.pragma('dart2js:noInline')
  static MapCluster getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MapCluster>(MapCluster.$_createMessage);
  static MapCluster? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get latitude => $_getN(0);
  @$pb.TagNumber(1)
  set latitude($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatitude() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatitude() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get longitude => $_getN(1);
  @$pb.TagNumber(2)
  set longitude($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLongitude() => $_has(1);
  @$pb.TagNumber(2)
  void clearLongitude() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get count => $_getIZ(2);
  @$pb.TagNumber(3)
  set count($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearCount() => $_clearField(3);

  /// For a single asset, its position in the build request.
  @$pb.TagNumber(4)
  $core.int get asset => $_getIZ(3);
  @$pb.TagNumber(4)
  set asset($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAsset() => $_has(3);
  @$pb.TagNumber(4)
  void clearAsset() => $_clearField(4);
}

/// The assets in a viewport that pass the filter, for the map as a search filter and for a lasso selection.
class MapAssetsRequest extends $pb.GeneratedMessage {
  factory MapAssetsRequest({
    $core.int? index,
    $core.double? west,
    $core.double? south,
    $core.double? east,
    $core.double? north,
    MapFilter? filter,
    $core.int? limit,
  }) {
    final result = MapAssetsRequest._();
    if (index != null) result.index = index;
    if (west != null) result.west = west;
    if (south != null) result.south = south;
    if (east != null) result.east = east;
    if (north != null) result.north = north;
    if (filter != null) result.filter = filter;
    if (limit != null) result.limit = limit;
    return result;
  }

  MapAssetsRequest._();

  factory MapAssetsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapAssetsRequest()..mergeFromBuffer(data, registry);
  factory MapAssetsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapAssetsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapAssetsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapAssetsRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aD(2, _omitFieldNames ? '' : 'west')
    ..aD(3, _omitFieldNames ? '' : 'south')
    ..aD(4, _omitFieldNames ? '' : 'east')
    ..aD(5, _omitFieldNames ? '' : 'north')
    ..aOM<MapFilter>(6, _omitFieldNames ? '' : 'filter',
        subBuilder: MapFilter.$_createMessage)
    ..aI(7, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapAssetsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapAssetsRequest copyWith(void Function(MapAssetsRequest) updates) =>
      super.copyWith((message) => updates(message as MapAssetsRequest))
          as MapAssetsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapAssetsRequest() / MapAssetsRequest.new instead')
  static MapAssetsRequest create() => MapAssetsRequest._();
  static $pb.GeneratedMessage $_createMessage() => MapAssetsRequest._();
  @$core.override
  MapAssetsRequest createEmptyInstance() => MapAssetsRequest._();
  @$core.pragma('dart2js:noInline')
  static MapAssetsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MapAssetsRequest>(
          MapAssetsRequest.$_createMessage);
  static MapAssetsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get index => $_getIZ(0);
  @$pb.TagNumber(1)
  set index($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get west => $_getN(1);
  @$pb.TagNumber(2)
  set west($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWest() => $_has(1);
  @$pb.TagNumber(2)
  void clearWest() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get south => $_getN(2);
  @$pb.TagNumber(3)
  set south($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSouth() => $_has(2);
  @$pb.TagNumber(3)
  void clearSouth() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get east => $_getN(3);
  @$pb.TagNumber(4)
  set east($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEast() => $_has(3);
  @$pb.TagNumber(4)
  void clearEast() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get north => $_getN(4);
  @$pb.TagNumber(5)
  set north($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNorth() => $_has(4);
  @$pb.TagNumber(5)
  void clearNorth() => $_clearField(5);

  @$pb.TagNumber(6)
  MapFilter get filter => $_getN(5);
  @$pb.TagNumber(6)
  set filter(MapFilter value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasFilter() => $_has(5);
  @$pb.TagNumber(6)
  void clearFilter() => $_clearField(6);
  @$pb.TagNumber(6)
  MapFilter ensureFilter() => $_ensure(5);

  /// At most this many assets, in ascending order; 0 means all.
  @$pb.TagNumber(7)
  $core.int get limit => $_getIZ(6);
  @$pb.TagNumber(7)
  set limit($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLimit() => $_has(6);
  @$pb.TagNumber(7)
  void clearLimit() => $_clearField(7);
}

/// The assets of the viewport that pass the filter.
class MapAssetsResponse extends $pb.GeneratedMessage {
  factory MapAssetsResponse({
    $core.Iterable<$core.int>? assets,
    $core.int? total,
  }) {
    final result = MapAssetsResponse._();
    if (assets != null) result.assets.addAll(assets);
    if (total != null) result.total = total;
    return result;
  }

  MapAssetsResponse._();

  factory MapAssetsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapAssetsResponse()..mergeFromBuffer(data, registry);
  factory MapAssetsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapAssetsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapAssetsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapAssetsResponse.$_createMessage)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'assets', $pb.PbFieldType.KU3)
    ..aI(2, _omitFieldNames ? '' : 'total', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapAssetsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapAssetsResponse copyWith(void Function(MapAssetsResponse) updates) =>
      super.copyWith((message) => updates(message as MapAssetsResponse))
          as MapAssetsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MapAssetsResponse() / MapAssetsResponse.new instead')
  static MapAssetsResponse create() => MapAssetsResponse._();
  static $pb.GeneratedMessage $_createMessage() => MapAssetsResponse._();
  @$core.override
  MapAssetsResponse createEmptyInstance() => MapAssetsResponse._();
  @$core.pragma('dart2js:noInline')
  static MapAssetsResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MapAssetsResponse>(
          MapAssetsResponse.$_createMessage);
  static MapAssetsResponse? _defaultInstance;

  /// Positions in the build request, ascending.
  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get assets => $_getList(0);

  /// How many assets pass the filter in all, which exceeds the list when the limit cut it.
  @$pb.TagNumber(2)
  $core.int get total => $_getIZ(1);
  @$pb.TagNumber(2)
  set total($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotal() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotal() => $_clearField(2);
}

/// Forgets an index.
class MapIndexDropRequest extends $pb.GeneratedMessage {
  factory MapIndexDropRequest({
    $core.int? index,
  }) {
    final result = MapIndexDropRequest._();
    if (index != null) result.index = index;
    return result;
  }

  MapIndexDropRequest._();

  factory MapIndexDropRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapIndexDropRequest()..mergeFromBuffer(data, registry);
  factory MapIndexDropRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapIndexDropRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapIndexDropRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapIndexDropRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapIndexDropRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapIndexDropRequest copyWith(void Function(MapIndexDropRequest) updates) =>
      super.copyWith((message) => updates(message as MapIndexDropRequest))
          as MapIndexDropRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use MapIndexDropRequest() / MapIndexDropRequest.new instead')
  static MapIndexDropRequest create() => MapIndexDropRequest._();
  static $pb.GeneratedMessage $_createMessage() => MapIndexDropRequest._();
  @$core.override
  MapIndexDropRequest createEmptyInstance() => MapIndexDropRequest._();
  @$core.pragma('dart2js:noInline')
  static MapIndexDropRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MapIndexDropRequest>(
          MapIndexDropRequest.$_createMessage);
  static MapIndexDropRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get index => $_getIZ(0);
  @$pb.TagNumber(1)
  set index($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);
}

/// Nothing: the index is gone.
class MapIndexDropResponse extends $pb.GeneratedMessage {
  factory MapIndexDropResponse() => MapIndexDropResponse._();

  MapIndexDropResponse._();

  factory MapIndexDropResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapIndexDropResponse()..mergeFromBuffer(data, registry);
  factory MapIndexDropResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MapIndexDropResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MapIndexDropResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: MapIndexDropResponse.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapIndexDropResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MapIndexDropResponse copyWith(void Function(MapIndexDropResponse) updates) =>
      super.copyWith((message) => updates(message as MapIndexDropResponse))
          as MapIndexDropResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use MapIndexDropResponse() / MapIndexDropResponse.new instead')
  static MapIndexDropResponse create() => MapIndexDropResponse._();
  static $pb.GeneratedMessage $_createMessage() => MapIndexDropResponse._();
  @$core.override
  MapIndexDropResponse createEmptyInstance() => MapIndexDropResponse._();
  @$core.pragma('dart2js:noInline')
  static MapIndexDropResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MapIndexDropResponse>(
          MapIndexDropResponse.$_createMessage);
  static MapIndexDropResponse? _defaultInstance;
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
