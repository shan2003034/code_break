import 'dart:io';
import 'package:path/path.dart' as p;
import 'errors.dart';

class Config {
  Config._({
    required this.groqApiKey,
    required this.elevenLabsApiKey,
    required this.elevenLabsVoiceId,
    required this.elevenLabsModelId,
    required this.githubToken,
    required this.githubUsername,
    required this.loadedFrom,
  });

  factory Config.fromReader(
    String? Function(String key) read, {
    String? loadedFrom,
  }) {
    return Config._(
      groqApiKey: read('GROQ_API_KEY') ?? '',
      elevenLabsApiKey: read('ELEVENLABS_API_KEY'),
      elevenLabsVoiceId: read('ELEVENLABS_VOICE_ID') ?? '21m00Tcm4TlvDq8ikWAM',
      elevenLabsModelId: read('ELEVENLABS_MODEL_ID') ?? 'eleven_multilingual_v2',
      githubToken: read('GITHUB_TOKEN'),
      githubUsername: read('GITHUB_USERNAME'),
      loadedFrom: loadedFrom,
    );
  }

  static Config load({String? envFilePath}) {
    var fileVars = <String, String>{};
    String? loadedFrom;

    if (envFilePath != null) {
      final file = File(envFilePath);
      if (!file.existsSync()) {
        throw ConfigException('Env file not found: $envFilePath');
      }
      fileVars = parseEnv(file.readAsStringSync());
      loadedFrom = p.absolute(envFilePath);
    } else {
      for (final candidate in _candidateEnvFiles()) {
        final file = File(candidate);
        if (file.existsSync()) {
          fileVars = parseEnv(file.readAsStringSync());
          loadedFrom = candidate;
          break;
        }
      }
    }

    String? read(String key) {
      final fromEnv = _clean(Platform.environment[key]);
      if (fromEnv != null) {
        return fromEnv;
      }
      return _clean(fileVars[key]);
    }

    return Config.fromReader(read, loadedFrom: loadedFrom);
  }

  final String groqApiKey;
  final String? elevenLabsApiKey;
  final String elevenLabsVoiceId;
  final String elevenLabsModelId;
  final String? githubToken;
  final String? githubUsername;
  final String? loadedFrom;

  bool get hasElevenLabs => elevenLabsApiKey != null;
  bool get hasGitHub => githubToken != null;

  static Map<String, String> parseEnv(String contents) {
    final result = <String, String>{};
    final text = contents.startsWith('\uFEFF') ? contents.substring(1) : contents;

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trimLeft();
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();

      final quoted = value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")));
      if (quoted) {
        value = value.substring(1, value.length - 1);
      } else {
        final comment = value.indexOf(' #');
        if (comment != -1) value = value.substring(0, comment).trimRight();
      }
      result[key] = value;
    }
    return result;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed.startsWith('your_')) return null;
    return trimmed;
  }

  static List<String> _candidateEnvFiles() {
    final files = <String>[p.join(Directory.current.path, '.env')];
    final exe = Platform.resolvedExecutable;
    final exeName = p.basenameWithoutExtension(exe).toLowerCase();
    if (exeName != 'dart' && exeName != 'dartaotruntime') {
      files.add(p.join(p.dirname(exe), '.env'));
    }
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      files.add(p.join(home, '.code_break.env'));
    }
    return files;
  }
}