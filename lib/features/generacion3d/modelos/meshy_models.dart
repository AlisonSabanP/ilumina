import 'package:flutter/foundation.dart';

/// Estados posibles de una tarea de Meshy, tal como los documenta la API.
enum MeshyTaskStatus {
  pending,
  inProgress,
  succeeded,
  failed,
  canceled;

  /// Traducción de los valores que devuelve la API (`PENDING`,
  /// `IN_PROGRESS`, `SUCCEEDED`, `FAILED`, `CANCELED`).
  static MeshyTaskStatus parse(String? raw) {
    switch (raw) {
      case 'PENDING':
        return MeshyTaskStatus.pending;
      case 'IN_PROGRESS':
        return MeshyTaskStatus.inProgress;
      case 'SUCCEEDED':
        return MeshyTaskStatus.succeeded;
      case 'FAILED':
        return MeshyTaskStatus.failed;
      case 'CANCELED':
        return MeshyTaskStatus.canceled;
      default:
        return MeshyTaskStatus.pending;
    }
  }

  bool get isTerminal =>
      this == MeshyTaskStatus.succeeded ||
      this == MeshyTaskStatus.failed ||
      this == MeshyTaskStatus.canceled;

  String get label => switch (this) {
        MeshyTaskStatus.pending => 'En cola',
        MeshyTaskStatus.inProgress => 'Generando',
        MeshyTaskStatus.succeeded => 'Listo',
        MeshyTaskStatus.failed => 'Error',
        MeshyTaskStatus.canceled => 'Cancelado',
      };
}

/// Error tipado del cliente de Meshy, con mensaje en español para el usuario.
class MeshyException implements Exception {
  const MeshyException({
    required this.message,
    required this.kind,
    this.statusCode,
    this.taskId,
    this.isRetryable = false,
  });

  /// Mensaje apto para mostrar al usuario.
  final String message;

  final MeshyErrorKind kind;

  /// Código HTTP, si la llamada llegó a responder.
  final int? statusCode;

  /// Id de la tarea, si ya existía cuando falló.
  final String? taskId;

  /// `true` si tiene sentido ofrecer el botón de reintentar.
  final bool isRetryable;

  @override
  String toString() =>
      'MeshyException($kind, status: $statusCode, message: $message)';
}

enum MeshyErrorKind {
  /// Sin conexión o tiempo de espera agotado.
  network,

  /// 400: petición mal formada (prompt demasiado largo, parámetro ausente...).
  badRequest,

  /// 401: clave de API ausente o inválida.
  unauthorized,

  /// 402: sin créditos o plan gratuito (Meshy exige plan de pago para crear tareas).
  paymentRequired,

  /// 429: se superó el límite de peticiones.
  rateLimited,

  /// La tarea terminó en `FAILED`.
  taskFailed,

  /// La tarea se canceló.
  taskCanceled,

  /// Respuesta inesperada o error del servidor (5xx).
  server,

  /// El usuario canceló o se agotó el tiempo máximo de espera.
  timeout,
}

/// Tarea de Meshy ya interpretada.
@immutable
class MeshyTask {
  const MeshyTask({
    required this.id,
    required this.status,
    required this.progress,
    this.type,
    this.prompt,
    this.glbUrl,
    this.objUrl,
    this.stlUrl,
    this.thumbnailUrl,
    this.textureBaseColorUrl,
    this.errorMessage,
    this.consumedCredits,
    this.createdAt,
    this.finishedAt,
  });

  final String id;
  final MeshyTaskStatus status;

  /// 0-100.
  final int progress;

  /// `text-to-3d-preview` o `text-to-3d-refine`.
  final String? type;

  final String? prompt;

  /// URL de descarga del `.glb`, disponible cuando la tarea termina bien.
  final String? glbUrl;

  final String? objUrl;
  final String? stlUrl;
  final String? thumbnailUrl;
  final String? textureBaseColorUrl;

  /// Mensaje de `task_error.message` cuando la tarea falla.
  final String? errorMessage;

  /// Créditos consumidos por la tarea.
  final int? consumedCredits;

  final DateTime? createdAt;
  final DateTime? finishedAt;

  bool get hasModel => glbUrl != null && glbUrl!.isNotEmpty;

  /// Fracción 0.0-1.0 lista para un `LinearProgressIndicator`.
  double get progressFraction => (progress.clamp(0, 100)) / 100;

  /// Interpreta el objeto JSON que devuelve `GET /openapi/v2/text-to-3d/{id}`.
  factory MeshyTask.fromJson(Map<String, dynamic> json) {
    final modelUrls = json['model_urls'];
    final textureUrls = json['texture_urls'];

    String? stringAt(dynamic container, String key) {
      if (container is Map) {
        final value = container[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return null;
    }

    String? textureBaseColor;
    if (textureUrls is List && textureUrls.isNotEmpty) {
      textureBaseColor = stringAt(textureUrls.first, 'base_color');
    }

    final taskError = json['task_error'];
    final errorMessage = taskError is Map
        ? (taskError['message'] as String?)
        : null;

    return MeshyTask(
      id: (json['id'] ?? '') as String,
      status: MeshyTaskStatus.parse(json['status'] as String?),
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      type: json['type'] as String?,
      prompt: json['prompt'] as String?,
      glbUrl: stringAt(modelUrls, 'glb'),
      objUrl: stringAt(modelUrls, 'obj'),
      stlUrl: stringAt(modelUrls, 'stl'),
      thumbnailUrl: stringAt(json, 'thumbnail_url'),
      textureBaseColorUrl: textureBaseColor,
      errorMessage:
          (errorMessage != null && errorMessage.isNotEmpty) ? errorMessage : null,
      consumedCredits: (json['consumed_credits'] as num?)?.toInt(),
      createdAt: _parseMillis(json['created_at']),
      finishedAt: _parseMillis(json['finished_at']),
    );
  }

  /// Meshy usa milisegundos Unix en todas sus marcas de tiempo.
  static DateTime? _parseMillis(dynamic value) {
    if (value is num && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  @override
  String toString() => 'MeshyTask($id, ${status.name}, $progress%)';
}

/// Registro de un modelo ya generado y descargado, para el historial local.
@immutable
class GeneratedModel {
  const GeneratedModel({
    required this.id,
    required this.title,
    required this.prompt,
    required this.glbUrl,
    this.stlUrl,
    this.localPath,
    this.stlPath,
    this.assetPath,
    this.thumbnailUrl,
    this.taskId,
    this.createdAt,
    this.isLocal = false,
    this.isDemo = false,
    this.pieceSummary,
    this.pieceNotes = const <String>[],
    this.dimensionsMm = const <String, double>{},
  });

  final String id;
  final String title;
  final String prompt;
  final String glbUrl;

  /// URL del `.stl` en Meshy, cuando se pidió ese formato.
  final String? stlUrl;

  /// Ruta del `.glb` guardado en el dispositivo, si ya se descargó.
  final String? localPath;

  /// Ruta del `.stl` guardado en el dispositivo, listo para laminar.
  ///
  /// Las piezas generadas en el propio móvil se guardan siempre en STL, que es
  /// lo que abren Cura, PrusaSlicer o Bambu Studio sin conversiones.
  final String? stlPath;

  /// Ruta del `.glb` **empaquetado en la app** que se usará como pieza.
  ///
  /// Es el caso de la pieza de demostración: no se genera nada, se muestra el
  /// archivo incluido en `assets/models/`. El visor lo carga con
  /// `Power3D.fromAsset` y al descargar se copia tal cual.
  final String? assetPath;

  final String? thumbnailUrl;
  final String? taskId;
  final DateTime? createdAt;

  /// `true` si la pieza la ha construido Lumina en el dispositivo, sin red.
  final bool isLocal;

  /// `true` si la pieza es la de demostración empaquetada en la app.
  ///
  /// Se usa cuando no hay clave de Meshy: en lugar de inventar geometría, se
  /// enseña una pieza de ejemplo real para que el flujo completo (visor,
  /// descarga, compartir) se pueda probar de principio a fin.
  final bool isDemo;

  /// `true` si el modelo vive como asset dentro de la app.
  bool get isLocalAsset => assetPath != null;

  /// Descripción legible de la pieza generada localmente.
  final String? pieceSummary;

  /// Avisos de fabricación (medidas por defecto usadas, holguras...).
  final List<String> pieceNotes;

  /// Caja envolvente de la pieza en milímetros.
  final Map<String, double> dimensionsMm;

  bool get isDownloaded => localPath != null || stlPath != null;

  GeneratedModel copyWith({
    String? localPath,
    String? stlPath,
    String? title,
  }) =>
      GeneratedModel(
        id: id,
        title: title ?? this.title,
        prompt: prompt,
        glbUrl: glbUrl,
        stlUrl: stlUrl,
        localPath: localPath ?? this.localPath,
        stlPath: stlPath ?? this.stlPath,
        assetPath: assetPath,
        thumbnailUrl: thumbnailUrl,
        taskId: taskId,
        createdAt: createdAt,
        isLocal: isLocal,
        isDemo: isDemo,
        pieceSummary: pieceSummary,
        pieceNotes: pieceNotes,
        dimensionsMm: dimensionsMm,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'prompt': prompt,
        'glbUrl': glbUrl,
        'stlUrl': stlUrl,
        'localPath': localPath,
        'stlPath': stlPath,
        'assetPath': assetPath,
        'thumbnailUrl': thumbnailUrl,
        'taskId': taskId,
        'createdAt': createdAt?.toIso8601String(),
        'isLocal': isLocal,
        'isDemo': isDemo,
        'pieceSummary': pieceSummary,
        'pieceNotes': pieceNotes,
        'dimensionsMm': dimensionsMm,
      };

  static GeneratedModel fromJson(Map<String, dynamic> json) => GeneratedModel(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Modelo sin título',
        prompt: json['prompt'] as String? ?? '',
        glbUrl: json['glbUrl'] as String? ?? '',
        stlUrl: json['stlUrl'] as String?,
        localPath: json['localPath'] as String?,
        stlPath: json['stlPath'] as String?,
        assetPath: json['assetPath'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        taskId: json['taskId'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        isLocal: json['isLocal'] as bool? ?? false,
        isDemo: json['isDemo'] as bool? ?? false,
        pieceSummary: json['pieceSummary'] as String?,
        pieceNotes: (json['pieceNotes'] as List?)?.whereType<String>().toList() ??
            const <String>[],
        dimensionsMm: (json['dimensionsMm'] as Map?)?.map(
              (key, value) => MapEntry(
                key.toString(),
                (value as num).toDouble(),
              ),
            ) ??
            const <String, double>{},
      );
}
