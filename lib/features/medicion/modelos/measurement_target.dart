import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../formulario/modelos/formulario_provider.dart';
import '../../orthosnap/providers/auth_provider.dart';
import 'measurement_models.dart';

/// Dónde se guardan las medidas que se toman.
///
/// Lumina tiene dos flujos que miden cosas distintas y las guardan en sitios
/// distintos: el formulario inteligente (diseño personal) y la ficha clínica de
/// OrthoSnap (paciente de un profesional). Sin esta distinción, medir desde la
/// ficha clínica guardaba la medida en el formulario y la órtesis se generaba
/// sin medidas.
enum MeasurementTarget {
  /// Formulario inteligente: diseños para uno mismo.
  formulario('Formulario'),

  /// Ficha clínica de OrthoSnap: medidas del paciente.
  clinico('Ficha clínica');

  const MeasurementTarget(this.label);

  final String label;
}

/// Lee y escribe medidas en el destino elegido.
///
/// Se centraliza aquí para que las pantallas de medición (mano y manual) no
/// tengan que saber en qué provider vive cada lista.
abstract final class MeasurementStore {
  /// Medidas guardadas actualmente en [target].
  ///
  /// Usa `watch`, así que debe llamarse desde `build`: el widget se reconstruye
  /// cuando cambia la lista.
  static List<Measurement> read(BuildContext context, MeasurementTarget target) {
    return switch (target) {
      MeasurementTarget.formulario =>
        context.watch<FormularioProvider>().measurements,
      MeasurementTarget.clinico =>
        context.watch<AuthProvider>().request.measurements,
    };
  }

  /// Añade o reemplaza una medida en [target].
  static void add(
    BuildContext context,
    MeasurementTarget target,
    Measurement measurement,
  ) {
    switch (target) {
      case MeasurementTarget.formulario:
        context.read<FormularioProvider>().upsertMeasurement(measurement);
      case MeasurementTarget.clinico:
        context.read<AuthProvider>().addMeasurement(measurement);
    }
  }

  /// Elimina la medida con [id] de [target].
  static void remove(BuildContext context, MeasurementTarget target, String id) {
    switch (target) {
      case MeasurementTarget.formulario:
        context.read<FormularioProvider>().removeMeasurement(id);
      case MeasurementTarget.clinico:
        context.read<AuthProvider>().removeMeasurement(id);
    }
  }

  /// Borra todas las medidas de [target].
  static void clear(BuildContext context, MeasurementTarget target) {
    switch (target) {
      case MeasurementTarget.formulario:
        context.read<FormularioProvider>().clearMeasurements();
      case MeasurementTarget.clinico:
        context.read<AuthProvider>().clearMeasurements();
    }
  }
}
