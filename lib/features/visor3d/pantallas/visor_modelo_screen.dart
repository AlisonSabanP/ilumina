import 'dart:io';

import 'package:flutter/material.dart';
import 'package:power3d/power3d.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../features/accesibilidad/widgets/accessibility_fab.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../generacion3d/modelos/meshy_models.dart';
import '../../generacion3d/providers/generation_provider.dart';
import '../servicios/model_download_service.dart';

/// Visor 3D del modelo generado.
///
/// Usa `Power3D.fromNetwork`, que carga el `.glb` en un visor Babylon.js
/// embebido en un WebView. El [Power3DController] expone el control fino:
///
///  * `updateRotation`  -> activar/desactivar la rotación automática.
///  * `resetView`       -> centrar la cámara.
///  * `setLockPosition` -> bloquear el paneo (evita "perder" la pieza).
///  * `updateZoom`      -> fijar límites de zoom razonables.
///
/// Se aplican límites de zoom desde el primer momento para que un usuario con
/// dificultades motrices no pueda perder el modelo fuera de la pantalla.
class VisorModeloScreen extends StatefulWidget {
  const VisorModeloScreen({super.key, required this.model});

  final GeneratedModel model;

  static Route<void> route(GeneratedModel model) => MaterialPageRoute<void>(
        builder: (_) => VisorModeloScreen(model: model),
      );

  @override
  State<VisorModeloScreen> createState() => _VisorModeloScreenState();
}

class _VisorModeloScreenState extends State<VisorModeloScreen> {
  final Power3DController _controller = Power3DController();
  final ModelDownloadService _downloader = ModelDownloadService();

  bool _positionLocked = false;
  bool _busy = false;
  String? _statusMessage;
  String? _localPath;

  /// Se usa la URL local si el modelo ya está descargado: así el visor
  /// funciona sin conexión.
  String get _modelUrl {
    final local = _localPath;
    if (local != null && File(local).existsSync()) {
      return Uri.file(local).toString();
    }
    return widget.model.glbUrl;
  }

  @override
  void initState() {
    super.initState();
    _configureController();
    _checkExistingDownload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Aplica los límites de navegación nada más crear el visor.
  Future<void> _configureController() async {
    // `initialize()` es síncrono: solo marca el estado como listo. El WebView
    // llama a este mismo método en `onLoadStop`, así que aquí únicamente se
    // fijan los límites de navegación.
    _controller.initialize();
    await _controller.updateZoom(enabled: true, min: 0.4, max: 4.0);
    await _controller.updateRotation(
      enabled: true,
      speed: 1.0,
      direction: RotationDirection.clockwise,
    );
    await _controller.setLockPosition(_positionLocked);
    if (mounted) setState(() {});
  }

  Future<void> _checkExistingDownload() async {
    final path = await _downloader.existingPath(
      widget.model.id,
      title: widget.model.title,
    );
    if (path != null && mounted) {
      setState(() {
        _localPath = path;
        _statusMessage = 'Modelo guardado en el dispositivo.';
      });
    }
  }

  Future<void> _toggleRotation(bool enabled) async {
    await _controller.updateRotation(enabled: enabled, speed: 1.0);
    if (!mounted) return;
    _announce(enabled ? 'Rotación automática activada' : 'Rotación detenida');
  }

  Future<void> _resetView() async {
    await _controller.resetView();
    if (!mounted) return;
    _announce('Cámara centrada');
  }

  Future<void> _togglePositionLock() async {
    setState(() => _positionLocked = !_positionLocked);
    await _controller.setLockPosition(_positionLocked);
    if (!mounted) return;
    _announce(
      _positionLocked
          ? 'Paneo bloqueado: el modelo ya no se puede mover'
          : 'Paneo desbloqueado',
    );
  }

  /// Descarga el `.glb` a almacenamiento local.
  Future<void> _download() async {
    setState(() {
      _busy = true;
      _statusMessage = 'Descargando el modelo...';
    });
    try {
      final path = await _downloader.download(
        id: widget.model.id,
        url: widget.model.glbUrl,
        title: widget.model.title,
      );
      if (!mounted) return;
      setState(() {
        _localPath = path;
        _statusMessage = 'Modelo guardado en el dispositivo.';
      });
      context.read<GenerationProvider>().markDownloaded(widget.model.id, path);
      _announce('Modelo descargado');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = error.toString().replaceFirst('MeshyException', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Descarga (si hace falta) y comparte el archivo.
  Future<void> _share() async {
    setState(() {
      _busy = true;
      _statusMessage = 'Preparando el archivo para compartir...';
    });
    try {
      final path = _localPath ??
          await _downloader.download(
            id: widget.model.id,
            url: widget.model.glbUrl,
            title: widget.model.title,
          );
      if (!mounted) return;
      setState(() => _localPath = path);
      context.read<GenerationProvider>().markDownloaded(widget.model.id, path);
      await _downloader.shareFile(path, title: widget.model.title);
      if (!mounted) return;
      setState(() => _statusMessage = 'Archivo listo para compartir.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = error.toString().replaceFirst('MeshyException', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _announce(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final reduceMotion = a11y.reduceMotion;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.model.title, overflow: TextOverflow.ellipsis),
        actions: const [AccessibilityAppBarAction()],
      ),
      body: Column(
        children: [
          // --- Visor 3D ---
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    label:
                        'Visor 3D del modelo ${widget.model.title}. Arrastra para rotar y pellizca para acercar.',
                    container: true,
                    child: Power3D.fromNetwork(
                      _modelUrl,
                      controller: _controller,
                      loadingUi: (context, controller) =>
                          const LuminaLoadingView(
                        message: 'Cargando el modelo 3D...',
                      ),
                      errorWidget: LuminaErrorView(
                        title: 'No se pudo mostrar el modelo',
                        message:
                            'Comprueba tu conexión. Si el modelo lleva más de tres días '
                            'en Meshy, puede haber caducado: vuelve a generarlo.',
                        onRetry: _configureController,
                        retryLabel: 'Reintentar',
                      ),
                    ),
                  ),
                ),
                // Indicador de estado superpuesto.
                if (_statusMessage != null)
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: Material(
                      color: theme.colorScheme.inverseSurface,
                      borderRadius: AppRadius.cardRadius,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            if (_busy)
                              const Padding(
                                padding: EdgeInsets.only(right: AppSpacing.sm),
                                child: SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onInverseSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // --- Controles ---
          SafeArea(
            top: false,
            child: Container(
              color: theme.colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.center,
                    children: [
                      _ViewerButton(
                        label: 'Rotar',
                        icon: Icons.rotate_right,
                        hint: 'Inicia la rotación automática del modelo',
                        onPressed: () => _toggleRotation(true),
                      ),
                      _ViewerButton(
                        label: 'Detener',
                        icon: Icons.pause,
                        hint: 'Detiene la rotación automática',
                        onPressed: () => _toggleRotation(false),
                      ),
                      _ViewerButton(
                        label: 'Centrar',
                        icon: Icons.center_focus_strong,
                        hint: 'Devuelve la cámara a la posición inicial',
                        onPressed: _resetView,
                      ),
                      _ViewerButton(
                        label: _positionLocked ? 'Soltar' : 'Bloquear',
                        icon: _positionLocked
                            ? Icons.lock_open
                            : Icons.lock_outline,
                        hint: _positionLocked
                            ? 'Permite volver a mover el modelo'
                            : 'Impide mover el modelo por accidente',
                        onPressed: _togglePositionLock,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AccessibleButton(
                    label: _localPath == null
                        ? 'Descargar .glb'
                        : 'Descargar otra vez',
                    icon: Icons.download,
                    pictogram: Icons.download,
                    busy: _busy,
                    onPressed: _busy ? null : _download,
                    hint: 'Guarda el archivo del modelo en el dispositivo',
                  ),
                  SizedBox(height: a11y.controlGap),
                  AccessibleButton(
                    label: 'Compartir modelo',
                    icon: Icons.share,
                    pictogram: Icons.share,
                    isPrimary: false,
                    busy: _busy,
                    onPressed: _busy ? null : _share,
                    hint: 'Comparte el archivo con otras aplicaciones',
                  ),
                  if (reduceMotion) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'La rotación automática está limitada por el modo reducir movimiento.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: const AccessibilityFab(heroTag: 'visor.a11y'),
    );
  }
}

/// Botón compacto del visor, con área táctil adaptada al modo botones grandes.
class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.hint,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final a11y = AccessibilityProvider.of(context);

    return Semantics(
      button: true,
      label: label,
      hint: hint,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: a11y.minTapTarget,
          minHeight: a11y.minTapTarget,
        ),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, semanticLabel: ''),
          label: Text(label),
        ),
      ),
    );
  }
}
