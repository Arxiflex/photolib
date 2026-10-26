// Every field is final: no `package:meta` here to say so with @immutable.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// How much of an item a device keeps (docs/10 §11).
enum Keep {
  /// Nothing: the catalogue, ThumbHashes and metadata, are all it has.
  nothing,

  /// The server's renditions: tiles, the preview and a video's proxy.
  previews,

  /// The renditions and the original.
  originals,
}

/// The presets of a device's storage policy (LIB-20), which Mylio calls
/// presets too. What each keeps of the whole library and of what is pinned:
///
/// | | the library | what is pinned |
/// |---|---|---|
/// | catalogue only | nothing | nothing: pins wait |
/// | space saver | previews | previews, originals if asked |
/// | travel | nothing | previews, originals if asked |
/// | everything | originals | originals |
enum StoragePreset {
  /// The catalogue and nothing else: tiles come from the network.
  catalogueOnly,

  /// Previews of the whole library within the budget.
  spaceSaver,

  /// Only what is pinned, the selected albums, offline.
  travel,

  /// The originals of the whole library within the budget.
  everything,
}

/// What a device keeps of the server's library, and how many bytes it may
/// take for it (LIB-20, R-MODE-1, R-MODE-2): one per device, kept sealed in
/// the vault.
class StoragePolicy {
  /// The policy of [preset] with a [budget] in bytes.
  const StoragePolicy({
    this.preset = StoragePreset.travel,
    this.budget = defaultBudget,
  });

  /// The policy [json] holds; what it does not hold validly is the default.
  factory StoragePolicy.fromJson(Object? json) {
    if (json is! Map) return const StoragePolicy();
    final budget = json['budget'];
    return StoragePolicy(
      preset:
          StoragePreset.values.asNameMap()[json['preset']] ??
          const StoragePolicy().preset,
      budget: budget is int && budget >= minBudget ? budget : defaultBudget,
    );
  }

  /// What a device keeps until the user chooses: nothing but what is pinned,
  /// and then five gigabytes at most.
  static const int defaultBudget = 5000000000;

  /// The least a budget is: it holds a few albums' tiles.
  static const int minBudget = 100000000;

  /// The preset.
  final StoragePreset preset;

  /// The most bytes the offline store takes on disk.
  final int budget;

  /// What it keeps of the whole library.
  Keep get library => switch (preset) {
    StoragePreset.catalogueOnly || StoragePreset.travel => Keep.nothing,
    StoragePreset.spaceSaver => Keep.previews,
    StoragePreset.everything => Keep.originals,
  };

  /// What it keeps of what [pin] pins.
  Keep keepOf(OfflinePin pin) => switch (preset) {
    StoragePreset.catalogueOnly => Keep.nothing,
    StoragePreset.everything => Keep.originals,
    _ => pin.originals ? Keep.originals : Keep.previews,
  };

  /// Whether pins are kept at all: not under *catalogue only*.
  bool get pinsActive => preset != StoragePreset.catalogueOnly;

  /// The policy with [preset] or [budget] changed.
  StoragePolicy copyWith({StoragePreset? preset, int? budget}) => StoragePolicy(
    preset: preset ?? this.preset,
    budget: budget ?? this.budget,
  );

  /// The policy as JSON.
  Map<String, Object?> toJson() => {'preset': preset.name, 'budget': budget};

  @override
  bool operator ==(Object other) =>
      other is StoragePolicy &&
      other.preset == preset &&
      other.budget == budget;

  @override
  int get hashCode => Object.hash(preset, budget);

  @override
  String toString() => 'StoragePolicy(${preset.name}, $budget)';
}

/// What a pin keeps available offline (MOB-15).
enum PinKind {
  /// An album, by its id.
  album,

  /// A search, by its query.
  search,

  /// A person, by their id.
  person,

  /// The whole library.
  library,

  /// One photo or video, kept whole on this device (ADR-0200 P2).
  asset,
}

/// An album, search, person or the whole library the user keeps available
/// offline on this device, up to the storage budget (MOB-15). Pins are not
/// synced: each device has its own.
class OfflinePin {
  const OfflinePin._(
    this.id,
    this.kind,
    this.title,
    this.created, {
    this.target,
    this.query,
    this.originals = false,
  });

  /// The pin of the album [album].
  factory OfflinePin.album(
    List<int> album,
    String title, {
    bool originals = false,
    int created = 0,
  }) => OfflinePin._(
    'album:${_hex(album)}',
    PinKind.album,
    title,
    created,
    target: List.unmodifiable(album),
    originals: originals,
  );

  /// The pin of the person [person].
  factory OfflinePin.person(
    List<int> person,
    String title, {
    bool originals = false,
    int created = 0,
  }) => OfflinePin._(
    'person:${_hex(person)}',
    PinKind.person,
    title,
    created,
    target: List.unmodifiable(person),
    originals: originals,
  );

  /// The pin of the single asset [asset], whose original too is kept, as
  /// *Keep on this device* does (ADR-0200 P2).
  factory OfflinePin.asset(
    List<int> asset,
    String title, {
    bool originals = true,
    int created = 0,
  }) => OfflinePin._(
    'asset:${_hex(asset)}',
    PinKind.asset,
    title,
    created,
    target: List.unmodifiable(asset),
    originals: originals,
  );

  /// The pin of the whole library.
  factory OfflinePin.library({bool originals = false, int created = 0}) =>
      OfflinePin._(
        libraryId,
        PinKind.library,
        '',
        created,
        originals: originals,
      );

  /// The pin of the search [query], as the app keeps it, under [id].
  factory OfflinePin.search(
    Map<String, Object?> query,
    String title, {
    required String id,
    bool originals = false,
    int created = 0,
  }) => OfflinePin._(
    'search:$id',
    PinKind.search,
    title,
    created,
    query: query,
    originals: originals,
  );

  /// The id of the pin of the whole library, which the library's baseline
  /// under *space saver* and *everything* shares.
  static const libraryId = 'library';

  /// Names the pin among the others: its kind and target.
  final String id;

  /// What it pins.
  final PinKind kind;

  /// What the user sees it by: an album's title, a person's name, a search.
  final String title;

  /// When it was made, in milliseconds since the epoch.
  final int created;

  /// The id of an album or a person.
  final List<int>? target;

  /// A search's query, as the app keeps it.
  final Map<String, Object?>? query;

  /// Whether it keeps the originals too, not only the renditions.
  final bool originals;

  /// The pin with [originals] or [title] changed.
  OfflinePin copyWith({bool? originals, String? title}) => OfflinePin._(
    id,
    kind,
    title ?? this.title,
    created,
    target: target,
    query: query,
    originals: originals ?? this.originals,
  );

  /// The pin as JSON.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'created': created,
    'target': ?_hexOrNull(target),
    'query': ?query,
    if (originals) 'originals': true,
  };

  /// The pin [json] holds, or null when it holds none.
  static OfflinePin? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = PinKind.values.asNameMap()[json['kind']];
    final id = json['id'];
    if (kind == null || id is! String) return null;
    final title = json['title'] is String ? json['title'] as String : '';
    final created = json['created'] is int ? json['created'] as int : 0;
    final originals = json['originals'] == true;
    final target = json['target'] is String
        ? _unhex(json['target'] as String)
        : null;
    final query = json['query'] is Map
        ? Map<String, Object?>.from(json['query'] as Map)
        : null;
    return switch (kind) {
      PinKind.album when target != null => OfflinePin.album(
        target,
        title,
        originals: originals,
        created: created,
      ),
      PinKind.person when target != null => OfflinePin.person(
        target,
        title,
        originals: originals,
        created: created,
      ),
      PinKind.asset when target != null => OfflinePin.asset(
        target,
        title,
        originals: originals,
        created: created,
      ),
      PinKind.library => OfflinePin.library(
        originals: originals,
        created: created,
      ),
      PinKind.search when query != null && id.startsWith('search:') =>
        OfflinePin.search(
          query,
          title,
          id: id.substring(7),
          originals: originals,
          created: created,
        ),
      _ => null,
    };
  }

  /// [pins] as JSON.
  static List<Object?> listToJson(List<OfflinePin> pins) => [
    for (final p in pins) p.toJson(),
  ];

  /// The pins [json] holds, the valid ones, once each.
  static List<OfflinePin> listFromJson(Object? json) {
    if (json is! List) return const [];
    final seen = <String>{};
    return [
      for (final j in json)
        if (fromJson(j) case final pin? when seen.add(pin.id)) pin,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is OfflinePin &&
      other.id == id &&
      other.title == title &&
      other.created == created &&
      other.originals == originals &&
      _same(other.target, target) &&
      _same(other.query, query);

  @override
  int get hashCode => Object.hash(id, title, created, originals);

  @override
  String toString() => 'OfflinePin($id)';
}

String? _hexOrNull(List<int>? bytes) => bytes == null ? null : _hex(bytes);

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

List<int>? _unhex(String text) {
  if (text.length.isOdd || text.length > 64) return null;
  try {
    return List.unmodifiable([
      for (var i = 0; i < text.length; i += 2)
        int.parse(text.substring(i, i + 2), radix: 16),
    ]);
  } on FormatException {
    return null;
  }
}

// Whether two JSON-like values are equal throughout.
bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        [for (var i = 0; i < a.length; i++) _same(a[i], b[i])].every((e) => e);
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
  }
  return a == b;
}
