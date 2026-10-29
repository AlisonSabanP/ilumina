import 'package:flutter/material.dart';

import '../../medicion/modelos/measurement_models.dart';

/// Zona anatómica sobre la que se aplica la órtesis.
enum BodyZone {
  wrist('Muñeca', Icons.pan_tool_alt),
  hand('Mano y dedos', Icons.back_hand),
  elbow('Codo', Icons.sports_martial_arts),
  knee('Rodilla', Icons.airline_seat_legroom_extra),
  ankle('Tobillo y pie', Icons.directions_walk),
  neck('Cuello', Icons.face_retouching_natural);

  const BodyZone(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Tipo de férula u órtesis.
enum SplintType {
  rest(
    'Férula de reposo',
    'Inmoviliza por completo la articulación para favorecer la recuperación.',
    Icons.lock_outline,
    <String>[
      'The orthosis is a full rest splint that immobilises the joint completely',
      'Rigid shell with a soft inner liner of 2 mm',
    ],
  ),
  functional(
    'Férula funcional',
    'Limita el movimiento a un rango seguro sin bloquearlo del todo.',
    Icons.open_in_full,
    <String>[
      'The orthosis is a functional splint that limits the joint to a safe range of motion',
      'Add adjustable hard stops at 15, 30 and 45 degrees',
    ],
  ),
  immobilizer(
    'Inmovilizador rígido',
    'Soporte rígido para postoperatorio o traumatismo.',
    Icons.shield_outlined,
    <String>[
      'The orthosis is a rigid immobiliser for post-operative use',
      'Reinforce the shell with 4 mm ribs along the load direction',
    ],
  ),
  dynamic(
    'Ortesis dinámica',
    'Aplica una tracción suave y constante con un elástico o muelle.',
    Icons.linear_scale,
    <String>[
      'The orthosis is a dynamic orthosis that applies gentle continuous traction',
      'Add anchor points for elastic bands on both sides',
    ],
  ),
  fingerSeparator(
    'Separador de dedos',
    'Mantiene los dedos separados para evitar contracturas.',
    Icons.vertical_align_center,
    <String>[
      'The orthosis is a finger separator that keeps the fingers apart',
      'Individual finger channels 18 mm wide with rounded ends',
    ],
  );

  const SplintType(
    this.label,
    this.description,
    this.icon,
    this.promptFragments,
  );

  final String label;
  final String description;
  final IconData icon;
  final List<String> promptFragments;
}

/// Petición clínica completa del módulo OrthoSnap.
@immutable
class OrthoSnapRequest {
  const OrthoSnapRequest({
    this.bodyZone = BodyZone.wrist,
    this.splintType = SplintType.functional,
    this.diagnosis = '',
    this.affectedSide,
    this.notes = '',
    this.material = 'PETG',
    this.measurements = const <Measurement>[],
  });

  final BodyZone bodyZone;
  final SplintType splintType;

  /// Indicación clínica (texto libre del profesional).
  final String diagnosis;

  /// `'izquierda'` o `'derecha'`, o `null` si no aplica.
  final String? affectedSide;

  final String notes;
  final String material;
  final List<Measurement> measurements;

  OrthoSnapRequest copyWith({
    BodyZone? bodyZone,
    SplintType? splintType,
    String? diagnosis,
    String? affectedSide,
    bool clearAffectedSide = false,
    String? notes,
    String? material,
    List<Measurement>? measurements,
  }) {
    return OrthoSnapRequest(
      bodyZone: bodyZone ?? this.bodyZone,
      splintType: splintType ?? this.splintType,
      diagnosis: diagnosis ?? this.diagnosis,
      affectedSide: clearAffectedSide ? null : (affectedSide ?? this.affectedSide),
      notes: notes ?? this.notes,
      material: material ?? this.material,
      measurements: measurements ?? this.measurements,
    );
  }

  String get title => '${splintType.label} de ${bodyZone.label.toLowerCase()}';

  /// Medidas que un profesional debería aportar para esta zona.
  List<String> get suggestedMeasurements => switch (bodyZone) {
        BodyZone.wrist => const [
            'Perímetro de muñeca',
            'Perímetro de antebrazo',
            'Largo de palma',
          ],
        BodyZone.hand => const [
            'Ancho de palma',
            'Largo de palma',
            'Perímetro de muñeca',
          ],
        BodyZone.elbow => const [
            'Perímetro de brazo',
            'Perímetro de antebrazo',
            'Distancia codo-muñeca',
          ],
        BodyZone.knee => const [
            'Perímetro de rodilla',
            'Perímetro de muslo',
            'Largo de pierna',
          ],
        BodyZone.ankle => const [
            'Perímetro de tobillo',
            'Largo del pie',
            'Ancho del pie',
          ],
        BodyZone.neck => const [
            'Perímetro de cuello',
            'Alto de cuello',
          ],
      };

  /// Aviso clínico que siempre debe mostrarse en pantalla.
  static const String disclaimer =
      'OrthoSnap es una ayuda de diseño, no un producto sanitario. '
      'Toda órtesis debe ser validada por un profesional sanitario colegiado '
      'antes de su uso en un paciente.';
}
