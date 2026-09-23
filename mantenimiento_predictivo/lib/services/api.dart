import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  static Future<dynamic> request(String path, {Map<String, dynamic>? body, bool put = false}) async {
    try {
      final uri = ApiConfig.uri(path);
      final headers = {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'};
      final response = await (body == null
          ? http.get(uri, headers: headers)
          : put ? http.put(uri, headers: headers, body: jsonEncode(body))
          : http.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        final detail = data is Map ? data['detail'] : null;
        throw ApiException(detail is String ? detail : 'Revisa los campos e inténtalo de nuevo.');
      }
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('El servidor tardó demasiado (${ApiConfig.baseUrl}). Inténtalo de nuevo.');
    } catch (_) {
      throw ApiException('No podemos conectar con Predicta en ${ApiConfig.baseUrl}. Comprueba que la API esté en marcha.');
    }
  }
}
