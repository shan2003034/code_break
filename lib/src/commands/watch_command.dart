import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import '../errors.dart';
import '../services/activity_monitor.dart';
import '../services/break_flow.dart';
import '../services/watcher_service.dart';
import '../utils/console_input.dart';
import '../utils/logger.dart';


class WatchCommand extends Command<int> {
  WatchCommand() {
    argParser
      ..addOption('dir',
          abbr: 'd',
          defaultsTo: '.',
          help: 'Directory to watch (recursively).')
      ..addOption('marathon',
          defaultsTo: '50',
          valueHelp: 'minutes',
          help: 'Continuous coding time that triggers a break.')
      ..addOption('idle-reset',
          defaultsTo: '5',
          valueHelp: 'minutes',
          help: 'Pause with no saves that counts as a real break.')
      ..addOption('burst-saves',
          defaultsTo: '20',
          valueHelp: 'count',
          help: 'Saves within the burst window that mean "stuck on a bug".')
      ..addOption('burst-window',
          defaultsTo: '120',
          valueHelp: 'seconds',
          help: 'Length of the burst window.')
      ..addOption('cooldown',
          defaultsTo: '20',
          valueHelp: 'minutes',
          help: 'Quiet time after a completed break.')
      ..addFlag('demo',
          negatable: false,
          help: 'Tiny thresholds (1 min marathon, 5 saves in 30 s) for demos.')
      ..addFlag('no-voice',
          negatable: false, help: 'Do not use ElevenLabs, even if a key is set.');
  }

  @override
  final String name = 'watch';

  @override
  final String description =
      'Watch a directory and interrupt you when you code for too long.';

  @override
  Future<int> run() async {
    final args = argResults!;
    Log.verbose = globalResults?['verbose'] as bool? ?? false;

    final config = Config.load(
      envFilePath: globalResults?['env-file'] as String?,
    );

    final directory = p.normalize(p.absolute(args['dir'] as String));
    if (!Directory(directory).existsSync()) {
      usageException('Directory does not exist: $directory');
    }

    final demo = args['demo'] as bool;
    final settings = demo
        ? WatchSettings.demo
        : WatchSettings(
            marathon: Duration(minutes: _positive(args, 'marathon')),
            idleReset: Duration(minutes: _positive(args, 'idle-reset')),
            burstSaves: _positive(args, 'burst-saves'),
            burstWindow: Duration(seconds: _positive(args, 'burst-window')),
            cooldown: Duration(minutes: _positive(args, 'cooldown')),
          );

    final input = ConsoleInput();
    final flow = BreakFlow.fromConfig(
      config,
      input: input,
      voice: !(args['no-voice'] as bool),
    );
    final monitor = ActivityMonitor(settings);

    _printBanner(directory, settings, config, flow);

    final watcher = DirectoryActivityWatcher(
      directory: directory,
      onSave: (path) {
        monitor.recordSave();
        Log.debug('save: $path (${monitor.sessionSaves} this session)');
      },
    );

    var breakRunning = false;
    Future<void> tick() async {
      if (breakRunning) {
        return;
      }
      final trigger = monitor.evaluate();
      if (trigger == null) {
        return;
      }

      breakRunning = true;
      watcher.paused = true; 
      try {
        final outcome = await flow.run(trigger);
        monitor.startCooldown(
          quiet: outcome == BreakOutcome.completed
              ? settings.cooldown
              : settings.snooze,
        );
        Log.line();
        Log.info('Back to watching. Happy coding!');
      } on Object {
        monitor.startCooldown(quiet: settings.snooze);
        rethrow;
      } finally {
        watcher.paused = false;
        breakRunning = false;
      }
    }

    await watcher.start();

    final timer = Timer.periodic(
      demo ? const Duration(seconds: 1) : const Duration(seconds: 5),
      (_) => unawaited(tick().catchError((Object e) {
        Log.error('Break failed: $e');
      })),
    );

    final stop = Completer<void>();
    final signals = <StreamSubscription<ProcessSignal>>[
      ProcessSignal.sigint.watch().listen((_) {
        if (!stop.isCompleted) {
          stop.complete();
        }
      }),
      if (!Platform.isWindows)
        ProcessSignal.sigterm.watch().listen((_) {
          if (!stop.isCompleted) {
            stop.complete();
          }
        }),
    ];
    await stop.future;

    Log.line();
    Log.info('Stopping Code-Break. Go touch some grass anyway. 🌱');
    timer.cancel();
    for (final sub in signals) {
      await sub.cancel();
    }
    await watcher.stop();
    flow.dispose();
    await input.close();
    return 0;
  }

  int _positive(ArgResults args, String option) {
    final value = int.tryParse(args[option] as String);
    if (value == null || value <= 0) {
      usageException('--$option must be a positive whole number.');
    }
    return value;
  }

  void _printBanner(
    String directory,
    WatchSettings settings,
    Config config,
    BreakFlow flow,
  ) {
    Log.line(Log.bold('🌱 Code-Break is watching ${Log.cyan(directory)}'));
    Log.line('   marathon: ${settings.marathon.inMinutes} min · '
        'burst: ${settings.burstSaves} saves / ${settings.burstWindow.inSeconds} s · '
        'cooldown: ${settings.cooldown.inMinutes} min');
    Log.line('   AI: Groq (gemma2-9b-it) · '
        'voice: ${flow.voiceEnabled ? 'on' : 'off'} · '
        'GitHub streak: ${flow.streakEnabled ? 'on' : 'off'}');
    final env = config.loadedFrom;
    Log.line(Log.dim(env == null
        ? '   (no .env file found - using environment variables only)'
        : '   config: $env'));
    Log.line(Log.dim('   Press Ctrl+C to stop.'));
    Log.line();
  }
}