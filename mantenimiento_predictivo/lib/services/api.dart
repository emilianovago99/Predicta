import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'http_client.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class ApiClient {
  final http.Client client;
  final Uri Function(String) resolve;
  final Duration timeout;
  String? _token;
  bool _unauthorizedNotified = false;
  String? get token => _token;
  set token(String? value) {
    _token = value;
    if (value != null) _unauthorizedNotified = false;
  }
  VoidCallback? onUnauthorized;
  Future<void> Function()? clearStoredToken;
  ApiClient({http.Client? client, Uri Function(String)? resolve,
    this.timeout = const Duration(seconds: 40)})
      : client = client ?? createHttpClient(), resolve = resolve ?? ApiConfig.uri;

  Future<dynamic> request(String path, {Map<String, dynamic>? body, bool put = false, bool delete = false}) async {
    try {
      final sentToken = token;
      final headers = {'Content-Type': 'application/json',
        if (sentToken != null) 'Authorization': 'Bearer $sentToken'};
      final uri = resolve(path);
      final response = await (delete ? client.delete(uri, headers: headers)
          : body == null ? client.get(uri, headers: headers)
          : put ? client.put(uri, headers: headers, body: jsonEncode(body))
          : client.post(uri, headers: headers, body: jsonEncode(body))).timeout(timeout);
      if (response.statusCode == 401) {
        if (path != '/api/login' && sentToken == token && !_unauthorizedNotified) {
          _unauthorizedNotified = true;
          token = null;
          await clearStoredToken?.call();
          onUnauthorized?.call();
        }
        throw ApiException(path == '/api/login' ? 'Credenciales incorrectas.' : 'Tu sesión venció. Inicia sesión de nuevo.', 401);
      }
      if (response.statusCode == 403) throw const ApiException('No tienes permiso para esta operación.', 403);
      if (response.statusCode == 429) throw const ApiException('Demasiados intentos. Espera un momento.', 429);
      if (response.statusCode >= 500) throw ApiException('El servicio no está disponible. Inténtalo más tarde.', response.statusCode);
      dynamic data;
      try { data = jsonDecode(utf8.decode(response.bodyBytes)); }
      on FormatException { throw const ApiException('Respuesta inválida del servidor.'); }
      if (response.statusCode >= 400) {
        final detail = data is Map ? data['detail'] : null;
        throw ApiException(detail is String ? detail : 'Revisa los campos e inténtalo de nuevo.', response.statusCode);
      }
      return data;
    } on ApiException { rethrow; }
    on TimeoutException { throw const ApiException('El servidor tardó demasiado. Inténtalo de nuevo.'); }
    catch (_) { throw const ApiException('No podemos conectar con Predicta. Comprueba tu conexión.'); }
  }
}

class Api {
  static final client = ApiClient();
  static const _storage = FlutterSecureStorage();
  static bool get _mobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  static Future<void> initialize() async {
    client.clearStoredToken = () async { if (_mobile) await _storage.delete(key: 'access_token'); };
    if (_mobile) client.token = await _storage.read(key: 'access_token');
  }
  static Future<void> saveToken(String token) async {
    if (_mobile) await _storage.write(key: 'access_token', value: token);
    client.token = token;
  }
  static Future<void> logout() async {
    try { await client.request('/api/logout', body: {}); } catch (_) { /* Expired sessions are already invalid. */ }
    client.token = null;
    await client.clearStoredToken?.call();
  }
  static Future<dynamic> request(String path, {Map<String, dynamic>? body, bool put = false, bool delete = false}) =>
    client.request(path, body: body, put: put, delete: delete);
}
