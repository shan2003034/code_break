import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../errors.dart';
import '../utils/http_utils.dart';

/// Converts text to speech with the ElevenLabs Text-to-Speech REST API.
class ElevenLabsService {
  ElevenLabsService({
    required this.apiKey,
    required this.voiceId,
    required this.modelId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String _baseUrl = 'https://api.elevenlabs.io/v1';

  final String apiKey;
  final String voiceId;
  final String modelId;
  final http.Client _client;

  /// Returns the spoken [text] as MP3 bytes.
  Future<Uint8List> synthesize(String text) async {
    final uri = Uri.parse('$_baseUrl/text-to-speech/$voiceId')
        .replace(queryParameters: {'output_format': 'mp3_44100_128'});

    final res = await guardedRequest(
      () => _client.post(
        uri,
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': modelId,
          'voice_settings': {
            'stability': 0.4,
            'similarity_boost': 0.8,
            'style': 0.3,
            'use_speaker_boost': true,
          },
        }),
      ),
      service: 'ElevenLabs',
      timeout: const Duration(seconds: 45),
      hint: 'Check your internet connection.',
    );

    if (res.statusCode != 200) {
      throw ServiceException(_describeError(res));
    }
    if (res.bodyBytes.isEmpty) {
      throw ServiceException('ElevenLabs returned an empty audio stream.');
    }
    return res.bodyBytes;
  }

  void dispose() => _client.close();

  String _describeError(http.Response res) {
    var message = utf8.decode(res.bodyBytes, allowMalformed: true);
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic>) {
          message = (detail['message'] ?? detail['status'] ?? message)
              .toString();
        } else if (detail != null) {
          message = detail.toString();
        }
      }
    } on FormatException {
      // Not JSON: keep the raw body.
    }

    final hint = switch (res.statusCode) {
      401 => ' (check ELEVENLABS_API_KEY and its Text-to-Speech permission)',
      402 || 429 => ' (quota or rate limit reached)',
      404 => ' (check ELEVENLABS_VOICE_ID)',
      _ => '',
    };
    return 'ElevenLabs returned HTTP ${res.statusCode}: '
        '${shorten(message, 160)}$hint';
  }
}
