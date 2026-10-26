// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/query.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Parses the text of a search query. Parsing never fails: what is not an operator is text.
class ParseQueryRequest extends $pb.GeneratedMessage {
  factory ParseQueryRequest({
    $core.String? query,
  }) {
    final result = ParseQueryRequest._();
    if (query != null) result.query = query;
    return result;
  }

  ParseQueryRequest._();

  factory ParseQueryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParseQueryRequest()..mergeFromBuffer(data, registry);
  factory ParseQueryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParseQueryRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ParseQueryRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ParseQueryRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'query')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParseQueryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParseQueryRequest copyWith(void Function(ParseQueryRequest) updates) =>
      super.copyWith((message) => updates(message as ParseQueryRequest))
          as ParseQueryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ParseQueryRequest() / ParseQueryRequest.new instead')
  static ParseQueryRequest create() => ParseQueryRequest._();
  static $pb.GeneratedMessage $_createMessage() => ParseQueryRequest._();
  @$core.override
  ParseQueryRequest createEmptyInstance() => ParseQueryRequest._();
  @$core.pragma('dart2js:noInline')
  static ParseQueryRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ParseQueryRequest>(
          ParseQueryRequest.$_createMessage);
  static ParseQueryRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get query => $_getSZ(0);
  @$pb.TagNumber(1)
  set query($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => $_clearField(1);
}

/// The parsed query; the root is absent when the query is empty.
class ParseQueryResponse extends $pb.GeneratedMessage {
  factory ParseQueryResponse({
    QueryNode? root,
  }) {
    final result = ParseQueryResponse._();
    if (root != null) result.root = root;
    return result;
  }

  ParseQueryResponse._();

  factory ParseQueryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParseQueryResponse()..mergeFromBuffer(data, registry);
  factory ParseQueryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParseQueryResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ParseQueryResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: ParseQueryResponse.$_createMessage)
    ..aOM<QueryNode>(1, _omitFieldNames ? '' : 'root',
        subBuilder: QueryNode.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParseQueryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParseQueryResponse copyWith(void Function(ParseQueryResponse) updates) =>
      super.copyWith((message) => updates(message as ParseQueryResponse))
          as ParseQueryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ParseQueryResponse() / ParseQueryResponse.new instead')
  static ParseQueryResponse create() => ParseQueryResponse._();
  static $pb.GeneratedMessage $_createMessage() => ParseQueryResponse._();
  @$core.override
  ParseQueryResponse createEmptyInstance() => ParseQueryResponse._();
  @$core.pragma('dart2js:noInline')
  static ParseQueryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ParseQueryResponse>(
          ParseQueryResponse.$_createMessage);
  static ParseQueryResponse? _defaultInstance;

  @$pb.TagNumber(1)
  QueryNode get root => $_getN(0);
  @$pb.TagNumber(1)
  set root(QueryNode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRoot() => $_has(0);
  @$pb.TagNumber(1)
  void clearRoot() => $_clearField(1);
  @$pb.TagNumber(1)
  QueryNode ensureRoot() => $_ensure(0);
}

enum QueryNode_Node { term, negated, all, any, notSet }

/// A node of a query tree.
class QueryNode extends $pb.GeneratedMessage {
  factory QueryNode({
    QueryTerm? term,
    QueryNode? negated,
    QueryNodeList? all,
    QueryNodeList? any,
  }) {
    final result = QueryNode._();
    if (term != null) result.term = term;
    if (negated != null) result.negated = negated;
    if (all != null) result.all = all;
    if (any != null) result.any = any;
    return result;
  }

  QueryNode._();

  factory QueryNode.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      QueryNode()..mergeFromBuffer(data, registry);
  factory QueryNode.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      QueryNode()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, QueryNode_Node> _QueryNode_NodeByTag = {
    1: QueryNode_Node.term,
    2: QueryNode_Node.negated,
    3: QueryNode_Node.all,
    4: QueryNode_Node.any,
    0: QueryNode_Node.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'QueryNode',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: QueryNode.$_createMessage)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<QueryTerm>(1, _omitFieldNames ? '' : 'term',
        subBuilder: QueryTerm.$_createMessage)
    ..aOM<QueryNode>(2, _omitFieldNames ? '' : 'negated',
        subBuilder: QueryNode.$_createMessage)
    ..aOM<QueryNodeList>(3, _omitFieldNames ? '' : 'all',
        subBuilder: QueryNodeList.$_createMessage)
    ..aOM<QueryNodeList>(4, _omitFieldNames ? '' : 'any',
        subBuilder: QueryNodeList.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryNode clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryNode copyWith(void Function(QueryNode) updates) =>
      super.copyWith((message) => updates(message as QueryNode)) as QueryNode;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use QueryNode() / QueryNode.new instead')
  static QueryNode create() => QueryNode._();
  static $pb.GeneratedMessage $_createMessage() => QueryNode._();
  @$core.override
  QueryNode createEmptyInstance() => QueryNode._();
  @$core.pragma('dart2js:noInline')
  static QueryNode getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<QueryNode>(QueryNode.$_createMessage);
  static QueryNode? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  QueryNode_Node whichNode() => _QueryNode_NodeByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearNode() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  QueryTerm get term => $_getN(0);
  @$pb.TagNumber(1)
  set term(QueryTerm value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTerm() => $_has(0);
  @$pb.TagNumber(1)
  void clearTerm() => $_clearField(1);
  @$pb.TagNumber(1)
  QueryTerm ensureTerm() => $_ensure(0);

  /// Matches what its operand does not match: `-x` or `NOT x`.
  @$pb.TagNumber(2)
  QueryNode get negated => $_getN(1);
  @$pb.TagNumber(2)
  set negated(QueryNode value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasNegated() => $_has(1);
  @$pb.TagNumber(2)
  void clearNegated() => $_clearField(2);
  @$pb.TagNumber(2)
  QueryNode ensureNegated() => $_ensure(1);

  /// Matches what all of its operands match: words side by side.
  @$pb.TagNumber(3)
  QueryNodeList get all => $_getN(2);
  @$pb.TagNumber(3)
  set all(QueryNodeList value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasAll() => $_has(2);
  @$pb.TagNumber(3)
  void clearAll() => $_clearField(3);
  @$pb.TagNumber(3)
  QueryNodeList ensureAll() => $_ensure(2);

  /// Matches what any of its operands matches: `x OR y`.
  @$pb.TagNumber(4)
  QueryNodeList get any => $_getN(3);
  @$pb.TagNumber(4)
  set any(QueryNodeList value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasAny() => $_has(3);
  @$pb.TagNumber(4)
  void clearAny() => $_clearField(4);
  @$pb.TagNumber(4)
  QueryNodeList ensureAny() => $_ensure(3);
}

/// The operands of an all or any node.
class QueryNodeList extends $pb.GeneratedMessage {
  factory QueryNodeList({
    $core.Iterable<QueryNode>? nodes,
  }) {
    final result = QueryNodeList._();
    if (nodes != null) result.nodes.addAll(nodes);
    return result;
  }

  QueryNodeList._();

  factory QueryNodeList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      QueryNodeList()..mergeFromBuffer(data, registry);
  factory QueryNodeList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      QueryNodeList()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'QueryNodeList',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: QueryNodeList.$_createMessage)
    ..pPM<QueryNode>(1, _omitFieldNames ? '' : 'nodes',
        subBuilder: QueryNode.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryNodeList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryNodeList copyWith(void Function(QueryNodeList) updates) =>
      super.copyWith((message) => updates(message as QueryNodeList))
          as QueryNodeList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use QueryNodeList() / QueryNodeList.new instead')
  static QueryNodeList create() => QueryNodeList._();
  static $pb.GeneratedMessage $_createMessage() => QueryNodeList._();
  @$core.override
  QueryNodeList createEmptyInstance() => QueryNodeList._();
  @$core.pragma('dart2js:noInline')
  static QueryNodeList getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<QueryNodeList>(
          QueryNodeList.$_createMessage);
  static QueryNodeList? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<QueryNode> get nodes => $_getList(0);
}

/// A word, a quoted phrase or a key:value operator.
class QueryTerm extends $pb.GeneratedMessage {
  factory QueryTerm({
    $core.String? key,
    $core.String? value,
    $core.bool? phrase,
  }) {
    final result = QueryTerm._();
    if (key != null) result.key = key;
    if (value != null) result.value = value;
    if (phrase != null) result.phrase = phrase;
    return result;
  }

  QueryTerm._();

  factory QueryTerm.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      QueryTerm()..mergeFromBuffer(data, registry);
  factory QueryTerm.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      QueryTerm()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'QueryTerm',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'photolib.kernel.v1'),
      createEmptyInstance: QueryTerm.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..aOB(3, _omitFieldNames ? '' : 'phrase')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryTerm clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryTerm copyWith(void Function(QueryTerm) updates) =>
      super.copyWith((message) => updates(message as QueryTerm)) as QueryTerm;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use QueryTerm() / QueryTerm.new instead')
  static QueryTerm create() => QueryTerm._();
  static $pb.GeneratedMessage $_createMessage() => QueryTerm._();
  @$core.override
  QueryTerm createEmptyInstance() => QueryTerm._();
  @$core.pragma('dart2js:noInline')
  static QueryTerm getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<QueryTerm>(QueryTerm.$_createMessage);
  static QueryTerm? _defaultInstance;

  /// The operator, e.g. "tag" in tag:beach; empty for free text.
  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);

  /// The value was quoted, so it matches as an exact phrase.
  @$pb.TagNumber(3)
  $core.bool get phrase => $_getBF(2);
  @$pb.TagNumber(3)
  set phrase($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPhrase() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhrase() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
