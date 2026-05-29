import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static const String _fallbackBaseUrl = 'http://127.0.0.1:8000';

  static String get baseUrl {
    final value = dotenv.env['API_BASE_URL']?.trim();
    if (value == null || value.isEmpty) {
      return _fallbackBaseUrl;
    }
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  static Uri uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }
}
