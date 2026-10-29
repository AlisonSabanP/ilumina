import 'package:flutter/material.dart';

/// Perfil de necesidad elegido al inicio del formulario.
///
/// Es la raíz del árbol de preguntas: cada perfil tiene su propio conjunto de
/// preguntas ramificadas.
enum NeedProfile {
  motriz(
    'Motriz',
    'Dificultad para agarrar, sostener o aplicar fuerza con las manos.',
    Icons.pan_tool_alt,
  ),
  visual(
    'Visual',
    'Baja visión o ceguera: necesitas referencias táctiles o en braille.',
    Icons.visibility,
  ),
  cognitiva(
    'Cognitiva / Sensibilidad',
    'Autismo, TDAH o sensibilidad sensorial: importan la previsibilidad y la textura.',
    Icons.psychology_alt,
  );

  const NeedProfile(this.label, this.description, this.pictogram);

  final String label;
  final String description;
  final IconData pictogram;
}

/// Una opción dentro de una pregunta.
///
/// Si [nextQuestionId] es nulo, la opción es terminal y aporta una
/// [recommendation] que cierra el formulario.
@immutable
class FormOption {
  const FormOption({
    required this.id,
    required this.label,
    this.description,
    this.pictogram,
    this.nextQuestionId,
    this.recommendation,
    this.promptFragments = const <String>[],
    this.suggestedMeasurements = const <String>[],
  }) : assert(
          nextQuestionId != null || recommendation != null,
          'Una opción terminal debe aportar una recomendación',
        );

  final String id;
  final String label;
  final String? description;
  final IconData? pictogram;

  /// Siguiente pregunta del árbol, o `null` si esta opción cierra el flujo.
  final String? nextQuestionId;

  /// Recomendación final (solo en opciones terminales).
  final ToolRecommendation? recommendation;

  /// Frases que se añadirán al prompt de Meshy.
  final List<String> promptFragments;

  /// Medidas que conviene capturar para esta opción.
  final List<String> suggestedMeasurements;

  bool get isTerminal => nextQuestionId == null;
}

/// Una pregunta del árbol, con sus opciones.
@immutable
class FormQuestion {
  const FormQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    this.helper,
    this.pictogram,
  });

  final String id;
  final String prompt;
  final String? helper;
  final IconData? pictogram;
  final List<FormOption> options;

  FormOption? optionById(String optionId) {
    for (final option in options) {
      if (option.id == optionId) return option;
    }
    return null;
  }
}

/// Herramienta o modelo recomendado al cerrar el formulario.
@immutable
class ToolRecommendation {
  const ToolRecommendation({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.promptSeed,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;

  /// Frase inicial del prompt que describe el objeto a generar.
  final String promptSeed;
}

/// Árbol de decisión completo, separado en ramas por perfil.
abstract final class FormTree {
  /// Primera pregunta de cada perfil.
  static String firstQuestionId(NeedProfile profile) => switch (profile) {
        NeedProfile.motriz => 'm_need',
        NeedProfile.visual => 'v_need',
        NeedProfile.cognitiva => 'c_need',
      };

  static FormQuestion? question(String? id) => id == null ? null : _all[id];

  static const Map<String, FormQuestion> _all = <String, FormQuestion>{
    // ======================= RAMA MOTRIZ =======================
    'm_need': FormQuestion(
      id: 'm_need',
      prompt: '¿Qué necesitas fabricar?',
      helper: 'Elige la opción que más se parezca a lo que buscas.',
      pictogram: Icons.help_outline,
      options: [
        FormOption(
          id: 'm_tool',
          label: 'Adaptador para una herramienta',
          description: 'Para usar martillo, destornillador, sierra... con poco agarre.',
          pictogram: Icons.handyman,
          nextQuestionId: 'm_tool_kind',
          suggestedMeasurements: [
            'Diámetro del mango de la herramienta',
            'Largo de la palma',
          ],
        ),
        FormOption(
          id: 'm_grip',
          label: 'Engrosador de mango',
          description: 'Un manguito más grueso para agarrar mejor lápices o cubiertos.',
          pictogram: Icons.linear_scale,
          nextQuestionId: 'm_fingers',
          suggestedMeasurements: ['Diámetro del objeto', 'Largo de los dedos'],
        ),
        FormOption(
          id: 'm_opener',
          label: 'Abridor o útil de agarre',
          description: 'Para abrir tapones, latas o envases con poca fuerza.',
          pictogram: Icons.local_drink,
          nextQuestionId: 'm_strength',
          suggestedMeasurements: ['Diámetro del tapón', 'Ancho de la mano'],
        ),
        FormOption(
          id: 'm_support',
          label: 'Soporte o estabilizador',
          description: 'Para fijar un objeto y no tener que sujetarlo.',
          pictogram: Icons.grid_view,
          nextQuestionId: 'm_support_where',
          suggestedMeasurements: ['Ancho del objeto', 'Alto del objeto'],
        ),
      ],
    ),
    'm_tool_kind': FormQuestion(
      id: 'm_tool_kind',
      prompt: '¿Para qué herramienta?',
      helper: 'El adaptador se ajusta al mango de la herramienta elegida.',
      pictogram: Icons.construction,
      options: [
        FormOption(
          id: 'm_tool_hammer',
          label: 'Martillo',
          pictogram: Icons.hardware,
          recommendation: ToolRecommendation(
            id: 'grip_martillo',
            title: 'Adaptador de agarre para martillo',
            description:
                'Manguito de agarre con garfio de dos dedos que fija el martillo a la mano.',
            icon: Icons.hardware,
            promptSeed:
                'Custom 3D printable tool adapter for a hammer for a person with limited grip strength',
          ),
          promptFragments: [
            'The adapter must allow a two-finger hold and transmit the hammer strike force without slipping',
            'Include a rounded palm rest and a fail-safe strap hole',
          ],
        ),
        FormOption(
          id: 'm_tool_screwdriver',
          label: 'Destornillador',
          pictogram: Icons.rotate_right,
          recommendation: ToolRecommendation(
            id: 'grip_destornillador',
            title: 'Adaptador de agarre para destornillador',
            description:
                'Garfio de pinza que mantiene el destornillador alineado con el antebrazo.',
            icon: Icons.rotate_right,
            promptSeed:
                'Custom 3D printable tool adapter for a screwdriver for a person with limited grip strength',
          ),
          promptFragments: [
            'The grip must keep the screwdriver aligned with the forearm to reduce wrist torque',
            'Add a T-shaped handle extension for extra leverage',
          ],
        ),
        FormOption(
          id: 'm_tool_saw',
          label: 'Sierra',
          pictogram: Icons.content_cut,
          recommendation: ToolRecommendation(
            id: 'grip_sierra',
            title: 'Adaptador de agarre para sierra',
            description:
                'Garfio curvo con tope de seguridad para evitar que la sierra se suelte durante el corte.',
            icon: Icons.content_cut,
            promptSeed:
                'Custom 3D printable tool adapter for a hand saw for a person with limited grip strength',
          ),
          promptFragments: [
            'The handle must include a mechanical stop so the saw cannot slide out under load',
            'Surface must be smooth on the palm side and textured on the fingers side',
          ],
        ),
        FormOption(
          id: 'm_tool_knife',
          label: 'Cuchillo',
          pictogram: Icons.cut,
          recommendation: ToolRecommendation(
            id: 'grip_cuchillo',
            title: 'Adaptador de agarre para cuchillo',
            description:
                'Garfio de gancho curvo con protección de dedos para cortar sin cerrar la mano.',
            icon: Icons.cut,
            promptSeed:
                'Custom 3D printable safety handle for a kitchen knife for a person with limited grip strength',
          ),
          promptFragments: [
            'Include a finger guard that prevents the hand from sliding toward the blade',
            'The handle must be usable without closing the fist',
          ],
        ),
        FormOption(
          id: 'm_tool_scissors',
          label: 'Tijeras',
          pictogram: Icons.content_cut_outlined,
          recommendation: ToolRecommendation(
            id: 'grip_tijeras',
            title: 'Adaptador de agarre para tijeras',
            description:
                'Palanca que permite accionar las tijeras con la palma en lugar de los dedos.',
            icon: Icons.content_cut_outlined,
            promptSeed:
                'Custom 3D printable lever adapter for scissors for a person with limited grip strength',
          ),
          promptFragments: [
            'The lever must be operated with the palm, not with finger flexion',
            'Add a spring return so the scissors open on their own',
          ],
        ),
        FormOption(
          id: 'm_tool_brush',
          label: 'Pincel',
          pictogram: Icons.brush,
          recommendation: ToolRecommendation(
            id: 'grip_pincel',
            title: 'Adaptador de agarre para pincel',
            description:
                'Manguito ergonómico que fija el pincel a la mano con una correa suave.',
            icon: Icons.brush,
            promptSeed:
                'Custom 3D printable ergonomic sleeve that holds a paint brush in the hand for a person with limited grip strength',
          ),
          promptFragments: [
            'The sleeve must hold the brush with a strap instead of finger pressure',
            'Keep the brush angle adjustable in 15 degree steps',
          ],
        ),
        FormOption(
          id: 'm_tool_rake',
          label: 'Rastrillo',
          pictogram: Icons.grass,
          recommendation: ToolRecommendation(
            id: 'grip_rastrillo',
            title: 'Adaptador de agarre para rastrillo',
            description:
                'Acople en D que permite tirar del rastrillo con el antebrazo en lugar de la mano.',
            icon: Icons.grass,
            promptSeed:
                'Custom 3D printable D-grip adapter for a garden rake for a person with limited grip strength',
          ),
          promptFragments: [
            'The D-grip must be pulled with the forearm, keeping the wrist in a neutral position',
            'Add a quick-release clamp compatible with a 25 mm diameter shaft',
          ],
        ),
      ],
    ),
    'm_fingers': FormQuestion(
      id: 'm_fingers',
      prompt: '¿Cuántos dedos puedes usar para agarrar?',
      helper: 'Así calculamos el grosor y la forma del manguito.',
      pictogram: Icons.back_hand,
      options: [
        FormOption(
          id: 'm_fingers_1',
          label: 'Un dedo o ninguno',
          pictogram: Icons.looks_one,
          recommendation: ToolRecommendation(
            id: 'grip_one_finger',
            title: 'Engrosador con correa de palma',
            description:
                'Manguito grueso con correa que se acciona con la palma, sin cerrar los dedos.',
            icon: Icons.looks_one,
            promptSeed:
                'Custom 3D printable thick pencil grip sleeve that is held with the palm for a person who cannot close their fingers',
          ),
          promptFragments: [
            'The user cannot close their fingers, so a palm strap must hold the sleeve',
            'Diameter must be at least 4 cm so the palm can press it',
          ],
          suggestedMeasurements: ['Ancho de la palma', 'Largo del objeto'],
        ),
        FormOption(
          id: 'm_fingers_23',
          label: 'Dos o tres dedos',
          pictogram: Icons.looks_two,
          recommendation: ToolRecommendation(
            id: 'grip_two_fingers',
            title: 'Engrosador con garfio de dos dedos',
            description:
                'Manguito de 4 a 5 cm con garfio que se engancha con dos o tres dedos.',
            icon: Icons.looks_two,
            promptSeed:
                'Custom 3D printable pencil grip sleeve with a two-finger hook for a person with limited grip strength',
          ),
          promptFragments: [
            'The hook must engage with two or three fingers and keep the wrist relaxed',
            'Handle diameter around 4.5 cm with a smooth, non-abrasive surface',
          ],
          suggestedMeasurements: ['Diámetro del objeto', 'Largo de los dedos'],
        ),
        FormOption(
          id: 'm_fingers_full',
          label: 'Mano completa, pero con poca fuerza',
          pictogram: Icons.back_hand,
          recommendation: ToolRecommendation(
            id: 'grip_full_hand',
            title: 'Engrosador de mano completa',
            description:
                'Manguito de 3,5 cm con superficie antideslizante para toda la mano.',
            icon: Icons.back_hand,
            promptSeed:
                'Custom 3D printable ergonomic grip sleeve for a full hand with reduced strength',
          ),
          promptFragments: [
            'Add a soft-touch ribbed surface to reduce the force needed to hold it',
            'Include a thumb rest that prevents the object from rotating',
          ],
          suggestedMeasurements: ['Diámetro del objeto', 'Largo de la mano'],
        ),
      ],
    ),
    'm_strength': FormQuestion(
      id: 'm_strength',
      prompt: '¿Cuánta fuerza tienes en la mano?',
      helper: 'Determina la palanca y el grosor del útil.',
      pictogram: Icons.fitness_center,
      options: [
        FormOption(
          id: 'm_strength_low',
          label: 'Muy poca',
          pictogram: Icons.trending_down,
          recommendation: ToolRecommendation(
            id: 'opener_long_lever',
            title: 'Abridor de palanca larga',
            description:
                'Palanca de 20 cm que multiplica la fuerza y se apoya en la mesa.',
            icon: Icons.trending_down,
            promptSeed:
                'Custom 3D printable long-lever bottle and jar opener that rests on a table for a person with very low hand strength',
          ),
          promptFragments: [
            'The lever must be at least 20 cm long and rest on a table so no hand strength is needed',
            'Add a wide base with rubber pads to prevent slipping',
          ],
          suggestedMeasurements: ['Diámetro del tapón', 'Ancho de la mano'],
        ),
        FormOption(
          id: 'm_strength_medium',
          label: 'Algo de fuerza',
          pictogram: Icons.trending_flat,
          recommendation: ToolRecommendation(
            id: 'opener_grip',
            title: 'Abridor con mango ergonómico',
            description: 'Abridor de mano con mango de 4 cm y superficie antideslizante.',
            icon: Icons.trending_flat,
            promptSeed:
                'Custom 3D printable ergonomic jar opener with a 4 cm handle for a person with reduced hand strength',
          ),
          promptFragments: [
            'Use a conical inner surface so the same opener fits several lid diameters',
            'Add a hanging hole so it can be stored within reach',
          ],
          suggestedMeasurements: ['Diámetro del tapón'],
        ),
        FormOption(
          id: 'm_strength_high',
          label: 'Fuerza suficiente, pero agarre inestable',
          pictogram: Icons.trending_up,
          recommendation: ToolRecommendation(
            id: 'opener_stabilizer',
            title: 'Abridor con estabilizador de muñeca',
            description: 'Abridor que mantiene la muñeca recta y evita giros bruscos.',
            icon: Icons.trending_up,
            promptSeed:
                'Custom 3D printable jar opener with a wrist stabilizer for a person with an unstable grip',
          ),
          promptFragments: [
            'Keep the wrist in a neutral position while turning the lid',
            'Add a forearm brace to avoid sudden wrist rotation',
          ],
          suggestedMeasurements: ['Diámetro del tapón', 'Largo del antebrazo'],
        ),
      ],
    ),
    'm_support_where': FormQuestion(
      id: 'm_support_where',
      prompt: '¿Dónde lo vas a usar?',
      pictogram: Icons.place,
      options: [
        FormOption(
          id: 'm_support_table',
          label: 'En la mesa',
          pictogram: Icons.table_restaurant,
          recommendation: ToolRecommendation(
            id: 'support_table',
            title: 'Soporte de mesa con ventosa',
            description:
                'Base que se fija a la mesa y sujeta el objeto con una pinza suave.',
            icon: Icons.table_restaurant,
            promptSeed:
                'Custom 3D printable table clamp support that holds an object for a person with limited hand mobility',
          ),
          promptFragments: [
            'Include a suction base and a spring clamp with a soft pad',
            'The clamp must open with a single downward press',
          ],
          suggestedMeasurements: ['Ancho del objeto', 'Alto del objeto'],
        ),
        FormOption(
          id: 'm_support_wheelchair',
          label: 'En la silla de ruedas',
          pictogram: Icons.accessible,
          recommendation: ToolRecommendation(
            id: 'support_wheelchair',
            title: 'Soporte para tubo de silla de ruedas',
            description:
                'Abrazadera para tubos de 22 a 25 mm con bandeja orientable.',
            icon: Icons.accessible,
            promptSeed:
                'Custom 3D printable clamp for a wheelchair tube that holds a tray or an object',
          ),
          promptFragments: [
            'Clamp must fit tubes between 22 mm and 25 mm with a single screw',
            'Add a 90 degree rotating tray with a raised lip',
          ],
          suggestedMeasurements: ['Diámetro del tubo', 'Ancho de la bandeja'],
        ),
        FormOption(
          id: 'm_support_bed',
          label: 'En la cama',
          pictogram: Icons.bed,
          recommendation: ToolRecommendation(
            id: 'support_bed',
            title: 'Soporte de cama inclinable',
            description: 'Brazo articulado que acerca el objeto sin levantarse.',
            icon: Icons.bed,
            promptSeed:
                'Custom 3D printable articulated bed support arm that brings an object closer to the user',
          ),
          promptFragments: [
            'The arm must be light, articulated and lock in position with one hand',
            'Add a wide flat base that does not tip over',
          ],
          suggestedMeasurements: ['Distancia a la cama', 'Alto del objeto'],
        ),
      ],
    ),

    // ======================= RAMA VISUAL =======================
    'v_need': FormQuestion(
      id: 'v_need',
      prompt: '¿Qué tipo de ayuda necesitas?',
      helper: 'Pensado para identificar objetos y espacios sin depender de la vista.',
      pictogram: Icons.help_outline,
      options: [
        FormOption(
          id: 'v_braille',
          label: 'Etiquetas en braille',
          description: 'Para marcar botes, cajones o medicamentos.',
          pictogram: Icons.dialpad,
          recommendation: ToolRecommendation(
            id: 'braille_label',
            title: 'Etiqueta en braille con relieve',
            description:
                'Placa con caracteres braille en relieve y un gancho para sujetarla al envase.',
            icon: Icons.dialpad,
            promptSeed:
                'Custom 3D printable braille label tag with raised dots and a snap hook for a blind user',
          ),
          promptFragments: [
            'Braille dots must be 1.5 mm high with the standard 2.5 mm dot spacing',
            'Add a tactile orientation notch so the label can be read by touch in the dark',
          ],
          suggestedMeasurements: ['Ancho de la etiqueta', 'Largo de la etiqueta'],
        ),
        FormOption(
          id: 'v_tactile',
          label: 'Marcador táctil para aparatos',
          description: 'Un relieve que permite reconocer botones o mandos.',
          pictogram: Icons.touch_app,
          recommendation: ToolRecommendation(
            id: 'tactile_marker',
            title: 'Marcador táctil con relieve',
            description:
                'Pieza adhesiva con relieve distinto para cada botón del aparato.',
            icon: Icons.touch_app,
            promptSeed:
                'Custom 3D printable tactile marker set with different raised shapes for appliance buttons for a blind user',
          ),
          promptFragments: [
            'Each marker must have a clearly different raised shape: dot, bar, ring and triangle',
            'Use a 0.8 mm relief height so it can be felt through a finger',
          ],
          suggestedMeasurements: ['Diámetro del botón'],
        ),
        FormOption(
          id: 'v_organizer',
          label: 'Organizador con relieve',
          description: 'Bandeja con compartimentos identificables al tacto.',
          pictogram: Icons.grid_on,
          recommendation: ToolRecommendation(
            id: 'tactile_organizer',
            title: 'Organizador táctil',
            description:
                'Bandeja con compartimentos separados por relieves diferentes.',
            icon: Icons.grid_on,
            promptSeed:
                'Custom 3D printable tactile organizer tray with compartments identified by different raised patterns for a blind user',
          ),
          promptFragments: [
            'Each compartment must have a different raised border pattern',
            'Add a raised corner so the tray orientation is obvious by touch',
          ],
          suggestedMeasurements: [
            'Ancho de la bandeja',
            'Largo de la bandeja',
            'Alto de la bandeja',
          ],
        ),
        FormOption(
          id: 'v_guide',
          label: 'Guía para escribir o firmar',
          description: 'Plantilla con ranuras para firmar en el sitio correcto.',
          pictogram: Icons.draw,
          recommendation: ToolRecommendation(
            id: 'writing_guide',
            title: 'Guía de firma con ranuras',
            description:
                'Plantilla rígida con ventana de firma y marcas táctiles de alineación.',
            icon: Icons.draw,
            promptSeed:
                'Custom 3D printable signature writing guide with a tactile window for a blind user',
          ),
          promptFragments: [
            'Include tactile alignment marks on the left and top edges',
            'The signature window must be 8 cm wide and 3 cm high',
          ],
          suggestedMeasurements: ['Ancho de la hoja'],
        ),
      ],
    ),

    // ================ RAMA COGNITIVA / SENSIBILIDAD ================
    'c_need': FormQuestion(
      id: 'c_need',
      prompt: '¿Qué te ayudaría más?',
      helper: 'Objetos previsibles, con textura agradable y sin sorpresas.',
      pictogram: Icons.help_outline,
      options: [
        FormOption(
          id: 'c_fidget',
          label: 'Objeto para regularme (fidget)',
          description: 'Para las manos, cuando necesito calmarme.',
          pictogram: Icons.rotate_90_degrees_ccw,
          nextQuestionId: 'c_texture',
          suggestedMeasurements: ['Largo de la mano', 'Ancho de la mano'],
        ),
        FormOption(
          id: 'c_routine',
          label: 'Secuencia de rutina con pictogramas',
          description: 'Piezas que se colocan en orden para seguir una rutina.',
          pictogram: Icons.view_timeline,
          recommendation: ToolRecommendation(
            id: 'routine_steps',
            title: 'Secuencia de rutina en relieve',
            description:
                'Piezas encajables que representan cada paso del día, en orden fijo.',
            icon: Icons.view_timeline,
            promptSeed:
                'Custom 3D printable routine sequence tiles with simple raised pictograms for an autistic user',
          ),
          promptFragments: [
            'Use simple, high-contrast, unambiguous raised pictograms',
            'Each tile must only fit in its own position so the order cannot be changed by mistake',
          ],
          suggestedMeasurements: ['Ancho de la pieza'],
        ),
        FormOption(
          id: 'c_transition',
          label: 'Objeto de transición',
          description: 'Un objeto que acompaña entre actividades.',
          pictogram: Icons.emoji_objects,
          nextQuestionId: 'c_texture',
          suggestedMeasurements: ['Largo de la mano'],
        ),
        FormOption(
          id: 'c_noise',
          label: 'Atenuador de ruido o vibración',
          description: 'Piezas que amortiguan sonidos o golpes repetitivos.',
          pictogram: Icons.volume_off,
          recommendation: ToolRecommendation(
            id: 'noise_damper',
            title: 'Amortiguador de ruido de puertas y muebles',
            description: 'Cuñas y topes flexibles que evitan golpes y chirridos.',
            icon: Icons.volume_off,
            promptSeed:
                'Custom 3D printable flexible door and furniture damper set to reduce repetitive noise for a noise-sensitive user',
          ),
          promptFragments: [
            'Use TPU-like flexible geometry so the parts absorb impact instead of bouncing',
            'Provide three sizes: door wedge, drawer stop and chair glide',
          ],
          suggestedMeasurements: ['Grosor de la puerta'],
        ),
      ],
    ),
    'c_texture': FormQuestion(
      id: 'c_texture',
      prompt: '¿Qué textura te resulta agradable al tacto?',
      helper: 'La superficie es tan importante como la forma.',
      pictogram: Icons.texture,
      options: [
        FormOption(
          id: 'c_texture_smooth',
          label: 'Lisa y sin relieve',
          pictogram: Icons.circle_outlined,
          recommendation: ToolRecommendation(
            id: 'fidget_smooth',
            title: 'Fidget de superficie lisa',
            description:
                'Pieza de superficie lisa con movimiento suave y sin piezas que se separen.',
            icon: Icons.circle_outlined,
            promptSeed:
                'Custom 3D printable smooth-surface fidget toy with a quiet, soft movement for a tactile-sensitive autistic user',
          ),
          promptFragments: [
            'The surface must be completely smooth with no ridges, no sharp edges and no visible layer lines',
            'The movement must be silent and slow, with no loose parts',
          ],
        ),
        FormOption(
          id: 'c_texture_soft',
          label: 'Suave con relieve redondeado',
          pictogram: Icons.grain,
          recommendation: ToolRecommendation(
            id: 'fidget_soft_relief',
            title: 'Fidget con relieve redondeado',
            description: 'Pieza con bolitas redondeadas para recorrer con los dedos.',
            icon: Icons.grain,
            promptSeed:
                'Custom 3D printable fidget toy with rounded bumps that can be traced with the fingers for an autistic user',
          ),
          promptFragments: [
            'Bumps must be rounded, 3 mm high and evenly spaced',
            'No part of the surface may catch on the skin or on clothing',
          ],
        ),
        FormOption(
          id: 'c_texture_deep',
          label: 'Relieve profundo y marcado',
          pictogram: Icons.waves,
          recommendation: ToolRecommendation(
            id: 'fidget_deep_relief',
            title: 'Fidget con relieve profundo',
            description: 'Pieza con canales profundos que se siguen con la uña.',
            icon: Icons.waves,
            promptSeed:
                'Custom 3D printable fidget toy with deep tactile grooves for an autistic user who seeks strong tactile input',
          ),
          promptFragments: [
            'Grooves must be 2 mm deep with rounded inner corners',
            'The shape must be graspable with one hand without squeezing',
          ],
        ),
      ],
    ),
  };
}
