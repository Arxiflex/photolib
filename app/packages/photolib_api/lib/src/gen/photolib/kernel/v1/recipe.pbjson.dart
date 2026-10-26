// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/recipe.proto.

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

@$core.Deprecated('Use recipeChangeKindDescriptor instead')
const RecipeChangeKind$json = {
  '1': 'RecipeChangeKind',
  '2': [
    {'1': 'RECIPE_CHANGE_KIND_UNSPECIFIED', '2': 0},
    {'1': 'RECIPE_CHANGE_KIND_ADDED', '2': 1},
    {'1': 'RECIPE_CHANGE_KIND_REMOVED', '2': 2},
    {'1': 'RECIPE_CHANGE_KIND_CHANGED', '2': 3},
    {'1': 'RECIPE_CHANGE_KIND_MOVED', '2': 4},
  ],
};

/// Descriptor for `RecipeChangeKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List recipeChangeKindDescriptor = $convert.base64Decode(
    'ChBSZWNpcGVDaGFuZ2VLaW5kEiIKHlJFQ0lQRV9DSEFOR0VfS0lORF9VTlNQRUNJRklFRBAAEh'
    'wKGFJFQ0lQRV9DSEFOR0VfS0lORF9BRERFRBABEh4KGlJFQ0lQRV9DSEFOR0VfS0lORF9SRU1P'
    'VkVEEAISHgoaUkVDSVBFX0NIQU5HRV9LSU5EX0NIQU5HRUQQAxIcChhSRUNJUEVfQ0hBTkdFX0'
    'tJTkRfTU9WRUQQBA==');

@$core.Deprecated('Use resolveRecipeRequestDescriptor instead')
const ResolveRecipeRequest$json = {
  '1': 'ResolveRecipeRequest',
  '2': [
    {
      '1': 'recipe',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'recipe'
    },
    {'1': 'width', '3': 2, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 3, '4': 1, '5': 13, '10': 'height'},
  ],
};

/// Descriptor for `ResolveRecipeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resolveRecipeRequestDescriptor = $convert.base64Decode(
    'ChRSZXNvbHZlUmVjaXBlUmVxdWVzdBI1CgZyZWNpcGUYASABKAsyHS5waG90b2xpYi5tb2RlbC'
    '52MS5FZGl0UmVjaXBlUgZyZWNpcGUSFAoFd2lkdGgYAiABKA1SBXdpZHRoEhYKBmhlaWdodBgD'
    'IAEoDVIGaGVpZ2h0');

@$core.Deprecated('Use resolveRecipeResponseDescriptor instead')
const ResolveRecipeResponse$json = {
  '1': 'ResolveRecipeResponse',
  '2': [
    {
      '1': 'recipe',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'recipe'
    },
    {'1': 'sha256', '3': 2, '4': 1, '5': 12, '10': 'sha256'},
    {'1': 'width', '3': 3, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 13, '10': 'height'},
    {
      '1': 'develop',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Develop',
      '10': 'develop'
    },
    {'1': 'geometry_only', '3': 6, '4': 1, '5': 8, '10': 'geometryOnly'},
    {'1': 'identity', '3': 7, '4': 1, '5': 8, '10': 'identity'},
  ],
};

/// Descriptor for `ResolveRecipeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resolveRecipeResponseDescriptor = $convert.base64Decode(
    'ChVSZXNvbHZlUmVjaXBlUmVzcG9uc2USNQoGcmVjaXBlGAEgASgLMh0ucGhvdG9saWIubW9kZW'
    'wudjEuRWRpdFJlY2lwZVIGcmVjaXBlEhYKBnNoYTI1NhgCIAEoDFIGc2hhMjU2EhQKBXdpZHRo'
    'GAMgASgNUgV3aWR0aBIWCgZoZWlnaHQYBCABKA1SBmhlaWdodBI1CgdkZXZlbG9wGAUgASgLMh'
    'sucGhvdG9saWIua2VybmVsLnYxLkRldmVsb3BSB2RldmVsb3ASIwoNZ2VvbWV0cnlfb25seRgG'
    'IAEoCFIMZ2VvbWV0cnlPbmx5EhoKCGlkZW50aXR5GAcgASgIUghpZGVudGl0eQ==');

@$core.Deprecated('Use compareRecipesRequestDescriptor instead')
const CompareRecipesRequest$json = {
  '1': 'CompareRecipesRequest',
  '2': [
    {
      '1': 'before',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'before'
    },
    {
      '1': 'after',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'after'
    },
  ],
};

/// Descriptor for `CompareRecipesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List compareRecipesRequestDescriptor = $convert.base64Decode(
    'ChVDb21wYXJlUmVjaXBlc1JlcXVlc3QSNQoGYmVmb3JlGAEgASgLMh0ucGhvdG9saWIubW9kZW'
    'wudjEuRWRpdFJlY2lwZVIGYmVmb3JlEjMKBWFmdGVyGAIgASgLMh0ucGhvdG9saWIubW9kZWwu'
    'djEuRWRpdFJlY2lwZVIFYWZ0ZXI=');

@$core.Deprecated('Use recipeChangeDescriptor instead')
const RecipeChange$json = {
  '1': 'RecipeChange',
  '2': [
    {'1': 'subject', '3': 1, '4': 1, '5': 9, '10': 'subject'},
    {
      '1': 'kind',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.RecipeChangeKind',
      '10': 'kind'
    },
    {'1': 'what', '3': 3, '4': 1, '5': 9, '10': 'what'},
    {'1': 'fields', '3': 4, '4': 3, '5': 9, '10': 'fields'},
  ],
};

/// Descriptor for `RecipeChange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recipeChangeDescriptor = $convert.base64Decode(
    'CgxSZWNpcGVDaGFuZ2USGAoHc3ViamVjdBgBIAEoCVIHc3ViamVjdBI4CgRraW5kGAIgASgOMi'
    'QucGhvdG9saWIua2VybmVsLnYxLlJlY2lwZUNoYW5nZUtpbmRSBGtpbmQSEgoEd2hhdBgDIAEo'
    'CVIEd2hhdBIWCgZmaWVsZHMYBCADKAlSBmZpZWxkcw==');

@$core.Deprecated('Use compareRecipesResponseDescriptor instead')
const CompareRecipesResponse$json = {
  '1': 'CompareRecipesResponse',
  '2': [
    {
      '1': 'changes',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.RecipeChange',
      '10': 'changes'
    },
  ],
};

/// Descriptor for `CompareRecipesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List compareRecipesResponseDescriptor =
    $convert.base64Decode(
        'ChZDb21wYXJlUmVjaXBlc1Jlc3BvbnNlEjoKB2NoYW5nZXMYASADKAsyIC5waG90b2xpYi5rZX'
        'JuZWwudjEuUmVjaXBlQ2hhbmdlUgdjaGFuZ2Vz');

@$core.Deprecated('Use regionDescriptor instead')
const Region$json = {
  '1': 'Region',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 2, '10': 'y'},
    {'1': 'width', '3': 3, '4': 1, '5': 2, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 2, '10': 'height'},
  ],
};

/// Descriptor for `Region`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List regionDescriptor = $convert.base64Decode(
    'CgZSZWdpb24SDAoBeBgBIAEoAlIBeBIMCgF5GAIgASgCUgF5EhQKBXdpZHRoGAMgASgCUgV3aW'
    'R0aBIWCgZoZWlnaHQYBCABKAJSBmhlaWdodA==');

@$core.Deprecated('Use mapRegionsRequestDescriptor instead')
const MapRegionsRequest$json = {
  '1': 'MapRegionsRequest',
  '2': [
    {
      '1': 'from',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'from'
    },
    {
      '1': 'to',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'to'
    },
    {
      '1': 'regions',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.Region',
      '10': 'regions'
    },
  ],
};

/// Descriptor for `MapRegionsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapRegionsRequestDescriptor = $convert.base64Decode(
    'ChFNYXBSZWdpb25zUmVxdWVzdBIxCgRmcm9tGAEgASgLMh0ucGhvdG9saWIubW9kZWwudjEuRW'
    'RpdFJlY2lwZVIEZnJvbRItCgJ0bxgCIAEoCzIdLnBob3RvbGliLm1vZGVsLnYxLkVkaXRSZWNp'
    'cGVSAnRvEjQKB3JlZ2lvbnMYAyADKAsyGi5waG90b2xpYi5rZXJuZWwudjEuUmVnaW9uUgdyZW'
    'dpb25z');

@$core.Deprecated('Use mappedRegionDescriptor instead')
const MappedRegion$json = {
  '1': 'MappedRegion',
  '2': [
    {
      '1': 'region',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Region',
      '10': 'region'
    },
    {'1': 'visible', '3': 2, '4': 1, '5': 2, '10': 'visible'},
  ],
};

/// Descriptor for `MappedRegion`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mappedRegionDescriptor = $convert.base64Decode(
    'CgxNYXBwZWRSZWdpb24SMgoGcmVnaW9uGAEgASgLMhoucGhvdG9saWIua2VybmVsLnYxLlJlZ2'
    'lvblIGcmVnaW9uEhgKB3Zpc2libGUYAiABKAJSB3Zpc2libGU=');

@$core.Deprecated('Use mapRegionsResponseDescriptor instead')
const MapRegionsResponse$json = {
  '1': 'MapRegionsResponse',
  '2': [
    {
      '1': 'regions',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.MappedRegion',
      '10': 'regions'
    },
  ],
};

/// Descriptor for `MapRegionsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mapRegionsResponseDescriptor = $convert.base64Decode(
    'ChJNYXBSZWdpb25zUmVzcG9uc2USOgoHcmVnaW9ucxgBIAMoCzIgLnBob3RvbGliLmtlcm5lbC'
    '52MS5NYXBwZWRSZWdpb25SB3JlZ2lvbnM=');

@$core.Deprecated('Use renderRecipeRequestDescriptor instead')
const RenderRecipeRequest$json = {
  '1': 'RenderRecipeRequest',
  '2': [
    {
      '1': 'recipe',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'recipe'
    },
    {
      '1': 'image',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Image',
      '10': 'image'
    },
  ],
};

/// Descriptor for `RenderRecipeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List renderRecipeRequestDescriptor = $convert.base64Decode(
    'ChNSZW5kZXJSZWNpcGVSZXF1ZXN0EjUKBnJlY2lwZRgBIAEoCzIdLnBob3RvbGliLm1vZGVsLn'
    'YxLkVkaXRSZWNpcGVSBnJlY2lwZRIvCgVpbWFnZRgCIAEoCzIZLnBob3RvbGliLmtlcm5lbC52'
    'MS5JbWFnZVIFaW1hZ2U=');

@$core.Deprecated('Use renderRecipeResponseDescriptor instead')
const RenderRecipeResponse$json = {
  '1': 'RenderRecipeResponse',
  '2': [
    {
      '1': 'image',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Image',
      '10': 'image'
    },
  ],
};

/// Descriptor for `RenderRecipeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List renderRecipeResponseDescriptor = $convert.base64Decode(
    'ChRSZW5kZXJSZWNpcGVSZXNwb25zZRIvCgVpbWFnZRgBIAEoCzIZLnBob3RvbGliLmtlcm5lbC'
    '52MS5JbWFnZVIFaW1hZ2U=');

@$core.Deprecated('Use recipeFromDevelopRequestDescriptor instead')
const RecipeFromDevelopRequest$json = {
  '1': 'RecipeFromDevelopRequest',
  '2': [
    {
      '1': 'develop',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.Develop',
      '10': 'develop'
    },
    {'1': 'width', '3': 2, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 3, '4': 1, '5': 13, '10': 'height'},
    {'1': 'tool', '3': 4, '4': 1, '5': 9, '10': 'tool'},
  ],
};

/// Descriptor for `RecipeFromDevelopRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recipeFromDevelopRequestDescriptor = $convert.base64Decode(
    'ChhSZWNpcGVGcm9tRGV2ZWxvcFJlcXVlc3QSNQoHZGV2ZWxvcBgBIAEoCzIbLnBob3RvbGliLm'
    'tlcm5lbC52MS5EZXZlbG9wUgdkZXZlbG9wEhQKBXdpZHRoGAIgASgNUgV3aWR0aBIWCgZoZWln'
    'aHQYAyABKA1SBmhlaWdodBISCgR0b29sGAQgASgJUgR0b29s');

@$core.Deprecated('Use recipeFromDevelopResponseDescriptor instead')
const RecipeFromDevelopResponse$json = {
  '1': 'RecipeFromDevelopResponse',
  '2': [
    {
      '1': 'recipe',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.EditRecipe',
      '10': 'recipe'
    },
  ],
};

/// Descriptor for `RecipeFromDevelopResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recipeFromDevelopResponseDescriptor =
    $convert.base64Decode(
        'ChlSZWNpcGVGcm9tRGV2ZWxvcFJlc3BvbnNlEjUKBnJlY2lwZRgBIAEoCzIdLnBob3RvbGliLm'
        '1vZGVsLnYxLkVkaXRSZWNpcGVSBnJlY2lwZQ==');
