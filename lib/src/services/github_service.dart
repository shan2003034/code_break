import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors.dart';
import '../utils/http_utils.dart';
import '../utils/readme_streak.dart';

/// The profile README as stored on GitHub.
class ProfileReadme {
  const ProfileReadme({
    required this.path,
    required this.sha,
    required this.content,
  });

  /// File path inside the repo, usually `README.md`.
  final String path;

  /// Blob SHA, required by GitHub to update an existing file safely.
  final String sha;

  /// Decoded UTF-8 text.
  final String content;
}

/// Outcome of [GitHubService.recordTouchGrass].
class StreakCommit {
  const StreakCommit({required this.owner, required this.update});

  final String owner;
  final StreakUpdate update;

  String get profileUrl => 'https://github.com/$owner/$owner';
}

/// Minimal GitHub REST client for the "profile README streak" feature.
///
/// Authenticates with a Personal Access Token, reads `<user>/<user>/README`,
/// bumps the streak counter and commits the new file through the Contents API
/// (a normal commit on the default branch, no local git needed).
class GitHubService {
  GitHubService({
    required this.token,
    this.username,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String _apiHost = 'api.github.com';

  final String token;

  /// Optional. When empty, the login is looked up from the token.
  final String? username;

  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'code-break-cli',
      };

  /// The GitHub login to use: [username] if set, otherwise `GET /user`.
  Future<String> resolveLogin() async {
    final configured = username;
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    final res = await _send(
      () => _client.get(Uri.https(_apiHost, '/user'), headers: _headers),
    );
    final login = _decodeObject(res)['login'];
    if (login is! String || login.isEmpty) {
      throw ServiceException('GitHub did not return your username.');
    }
    return login;
  }

  /// Fetches and decodes `<owner>/<owner>`'s README.
  Future<ProfileReadme> fetchProfileReadme(String owner) async {
    final res = await _send(
      () => _client.get(
        Uri.https(_apiHost, '/repos/$owner/$owner/readme'),
        headers: _headers,
      ),
      notFoundHint: 'Could not find the README of "$owner/$owner". Create a '
          'public repository named exactly "$owner" containing a README.md '
          '(your GitHub profile README) and make sure the token can access it.',
    );

    final json = _decodeObject(res);
    final path = json['path'];
    final sha = json['sha'];
    final content = json['content'];
    if (path is! String || sha is! String || content is! String) {
      throw ServiceException(
          'Unexpected response while reading the profile README.');
    }
    if (json['encoding'] != 'base64') {
      throw ServiceException(
          'Unsupported README encoding: ${json['encoding']}.');
    }

    // GitHub wraps the base64 text at 60 columns, so strip whitespace first.
    final bytes =
        base64.decode(base64.normalize(content.replaceAll(RegExp(r'\s'), '')));
    return ProfileReadme(path: path, sha: sha, content: utf8.decode(bytes));
  }

  /// Counts one Touch Grass break: fetch README -> bump streak -> commit.
  ///
  /// Retries once if somebody pushed to the README in the meantime. When today
  /// was already counted nothing is committed.
  Future<StreakCommit> recordTouchGrass({DateTime? now}) async {
    final owner = await resolveLogin();
    final stamp = now ?? DateTime.now();

    for (var attempt = 1;; attempt++) {
      final readme = await fetchProfileReadme(owner);
      final update = ReadmeStreak.apply(readme.content, stamp);
      if (update.outcome == StreakOutcome.alreadyCounted) {
        return StreakCommit(owner: owner, update: update);
      }

      try {
        await _commit(
          owner,
          readme,
          update.content,
          'Touch Grass 🌱 streak: ${update.streak} '
          '${update.streak == 1 ? 'day' : 'days'}',
        );
        return StreakCommit(owner: owner, update: update);
      } on GitHubConflictException {
        if (attempt >= 2) {
          rethrow;
        }
        // README changed under us: loop to refetch the new SHA and retry.
      }
    }
  }

  void dispose() => _client.close();

  // ---------------------------------------------------------------------------

  Future<void> _commit(
    String owner,
    ProfileReadme readme,
    String newContent,
    String message,
  ) async {
    final uri =
        Uri.https(_apiHost, '/repos/$owner/$owner/contents/${readme.path}');
    await _send(
      () => _client.put(
        uri,
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'content': base64.encode(utf8.encode(newContent)),
          'sha': readme.sha,
        }),
      ),
      notFoundHint: 'GitHub returned 404 while saving the README. The token '
          'needs write access ("Contents: Read and write") to "$owner/$owner".',
    );
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    String? notFoundHint,
  }) async {
    final res = await guardedRequest(request, service: 'the GitHub API');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res;
    }
    throw _errorFor(res, notFoundHint: notFoundHint);
  }

  ServiceException _errorFor(http.Response res, {String? notFoundHint}) {
    var detail = '';
    final raw = utf8.decode(res.bodyBytes, allowMalformed: true);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['message'] is String) {
        detail = decoded['message'] as String;
      }
    } on FormatException {
      detail = shorten(raw, 120);
    }

    switch (res.statusCode) {
      case 401:
        return ServiceException('GitHub rejected the token (HTTP 401). Check '
            'GITHUB_TOKEN - it may be mistyped, revoked or expired.');
      case 403:
        if (res.headers['x-ratelimit-remaining'] == '0') {
          return ServiceException(
              'GitHub rate limit reached. Try again in a few minutes.');
        }
        return ServiceException('GitHub refused the request (HTTP 403: '
            '$detail). The token needs write access to repository contents.');
      case 404:
        return ServiceException(
            notFoundHint ?? 'GitHub returned 404 ($detail).');
      case 409:
        return GitHubConflictException(
            'The README changed on GitHub while updating it (HTTP 409).');
      default:
        return ServiceException(
            'GitHub returned HTTP ${res.statusCode}: $detail');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Handled below.
    }
    throw ServiceException('GitHub returned an unexpected response.');
  }
}
