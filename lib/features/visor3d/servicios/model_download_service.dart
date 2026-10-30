import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../generacion3d/modelos/meshy_models.dart';
import '../../generacion3d/servicios/meshy_service.dart';

/// Descarga y comparte los modelos `.glb` generados.
///
/// Los archivos se guardan en el directorio de documentos de la app, dentro de
/// `lumina_models/`, con un nombre estable derivado del identificador de la
/// tarea para poder reutilizarlos sin volver a descargarlos.
///
/// Nota sobre la caducidad: Meshy solo conserva los archivos generados durante
/// 3 días para cuentas no Enterprise. Por eso Lumina descarga el `.glb` a
/// almacenamiento local en cuanto el usuario lo pide, en lugar de depender de
/// la URL remota.
class ModelDownloadService {
  ModelDownloadService({MeshyService? service})
      : _service = service ?? _sharedService;

  /// Un solo cliente HTTP compartido evita abrir una conexión por descarga.
  static final MeshyService _sharedService = MeshyService();

  final MeshyService _service;

  static const String folderName = 'lumina_models';

  /// Nombre de archivo seguro para el sistema de ficheros.
  static String fileNameFor(String id, {String? title}) {
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeTitle = (title ?? '')
        .replaceAll(RegExp(r'[^A-Za-z0-9áéíóúÁÉÍÓÚñÑ _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final prefix = safeTitle.isEmpty ? 'lumina' : safeTitle;
    return '${prefix}_$safeId.glb';
  }

  /// Carpeta donde se guardan los modelos.
  Future<Directory> modelsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Devuelve la ruta local si el modelo ya está descargado.
  Future<String?> existingPath(String id, {String? title}) async {
    final dir = await modelsDirectory();
    final file = File('${dir.path}/${fileNameFor(id, title: title)}');
    return await file.exists() ? file.path : null;
  }

  /// Descarga el `.glb` desde [url] y devuelve la ruta local.
  ///
  /// Lanza [MeshyException] con un mensaje legible si falla la red o el disco.
  Future<String> download({
    required String id,
    required String url,
    String? title,
  }) async {
    try {
      final dir = await modelsDirectory();
      final file = File('${dir.path}/${fileNameFor(id, title: title)}');

      // Si ya existe y tiene contenido, no se vuelve a descargar.
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }

      final bytes = await _service.downloadModelBytes(url);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on MeshyException {
      rethrow;
    } on FileSystemException catch (error) {
      throw MeshyException(
        message:
            'No se pudo guardar el modelo en el dispositivo: ${error.message}',
        kind: MeshyErrorKind.server,
        isRetryable: true,
      );
    }
  }

  /// Nombre de archivo STL para una pieza, con extensión `.stl`.
  static String stlFileNameFor(String id, {String? title}) =>
      fileNameFor(id, title: title).replaceAll(RegExp(r'\.glb$'), '.stl');

  /// Descarga el `.stl` desde [url] y devuelve la ruta local.
  ///
  /// Es el formato que se entrega para imprimir: los laminadores lo abren tal
  /// cual, sin conversiones ni pasos intermedios.
  Future<String> downloadStl({
    required String id,
    required String url,
    String? title,
  }) async {
    try {
      final dir = await modelsDirectory();
      final file = File('${dir.path}/${stlFileNameFor(id, title: title)}');
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
      final bytes = await _service.downloadModelBytes(url);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on MeshyException {
      rethrow;
    } on FileSystemException catch (error) {
      throw MeshyException(
        message:
            'No se pudo guardar el archivo STL en el dispositivo: ${error.message}',
        kind: MeshyErrorKind.server,
        isRetryable: true,
      );
    }
  }

  /// Copia a disco un `.glb` **empaquetado en la app** y devuelve su ruta.
  ///
  /// Es el caso de la pieza de demostración: no hay nada que descargar, el
  /// archivo viaja dentro de la app. Se copia para que el resto del flujo
  /// (compartir, abrir en el laminador) funcione igual que con un modelo real.
  Future<String> exportAsset({
    required String assetPath,
    required String id,
    String? title,
  }) async {
    try {
      final dir = await modelsDirectory();
      final file = File('${dir.path}/${fileNameFor(id, title: title)}');
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    } on FlutterError catch (error) {
      throw MeshyException(
        message: 'No se pudo preparar la pieza de demostración: ${error.message}',
        kind: MeshyErrorKind.server,
      );
    } on FileSystemException catch (error) {
      throw MeshyException(
        message:
            'No se pudo guardar el modelo en el dispositivo: ${error.message}',
        kind: MeshyErrorKind.server,
        isRetryable: true,
      );
    }
  }

  /// Abre la hoja de compartir del sistema con el archivo `.glb`.
  Future<ShareResult> shareFile(String path, {String? title}) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const MeshyException(
        message: 'El archivo ya no está en el dispositivo. Descárgalo otra vez.',
        kind: MeshyErrorKind.server,
      );
    }

    return SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path, mimeType: 'model/gltf-binary')],
        subject: title == null ? 'Modelo 3D de Lumina' : '$title — Lumina',
        text: 'Modelo 3D generado con Lumina. Ábrelo en tu laminador '
            '(Cura, PrusaSlicer, Bambu Studio) o en cualquier visor de glTF.',
      ),
    );
  }

  /// Abre la hoja de compartir con el archivo `.stl`.
  ///
  /// El texto que acompaña al archivo explica el paso siguiente, porque quien
  /// recibe un STL necesita saber que se abre en un laminador.
  Future<ShareResult> shareStlFile(String path, {String? title}) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const MeshyException(
        message: 'El archivo ya no está en el dispositivo. Descárgalo otra vez.',
        kind: MeshyErrorKind.server,
      );
    }

    return SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path, mimeType: 'model/stl')],
        subject: title == null ? 'Pieza Lumina para imprimir' : '$title — Lumina',
        text: 'Pieza lista para imprimir en 3D, generada con Lumina. '
            'Ábrela en tu laminador (Cura, PrusaSlicer, Bambu Studio).',
      ),
    );
  }

  /// Borra todos los modelos descargados.
  Future<void> clearAll() async {
    final dir = await modelsDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Tamaño total ocupado por los modelos descargados.
  Future<int> totalBytes() async {
    try {
      final dir = await modelsDirectory();
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (error) {
      debugPrint('No se pudo calcular el tamaño de los modelos: $error');
      return 0;
    }
  }
}
