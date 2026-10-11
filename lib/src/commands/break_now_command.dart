import 'package:args/command_runner.dart';

import '../config.dart';
import '../services/activity_monitor.dart';
import '../services/break_flow.dart';
import '../utils/console_input.dart';
import '../utils/logger.dart';

/// `code_break break-now` - runs the Touch Grass flow immediately.
///
/// Perfect for demos and for testing your Ollama / ElevenLabs / GitHub setup
/// without waiting for a real marathon.
class BreakNowCommand extends Command<int> {
  BreakNowCommand() {
    argParser
      ..addOption('reason',
          allowed: ['marathon', 'frantic'],
          defaultsTo: 'marathon',
          help: 'Which kind of trigger to simulate.')
      ..addFlag('no-voice',
          negatable: false, help: 'Do not use ElevenLabs, even if a key is set.');
  }

  @override
  final String name = 'break-now';

  @override
  final String description =
      'Trigger a Touch Grass break right now (demo / setup test).';

  @override
  Future<int> run() async {
    final args = argResults!;
    Log.verbose = globalResults?['verbose'] as bool? ?? false;

    final config = Config.load(
      envFilePath: globalResults?['env-file'] as String?,
    );
    final input = ConsoleInput();
    final flow = BreakFlow.fromConfig(
      config,
      input: input,
      voice: !(args['no-voice'] as bool),
    );

    try {
      final frantic = args['reason'] == 'frantic';
      final trigger = frantic
          ? const BreakTrigger(
              BreakReason.frantic, '32 saves in 60 seconds (simulated)')
          : const BreakTrigger(
              BreakReason.marathon, '75 minutes of coding without a break '
                  '(simulated)');
      await flow.run(trigger);
      return 0;
    } finally {
      flow.dispose();
      await input.close();
    }
  }
}
