import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/env.dart';
import '../modelos/meshy_models.dart';

/// Cliente REST de Meshy AI.
///
/// Implementa el flujo asíncrono documentado por Meshy:
///
///   1. `POST /openapi/v2/text-to-3d` con `mode: preview` -> devuelve `result`
///      (el `task_id`).
///   2. `GET /openapi/v2/text-to-3d/{task_id}` en bucle hasta que el `status`
///      sea terminal (`SUCCEEDED`, `FAILED`, `CANCELED`).
///   3. Descarga del `.glb` desde `model_urls.glb`.
///
/// Puntos delicados que este servicio respeta a propósito:
///
///  * **Nunca se reintenta un `POST`** tras un error de red o un `5xx`: Meshy
///    no tiene clave de idempotencia, así que un segundo `POST` crearía y
///    cobraría una segunda tarea. Solo se reintenta el `GET`.
///  * **`Retry-After`**: si la respuesta lo incluye, se espera ese número de
///    segundos antes del siguiente `GET`. Si no, se usa [pollInterval].
///  * **Tiempo máximo de espera**: por defecto 60 minutos, como recomienda la
///    documentación ("espera al menos 60 minutos antes de darte por vencido").
///    Si se agota, la tarea sigue viva en el servidor: se devuelve el último
///    estado conocido con `timeout`, no un fallo.
///  * **Clave de prueba**: si no hay clave configurada, se usa
///    `Env.testModeApiKey`. En ese modo Meshy no genera el modelo del prompt
///    (devuelve un resultado de demostración), y la UI lo advierte.
class MeshyService {
  MeshyService({http.Client? client}) : _client = client ?? http.Client();

  /// URL base documentada por Meshy.
  static const String baseUrl = 'https://api.meshy.ai';

  /// Ruta del endpoint Text to 3D (v2).
  static const String textTo3dPath = '/openapi/v2/text-to-3d';

  /// Intervalo por defecto entre sondeos cuando la API no envía `Retry-After`.
  static const Duration pollInterval = Duration(seconds: 5);

  /// Tiempo máximo de espera total del sondeo.
  static const Duration defaultMaxWait = Duration(minutes: 60);

  /// Tiempo máximo por petición HTTP individual.
  static const Duration requestTimeout = Duration(seconds: 30);

  final http.Client _client;

  bool _disposed = false;

  /// Cabeceras comunes. La clave nunca se registra en logs.
  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer ${Env.meshyApiKey}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// Paso 1: crea la tarea de vista previa y devuelve su `task_id`.
  ///
  /// No se debe llamar dos veces ante un error: ver la nota de clase.
  Future<String> createTextTo3dPreview({
    required String prompt,
    bool shouldRemesh = true,
    bool enablePbr = false,
    List<String>? targetFormats,
  }) async {
    if (prompt.trim().isEmpty) {
      throw const MeshyException(
        message: 'El prompt está vacío: no hay nada que generar.',
        kind: MeshyErrorKind.badRequest,
      );
    }
    if (prompt.length > 800) {
      throw const MeshyException(
        message:
            'El prompt supera los 800 caracteres que admite Meshy. Reduce el número de medidas o de requisitos.',
        kind: MeshyErrorKind.badRequest,
      );
    }

    final body = <String, dynamic>{
      'mode': 'preview',
      'prompt': prompt,
      // Para un objeto impreso en 3D interesa la geometría tal cual, sin
      // remallado agresivo. `should_remesh: false` es lo que Meshy recomienda
      // para obtener la máxima calidad.
      'should_remesh': shouldRemesh,
      if (enablePbr) 'enable_pbr': true,
      if (targetFormats != null && targetFormats.isNotEmpty)
        'target_formats': targetFormats,
    };

    final response = await _post(textTo3dPath, body);
    final decoded = _decodeBody(response);

    final result = decoded['result'];
    if (result is! String || result.isEmpty) {
      throw const MeshyException(
        message:
            'Meshy no devolvió un identificador de tarea. Inténtalo de nuevo más tarde.',
        kind: MeshyErrorKind.server,
      );
    }
    return result;
  }

  /// Paso 2: consulta el estado de una tarea una sola vez.
  Future<MeshyTask> getTask(String taskId) async {
    final uri = Uri.parse('$baseUrl$textTo3dPath/$taskId');
    http.Response response;
    try {
      response = await _client
          .get(uri, headers: _headers)
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const MeshyException(
        message: 'Meshy tardó demasiado en responder. Se reintentará el sondeo.',
        kind: MeshyErrorKind.network,
        isRetryable: true,
      );
    } on SocketException catch (error) {
      throw MeshyException(
        message: 'No hay conexión con Meshy (${error.osError?.message ?? 'red'}).',
        kind: MeshyErrorKind.network,
        isRetryable: true,
      );
    } on http.ClientException catch (error) {
      throw MeshyException(
        message: 'Fallo de red al consultar la tarea: ${error.message}',
        kind: MeshyErrorKind.network,
        isRetryable: true,
      );
    }

    _throwIfError(response);

    final decoded = _decodeBody(response);
    return MeshyTask.fromJson(decoded);
  }

  /// Paso 2 completo: sondea hasta que la tarea termina o se agota [maxWait].
  ///
  /// [onProgress] se llama con cada actualización para refrescar la UI.
  /// [shouldCancel] permite abortar desde la pantalla.
  Future<MeshyTask> waitForCompletion(
    String taskId, {
    Duration maxWait = defaultMaxWait,
    void Function(MeshyTask task)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final deadline = DateTime.now().add(maxWait);
    MeshyTask? lastTask;

    while (!_disposed) {
      if (shouldCancel?.call() ?? false) {
        throw MeshyException(
          message: 'Sondeo detenido por el usuario. La tarea sigue en Meshy '
              'con el identificador $taskId: podrás consultarla más tarde.',
          kind: MeshyErrorKind.timeout,
          taskId: taskId,
        );
      }

      // Un fallo de red puntual no invalida la tarea: se reintenta el sondeo.
      try {
        final task = await getTask(taskId);
        lastTask = task;
        onProgress?.call(task);

        if (task.status.isTerminal) {
          if (task.status == MeshyTaskStatus.failed) {
            throw MeshyException(
              message: task.errorMessage ??
                  'Meshy no pudo generar el modelo con este prompt. Prueba a describirlo de otra forma.',
              kind: MeshyErrorKind.taskFailed,
              taskId: taskId,
              isRetryable: true,
            );
          }
          if (task.status == MeshyTaskStatus.canceled) {
            throw MeshyException(
              message: 'La tarea se canceló en Meshy.',
              kind: MeshyErrorKind.taskCanceled,
              taskId: taskId,
              isRetryable: true,
            );
          }
          return task;
        }
      } on MeshyException catch (error) {
        // Solo se ignoran los fallos de red; el resto se propaga.
        if (error.kind != MeshyErrorKind.network) rethrow;
        onProgress?.call(lastTask ??
            MeshyTask(
              id: taskId,
              status: MeshyTaskStatus.pending,
              progress: 0,
            ));
      }

      if (DateTime.now().isAfter(deadline)) {
        throw MeshyException(
          message: 'La generación sigue en curso en Meshy tras '
              '${maxWait.inMinutes} minutos. La tarea no se ha perdido: '
              'vuelve a consultarla con su identificador.',
          kind: MeshyErrorKind.timeout,
          taskId: taskId,
          isRetryable: true,
        );
      }

      await Future<void>.delayed(pollInterval);
    }

    throw MeshyException(
      message: 'El sondeo se detuvo porque la pantalla se cerró. '
          'La tarea continúa en Meshy con el identificador $taskId.',
      kind: MeshyErrorKind.timeout,
      taskId: taskId,
    );
  }

  /// Paso 3: descarga el `.glb` y lo devuelve en memoria.
  ///
  /// Se separa de [downloadToFile] para poder usarlo desde pruebas.
  Future<Uint8List> downloadModelBytes(String url) async {
    final uri = Uri.parse(url);
    try {
      final response = await _client.get(uri).timeout(const Duration(minutes: 2));
      if (response.statusCode != 200) {
        throw MeshyException(
          message:
              'No se pudo descargar el modelo (HTTP ${response.statusCode}).',
          kind: MeshyErrorKind.network,
          statusCode: response.statusCode,
          isRetryable: true,
        );
      }
      return response.bodyBytes;
    } on TimeoutException {
      throw const MeshyException(
        message: 'La descarga del modelo tardó demasiado.',
        kind: MeshyErrorKind.network,
        isRetryable: true,
      );
    } on SocketException {
      throw const MeshyException(
        message: 'Sin conexión para descargar el modelo.',
        kind: MeshyErrorKind.network,
        isRetryable: true,
      );
    }
  }

  /// Consulta el saldo de créditos (`GET /openapi/v1/balance`).
  ///
  /// Se usa para avisar antes de gastar créditos. Devuelve `null` si la
  /// respuesta no trae el campo esperado.
  Future<int?> getBalance() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/openapi/v1/balance'),
            headers: _headers,
          )
          .timeout(requestTimeout);
      if (response.statusCode != 200) return null;
      final decoded = _decodeBody(response);
      final balance = decoded['balance'];
      return balance is num ? balance.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  /// Libera el cliente HTTP.
  void dispose() {
    _disposed = true;
    _client.close();
  }

  // --- Internos --------------------------------------------------------------

  /// Ejecuta el `POST` y traduce cualquier fallo a [MeshyException].
  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await _client
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(requestTimeout);
      _throwIfError(response);
      return response;
    } on TimeoutException {
      // Importante: no se reintenta. La tarea puede haberse creado igualmente.
      throw const MeshyException(
        message:
            'Meshy no respondió a tiempo. La tarea puede haberse creado igualmente: '
            'espera un minuto y consulta tus tareas antes de volver a enviarla, '
            'para no gastar créditos dos veces.',
        kind: MeshyErrorKind.network,
        isRetryable: false,
      );
    } on SocketException {
      throw const MeshyException(
        message: 'Sin conexión con Meshy. Comprueba tu red e inténtalo de nuevo.',
        kind: MeshyErrorKind.network,
        isRetryable: true,
      );
    } on http.ClientException catch (error) {
      throw MeshyException(
        message: 'Fallo de red al enviar el diseño: ${error.message}',
        kind: MeshyErrorKind.network,
        isRetryable: false,
      );
    }
  }

  /// Traduce los códigos de error documentados a mensajes accionables.
  void _throwIfError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    final detail = _extractMessage(response.body);

    switch (response.statusCode) {
      case 400:
        throw MeshyException(
          message: detail ??
              'Meshy rechazó la petición: revisa el prompt y vuelve a intentarlo.',
          kind: MeshyErrorKind.badRequest,
          statusCode: 400,
        );
      case 401:
        throw MeshyException(
          message: 'La clave de API de Meshy no es válida. '
              'Revisa MESHY_API_KEY en tu .env o en --dart-define.',
          kind: MeshyErrorKind.unauthorized,
          statusCode: 401,
        );
      case 402:
        throw MeshyException(
          message: detail ??
              'Meshy requiere un plan de pago para crear tareas, o te has quedado sin créditos.',
          kind: MeshyErrorKind.paymentRequired,
          statusCode: 402,
        );
      case 429:
        throw MeshyException(
          message: 'Has superado el límite de peticiones de Meshy. '
              'Espera unos segundos antes de reintentar.',
          kind: MeshyErrorKind.rateLimited,
          statusCode: 429,
          isRetryable: true,
        );
      default:
        throw MeshyException(
          message: detail ??
              'Meshy devolvió un error inesperado (HTTP ${response.statusCode}).',
          kind: MeshyErrorKind.server,
          statusCode: response.statusCode,
          isRetryable: response.statusCode >= 500,
        );
    }
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      throw const MeshyException(
        message: 'Meshy devolvió una respuesta con un formato inesperado.',
        kind: MeshyErrorKind.server,
      );
    } on FormatException {
      throw const MeshyException(
        message: 'La respuesta de Meshy no es JSON válido.',
        kind: MeshyErrorKind.server,
      );
    } catch (error) {
      if (error is MeshyException) rethrow;
      throw const MeshyException(
        message: 'No se pudo interpretar la respuesta de Meshy.',
        kind: MeshyErrorKind.server,
      );
    }
  }

  /// Extrae un mensaje legible del cuerpo de error, si lo hay.
  static String? _extractMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        for (final key in ['message', 'error', 'detail']) {
          final value = decoded[key];
          if (value is String && value.isNotEmpty) return value;
        }
      }
    } catch (_) {
      // Cuerpo no JSON: se ignora.
    }
    return null;
  }
}
