import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mantenimiento_predictivo/services/api.dart';

void main() {
  ApiClient make(Future<http.Response> Function(http.Request) handler) => ApiClient(
    client: MockClient(handler), resolve: (path) => Uri.parse('https://example.com$path'));

  test('Bearer token attaches to private requests, password is not retained', () async {
    final api = make((request) async {
      expect(request.headers['Authorization'], 'Bearer user-token');
      return http.Response('{"ok":true}', 200);
    })..token = 'user-token';
    expect(await api.request('/api/me'), {'ok': true});
  });
  test('401 clears session once and notifies navigation', () async {
    var expired = 0;
    var cleared = 0;
    final api = make((_) async => http.Response('unauthorized', 401))
      ..token = 'expired'
      ..onUnauthorized = () { expired++; }
      ..clearStoredToken = () async { cleared++; };
    for (var i = 0; i < 2; i++) {
      await expectLater(api.request('/api/me'), throwsA(isA<ApiException>()));
    }
    expect(api.token, isNull);
    expect(expired, 1);
    expect(cleared, 1);
  });
  test('403 preserves session; HTML 502 gets a safe server message', () async {
    for (final status in [403, 502]) {
      final api = make((_) async => http.Response('<html>private error</html>', status))..token = 'valid';
      await expectLater(api.request('/api/me'), throwsA(isA<ApiException>()
        .having((e) => e.statusCode, 'status', status)
        .having((e) => e.message.contains('private error'), 'no internal detail', false)));
      expect(api.token, 'valid');
    }
  });
  test('timeout becomes a user-facing API error', () async {
    final api = make((_) async => throw TimeoutException('internal'));
    await expectLater(api.request('/api/me'), throwsA(isA<ApiException>()
      .having((e) => e.message, 'message', contains('tardó demasiado'))));
  });
}
