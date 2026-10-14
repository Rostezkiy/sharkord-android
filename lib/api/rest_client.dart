import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/server_info.dart';
import 'api_exception.dart';
import 'server_endpoint.dart';

/// the two endpoints that cannot go over tRPC because they run before the user
/// has a session: the server card shown on the connect screen, and the login
/// that mints the token everything else is authenticated with.
class RestClient {
  RestClient(this.endpoint, {http.Client? client})
    : _client = client ?? http.Client();

  final ServerEndpoint endpoint;
  final http.Client _client;

  Future<ServerInfo> fetchInfo() async {
    final response = await _get('/info');

    return ServerInfo.fromJson(_decode(response));
  }

  Future<String> login({
    required String identity,
    required String password,
    String? invite,
  }) async {
    final response = await _post('/login', <String, Object?>{
      'identity': identity,
      'password': password,
      if (invite != null && invite.isNotEmpty) 'invite': invite,
    });

    final json = _decode(response);

    if (json['token'] is String) return json['token'] as String;

    throw RestException(
      'The server did not return a session token',
      statusCode: response.statusCode,
    );
  }

  void close() => _client.close();

  Future<http.Response> _get(String path) async {
    try {
      return await _client
          .get(endpoint.resolve(path))
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw RestException(_networkMessage(error));
    }
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    try {
      return await _client
          .post(
            endpoint.resolve(path),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw RestException(_networkMessage(error));
    }
  }

  String _networkMessage(Exception error) {
    if (error is RestException) return error.message;

    return 'Could not reach ${endpoint.host}. Check the address and your connection.';
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      json = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
    } on FormatException {
      throw RestException(
        'The server answered with something unexpected',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return json;

    final fieldErrors = <String, String>{};
    String? message;

    for (final entry in json.entries) {
      final value = entry.value;
      if (value is String) {
        fieldErrors[entry.key] = value;
        message ??= value;
      }
    }

    // the identity field carries the reason for every auth failure, including a
    // wrong password, so prefer it when it is there
    throw RestException(
      fieldErrors['identity'] ??
          message ??
          'Request failed (${response.statusCode})',
      statusCode: response.statusCode,
      fieldErrors: fieldErrors,
    );
  }
}
