import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/seasonal_calendar.dart';

void main() {
  group('SeasonalCalendar.getCurrentSeason', () {
    test('Advent: Dec 1-24', () {
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 12, 1)), 'advent');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 12, 15)), 'advent');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 12, 24)), 'advent');
    });

    test('Christmas: Dec 25 - Jan 6', () {
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 12, 25)), 'christmas');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 12, 31)), 'christmas');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2027, 1, 1)), 'christmas');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2027, 1, 6)), 'christmas');
    });

    test('Thanksgiving: Nov 20-30', () {
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 11, 22)), 'thanksgiving');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 11, 26)), 'thanksgiving');
    });

    test('Easter 2026 (April 5)', () {
      // Easter 2026 is April 5
      // Easter Sunday and the week after
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 4, 5)), 'easter');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 4, 8)), 'easter');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 4, 12)), 'easter');
    });

    test('Lent 2026 (Feb 18 - April 4)', () {
      // Ash Wednesday 2026 = Feb 18 (46 days before Easter April 5)
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 2, 18)), 'lent');
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 3, 15)), 'lent');
      // Holy Saturday = April 4
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 4, 4)), 'lent');
    });

    test('no season in summer', () {
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 7, 15)), isNull);
    });

    test('no season in October', () {
      expect(SeasonalCalendar.getCurrentSeason(DateTime(2026, 10, 10)), isNull);
    });
  });

  group('SeasonalCalendar.getSeasonalGreeting', () {
    test('returns greeting during Advent', () {
      final greeting = SeasonalCalendar.getSeasonalGreeting(DateTime(2026, 12, 10));
      expect(greeting, isNotNull);
      expect(greeting, contains('Advent'));
    });

    test('returns null when no season', () {
      expect(SeasonalCalendar.getSeasonalGreeting(DateTime(2026, 7, 15)), isNull);
    });
  });
}
