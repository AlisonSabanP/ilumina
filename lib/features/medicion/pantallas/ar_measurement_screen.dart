import 'dart:async';
import 'dart:io';

import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:neom_ar/neom_ar.dart';
// `ArMeasureController` no se reexporta desde `neom_ar.dart`; se importa su
// archivo directamente porque es la única forma de usar su máquina de estados.
// [VERIFICAR] Ruta interna del paquete: si `neom_ar` cambia de estructura en una
// versión futura, habrá que ajustar este import.
import 'package:neom_ar/ui/controllers/ar_measure_controller.dart';
import 'package:provider/provider.dart';
import 'package:sint/sint.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../modelos/measurement_models.dart';
import 'manual_measurement_screen.dart';

/// Pantalla de medición AR de objetos, basada en `neom_ar`.
///
/// `neom_ar` envuelve ARKit (iOS) y ARCore (Android) tras la interfaz
/// [ArService] y aporta el flujo de medición (dos toques -> distancia) en
/// [ArMeasureController]. Sin embargo, el widget de cámara real es específico
/// de cada plataforma (`ARKitSceneView` / `ArCoreView`), por lo que Lumina
/// construye esa vista aquí y conecta las dos piezas:
///
///   1. Crea el widget nativo de AR con detección de planos.
///   2. Al crearse, conecta el controlador nativo al [ArService] de `neom_ar`
///      (`attachController`), que es lo que habilita el hit test y los marcadores.
///   3. Captura los toques del usuario y los traduce a coordenadas normalizadas
///      (0-1) que es lo que espera [ArService.hitTest].
///   4. Cuando [ArMeasureController] obtiene una medición, Lumina la ofrece
///      para guardarla en el formulario.
///
/// [VERIFICAR] El paso 3 es el único punto no documentado por `neom_ar`: su
/// `ArMeasureController.onTap(x, y)` recibe coordenadas normalizadas, y en
/// ARCore el plugin entrega los resultados ya calculados mediante
/// `onPlaneTap`. Lumina usa el camino de hit test por coordenadas, que es el
/// que funciona igual en ambas plataformas, y además admite entrada manual
/// como respaldo si el hit test no devuelve resultados.
class ArMeasurementScreen extends StatefulWidget {
  const ArMeasurementScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const ArMeasurementScreen(),
      );

  @override
  State<ArMeasurementScreen> createState() => _ArMeasurementScreenState();
}

class _ArMeasurementScreenState extends State<ArMeasurementScreen> {
  late final ArMeasureController _arController;
  ArService? _service;

  bool _initializing = true;
  String? _initError;

  /// Medición aceptada más reciente, pendiente de guardar en el formulario.
  ArMeasurement? _pending;

  @override
  void initState() {
    super.initState();
    // `neom_ar` usa Sint (GetX-like) para su controlador. `Sint.put` registra la
    // dependencia para que el árbol interno del paquete la encuentre.
    _arController = Sint.put<ArMeasureController>(ArMeasureController());
    _service = ArPlatformFactory.create();
    _checkSupport();
  }

  @override
  void dispose() {
    _arController.onClose();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _checkSupport() async {
    try {
      final supported = await _service!.isSupported();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        if (!supported) {
          _initError =
              'Este dispositivo no soporta ARKit ni ARCore. Usa la entrada manual.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initError = 'No se pudo iniciar la cámara AR: $error';
      });
    }
  }

  /// Conecta el controlador nativo al [ArService] de `neom_ar`.
  void _attachArCore(ArCoreController controller) {
    final service = _service;
    if (service is ArcoreArService) {
      service.attachController(controller);
      // Los toques los procesa el propio plugin de ARCore.
      controller.onPlaneTap = (hits) {
        if (hits.isEmpty) return;
        final results = service.processHitResults(hits);
        if (results.isEmpty) return;
        _handleHitResult(results.first);
      };
    }
    setState(() {});
  }

  void _attachArKit(ARKitController controller) {
    final service = _service;
    if (service is ArkitArService) {
      service.attachController(controller);
    }
    setState(() {});
  }

  /// Traduce un resultado de hit test en una medición del controlador de
  /// `neom_ar`, respetando su máquina de estados (primer punto / segundo punto).
  Future<void> _handleHitResult(ArHitResult hit) async {
    final controller = _arController;
    final service = _service;
    if (service == null) return;

    try {
      switch (controller.measureState.value) {
        case ArMeasureState.idle:
          controller.startMeasuring();
          await _placeFirst(controller, service, hit);
        case ArMeasureState.scanning:
        case ArMeasureState.placingFirst:
          await _placeFirst(controller, service, hit);
        case ArMeasureState.placingSecond:
          await _placeSecond(controller, service, hit);
        case ArMeasureState.measured:
          // Se empieza una medición nueva limpiando los marcadores previos.
          await service.clearMarkers();
          controller.currentMeasurement.value = null;
          await _placeFirst(controller, service, hit);
      }
    } catch (error) {
      _showMessage('No se pudo registrar el punto: $error');
    }
  }

  /// Guarda el primer punto usando la API pública del controlador.
  ///
  /// Se usa el método público `onTap` del controlador con coordenadas
  /// normalizadas del centro de la pantalla cuando el hit test lo aporta la
  /// plataforma, y se replica su lógica mínima aquí para el caso en el que ya
  /// tenemos un [ArHitResult] calculado (ARCore).
  Future<void> _placeFirst(
    ArMeasureController controller,
    ArService service,
    ArHitResult hit,
  ) async {
    final markerId = await service.addMarker(hit, label: 'A');
    controller.measureState.value = ArMeasureState.placingSecond;
    controller.statusMessage.value = 'Toca el segundo punto del objeto';
    _firstHit = hit;
    _firstMarkerId = markerId;
  }

  Future<void> _placeSecond(
    ArMeasureController controller,
    ArService service,
    ArHitResult hit,
  ) async {
    final first = _firstHit;
    if (first == null) {
      controller.measureState.value = ArMeasureState.placingFirst;
      return;
    }

    final secondMarkerId = await service.addMarker(hit, label: 'B');
    final measurement = ArMeasurement(pointA: first.pose, pointB: hit.pose);
    await service.addDistanceLine(_firstMarkerId ?? '', secondMarkerId, measurement);

    controller.currentMeasurement.value = measurement;
    controller.measureState.value = ArMeasureState.measured;
    controller.statusMessage.value = measurement.formattedDistance;

    if (!mounted) return;
    setState(() => _pending = measurement);
  }

  ArHitResult? _firstHit;
  String? _firstMarkerId;

  /// Hit test por coordenadas normalizadas (iOS y respaldo en Android).
  Future<void> _onTapUp(TapUpDetails details, Size viewSize) async {
    final service = _service;
    if (service == null || viewSize.width == 0 || viewSize.height == 0) return;

    // `neom_ar` espera coordenadas normalizadas 0-1 y su implementación de
    // ARKit usa `assert(x > 0 && y > 0)`, por lo que se evitan los bordes.
    final x = (details.localPosition.dx / viewSize.width).clamp(0.01, 0.99);
    final y = (details.localPosition.dy / viewSize.height).clamp(0.01, 0.99);

    final results = await service.hitTest(x, y);
    if (results.isEmpty) {
      _showMessage(
        'No se detectó ninguna superficie. Mueve el dispositivo despacio '
        'para que AR encuentre un plano.',
      );
      return;
    }
    // El primer resultado es el más preciso, según la documentación de neom_ar.
    await _handleHitResult(results.first);
  }

  /// Reinicia la medición en curso.
  Future<void> _reset() async {
    await _service?.clearMarkers();
    _arController.reset();
    setState(() {
      _pending = null;
      _firstHit = null;
      _firstMarkerId = null;
    });
  }

  /// Guarda la medición pendiente en el formulario y cierra.
  void _accept() {
    final measurement = _pending;
    if (measurement == null) return;
    final label = _labelController.text.trim();
    context.read<FormularioProvider>().upsertMeasurement(
          Measurement(
            id: 'ar_${DateTime.now().microsecondsSinceEpoch}',
            label: label.isEmpty ? 'Distancia AR' : label,
            valueCm: measurement.distanceCm,
            kind: MeasurementKind.arDistance,
            source: MeasurementSource.ar,
            timestamp: DateTime.now(),
          ),
        );
    Navigator.of(context).maybePop();
  }

  final TextEditingController _labelController = TextEditingController();

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medir con AR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reiniciar la medición',
            onPressed: _reset,
          ),
        ],
      ),
      body: _buildBody(theme),
      floatingActionButton: const AccessibilityFab(heroTag: 'ar.a11y'),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_initializing) {
      return const LuminaLoadingView(message: 'Comprobando el soporte de AR...');
    }

    if (_initError != null) {
      return Column(
        children: [
          Expanded(
            child: LuminaErrorView(
              title: 'AR no disponible',
              message: _initError!,
              onRetry: () {
                setState(() {
                  _initializing = true;
                  _initError = null;
                });
                _checkSupport();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AccessibleButton(
              label: 'Introducir la medida a mano',
              icon: Icons.edit,
              pictogram: Icons.edit,
              onPressed: _openManualEntry,
              hint: 'Abre un formulario para escribir la medida en centímetros',
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onTapUp(details, size),
                child: _buildArView(),
              );
            },
          ),
        ),

        // Instrucciones en la parte superior.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Obx(
            () => Container(
              color: theme.colorScheme.inverseSurface.withValues(alpha: 0.85),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toca los dos extremos del objeto',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _arController.statusMessage.value.isEmpty
                          ? 'Mueve el dispositivo despacio para detectar superficies.'
                          : _arController.statusMessage.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Panel de la medición obtenida.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _pending == null
                  ? const SizedBox.shrink()
                  : _buildResultCard(theme, _pending!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(ThemeData theme, ArMeasurement measurement) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            label: 'Distancia medida: ${measurement.formattedDistance}',
            child: Text(
              measurement.formattedDistance,
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: '¿Qué has medido?',
              helperText: 'Por ejemplo: diámetro del mango',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AccessibleButton(
                  label: 'Descartar',
                  icon: Icons.close,
                  isPrimary: false,
                  onPressed: _reset,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AccessibleButton(
                  label: 'Guardar',
                  icon: Icons.check,
                  pictogram: Icons.check,
                  onPressed: _accept,
                  hint: 'Guarda la medida en el formulario',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Vista nativa de AR por plataforma.
  Widget _buildArView() {
    if (kIsWeb) {
      return const LuminaErrorView(
        title: 'AR no disponible en web',
        message: 'La medición AR necesita un dispositivo Android o iOS.',
      );
    }

    if (Platform.isIOS) {
      return ARKitSceneView(
        configuration: ARKitConfiguration.worldTracking,
        planeDetection: ARPlaneDetection.horizontalAndVertical,
        showFeaturePoints: true,
        showStatistics: false,
        onARKitViewCreated: _attachArKit,
      );
    }

    if (Platform.isAndroid) {
      return ArCoreView(
        enablePlaneRenderer: true,
        enableTapRecognizer: false,
        onArCoreViewCreated: _attachArCore,
      );
    }

    return const LuminaErrorView(
      title: 'Plataforma no soportada',
      message: 'La medición AR solo funciona en Android e iOS.',
    );
  }

  void _openManualEntry() {
    Navigator.of(context).push(
      ManualMeasurementScreen.route(
        defaultLabel: 'Distancia',
        suggestedLabels: const [
          'Largo del objeto',
          'Ancho del objeto',
          'Alto del objeto',
          'Diámetro del mango',
        ],
      ),
    );
  }
}
