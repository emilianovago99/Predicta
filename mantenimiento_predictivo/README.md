# Cliente Predicta

Flutter 3.38.3 / Dart 3.10.1. Ver [guía de desarrollo y despliegue](../deploy/README.md).

```bash
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://127.0.0.1:8000
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
flutter build apk --release --dart-define=API_BASE_URL=https://TU_DOMINIO
flutter build appbundle --release --dart-define=API_BASE_URL=https://TU_DOMINIO
```

Web release usa el origen actual con /api. Android/iOS release requieren HTTPS
por dart-define; debug permite localhost/emulador. .env no se carga automáticamente.
ApiClient centraliza Bearer JWT, 401/403/429/timeouts/errores del servidor.
Tokens móviles en almacenamiento seguro; web en memoria. No se guardan passwords.
Configurar firma Android/iOS propia antes de distribuir. La firma Android del
proyecto sigue siendo la original de desarrollo hasta que se configure una propia.
