import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';

void main() {
  late AppLocalizations english;

  setUpAll(() async {
    english = await AppLocalizations.delegate.load(const Locale('en'));
    await GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  });

  final may3 = DateTime(2024, 5, 3);

  test('dates, numbers and the first day of the week follow the locale', () {
    final formats = Formats(english);
    expect(formats.date(may3), 'May 3, 2024');
    expect(formats.month(may3), 'May 2024');
    expect(formats.year(may3), '2024');
    expect(formats.number(1234567.5), '1,234,567.5');
    expect(formats.firstDayOfWeek, DateTime.sunday);
  });

  test('a capture time shows as far as it is known, and percentages and '
      'coordinates follow the locale', () {
    final formats = Formats(english);
    final when = DateTime(2024, 5, 3, 16, 3, 9);
    expect(formats.taken(when), 'May 3, 2024 4:03\u202fPM');
    expect(formats.taken(when, 'second'), 'May 3, 2024 4:03\u202fPM');
    expect(formats.taken(when, 'day'), 'May 3, 2024');
    expect(formats.taken(when, 'month'), 'May 2024');
    expect(formats.taken(when, 'year'), '2024');
    expect(formats.percent(95), '95%');
    expect(formats.place(48.858361, -2.2944), '48.85836, -2.29440');
  });

  test('dates can follow another locale than the language', () {
    final formats = Formats(english, dateLocale: 'en_GB');
    expect(formats.date(may3), '3 May 2024');
    expect(formats.firstDayOfWeek, DateTime.monday);
    expect(formats.number(1234567.5), '1,234,567.5');
  });

  test("a video's length is m:ss, or h:mm:ss, to the nearest second", () {
    final length = Formats(english).duration;
    expect(length(const Duration(milliseconds: 2008)), '0:02');
    expect(length(const Duration(minutes: 1, seconds: 5)), '1:05');
    expect(
      length(const Duration(hours: 2, seconds: 59, milliseconds: 600)),
      '2:01:00',
    );
  });

  test('file sizes use powers of 1000 and at most one decimal', () {
    final size = Formats(english).fileSize;
    expect(size(0), '0 B');
    expect(size(999), '999 B');
    expect(size(1000), '1 kB');
    expect(size(1500000), '1.5 MB');
    expect(size(999949), '999.9 kB');
    expect(size(999950), '1 MB');
    expect(size(3210000000000), '3.2 TB');
    expect(size(5000000000000000), '5,000 TB');
  });

  test('a translation formats the number and names the unit', () async {
    final pseudo = await AppLocalizations.delegate.load(
      const Locale('en', 'XA'),
    );
    expect(Formats(pseudo).fileSize(1500000), '[1.5 ṀƁ one]');
  });
}
