// This is a generated file - do not edit.
//
// Generated from photolib/kernel/v1/metadata.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// How a video's time runs against the time it recorded.
class Pace extends $pb.ProtobufEnum {
  /// Real time, or not said.
  static const Pace PACE_UNSPECIFIED =
      Pace._(0, _omitEnumNames ? '' : 'PACE_UNSPECIFIED');

  /// Recorded faster than it plays: Samsung's Slow_Motion_Data trailer block, Android's com.android.capture.fps over 60,
  /// or a frame rate of 100 and more, as iPhones and action cameras record slow motion.
  static const Pace PACE_SLOW_MOTION =
      Pace._(1, _omitEnumNames ? '' : 'PACE_SLOW_MOTION');

  /// Recorded slower than it plays: Android's com.android.capture.fps below the frame rate.
  static const Pace PACE_TIME_LAPSE =
      Pace._(2, _omitEnumNames ? '' : 'PACE_TIME_LAPSE');

  static const $core.List<Pace> values = <Pace>[
    PACE_UNSPECIFIED,
    PACE_SLOW_MOTION,
    PACE_TIME_LAPSE,
  ];

  static final $core.List<Pace?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Pace? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Pace._(super.value, super.name);
}

/// A file format, by its magic bytes.
class FileFormat extends $pb.ProtobufEnum {
  static const FileFormat FILE_FORMAT_UNSPECIFIED =
      FileFormat._(0, _omitEnumNames ? '' : 'FILE_FORMAT_UNSPECIFIED');
  static const FileFormat FILE_FORMAT_JPEG =
      FileFormat._(1, _omitEnumNames ? '' : 'FILE_FORMAT_JPEG');

  /// TIFF and BigTIFF, with DNG and the TIFF-based RAW formats (CR2, NEF, ARW, ORF, RW2, PEF).
  static const FileFormat FILE_FORMAT_TIFF =
      FileFormat._(2, _omitEnumNames ? '' : 'FILE_FORMAT_TIFF');

  /// HEIC and AVIF.
  static const FileFormat FILE_FORMAT_HEIF =
      FileFormat._(3, _omitEnumNames ? '' : 'FILE_FORMAT_HEIF');
  static const FileFormat FILE_FORMAT_PNG =
      FileFormat._(4, _omitEnumNames ? '' : 'FILE_FORMAT_PNG');
  static const FileFormat FILE_FORMAT_WEBP =
      FileFormat._(5, _omitEnumNames ? '' : 'FILE_FORMAT_WEBP');
  static const FileFormat FILE_FORMAT_GIF =
      FileFormat._(6, _omitEnumNames ? '' : 'FILE_FORMAT_GIF');

  /// An XMP packet on its own, such as a sidecar.
  static const FileFormat FILE_FORMAT_XMP =
      FileFormat._(7, _omitEnumNames ? '' : 'FILE_FORMAT_XMP');

  /// A Fujifilm RAW file, read through its embedded JPEG.
  static const FileFormat FILE_FORMAT_RAF =
      FileFormat._(8, _omitEnumNames ? '' : 'FILE_FORMAT_RAF');

  /// An ISOBMFF or QuickTime movie: MP4, MOV, 3GP and the formats built on them, such as GoPro's LRV.
  static const FileFormat FILE_FORMAT_QUICKTIME =
      FileFormat._(9, _omitEnumNames ? '' : 'FILE_FORMAT_QUICKTIME');

  /// A RIFF AVI movie.
  static const FileFormat FILE_FORMAT_AVI =
      FileFormat._(10, _omitEnumNames ? '' : 'FILE_FORMAT_AVI');

  /// Canon's CR3, a RAW still in ISOBMFF.
  static const FileFormat FILE_FORMAT_CR3 =
      FileFormat._(11, _omitEnumNames ? '' : 'FILE_FORMAT_CR3');

  static const $core.List<FileFormat> values = <FileFormat>[
    FILE_FORMAT_UNSPECIFIED,
    FILE_FORMAT_JPEG,
    FILE_FORMAT_TIFF,
    FILE_FORMAT_HEIF,
    FILE_FORMAT_PNG,
    FILE_FORMAT_WEBP,
    FILE_FORMAT_GIF,
    FILE_FORMAT_XMP,
    FILE_FORMAT_RAF,
    FILE_FORMAT_QUICKTIME,
    FILE_FORMAT_AVI,
    FILE_FORMAT_CR3,
  ];

  static final $core.List<FileFormat?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 11);
  static FileFormat? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FileFormat._(super.value, super.name);
}

/// How a stereoscopic video packs its two views into each frame, numbered as Spherical Video V2's st3d box does.
class StereoMode extends $pb.ProtobufEnum {
  /// Monoscopic, or not said.
  static const StereoMode STEREO_MODE_UNSPECIFIED =
      StereoMode._(0, _omitEnumNames ? '' : 'STEREO_MODE_UNSPECIFIED');
  static const StereoMode STEREO_MODE_TOP_BOTTOM =
      StereoMode._(1, _omitEnumNames ? '' : 'STEREO_MODE_TOP_BOTTOM');
  static const StereoMode STEREO_MODE_LEFT_RIGHT =
      StereoMode._(2, _omitEnumNames ? '' : 'STEREO_MODE_LEFT_RIGHT');

  /// As the projection's mesh lays them out.
  static const StereoMode STEREO_MODE_CUSTOM =
      StereoMode._(3, _omitEnumNames ? '' : 'STEREO_MODE_CUSTOM');
  static const StereoMode STEREO_MODE_RIGHT_LEFT =
      StereoMode._(4, _omitEnumNames ? '' : 'STEREO_MODE_RIGHT_LEFT');

  static const $core.List<StereoMode> values = <StereoMode>[
    STEREO_MODE_UNSPECIFIED,
    STEREO_MODE_TOP_BOTTOM,
    STEREO_MODE_LEFT_RIGHT,
    STEREO_MODE_CUSTOM,
    STEREO_MODE_RIGHT_LEFT,
  ];

  static final $core.List<StereoMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static StereoMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const StereoMode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
