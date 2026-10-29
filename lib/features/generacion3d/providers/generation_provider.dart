import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/env.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../../orthosnap/modelos/orthosnap_modelos.dart';
import '../../progrip/modelos/progrip_modelos.dart';
import '../modelos/meshy_models.dart';
import '../servicios/meshy_service.dart';
import '../servicios/prompt_builder_service.dart';

/// Fase del flujo de generación, para pintar la UI.
enum GenerationPhase {
  idle('Sin generar'),
  preparing('Preparando el prompt'),
  creating('Enviando el diseño a Meshy'),
  polling('Generando el modelo 3D'),
  succeeded('Modelo listo'),
  failed('Error');

  const GenerationPhase(this.label);

  final String label;

  bool get isBusy =>
      this == GenerationPhase.preparing ||
      this == GenerationPhase.creating ||
      this == GenerationPhase.polling;
}

/// Estado global del flujo de generación 3D.
///
/// Orquesta: prompt -> creación de tarea -> sondeo -> modelo descargable.
/// Mantiene además un historial local de los modelos generados, persistido en
/// `SharedPreferences` (solo metadatos: el `.glb` vive en el sistema de
/// ficheros y se descarga a petición).
class GenerationProvider extends ChangeNotifier {
  GenerationProvider({
    MeshyService? service,
    PromptBuilderService? promptBuilder,
    SharedPreferences? preferences,
  })  : _service = service ?? MeshyService(),
        _promptBuilder = promptBuilder ?? const PromptBuilderService(),
        // ignore: prefer_initializing_formals
        _preferences = preferences;

  static const String _historyKey = 'lumina.models.history';
  static const int _historyLimit = 20;

  final MeshyService _service;
  final PromptBuilderService _promptBuilder;
  SharedPreferences? _preferences;

  GenerationPhase _phase = GenerationPhase.idle;
  PromptBuildResult? _prompt;
  MeshyTask? _task;
  MeshyException? _error;
  GeneratedModel? _model;
  String _title = '';
  bool _cancelRequested = false;
  final List<GeneratedModel> _history = <GeneratedModel>[];

  // --- Lectura ---------------------------------------------------------------

  GenerationPhase get phase => _phase;

  /// Prompt enriquecido que se enviará (o se envió) a Meshy.
  PromptBuildResult? get prompt => _prompt;

  /// Última tarea conocida de Meshy (para mostrar `status` y `progress`).
  MeshyTask? get task => _task;

  /// Error actual, con mensaje ya en español.
  MeshyException? get error => _error;

  /// Modelo generado, con su URL de descarga.
  GeneratedModel? get model => _model;

  /// Título corto derivado del prompt.
  String get title => _title;

  /// Historial de modelos generados en este dispositivo.
  List<GeneratedModel> get history => List.unmodifiable(_history);

  /// `true` si se está usando la clave de prueba gratuita de Meshy.
  bool get isTestMode => Env.isMeshyTestMode;

  /// Progreso 0.0-1.0 de la fase actual.
  double get progress {
    switch (_phase) {
      case GenerationPhase.preparing:
        return 0.05;
      case GenerationPhase.creating:
        return 0.1;
      case GenerationPhase.polling:
        // Se reserva el 10 % inicial para el envío y se escala el resto.
        return 0.1 + (_task?.progressFraction ?? 0) * 0.9;
      case GenerationPhase.succeeded:
        return 1;
      case GenerationPhase.idle:
      case GenerationPhase.failed:
        return 0;
    }
  }

  /// `true` cuando hay un modelo listo para visualizar.
  bool get hasModel => _model != null && _model!.glbUrl.isNotEmpty;

  // --- Acciones --------------------------------------------------------------

  /// Genera a partir del formulario inteligente.
  Future<void> generateFromFormulario(FormularioProvider form) async {
    final recommendation = form.recommendation;
    if (recommendation == null) {
      _fail(
        const MeshyException(
          message: 'Completa el formulario antes de generar el modelo.',
          kind: MeshyErrorKind.badRequest,
        ),
      );
      return;
    }
    final built = _promptBuilder.fromFormulario(form);
    await _run(
      built: built,
      title: recommendation.title,
      material: form.material,
    );
  }

  /// Genera una pieza ProGrip a partir de sus tres capas.
  Future<void> generateFromProGrip(ProGripConfig config) async {
    final built = _promptBuilder.fromProGrip(config);
    await _run(built: built, title: config.title, material: config.material);
  }

  /// Genera una órtesis OrthoSnap.
  Future<void> generateFromOrthoSnap(OrthoSnapRequest request) async {
    final built = _promptBuilder.fromOrthoSnap(request);
    await _run(built: built, title: request.title, material: request.material);
  }

  /// Reintenta con el último prompt. Nunca reutiliza un `task_id` fallido:
  /// Meshy no reanuda tareas `FAILED`, hay que crear una nueva.
  Future<void> retry() async {
    final built = _prompt;
    if (built == null) return;
    await _run(built: built, title: _title, material: _model?.material);
  }

  /// Pide detener el sondeo. La tarea sigue viva en Meshy.
  void cancelPolling() {
    if (!_phase.isBusy) return;
    _cancelRequested = true;
    notifyListeners();
  }

  /// Vuelve al estado inicial (no borra el historial).
  void reset() {
    _phase = GenerationPhase.idle;
    _prompt = null;
    _task = null;
    _error = null;
    _model = null;
    _title = '';
    _cancelRequested = false;
    notifyListeners();
  }

  /// Registra que un modelo se ha guardado en el dispositivo.
  void markDownloaded(String id, String localPath) {
    final index = _history.indexWhere((m) => m.id == id);
    if (index >= 0) {
      _history[index] = _history[index].copyWith(localPath: localPath);
    }
    if (_model?.id == id) {
      _model = _model!.copyWith(localPath: localPath);
    }
    _persistHistory();
    notifyListeners();
  }

  void removeFromHistory(String id) {
    _history.removeWhere((m) => m.id == id);
    _persistHistory();
    notifyListeners();
  }

  // --- Historial -------------------------------------------------------------

  /// Carga el historial guardado. Se llama una vez al arrancar.
  Future<void> restoreHistory() async {
    try {
      final prefs = _preferences ??= await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _history
        ..clear()
        ..addAll(
          decoded
              .whereType<Map<String, dynamic>>()
              .map(GeneratedModel.fromJson),
        );
      notifyListeners();
    } catch (error) {
      debugPrint('No se pudo restaurar el historial de modelos: $error');
    }
  }

  void _persistHistory() {
    final prefs = _preferences;
    if (prefs == null) return;
    final encoded = jsonEncode(
      _history.take(_historyLimit).map((m) => m.toJson()).toList(),
    );
    prefs.setString(_historyKey, encoded).catchError((Object error) {
      debugPrint('No se pudo guardar el historial: $error');
      return false;
    });
  }

  void _addToHistory(GeneratedModel model) {
    _history.insert(0, model);
    if (_history.length > _historyLimit) {
      _history.removeRange(_historyLimit, _history.length);
    }
    _persistHistory();
  }

  // --- Núcleo del flujo ------------------------------------------------------

  /// Ejecuta el ciclo completo: crear tarea -> sondear -> construir modelo.
  Future<void> _run({
    required PromptBuildResult built,
    required String title,
    String? material,
  }) async {
    _prompt = built;
    _title = title;
    _error = null;
    _model = null;
    _task = null;
    _cancelRequested = false;

    try {
      _phase = GenerationPhase.creating;
      notifyListeners();

      final taskId = await _service.createTextTo3dPreview(
        prompt: built.prompt,
        // Para piezas impresas interesa la geometría original de Meshy, sin
        // decimar: el usuario decide después si reduce el número de caras.
        shouldRemesh: false,
        enablePbr: false,
        targetFormats: const <String>['glb'],
      );

      _phase = GenerationPhase.polling;
      _task = MeshyTask(
        id: taskId,
        status: MeshyTaskStatus.pending,
        progress: 0,
      );
      notifyListeners();

      final finished = await _service.waitForCompletion(
        taskId,
        onProgress: (task) {
          _task = task;
          notifyListeners();
        },
        shouldCancel: () => _cancelRequested,
      );

      if (!finished.hasModel) {
        _fail(
          const MeshyException(
            message:
                'La generación terminó pero Meshy no devolvió ningún archivo .glb. '
                'Vuelve a intentarlo.',
            kind: MeshyErrorKind.server,
            isRetryable: true,
          ),
        );
        return;
      }

      final model = GeneratedModel(
        id: finished.id,
        title: title,
        prompt: built.prompt,
        glbUrl: finished.glbUrl!,
        thumbnailUrl: finished.thumbnailUrl,
        taskId: finished.id,
        createdAt: DateTime.now(),
        material: material,
      );

      _model = model;
      _task = finished;
      _phase = GenerationPhase.succeeded;
      _addToHistory(model);
      notifyListeners();
    } on MeshyException catch (error) {
      _fail(error);
    } catch (error) {
      _fail(
        MeshyException(
          message: 'Ocurrió un error inesperado al generar el modelo: $error',
          kind: MeshyErrorKind.server,
          isRetryable: true,
        ),
      );
    }
  }

  void _fail(MeshyException error) {
    _error = error;
    _phase = GenerationPhase.failed;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
