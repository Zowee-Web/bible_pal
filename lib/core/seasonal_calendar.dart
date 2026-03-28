/// Detects the current liturgical/cultural season for story surfacing.
/// Returns a season tag that matches Parable.seasonTag values.
class SeasonalCalendar {
  /// Get the current season tag, or null if no special season.
  /// Seasons: 'advent', 'christmas', 'lent', 'easter', 'thanksgiving'
  static String? getCurrentSeason([DateTime? now]) {
    final date = now ?? DateTime.now();
    final month = date.month;
    final day = date.day;

    // Thanksgiving: US, 4th Thursday of November (approx Nov 22-28)
    if (month == 11 && day >= 20 && day <= 30) return 'thanksgiving';

    // Advent: ~Dec 1–24
    if (month == 12 && day <= 24) return 'advent';

    // Christmas: Dec 25 – Jan 6
    if (month == 12 && day >= 25) return 'christmas';
    if (month == 1 && day <= 6) return 'christmas';

    // Lent: 46 days before Easter (Ash Wednesday to Holy Saturday)
    // Must check Lent BEFORE Easter since Palm Sunday overlaps both windows
    final easter = _computeEaster(date.year);
    final ashWednesday = easter.subtract(const Duration(days: 46));
    final holySaturday = easter.subtract(const Duration(days: 1));
    if (!date.isBefore(ashWednesday) && !date.isAfter(holySaturday)) {
      return 'lent';
    }

    // Easter season: Palm Sunday through Easter +7
    final palmSunday = easter.subtract(const Duration(days: 7));
    final easterEnd = easter.add(const Duration(days: 7));
    if (!date.isBefore(palmSunday) && !date.isAfter(easterEnd)) {
      return 'easter';
    }

    return null;
  }

  /// Get a seasonal greeting message for PAL, or null if no season.
  static String? getSeasonalGreeting([DateTime? now]) {
    final season = getCurrentSeason(now);
    if (season == null) return null;

    switch (season) {
      case 'advent':
        return 'It\'s Advent season. I have something special for you today.';
      case 'christmas':
        return 'Merry Christmas. I have a story to celebrate with you.';
      case 'lent':
        return 'This Lenten season, let\'s listen together.';
      case 'easter':
        return 'It\'s Easter. I have a story of hope for you.';
      case 'thanksgiving':
        return 'In this season of thanks, I have a grateful story for you.';
      default:
        return null;
    }
  }

  /// Compute Easter Sunday for a given year (Anonymous Gregorian algorithm).
  static DateTime _computeEaster(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }
}
