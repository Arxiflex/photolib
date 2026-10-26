/// The prototype edit decision list: the video body of `EditRecipe` (design 11 §6.1) in its JSON form, limited to
/// one track of trimmed clips. M8-01 replaces it with the generated protobuf message.
class Edl {
  Edl(
    this.clips, {
    this.keepHdr = true,
    this.maxShortSide,
    this.preferLossless = true,
    this.keepLocation = true,
  });

  factory Edl.fromJson(Map<String, Object?> json) {
    try {
      final [track] = json['tracks'] as List;
      final clips = [
        for (final item in (track as Map)['items'] as List)
          switch (item) {
            {
              'clip': {
                'assetId': final String id,
                'source': {
                  'start': final Map start,
                  'duration': final Map length,
                },
              },
            } =>
              Clip(id, _us(start), _us(length)),
            _ => throw FormatException('unsupported item $item'),
          },
      ];
      if (clips.isEmpty ||
          clips.any((c) => c.startUs < 0 || c.durationUs <= 0)) {
        throw FormatException(
          'no clips, or a clip with a negative start or no duration',
        );
      }
      final output = json['output'] as Map? ?? const {};
      return Edl(
        clips,
        keepHdr: switch (output['hdr'] ?? 'KEEP_IF_ALL_HDR') {
          'KEEP_IF_ALL_HDR' => true,
          'TONE_MAP' => false,
          final other => throw FormatException('unsupported HDR policy $other'),
        },
        maxShortSide: output['maxShortSide'] as int?,
        preferLossless:
            (json['planner'] as Map?)?['preferLossless'] as bool? ?? true,
        keepLocation:
            !((json['metadata'] as Map?)?['stripGps'] as bool? ?? false),
      );
    } on TypeError catch (e) {
      throw FormatException('malformed edit decision list: $e');
    } on StateError catch (e) {
      throw FormatException('malformed edit decision list: $e');
    }
  }

  final List<Clip> clips;
  final bool keepHdr;
  final int? maxShortSide;
  final bool preferLossless;
  final bool keepLocation;
}

/// A range of one source, in microseconds of its own timeline.
class Clip {
  const Clip(this.assetId, this.startUs, this.durationUs);

  final String assetId;
  final int startUs;
  final int durationUs;
}

int _us(Map rational) {
  final {'num': int num, 'den': int den} = rational;
  if (den <= 0) throw FormatException('denominator $den');
  return (num * 1000000 / den).round();
}
