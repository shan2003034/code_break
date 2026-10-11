import 'dart:async';
import 'dart:convert';
import 'dart:io';


class ConsoleInput {
  ConsoleInput()
      : _lines = StreamIterator<String>(
          stdin.transform(utf8.decoder).transform(const LineSplitter()),
        );

  final StreamIterator<String> _lines;

  
  Future<String?> readLine(String prompt) async {
    stdout.write(prompt);
    final hasLine = await _lines.moveNext();
    return hasLine ? _lines.current : null;
  }

  Future<void> close() async {
    await _lines.cancel();
  }
}
