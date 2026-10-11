import 'package:args/command_runner.dart';

import '../config.dart';
import '../errors.dart';
import '../services/github_service.dart';
import '../services/groq_service.dart'; // Ollama වෙනුවට Groq යොදා ඇත
import '../utils/logger.dart';
import '../utils/readme_streak.dart';

/// `code_break doctor` - checks every integration and says how to fix it.
class DoctorCommand extends Command<int> {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Check Groq, ElevenLabs and GitHub configuration.';

  @override
  Future<int> run() async {
    Log.verbose = globalResults?['verbose'] as bool? ?? false;
    final config = Config.load(
      envFilePath: globalResults?['env-file'] as String?,
    );
    var problems = 0;

    Log.line(Log.bold('Code-Break doctor'));
    final env = config.loadedFrom;
    Log.line(env == null
        ? Log.dim('config: no .env file found, using environment variables')
        : Log.dim('config: $env'));
    Log.line();

    // -- Groq (Replace Ollama section) ----------------------------------------
    if (config.groqApiKey.isEmpty) {
      Log.warn('GROQ_API_KEY not set - breaks will use built-in messages.');
      problems++;
    } else {
      Log.success('Groq API Key found (model: gemma2-9b-it).');
    }

    // -- ElevenLabs -----------------------------------------------------------
    if (config.hasElevenLabs) {
      Log.success('ElevenLabs key found (voice ${config.elevenLabsVoiceId}, '
          'model ${config.elevenLabsModelId}). It is verified on first use.');
    } else {
      Log.warn('ELEVENLABS_API_KEY not set - breaks will be silent.');
    }

    // -- GitHub ---------------------------------------------------------------
    final token = config.githubToken;
    if (token == null) {
      Log.warn('GITHUB_TOKEN not set - the profile streak is disabled.');
    } else {
      final github =
          GitHubService(token: token, username: config.githubUsername);
      try {
        final login = await github.resolveLogin();
        final readme = await github.fetchProfileReadme(login);
        final streak = _currentStreak(readme);
        Log.success('GitHub OK: $login/$login/${readme.path} is readable'
            '${streak == null ? ' (no streak counter yet)' : ' (streak: $streak)'}.');
        Log.line(Log.dim('  Write access is checked when the first streak is '
            'saved.'));
      } on ServiceException catch (e) {
        problems++;
        Log.error(e.message);
      } finally {
        github.dispose();
      }
    }

    Log.line();
    if (problems == 0) {
      Log.success('Everything required is ready. Try: code_break break-now');
    } else {
      Log.warn('$problems problem(s) found - see the messages above.');
    }
    return problems == 0 ? 0 : 1;
  }

  int? _currentStreak(ProfileReadme readme) =>
      ReadmeStreak.currentStreak(readme.content);
}