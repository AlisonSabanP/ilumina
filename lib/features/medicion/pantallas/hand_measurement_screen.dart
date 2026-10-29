import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../core/app_theme.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../modelos/measurement_models.dart';
import '../servicios/hand_detector.dart';
import 'manual_measurement_screen.dart';

/// Detección de la mano y cálculo de medidas con `hand_landmarker`.
///
/// ## Plataforma
/// `hand_landmarker` es **exclusivo de Android**: su implementación usa un
/// puente JNI sobre MediaPipe y no tiene equivalente para iOS. Por eso esta
/// pantalla comprueba la plataforma antes de importar nada del plugin: en iOS
/// se ofrece directamente la medición AR y la entrada manual, sin intentar
/// cargar una librería nativa que no existe.
///
/// ## Cómo se obtienen las medidas
/// `HandLandmarkerPlugin.landmarkStream` emite listas de 21 [Landmark]
/// normalizados (x, y en 0-1, z relativo). Esos puntos **no tienen escala
/// métrica**, así que [HandMetrics.fromLandmarks] necesita una calibración:
/// el usuario indica el ancho real de su palma en centímetros y de ahí se
/// deduce el factor cm/píxel. Sin calibración las medidas se muestran en
/// unidades relativas y se marcan como tales.
///
/// ## Rendimiento
/// `processFrame` se alimenta con `startImageStream` en formato YUV420, que es
/// lo que el plugin espera (tres planos: Y, U, V).
class HandMeasurementScreen extends StatefulWidget {
  const HandMeasurementScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const HandMeasurementScreen(),
      );

  @override
  State<HandMeasurementScreen> createState() => _HandMeasurementScreenState();
}

class _HandMeasurementScreenState extends State<HandMeasurementScreen> {
  CameraController? _camera;
  HandDetector? _detector;
  StreamSubscription<List<HandPoint>>? _landmarkSubscription;
  bool _disposed = false;

  List<HandPoint> _landmarks = <HandPoint>[];
  HandMetrics? _metrics;

  bool _initializing = true;
  String? _initError;
  bool _cameraReady = false;

  /// Ancho real de la palma, en centímetros, usado como calibración.
  double? _referencePalmWidthCm;

  final TextEditingController _calibrationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!HandDetector.isSupported) {
      _initializing = false;
      return;
    }
    _initialize();
  }

  @override
  void dispose() {
    _disposed = true;
    _landmarkSubscription?.cancel();
    _camera?.stopImageStream().catchError((Object _) {});
    _camera?.dispose();
    _detector?.dispose();
    _calibrationController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No se encontró ninguna cámara disponible.');
      }
      // Se prefiere la cámara trasera: la mano se apoya en una superficie.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        // El detector espera tres planos YUV; es el formato por defecto en
        // Android, pero se declara de forma explícita.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraReady = true;
        _initializing = false;
      });

      _startDetection(controller);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initError = _describeError(error);
      });
    }
  }

  /// Arranca el detector y el flujo de imágenes.
  ///
  /// El detector se crea a través de [HandDetector], que encapsula el paquete
  /// `hand_landmarker` (solo Android) y traduce sus tipos a los de Lumina.
  Future<void> _startDetection(CameraController controller) async {
    try {
      final detector = HandDetector.createIfSupported(numHands: 1);
      if (detector == null) {
        if (!mounted) return;
        setState(() {
          _initError =
              'No se pudo iniciar el detector de manos. Usa la medida a mano.';
        });
        return;
      }
      _detector = detector;

      _landmarkSubscription = detector.landmarkStream.listen(
        (hands) => _onHands(hands),
        onError: (Object error) {
          debugPrint('Error en el flujo de landmarks: $error');
        },
      );

      await controller.startImageStream((image) {
        if (_disposed) return;
        _detector?.processFrame(image, controller.description.sensorOrientation);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _initError = _describeError(error));
    }
  }

  void _onHands(List<HandPoint> landmarks) {
    if (!mounted) return;
    if (landmarks.isEmpty) {
      if (_landmarks.isNotEmpty) {
        setState(() {
          _landmarks = <HandPoint>[];
          _metrics = null;
        });
      }
      return;
    }

    // El adaptador ya entrega solo la primera mano detectada.
    final points = landmarks;
    if (points.length < 21) return;

    final previewSize = _camera?.value.previewSize;
    final width = previewSize?.width ?? 720;
    final height = previewSize?.height ?? 1280;

    HandMetrics? metrics;
    try {
      metrics = HandMetrics.fromLandmarks(
        points,
        frameWidth: width,
        frameHeight: height,
        referencePalmWidthCm: _referencePalmWidthCm,
      );
    } catch (error) {
      debugPrint('No se pudieron calcular las métricas: $error');
    }

    setState(() {
      _landmarks = points;
      _metrics = metrics;
    });
  }

  /// Aplica la calibración introducida por el usuario.
  void _applyCalibration() {
    final raw = _calibrationController.text.replaceAll(',', '.').trim();
    final value = double.tryParse(raw);
    if (value == null || value < 4 || value > 20) {
      setState(() {
        _initError =
            'Introduce un ancho de palma realista (entre 4 y 20 cm).';
      });
      return;
    }
    setState(() {
      _referencePalmWidthCm = value;
      _initError = null;
    });
    if (_landmarks.length == 21) {
      _onHands(_landmarks);
    }
  }

  /// Guarda en el formulario las medidas derivadas de la mano.
  void _saveMeasurements() {
    final metrics = _metrics;
    if (metrics == null) {
      _showMessage('Todavía no se detecta ninguna mano.');
      return;
    }

    final unit = metrics.unitLabel;
    final note = metrics.isCalibrated
        ? 'Estimado a partir de los 21 puntos de la mano'
        : 'Sin calibrar: valor en unidades relativas, no en centímetros';

    final form = context.read<FormularioProvider>();
    final now = DateTime.now();

    void add(String label, double value, MeasurementKind kind) {
      form.upsertMeasurement(
        Measurement(
          id: 'hand_${kind.name}_${now.microsecondsSinceEpoch}',
          label: label,
          valueCm: value,
          kind: kind,
          source: MeasurementSource.hand,
          timestamp: now,
          confidence: metrics.confidence,
          note: note,
        ),
      );
    }

    add('Ancho de palma ($unit)', metrics.palmWidth, MeasurementKind.handPalmWidth);
    add(
      'Envergadura de la mano ($unit)',
      metrics.handSpan,
      MeasurementKind.handSpan,
    );
    add(
      'Apertura de agarre ($unit)',
      metrics.gripOpening,
      MeasurementKind.handGripOpening,
    );
    add(
      'Largo del dedo índice ($unit)',
      metrics.indexFingerLength,
      MeasurementKind.handFingerLength,
    );

    _showMessage(
      metrics.isCalibrated
          ? 'Medidas guardadas.'
          : 'Medidas guardadas en unidades relativas. Calibra el ancho de palma '
              'para obtener centímetros.',
    );
    Navigator.of(context).maybePop();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _describeError(Object error) {
    if (error is CameraException) {
      switch (error.code) {
        case 'CameraAccessDenied':
        case 'CameraAccessDeniedWithoutPrompt':
          return 'Lumina necesita permiso para usar la cámara. '
              'Actívalo en los ajustes del sistema.';
        case 'CameraAccessRestricted':
          return 'El acceso a la cámara está restringido en este dispositivo.';
        default:
          return 'No se pudo iniciar la cámara: ${error.description ?? error.code}';
      }
    }
    return 'No se pudo iniciar la detección de manos: $error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medir la mano'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Introducir la medida a mano',
            onPressed: () => Navigator.of(context).push(
              ManualMeasurementScreen.route(
                defaultLabel: 'Ancho de palma',
                suggestedLabels: const [
                  'Ancho de palma',
                  'Largo de los dedos',
                  'Apertura de agarre',
                ],
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!HandDetector.isSupported) {
      return _UnsupportedPlatformView(
        onManual: () => Navigator.of(context).push(
          ManualMeasurementScreen.route(
            defaultLabel: 'Ancho de palma',
            suggestedLabels: const [
              'Ancho de palma',
              'Largo de los dedos',
              'Apertura de agarre',
            ],
          ),
        ),
      );
    }

    if (_initializing) {
      return const LuminaLoadingView(message: 'Preparando la cámara...');
    }

    if (_initError != null && !_cameraReady) {
      return LuminaErrorView(
        title: 'No se pudo iniciar la detección',
        message: _initError!,
        onRetry: () {
          setState(() {
            _initializing = true;
            _initError = null;
          });
          _initialize();
        },
      );
    }

    return _buildCameraView(context);
  }

  Widget _buildCameraView(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final controller = _camera!;
    final previewSize = controller.value.previewSize;
    final aspectRatio = previewSize == null || previewSize.width == 0
        ? 3 / 4
        : previewSize.height / previewSize.width;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: CameraPreview(controller),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: HandLandmarkPainter(
                    landmarks: _landmarks,
                    previewSize: previewSize ?? const Size(720, 1280),
                    lensDirection: controller.description.lensDirection,
                    sensorOrientation: controller.description.sensorOrientation,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: theme.colorScheme.inverseSurface.withValues(
                    alpha: 0.85,
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SafeArea(
                    bottom: false,
                    child: Text(
                      _landmarks.isEmpty
                          ? 'Coloca la mano abierta frente a la cámara.'
                          : 'Mano detectada. Ajusta la calibración para obtener centímetros.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildBottomPanel(context, theme, a11y),
      ],
    );
  }

  Widget _buildBottomPanel(
    BuildContext context,
    ThemeData theme,
    LuminaAccessibilityTheme a11y,
  ) {
    final metrics = _metrics;

    return SafeArea(
      top: false,
      child: Container(
        color: theme.colorScheme.surfaceContainerLow,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Calibración ---
            LuminaSectionCard(
              title: 'Calibración',
              subtitle:
                  'Mide el ancho de tu palma con una regla (de nudillo a nudillo) y escríbelo aquí.',
              leadingIcon: Icons.tune,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _calibrationController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Ancho de palma',
                        suffixText: 'cm',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AccessibleButton(
                    label: 'Aplicar',
                    icon: Icons.check,
                    isPrimary: false,
                    expand: false,
                    onPressed: _applyCalibration,
                    hint: 'Aplica la calibración a las medidas de la mano',
                  ),
                ],
              ),
            ),
            SizedBox(height: a11y.controlGap),

            // --- Medidas ---
            if (metrics != null)
              LuminaSectionCard(
                title: 'Medidas de la mano',
                subtitle: metrics.isCalibrated
                    ? 'En centímetros, a partir de 21 puntos.'
                    : 'Sin calibrar: valores en unidades relativas.',
                leadingIcon: Icons.straighten,
                child: Column(
                  children: [
                    _metricRow(
                      theme,
                      'Ancho de palma',
                      metrics.palmWidth,
                      metrics.unitLabel,
                    ),
                    _metricRow(
                      theme,
                      'Envergadura',
                      metrics.handSpan,
                      metrics.unitLabel,
                    ),
                    _metricRow(
                      theme,
                      'Apertura de agarre',
                      metrics.gripOpening,
                      metrics.unitLabel,
                    ),
                    _metricRow(
                      theme,
                      'Dedo índice',
                      metrics.indexFingerLength,
                      metrics.unitLabel,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Fiabilidad de la detección: '
                      '${(metrics.confidence * 100).round()} %',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              LuminaInfoBanner(
                message:
                    'Sin mano detectada. Acércala y abre bien los dedos para que la cámara vea los 21 puntos.',
                icon: Icons.back_hand,
                tone: LuminaBannerTone.warning,
              ),

            SizedBox(height: a11y.controlGap),
            AccessibleButton(
              label: 'Guardar medidas',
              icon: Icons.save,
              pictogram: Icons.save,
              onPressed: metrics == null ? null : _saveMeasurements,
              hint: 'Añade las medidas de la mano al formulario',
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(
    ThemeData theme,
    String label,
    double value,
    String unit,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            '${value.toStringAsFixed(1)} $unit',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// Vista informativa para plataformas sin `hand_landmarker`.
class _UnsupportedPlatformView extends StatelessWidget {
  const _UnsupportedPlatformView({required this.onManual});

  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        LuminaErrorView(
          title: 'Detección de manos no disponible',
          message: HandDetector.unsupportedReason,
        ),
        const SizedBox(height: AppSpacing.lg),
        LuminaInfoBanner(
          message:
              'En iOS sigue disponible: la medición AR de objetos (ARKit) y la '
              'entrada manual de medidas.',
          icon: Icons.info_outline,
        ),
        const SizedBox(height: AppSpacing.xl),
        AccessibleButton(
          label: 'Introducir medidas a mano',
          icon: Icons.edit,
          pictogram: Icons.edit,
          onPressed: onManual,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Plataforma detectada: ${Platform.operatingSystem}',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Dibuja el esqueleto de la mano sobre la vista de la cámara.
///
/// Se replica el enfoque del ejemplo oficial del paquete: se trabaja en el
/// espacio de la imagen de vista previa y se corrige con la orientación del
/// sensor y la dirección de la lente.
class HandLandmarkPainter extends CustomPainter {
  const HandLandmarkPainter({
    required this.landmarks,
    required this.previewSize,
    required this.lensDirection,
    required this.sensorOrientation,
    required this.color,
  });

  final List<HandPoint> landmarks;
  final Size previewSize;
  final CameraLensDirection lensDirection;
  final int sensorOrientation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.length < 21 || previewSize.height == 0) return;

    final scale = size.width / previewSize.height;

    final pointPaint = Paint()
      ..color = color
      ..strokeWidth = 6 / scale
      ..strokeCap = StrokeCap.round;

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 3 / scale;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(sensorOrientation * 3.141592653589793 / 180);

    if (lensDirection == CameraLensDirection.front) {
      canvas.scale(-1, 1);
      canvas.rotate(3.141592653589793);
    }

    canvas.scale(scale);

    Offset offsetFor(int index) {
      final point = landmarks[index];
      return Offset(
        (point.x - 0.5) * previewSize.width,
        (point.y - 0.5) * previewSize.height,
      );
    }

    for (final connection in HandLandmark.connections) {
      if (connection[0] >= landmarks.length ||
          connection[1] >= landmarks.length) {
        continue;
      }
      canvas.drawLine(
        offsetFor(connection[0]),
        offsetFor(connection[1]),
        linePaint,
      );
    }

    for (var i = 0; i < landmarks.length; i++) {
      canvas.drawCircle(offsetFor(i), 6 / scale, pointPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HandLandmarkPainter oldDelegate) =>
      oldDelegate.landmarks != landmarks ||
      oldDelegate.previewSize != previewSize;
}
