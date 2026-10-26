import 'package:flutter/foundation.dart';

enum Flag {
  diagnostics(defaultOn: false),

  /// Offers the pseudo-locales en-XA and ar-XB (docs/dev/flutter.md).
  pseudoLocales(defaultOn: false);

  const Flag({required this.defaultOn});

  final bool defaultOn;
}

/// Local switches only: set at build time, never fetched from a server.
@immutable
class FeatureFlags {
  const FeatureFlags(this._overrides);

  /// Parses `name,-name,...`; a leading minus turns a flag off.
  factory FeatureFlags.parse(String spec) {
    final overrides = <Flag, bool>{};
    for (final raw in spec.split(',')) {
      final token = raw.trim();
      final on = !token.startsWith('-');
      final name = on ? token : token.substring(1);
      for (final flag in Flag.values) {
        if (flag.name == name) overrides[flag] = on;
      }
    }
    return FeatureFlags(overrides);
  }

  final Map<Flag, bool> _overrides;

  bool isOn(Flag flag) => _overrides[flag] ?? flag.defaultOn;
}
