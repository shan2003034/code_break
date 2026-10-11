import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../errors.dart';


Future<http.Response> guardedRequest(
  Future<http.Response> Function() send, {
  required String service,
  Duration timeout = const Duration(seconds: 30),
  String? hint,
}) async {
  final suffix = hint == null ? '' : ' $hint';
  try {
    return await send().timeout(timeout);
  } on TimeoutException {
    throw ServiceException(
        '$service did not answer within ${timeout.inSeconds}s.$suffix');
  } on SocketException catch (e) {
    throw ServiceException('Could not reach $service (${e.message}).$suffix');
  } on http.ClientException catch (e) {
    throw ServiceException(
        'Network error while talking to $service: ${e.message}.$suffix');
  }
}

/// Collapses whitespace and truncates [text] to at most [max] characters.
String shorten(String text, [int max = 200]) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}
