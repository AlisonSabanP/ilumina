import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/env.dart';

/// Punto de entrada de Lumina.
///
/// Orden de arranque:
///   1. Inicializar los enlaces con el motor de Flutter.
///   2. Cargar el `.env` para resolver la clave de Meshy (ver [Env]).
///   3. Fijar la orientación vertical: la medición con cámara y el visor 3D
///      están diseñados para retrato, y en `hand_landmarker` la orientación
///      del sensor afecta al cálculo de los landmarks.
///   4. Montar los providers globales y la app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carga del .env. Si falta o está vacío, Env cae en la clave de prueba de
  // Meshy y la aplicación sigue siendo utilizable en modo demostración.
  await Env.load();

  await SystemChrome.setPreferredOrientations(
    const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ],
  );

  runApp(const LuminaRoot());
}
