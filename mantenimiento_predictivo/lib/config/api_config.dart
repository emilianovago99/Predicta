import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    final value = configured.trim();
    if (value.isNotEmpty) return value.replaceFirst(RegExp(r'/+$'), '');
    if (kIsWeb) {
      final origin = Uri.base;
      final port = origin.hasPort ? origin.port : (origin.scheme == 'https' ? 443 : 80);
      // Solo el nginx de Docker (8088) y deploys en 80/443 proxyan /api.
      // flutter run -d chrome usa un puerto aleatorio (p. ej. 57594) sin API.
      if (port == 80 || port == 443 || port == 8088) {
        return origin.origin.replaceFirst(RegExp(r'/+$'), '');
      }
      return 'http://127.0.0.1:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static Uri uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }
}
