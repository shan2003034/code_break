/// Raised when an external piece (Ollama, ElevenLabs, GitHub, the audio
/// player) fails in a way the developer can act on.
///
/// [message] is always safe to print: it never contains API keys or tokens.
class ServiceException implements Exception {
  ServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Raised for missing or invalid configuration (e.g. an unreadable .env path).
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// GitHub refused a commit because the README changed while we were
/// preparing our update (stale blob SHA). Callers may refetch and retry.
class GitHubConflictException extends ServiceException {
  GitHubConflictException(super.message);
}
