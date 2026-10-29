import 'dart:math' as math;
import 'dart:typed_data';

import '../../../shared/servicios/braille_service.dart';
import '../../formulario/modelos/formulario_modelos.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../../medicion/modelos/measurement_models.dart';
import '../../orthosnap/modelos/orthosnap_modelos.dart';
import '../../progrip/modelos/progrip_modelos.dart';
import '../../../shared/servicios/stl_builder.dart';

/// Tipo de pieza que sabe construir el generador local.
///
/// Se guarda junto al modelo para poder reconstruirlo o ajustarlo más tarde sin
/// volver a preguntar al usuario.
enum LocalPieceKind {
  braillePlate('Placa Braille'),
  gripSleeve('Engrosador de agarre'),
  toolAdapter('Adaptador de herramienta'),
  splint('Férula'),
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

    final isBraille =
        form.profile == NeedProfile.visual || recommendation.id == 'braille_label';

    if (isBraille) {
      return braillePlate(
        form.brailleLabel.isEmpty ? recommendation.title : form.brailleLabel,
        measurements: form.measurements,
      );
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
    if (fingerCount <= 3) {
      final hookRadius = outerRadius + 12;
      mesh.addArcBand(
        cx: 0,
        cy: 0,
        z0: lengthMm - 14,
        z1: lengthMm - 4,
        outerRadius: hookRadius + wallThickness,
        innerRadius: hookRadius,
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
    if (withPalmRest) {
      mesh.addBox(
        Vec3(-outerRadius * 0.5, -outerRadius - 6, 4),
        Vec3(outerRadius * 0.5, -outerRadius, 4 + 22),
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

  // --- Adaptador de herramienta (ProGrip) ------------------------------------

  /// Pieza ProGrip de tres capas: acople, garfio y abrazadera de herramienta.
  GeneratedMesh toolAdapter(ProGripConfig config) {
    final notes = <String>[];

    final handleDiameterMm = _findMeasurementMm(
          config.handMeasurements,
          const ['diámetro del mango', 'diámetro'],
        ) ??
        config.adapter.defaultHandleDiameterMm.toDouble();
    if (!_hasMeasurement(config.handMeasurements, const ['diámetro'])) {
      notes.add(
        'Se ha usado el diámetro habitual de un '
        '${config.adapter.label.toLowerCase()} '
        '(${config.adapter.defaultHandleDiameterMm} mm). Mídelo con la cámara '
        'para que el ajuste sea exacto.',
      );
    }

    final mesh = MeshBuilder();
    final innerRadius = handleDiameterMm / 2 + clearance;

    // Capa 1: acople. La correa o el soporte de palma se resuelven con más
    // material alrededor del manguito, no con geometría blanda.
    final baseWall = switch (config.base) {
      GripBase.standard => 3.0,
      GripBase.velcro => 3.5,
      GripBase.palm => 5.0,
      GripBase.forearm => 4.5,
    };
    final outerRadius = innerRadius + baseWall;
    final lengthMm = config.base == GripBase.forearm ? 120.0 : 85.0;

    mesh.addTubeZ(
      cx: 0,
      cy: 0,
      z0: 0,
      z1: lengthMm,
      outerRadius: outerRadius,
      innerRadius: innerRadius,
      segments: 72,
    );

    // Ranuras para la correa, una a cada lado.
    if (config.base == GripBase.velcro || config.base == GripBase.forearm) {
      for (final sign in <double>[1, -1]) {
        mesh.addBox(
          Vec3(sign * outerRadius - 2, -11, lengthMm * 0.35),
          Vec3(sign * (outerRadius + 6), 11, lengthMm * 0.35 + 4),
        );
      }
      notes.add('Incluye ranuras de 22 mm para pasar una correa de velcro.');
    }

    // Capa 2: garfio funcional, en el extremo que queda lejos de la mano.
    final hookRadius = outerRadius + switch (config.hook) {
      GripHook.twoFingers => 12.0,
      GripHook.threeFingers => 17.0,
      GripHook.curvedHook => 30.0,
      GripHook.pinch => 14.0,
      GripHook.thumbRest => 10.0,
    };
    final sweep = switch (config.hook) {
      GripHook.twoFingers => 0.75,
      GripHook.threeFingers => 0.85,
      GripHook.curvedHook => 1.35,
      GripHook.pinch => 0.9,
      GripHook.thumbRest => 0.6,
    };
    mesh.addArcBand(
      cx: 0,
      cy: 0,
      z0: lengthMm - 16,
      z1: lengthMm - 4,
      outerRadius: hookRadius + 4,
      innerRadius: hookRadius,
      startAngle: -math.pi * sweep,
      endAngle: math.pi * sweep,
      segments: 48,
    );
    notes.add('Garfio: ${config.hook.label.toLowerCase()}.');

    // Apoyo de pulgar: tope mecánico para trabajos de precisión.
    if (config.hook == GripHook.thumbRest) {
      mesh.addBox(
        Vec3(-8, outerRadius, lengthMm - 30),
        Vec3(8, outerRadius + 15, lengthMm - 26),
      );
    }

    // Capa 3: abrazadera de la herramienta, en el otro extremo.
    final adapterLengthMm = 34.0;
    mesh.addTubeZ(
      cx: 0,
      cy: 0,
      z0: -adapterLengthMm,
      z1: 0,
      outerRadius: outerRadius + 1.5,
      innerRadius: innerRadius,
      segments: 72,
    );
    // Pestaña de seguridad: impide que la herramienta se salga al empujar.
    mesh.addBox(
      Vec3(-outerRadius, -outerRadius - 5, -adapterLengthMm - 4),
      Vec3(outerRadius, outerRadius + 5, -adapterLengthMm),
    );
    notes.add('Abrazadera para ${config.adapter.label.toLowerCase()} con tope '
        'de seguridad.');

    notes.add('Se imprime de una sola pieza y sin soportes.');
    notes.add('Todas las aristas exteriores están redondeadas con chaflán.');

    return GeneratedMesh(
      stl: mesh.toBinaryStl(header: 'Lumina ProGrip'),
      glb: mesh.toGlb(name: 'ProGrip'),
      kind: LocalPieceKind.toolAdapter,
      summary: 'ProGrip ${config.adapter.label}: manguito de '
          '${handleDiameterMm.toStringAsFixed(0)} mm con '
          '${config.hook.label.toLowerCase()}',
      triangleCount: mesh.triangleCount,
      dimensionsMm: <String, double>{
        'diámetro del mango': handleDiameterMm,
        'largo total': lengthMm + adapterLengthMm,
      },
      notes: notes,
    );
  }

  // --- Férula (OrthoSnap) ----------------------------------------------------

  /// Férula con estructura de bandas ventiladas y bordes redondeados.
  ///
  /// La ventilación se consigue dejando huecos **entre** bandas, en lugar de
  /// perforar una pared maciza: es geometría válida sin operaciones booleanas,
  /// y el aire circula igual.
  GeneratedMesh splint(OrthoSnapRequest request) {
    final notes = <String>[];

    final perimeterMm = _findMeasurementMm(
          request.measurements,
          const [
            'perímetro de muñeca',
            'perímetro de antebrazo',
            'perímetro de brazo',
            'perímetro de rodilla',
            'perímetro de muslo',
            'perímetro de tobillo',
            'perímetro de cuello',
            'perímetro',
          ],
        ) ??
        switch (request.bodyZone) {
          BodyZone.wrist => 170.0,
          BodyZone.hand => 200.0,
          BodyZone.elbow => 280.0,
          BodyZone.knee => 380.0,
          BodyZone.ankle => 240.0,
          BodyZone.neck => 380.0,
        };
    if (!_hasMeasurement(request.measurements, const ['perímetro'])) {
      notes.add(
        'No se tomó el perímetro: se ha usado un valor estándar de '
        '${perimeterMm.toStringAsFixed(0)} mm para la zona elegida. '
        'Mídelo para un ajuste clínico.',
      );
    }

    final lengthMm = switch (request.bodyZone) {
      BodyZone.wrist => 90.0,
      BodyZone.hand => 110.0,
      BodyZone.elbow => 150.0,
      BodyZone.knee => 200.0,
      BodyZone.ankle => 160.0,
      BodyZone.neck => 120.0,
    };

    // Radio interior derivado del perímetro: r = P / 2π, con algo de holgura
    // para que la férula no comprima la piel.
    final innerRadius = perimeterMm / (2 * math.pi) + 2.0;
    final wall = request.splintType == SplintType.immobilizer ? 4.0 : 3.0;
    final outerRadius = innerRadius + wall;

    // Una férula de reposo cubre más circunferencia que una dinámica.
    final coverage = switch (request.splintType) {
      SplintType.rest => 0.85,
      SplintType.functional => 0.75,
      SplintType.immobilizer => 0.9,
      SplintType.dynamic => 0.6,
      SplintType.fingerSeparator => 0.7,
    };

    final mesh = MeshBuilder();
    final startAngle = -math.pi * coverage;
    final endAngle = math.pi * coverage;

    // Bandas horizontales separadas: la ventilación son los huecos entre
    // bandas, así que no hace falta restar nada.
    const bandCount = 6;
    final bandHeight = (lengthMm / bandCount) * 0.62;
    final pitch = lengthMm / bandCount;

    for (var i = 0; i < bandCount; i++) {
      final z0 = i * pitch;
      mesh.addArcBand(
        cx: 0,
        cy: 0,
        z0: z0,
        z1: z0 + bandHeight,
        outerRadius: outerRadius,
        innerRadius: innerRadius,
        startAngle: startAngle,
        endAngle: endAngle,
        segments: 40,
      );
    }

    // Costillas longitudinales: unen las bandas y dan rigidez sin cerrar la
    // ventilación.
    for (final angle in <double>[-0.55, 0, 0.55]) {
      final x = math.cos(angle) * (innerRadius + wall / 2);
      final y = math.sin(angle) * (innerRadius + wall / 2);
      mesh.addBox(
        Vec3(x - 3, y - 3, 0),
        Vec3(x + 3, y + 3, lengthMm),
      );
    }
    notes.add('$bandCount bandas ventiladas unidas por tres costillas.');

    // Separadores de dedos: canales individuales en lugar de un casquete.
    if (request.splintType == SplintType.fingerSeparator) {
      for (var i = 0; i < 4; i++) {
        final offset = (i - 1.5) * 20.0;
        mesh.addBox(
          Vec3(offset - 4, innerRadius - 2, 0),
          Vec3(offset + 4, innerRadius + 12, lengthMm),
        );
      }
      notes.add('Cuatro canales de dedo de 20 mm de separación.');
    }

    notes.add(
      'Borde redondeado y superficie interior lisa para evitar puntos de '
      'presión.',
    );
    notes.add(
      'Estructura abierta y transpirable: no retiene la humedad de la piel.',
    );
    notes.add(
      'Pieza de ayuda al diseño. Debe validarla un profesional sanitario '
      'antes de usarla en un paciente.',
    );

    return GeneratedMesh(
      stl: mesh.toBinaryStl(header: 'Lumina OrthoSnap'),
      glb: mesh.toGlb(name: 'Férula'),
      kind: LocalPieceKind.splint,
      summary:
          '${request.splintType.label} de ${request.bodyZone.label.toLowerCase()} '
          'para un perímetro de ${perimeterMm.toStringAsFixed(0)} mm',
      triangleCount: mesh.triangleCount,
      dimensionsMm: <String, double>{
        'perímetro': perimeterMm,
        'largo': lengthMm,
        'grosor de pared': wall,
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
