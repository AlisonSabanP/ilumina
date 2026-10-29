import 'package:flutter/material.dart';

import '../../medicion/modelos/measurement_models.dart';

/// Capa 1 de ProGrip: cómo se acopla la pieza a la mano o al brazo.
enum GripBase {
  standard(
    'Acople estándar',
    'Manguito cilíndrico que se sujeta con la mano que lo va a usar.',
    Icons.circle_outlined,
    <String>[
      'The base is a cylindrical sleeve that fits the palm without squeezing',
    ],
  ),
  velcro(
    'Base con correa de velcro',
    'Se fija con una correa: no hace falta cerrar los dedos.',
    Icons.linear_scale,
    <String>[
      'The base uses a hook-and-loop strap so no finger closure is needed',
      'Add a 20 mm wide slot for a hook-and-loop strap on each side',
    ],
  ),
  palm(
    'Soporte de palma',
    'La fuerza se transmite con la palma y el antebrazo, no con los dedos.',
    Icons.pan_tool,
    <String>[
      'The base transfers force through the palm and forearm instead of the fingers',
      'Keep the wrist in a neutral position while using the tool',
    ],
  ),
  forearm(
    'Correa de antebrazo',
    'Reparte el peso a lo largo del antebrazo: ideal para herramientas pesadas.',
    Icons.accessibility_new,
    <String>[
      'The base is a forearm cuff that distributes the tool weight along the forearm',
      'Use a two-strap cuff with a soft inner padding gap of 2 mm',
    ],
  );

  const GripBase(this.label, this.description, this.icon, this.promptFragments);

  final String label;
  final String description;
  final IconData icon;
  final List<String> promptFragments;
}

/// Capa 2 de ProGrip: el garfio funcional que hace de "mano mecánica".
enum GripHook {
  twoFingers(
    'Garfio de 2 dedos',
    'Se engancha con el índice y el corazón.',
    Icons.looks_two,
    <String>[
      'The hook is engaged with two fingers (index and middle)',
      'Hook opening 25 mm with rounded inner surface',
    ],
  ),
  threeFingers(
    'Garfio de 3 dedos',
    'Reparte el esfuerzo entre índice, corazón y anular.',
    Icons.looks_3,
    <String>[
      'The hook is engaged with three fingers to spread the load',
      'Hook opening 35 mm with a 4 mm radius on every contact surface',
    ],
  ),
  curvedHook(
    'Gancho curvo',
    'Gancho en J para colgar y tirar sin cerrar la mano.',
    Icons.turn_right,
    <String>[
      'The hook is a J-shaped curved hook for pulling and hanging',
      'Curve radius 30 mm and a 10 mm safety lip at the tip',
    ],
  ),
  pinch(
    'Pinza de presión',
    'Mantiene el objeto presionado contra la palma con un muelle.',
    Icons.compress,
    <String>[
      'The hook is a spring-loaded pinch clamp that presses the object against the palm',
      'Add a living-hinge spring printed in the same flexible material',
    ],
  ),
  thumbRest(
    'Apoyo de pulgar',
    'El pulgar hace de tope: útil para precisión, como un destornillador.',
    Icons.thumb_up,
    <String>[
      'The hook includes a thumb rest that acts as a mechanical stop for precision work',
      'Add a 15 mm wide thumb shelf with a rounded 6 mm fillet',
    ],
  );

  const GripHook(this.label, this.description, this.icon, this.promptFragments);

  final String label;
  final String description;
  final IconData icon;
  final List<String> promptFragments;
}

/// Capa 3 de ProGrip: el adaptador específico de cada herramienta.
enum ToolAdapter {
  hammer(
    'Martillo',
    Icons.hardware,
    'hammer',
    32,
    <String>[
      'The tool adapter is a hammer shaft clamp with a mechanical stop against the head',
      'Transmit the strike force along the arm without slipping',
    ],
  ),
  screwdriver(
    'Destornillador',
    Icons.rotate_right,
    'screwdriver',
    26,
    <String>[
      'The tool adapter is a hexagonal clamp that keeps the screwdriver aligned with the forearm',
      'Add a T-handle extension for extra torque',
    ],
  ),
  saw(
    'Sierra',
    Icons.content_cut,
    'hand saw',
    30,
    <String>[
      'The tool adapter clamps the saw handle with a mechanical stop so it cannot slide out',
      'Keep the saw blade aligned with the forearm to reduce wrist torque',
    ],
  ),
  drill(
    'Taladro',
    Icons.build_circle,
    'power drill',
    45,
    <String>[
      'The tool adapter is a drill cradle that rests on the forearm and dampens vibration',
      'Add a large trigger paddle that can be pressed with the whole hand',
    ],
  ),
  knife(
    'Cuchillo',
    Icons.cut,
    'kitchen knife',
    22,
    <String>[
      'The tool adapter clamps the knife handle and adds a finger guard towards the blade',
      'The knife must be usable without closing the fist',
    ],
  ),
  scissors(
    'Tijeras',
    Icons.content_cut_outlined,
    'pair of scissors',
    20,
    <String>[
      'The tool adapter connects the scissors to a palm-operated lever',
      'Add a spring return so the scissors open on their own',
    ],
  ),
  brush(
    'Pincel',
    Icons.brush,
    'paint brush',
    12,
    <String>[
      'The tool adapter is a sleeve that holds the brush with a strap instead of finger pressure',
      'Keep the brush angle adjustable in 15 degree steps',
    ],
  ),
  rake(
    'Rastrillo',
    Icons.grass,
    'garden rake',
    25,
    <String>[
      'The tool adapter is a quick-release clamp for the rake shaft',
      'The D-grip is pulled with the forearm keeping the wrist neutral',
    ],
  );

  const ToolAdapter(
    this.label,
    this.icon,
    this.toolName,
    this.defaultHandleDiameterMm,
    this.promptFragments,
  );

  final String label;
  final IconData icon;

  /// Nombre en inglés, para el prompt de Meshy.
  final String toolName;

  /// Diámetro de mango por defecto, para pre-rellenar la medida.
  final int defaultHandleDiameterMm;

  final List<String> promptFragments;
}

/// Configuración completa de una pieza ProGrip (las tres capas).
@immutable
class ProGripConfig {
  const ProGripConfig({
    this.base = GripBase.standard,
    this.hook = GripHook.twoFingers,
    this.adapter = ToolAdapter.screwdriver,
    this.material = 'PETG',
    this.notes = '',
    this.handMeasurements = const <Measurement>[],
  });

  final GripBase base;
  final GripHook hook;
  final ToolAdapter adapter;
  final String material;
  final String notes;

  /// Medidas de la mano del usuario, tomadas con `hand_landmarker` o a mano.
  final List<Measurement> handMeasurements;

  ProGripConfig copyWith({
    GripBase? base,
    GripHook? hook,
    ToolAdapter? adapter,
    String? material,
    String? notes,
    List<Measurement>? handMeasurements,
  }) {
    return ProGripConfig(
      base: base ?? this.base,
      hook: hook ?? this.hook,
      adapter: adapter ?? this.adapter,
      material: material ?? this.material,
      notes: notes ?? this.notes,
      handMeasurements: handMeasurements ?? this.handMeasurements,
    );
  }

  /// Título corto que resume la combinación elegida.
  String get title => 'ProGrip ${adapter.label} · ${hook.label}';

  /// Resumen legible de las tres capas.
  String get summary =>
      '${base.label} + ${hook.label} + adaptador de ${adapter.label.toLowerCase()}';

  /// Medidas sugeridas si el usuario aún no ha capturado ninguna.
  List<String> get suggestedMeasurements => <String>[
        'Diámetro del mango de ${adapter.label.toLowerCase()}',
        'Ancho de la palma',
        'Largo de los dedos',
      ];
}
