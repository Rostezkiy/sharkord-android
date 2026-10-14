import 'dart:convert';

/// an error the server or the transport produced, carrying the tRPC error code
/// where there is one so callers can branch on it instead of matching text.
class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'UNKNOWN'});

  final String message;
  final String code;

  bool get isUnauthorized => code == 'UNAUTHORIZED';
  bool get isForbidden => code == 'FORBIDDEN';
  bool get isNotFound => code == 'NOT_FOUND';
  bool get isRateLimited => code == 'TOO_MANY_REQUESTS';
  bool get isConnectionProblem =>
      code == 'CLOSED' || code == 'TIMEOUT' || code == 'UNKNOWN';

  /// the wire shape is `{"message":"...","code":-32003,"data":{"code":"FORBIDDEN"}}`,
  /// so the string code the routes use lives one level down from the numeric one.
  factory ApiException.fromTrpcError(Object? error) {
    final json = error is Map ? error.cast<String, dynamic>() : null;
    if (json == null) {
      return ApiException(error?.toString() ?? 'Unknown server error');
    }

    final data = json['data'];
    final dataMap = data is Map ? data.cast<String, dynamic>() : null;
    final code = dataMap?['code']?.toString() ?? json['code']?.toString();

    return ApiException(
      unwrapMessage(json['message']),
      code: code ?? 'UNKNOWN',
    );
  }

  /// a validation failure arrives as the zod issue list serialized into the
  /// message, which is unreadable as-is
  static String unwrapMessage(Object? message) {
    if (message is! String || message.isEmpty) return 'Unknown server error';

    if (message.startsWith('[')) {
      try {
        final issues = jsonDecode(message);
        if (issues is List) {
          final messages = issues
              .whereType<Map>()
              .map((issue) => issue['message'])
              .whereType<String>()
              .toList();

          if (messages.isNotEmpty) return messages.join('\n');
        }
      } on FormatException {
        return message;
      }
    }

    return message;
  }

  @override
  String toString() => message;
}

/// thrown by `GET /info` and `POST /login`, which answer with a
/// `field -> message` map instead of the tRPC error envelope.
class RestException implements Exception {
  const RestException(
    this.message, {
    this.statusCode = 0,
    this.fieldErrors = const <String, String>{},
  });

  final String message;
  final int statusCode;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}
