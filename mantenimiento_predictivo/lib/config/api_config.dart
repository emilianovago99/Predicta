import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    // Release web always uses the serving origin and its /api reverse proxy.
    if (kIsWeb && kReleaseMode) return Uri.base.origin;
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.trim().isNotEmpty) {
      final value = configured.trim().replaceFirst(RegExp(r'/+$'), '');
      final uri = Uri.parse(value);
      if (!uri.hasAuthority || (kReleaseMode && uri.scheme != 'https')) {
        throw StateError('API_BASE_URL debe ser un origen HTTPS en release');
      }
      return value;
    }
    if (kIsWeb) return Uri.base.origin;
    if (kReleaseMode) throw StateError('Configura --dart-define=API_BASE_URL=https://DOMAIN');
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  static Uri uri(String path) => Uri.parse('$baseUrl${path.startsWith('/') ? path : '/$path'}');
}
