import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:hand_landmarker/hand_landmarker.dart' as hl;

import '../modelos/measurement_models.dart';

/// Adaptador que aísla la dependencia de `hand_landmarker` del resto de Lumina.
///
/// Motivos para este aislamiento:
///  * `hand_landmarker` es **exclusivo de Android** (puente JNI sobre
///    MediaPipe). Sus tipos no deben filtrarse a la UI, porque la UI debe
///    compilar y funcionar también en iOS.
///  * Convierte los `Landmark` del paquete a los [HandPoint] de Lumina, de modo
///    que el cálculo de medidas ([HandMetrics]) y el pintado del esqueleto
///    ([HandLandmarkPainter]) no dependan del paquete.
///  * Centraliza el manejo de errores de la cámara y del plugin.
///
/// Uso:
/// ```dart
/// final detector = HandDetector.createIfSupported();
/// if (detector == null) {
///   // iOS o plataforma sin soporte: usar AR o medida manual.
/// }
/// ```
class HandDetector {
  HandDetector._(this._plugin);

  final hl.HandLandmarkerPlugin _plugin;

  Stream<List<HandPoint>>? _stream;

  /// `true` si esta plataforma puede ejecutar la detección.
  ///
  /// Se comprueba en tiempo de ejecución en lugar de con imports
  /// condicionales: así el código es uno solo y el fallo, si lo hubiera, es
  /// explícito y controlado en lugar de un error de compilación.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Motivo legible cuando [isSupported] es `false`.
  static String get unsupportedReason {
    if (kIsWeb) {
      return 'La detección de manos necesita la cámara de un móvil Android.';
    }
    if (Platform.isIOS) {
      return 'MediaPipe (hand_landmarker) solo está implementado para Android. '
          'En iOS usa la medición AR o la entrada manual.';
    }
    return 'La detección de manos solo está disponible en Android.';
  }

  /// Crea el detector, o devuelve `null` si la plataforma no lo soporta.
  ///
  /// Cualquier fallo de inicialización nativa se traduce en `null` para que la
  /// pantalla pueda ofrecer la alternativa manual en lugar de romperse.
  static HandDetector? createIfSupported({
    int numHands = 1,
    double minHandDetectionConfidence = 0.6,
  }) {
    if (!isSupported) return null;
    try {
      final plugin = hl.HandLandmarkerPlugin.create(
        numHands: numHands,
        minHandDetectionConfidence: minHandDetectionConfidence,
        delegate: hl.HandLandmarkerDelegate.gpu,
      );
      return HandDetector._(plugin);
    } catch (error) {
      debugPrint('HandDetector: no se pudo crear el detector nativo: $error');
      return null;
    }
  }

  /// Flujo con los 21 puntos de la **primera** mano detectada.
  ///
  /// Lumina solo mide una mano, así que el adaptador descarta las demás en
  /// lugar de propagar una lista de listas. Si no se detecta ninguna mano, el
  /// flujo emite una lista vacía, lo que la UI interpreta como "sin mano".
  Stream<List<HandPoint>> get landmarkStream {
    return _stream ??= _plugin.landmarkStream.map(_convert).asBroadcastStream();
  }

  List<HandPoint> _convert(List<hl.Hand> hands) {
    if (hands.isEmpty) return const <HandPoint>[];
    return hands.first.landmarks
        .map((landmark) => HandPoint(landmark.x, landmark.y, landmark.z))
        .toList(growable: false);
  }

  /// Envía un fotograma al detector.
  ///
  /// El plugin espera exactamente tres planos (Y, U, V) en formato YUV420, que
  /// es el que se solicita al `CameraController`. Si el dispositivo entrega
  /// otro formato, el fotograma se descarta en lugar de provocar un fallo
  /// nativo.
  bool processFrame(CameraImage image, int sensorOrientation) {
    if (image.planes.length < 3) return false;
    final uPlane = image.planes[1];
    if (uPlane.bytesPerPixel == null) return false;

    try {
      _plugin.processFrame(image, sensorOrientation);
      return true;
    } catch (error) {
      debugPrint('HandDetector: fotograma descartado: $error');
      return false;
    }
  }

  /// Libera los recursos nativos.
  void dispose() {
    try {
      _plugin.dispose();
    } catch (error) {
      debugPrint('HandDetector: error al liberar: $error');
    }
  }
}
