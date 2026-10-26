// This is a generated file - do not edit.
//
// Generated from photolib/api/v1/admin.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Where a library's files are.
class LibraryKind extends $pb.ProtobufEnum {
  static const LibraryKind LIBRARY_KIND_UNSPECIFIED =
      LibraryKind._(0, _omitEnumNames ? '' : 'LIBRARY_KIND_UNSPECIFIED');
  static const LibraryKind LIBRARY_KIND_MANAGED =
      LibraryKind._(1, _omitEnumNames ? '' : 'LIBRARY_KIND_MANAGED');
  static const LibraryKind LIBRARY_KIND_EXTERNAL =
      LibraryKind._(2, _omitEnumNames ? '' : 'LIBRARY_KIND_EXTERNAL');

  static const $core.List<LibraryKind> values = <LibraryKind>[
    LIBRARY_KIND_UNSPECIFIED,
    LIBRARY_KIND_MANAGED,
    LIBRARY_KIND_EXTERNAL,
  ];

  static final $core.List<LibraryKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static LibraryKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const LibraryKind._(super.value, super.name);
}

/// Whether a library can be read.
class LibraryState extends $pb.ProtobufEnum {
  static const LibraryState LIBRARY_STATE_UNSPECIFIED =
      LibraryState._(0, _omitEnumNames ? '' : 'LIBRARY_STATE_UNSPECIFIED');
  static const LibraryState LIBRARY_STATE_ONLINE =
      LibraryState._(1, _omitEnumNames ? '' : 'LIBRARY_STATE_ONLINE');

  /// Its root or marker is missing; nothing in it changes.
  static const LibraryState LIBRARY_STATE_OFFLINE =
      LibraryState._(2, _omitEnumNames ? '' : 'LIBRARY_STATE_OFFLINE');
  static const LibraryState LIBRARY_STATE_SCANNING =
      LibraryState._(3, _omitEnumNames ? '' : 'LIBRARY_STATE_SCANNING');
  static const LibraryState LIBRARY_STATE_ERROR =
      LibraryState._(4, _omitEnumNames ? '' : 'LIBRARY_STATE_ERROR');

  static const $core.List<LibraryState> values = <LibraryState>[
    LIBRARY_STATE_UNSPECIFIED,
    LIBRARY_STATE_ONLINE,
    LIBRARY_STATE_OFFLINE,
    LIBRARY_STATE_SCANNING,
    LIBRARY_STATE_ERROR,
  ];

  static final $core.List<LibraryState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static LibraryState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const LibraryState._(super.value, super.name);
}

/// What a scrub or a read found wrong with an object.
class FindingKind extends $pb.ProtobufEnum {
  static const FindingKind FINDING_KIND_UNSPECIFIED =
      FindingKind._(0, _omitEnumNames ? '' : 'FINDING_KIND_UNSPECIFIED');

  /// Its bytes no longer have the hash recorded when it was written: bit-rot or a silent change.
  static const FindingKind FINDING_KIND_CONTENT =
      FindingKind._(1, _omitEnumNames ? '' : 'FINDING_KIND_CONTENT');

  /// It is gone.
  static const FindingKind FINDING_KIND_MISSING =
      FindingKind._(2, _omitEnumNames ? '' : 'FINDING_KIND_MISSING');

  /// It has another size than recorded, such as a truncated one.
  static const FindingKind FINDING_KIND_SIZE =
      FindingKind._(3, _omitEnumNames ? '' : 'FINDING_KIND_SIZE');

  /// It carries another hash than recorded: it was replaced.
  static const FindingKind FINDING_KIND_HASH =
      FindingKind._(4, _omitEnumNames ? '' : 'FINDING_KIND_HASH');

  /// It lies under a library, but no file names it.
  static const FindingKind FINDING_KIND_ORPHAN =
      FindingKind._(5, _omitEnumNames ? '' : 'FINDING_KIND_ORPHAN');

  static const $core.List<FindingKind> values = <FindingKind>[
    FINDING_KIND_UNSPECIFIED,
    FINDING_KIND_CONTENT,
    FINDING_KIND_MISSING,
    FINDING_KIND_SIZE,
    FINDING_KIND_HASH,
    FINDING_KIND_ORPHAN,
  ];

  static final $core.List<FindingKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static FindingKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FindingKind._(super.value, super.name);
}

/// Where a job is in its life.
class JobStatus extends $pb.ProtobufEnum {
  static const JobStatus JOB_STATUS_UNSPECIFIED =
      JobStatus._(0, _omitEnumNames ? '' : 'JOB_STATUS_UNSPECIFIED');
  static const JobStatus JOB_STATUS_QUEUED =
      JobStatus._(1, _omitEnumNames ? '' : 'JOB_STATUS_QUEUED');
  static const JobStatus JOB_STATUS_RUNNING =
      JobStatus._(2, _omitEnumNames ? '' : 'JOB_STATUS_RUNNING');
  static const JobStatus JOB_STATUS_DONE =
      JobStatus._(3, _omitEnumNames ? '' : 'JOB_STATUS_DONE');

  /// Failed every attempt: the dead-letter queue.
  static const JobStatus JOB_STATUS_DEAD =
      JobStatus._(4, _omitEnumNames ? '' : 'JOB_STATUS_DEAD');
  static const JobStatus JOB_STATUS_CANCELLED =
      JobStatus._(5, _omitEnumNames ? '' : 'JOB_STATUS_CANCELLED');

  static const $core.List<JobStatus> values = <JobStatus>[
    JOB_STATUS_UNSPECIFIED,
    JOB_STATUS_QUEUED,
    JOB_STATUS_RUNNING,
    JOB_STATUS_DONE,
    JOB_STATUS_DEAD,
    JOB_STATUS_CANCELLED,
  ];

  static final $core.List<JobStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static JobStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const JobStatus._(super.value, super.name);
}

/// The outcome of a check.
class CheckStatus extends $pb.ProtobufEnum {
  static const CheckStatus CHECK_STATUS_UNSPECIFIED =
      CheckStatus._(0, _omitEnumNames ? '' : 'CHECK_STATUS_UNSPECIFIED');
  static const CheckStatus CHECK_STATUS_OK =
      CheckStatus._(1, _omitEnumNames ? '' : 'CHECK_STATUS_OK');

  /// Works, but needs attention.
  static const CheckStatus CHECK_STATUS_WARN =
      CheckStatus._(2, _omitEnumNames ? '' : 'CHECK_STATUS_WARN');
  static const CheckStatus CHECK_STATUS_FAIL =
      CheckStatus._(3, _omitEnumNames ? '' : 'CHECK_STATUS_FAIL');

  static const $core.List<CheckStatus> values = <CheckStatus>[
    CHECK_STATUS_UNSPECIFIED,
    CHECK_STATUS_OK,
    CHECK_STATUS_WARN,
    CHECK_STATUS_FAIL,
  ];

  static final $core.List<CheckStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static CheckStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CheckStatus._(super.value, super.name);
}

/// What to redo for the assets of a scope.
class ReprocessKind extends $pb.ProtobufEnum {
  static const ReprocessKind REPROCESS_KIND_UNSPECIFIED =
      ReprocessKind._(0, _omitEnumNames ? '' : 'REPROCESS_KIND_UNSPECIFIED');

  /// Read the original's metadata again: a `metadata` job per asset.
  static const ReprocessKind REPROCESS_KIND_METADATA =
      ReprocessKind._(1, _omitEnumNames ? '' : 'REPROCESS_KIND_METADATA');

  /// Render every rendition again: a `renditions` job per asset.
  static const ReprocessKind REPROCESS_KIND_RENDITIONS =
      ReprocessKind._(2, _omitEnumNames ? '' : 'REPROCESS_KIND_RENDITIONS');

  /// Detect faces again: a `faces` job per asset.
  static const ReprocessKind REPROCESS_KIND_FACES =
      ReprocessKind._(3, _omitEnumNames ? '' : 'REPROCESS_KIND_FACES');

  static const $core.List<ReprocessKind> values = <ReprocessKind>[
    REPROCESS_KIND_UNSPECIFIED,
    REPROCESS_KIND_METADATA,
    REPROCESS_KIND_RENDITIONS,
    REPROCESS_KIND_FACES,
  ];

  static final $core.List<ReprocessKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ReprocessKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReprocessKind._(super.value, super.name);
}

/// A capability the server's policy switches (design 15 §10); off, the server refuses what needs it to everyone.
class Capability extends $pb.ProtobufEnum {
  static const Capability CAPABILITY_UNSPECIFIED =
      Capability._(0, _omitEnumNames ? '' : 'CAPABILITY_UNSPECIFIED');

  /// Managed libraries: none is created, and none takes uploads.
  static const Capability CAPABILITY_MANAGED_LIBRARIES =
      Capability._(1, _omitEnumNames ? '' : 'CAPABILITY_MANAGED_LIBRARIES');

  /// Uploads from devices, the web and the CLI.
  static const Capability CAPABILITY_UPLOADS =
      Capability._(2, _omitEnumNames ? '' : 'CAPABILITY_UPLOADS');

  /// Browsing a library's folders.
  static const Capability CAPABILITY_FOLDER_BROWSER =
      Capability._(3, _omitEnumNames ? '' : 'CAPABILITY_FOLDER_BROWSER');

  /// Device folders in the apps connected to the server.
  static const Capability CAPABILITY_DEVICE_FOLDERS =
      Capability._(4, _omitEnumNames ? '' : 'CAPABILITY_DEVICE_FOLDERS');

  /// Sharing and public links: no album, partner share or link gives access, and none is made.
  static const Capability CAPABILITY_SHARING =
      Capability._(5, _omitEnumNames ? '' : 'CAPABILITY_SHARING');

  /// Editing assets.
  static const Capability CAPABILITY_EDITS =
      Capability._(6, _omitEnumNames ? '' : 'CAPABILITY_EDITS');

  /// Trashing and deleting assets.
  static const Capability CAPABILITY_DELETES =
      Capability._(7, _omitEnumNames ? '' : 'CAPABILITY_DELETES');

  /// Writing XMP sidecars.
  static const Capability CAPABILITY_XMP_WRITES =
      Capability._(8, _omitEnumNames ? '' : 'CAPABILITY_XMP_WRITES');

  /// Faces and people.
  static const Capability CAPABILITY_FACE_RECOGNITION =
      Capability._(9, _omitEnumNames ? '' : 'CAPABILITY_FACE_RECOGNITION');

  /// Smart search.
  static const Capability CAPABILITY_ML_SEARCH =
      Capability._(10, _omitEnumNames ? '' : 'CAPABILITY_ML_SEARCH');

  static const $core.List<Capability> values = <Capability>[
    CAPABILITY_UNSPECIFIED,
    CAPABILITY_MANAGED_LIBRARIES,
    CAPABILITY_UPLOADS,
    CAPABILITY_FOLDER_BROWSER,
    CAPABILITY_DEVICE_FOLDERS,
    CAPABILITY_SHARING,
    CAPABILITY_EDITS,
    CAPABILITY_DELETES,
    CAPABILITY_XMP_WRITES,
    CAPABILITY_FACE_RECOGNITION,
    CAPABILITY_ML_SEARCH,
  ];

  static final $core.List<Capability?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 10);
  static Capability? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Capability._(super.value, super.name);
}

/// The level a capability's effective value comes from: the narrowest that sets it, unless the configuration pins it.
class PolicySource extends $pb.ProtobufEnum {
  static const PolicySource POLICY_SOURCE_UNSPECIFIED =
      PolicySource._(0, _omitEnumNames ? '' : 'POLICY_SOURCE_UNSPECIFIED');

  /// No level sets it: on.
  static const PolicySource POLICY_SOURCE_DEFAULT =
      PolicySource._(1, _omitEnumNames ? '' : 'POLICY_SOURCE_DEFAULT');
  static const PolicySource POLICY_SOURCE_SERVER =
      PolicySource._(2, _omitEnumNames ? '' : 'POLICY_SOURCE_SERVER');
  static const PolicySource POLICY_SOURCE_USER =
      PolicySource._(3, _omitEnumNames ? '' : 'POLICY_SOURCE_USER');
  static const PolicySource POLICY_SOURCE_LIBRARY =
      PolicySource._(4, _omitEnumNames ? '' : 'POLICY_SOURCE_LIBRARY');

  /// Pinned in the configuration file: read-only.
  static const PolicySource POLICY_SOURCE_CONFIG =
      PolicySource._(5, _omitEnumNames ? '' : 'POLICY_SOURCE_CONFIG');

  static const $core.List<PolicySource> values = <PolicySource>[
    POLICY_SOURCE_UNSPECIFIED,
    POLICY_SOURCE_DEFAULT,
    POLICY_SOURCE_SERVER,
    POLICY_SOURCE_USER,
    POLICY_SOURCE_LIBRARY,
    POLICY_SOURCE_CONFIG,
  ];

  static final $core.List<PolicySource?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static PolicySource? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PolicySource._(super.value, super.name);
}

/// A set of switches for a kind of server (design 15 §10, ADR-0240).
class Preset extends $pb.ProtobufEnum {
  static const Preset PRESET_UNSPECIFIED =
      Preset._(0, _omitEnumNames ? '' : 'PRESET_UNSPECIFIED');

  /// External read-only libraries are the only source of truth: only browsing, sharing, faces and smart search on.
  static const Preset PRESET_ARCHIVE_VIEWER =
      Preset._(1, _omitEnumNames ? '' : 'PRESET_ARCHIVE_VIEWER');

  /// A household backs up and shares: everything on but XMP writes.
  static const Preset PRESET_FAMILY_BACKUP =
      Preset._(2, _omitEnumNames ? '' : 'PRESET_FAMILY_BACKUP');

  /// One person: everything on but sharing and public links.
  static const Preset PRESET_PERSONAL =
      Preset._(3, _omitEnumNames ? '' : 'PRESET_PERSONAL');

  static const $core.List<Preset> values = <Preset>[
    PRESET_UNSPECIFIED,
    PRESET_ARCHIVE_VIEWER,
    PRESET_FAMILY_BACKUP,
    PRESET_PERSONAL,
  ];

  static final $core.List<Preset?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static Preset? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Preset._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
