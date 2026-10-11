/// Why a Touch Grass break was triggered.
enum BreakReason {
  /// Coding for a long, uninterrupted stretch.
  marathon,

  /// Furious repeated saves, typically someone stuck on a stubborn bug.
  frantic,
}

/// A fired trigger: the [reason] plus a human readable [detail] that is shown
/// in the terminal and given to Gemma as context.
class BreakTrigger {
  const BreakTrigger(this.reason, this.detail);

  final BreakReason reason;
  final String detail;
}

/// Thresholds that decide when a break is due.
class WatchSettings {
  const WatchSettings({
    this.marathon = const Duration(minutes: 50),
    this.idleReset = const Duration(minutes: 5),
    this.burstSaves = 20,
    this.burstWindow = const Duration(minutes: 2),
    this.cooldown = const Duration(minutes: 20),
    this.snooze = const Duration(minutes: 10),
  });

  /// Short thresholds so a demo (or video) does not take an hour.
  static const WatchSettings demo = WatchSettings(
    marathon: Duration(minutes: 1),
    idleReset: Duration(seconds: 30),
    burstSaves: 5,
    burstWindow: Duration(seconds: 30),
    cooldown: Duration(minutes: 1),
    snooze: Duration(seconds: 30),
  );

  /// A session this long without a real pause triggers a break.
  final Duration marathon;

  /// If no file was saved for this long the developer already took a break,
  /// so the current session is forgotten.
  final Duration idleReset;

  /// This many saves inside [burstWindow] counts as "stuck on a bug".
  final int burstSaves;
  final Duration burstWindow;

  /// Quiet period after a completed break.
  final Duration cooldown;

  /// Quiet period after the developer skipped a break.
  final Duration snooze;
}

/// Pure decision logic: feed it save events, ask it whether a break is due.
///
/// It has no timers or I/O of its own, and the clock is injectable, which
/// keeps it trivial to unit-test.
class ActivityMonitor {
  ActivityMonitor(this.settings, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final WatchSettings settings;
  final DateTime Function() _clock;

  DateTime? _sessionStart;
  DateTime? _lastSave;
  DateTime? _quietUntil;
  int _sessionSaves = 0;
  final List<DateTime> _recentSaves = <DateTime>[];

  /// Number of saves in the current session.
  int get sessionSaves => _sessionSaves;

  /// Length of the current coding session (zero when idle).
  Duration get sessionLength {
    final start = _sessionStart;
    return start == null ? Duration.zero : _clock().difference(start);
  }

  /// Registers one file save.
  void recordSave() {
    final now = _clock();
    _expireIdleSession(now);
    _sessionStart ??= now;
    _lastSave = now;
    _sessionSaves++;
    _recentSaves.add(now);
    _trimBurstWindow(now);
  }

  /// Returns a [BreakTrigger] when a break is due, otherwise `null`.
  BreakTrigger? evaluate() {
    final now = _clock();
    _expireIdleSession(now);

    final quietUntil = _quietUntil;
    if (quietUntil != null && now.isBefore(quietUntil)) {
      return null;
    }
    final start = _sessionStart;
    if (start == null) {
      return null;
    }

    _trimBurstWindow(now);
    if (_recentSaves.length >= settings.burstSaves) {
      return BreakTrigger(
        BreakReason.frantic,
        '${_recentSaves.length} saves in ${settings.burstWindow.inSeconds} '
        'seconds - looks like a stubborn bug',
      );
    }

    final length = now.difference(start);
    if (length >= settings.marathon) {
      return BreakTrigger(
        BreakReason.marathon,
        '${length.inMinutes} minutes of coding without a real break',
      );
    }
    return null;
  }

  /// Forgets the current session and stays quiet for [quiet]
  /// (defaults to [WatchSettings.cooldown]).
  void startCooldown({Duration? quiet}) {
    _resetSession();
    _quietUntil = _clock().add(quiet ?? settings.cooldown);
  }

  void _expireIdleSession(DateTime now) {
    final last = _lastSave;
    if (last != null && now.difference(last) >= settings.idleReset) {
      _resetSession();
    }
  }

  void _resetSession() {
    _sessionStart = null;
    _lastSave = null;
    _sessionSaves = 0;
    _recentSaves.clear();
  }

  void _trimBurstWindow(DateTime now) {
    _recentSaves.removeWhere((t) => now.difference(t) > settings.burstWindow);
  }
}
