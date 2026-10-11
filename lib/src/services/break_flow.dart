import '../config.dart';
import '../errors.dart';
import '../utils/console_input.dart';
import '../utils/logger.dart';
import '../utils/readme_streak.dart';
import 'activity_monitor.dart';
import 'audio_service.dart';
import 'elevenlabs_service.dart';
import 'github_service.dart';
import 'groq_service.dart';

enum BreakOutcome { completed, skipped }

class BreakFlow {
  BreakFlow({
    required this.groq,
    required this.input,
    this.elevenLabs,
    this.github,
    AudioService? audio,
    this.maxAttempts = 3,
  }) : audio = audio ?? AudioService();

  factory BreakFlow.fromConfig(
    Config config, {
    required ConsoleInput input,
    bool voice = true,
  }) {
    final elevenKey = config.elevenLabsApiKey;
    final githubToken = config.githubToken;
    return BreakFlow(
      groq: GroqService(apiKey: config.groqApiKey),
      input: input,
      elevenLabs: voice && elevenKey != null
          ? ElevenLabsService(
              apiKey: elevenKey,
              voiceId: config.elevenLabsVoiceId,
              modelId: config.elevenLabsModelId,
            )
          : null,
      github: githubToken != null
          ? GitHubService(token: githubToken, username: config.githubUsername)
          : null,
    );
  }

  final GroqService groq;
  final ElevenLabsService? elevenLabs;
  final GitHubService? github;
  final AudioService audio;
  final ConsoleInput input;
  final int maxAttempts;

  bool get voiceEnabled => elevenLabs != null;
  bool get streakEnabled => github != null;

  Future<BreakOutcome> run(BreakTrigger trigger) async {
    Log.line();
    Log.line(Log.bold(Log.green('🌱  T O U C H   G R A S S   T I M E  🌱')));
    Log.info('Why now: ${trigger.detail}.');

    final message = await _generateMessage(trigger);
    Log.line();
    Log.line('   ${Log.bold(message)}');
    Log.line();

    await _speak(message);
    return _challenge();
  }

  void dispose() {
    groq.dispose();
    elevenLabs?.dispose();
    github?.dispose();
  }

  Future<String> _generateMessage(BreakTrigger trigger) async {
    Log.info('Asking Gemma (${groq.model}) for a gentle nudge...');
    try {
      return await groq.generateBreakMessage(trigger);
    } on ServiceException catch (e) {
      Log.warn('${e.message}\n  Using a built-in message instead.');
      return groq.fallbackMessage();
    }
  }

  Future<void> _speak(String message) async {
    final voice = elevenLabs;
    if (voice == null) return;
    final spoken = message.replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]', unicode: true), '').trim();
    try {
      Log.info('🔊 Speaking...');
      final mp3 = await voice.synthesize(spoken);
      await audio.play(mp3);
    } on ServiceException catch (e) {
      Log.warn('Voice unavailable: ${e.message}');
    }
  }

  Future<BreakOutcome> _challenge() async {
    Log.line(Log.dim('Code-Break is paused. Go outside, then come back and tell me what you saw. (Type "skip" to snooze.)'));
    var rejected = 0;
    while (rejected < maxAttempts) {
      final line = await input.readLine(Log.bold('What unique thing did you see outside? '));
      if (line == null) return BreakOutcome.skipped;
      final answer = line.trim();
      if (answer.toLowerCase() == 'skip') return BreakOutcome.skipped;
      if (answer.length < 8) {
        Log.warn('Give me a bit more detail - a few words at least.');
        continue;
      }
      Log.info('Gemma is judging your observation...');
      final ObservationVerdict verdict;
      try {
        verdict = await groq.validateObservation(answer);
      } on ServiceException catch (e) {
        Log.error('Could not validate right now: ${e.message}');
        return BreakOutcome.skipped;
      }
      if (verdict.valid) {
        Log.success('Verified! ${verdict.reason}');
        await _awardStreak();
        return BreakOutcome.completed;
      }
      rejected++;
      Log.warn('Gemma is not convinced: ${verdict.reason}');
      if (rejected < maxAttempts) Log.line(Log.dim('Try again ($rejected/$maxAttempts) - be specific!'));
    }
    return BreakOutcome.skipped;
  }

  Future<void> _awardStreak() async {
    final client = github;
    if (client == null) return;
    try {
      Log.info('Updating your GitHub profile README...');
      final result = await client.recordTouchGrass();
      final days = result.update.streak;
      switch (result.update.outcome) {
        case StreakOutcome.started: Log.success('Streak started! Day 1 is now on your profile. 🌱');
        case StreakOutcome.incremented: Log.success('Streak is now $days ${days == 1 ? 'day' : 'days'}! 🔥');
        case StreakOutcome.reset: Log.warn('You missed a day, so the streak restarted - but today counts! 🌱');
        case StreakOutcome.alreadyCounted: Log.info('Today is already counted - streak stays at $days ${days == 1 ? 'day' : 'days'}.');
      }
      Log.info('Profile: ${result.profileUrl}');
    } on ServiceException catch (e) {
      Log.error('Could not update the streak: ${e.message}');
    }
  }
}