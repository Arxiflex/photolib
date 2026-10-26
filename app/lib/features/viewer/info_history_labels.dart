import 'package:photolib/features/viewer/info_facts.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';

/// What a step of a recipe is called in the edit history, by the kernel's
/// name for it (`InfoVersion.changes`).
String changeLabel(AppLocalizations strings, String change) => switch (change) {
  'turn' => strings.infoChangeTurn,
  'flip' => strings.infoChangeFlip,
  'crop' => strings.infoChangeCrop,
  'adjust' => strings.infoChangeAdjust,
  'lut' => strings.infoChangeLut,
  'local_adjust' => strings.infoChangeLocal,
  'inpaint' => strings.infoChangeInpaint,
  _ => strings.infoChangeOther,
};

/// A version's title in the history: its label, else Original, else Edit
/// [number] (counted from the oldest), and Current when it is.
String versionTitle(AppLocalizations strings, InfoVersion v, int number) => [
  if (v.label.isNotEmpty)
    v.label
  else if (v.original)
    strings.infoOriginal
  else
    strings.infoEditNumber(number),
  if (v.current) strings.infoCurrent,
].join(' · ');

/// A version's lines under its title: when, on what device, what changed.
String versionDetail(
  AppLocalizations strings,
  Formats formats,
  InfoVersion v,
) => [
  formats.taken(v.time),
  v.device,
  if (v.change.isNotEmpty) v.change,
  if (v.changes.isNotEmpty)
    v.changes.map((c) => changeLabel(strings, c)).join(', '),
].where((s) => s.isNotEmpty).join('\n');
