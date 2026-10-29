import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Acceso centralizado a la configuración sensible (API key de Meshy).
///
/// Prioridad de resolución:
///   1. `--dart-define=MESHY_API_KEY=...` (recomendado en CI y en release).
///   2. Fichero `.env` (recomendado en desarrollo local).
///   3. [testModeApiKey], que activa el modo de demostración local.
///
/// La clave NUNCA se escribe en el código de la aplicación: solo se lee desde
/// el entorno de compilación o desde el `.env`, que está en `.gitignore`.
abstract final class Env {
  /// Valor centinela que indica "no hay clave configurada".
  ///
  /// Meshy **no tiene un modo de prueba**: con cualquier clave que no sea una
  /// cuenta real, la API responde 401. Este valor existe solo para que la app
  /// pueda distinguir "el usuario no ha configurado clave" de "el usuario ha
  /// configurado una clave", y en ese caso cargar la pieza de demostración
  /// local en lugar de llamar a la API y fallar.
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

  /// `true` cuando no hay una clave propia configurada.
  ///
  /// En ese caso Lumina trabaja en modo de demostración: genera la pieza a
  /// partir de un `.glb` local y no llama a Meshy.
  static bool get isMeshyTestMode => meshyApiKey == testModeApiKey;

  /// `true` si el desarrollador configuró una clave propia.
  static bool get hasCustomMeshyKey => !isMeshyTestMode;
}
