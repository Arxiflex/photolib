import 'package:intl/intl.dart';

import 'app_localizations.dart';

/// [path] laid out left to right, as paths are, inside right-to-left text.
String isolated(String path) => '\u2066$path\u2069';

/// Dates, numbers and file sizes in the user's locale (docs/17 §1). Dates and
/// the first day of the week may follow another locale than the language, such
/// as `en_GB` in an English app, for day-month-year dates.
class Formats {
  Formats(this.strings, {String? dateLocale})
    : _dates = DateFormat.yMMMd(dateLocale ?? strings.localeName),
      _months = DateFormat.yMMM(dateLocale ?? strings.localeName),
      _years = DateFormat.y(dateLocale ?? strings.localeName),
      _times = DateFormat.yMMMd(dateLocale ?? strings.localeName).add_jm();

  final AppLocalizations strings;
  final DateFormat _dates;
  final DateFormat _months;
  final DateFormat _years;
  final DateFormat _times;

  String date(DateTime when) => _dates.format(when);
  String month(DateTime when) => _months.format(when);
  String year(DateTime when) => _years.format(when);

  /// A capture time as far as its [precision] goes: `year`, `month`, `day`,
  /// else to the minute.
  String taken(DateTime when, [String? precision]) => switch (precision) {
    'year' => year(when),
    'month' => month(when),
    'day' => date(when),
    _ => _times.format(when),
  };

  String number(num value) =>
      NumberFormat.decimalPattern(strings.localeName).format(value);

  String percent(int value) =>
      NumberFormat.percentPattern(strings.localeName).format(value / 100);

  /// Latitude and longitude to five decimals, about a metre.
  String place(double lat, double lon) {
    final degrees = NumberFormat('0.00000', strings.localeName);
    return '${degrees.format(lat)}, ${degrees.format(lon)}';
  }

  /// A video's length as m:ss, or h:mm:ss, to the nearest second.
  String duration(Duration length) {
    final s = (length.inMilliseconds / 1000).round();
    final two = NumberFormat('00', strings.localeName);
    final (h, m) = (s ~/ 3600, s ~/ 60 % 60);
    return [
      if (h > 0) number(h),
      if (h > 0) two.format(m) else number(m),
      two.format(s % 60),
    ].join(':');
  }

  String fileSize(int bytes) {
    const units = ['B', 'kB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (unit < units.length - 1 && (size * 10).round() >= 10000) {
      size /= 1000;
      unit++;
    }
    return strings.fileSize((size * 10).round() / 10, units[unit]);
  }

  /// [DateTime.monday] to [DateTime.sunday].
  int get firstDayOfWeek => _dates.dateSymbols.FIRSTDAYOFWEEK + 1;
}
