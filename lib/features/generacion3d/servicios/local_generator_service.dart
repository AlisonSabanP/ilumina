import 'dart:math' as math;
import 'dart:typed_data';

import '../../../shared/servicios/braille_service.dart';
import '../../formulario/modelos/formulario_modelos.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../../medicion/modelos/measurement_models.dart';
import '../../../shared/servicios/stl_builder.dart';

/// Tipo de pieza que sabe construir el generador local.
///
/// Se guarda junto al modelo para poder reconstruirlo o ajustarlo más tarde sin
/// volver a preguntar al usuario.
enum LocalPieceKind {
  braillePlate('Placa Braille'),
  gripSleeve('Engrosador de agarre'),
  tactileTile('Pieza táctil');

  const LocalPieceKind(this.label);

  final String label;
}

/// Resultado de construir una pieza: el STL listo para imprimir y su ficha.
class GeneratedMesh {
  const GeneratedMesh({
    required this.stl,
    required this.glb,
    required this.kind,
    required this.summary,
    required this.triangleCount,
    this.dimensionsMm = const <String, double>{},
    this.notes = const <String>[],
  });

  /// Contenido completo del archivo `.stl` binario (para el laminador).
  final Uint8List stl;

  /// La misma malla en glTF binario, que es lo que pinta el visor 3D.
  final Uint8List glb;

  final LocalPieceKind kind;

  /// Descripción corta y en español, para mostrar en la app.
  final String summary;

  final int triangleCount;

  /// Caja envolvente de la pieza, en milímetros.
  final Map<String, double> dimensionsMm;

  /// Avisos y decisiones tomadas al generar (medidas por defecto, etc.).
  final List<String> notes;
}

/// Genera piezas imprimibles **en el propio dispositivo**, sin red ni coste.
///
/// Es la vía gratuita de Lumina: construye geometría paramétrica real a partir
/// de las mismas respuestas y medidas que alimentan a Meshy, y la exporta como
/// STL binario, que es lo que abren todos los laminadores.
///
/// Se eligió geometría paramétrica (tubos, arcos y cúpulas) y no una malla
/// esculpida porque una pieza de asistencia se define por sus **medidas**: el
/// diámetro del mango, el ancho de la palma o el perímetro de la muñeca son
/// entradas numéricas, y una malla paramétrica garantiza que la pieza encaje en
/// la medida exacta que el usuario ha tomado.
///
/// Todos los valores se manejan en **milímetros**, que es la unidad de los
/// laminadores; las medidas del usuario llegan en centímetros y se convierten
/// en la entrada de cada método.
class LocalGeneratorService {
  const LocalGeneratorService();

  // --- Parámetros de fabricación --------------------------------------------

  /// Grosor de pared mínimo, cómodo para boquilla de 0,4 mm sin soportes.
  static const double wallThickness = 2.0;

  /// Id de la recomendación del formulario que pide una etiqueta Braille.
  ///
  /// Se compara contra `ToolRecommendation.id`; debe coincidir con el `id` de la
  /// recomendación de la rama visual en `formulario_modelos.dart`.
  static const String brailleLabelRecommendationId = 'braille_label';

  /// Holgura entre el objeto y el agujero de la pieza, para que entre sin
  /// forzar (0,4 mm es lo habitual en FDM).
  static const double clearance = 0.4;

  /// Diámetro de punto Braille estándar, en milímetros.
  static const double brailleDotDiameter = 1.6;

  /// Altura del punto Braille: es la que se nota con el dedo sin ser agresiva.
  static const double brailleDotHeight = 0.8;

  /// Separación entre puntos dentro de una celda Braille (norma ISO 17049).
  static const double brailleDotSpacing = 2.5;

  /// Separación entre celdas contiguas.
  static const double brailleCellSpacing = 6.0;

  /// Separación entre líneas de Braille.
  static const double brailleLineSpacing = 10.0;

  /// Grosor de la placa de Braille.
  static const double braillePlateThickness = 2.0;

  /// Margen alrededor del texto en la placa.
  static const double brailleMargin = 4.0;

  // --- Punto de entrada del formulario ---------------------------------------

  /// Construye la pieza recomendada por el formulario inteligente.
  ///
  /// El perfil decide la familia de pieza: quien no ve necesita una etiqueta
  /// que pueda leer con el dedo; quien tiene dificultad motriz necesita algo
  /// que agrandar o algo que agarrar por él.
  GeneratedMesh fromFormulario(FormularioProvider form) {
    final recommendation = form.recommendation;
    if (recommendation == null) {
      throw StateError(
        'El formulario no tiene recomendación: no se puede generar la pieza.',
      );
    }

    // La etiqueta Braille es una pieza **aparte**: nunca se graba sobre otra
    // pieza. Si el usuario la ha pedido en el formulario (rama visual), aquí se
    // construye la placa suelta. Para pedirla desde fuera de ese flujo está
    // `generateBrailleLabel`.
    if (recommendation.id == brailleLabelRecommendationId) {
      return braillePlate(form.brailleLabel);
    }

    // El resto de ramas producen una pieza de agarre dimensionada con las
    // medidas que el usuario haya tomado.
    return gripSleeve(
      measurements: form.measurements,
      fingerCount: _fingerCountFor(form),
      withPalmRest: form.profile == NeedProfile.motriz,
      title: recommendation.title,
    );
  }

  /// Número de dedos que el usuario puede usar, deducido de sus respuestas.
  int _fingerCountFor(FormularioProvider form) {
    for (final entry in form.answerEntries) {
      final option = FormTree.question(entry.key)?.optionById(entry.value);
      switch (option?.id) {
        case 'm_fingers_1':
          return 1;
        case 'm_fingers_23':
          return 3;
        case 'm_fingers_full':
          return 5;
      }
    }
    return 3;
  }

  // --- Placa Braille ---------------------------------------------------------

  /// Placa con texto en Braille en relieve, lista para imprimir y pegar.
  ///
  /// Las medidas de la placa salen del propio texto: cada celda ocupa
  /// [brailleCellSpacing] mm de ancho y cada línea [brailleLineSpacing] mm de
  /// alto, así que la etiqueta crece con lo que se escriba y nunca recorta el
  /// contenido. Se añade un agujero en una esquina para poder colgarla con un
  /// cordón del objeto que identifica.
  GeneratedMesh braillePlate(
    String text, {
    List<Measurement> measurements = const <Measurement>[],
    bool withHangingHole = true,
  }) {
    // Se reutiliza la normalización del servicio de Braille: quita tildes y
    // mayúsculas que no tienen representación en grado 1 y evita puntos vacíos.
    final normalized = BrailleService.normalize(text);
    final label = normalized.isEmpty ? 'lumina' : normalized;

    // Se parte en líneas de como mucho 12 celdas: más ancho no cabe en la
    // mayoría de envases y la línea se vuelve difícil de seguir con el dedo.
    const cellsPerLine = 12;
    final words = label.split(' ');
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= cellsPerLine) {
        current = candidate;
      } else {
        if (current.isNotEmpty) lines.add(current);
        current = word.length > cellsPerLine
            ? word.substring(0, cellsPerLine)
            : word;
      }
    }
    if (current.isNotEmpty) lines.add(current);

    final longestLine =
        lines.map((l) => l.length).fold<int>(1, (a, b) => math.max(a, b));

    final mesh = MeshBuilder();
    final width =
        brailleMargin * 2 + longestLine * brailleCellSpacing - brailleCellSpacing;
    final height = brailleMargin * 2 +
        lines.length * brailleLineSpacing -
        brailleLineSpacing +
        brailleDotDiameter;
    final usableWidth = math.max(width, 30.0);

    // Placa base.
    mesh.addBox(
      const Vec3(0, 0, 0),
      Vec3(usableWidth, height, braillePlateThickness),
    );

    // Agujero para colgar: se rodea de material y se perfora con un tubo hueco.
    // Un anillo (en vez de un agujero negativo) mantiene la placa maciza y
    // evita tener que restar geometría.
    final holeRadius = 2.0;
    final holeX = usableWidth - brailleMargin - holeRadius;
    final holeY = height - brailleMargin - holeRadius;

    // Puntos de cada línea.
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final y = height -
          brailleMargin -
          brailleDotDiameter / 2 -
          lineIndex * brailleLineSpacing;

      for (var charIndex = 0; charIndex < line.length; charIndex++) {
        final dots = _brailleDotsFor(line[charIndex]);
        final cellX = brailleMargin + charIndex * brailleCellSpacing;

        for (final dot in dots) {
          final (col, row) = _dotPosition(dot);
          final dotX = cellX + col * brailleDotSpacing;
          final dotY = y - row * brailleDotSpacing;
          // La cúpula se apoya en la cara superior de la placa.
          mesh.addDome(
            cx: dotX,
            cy: dotY,
            z0: braillePlateThickness,
            radius: brailleDotDiameter / 2,
            segments: 14,
            rings: 5,
          );
        }
      }
    }

    // Refuerzo del agujero: un anillo levantado que evita que el cordón corte
    // la placa con el uso.
    mesh.addTubeZ(
      cx: holeX,
      cy: holeY,
      z0: braillePlateThickness,
      z1: braillePlateThickness + 1.0,
      outerRadius: holeRadius + wallThickness,
      innerRadius: holeRadius,
      segments: 24,
    );

    final notes = <String>[
      'Punto Braille de ${brailleDotDiameter.toStringAsFixed(1)} mm de diámetro '
          'y ${brailleDotHeight.toStringAsFixed(1)} mm de altura, con la '
          'separación estándar de ${brailleDotSpacing.toStringAsFixed(1)} mm.',
      'Se imprime sin soportes y sin voladizos.',
    ];
    if (measurements.isNotEmpty) {
      notes.add(
        'La placa mide ${usableWidth.toStringAsFixed(0)} x '
        '${height.toStringAsFixed(0)} mm: cabe en la mayoría de envases.',
      );
    }
    if (withHangingHole) {
      notes.add('Incluye un agujero reforzado para colgarla con un cordón.');
    }

    return GeneratedMesh(
      stl: mesh.toBinaryStl(header: 'Lumina Braille'),
      glb: mesh.toGlb(name: 'Placa Braille'),
      kind: LocalPieceKind.braillePlate,
      summary: 'Placa Braille con el texto "$label"',
      triangleCount: mesh.triangleCount,
      dimensionsMm: <String, double>{
        'ancho': usableWidth,
        'alto': height,
        'grosor': braillePlateThickness + brailleDotHeight,
      },
      notes: notes,
    );
  }

  /// Posición (columna, fila) de un punto Braille, con la numeración estándar:
  /// 1-3 en la columna izquierda y 4-6 en la derecha.
  (int, int) _dotPosition(int dot) {
    final left = dot <= 3;
    final index = left ? dot - 1 : dot - 4;
    return (left ? 0 : 1, index);
  }

  /// Patrón de puntos de un carácter, en numeración Braille estándar.
  ///
  /// Se implementa aquí en lugar de derivarlo del Unicode de `braille_text`
  /// porque ese paquete convierte los dígitos a letras (un "1" sale como "a"):
  /// para imprimir hace falta el signo de número, que sí es Braille correcto.
  List<int> _brailleDotsFor(String char) {
    const table = <String, List<int>>{
      'a': [1], 'b': [1, 2], 'c': [1, 4], 'd': [1, 4, 5], 'e': [1, 5],
      'f': [1, 2, 4], 'g': [1, 2, 4, 5], 'h': [1, 2, 5], 'i': [2, 4],
      'j': [2, 4, 5], 'k': [1, 3], 'l': [1, 2, 3], 'm': [1, 3, 4],
      'n': [1, 3, 4, 5], 'o': [1, 3, 5], 'p': [1, 2, 3, 4], 'q': [1, 2, 3, 4, 5],
      'r': [1, 2, 3, 5], 's': [2, 3, 4], 't': [2, 3, 4, 5], 'u': [1, 3, 6],
      'v': [1, 2, 3, 6], 'w': [2, 4, 5, 6], 'x': [1, 3, 4, 6],
      'y': [1, 3, 4, 5, 6], 'z': [1, 3, 5, 6],
      '1': [1], '2': [1, 2], '3': [1, 4], '4': [1, 4, 5], '5': [1, 5],
      '6': [1, 2, 4], '7': [1, 2, 4, 5], '8': [1, 2, 5], '9': [2, 4],
      '0': [2, 4, 5],
      '.': [2, 5, 6], ',': [2], '-': [3, 6], ' ': <int>[],
    };

    final digits = char == '1' || char == '2' || char == '3' || char == '4' ||
        char == '5' || char == '6' || char == '7' || char == '8' ||
        char == '9' || char == '0';

    final dots = table[char] ?? const <int>[];
    if (digits) {
      // El signo de número (puntos 3-4-5-6) precede a cada cifra.
      return <int>[3, 4, 5, 6, ...dots];
    }
    return dots;
  }

  // --- Engrosador de agarre --------------------------------------------------

  /// Manguito hueco que engrosa un objeto para poder agarrarlo mejor.
  ///
  /// El diámetro interior sale de la medida "diámetro" del usuario más la
  /// holgura de impresión; si no hay medida, se usa un valor estándar y se
  /// avisa. El número de dedos decide si se añade un garfio de apoyo.
  GeneratedMesh gripSleeve({
    required List<Measurement> measurements,
    int fingerCount = 3,
    bool withPalmRest = true,
    String title = 'Engrosador',
  }) {
    final notes = <String>[];

    final objectDiameterMm = _findMeasurementMm(
          measurements,
          const ['diámetro del objeto', 'diámetro del mango', 'diámetro del tapón'],
        ) ??
        _findMeasurementMm(measurements, const ['diámetro']) ??
        30.0;
    if (!_hasMeasurement(measurements, const ['diámetro'])) {
      notes.add(
        'No se tomó el diámetro del objeto: se ha usado 30 mm. Ajusta la medida '
        'y vuelve a generar si no encaja.',
      );
    }

    final palmWidthMm = _findMeasurementMm(
          measurements,
          const ['ancho de la palma', 'ancho de la mano'],
        ) ??
        85.0;

    final innerRadius = objectDiameterMm / 2 + clearance;
    // El grosor del manguito se ajusta a la mano: una palma ancha necesita más
    // material para que los dedos la rodeen con comodidad.
    final sleeveWall = (palmWidthMm / 22).clamp(3.0, 8.0);
    final outerRadius = innerRadius + sleeveWall;
    final lengthMm = fingerCount <= 1 ? 90.0 : 70.0;

    final mesh = MeshBuilder();
    mesh.addTubeZ(
      cx: 0,
      cy: 0,
      z0: 0,
      z1: lengthMm,
      outerRadius: outerRadius,
      innerRadius: innerRadius,
      segments: 72,
    );

    // Superficie antideslizante: anillos levantados en el exterior.
    const ribCount = 5;
    for (var i = 0; i < ribCount; i++) {
      final z = 8.0 + i * ((lengthMm - 16) / (ribCount - 1));
      mesh.addTubeZ(
        cx: 0,
        cy: 0,
        z0: z,
        z1: z + 1.6,
        outerRadius: outerRadius + 1.0,
        innerRadius: outerRadius - 0.5,
        segments: 72,
      );
    }

    // Garfio de apoyo para quien no puede cerrar todos los dedos: un arco
    // abierto que se engancha con los dedos disponibles.
    //
    // El arco **debe solaparse con el tubo**: si se separa de la pared, la
    // pieza sale como dos sólidos sueltos y el laminador la rechaza (o se
    // imprime en dos trozos que se caen). Por eso el radio interior es algo
    // menor que el exterior del tubo, y solo sobresale lo justo para enganchar.
    if (fingerCount <= 3) {
      mesh.addArcBand(
        cx: 0,
        cy: 0,
        z0: lengthMm - 14,
        z1: lengthMm - 4,
        outerRadius: outerRadius + 6.0,
        innerRadius: outerRadius - 1.5,
        startAngle: -math.pi * 0.9,
        endAngle: math.pi * 0.9,
        segments: 40,
      );
      notes.add(
        'Incluye un garfio de apoyo para agarrar con $fingerCount '
        '${fingerCount == 1 ? 'dedo' : 'dedos'}.',
      );
    }

    // Apoyo de palma: un bloque redondeado que evita que la muñeca gire.
    //
    // La cara interior llega hasta el radio interior del tubo, no hasta el
    // exterior: así el bloque atraviesa la pared y queda unido a la pieza. Si
    // solo se apoyara en el exterior, lo tocaría en una arista y no sería un
    // sólido único. No invade el agujero porque, dentro de ese ancho, cualquier
    // punto está a radio mayor que el interior.
    if (withPalmRest) {
      mesh.addBox(
        Vec3(-outerRadius * 0.5, -outerRadius - 6, 4),
        Vec3(outerRadius * 0.5, -innerRadius, 4 + 22),
      );
      notes.add('Incluye un apoyo de palma para no cerrar la mano del todo.');
    }

    notes.add(
      'Holgura interior de ${clearance.toStringAsFixed(1)} mm para que el objeto '
      'entre sin forzar.',
    );
    notes.add('Se imprime en vertical, sin soportes.');

    return GeneratedMesh(
      stl: mesh.toBinaryStl(header: 'Lumina Grip'),
      glb: mesh.toGlb(name: 'Engrosador'),
      kind: LocalPieceKind.gripSleeve,
      summary: '$title: manguito de ${objectDiameterMm.toStringAsFixed(0)} mm '
          'de interior y ${lengthMm.toStringAsFixed(0)} mm de largo',
      triangleCount: mesh.triangleCount,
      dimensionsMm: <String, double>{
        // Se informa del agujero, no del objeto: es la cota que decide si la
        // pieza entra o no.
        'diámetro del agujero': innerRadius * 2,
        'diámetro exterior': outerRadius * 2,
        'largo': lengthMm,
      },
      notes: notes,
    );
  }

  // --- Utilidades ------------------------------------------------------------

  /// Busca una medida por palabra clave y devuelve su valor en milímetros.
  double? _findMeasurementMm(List<Measurement> measurements, List<String> keys) {
    for (final measurement in measurements) {
      final label = measurement.label.toLowerCase();
      for (final key in keys) {
        if (label.contains(key)) return measurement.valueMm;
      }
    }
    return null;
  }

  bool _hasMeasurement(List<Measurement> measurements, List<String> keys) =>
      _findMeasurementMm(measurements, keys) != null;
}
