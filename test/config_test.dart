import 'package:code_break/code_break.dart';
import 'package:test/test.dart';

void main() {
  group('Config.parseEnv', () {
    test('parses keys, comments, quotes and export prefixes', () {
      final vars = Config.parseEnv('''
# comment
GITHUB_TOKEN=abc123
export GROQ_API_KEY="test_key"
ELEVENLABS_API_KEY='k e y'
EMPTY=
INLINE=value # trailing comment
no equals sign here
''');

      expect(vars['GITHUB_TOKEN'], 'abc123');
      expect(vars['GROQ_API_KEY'], 'test_key');
      expect(vars['ELEVENLABS_API_KEY'], 'k e y');
      expect(vars['EMPTY'], '');
      expect(vars['INLINE'], 'value');
      expect(vars.containsKey('no equals sign here'), isFalse);
    });

    test('handles Windows line endings and a BOM', () {
      final vars = Config.parseEnv('\uFEFFA=1\r\nB=2\r\n');
      expect(vars, {'A': '1', 'B': '2'});
    });
  });

  group('Config.fromReader', () {
    test('applies defaults and treats placeholders as unset', () {
      final config = Config.fromReader((_) => null);
      expect(config.groqApiKey, '');
      expect(config.elevenLabsVoiceId, '21m00Tcm4TlvDq8ikWAM');
      expect(config.hasGitHub, isFalse);
      expect(config.hasElevenLabs, isFalse);
    });
  });
}