import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../utils/logger.dart';


class DirectoryActivityWatcher {
  DirectoryActivityWatcher({
    required this.directory,
    required this.onSave,
    this.debounce = const Duration(milliseconds: 750),
  });

  /// Absolute path of the directory being watched.
  final String directory;

  /// Called with the changed path (relative to [directory]).
  final void Function(String relativePath) onSave;

  /// Events for the same file closer together than this count as one save.
  final Duration debounce;

  /// While `true` (during a break) events are ignored.
  bool paused = false;

  StreamSubscription<WatchEvent>? _subscription;
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  static const Set<String> _ignoredDirectories = {
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    '.gradle',
    '.next',
    '.venv',
    '__pycache__',
    'build',
    'dist',
    'node_modules',
    'Pods',
    'target',
    'venv',
  };

  static const Set<String> _ignoredFileNames = {'.DS_Store', 'Thumbs.db'};

  static const List<String> _ignoredSuffixes = [
    '~',
    '.swp',
    '.swx',
    '.tmp',
    '.crdownload',
  ];

  /// Starts watching. Completes once the watcher is ready to receive events.
  Future<void> start() async {
    final watcher = DirectoryWatcher(directory);
    _subscription = watcher.events.listen(
      _handle,
      onError: (Object error) => Log.warn('File watcher error: $error'),
    );
    await watcher.ready;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _handle(WatchEvent event) {
    if (paused || event.type == ChangeType.REMOVE) {
      return;
    }

    final relative = p.relative(event.path, from: directory);
    if (_isIgnored(relative)) {
      return;
    }

    final now = DateTime.now();
    final previous = _lastSeen[relative];
    if (previous != null && now.difference(previous) < debounce) {
      return;
    }
    _lastSeen[relative] = now;

    // Keep the map from growing forever in very busy trees.
    if (_lastSeen.length > 2000) {
      _lastSeen.removeWhere(
          (_, seen) => now.difference(seen) > const Duration(minutes: 1));
    }

    onSave(relative);
  }

  bool _isIgnored(String relativePath) {
    final parts = p.split(relativePath);
    if (parts.any(_ignoredDirectories.contains)) {
      return true;
    }
    final name = parts.isEmpty ? relativePath : parts.last;
    if (_ignoredFileNames.contains(name)) {
      return true;
    }
    return _ignoredSuffixes.any(name.endsWith);
  }
}
