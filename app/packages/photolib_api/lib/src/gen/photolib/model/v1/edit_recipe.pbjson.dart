// This is a generated file - do not edit.
//
// Generated from photolib/model/v1/edit_recipe.proto.

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

@$core.Deprecated('Use storedOutputKindDescriptor instead')
const StoredOutputKind$json = {
  '1': 'StoredOutputKind',
  '2': [
    {'1': 'STORED_OUTPUT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'STORED_OUTPUT_KIND_MASK', '2': 1},
    {'1': 'STORED_OUTPUT_KIND_PATCH', '2': 2},
  ],
};

/// Descriptor for `StoredOutputKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List storedOutputKindDescriptor = $convert.base64Decode(
    'ChBTdG9yZWRPdXRwdXRLaW5kEiIKHlNUT1JFRF9PVVRQVVRfS0lORF9VTlNQRUNJRklFRBAAEh'
    'sKF1NUT1JFRF9PVVRQVVRfS0lORF9NQVNLEAESHAoYU1RPUkVEX09VVFBVVF9LSU5EX1BBVENI'
    'EAI=');

@$core.Deprecated('Use digitalSourceTypeDescriptor instead')
const DigitalSourceType$json = {
  '1': 'DigitalSourceType',
  '2': [
    {'1': 'DIGITAL_SOURCE_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'DIGITAL_SOURCE_TYPE_HUMAN_EDITS', '2': 1},
    {'1': 'DIGITAL_SOURCE_TYPE_ALGORITHMICALLY_ENHANCED', '2': 2},
    {
      '1': 'DIGITAL_SOURCE_TYPE_COMPOSITE_WITH_TRAINED_ALGORITHMIC_MEDIA',
      '2': 3
    },
  ],
};

/// Descriptor for `DigitalSourceType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List digitalSourceTypeDescriptor = $convert.base64Decode(
    'ChFEaWdpdGFsU291cmNlVHlwZRIjCh9ESUdJVEFMX1NPVVJDRV9UWVBFX1VOU1BFQ0lGSUVEEA'
    'ASIwofRElHSVRBTF9TT1VSQ0VfVFlQRV9IVU1BTl9FRElUUxABEjAKLERJR0lUQUxfU09VUkNF'
    'X1RZUEVfQUxHT1JJVEhNSUNBTExZX0VOSEFOQ0VEEAISQAo8RElHSVRBTF9TT1VSQ0VfVFlQRV'
    '9DT01QT1NJVEVfV0lUSF9UUkFJTkVEX0FMR09SSVRITUlDX01FRElBEAM=');

@$core.Deprecated('Use editRecipeDescriptor instead')
const EditRecipe$json = {
  '1': 'EditRecipe',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {
      '1': 'operations',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.photolib.model.v1.Operation',
      '10': 'operations'
    },
    {
      '1': 'provenance',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.Provenance',
      '10': 'provenance'
    },
    {
      '1': 'outputs',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.photolib.model.v1.StoredOutput',
      '10': 'outputs'
    },
  ],
};

/// Descriptor for `EditRecipe`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List editRecipeDescriptor = $convert.base64Decode(
    'CgpFZGl0UmVjaXBlEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2hlbWFWZXJzaW9uEjwKCm'
    '9wZXJhdGlvbnMYAiADKAsyHC5waG90b2xpYi5tb2RlbC52MS5PcGVyYXRpb25SCm9wZXJhdGlv'
    'bnMSPQoKcHJvdmVuYW5jZRgDIAEoCzIdLnBob3RvbGliLm1vZGVsLnYxLlByb3ZlbmFuY2VSCn'
    'Byb3ZlbmFuY2USOQoHb3V0cHV0cxgEIAMoCzIfLnBob3RvbGliLm1vZGVsLnYxLlN0b3JlZE91'
    'dHB1dFIHb3V0cHV0cw==');

@$core.Deprecated('Use operationDescriptor instead')
const Operation$json = {
  '1': 'Operation',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
    {'1': 'disabled', '3': 2, '4': 1, '5': 8, '10': 'disabled'},
    {
      '1': 'turn',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.TurnOperation',
      '9': 0,
      '10': 'turn'
    },
    {
      '1': 'flip',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.FlipOperation',
      '9': 0,
      '10': 'flip'
    },
    {
      '1': 'crop',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.CropOperation',
      '9': 0,
      '10': 'crop'
    },
    {
      '1': 'adjust',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.AdjustOperation',
      '9': 0,
      '10': 'adjust'
    },
    {
      '1': 'lut',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.LutOperation',
      '9': 0,
      '10': 'lut'
    },
    {
      '1': 'local_adjust',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.LocalAdjustOperation',
      '9': 0,
      '10': 'localAdjust'
    },
    {
      '1': 'inpaint',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.InpaintOperation',
      '9': 0,
      '10': 'inpaint'
    },
  ],
  '8': [
    {'1': 'kind'},
  ],
};

/// Descriptor for `Operation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List operationDescriptor = $convert.base64Decode(
    'CglPcGVyYXRpb24SIQoMb3BlcmF0aW9uX2lkGAEgASgJUgtvcGVyYXRpb25JZBIaCghkaXNhYm'
    'xlZBgCIAEoCFIIZGlzYWJsZWQSNgoEdHVybhgKIAEoCzIgLnBob3RvbGliLm1vZGVsLnYxLlR1'
    'cm5PcGVyYXRpb25IAFIEdHVybhI2CgRmbGlwGAsgASgLMiAucGhvdG9saWIubW9kZWwudjEuRm'
    'xpcE9wZXJhdGlvbkgAUgRmbGlwEjYKBGNyb3AYDCABKAsyIC5waG90b2xpYi5tb2RlbC52MS5D'
    'cm9wT3BlcmF0aW9uSABSBGNyb3ASPAoGYWRqdXN0GA0gASgLMiIucGhvdG9saWIubW9kZWwudj'
    'EuQWRqdXN0T3BlcmF0aW9uSABSBmFkanVzdBIzCgNsdXQYDiABKAsyHy5waG90b2xpYi5tb2Rl'
    'bC52MS5MdXRPcGVyYXRpb25IAFIDbHV0EkwKDGxvY2FsX2FkanVzdBgPIAEoCzInLnBob3RvbG'
    'liLm1vZGVsLnYxLkxvY2FsQWRqdXN0T3BlcmF0aW9uSABSC2xvY2FsQWRqdXN0Ej8KB2lucGFp'
    'bnQYECABKAsyIy5waG90b2xpYi5tb2RlbC52MS5JbnBhaW50T3BlcmF0aW9uSABSB2lucGFpbn'
    'RCBgoEa2luZA==');

@$core.Deprecated('Use turnOperationDescriptor instead')
const TurnOperation$json = {
  '1': 'TurnOperation',
  '2': [
    {'1': 'quarter_turns', '3': 1, '4': 1, '5': 13, '10': 'quarterTurns'},
  ],
};

/// Descriptor for `TurnOperation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List turnOperationDescriptor = $convert.base64Decode(
    'Cg1UdXJuT3BlcmF0aW9uEiMKDXF1YXJ0ZXJfdHVybnMYASABKA1SDHF1YXJ0ZXJUdXJucw==');

@$core.Deprecated('Use flipOperationDescriptor instead')
const FlipOperation$json = {
  '1': 'FlipOperation',
  '2': [
    {'1': 'vertical', '3': 1, '4': 1, '5': 8, '10': 'vertical'},
  ],
};

/// Descriptor for `FlipOperation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List flipOperationDescriptor = $convert.base64Decode(
    'Cg1GbGlwT3BlcmF0aW9uEhoKCHZlcnRpY2FsGAEgASgIUgh2ZXJ0aWNhbA==');

@$core.Deprecated('Use cropOperationDescriptor instead')
const CropOperation$json = {
  '1': 'CropOperation',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 2, '10': 'y'},
    {'1': 'width', '3': 3, '4': 1, '5': 2, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 2, '10': 'height'},
  ],
};

/// Descriptor for `CropOperation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cropOperationDescriptor = $convert.base64Decode(
    'Cg1Dcm9wT3BlcmF0aW9uEgwKAXgYASABKAJSAXgSDAoBeRgCIAEoAlIBeRIUCgV3aWR0aBgDIA'
    'EoAlIFd2lkdGgSFgoGaGVpZ2h0GAQgASgCUgZoZWlnaHQ=');

@$core.Deprecated('Use adjustOperationDescriptor instead')
const AdjustOperation$json = {
  '1': 'AdjustOperation',
  '2': [
    {'1': 'temperature', '3': 1, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'tint', '3': 2, '4': 1, '5': 2, '10': 'tint'},
    {'1': 'exposure', '3': 3, '4': 1, '5': 2, '10': 'exposure'},
    {'1': 'contrast', '3': 4, '4': 1, '5': 2, '10': 'contrast'},
    {'1': 'clarity', '3': 5, '4': 1, '5': 2, '10': 'clarity'},
    {'1': 'saturation', '3': 6, '4': 1, '5': 2, '10': 'saturation'},
  ],
};

/// Descriptor for `AdjustOperation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List adjustOperationDescriptor = $convert.base64Decode(
    'Cg9BZGp1c3RPcGVyYXRpb24SIAoLdGVtcGVyYXR1cmUYASABKAJSC3RlbXBlcmF0dXJlEhIKBH'
    'RpbnQYAiABKAJSBHRpbnQSGgoIZXhwb3N1cmUYAyABKAJSCGV4cG9zdXJlEhoKCGNvbnRyYXN0'
    'GAQgASgCUghjb250cmFzdBIYCgdjbGFyaXR5GAUgASgCUgdjbGFyaXR5Eh4KCnNhdHVyYXRpb2'
    '4YBiABKAJSCnNhdHVyYXRpb24=');

@$core.Deprecated('Use lutOperationDescriptor instead')
const LutOperation$json = {
  '1': 'LutOperation',
  '2': [
    {'1': 'size', '3': 1, '4': 1, '5': 13, '10': 'size'},
    {'1': 'rgb16', '3': 2, '4': 1, '5': 12, '10': 'rgb16'},
  ],
};

/// Descriptor for `LutOperation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lutOperationDescriptor = $convert.base64Decode(
    'CgxMdXRPcGVyYXRpb24SEgoEc2l6ZRgBIAEoDVIEc2l6ZRIUCgVyZ2IxNhgCIAEoDFIFcmdiMT'
    'Y=');

@$core.Deprecated('Use localAdjustOperationDescriptor instead')
const LocalAdjustOperation$json = {
  '1': 'LocalAdjustOperation',
  '2': [
    {'1': 'output_id', '3': 1, '4': 1, '5': 9, '10': 'outputId'},
    {
      '1': 'adjust',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.AdjustOperation',
      '10': 'adjust'
    },
  ],
};

/// Descriptor for `LocalAdjustOperation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List localAdjustOperationDescriptor = $convert.base64Decode(
    'ChRMb2NhbEFkanVzdE9wZXJhdGlvbhIbCglvdXRwdXRfaWQYASABKAlSCG91dHB1dElkEjoKBm'
    'FkanVzdBgCIAEoCzIiLnBob3RvbGliLm1vZGVsLnYxLkFkanVzdE9wZXJhdGlvblIGYWRqdXN0');

@$core.Deprecated('Use inpaintOperationDescriptor instead')
const InpaintOperation$json = {
  '1': 'InpaintOperation',
  '2': [
    {'1': 'output_id', '3': 1, '4': 1, '5': 9, '10': 'outputId'},
    {'1': 'x', '3': 2, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 3, '4': 1, '5': 2, '10': 'y'},
    {'1': 'width', '3': 4, '4': 1, '5': 2, '10': 'width'},
    {'1': 'height', '3': 5, '4': 1, '5': 2, '10': 'height'},
  ],
};

/// Descriptor for `InpaintOperation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List inpaintOperationDescriptor = $convert.base64Decode(
    'ChBJbnBhaW50T3BlcmF0aW9uEhsKCW91dHB1dF9pZBgBIAEoCVIIb3V0cHV0SWQSDAoBeBgCIA'
    'EoAlIBeBIMCgF5GAMgASgCUgF5EhQKBXdpZHRoGAQgASgCUgV3aWR0aBIWCgZoZWlnaHQYBSAB'
    'KAJSBmhlaWdodA==');

@$core.Deprecated('Use storedOutputDescriptor instead')
const StoredOutput$json = {
  '1': 'StoredOutput',
  '2': [
    {'1': 'output_id', '3': 1, '4': 1, '5': 9, '10': 'outputId'},
    {
      '1': 'kind',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.photolib.model.v1.StoredOutputKind',
      '10': 'kind'
    },
    {'1': 'width', '3': 3, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 13, '10': 'height'},
    {'1': 'data', '3': 5, '4': 1, '5': 12, '10': 'data'},
    {
      '1': 'model',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.ModelUse',
      '10': 'model'
    },
  ],
};

/// Descriptor for `StoredOutput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storedOutputDescriptor = $convert.base64Decode(
    'CgxTdG9yZWRPdXRwdXQSGwoJb3V0cHV0X2lkGAEgASgJUghvdXRwdXRJZBI3CgRraW5kGAIgAS'
    'gOMiMucGhvdG9saWIubW9kZWwudjEuU3RvcmVkT3V0cHV0S2luZFIEa2luZBIUCgV3aWR0aBgD'
    'IAEoDVIFd2lkdGgSFgoGaGVpZ2h0GAQgASgNUgZoZWlnaHQSEgoEZGF0YRgFIAEoDFIEZGF0YR'
    'IxCgVtb2RlbBgGIAEoCzIbLnBob3RvbGliLm1vZGVsLnYxLk1vZGVsVXNlUgVtb2RlbA==');

@$core.Deprecated('Use modelUseDescriptor instead')
const ModelUse$json = {
  '1': 'ModelUse',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'model_version', '3': 2, '4': 1, '5': 9, '10': 'modelVersion'},
    {
      '1': 'parameters',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.photolib.model.v1.Parameter',
      '10': 'parameters'
    },
  ],
};

/// Descriptor for `ModelUse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelUseDescriptor = $convert.base64Decode(
    'CghNb2RlbFVzZRIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBIjCg1tb2RlbF92ZXJzaW9uGA'
    'IgASgJUgxtb2RlbFZlcnNpb24SPAoKcGFyYW1ldGVycxgDIAMoCzIcLnBob3RvbGliLm1vZGVs'
    'LnYxLlBhcmFtZXRlclIKcGFyYW1ldGVycw==');

@$core.Deprecated('Use parameterDescriptor instead')
const Parameter$json = {
  '1': 'Parameter',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
};

/// Descriptor for `Parameter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List parameterDescriptor = $convert.base64Decode(
    'CglQYXJhbWV0ZXISEgoEbmFtZRgBIAEoCVIEbmFtZRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU=');

@$core.Deprecated('Use provenanceDescriptor instead')
const Provenance$json = {
  '1': 'Provenance',
  '2': [
    {'1': 'tool', '3': 1, '4': 1, '5': 9, '10': 'tool'},
    {
      '1': 'models',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.photolib.model.v1.ModelUse',
      '10': 'models'
    },
    {
      '1': 'digital_source_type',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.photolib.model.v1.DigitalSourceType',
      '10': 'digitalSourceType'
    },
  ],
};

/// Descriptor for `Provenance`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List provenanceDescriptor = $convert.base64Decode(
    'CgpQcm92ZW5hbmNlEhIKBHRvb2wYASABKAlSBHRvb2wSMwoGbW9kZWxzGAIgAygLMhsucGhvdG'
    '9saWIubW9kZWwudjEuTW9kZWxVc2VSBm1vZGVscxJUChNkaWdpdGFsX3NvdXJjZV90eXBlGAMg'
    'ASgOMiQucGhvdG9saWIubW9kZWwudjEuRGlnaXRhbFNvdXJjZVR5cGVSEWRpZ2l0YWxTb3VyY2'
    'VUeXBl');
