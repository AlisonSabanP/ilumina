import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../formulario/modelos/formulario_provider.dart';
import 'measurement_models.dart';

/// Dónde se guardan las medidas que se toman.
///
/// Hoy solo hay un destino, el formulario inteligente. El enum se mantiene
/// porque las pantallas de medición lo reciben como parámetro y así añadir otro
/// destino (por ejemplo una ficha clínica) no obliga a cambiar sus firmas.
enum MeasurementTarget {
  /// Formulario inteligente: diseños para uno mismo.
  formulario('Formulario');

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
    }
  }

  /// Elimina la medida con [id] de [target].
  static void remove(BuildContext context, MeasurementTarget target, String id) {
    switch (target) {
      case MeasurementTarget.formulario:
        context.read<FormularioProvider>().removeMeasurement(id);
    }
  }

  /// Borra todas las medidas de [target].
  static void clear(BuildContext context, MeasurementTarget target) {
    switch (target) {
      case MeasurementTarget.formulario:
        context.read<FormularioProvider>().clearMeasurements();
    }
  }
}
