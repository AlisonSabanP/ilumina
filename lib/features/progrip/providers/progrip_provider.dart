import 'package:flutter/foundation.dart';

import '../../medicion/modelos/measurement_models.dart';
import '../../formulario/modelos/formulario_modelos.dart';
import '../modelos/progrip_modelos.dart';

/// Estado del configurador ProGrip.
///
/// ProGrip construye una prótesis de mano en **tres capas** y cada selección
/// cambia el prompt que se enviará a Meshy:
///
///   1. [GripBase]     -> cómo se acopla a la mano o al brazo.
///   2. [GripHook]     -> el garfio funcional que sustituye al agarre.
///   3. [ToolAdapter]  -> el adaptador de la herramienta concreta.
///
/// Las medidas de la mano se toman de la pantalla de medición y se filtran aquí
/// para quedarse solo con las relevantes (ancho de palma, apertura de agarre).
class ProGripProvider extends ChangeNotifier {
  GripBase _base = GripBase.standard;
  GripHook _hook = GripHook.twoFingers;
  ToolAdapter _adapter = ToolAdapter.screwdriver;
  String _material = 'PETG';
  String _notes = '';
  final List<Measurement> _measurements = <Measurement>[];

  // --- Lectura ---------------------------------------------------------------

  GripBase get base => _base;
  GripHook get hook => _hook;
  ToolAdapter get adapter => _adapter;
  String get material => _material;
  String get notes => _notes;
  List<Measurement> get measurements => List.unmodifiable(_measurements);

  ProGripConfig get config => ProGripConfig(
        base: _base,
        hook: _hook,
        adapter: _adapter,
        material: _material,
        notes: _notes,
        handMeasurements: _measurements,
      );

  /// `true` cuando la combinación elegida tiene sentido.
  ///
  /// Dos avisos útiles para el usuario:
  ///  * Un adaptador pesado (taladro) pide un acople de antebrazo.
  ///  * Un garfio de dos dedos no es suficiente para una sierra.
  List<String> get compatibilityWarnings {
    final warnings = <String>[];

    if (_adapter == ToolAdapter.drill && _base != GripBase.forearm) {
      warnings.add(
        'Un taladro pesa: considera el acople de antebrazo para repartir el peso.',
      );
    }
    if (_adapter == ToolAdapter.saw &&
        (_hook == GripHook.twoFingers || _hook == GripHook.thumbRest)) {
      warnings.add(
        'Una sierra necesita un agarre firme: el garfio curvo o la pinza de '
        'presión evitan que se suelte durante el corte.',
      );
    }
    if (_hook == GripHook.pinch && _base == GripBase.standard) {
      warnings.add(
        'La pinza de presión funciona mejor con correa de velcro o soporte de palma.',
      );
    }
    return warnings;
  }

  /// Medidas que faltan para esta configuración concreta.
  List<String> get missingMeasurements {
    final suggested = config.suggestedMeasurements;
    final present = _measurements.map((m) => m.label.toLowerCase()).toSet();
    return suggested
        .where((s) => !present.contains(s.toLowerCase()))
        .toList(growable: false);
  }

  // --- Escritura -------------------------------------------------------------

  void setBase(GripBase value) {
    if (_base == value) return;
    _base = value;
    notifyListeners();
  }

  void setHook(GripHook value) {
    if (_hook == value) return;
    _hook = value;
    notifyListeners();
  }

  void setAdapter(ToolAdapter value) {
    if (_adapter == value) return;
    _adapter = value;
    notifyListeners();
  }

  void setMaterial(String value) {
    if (_material == value) return;
    _material = value;
    notifyListeners();
  }

  void setNotes(String value) {
    if (_notes == value) return;
    _notes = value;
    notifyListeners();
  }

  void addMeasurement(Measurement measurement) {
    final index = _measurements.indexWhere(
      (m) => m.label.toLowerCase() == measurement.label.toLowerCase(),
    );
    if (index >= 0) {
      _measurements[index] = measurement;
    } else {
      _measurements.add(measurement);
    }
    notifyListeners();
  }

  void removeMeasurement(String id) {
    _measurements.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  void reset() {
    _base = GripBase.standard;
    _hook = GripHook.twoFingers;
    _adapter = ToolAdapter.screwdriver;
    _material = 'PETG';
    _notes = '';
    _measurements.clear();
    notifyListeners();
  }

  /// Crea la medida del diámetro del mango con el valor por defecto del
  /// adaptador, para que el usuario pueda ajustarla después.
  void seedHandleDiameter() {
    final label = 'Diámetro del mango de ${_adapter.label.toLowerCase()}';
    final exists = _measurements.any(
      (m) => m.label.toLowerCase() == label.toLowerCase(),
    );
    if (exists) return;
    _measurements.add(
      Measurement(
        id: 'progrip_seed_${DateTime.now().microsecondsSinceEpoch}',
        label: label,
        valueCm: _adapter.defaultHandleDiameterMm / 10,
        kind: MeasurementKind.manualDiameter,
        source: MeasurementSource.manual,
        timestamp: DateTime.now(),
        note: 'Valor orientativo: ajústalo con tu herramienta',
      ),
    );
    notifyListeners();
  }

  /// Materiales admitidos para piezas ProGrip.
  static List<String> get materials => MaterialQuestion.options;
}
