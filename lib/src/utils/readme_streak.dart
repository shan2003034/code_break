/// What happened to the streak counter when we processed the README.
enum StreakOutcome {
  /// No counter existed, a new "Touch Grass" section was appended.
  started,

  /// The counter went up by one.
  incremented,

  /// The developer missed at least one day, so the counter restarted at 1.
  reset,

  /// Today was already counted, the README is left untouched.
  alreadyCounted,
}

/// Result of [ReadmeStreak.apply].
class StreakUpdate {
  const StreakUpdate({
    required this.content,
    required this.streak,
    required this.outcome,
  });

  /// The full README text to commit (identical to the input when
  /// [outcome] is [StreakOutcome.alreadyCounted]).
  final String content;

  /// The streak value after processing.
  final int streak;

  final StreakOutcome outcome;
}


class ReadmeStreak {
  ReadmeStreak._();

  static final RegExp _pattern = RegExp(
    r'Touch Grass\s*🌱\s*Streak:\s*(\d+)\s*Days?'
    r'(?:[ \t]*<!--\s*touch-grass:last=(\d{4}-\d{2}-\d{2})\s*-->)?',
    caseSensitive: false,
  );

  /// Canonical text of the counter line for [streak] counted on [day].
  static String format(int streak, DateTime day) =>
      'Touch Grass 🌱 Streak: $streak ${streak == 1 ? 'Day' : 'Days'} '
      '<!-- touch-grass:last=${_ymd(day)} -->';

  /// Reads the current streak from [readme], or `null` if there is none.
  static int? currentStreak(String readme) {
    final match = _pattern.firstMatch(readme);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Returns the README after counting a Touch Grass break on [now].
  static StreakUpdate apply(String readme, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final match = _pattern.firstMatch(readme);

    // No counter yet: append a fresh section.
    if (match == null) {
      final separator =
          readme.isEmpty ? '' : (readme.endsWith('\n') ? '\n' : '\n\n');
      final block = '## 🌱 Touch Grass\n\n${format(1, today)}\n';
      return StreakUpdate(
        content: '$readme$separator$block',
        streak: 1,
        outcome: StreakOutcome.started,
      );
    }

    final current = int.tryParse(match.group(1)!) ?? 0;
    final lastRaw = match.group(2);
    final last = lastRaw == null ? null : _parseYmd(lastRaw);

    int next;
    StreakOutcome outcome;
    if (last == null) {
      // Plain-text counter without a marker: just increment.
      next = current + 1;
      outcome = StreakOutcome.incremented;
    } else {
      final gap = _daysBetween(last, today);
      if (gap <= 0) {
        return StreakUpdate(
          content: readme,
          streak: current,
          outcome: StreakOutcome.alreadyCounted,
        );
      } else if (gap == 1) {
        next = current + 1;
        outcome = StreakOutcome.incremented;
      } else {
        next = 1;
        outcome = StreakOutcome.reset;
      }
    }

    return StreakUpdate(
      content: readme.replaceRange(match.start, match.end, format(next, today)),
      streak: next,
      outcome: outcome,
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime _parseYmd(String s) {
    final parts = s.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  /// Whole calendar days from [a] to [b] (DST-safe because it uses UTC dates).
  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;
}
