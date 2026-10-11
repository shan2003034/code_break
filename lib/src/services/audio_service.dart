import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../errors.dart';

class _PlayerCommand {
  const _PlayerCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}


class AudioService {
  /// Plays and completes when playback has finished.
  Future<void> play(Uint8List mp3Bytes) async {
    final dir = await Directory.systemTemp.createTemp('code_break_');
    final file = File(p.join(dir.path, 'touch_grass.mp3'));
    try {
      await file.writeAsBytes(mp3Bytes, flush: true);
      await _playFile(file.path);
    } finally {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Temp-file cleanup is best effort.
      }
    }
  }

  Future<void> _playFile(String path) async {
    final candidates = await _candidates(path);
    if (candidates.isEmpty) {
      throw ServiceException(
          'No audio player found. On Linux install one of: mpv, ffmpeg '
          '(ffplay), mpg123, vlc or sox.');
    }

    String? lastProblem;
    for (final command in candidates) {
      try {
        final exitCode = await _run(command);
        if (exitCode == 0) {
          return;
        }
        lastProblem = '${command.executable} exited with code $exitCode';
      } on ProcessException catch (e) {
        lastProblem = e.message;
      }
    }
    throw ServiceException('Audio playback failed ($lastProblem).');
  }

  Future<List<_PlayerCommand>> _candidates(String path) async {
    if (Platform.isMacOS) {
      return [_PlayerCommand('afplay', [path])];
    }
    if (Platform.isWindows) {
      return [_windowsPowerShell(path)];
    }

    final linuxPlayers = <_PlayerCommand>[
      _PlayerCommand('mpv', ['--no-video', '--no-terminal', '--really-quiet', path]),
      _PlayerCommand('ffplay', ['-nodisp', '-autoexit', '-loglevel', 'quiet', path]),
      _PlayerCommand('mpg123', ['-q', path]),
      _PlayerCommand('cvlc', ['--play-and-exit', '--quiet', path]),
      _PlayerCommand('play', ['-q', path]),
    ];
    final available = <_PlayerCommand>[];
    for (final player in linuxPlayers) {
      if (await _commandExists(player.executable)) {
        available.add(player);
      }
    }
    return available;
  }

  /// Windows ships no CLI MP3 player, but PowerShell can drive the WPF
  /// MediaPlayer. The script is passed base64 (UTF-16LE) via -EncodedCommand so
  /// paths with spaces or quotes cannot break the command line.
  _PlayerCommand _windowsPowerShell(String path) {
    final uri = Uri.file(path).toString().replaceAll("'", "''");
    final script = '''
Add-Type -AssemblyName PresentationCore
\$player = New-Object System.Windows.Media.MediaPlayer
\$player.Open([System.Uri]'$uri')
\$tries = 0
while (-not \$player.NaturalDuration.HasTimeSpan -and \$tries -lt 100) { Start-Sleep -Milliseconds 100; \$tries++ }
\$player.Play()
if (\$player.NaturalDuration.HasTimeSpan) {
  Start-Sleep -Milliseconds ([int]\$player.NaturalDuration.TimeSpan.TotalMilliseconds + 400)
} else {
  Start-Sleep -Seconds 8
}
\$player.Close()
''';

    final utf16le = <int>[];
    for (final unit in script.codeUnits) {
      utf16le
        ..add(unit & 0xFF)
        ..add(unit >> 8);
    }
    return _PlayerCommand('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      base64.encode(utf16le),
    ]);
  }

  Future<bool> _commandExists(String executable) async {
    try {
      final result = await Process.run('which', [executable]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<int> _run(_PlayerCommand command) async {
    final process = await Process.start(command.executable, command.arguments);
    // Drain the pipes so a chatty player can never block on a full buffer.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return process.exitCode.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }
}
