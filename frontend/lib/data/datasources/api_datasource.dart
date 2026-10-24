import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sketchduel_app/core/constants/app_constants.dart';

/// Returns the current access token (or null when signed out).
/// With [forceRefresh] it should obtain a fresh token first.
typedef TokenProvider = Future<String?> Function({bool forceRefresh});

/// An error answer from the SketchDuel API, or a failure to reach it.
///
/// [toString] returns only the human-readable [message], so it can go straight into a SnackBar.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  /// HTTP status, or 0 when the server could not be reached at all.
  final int statusCode;
  final String message;

  bool get isNetworkError => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => message;
}

class ApiDatasource {
  ApiDatasource({
    http.Client? client,
    String? baseUrl,
    TokenProvider? tokenProvider,
    Duration timeout = const Duration(seconds: 20),
  })  : _client = client ?? _sharedClient,
        _base = baseUrl ?? AppConstants.baseUrl,
        _tokenProvider = tokenProvider,
        _timeout = timeout;

  static final http.Client _sharedClient = http.Client();

  final http.Client _client;
  final String _base;
  final TokenProvider? _tokenProvider;
  final Duration _timeout;

  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? query,
    Duration? timeout,
  }) {
    return _send('GET', endpoint, query: query, timeout: timeout);
  }

  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final data = await _send('POST', endpoint, body: body, timeout: timeout);
    if (data is! Map) {
      throw const ApiException(200, 'The server sent an unexpected answer.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<dynamic> _send(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    var uri = Uri.parse('$_base$endpoint');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    var response = await _request(method, uri, body, timeout, false);

    // An expired token: get a fresh one and try exactly once more.
    if (response.statusCode == 401 && _tokenProvider != null) {
      response = await _request(method, uri, body, timeout, true);
    }
    return _decode(response);
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
    Duration? timeout,
    bool forceRefresh,
  ) async {
    final token = await _tokenProvider?.call(forceRefresh: forceRefresh);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (method != 'GET') 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    try {
      final Future<http.Response> pending = method == 'GET'
          ? _client.get(uri, headers: headers)
          : _client.post(
              uri,
              headers: headers,
              body: jsonEncode(body ?? <String, dynamic>{}),
            );
      return await pending.timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw const ApiException(
        0,
        'The server took too long to answer. Please try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        0,
        'Cannot reach the server. Check your connection and try again.',
      );
    }
  }

  dynamic _decode(http.Response response) {
    final status = response.statusCode;

    dynamic parsed;
    if (response.body.isNotEmpty) {
      try {
        parsed = jsonDecode(response.body);
      } on FormatException {
        parsed = null; // e.g. an HTML error page from a proxy
      }
    }

    if (status >= 200 && status < 300) {
      if (parsed == null) {
        throw ApiException(status, 'The server sent an unreadable answer.');
      }
      return parsed;
    }
    throw ApiException(status, errorMessage(status, parsed));
  }

  /// Turns an error response into a short message a player can read.
  static String errorMessage(int status, dynamic body) {
    if (status == 401) {
      return 'Your session has expired. Please log in again.';
    }

    if (body is Map && body['detail'] != null) {
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) {
        return detail;
      }
      if (detail is List && detail.isNotEmpty) {
        final parts = <String>[];
        for (final item in detail) {
          if (item is Map && item['msg'] != null) {
            final loc = item['loc'];
            final field = (loc is List && loc.isNotEmpty) ? '${loc.last}' : '';
            parts.add(field.isEmpty ? '${item['msg']}' : '$field: ${item['msg']}');
          }
        }
        if (parts.isNotEmpty) return parts.join('\n');
      }
    }

    if (status == 429) return 'Too many requests. Please wait a moment.';
    if (status == 413) return 'That drawing is too large to send.';
    if (status >= 500) {
      return 'The server had a problem (error $status). Please try again.';
    }
    return 'Request failed (error $status).';
  }
}