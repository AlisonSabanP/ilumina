import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/env.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../modelos/meshy_models.dart';
import '../servicios/local_generator_service.dart';
import '../servicios/meshy_service.dart';
import '../servicios/prompt_builder_service.dart';

/// Fase del flujo de generación, para pintar la UI.
enum GenerationPhase {
  idle('Sin generar'),
  preparing('Preparando el diseño'),
  creating('Construyendo la pieza'),
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
    LocalGeneratorService? localGenerator,
    SharedPreferences? preferences,
  })  : _service = service ?? MeshyService(),
        _promptBuilder = promptBuilder ?? const PromptBuilderService(),
        _localGenerator = localGenerator ?? const LocalGeneratorService(),
        // ignore: prefer_initializing_formals
        _preferences = preferences;

  static const String _historyKey = 'lumina.models.history';
  static const int _historyLimit = 20;

  /// Carpeta donde se guardan las piezas construidas en el dispositivo.
  static const String _localFolderName = 'lumina_piezas';

  /// Pieza de ejemplo empaquetada en la app.
  ///
  /// Es el cubo que se muestra cuando no hay clave de Meshy: en lugar de
  /// inventar geometría, se enseña una pieza real para que el flujo completo
  /// (visor, descarga y compartir) se pueda probar de principio a fin.
  static const String demoAssetPath = 'assets/models/demo_pieza.glb';

  final MeshyService _service;
  final PromptBuilderService _promptBuilder;
  final LocalGeneratorService _localGenerator;
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

  /// `true` si no hay una clave propia de Meshy configurada.
  bool get isTestMode => Env.isMeshyTestMode;

  /// `true` si no hay una clave propia de Meshy configurada.
  ///
  /// En ese caso Lumina no llama a la API (respondería 401) y muestra la
  /// **pieza de demostración** incluida en la app: un cubo de ejemplo. Así el
  /// flujo completo —visor, descarga y compartir— se puede probar de principio
  /// a fin sin gastar créditos.
  bool get isDemoMode => Env.isMeshyTestMode;

  /// `true` si la generación se delega en la API de Meshy.
  ///
  /// Solo ocurre cuando el usuario ha configurado su propia clave, porque la
  /// API de Meshy es de pago: sin clave propia responde 401 y no hay modo de
  /// prueba gratuito.
  bool get isMeshyMode => !Env.isMeshyTestMode;

  /// `true` si el último modelo es la pieza de demostración.
  bool get isDemoPiece => _model?.isDemo ?? false;

  /// `true` si el último modelo es una pieza construida en el dispositivo.
  bool get isLocalPiece => _model?.isLocal ?? false;

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

  /// `true` cuando hay una pieza lista para visualizar.
  ///
  /// Sirve tanto la vía de demostración (el `.glb` está empaquetado como asset)
  /// como la de Meshy (hay URL remota que descargar).
  bool get hasModel {
    final model = _model;
    if (model == null) return false;
    if (model.isLocalAsset) return true;
    if (model.localPath != null && model.localPath!.isNotEmpty) return true;
    return model.glbUrl.isNotEmpty;
  }

  // --- Acciones --------------------------------------------------------------

  /// Genera a partir del formulario inteligente.
  Future<void> generateFromFormulario(FormularioProvider form) async {
    final recommendation = form.recommendation;
    if (recommendation == null) {
      _fail(
        const MeshyException(
          message: 'Completa el formulario antes de generar la pieza.',
          kind: MeshyErrorKind.badRequest,
        ),
      );
      return;
    }
    final built = _promptBuilder.fromFormulario(form);
    await _run(built: built, title: recommendation.title);
  }

  /// Construye **solo** la etiqueta Braille como pieza imprimible.
  ///
  /// Es el caso de uso del perfil visual: quien no ve el objeto no necesita
  /// una pieza grande con relieve encima, necesita la etiqueta. Se ofrece como
  /// acción independiente para que se pueda imprimir sola.
  ///
  /// Es la única pieza que Lumina sigue construyendo en el propio dispositivo:
  /// la geometría de los puntos Braille es determinista y no depende de ningún
  /// servicio externo.
  Future<void> generateBrailleLabel(String text, {String? title}) async {
    final label = text.trim().isEmpty ? 'lumina' : text.trim();
    await _runLocal(
      built: PromptBuildResult(
        prompt: 'Braille label reading "$label" with raised dots',
        seed: 'Braille label',
        wasTrimmed: false,
        originalLength: 0,
      ),
      title: title ?? 'Etiqueta Braille',
      mesh: _localGenerator.braillePlate(label),
    );
  }

  /// Reintenta con el último diseño. Nunca reutiliza un `task_id` fallido:
  /// Meshy no reanuda tareas `FAILED`, hay que crear una nueva.
  Future<void> retry() async {
    final built = _prompt;
    if (built == null) return;
    await _run(built: built, title: _title);
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
  void markDownloaded(String id, String localPath, {String? stlPath}) {
    final index = _history.indexWhere((m) => m.id == id);
    if (index >= 0) {
      _history[index] = _history[index].copyWith(
        localPath: localPath,
        stlPath: stlPath,
      );
    }
    if (_model?.id == id) {
      _model = _model!.copyWith(localPath: localPath, stlPath: stlPath);
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

  /// Ejecuta el ciclo completo, por la vía de demostración o por la de Meshy.
  ///
  /// La vía de demostración es la de por defecto: en lugar de llamar a la API
  /// (que sin clave propia responde 401), muestra la pieza de ejemplo incluida
  /// en la app. Meshy solo se usa cuando hay una clave propia configurada,
  /// porque su API es de pago.
  Future<void> _run({
    required PromptBuildResult built,
    required String title,
  }) async {
    _prompt = built;
    _title = title;
    _error = null;
    _model = null;
    _task = null;
    _cancelRequested = false;

    if (isDemoMode) {
      await _runDemo(built: built, title: title);
      return;
    }

    await _runMeshy(built: built, title: title);
  }

  // --- Vía de demostración: la pieza de ejemplo de la app --------------------

  /// Simula el flujo de generación con la pieza empaquetada en la app.
  ///
  /// Mantiene las mismas fases que la generación real (`creating` -> `polling`
  /// -> `succeeded`) para que la interfaz no cambie, pero no hace ninguna
  /// llamada de red ni consume créditos: el modelo que se muestra es el cubo
  /// de ejemplo incluido en `assets/models/`.
  Future<void> _runDemo({
    required PromptBuildResult built,
    required String title,
  }) async {
    _phase = GenerationPhase.creating;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_cancelRequested) {
      _cancelDemo();
      return;
    }

    _phase = GenerationPhase.polling;
    _task = MeshyTask(
      id: 'demo',
      status: MeshyTaskStatus.inProgress,
      progress: 0,
    );
    notifyListeners();

    // Progreso simulado, para que se vea que el flujo avanza.
    for (final step in const <int>[25, 50, 75, 100]) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (_cancelRequested) {
        _cancelDemo();
        return;
      }
      _task = MeshyTask(
        id: 'demo',
        status: step == 100
            ? MeshyTaskStatus.succeeded
            : MeshyTaskStatus.inProgress,
        progress: step,
      );
      notifyListeners();
    }

    final model = GeneratedModel(
      id: 'demo_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      prompt: built.prompt,
      glbUrl: '',
      assetPath: demoAssetPath,
      taskId: 'demo',
      createdAt: DateTime.now(),
      isDemo: true,
    );

    _model = model;
    _phase = GenerationPhase.succeeded;
    _addToHistory(model);
    notifyListeners();
  }

  void _cancelDemo() {
    _fail(
      const MeshyException(
        message: 'Demostración detenida.',
        kind: MeshyErrorKind.timeout,
      ),
    );
  }

  // --- Vía local: solo la etiqueta Braille -----------------------------------

  /// Escribe en disco una pieza construida en el dispositivo y la publica.
  ///
  /// Se usa únicamente para la etiqueta Braille: es la única pieza cuya
  /// geometría Lumina puede calcular sola con garantías. El resto de piezas
  /// pasan por la pieza de demostración o por Meshy.
  Future<void> _runLocal({
    required PromptBuildResult built,
    required String title,
    required GeneratedMesh mesh,
  }) async {
    try {
      _phase = GenerationPhase.creating;
      notifyListeners();

      // Se cede el hilo antes de escribir: en un móvil modesto, serializar la
      // malla y tocar el disco puede notarse si no se deja pintar la fase.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_cancelRequested) {
        _cancelLocal();
        return;
      }

      _phase = GenerationPhase.polling;
      _task = MeshyTask(
        id: 'local',
        status: MeshyTaskStatus.inProgress,
        progress: 60,
      );
      notifyListeners();

      final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
      final paths = await _writeLocalFiles(id: id, title: title, mesh: mesh);

      final model = GeneratedModel(
        id: id,
        title: title,
        prompt: built.prompt,
        glbUrl: '',
        localPath: paths.glbPath,
        stlPath: paths.stlPath,
        taskId: 'local',
        createdAt: DateTime.now(),
        isLocal: true,
        pieceSummary: mesh.summary,
        pieceNotes: mesh.notes,
        dimensionsMm: mesh.dimensionsMm,
      );

      _model = model;
      _task = MeshyTask(
        id: 'local',
        status: MeshyTaskStatus.succeeded,
        progress: 100,
      );
      _phase = GenerationPhase.succeeded;
      _addToHistory(model);
      notifyListeners();
    } catch (error) {
      _fail(
        MeshyException(
          message: 'No se pudo construir la pieza en el dispositivo: $error',
          kind: MeshyErrorKind.server,
          isRetryable: true,
        ),
      );
    }
  }

  void _cancelLocal() {
    _fail(
      const MeshyException(
        message: 'Generación detenida.',
        kind: MeshyErrorKind.timeout,
      ),
    );
  }

  /// Escribe la pieza en disco: el `.stl` para imprimir y el `.glb` para ver.
  Future<_LocalPaths> _writeLocalFiles({
    required String id,
    required String title,
    required GeneratedMesh mesh,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_localFolderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final safeTitle = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áéíóúñ _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final prefix = safeTitle.isEmpty ? 'lumina' : safeTitle;

    final stlFile = File('${dir.path}/${prefix}_$id.stl');
    final glbFile = File('${dir.path}/${prefix}_$id.glb');

    await stlFile.writeAsBytes(mesh.stl, flush: true);
    await glbFile.writeAsBytes(mesh.glb, flush: true);

    return _LocalPaths(stlPath: stlFile.path, glbPath: glbFile.path);
  }

  // --- Vía Meshy: generación remota con IA -----------------------------------

  /// Ciclo completo contra la API de Meshy: crear -> sondear -> modelo.
  Future<void> _runMeshy({
    required PromptBuildResult built,
    required String title,
  }) async {
    try {
      _phase = GenerationPhase.creating;
      notifyListeners();

      final taskId = await _service.createTextTo3dPreview(
        prompt: built.prompt,
        // Para piezas impresas interesa la geometría original de Meshy, sin
        // decimar: el usuario decide después si reduce el número de caras.
        shouldRemesh: false,
        enablePbr: false,
        // Se piden los dos formatos: el STL para laminar y el GLB para ver.
        targetFormats: const <String>['glb', 'stl'],
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
                'La generación terminó pero Meshy no devolvió ningún archivo. '
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
        stlUrl: finished.stlUrl,
        taskId: finished.id,
        createdAt: DateTime.now(),
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
          message: 'Ocurrió un error inesperado al generar la pieza: $error',
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

/// Rutas de los dos archivos que se escriben por cada pieza local.
class _LocalPaths {
  const _LocalPaths({required this.stlPath, required this.glbPath});

  final String stlPath;
  final String glbPath;
}
