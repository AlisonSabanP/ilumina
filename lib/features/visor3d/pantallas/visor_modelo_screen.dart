import 'dart:async';
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
/// Carga el `.glb` con `Power3D`: `fromFile` para las piezas generadas en el
/// dispositivo y `fromNetwork` para los modelos de Meshy. El
/// [Power3DController] expone el control fino:
///
///  * `setCameraPosition` -> vista inicial de tres cuartos (ver [_cameraAlpha]).
///  * `updateRotation`    -> activar/desactivar la rotación automática.
///  * `setLockPosition`   -> bloquear el paneo (evita "perder" la pieza).
///  * `updateZoom`        -> fijar límites de zoom razonables.
///
/// No se usa `resetView` del paquete para el botón "Centrar": recrea la cámara
/// por defecto, que mira la pieza de frente y la aplana. Ver [_resetView].
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

  /// Vista de tres cuartos con la que se abre el visor.
  ///
  /// La cámara por defecto de `power3d` mira la pieza **de frente**
  /// (`alpha = -1.57`, unos -90°), que es justo el peor ángulo para una pieza
  /// alta y estrecha: se ve de canto y parece un círculo. Con `alpha` a -0.75
  /// la pieza se gira unos 45° y se aprecia el volumen; `beta` a 1.15 la deja
  /// algo por encima del ecuador, como una foto de producto.
  static const double _cameraAlpha = -0.75;
  static const double _cameraBeta = 1.15;

  /// Radio con el que se encuadra la pieza al abrir el visor.
  ///
  /// Es algo menor que el 3.0 por defecto porque las piezas de Lumina son
  /// pequeñas (una etiqueta Braille o un engrosador miden pocos centímetros) y
  /// con el encuadre por defecto quedaban diminutas en el centro.
  static const double _cameraRadius = 2.4;

  bool _positionLocked = false;
  bool _busy = false;
  String? _statusMessage;
  String? _localPath;

  /// Evita reaplicar los ajustes de vista más de una vez.
  ///
  /// El listener [_onViewerState] se dispara con cada cambio de estado del
  /// controlador; sin esta bandera, cada reaplicación volvería a notificar y
  /// entraríamos en el mismo bucle que había con `onModelLoaded`.
  bool _viewSettingsApplied = false;

  /// `true` si el modelo es la pieza de demostración incluida en la app.
  bool get _isDemo => widget.model.isLocalAsset;

  /// Ruta local del `.glb` si ya está en el dispositivo.
  ///
  /// Es el caso de las piezas construidas por Lumina: el archivo ya existe
  /// cuando se abre el visor, así que se carga desde disco con
  /// `Power3D.fromFile` y no hace falta ninguna descarga.
  String? get _localGlbPath {
    for (final candidate in <String?>[_localPath, widget.model.localPath]) {
      if (candidate != null && candidate.isNotEmpty && File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  /// Se usa el archivo local si existe: así el visor funciona sin conexión.
  /// Si no, la URL remota de Meshy.
  String get _modelUrl {
    final local = _localGlbPath;
    if (local != null) return Uri.file(local).toString();
    return widget.model.glbUrl;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onViewerState);
    _configureController();
    _checkExistingDownload();
  }

  @override
  void dispose() {
    _controller.removeListener(_onViewerState);
    _controller.dispose();
    super.dispose();
  }

  /// Reaplica los ajustes de vista cuando la escena ya está montada.
  ///
  /// `updateZoom`, `updateRotation` y `setLockPosition` escriben en el
  /// controlador *y* mandan el ajuste al WebView. En `initState` el WebView
  /// todavía no existe, así que sin esto los límites de zoom y el bloqueo de
  /// paneo nunca llegaban a la vista. Se aplican una sola vez, cuando el modelo
  /// termina de cargar.
  ///
  /// Nota: no se puede usar `onModelLoaded` del paquete para esto. Ese callback
  /// se dispara desde su propio listener de estado, y `Power3DState` no define
  /// `operator ==`, así que cualquier `copyWith` notifica aunque no cambie nada:
  /// escribir el estado desde el callback provoca un bucle infinito que congela
  /// la app. La bandera [_viewSettingsApplied] corta ese bucle aquí.
  void _onViewerState() {
    if (_viewSettingsApplied) return;
    if (_controller.value.status != Power3DStatus.loaded) return;
    // La bandera se pone ANTES de tocar el controlador: cada escritura notifica
    // a los listeners y volveríamos a entrar en este método.
    _viewSettingsApplied = true;
    // En microtask para no escribir el estado durante la notificación en curso.
    unawaited(Future.microtask(_applyViewSettings));
  }

  Future<void> _applyViewSettings() async {
    await _controller.updateZoom(enabled: true, min: 0.4, max: 4.0);
    await _controller.updateRotation(
      enabled: true,
      speed: 1.0,
      direction: RotationDirection.clockwise,
    );
    await _controller.setLockPosition(_positionLocked);
  }

  /// Prepara el controlador y fija la cámara inicial.
  ///
  /// Se llama en `initState` y desde el botón "Reintentar" del visor.
  Future<void> _configureController() async {
    // Un reintento vuelve a cargar el modelo, así que hay que permitir que los
    // ajustes de vista se reapliquen a la escena nueva.
    _viewSettingsApplied = false;
    // `initialize()` es síncrono: solo marca el estado como listo y reenvía la
    // configuración que ya esté en `value`.
    _controller.initialize();
    // La posición de cámara sí conviene fijarla ya: `power3d` la reaplica por su
    // cuenta al cargar el modelo leyendo `value`.
    await _applyInitialCamera();
    if (mounted) setState(() {});
  }

  /// Coloca la cámara en la vista de tres cuartos.
  ///
  /// Ojo: `power3d` ya reaplica `cameraAlpha`/`cameraBeta`/`cameraRadius` por su
  /// cuenta cada vez que carga el modelo (`initialize()` y el mensaje `loaded`
  /// lo hacen leyendo `value`), así que basta con dejar el valor en el
  /// controlador. Ver [_onViewerState] para el porqué de no usar `onModelLoaded`.
  Future<void> _applyInitialCamera() async {
    try {
      await _controller.setCameraPosition(
        alpha: _cameraAlpha,
        beta: _cameraBeta,
        radius: _cameraRadius,
      );
    } catch (error) {
      // Si el WebView aún no está listo, `initialize()` reaplicará el valor
      // cuando termine de cargar.
      debugPrint('No se pudo fijar la cámara inicial: $error');
    }
  }

  Future<void> _checkExistingDownload() async {
    // La pieza de demostración vive en los assets: no hay nada que buscar.
    if (_isDemo) return;
    // Las piezas locales ya están en disco: no hay nada que buscar.
    if (widget.model.isLocal) {
      if (mounted && widget.model.stlPath != null) {
        setState(() {
          _statusMessage = 'Archivo STL listo para imprimir.';
        });
      }
      return;
    }
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

  /// Devuelve la cámara a la vista de tres cuartos.
  ///
  /// No se usa `resetView()` del paquete a propósito: ese método recrea la
  /// cámara por defecto, que mira la pieza de frente (`alpha = -1.57`), que es
  /// justo el ángulo que hace que una pieza alta parezca un círculo. Centrar
  /// debe devolver la pieza a la vista buena, no a la mala.
  Future<void> _resetView() async {
    await _applyInitialCamera();
    if (!mounted) return;
    _announce('Vista restablecida');
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

  /// Guarda el archivo STL en el dispositivo, listo para laminar.
  ///
  /// El STL es el formato que abre cualquier laminador (Cura, PrusaSlicer,
  /// Bambu Studio) sin conversiones, así que es lo que Lumina entrega para
  /// imprimir. Las piezas construidas en el dispositivo ya lo tienen en disco;
  /// las de Meshy se descargan desde su URL.
  Future<void> _download() async {
    setState(() {
      _busy = true;
      _statusMessage = 'Preparando el archivo STL...';
    });
    try {
      final path = await _ensureDownloadable();
      if (!mounted) return;
      setState(() {
        _localPath = path;
        _statusMessage = 'Archivo STL guardado en el dispositivo.';
      });
      context.read<GenerationProvider>().markDownloaded(
            widget.model.id,
            widget.model.localPath ?? path,
            stlPath: path,
          );
      _announce('Archivo STL guardado');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = error.toString().replaceFirst('MeshyException', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Descarga (si hace falta) y comparte el archivo STL.
  Future<void> _share() async {
    setState(() {
      _busy = true;
      _statusMessage = 'Preparando el archivo para compartir...';
    });
    try {
      final path = await _ensureDownloadable();
      if (!mounted) return;
      setState(() => _localPath = path);
      context.read<GenerationProvider>().markDownloaded(
            widget.model.id,
            widget.model.localPath ?? path,
            stlPath: path,
          );
      if (_isDemo) {
        await _downloader.shareFile(path, title: widget.model.title);
      } else {
        await _downloader.shareStlFile(path, title: widget.model.title);
      }
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

  /// Devuelve la ruta del archivo para descargar o compartir.
  ///
  /// Tres casos: la pieza de demostración se copia desde el asset, la local ya
  /// está escrita en disco y la de Meshy se descarga de su URL.
  Future<String> _ensureDownloadable() async {
    // Pieza de demostración: se copia desde los assets de la app.
    if (_isDemo) {
      return _downloader.exportAsset(
        assetPath: widget.model.assetPath!,
        id: widget.model.id,
        title: widget.model.title,
      );
    }
    return _ensureStl();
  }

  /// Devuelve la ruta del STL, obteniéndolo por la vía que corresponda.
  Future<String> _ensureStl() async {
    // Pieza construida en el dispositivo: el STL ya está escrito.
    final existingStl = widget.model.stlPath;
    if (existingStl != null && File(existingStl).existsSync()) {
      return existingStl;
    }
    // Pieza de Meshy: se descarga el STL si lo hay; si no, el GLB.
    if (widget.model.stlUrl != null && widget.model.stlUrl!.isNotEmpty) {
      return _downloader.downloadStl(
        id: widget.model.id,
        url: widget.model.stlUrl!,
        title: widget.model.title,
      );
    }
    return _downloader.download(
      id: widget.model.id,
      url: widget.model.glbUrl,
      title: widget.model.title,
    );
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

  /// Construye el visor con la fuente que corresponda.
  ///
  /// Tres caminos, en este orden de preferencia:
  ///  * `fromAsset`:   la pieza de demostración incluida en la app.
  ///  * `fromFile`:    una pieza ya escrita en el disco del dispositivo.
  ///  * `fromNetwork`: un modelo de Meshy que aún hay que descargar.
  ///
  /// Se prefiere siempre la fuente local: el visor funciona sin conexión y sin
  /// esperas cuando el archivo ya está en el móvil.
  ///
  /// No se pasa `onModelLoaded`: ese callback se dispara desde el listener de
  /// estado del paquete y colocar la cámara desde ahí provoca un bucle infinito
  /// (ver [_applyInitialCamera]). El paquete ya reaplica la posición de cámara
  /// guardada en el controlador cuando la malla termina de cargar.
  Widget _buildViewer() {
    // Pieza de demostración: vive dentro de la app, no hay nada que descargar.
    if (_isDemo) {
      return Power3D.fromAsset(
        widget.model.assetPath!,
        controller: _controller,
        loadingUi: (context, controller) => const LuminaLoadingView(
          message: 'Cargando la pieza de ejemplo...',
        ),
        errorWidget: LuminaErrorView(
          title: 'No se pudo mostrar la pieza de ejemplo',
          message: 'La pieza incluida en la app no se pudo cargar.',
          onRetry: _configureController,
          retryLabel: 'Reintentar',
        ),
      );
    }

    final localPath = _localGlbPath;
    if (localPath != null) {
      return Power3D.fromFile(
        localPath,
        controller: _controller,
        loadingUi: (context, controller) => const LuminaLoadingView(
          message: 'Cargando tu pieza...',
        ),
        errorWidget: LuminaErrorView(
          title: 'No se pudo mostrar la pieza',
          message: 'El archivo del dispositivo no se pudo leer.',
          onRetry: _configureController,
          retryLabel: 'Reintentar',
        ),
      );
    }

    return Power3D.fromNetwork(
      _modelUrl,
      controller: _controller,
      loadingUi: (context, controller) => const LuminaLoadingView(
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
                    child: _buildViewer(),
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
                        hint: 'Devuelve la cámara a la vista inicial de tres cuartos',
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
                        ? 'Descargar STL'
                        : 'Descargar STL otra vez',
                    icon: Icons.download,
                    pictogram: Icons.download,
                    busy: _busy,
                    onPressed: _busy ? null : _download,
                    hint: 'Guarda el archivo STL, listo para el laminador',
                  ),
                  SizedBox(height: a11y.controlGap),
                  AccessibleButton(
                    label: 'Compartir STL',
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
