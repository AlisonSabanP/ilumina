import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../../visor3d/pantallas/visor_modelo_screen.dart';
import '../modelos/meshy_models.dart';
import '../providers/generation_provider.dart';

/// Pantalla de generación 3D con Meshy AI.
///
/// Muestra el prompt enriquecido que se envía, el estado real de la tarea
/// (`PENDING` -> `IN_PROGRESS` -> `SUCCEEDED`) con su porcentaje de progreso, y
/// ofrece reintentar ante cualquier error.
///
/// Sin una clave propia de Meshy, la pieza se construye en el propio
/// dispositivo (`LocalGeneratorService`): no gasta créditos, funciona sin
/// conexión y el resultado es un STL imprimible de verdad.
class GeneracionScreen extends StatefulWidget {
  const GeneracionScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const GeneracionScreen(),
      );

  @override
  State<GeneracionScreen> createState() => _GeneracionScreenState();
}

class _GeneracionScreenState extends State<GeneracionScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se lanza la generación una sola vez, cuando el provider ya está
    // disponible en el árbol.
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    final generation = context.read<GenerationProvider>();
    final form = context.read<FormularioProvider>();
    await generation.generateFromFormulario(form);
  }

  @override
  Widget build(BuildContext context) {
    final generation = context.watch<GenerationProvider>();
    final a11y = AccessibilityProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generar modelo 3D'),
        actions: [
          if (generation.phase.isBusy)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Detener la espera',
              onPressed: generation.cancelPolling,
            ),
          if (!generation.phase.isBusy)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Volver a generar',
              onPressed: _generate,
            ),
        ],
      ),
      floatingActionButton: const AccessibilityFab(heroTag: 'gen.a11y'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const LuminaPageHeader(
            title: 'Generando tu modelo',
            subtitle:
                'La pieza se construye a partir de tus respuestas y tus medidas. '
                'Suele tardar unos minutos.',
            icon: Icons.auto_awesome,
          ),

          LuminaInfoBanner(
            message: generation.isLocalMode
                ? 'Lumina construye la pieza en el propio dispositivo a partir de '
                    'tus medidas: es gratis, funciona sin conexión y el archivo '
                    'STL sale listo para imprimir.'
                : 'Se está usando tu clave de Meshy: la pieza la genera el '
                    'servicio en la nube y puede tardar unos minutos.',
            icon: generation.isLocalMode ? Icons.offline_bolt : Icons.cloud,
          ),

          const SizedBox(height: AppSpacing.lg),
          _StatusCard(generation: generation),
          const SizedBox(height: AppSpacing.lg),

          // --- Prompt enviado ---
          if (generation.prompt != null)
            LuminaSectionCard(
              title: 'Descripción de tu pieza',
              subtitle: generation.prompt!.wasTrimmed
                  ? 'Se ajustó a ${generation.prompt!.length} caracteres.'
                  : '${generation.prompt!.length} caracteres.',
              leadingIcon: Icons.description_outlined,
              child: SelectableText(
                generation.prompt!.prompt,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

          // --- Ficha de la pieza local ---
          if (generation.model?.isLocal == true) ...[
            const SizedBox(height: AppSpacing.lg),
            _LocalPieceCard(model: generation.model!),
          ],

          // --- Tarea ---
          if (generation.task != null && generation.isMeshyMode) ...[
            const SizedBox(height: AppSpacing.lg),
            LuminaSectionCard(
              title: 'Progreso de la generación',
              leadingIcon: Icons.cloud_sync,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _keyValue(context, 'Identificador', generation.task!.id),
                  _keyValue(
                    context,
                    'Estado',
                    '${generation.task!.status.label} '
                        '(${generation.task!.status.name})',
                  ),
                  _keyValue(
                    context,
                    'Progreso',
                    '${generation.task!.progress} %',
                  ),
                  if (generation.task!.consumedCredits != null)
                    _keyValue(
                      context,
                      'Créditos usados',
                      '${generation.task!.consumedCredits}',
                    ),
                ],
              ),
            ),
          ],

          // --- Error ---
          if (generation.error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            LuminaSectionCard(
              title: 'No se pudo generar',
              leadingIcon: Icons.error_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    generation.error!.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (generation.error!.taskId != null)
                    Text(
                      'Identificador de la tarea: ${generation.error!.taskId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  if (generation.error!.isRetryable)
                    AccessibleButton(
                      label: 'Reintentar',
                      icon: Icons.refresh,
                      pictogram: Icons.refresh,
                      onPressed: generation.retry,
                      hint: 'Vuelve a generar el modelo',
                    )
                  else
                    AccessibleButton(
                      label: 'Volver a empezar',
                      icon: Icons.restart_alt,
                      pictogram: Icons.restart_alt,
                      onPressed: _generate,
                      hint: 'Crea una tarea nueva con el mismo diseño',
                    ),
                ],
              ),
            ),
          ],

          // --- Modelo listo ---
          if (generation.hasModel) ...[
            const SizedBox(height: AppSpacing.lg),
            LuminaSectionCard(
              title: 'Modelo listo',
              subtitle: generation.model?.isLocal == true
                  ? 'Pieza construida en el dispositivo, lista para ver, descargar '
                      'y compartir.'
                  : 'Meshy conserva los archivos tres días. Descárgalo o compártelo para no perderlo.',
              leadingIcon: Icons.check_circle,
              child: Column(
                children: [
                  AccessibleButton(
                    label: 'Ver el modelo en 3D',
                    icon: Icons.threed_rotation,
                    pictogram: Icons.threed_rotation,
                    onPressed: () => Navigator.of(context).push(
                      VisorModeloScreen.route(generation.model!),
                    ),
                    hint:
                        'Abre el visor con rotación, zoom y bloqueo de paneo',
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // --- Explicación del proceso ---
          LuminaSectionCard(
            title: 'Cómo funciona',
            leadingIcon: Icons.help_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _step(
                  context,
                  '1',
                  'Lumina describe tu pieza con tus respuestas y tus medidas.',
                ),
                _step(
                  context,
                  '2',
                  'La pieza se construye y se muestra el avance.',
                ),
                _step(
                  context,
                  '3',
                  'Cuando está lista, puedes verla en 3D.',
                ),
                _step(
                  context,
                  '4',
                  'Descárgala o compártela para imprimirla.',
                ),
              ],
            ),
          ),

          if (a11y.reduceMotion) ...[
            const SizedBox(height: AppSpacing.md),
            const LuminaInfoBanner(
              message:
                  'Modo reducir movimiento activo: la barra de progreso no anima, pero sigue mostrando el porcentaje.',
              icon: Icons.motion_photos_off,
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _keyValue(BuildContext context, String key, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(key, style: theme.textTheme.labelLarge),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, String number, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Tarjeta de estado con la barra de progreso y el estado de Meshy.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.generation});

  final GenerationProvider generation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);

    final statusText = switch (generation.phase) {
      GenerationPhase.idle => 'Sin empezar',
      GenerationPhase.preparing => 'Preparando tu diseño...',
      GenerationPhase.creating => generation.isLocalMode
          ? 'Construyendo la pieza...'
          : 'Enviando el diseño...',
      GenerationPhase.polling => generation.task == null
          ? 'Consultando el estado...'
          : '${generation.task!.status.label} '
              '(${generation.task!.progress} %)',
      GenerationPhase.succeeded => 'Modelo generado correctamente',
      GenerationPhase.failed => 'La generación falló',
    };

    final progress = generation.progress;

    return Semantics(
      liveRegion: true,
      label: statusText,
      value: '${(progress * 100).round()} por ciento',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    generation.phase.isBusy
                        ? Icons.hourglass_top
                        : generation.phase == GenerationPhase.succeeded
                            ? Icons.check_circle
                            : generation.phase == GenerationPhase.failed
                                ? Icons.error_outline
                                : Icons.hourglass_empty,
                    color: generation.phase == GenerationPhase.failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    size: a11y.iconSize,
                  ),
                  SizedBox(width: a11y.controlGap),
                  Expanded(
                    child: Text(statusText, style: theme.textTheme.titleMedium),
                  ),
                  if (generation.phase.isBusy)
                    Text(
                      '${(progress * 100).round()} %',
                      style: theme.textTheme.titleMedium,
                    ),
                ],
              ),
              SizedBox(height: a11y.controlGap),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  // Si no hay progreso real todavía se muestra indeterminada,
                  // para que el usuario sepa que algo está pasando.
                  value: generation.phase == GenerationPhase.creating ||
                          generation.phase == GenerationPhase.preparing
                      ? null
                      : progress,
                  minHeight: a11y.bigButtons ? 14 : 8,
                ),
              ),
              if (generation.phase == GenerationPhase.polling) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'La generación puede tardar varios minutos. Si cierras la '
                  'pantalla, el modelo se seguirá creando.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (generation.isLocalMode) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'La pieza se construye en el dispositivo: no se envía nada a '
                  'ningún servicio.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ficha de la pieza construida en el dispositivo.
///
/// Muestra lo que un usuario necesita saber antes de imprimir: qué se ha
/// construido, con qué medidas y qué decisiones se tomaron cuando faltaba
/// algún dato. Los avisos son importantes: si el diámetro salió de un valor
/// estándar y no de una medida real, la pieza no encajará y hay que decirlo.
class _LocalPieceCard extends StatelessWidget {
  const _LocalPieceCard({required this.model});

  final GeneratedModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimensions = model.dimensionsMm;

    return LuminaSectionCard(
      title: 'Ficha de la pieza',
      subtitle: model.pieceSummary,
      leadingIcon: Icons.straighten,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dimensions.isNotEmpty) ...[
            Text('Medidas', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            for (final entry in dimensions.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key[0].toUpperCase() + entry.key.substring(1),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${entry.value.toStringAsFixed(1)} mm',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (model.pieceNotes.isNotEmpty) ...[
            Text('Notas de fabricación', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            for (final note in model.pieceNotes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(note, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
