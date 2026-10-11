import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:code_break/code_break.dart';

/// Exit codes follow sysexits.h: 64 = usage error, 78 = configuration error.
Future<void> main(List<String> arguments) async {
  try {
    // Make sure emoji survive on Windows terminals that default to a legacy
    // code page.
    stdout.encoding = utf8;
  } on Object {
    // Not every terminal allows changing the encoding. Ignore.
  }

  final runner = CommandRunner<int>(
    'code_break',
    'Code-Break 🌱 - watches your coding and sends you outside to touch grass.',
  )
    ..addCommand(WatchCommand())
    ..addCommand(BreakNowCommand())
    ..addCommand(DoctorCommand());

  runner.argParser
    ..addOption('env-file',
        valueHelp: 'path', help: 'Load settings from this .env file.')
    ..addFlag('verbose',
        abbr: 'v', negatable: false, help: 'Print debug output.');

  // No arguments: start watching the current directory.
  final args = arguments.isEmpty ? const ['watch'] : arguments;

  int code;
  try {
    code = await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    code = 64;
  } on ConfigException catch (e) {
    Log.error(e.message);
    code = 78;
  } on ServiceException catch (e) {
    Log.error(e.message);
    code = 1;
  }

  // Exit explicitly: the stdin subscription would otherwise keep the process
  // alive after the command finished.
  exit(code);
}
