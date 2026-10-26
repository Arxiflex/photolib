// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/capture_time.proto.

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

@$core.Deprecated('Use zoneSourceDescriptor instead')
const ZoneSource$json = {
  '1': 'ZoneSource',
  '2': [
    {'1': 'ZONE_SOURCE_UNSPECIFIED', '2': 0},
    {'1': 'ZONE_SOURCE_EXPLICIT_OFFSET', '2': 1},
    {'1': 'ZONE_SOURCE_GPS_DELTA', '2': 2},
    {'1': 'ZONE_SOURCE_PAIRED_UTC_DELTA', '2': 3},
    {'1': 'ZONE_SOURCE_GPS_ZONE', '2': 4},
    {'1': 'ZONE_SOURCE_DEVICE_ZONE', '2': 5},
    {'1': 'ZONE_SOURCE_DEFAULT_ZONE', '2': 6},
  ],
};

/// Descriptor for `ZoneSource`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List zoneSourceDescriptor = $convert.base64Decode(
    'Cgpab25lU291cmNlEhsKF1pPTkVfU09VUkNFX1VOU1BFQ0lGSUVEEAASHwobWk9ORV9TT1VSQ0'
    'VfRVhQTElDSVRfT0ZGU0VUEAESGQoVWk9ORV9TT1VSQ0VfR1BTX0RFTFRBEAISIAocWk9ORV9T'
    'T1VSQ0VfUEFJUkVEX1VUQ19ERUxUQRADEhgKFFpPTkVfU09VUkNFX0dQU19aT05FEAQSGwoXWk'
    '9ORV9TT1VSQ0VfREVWSUNFX1pPTkUQBRIcChhaT05FX1NPVVJDRV9ERUZBVUxUX1pPTkUQBg==');

@$core.Deprecated('Use captureTimeFlagDescriptor instead')
const CaptureTimeFlag$json = {
  '1': 'CaptureTimeFlag',
  '2': [
    {'1': 'CAPTURE_TIME_FLAG_UNSPECIFIED', '2': 0},
    {'1': 'CAPTURE_TIME_FLAG_NEEDS_REVIEW', '2': 1},
    {'1': 'CAPTURE_TIME_FLAG_CAPTURE_AFTER_RECEIVE', '2': 2},
    {'1': 'CAPTURE_TIME_FLAG_DST_AMBIGUOUS', '2': 3},
    {'1': 'CAPTURE_TIME_FLAG_ASSUMED_ZONE', '2': 4},
    {'1': 'CAPTURE_TIME_FLAG_ZONE_MISMATCH', '2': 5},
  ],
};

/// Descriptor for `CaptureTimeFlag`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List captureTimeFlagDescriptor = $convert.base64Decode(
    'Cg9DYXB0dXJlVGltZUZsYWcSIQodQ0FQVFVSRV9USU1FX0ZMQUdfVU5TUEVDSUZJRUQQABIiCh'
    '5DQVBUVVJFX1RJTUVfRkxBR19ORUVEU19SRVZJRVcQARIrCidDQVBUVVJFX1RJTUVfRkxBR19D'
    'QVBUVVJFX0FGVEVSX1JFQ0VJVkUQAhIjCh9DQVBUVVJFX1RJTUVfRkxBR19EU1RfQU1CSUdVT1'
    'VTEAMSIgoeQ0FQVFVSRV9USU1FX0ZMQUdfQVNTVU1FRF9aT05FEAQSIwofQ0FQVFVSRV9USU1F'
    'X0ZMQUdfWk9ORV9NSVNNQVRDSBAF');

@$core.Deprecated('Use captureTimeRuleDescriptor instead')
const CaptureTimeRule$json = {
  '1': 'CaptureTimeRule',
  '2': [
    {'1': 'CAPTURE_TIME_RULE_UNSPECIFIED', '2': 0},
    {'1': 'CAPTURE_TIME_RULE_NO_EVIDENCE', '2': 1},
    {'1': 'CAPTURE_TIME_RULE_AGREEMENT', '2': 2},
    {'1': 'CAPTURE_TIME_RULE_MOST_CONFIDENT', '2': 3},
  ],
};

/// Descriptor for `CaptureTimeRule`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List captureTimeRuleDescriptor = $convert.base64Decode(
    'Cg9DYXB0dXJlVGltZVJ1bGUSIQodQ0FQVFVSRV9USU1FX1JVTEVfVU5TUEVDSUZJRUQQABIhCh'
    '1DQVBUVVJFX1RJTUVfUlVMRV9OT19FVklERU5DRRABEh8KG0NBUFRVUkVfVElNRV9SVUxFX0FH'
    'UkVFTUVOVBACEiQKIENBUFRVUkVfVElNRV9SVUxFX01PU1RfQ09ORklERU5UEAM=');

@$core.Deprecated('Use timeEventDescriptor instead')
const TimeEvent$json = {
  '1': 'TimeEvent',
  '2': [
    {'1': 'TIME_EVENT_UNSPECIFIED', '2': 0},
    {'1': 'TIME_EVENT_CAPTURE', '2': 1},
    {'1': 'TIME_EVENT_RECEIVE', '2': 2},
    {'1': 'TIME_EVENT_SAVE', '2': 3},
    {'1': 'TIME_EVENT_TRANSFER', '2': 4},
    {'1': 'TIME_EVENT_SCAN', '2': 5},
  ],
};

/// Descriptor for `TimeEvent`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List timeEventDescriptor = $convert.base64Decode(
    'CglUaW1lRXZlbnQSGgoWVElNRV9FVkVOVF9VTlNQRUNJRklFRBAAEhYKElRJTUVfRVZFTlRfQ0'
    'FQVFVSRRABEhYKElRJTUVfRVZFTlRfUkVDRUlWRRACEhMKD1RJTUVfRVZFTlRfU0FWRRADEhcK'
    'E1RJTUVfRVZFTlRfVFJBTlNGRVIQBBITCg9USU1FX0VWRU5UX1NDQU4QBQ==');

@$core.Deprecated('Use claimVerdictDescriptor instead')
const ClaimVerdict$json = {
  '1': 'ClaimVerdict',
  '2': [
    {'1': 'CLAIM_VERDICT_UNSPECIFIED', '2': 0},
    {'1': 'CLAIM_VERDICT_WON', '2': 1},
    {'1': 'CLAIM_VERDICT_AGREES', '2': 2},
    {'1': 'CLAIM_VERDICT_CONFLICTS', '2': 3},
    {'1': 'CLAIM_VERDICT_OUTVOTED', '2': 4},
    {'1': 'CLAIM_VERDICT_BOUND', '2': 5},
    {'1': 'CLAIM_VERDICT_STALE', '2': 6},
    {'1': 'CLAIM_VERDICT_SCAN_TIME', '2': 7},
    {'1': 'CLAIM_VERDICT_INVALID', '2': 8},
    {'1': 'CLAIM_VERDICT_SENTINEL', '2': 9},
    {'1': 'CLAIM_VERDICT_OUT_OF_RANGE', '2': 10},
    {'1': 'CLAIM_VERDICT_AMBIGUOUS_ORDER', '2': 11},
    {'1': 'CLAIM_VERDICT_NO_YEAR', '2': 12},
    {'1': 'CLAIM_VERDICT_UNKNOWN_SOURCE', '2': 13},
  ],
};

/// Descriptor for `ClaimVerdict`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List claimVerdictDescriptor = $convert.base64Decode(
    'CgxDbGFpbVZlcmRpY3QSHQoZQ0xBSU1fVkVSRElDVF9VTlNQRUNJRklFRBAAEhUKEUNMQUlNX1'
    'ZFUkRJQ1RfV09OEAESGAoUQ0xBSU1fVkVSRElDVF9BR1JFRVMQAhIbChdDTEFJTV9WRVJESUNU'
    'X0NPTkZMSUNUUxADEhoKFkNMQUlNX1ZFUkRJQ1RfT1VUVk9URUQQBBIXChNDTEFJTV9WRVJESU'
    'NUX0JPVU5EEAUSFwoTQ0xBSU1fVkVSRElDVF9TVEFMRRAGEhsKF0NMQUlNX1ZFUkRJQ1RfU0NB'
    'Tl9USU1FEAcSGQoVQ0xBSU1fVkVSRElDVF9JTlZBTElEEAgSGgoWQ0xBSU1fVkVSRElDVF9TRU'
    '5USU5FTBAJEh4KGkNMQUlNX1ZFUkRJQ1RfT1VUX09GX1JBTkdFEAoSIQodQ0xBSU1fVkVSRElD'
    'VF9BTUJJR1VPVVNfT1JERVIQCxIZChVDTEFJTV9WRVJESUNUX05PX1lFQVIQDBIgChxDTEFJTV'
    '9WRVJESUNUX1VOS05PV05fU09VUkNFEA0=');

@$core.Deprecated('Use resolveCaptureTimeRequestDescriptor instead')
const ResolveCaptureTimeRequest$json = {
  '1': 'ResolveCaptureTimeRequest',
  '2': [
    {'1': 'head', '3': 1, '4': 1, '5': 12, '10': 'head'},
    {'1': 'file_name', '3': 2, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'folder', '3': 3, '4': 1, '5': 9, '10': 'folder'},
    {
      '1': 'claims',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.photolib.model.v1.CaptureTime',
      '10': 'claims'
    },
    {
      '1': 'gps_zone',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.TimeZone',
      '10': 'gpsZone'
    },
    {
      '1': 'device_zone',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.TimeZone',
      '10': 'deviceZone'
    },
    {
      '1': 'resolved_at',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'resolvedAt'
    },
    {
      '1': 'ranges',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.FileRange',
      '10': 'ranges'
    },
    {'1': 'size', '3': 9, '4': 1, '5': 4, '10': 'size'},
    {
      '1': 'default_zone',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.photolib.kernel.v1.TimeZone',
      '10': 'defaultZone'
    },
  ],
};

/// Descriptor for `ResolveCaptureTimeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resolveCaptureTimeRequestDescriptor = $convert.base64Decode(
    'ChlSZXNvbHZlQ2FwdHVyZVRpbWVSZXF1ZXN0EhIKBGhlYWQYASABKAxSBGhlYWQSGwoJZmlsZV'
    '9uYW1lGAIgASgJUghmaWxlTmFtZRIWCgZmb2xkZXIYAyABKAlSBmZvbGRlchI2CgZjbGFpbXMY'
    'BCADKAsyHi5waG90b2xpYi5tb2RlbC52MS5DYXB0dXJlVGltZVIGY2xhaW1zEjcKCGdwc196b2'
    '5lGAUgASgLMhwucGhvdG9saWIua2VybmVsLnYxLlRpbWVab25lUgdncHNab25lEj0KC2Rldmlj'
    'ZV96b25lGAYgASgLMhwucGhvdG9saWIua2VybmVsLnYxLlRpbWVab25lUgpkZXZpY2Vab25lEj'
    'sKC3Jlc29sdmVkX2F0GAcgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIKcmVzb2x2'
    'ZWRBdBI1CgZyYW5nZXMYCCADKAsyHS5waG90b2xpYi5rZXJuZWwudjEuRmlsZVJhbmdlUgZyYW'
    '5nZXMSEgoEc2l6ZRgJIAEoBFIEc2l6ZRI/CgxkZWZhdWx0X3pvbmUYCiABKAsyHC5waG90b2xp'
    'Yi5rZXJuZWwudjEuVGltZVpvbmVSC2RlZmF1bHRab25l');

@$core.Deprecated('Use timeZoneDescriptor instead')
const TimeZone$json = {
  '1': 'TimeZone',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'offsets',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.ZoneOffset',
      '10': 'offsets'
    },
  ],
};

/// Descriptor for `TimeZone`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List timeZoneDescriptor = $convert.base64Decode(
    'CghUaW1lWm9uZRISCgRuYW1lGAEgASgJUgRuYW1lEjgKB29mZnNldHMYAiADKAsyHi5waG90b2'
    'xpYi5rZXJuZWwudjEuWm9uZU9mZnNldFIHb2Zmc2V0cw==');

@$core.Deprecated('Use zoneOffsetDescriptor instead')
const ZoneOffset$json = {
  '1': 'ZoneOffset',
  '2': [
    {
      '1': 'starts_at',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'startsAt'
    },
    {'1': 'offset_minutes', '3': 2, '4': 1, '5': 17, '10': 'offsetMinutes'},
  ],
};

/// Descriptor for `ZoneOffset`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List zoneOffsetDescriptor = $convert.base64Decode(
    'Cgpab25lT2Zmc2V0EjcKCXN0YXJ0c19hdBgBIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3'
    'RhbXBSCHN0YXJ0c0F0EiUKDm9mZnNldF9taW51dGVzGAIgASgRUg1vZmZzZXRNaW51dGVz');

@$core.Deprecated('Use resolveCaptureTimeResponseDescriptor instead')
const ResolveCaptureTimeResponse$json = {
  '1': 'ResolveCaptureTimeResponse',
  '2': [
    {
      '1': 'capture_time',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.CaptureTime',
      '10': 'captureTime'
    },
    {
      '1': 'taken_at',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'takenAt'
    },
    {
      '1': 'zone_source',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.ZoneSource',
      '10': 'zoneSource'
    },
    {'1': 'upper_bound', '3': 4, '4': 1, '5': 8, '10': 'upperBound'},
    {
      '1': 'flags',
      '3': 5,
      '4': 3,
      '5': 14,
      '6': '.photolib.kernel.v1.CaptureTimeFlag',
      '10': 'flags'
    },
    {
      '1': 'claims',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.photolib.kernel.v1.TimeClaim',
      '10': 'claims'
    },
    {
      '1': 'rule',
      '3': 7,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.CaptureTimeRule',
      '10': 'rule'
    },
  ],
};

/// Descriptor for `ResolveCaptureTimeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resolveCaptureTimeResponseDescriptor = $convert.base64Decode(
    'ChpSZXNvbHZlQ2FwdHVyZVRpbWVSZXNwb25zZRJBCgxjYXB0dXJlX3RpbWUYASABKAsyHi5waG'
    '90b2xpYi5tb2RlbC52MS5DYXB0dXJlVGltZVILY2FwdHVyZVRpbWUSNQoIdGFrZW5fYXQYAiAB'
    'KAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgd0YWtlbkF0Ej8KC3pvbmVfc291cmNlGA'
    'MgASgOMh4ucGhvdG9saWIua2VybmVsLnYxLlpvbmVTb3VyY2VSCnpvbmVTb3VyY2USHwoLdXBw'
    'ZXJfYm91bmQYBCABKAhSCnVwcGVyQm91bmQSOQoFZmxhZ3MYBSADKA4yIy5waG90b2xpYi5rZX'
    'JuZWwudjEuQ2FwdHVyZVRpbWVGbGFnUgVmbGFncxI1CgZjbGFpbXMYBiADKAsyHS5waG90b2xp'
    'Yi5rZXJuZWwudjEuVGltZUNsYWltUgZjbGFpbXMSNwoEcnVsZRgHIAEoDjIjLnBob3RvbGliLm'
    'tlcm5lbC52MS5DYXB0dXJlVGltZVJ1bGVSBHJ1bGU=');

@$core.Deprecated('Use timeClaimDescriptor instead')
const TimeClaim$json = {
  '1': 'TimeClaim',
  '2': [
    {
      '1': 'time',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.photolib.model.v1.CaptureTime',
      '10': 'time'
    },
    {
      '1': 'event',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.TimeEvent',
      '10': 'event'
    },
    {
      '1': 'verdict',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.photolib.kernel.v1.ClaimVerdict',
      '10': 'verdict'
    },
  ],
};

/// Descriptor for `TimeClaim`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List timeClaimDescriptor = $convert.base64Decode(
    'CglUaW1lQ2xhaW0SMgoEdGltZRgBIAEoCzIeLnBob3RvbGliLm1vZGVsLnYxLkNhcHR1cmVUaW'
    '1lUgR0aW1lEjMKBWV2ZW50GAIgASgOMh0ucGhvdG9saWIua2VybmVsLnYxLlRpbWVFdmVudFIF'
    'ZXZlbnQSOgoHdmVyZGljdBgDIAEoDjIgLnBob3RvbGliLmtlcm5lbC52MS5DbGFpbVZlcmRpY3'
    'RSB3ZlcmRpY3Q=');
