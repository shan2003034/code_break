import 'package:code_break/code_break.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;

  setUp(() => now = DateTime(2026, 10, 11, 9));

  ActivityMonitor monitor(WatchSettings settings) =>
      ActivityMonitor(settings, clock: () => now);

  test('stays quiet when nothing was saved', () {
    expect(monitor(const WatchSettings()).evaluate(), isNull);
  });

  test('fires "marathon" after continuous coding', () {
    final m = monitor(const WatchSettings(
      marathon: Duration(minutes: 30),
      idleReset: Duration(minutes: 5),
      burstSaves: 20,
    ));

    // A save every 4 minutes (never idle for 5) for 36 minutes.
    for (var i = 0; i < 9; i++) {
      m.recordSave();
      now = now.add(const Duration(minutes: 4));
    }

    expect(m.evaluate()?.reason, BreakReason.marathon);
  });

  test('does not fire before the marathon threshold', () {
    final m = monitor(const WatchSettings(marathon: Duration(minutes: 30)));
    for (var i = 0; i < 5; i++) {
      m.recordSave();
      now = now.add(const Duration(minutes: 4));
    }
    expect(m.evaluate(), isNull);
  });

  test('fires "frantic" on a burst of saves', () {
    final m = monitor(const WatchSettings(
      burstSaves: 5,
      burstWindow: Duration(seconds: 60),
    ));

    for (var i = 0; i < 5; i++) {
      m.recordSave();
      now = now.add(const Duration(seconds: 3));
    }

    expect(m.evaluate()?.reason, BreakReason.frantic);
  });

  test('old saves fall out of the burst window', () {
    final m = monitor(const WatchSettings(
      burstSaves: 5,
      burstWindow: Duration(seconds: 60),
    ));

    for (var i = 0; i < 5; i++) {
      m.recordSave();
      now = now.add(const Duration(seconds: 20)); // 100 s in total
    }

    expect(m.evaluate(), isNull);
  });

  test('a long pause resets the session', () {
    final m = monitor(const WatchSettings(
      marathon: Duration(minutes: 30),
      idleReset: Duration(minutes: 5),
    ));

    m.recordSave();
    now = now.add(const Duration(minutes: 6));

    expect(m.evaluate(), isNull);
    expect(m.sessionSaves, 0);
    expect(m.sessionLength, Duration.zero);
  });

  test('cooldown suppresses triggers until it ends', () {
    final m = monitor(const WatchSettings(
      burstSaves: 3,
      burstWindow: Duration(seconds: 60),
      cooldown: Duration(minutes: 10),
    ));

    m.startCooldown();
    for (var i = 0; i < 3; i++) {
      m.recordSave();
    }
    expect(m.evaluate(), isNull);

    now = now.add(const Duration(minutes: 11));
    for (var i = 0; i < 3; i++) {
      m.recordSave();
    }
    expect(m.evaluate()?.reason, BreakReason.frantic);
  });
}
