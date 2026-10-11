import 'dart:io';

/// Tiny dependency-free terminal logger.
///
/// Colours are switched off automatically when the output is not a real
/// terminal (for example when piped to a file).
class Log {
  Log._();

  /// Enables [debug] output (`--verbose`).
  static bool verbose = false;

  static final bool _ansi = _detectAnsi();

  static bool _detectAnsi() {
    try {
      return stdout.hasTerminal && stdout.supportsAnsiEscapes;
    } on Object {
      return false;
    }
  }

  static String _wrap(String code, String text) =>
      _ansi ? '\x1B[${code}m$text\x1B[0m' : text;

  static String bold(String text) => _wrap('1', text);
  static String dim(String text) => _wrap('2', text);
  static String red(String text) => _wrap('31', text);
  static String green(String text) => _wrap('32', text);
  static String yellow(String text) => _wrap('33', text);
  static String cyan(String text) => _wrap('36', text);

  static void line([String message = '']) => stdout.writeln(message);

  static void info(String message) => stdout.writeln('${cyan('i')} $message');

  static void success(String message) =>
      stdout.writeln('${green('✔')} $message');

  static void warn(String message) => stdout.writeln('${yellow('!')} $message');

  static void error(String message) => stderr.writeln('${red('✖')} $message');

  static void debug(String message) {
    if (verbose) {
      stdout.writeln(dim('· $message'));
    }
  }
}
