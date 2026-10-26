import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A batch rename (MOB-26): each file's name without its extension, after
/// [find] is replaced with [replace], goes into [template] as `{name}`, with
/// its position from 1 as `{n}` (`{nnn}` pads it to three digits) and
/// its capture time as `{yyyy}`, `{MM}`, `{dd}`, `{HH}`, `{mm}` and `{ss}`.
@immutable
class RenamePattern {
  /// A pattern; by default every name stays.
  const new({this.template = '{name}', this.find = '', this.replace = ''});

  /// The new name, without the extension, which stays.
  final String template;

  /// Text to replace in each name, wherever it is.
  final String find;

  /// What replaces [find].
  final String replace;
}

/// Why a new name cannot be given.
enum RenameProblem {
  /// Longer than the 255 bytes a file name may have.
  tooLong,

  /// Empty, `.` or `..`, or with a character no file name may hold.
  invalid,

  /// The new name of an earlier file too.
  duplicate,

  /// The name of another file of the folder.
  exists,
}

/// A file of a batch rename: its name and when it was taken.
typedef RenameFile = ({String name, DateTime taken});

/// A file's outcome in a rename's preview: its new `name`, null when it keeps
/// its own, and the `problem` that keeps it from taking it.
typedef PlannedName = ({String? name, RenameProblem? problem});

final _token = RegExp(r'\{(name|n+|yyyy|MM|dd|HH|mm|ss)\}');
final _forbidden = RegExp(r'[/\\:*?"<>|\u0000-\u001f]');

/// The new name of each of [files] under [pattern], in order, refusing names
/// that [others], the folder's other files, have: every name is checked, none
/// is cut short.
List<PlannedName> planRename(
  List<RenameFile> files,
  RenamePattern pattern, {
  Set<String> others = const {},
}) {
  final names = [
    for (final (i, file) in files.indexed) _name(file, pattern, i + 1),
  ];
  final other = {for (final o in others) o.toLowerCase()};
  final given = {
    for (final (i, file) in files.indexed)
      if (names[i] == null) file.name.toLowerCase(),
  };
  return [
    for (final name in names)
      (
        name: name,
        problem: name == null
            ? null
            : !validName(name)
            ? RenameProblem.invalid
            : utf8.encode(name).length > 255
            ? RenameProblem.tooLong
            : other.contains(name.toLowerCase())
            ? RenameProblem.exists
            : !given.add(name.toLowerCase())
            ? RenameProblem.duplicate
            : null,
      ),
  ];
}

// The new name of [file], or null when it stays.
String? _name(RenameFile file, RenamePattern pattern, int number) {
  final dot = file.name.lastIndexOf('.');
  final (stem, extension) = dot > 0
      ? (file.name.substring(0, dot), file.name.substring(dot))
      : (file.name, '');
  String two(int n) => '$n'.padLeft(2, '0');
  final t = file.taken;
  final named = pattern.template.replaceAllMapped(
    _token,
    (m) => switch (m[1]) {
      'name' =>
        pattern.find.isEmpty
            ? stem
            : stem.replaceAll(pattern.find, pattern.replace),
      'yyyy' => '${t.year}',
      'MM' => two(t.month),
      'dd' => two(t.day),
      'HH' => two(t.hour),
      'mm' => two(t.minute),
      'ss' => two(t.second),
      final n => '$number'.padLeft(n?.length ?? 1, '0'),
    },
  );
  final name = '$named$extension';
  return name == file.name ? null : (named.isEmpty ? '' : name);
}

/// Whether [name] may name a file on every platform: not empty, `.` or `..`,
/// without a separator, a control character or one Windows forbids.
bool validName(String name) =>
    !const {'', '.', '..'}.contains(name) && !_forbidden.hasMatch(name);

/// Whether [plan] renames a file and refuses none.
bool isRenamable(List<PlannedName> plan) =>
    plan.any((p) => p.name != null) && plan.every((p) => p.problem == null);
