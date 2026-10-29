import 'dart:math' as math;

/// Origen de una medida.
enum MeasurementSource {
  /// Obtenida de los 21 landmarks de la mano (MediaPipe).
  hand('Mano', 'Medida calculada a partir de la mano'),

  /// Introducida a mano por el usuario o el profesional.
  manual('Manual', 'Medida introducida a mano');

  const MeasurementSource(this.label, this.description);

  final String label;
  final String description;
}

/// Qué representa la medida. Determina cómo se usa en el prompt de Meshy.
enum MeasurementKind {
  handSpan('Envergadura de la mano'),
  handPalmWidth('Ancho de palma'),
  handGripOpening('Apertura de agarre'),
  handFingerLength('Largo de dedo'),
  manualLength('Largo'),
  manualWidth('Ancho'),
  manualHeight('Alto'),
  manualDiameter('Diámetro'),
  manualThickness('Grosor');

  const MeasurementKind(this.label);

  final String label;
}

/// Una medida concreta, con su unidad ya normalizada a centímetros.
///
/// Nota: hubo un origen `ar` (medición por ARCore/ARKit) que se retiró porque
/// la medición AR no funcionaba de forma fiable en dispositivos reales. Los
/// datos guardados con ese origen se leen como `manual`, que es su equivalente
/// más cercano, gracias al `orElse` de [Measurement.fromJson].
class Measurement {
  const Measurement({
    required this.id,
    required this.label,
    required this.valueCm,
    required this.kind,
    required this.source,
    required this.timestamp,
    this.confidence,
    this.note,
  });

  final String id;

  /// Etiqueta legible, p. ej. "Diámetro del mango".
  final String label;

  /// Valor en centímetros (unidad interna de Lumina).
  final double valueCm;

  final MeasurementKind kind;
  final MeasurementSource source;
  final DateTime timestamp;

  /// 0.0-1.0. Solo tiene sentido en medidas derivadas de landmarks.
  final double? confidence;

  /// Aclaración opcional (p. ej. "estimado por calibración").
  final String? note;

  double get valueMm => valueCm * 10;

  /// Texto corto y legible para la UI y para el prompt.
  String get display {
    if (valueCm >= 100) {
      return '${(valueCm / 100).toStringAsFixed(2)} m';
    }
    return '${valueCm.toStringAsFixed(1)} cm';
  }

  /// Frase que se inserta en el prompt de Meshy.
  String get promptPhrase => '$label: ${valueCm.toStringAsFixed(1)} cm';

  Measurement copyWith({
    String? label,
    double? valueCm,
    MeasurementKind? kind,
    String? note,
  }) {
    return Measurement(
      id: id,
      label: label ?? this.label,
      valueCm: valueCm ?? this.valueCm,
      kind: kind ?? this.kind,
      source: source,
      timestamp: timestamp,
      confidence: confidence,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'valueCm': valueCm,
        'kind': kind.name,
        'source': source.name,
        'timestamp': timestamp.toIso8601String(),
        'confidence': confidence,
        'note': note,
      };

  static Measurement fromJson(Map<String, dynamic> json) => Measurement(
        id: json['id'] as String,
        label: json['label'] as String,
        valueCm: (json['valueCm'] as num).toDouble(),
        kind: MeasurementKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => MeasurementKind.manualLength,
        ),
        source: MeasurementSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => MeasurementSource.manual,
        ),
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        confidence: (json['confidence'] as num?)?.toDouble(),
        note: json['note'] as String?,
      );
}

/// Índices de los 21 landmarks de MediaPipe, en el orden que documenta Google.
///
/// 0 muñeca · 1-4 pulgar (CMC, MCP, IP, punta) · 5-8 índice · 9-12 corazón ·
/// 13-16 anular · 17-20 meñique (MCP, PIP, DIP, punta).
abstract final class HandLandmark {
  static const int wrist = 0;
  static const int thumbTip = 4;
  static const int indexMcp = 5;
  static const int indexTip = 8;
  static const int middleMcp = 9;
  static const int middleTip = 12;
  static const int ringMcp = 13;
  static const int pinkyMcp = 17;
  static const int pinkyTip = 20;

  /// Conexiones del esqueleto, para dibujar la mano superpuesta.
  static const List<List<int>> connections = <List<int>>[
    <int>[0, 1], <int>[1, 2], <int>[2, 3], <int>[3, 4],
    <int>[0, 5], <int>[5, 6], <int>[6, 7], <int>[7, 8],
    <int>[5, 9], <int>[9, 10], <int>[10, 11], <int>[11, 12],
    <int>[9, 13], <int>[13, 14], <int>[14, 15], <int>[15, 16],
    <int>[13, 17], <int>[0, 17], <int>[17, 18], <int>[18, 19],
    <int>[19, 20],
  ];
}

/// Punto 3D normalizado devuelto por `hand_landmarker`.
///
/// `x` e `y` están normalizados al ancho y alto de la imagen (0-1). `z` es la
/// profundidad relativa a la muñeca, aproximadamente en las mismas unidades
/// que `x`. Ninguno de los tres está en milímetros: MediaPipe no da escala
/// métrica (ver [HandMetrics.fromLandmarks]).
class HandPoint {
  const HandPoint(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  @override
  String toString() =>
      'HandPoint(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// Calcula distancias entre landmarks de la mano y las convierte a centímetros.
///
/// ## Por qué hace falta calibrar
/// `hand_landmarker` devuelve coordenadas **normalizadas**, sin escala física.
/// Una distancia medida en píxeles no se puede convertir a centímetros sin una
/// referencia de tamaño conocido. Lumina resuelve esto con una calibración
/// explícita: el usuario indica el ancho real de su palma en centímetros
/// —medido con una regla o con la cinta métrica— y de ahí se obtiene
/// el factor `cm/píxel` que se aplica a todas las demás distancias.
///
/// Si el usuario todavía no ha calibrado, se usa [defaultReferencePalmWidthCm]
/// y el resultado se marca con [isEstimated]: son centímetros de orden de
/// magnitud creíble, pero conviene sustituirlos por una calibración real antes
/// de imprimir.
class HandMetrics {
  const HandMetrics({
    required this.handSpan,
    required this.palmWidth,
    required this.gripOpening,
    required this.indexFingerLength,
    required this.middleFingerLength,
    required this.cmPerPixel,
    required this.confidence,
    this.isEstimated = false,
  });

  /// Ancho de palma de referencia por defecto, en centímetros.
  ///
  /// Media antropométrica de una persona adulta, de nudillo a nudillo. Se usa
  /// cuando el usuario aún no ha calibrado, para que las medidas aparezcan en
  /// centímetros y con un orden de magnitud creíble desde el primer momento.
  static const double defaultReferencePalmWidthCm = 8.5;

  /// Distancia punta del pulgar (4) a punta del meñique (20), en cm.
  final double handSpan;

  /// Distancia entre nudillos índice (5) y meñique (17), en cm.
  final double palmWidth;

  /// Apertura máxima de agarre: pulgar (4) a nudillo del corazón (9), en cm.
  ///
  /// Es una **estimación** del diámetro máximo que la mano puede abrazar; sirve
  /// para dimensionar mangos y engrosadores.
  final double gripOpening;

  final double indexFingerLength;
  final double middleFingerLength;

  /// Factor de conversión usado. Si es nulo, no hubo calibración.
  final double? cmPerPixel;

  /// 0.0-1.0: fracción de landmarks con coordenadas válidas dentro de [0,1].
  final double confidence;

  /// `true` si los centímetros salen de una calibración hecha por el usuario.
  /// Si es `false` pero [isCalibrated] es `true`, son una estimación con el
  /// ancho de palma medio.
  final bool isEstimated;

  /// `true` si los valores están en centímetros (medidos o estimados).
  bool get isCalibrated => cmPerPixel != null;

  /// Etiqueta de unidad que debe mostrarse junto a los valores.
  String get unitLabel => isCalibrated ? 'cm' : 'u.r.';

  /// Calcula las métricas a partir de los landmarks.
  ///
  /// [frameWidth] y [frameHeight] deben ser el tamaño **real** de la imagen que
  /// se envió al detector, es decir `CameraImage.width` y `CameraImage.height`
  /// ya corregidos por la rotación del sensor. Es un error frecuente pasar aquí
  /// el `previewSize` del `CameraController`: la vista previa y el flujo de
  /// imágenes son dos resoluciones distintas, y usar la equivocada desvía todas
  /// las distancias. Ver `hand_measurement_screen.dart`.
  ///
  /// [referencePalmWidthCm] es la calibración: ancho real de la palma en cm. Si
  /// se omite, se usa [defaultReferencePalmWidthCm] y el resultado se marca con
  /// [isEstimated] para que la UI lo advierta.
  factory HandMetrics.fromLandmarks(
    List<HandPoint> landmarks, {
    required double frameWidth,
    required double frameHeight,
    double? referencePalmWidthCm,
  }) {
    if (landmarks.length < 21) {
      throw ArgumentError(
        'Se esperaban 21 landmarks y se recibieron ${landmarks.length}',
      );
    }
    if (frameWidth <= 0 || frameHeight <= 0) {
      throw ArgumentError(
        'El tamaño del fotograma debe ser positivo '
        '(${frameWidth.toStringAsFixed(0)}x${frameHeight.toStringAsFixed(0)}).',
      );
    }

    double pixelDistance(int a, int b) {
      final pa = landmarks[a];
      final pb = landmarks[b];
      final dx = (pa.x - pb.x) * frameWidth;
      final dy = (pa.y - pb.y) * frameHeight;
      return math.sqrt(dx * dx + dy * dy);
    }

    final palmWidthPx = pixelDistance(
      HandLandmark.indexMcp,
      HandLandmark.pinkyMcp,
    );

    final isEstimated = referencePalmWidthCm == null;
    final reference = referencePalmWidthCm ?? defaultReferencePalmWidthCm;

    // El factor solo tiene sentido si la palma se ve con un tamaño razonable.
    // Un `palmWidthPx` diminuto significa que la mano está lejísimos o que el
    // fotograma no es el que se cree: en ese caso es mejor no calibrar que
    // devolver centímetros absurdos.
    double? cmPerPixel;
    if (reference > 0 && palmWidthPx > 1) {
      cmPerPixel = reference / palmWidthPx;
    }

    double convert(double px) => cmPerPixel == null ? px : px * cmPerPixel;

    final valid = landmarks
        .where(
          (p) => p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1 && p.z.isFinite,
        )
        .length;

    return HandMetrics(
      handSpan: convert(
        pixelDistance(HandLandmark.thumbTip, HandLandmark.pinkyTip),
      ),
      palmWidth: convert(palmWidthPx),
      gripOpening: convert(
        pixelDistance(HandLandmark.thumbTip, HandLandmark.middleMcp),
      ),
      indexFingerLength: convert(
        pixelDistance(HandLandmark.indexMcp, HandLandmark.indexTip),
      ),
      middleFingerLength: convert(
        pixelDistance(HandLandmark.middleMcp, HandLandmark.middleTip),
      ),
      cmPerPixel: cmPerPixel,
      confidence: valid / 21,
      isEstimated: isEstimated,
    );
  }
}
