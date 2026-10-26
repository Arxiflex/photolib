// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/search.proto.

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

@$core.Deprecated('Use searchTextRequestDescriptor instead')
const SearchTextRequest$json = {
  '1': 'SearchTextRequest',
  '2': [
    {'1': 'query', '3': 1, '4': 1, '5': 9, '10': 'query'},
    {'1': 'page_size', '3': 2, '4': 1, '5': 13, '10': 'pageSize'},
  ],
};

/// Descriptor for `SearchTextRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchTextRequestDescriptor = $convert.base64Decode(
    'ChFTZWFyY2hUZXh0UmVxdWVzdBIUCgVxdWVyeRgBIAEoCVIFcXVlcnkSGwoJcGFnZV9zaXplGA'
    'IgASgNUghwYWdlU2l6ZQ==');

@$core.Deprecated('Use searchHitDescriptor instead')
const SearchHit$json = {
  '1': 'SearchHit',
  '2': [
    {'1': 'asset_id', '3': 1, '4': 1, '5': 9, '10': 'assetId'},
    {'1': 'library_id', '3': 2, '4': 1, '5': 9, '10': 'libraryId'},
    {'1': 'text', '3': 3, '4': 1, '5': 9, '10': 'text'},
  ],
};

/// Descriptor for `SearchHit`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchHitDescriptor = $convert.base64Decode(
    'CglTZWFyY2hIaXQSGQoIYXNzZXRfaWQYASABKAlSB2Fzc2V0SWQSHQoKbGlicmFyeV9pZBgCIA'
    'EoCVIJbGlicmFyeUlkEhIKBHRleHQYAyABKAlSBHRleHQ=');

@$core.Deprecated('Use searchTextResponseDescriptor instead')
const SearchTextResponse$json = {
  '1': 'SearchTextResponse',
  '2': [
    {
      '1': 'hits',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.SearchHit',
      '10': 'hits'
    },
  ],
};

/// Descriptor for `SearchTextResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchTextResponseDescriptor = $convert.base64Decode(
    'ChJTZWFyY2hUZXh0UmVzcG9uc2USLgoEaGl0cxgBIAMoCzIaLnBob3RvbGliLmFwaS52MS5TZW'
    'FyY2hIaXRSBGhpdHM=');

@$core.Deprecated('Use getTextRequestDescriptor instead')
const GetTextRequest$json = {
  '1': 'GetTextRequest',
  '2': [
    {'1': 'asset_id', '3': 1, '4': 1, '5': 9, '10': 'assetId'},
  ],
};

/// Descriptor for `GetTextRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTextRequestDescriptor = $convert.base64Decode(
    'Cg5HZXRUZXh0UmVxdWVzdBIZCghhc3NldF9pZBgBIAEoCVIHYXNzZXRJZA==');

@$core.Deprecated('Use getTextResponseDescriptor instead')
const GetTextResponse$json = {
  '1': 'GetTextResponse',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'read', '3': 2, '4': 1, '5': 8, '10': 'read'},
    {
      '1': 'regions',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.api.v1.TextRegion',
      '10': 'regions'
    },
  ],
};

/// Descriptor for `GetTextResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTextResponseDescriptor = $convert.base64Decode(
    'Cg9HZXRUZXh0UmVzcG9uc2USEgoEdGV4dBgBIAEoCVIEdGV4dBISCgRyZWFkGAIgASgIUgRyZW'
    'FkEjUKB3JlZ2lvbnMYAyADKAsyGy5waG90b2xpYi5hcGkudjEuVGV4dFJlZ2lvblIHcmVnaW9u'
    'cw==');

@$core.Deprecated('Use textRegionDescriptor instead')
const TextRegion$json = {
  '1': 'TextRegion',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'x', '3': 2, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 3, '4': 1, '5': 2, '10': 'y'},
    {'1': 'width', '3': 4, '4': 1, '5': 2, '10': 'width'},
    {'1': 'height', '3': 5, '4': 1, '5': 2, '10': 'height'},
  ],
};

/// Descriptor for `TextRegion`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List textRegionDescriptor = $convert.base64Decode(
    'CgpUZXh0UmVnaW9uEhIKBHRleHQYASABKAlSBHRleHQSDAoBeBgCIAEoAlIBeBIMCgF5GAMgAS'
    'gCUgF5EhQKBXdpZHRoGAQgASgCUgV3aWR0aBIWCgZoZWlnaHQYBSABKAJSBmhlaWdodA==');

const $core.Map<$core.String, $core.dynamic> SearchServiceBase$json = {
  '1': 'SearchService',
  '2': [
    {
      '1': 'SearchText',
      '2': '.photolib.api.v1.SearchTextRequest',
      '3': '.photolib.api.v1.SearchTextResponse'
    },
    {
      '1': 'GetText',
      '2': '.photolib.api.v1.GetTextRequest',
      '3': '.photolib.api.v1.GetTextResponse'
    },
  ],
};

@$core.Deprecated('Use searchServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>>
    SearchServiceBase$messageJson = {
  '.photolib.api.v1.SearchTextRequest': SearchTextRequest$json,
  '.photolib.api.v1.SearchTextResponse': SearchTextResponse$json,
  '.photolib.api.v1.SearchHit': SearchHit$json,
  '.photolib.api.v1.GetTextRequest': GetTextRequest$json,
  '.photolib.api.v1.GetTextResponse': GetTextResponse$json,
  '.photolib.api.v1.TextRegion': TextRegion$json,
};

/// Descriptor for `SearchService`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List searchServiceDescriptor = $convert.base64Decode(
    'Cg1TZWFyY2hTZXJ2aWNlElUKClNlYXJjaFRleHQSIi5waG90b2xpYi5hcGkudjEuU2VhcmNoVG'
    'V4dFJlcXVlc3QaIy5waG90b2xpYi5hcGkudjEuU2VhcmNoVGV4dFJlc3BvbnNlEkwKB0dldFRl'
    'eHQSHy5waG90b2xpYi5hcGkudjEuR2V0VGV4dFJlcXVlc3QaIC5waG90b2xpYi5hcGkudjEuR2'
    'V0VGV4dFJlc3BvbnNl');
