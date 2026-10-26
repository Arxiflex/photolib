/// What a folder scan skips: the defaults shared with the server, then the `.photolibignore` of each directory from
/// the root down, in gitignore syntax (docs/07-storage-and-libraries.md §4, testdata/photolibignore.json). Paths are
/// `/`-separated under the root; the scanner never enters an ignored directory, so nothing below it comes back.
class IgnoreRules {
  const IgnoreRules._(this._rules, this._caseSensitive);

  /// The defaults, matching names in any case unless [caseSensitive], as the folder's file system compares them.
  factory IgnoreRules.defaults({
    required bool caseSensitive,
  }) => IgnoreRules._(const [], caseSensitive).add(
    '',
    r'@eaDir \#recycle .thumbnails .trashed-* .Trash-* $RECYCLE.BIN .dtrash Thumbs.db .DS_Store .AppleDouble'
        .replaceAll(' ', '\n'),
  );

  final List<({String base, RegExp glob, bool negate, bool dirOnly})> _rules;
  final bool _caseSensitive;

  /// These rules followed by [text], the `.photolibignore` of the directory [base].
  IgnoreRules add(String base, String text) {
    final added = [
      for (var line in text.split('\n'))
        if (!line.startsWith('#') &&
            (line = line.replaceFirst(
              RegExp(r'(?<!\\)[ \r]+$'),
              '',
            )).isNotEmpty)
          _rule(base, line, _caseSensitive),
    ];
    return added.isEmpty
        ? this
        : IgnoreRules._([..._rules, ...added], _caseSensitive);
  }

  /// Whether the last rule that matches [path], a directory if [dir], ignores it.
  bool ignores(String path, {bool dir = false}) {
    for (final r in _rules.reversed) {
      if (r.dirOnly && !dir) continue;
      final rest = r.base.isEmpty ? path : path.substring(r.base.length + 1);
      if (r.glob.hasMatch(rest)) return !r.negate;
    }
    return false;
  }
}

({String base, RegExp glob, bool negate, bool dirOnly}) _rule(
  String base,
  String line,
  bool caseSensitive,
) {
  final negate = line.startsWith('!');
  if (negate) line = line.substring(1);
  final dirOnly = line.endsWith('/');
  if (dirOnly) line = line.substring(0, line.length - 1);
  // A slash before the end anchors the pattern to [base]; without one it matches a name at any depth.
  final out = StringBuffer(line.contains('/') ? '^' : '^(?:.*/)?');
  if (line.startsWith('/')) line = line.substring(1);
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    final end = c == '[' ? line.indexOf(']', i + 2) : -1;
    if (line.startsWith('**', i) &&
        (i == 0 || line[i - 1] == '/') &&
        (i + 2 == line.length || line[i + 2] == '/')) {
      out.write(i + 2 == line.length ? '.*' : '(?:.*/)?');
      i += 2;
    } else if (c == '*') {
      out.write('[^/]*');
      while (line.startsWith('*', i + 1)) {
        i++;
      }
    } else if (c == '?') {
      out.write('[^/]');
    } else if (end > 0) {
      final set = line.substring(i + 1, end);
      final not = set.startsWith('!') || set.startsWith('^');
      out.write(
        '(?!/)[${not ? '^' : ''}'
        '${(not ? set.substring(1) : set).replaceAll(r'\', r'\\').replaceAll('[', r'\[')}]',
      );
      i = end;
    } else {
      if (c == r'\' && i + 1 < line.length) i++;
      out.write(RegExp.escape(line[i]));
    }
  }
  final glob = RegExp('$out\$', caseSensitive: caseSensitive);
  return (base: base, glob: glob, negate: negate, dirOnly: dirOnly);
}
