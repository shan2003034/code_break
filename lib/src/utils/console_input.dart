import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Asynchronous, line-based reader for stdin.
///
/// `stdin.readLineSync()` blocks the whole isolate, which would swallow Ctrl+C
/// handling and make the watcher unresponsive. This wrapper reads lines with a
/// [StreamIterator] instead, so signals keep working while we wait for the
/// developer to come back from outside.
///
/// Create exactly ONE instance per process: stdin can only be listened to once.
class ConsoleInput {
  ConsoleInput()
      : _lines = StreamIterator<String>(
          stdin.transform(utf8.decoder).transform(const LineSplitter()),
        );

  final StreamIterator<String> _lines;

  /// Prints [prompt] and waits for one line.
  ///
  /// Returns `null` when stdin is closed (e.g. piped input ended, Ctrl+D).
  Future<String?> readLine(String prompt) async {
    stdout.write(prompt);
    final hasLine = await _lines.moveNext();
    return hasLine ? _lines.current : null;
  }

  Future<void> close() async {
    await _lines.cancel();
  }
}
