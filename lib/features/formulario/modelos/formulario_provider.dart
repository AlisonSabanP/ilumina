import 'package:flutter/foundation.dart';

import '../../../shared/servicios/braille_service.dart';
import '../../medicion/modelos/measurement_models.dart';
import 'formulario_modelos.dart';

/// Estado del formulario inteligente ramificado.
///
/// El formulario es un árbol: se guardan las respuestas por pregunta y se
/// navega con una pila de preguntas visitadas para poder retroceder sin perder
/// las respuestas ya dadas.
class FormularioProvider extends ChangeNotifier {
  NeedProfile? _profile;
  final Map<String, String> _answers = <String, String>{};
  final List<String> _history = <String>[];
  String? _currentQuestionId;
  String _material = FormTree.defaultMaterial;
  ToolRecommendation? _recommendation;
  final List<Measurement> _measurements = <Measurement>[];
  String _brailleText = '';
  bool _finished = false;

  // --- Lectura ---------------------------------------------------------------

  NeedProfile? get profile => _profile;

  /// `true` mientras no se haya elegido perfil.
  bool get needsProfile => _profile == null;

  String? get currentQuestionId => _currentQuestionId;

  FormQuestion? get currentQuestion => FormTree.question(_currentQuestionId);

  String get material => _material;

  /// Recomendación final. Solo es no nula al terminar el flujo.
  ToolRecommendation? get recommendation => _recommendation;

  List<Measurement> get measurements => List.unmodifiable(_measurements);

  String get brailleText => _brailleText;

  /// Etiqueta Braille efectiva que se grabará en la pieza.
  ///
  /// Si el usuario no ha escrito nada, se genera sola a partir de la
  /// recomendación ("Adaptador ProGrip para sierra" -> "adaptador progrip para
  /// sierra"). Así toda pieza sale etiquetada sin trabajo extra, que es lo que
  /// necesita alguien que no ve el objeto.
  String get brailleLabel {
    if (_brailleText.trim().isNotEmpty) {
      return BrailleService.prepareLabel(_brailleText);
    }
    final title = _recommendation?.title;
    if (title == null || title.trim().isEmpty) return '';
    return BrailleService.labelFromTitle(title);
  }

  /// `true` si la etiqueta la ha escrito el usuario.
  bool get hasCustomBrailleLabel => _brailleText.trim().isNotEmpty;

  bool get finished => _finished;

  /// `true` cuando ya hay una recomendación y medidas suficientes para generar.
  bool get canGenerate => _recommendation != null;

  /// `true` si se puede retroceder.
  bool get canGoBack => _history.isNotEmpty;

  /// Respuestas dadas, en orden de aparición.
  List<MapEntry<String, String>> get answerEntries => _answers.entries.toList();

  /// Texto legible de una respuesta concreta (etiqueta, no id).
  String? answerLabel(String questionId) {
    final optionId = _answers[questionId];
    if (optionId == null) return null;
    return FormTree.question(questionId)?.optionById(optionId)?.label;
  }

  // --- Navegación ------------------------------------------------------------

  /// Elige el perfil y arranca su rama.
  void selectProfile(NeedProfile profile) {
    _profile = profile;
    _answers.clear();
    _history.clear();
    _recommendation = null;
    _finished = false;
    _currentQuestionId = FormTree.firstQuestionId(profile);
    notifyListeners();
  }

  /// Responde la pregunta actual y avanza.
  void answer(String optionId) {
    final question = currentQuestion;
    if (question == null) return;
    final option = question.optionById(optionId);
    if (option == null) return;

    _answers[question.id] = optionId;
    _history.add(question.id);

    if (option.isTerminal) {
      _recommendation = option.recommendation;
      _currentQuestionId = null;
      _finished = true;
    } else {
      _currentQuestionId = option.nextQuestionId;
      // Materiales sugeridos por la opción, si los hay.
      if (option.materialHint != null) {
        _material = option.materialHint!;
      }
    }
    notifyListeners();
  }

  /// Retrocede a la pregunta anterior.
  void goBack() {
    if (_history.isEmpty) {
      // Estábamos en la primera pregunta: se vuelve a la elección de perfil.
      _profile = null;
      _currentQuestionId = null;
      _recommendation = null;
      _finished = false;
      notifyListeners();
      return;
    }

    final last = _history.removeLast();
    _currentQuestionId = last;
    _recommendation = null;
    _finished = false;
    notifyListeners();
  }

  /// Reinicia el formulario por completo.
  void reset() {
    _profile = null;
    _answers.clear();
    _history.clear();
    _currentQuestionId = null;
    _material = FormTree.defaultMaterial;
    _recommendation = null;
    _measurements.clear();
    _brailleText = '';
    _finished = false;
    notifyListeners();
  }

  // --- Material y braille ----------------------------------------------------

  void setMaterial(String material) {
    if (_material == material) return;
    _material = material;
    notifyListeners();
  }

  void setBrailleText(String text) {
    if (_brailleText == text) return;
    _brailleText = text;
    notifyListeners();
  }

  // --- Medidas ---------------------------------------------------------------

  /// Añade o reemplaza una medida (misma etiqueta = misma magnitud).
  void upsertMeasurement(Measurement measurement) {
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

  void clearMeasurements() {
    _measurements.clear();
    notifyListeners();
  }

  /// Medidas que aún faltan según la opción elegida, para avisar al usuario.
  List<String> get missingSuggestedMeasurements {
    final suggestion = _lastTerminalOption?.suggestedMeasurements ?? const [];
    if (suggestion.isEmpty) return const [];
    final present = _measurements
        .map((m) => m.label.toLowerCase())
        .toSet();
    return suggestion
        .where((s) => !present.contains(s.toLowerCase()))
        .toList();
  }

  /// Última opción terminal elegida (la que cerró el flujo).
  FormOption? get _lastTerminalOption {
    for (final questionId in _history.reversed) {
      final optionId = _answers[questionId];
      final option = FormTree.question(questionId)?.optionById(optionId ?? '');
      if (option != null && option.isTerminal) return option;
    }
    return null;
  }

  /// Frases de prompt acumuladas de todas las respuestas dadas.
  List<String> get promptFragments {
    final fragments = <String>[];
    for (final questionId in _history) {
      final optionId = _answers[questionId];
      final option = FormTree.question(questionId)?.optionById(optionId ?? '');
      if (option != null) fragments.addAll(option.promptFragments);
    }
    return fragments;
  }

  /// Resumen de una línea para la pantalla de revisión.
  String get summary {
    final buffer = StringBuffer();
    buffer.write(profile?.label ?? 'Sin perfil');
    for (final entry in answerEntries) {
      final label = answerLabel(entry.key);
      if (label != null) buffer.write(' · $label');
    }
    buffer.write(' · $material');
    return buffer.toString();
  }
}
