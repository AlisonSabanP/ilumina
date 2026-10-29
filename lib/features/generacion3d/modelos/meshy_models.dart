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
    this.localPath,
    this.thumbnailUrl,
    this.taskId,
    this.createdAt,
    this.material,
  });

  final String id;
  final String title;
  final String prompt;
  final String glbUrl;

  /// Ruta del `.glb` guardado en el dispositivo, si ya se descargó.
  final String? localPath;

  final String? thumbnailUrl;
  final String? taskId;
  final DateTime? createdAt;
  final String? material;

  bool get isDownloaded => localPath != null;

  GeneratedModel copyWith({String? localPath, String? title}) => GeneratedModel(
        id: id,
        title: title ?? this.title,
        prompt: prompt,
        glbUrl: glbUrl,
        localPath: localPath ?? this.localPath,
        thumbnailUrl: thumbnailUrl,
        taskId: taskId,
        createdAt: createdAt,
        material: material,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'prompt': prompt,
        'glbUrl': glbUrl,
        'localPath': localPath,
        'thumbnailUrl': thumbnailUrl,
        'taskId': taskId,
        'createdAt': createdAt?.toIso8601String(),
        'material': material,
      };

  static GeneratedModel fromJson(Map<String, dynamic> json) => GeneratedModel(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Modelo sin título',
        prompt: json['prompt'] as String? ?? '',
        glbUrl: json['glbUrl'] as String? ?? '',
        localPath: json['localPath'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        taskId: json['taskId'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        material: json['material'] as String?,
      );
}
