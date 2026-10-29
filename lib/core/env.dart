import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Acceso centralizado a la configuración sensible (API key de Meshy).
///
/// Prioridad de resolución:
///   1. `--dart-define=MESHY_API_KEY=...` (recomendado en CI y en release).
///   2. Fichero `.env` (recomendado en desarrollo local).
///   3. Clave de prueba de Meshy (`msy_dummy_api_key_for_test_mode_12345678`).
///
/// La clave NUNCA se escribe en el código de la aplicación: solo se lee desde
/// el entorno de compilación o desde el `.env`, que está en `.gitignore`.
abstract final class Env {
  /// Clave pública de "test mode" que Meshy publica en su documentación.
  /// No consume créditos y permite ejecutar la demo sin cuenta de pago.
  static const String testModeApiKey =
      'msy_dummy_api_key_for_test_mode_12345678';

  /// Valor inyectado en tiempo de compilación.
  static const String _definedKey = String.fromEnvironment('MESHY_API_KEY');

  static String? _dotenvKey;

  /// Debe llamarse una sola vez, antes de `runApp`.
  ///
  /// El `.env` se declara como asset en `pubspec.yaml`, por lo que siempre
  /// existe en el bundle (en el peor caso, vacío).
  static Future<void> load() async {
    try {
      await dotenv.load();
      _dotenvKey = dotenv.maybeGet('MESHY_API_KEY');
    } catch (error) {
      // El `.env` puede faltar o estar vacío: no es un error fatal.
      debugPrint(
        'Env: no se pudo leer .env ($error). Se usará la clave de prueba.',
      );
    }
  }

  /// Clave efectiva que se enviará en la cabecera `Authorization`.
  static String get meshyApiKey {
    if (_definedKey.isNotEmpty) return _definedKey;
    final fromDotenv = _dotenvKey;
    if (fromDotenv != null && fromDotenv.isNotEmpty) return fromDotenv;
    return testModeApiKey;
  }

  /// `true` cuando se está trabajando con la clave de prueba gratuita.
  ///
  /// La UI lo muestra con un aviso: en este modo Meshy devuelve modelos de
  /// demostración y no se generan piezas reales a partir del prompt.
  static bool get isMeshyTestMode => meshyApiKey == testModeApiKey;

  /// `true` si el desarrollador configuró una clave propia.
  static bool get hasCustomMeshyKey => !isMeshyTestMode;
}
