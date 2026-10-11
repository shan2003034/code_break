import 'package:code_break/code_break.dart';
import 'package:test/test.dart';

void main() {
  group('ReadmeStreak.apply', () {
    test('appends a new section when the README has no counter', () {
      final result = ReadmeStreak.apply('# Hi there\n', DateTime(2026, 10, 11));

      expect(result.outcome, StreakOutcome.started);
      expect(result.streak, 1);
      expect(result.content, startsWith('# Hi there\n'));
      expect(
        result.content,
        contains(
            'Touch Grass 🌱 Streak: 1 Day <!-- touch-grass:last=2026-10-11 -->'),
      );
    });

    test('works on an empty README', () {
      final result = ReadmeStreak.apply('', DateTime(2026, 10, 11));
      expect(result.streak, 1);
      expect(result.content, startsWith('## 🌱 Touch Grass'));
    });

    test('increments a plain-text counter without a date marker', () {
      final result = ReadmeStreak.apply(
        'About me\n\nTouch Grass 🌱 Streak: 4 Days\n\nBye',
        DateTime(2026, 10, 11),
      );

      expect(result.outcome, StreakOutcome.incremented);
      expect(result.streak, 5);
      expect(result.content, contains('Streak: 5 Days <!-- touch-grass'));
      expect(result.content, startsWith('About me\n\n'));
      expect(result.content, endsWith('\n\nBye'));
    });

    test('increments when the last counted day was yesterday', () {
      const readme =
          'Touch Grass 🌱 Streak: 7 Days <!-- touch-grass:last=2026-10-10 -->';
      final result = ReadmeStreak.apply(readme, DateTime(2026, 10, 11, 18, 30));

      expect(result.outcome, StreakOutcome.incremented);
      expect(result.streak, 8);
      expect(result.content, contains('last=2026-10-11'));
    });

    test('resets to 1 after a missed day', () {
      const readme =
          'Touch Grass 🌱 Streak: 7 Days <!-- touch-grass:last=2026-10-08 -->';
      final result = ReadmeStreak.apply(readme, DateTime(2026, 10, 11));

      expect(result.outcome, StreakOutcome.reset);
      expect(result.streak, 1);
      expect(result.content, contains('Streak: 1 Day <!--'));
    });

    test('does not count the same day twice', () {
      const readme =
          'Touch Grass 🌱 Streak: 7 Days <!-- touch-grass:last=2026-10-11 -->';
      final result = ReadmeStreak.apply(readme, DateTime(2026, 10, 11, 23));

      expect(result.outcome, StreakOutcome.alreadyCounted);
      expect(result.streak, 7);
      expect(result.content, readme);
    });

    test('keeps counting across consecutive days', () {
      var readme = '# Profile\n';
      for (var day = 1; day <= 5; day++) {
        readme = ReadmeStreak.apply(readme, DateTime(2026, 10, day)).content;
      }
      expect(ReadmeStreak.currentStreak(readme), 5);
    });
  });
}
