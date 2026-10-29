import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../core/env.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../../visor3d/pantallas/visor_modelo_screen.dart';
import '../providers/generation_provider.dart';

/// Pantalla de generación 3D con Meshy AI.
///
/// Muestra el prompt enriquecido que se envía, el estado real de la tarea
/// (`PENDING` -> `IN_PROGRESS` -> `SUCCEEDED`) con su porcentaje de progreso, y
/// ofrece reintentar ante cualquier error.
///
/// Notas de comportamiento importantes:
///  * El botón de reintento **crea una tarea nueva**. Es correcto solo cuando la
///    anterior terminó en `FAILED`; si lo que falló fue la red, el mensaje de
///    error avisa de que la tarea puede seguir viva.
///  * Con la clave de prueba (`Env.testModeApiKey`) Meshy no genera el modelo
///    del prompt: se avisa de forma visible en lugar de dejar creer al usuario
///    que su pieza se ha generado.
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
                'Meshy AI construye la geometría a partir del prompt. Suele tardar entre uno y cinco minutos.',
            icon: Icons.auto_awesome,
          ),

          if (generation.isTestMode)
            const LuminaInfoBanner(
              message:
                  'Modo de prueba: estás usando la clave de demostración de Meshy. '
                  'No se genera el modelo de tu prompt y no se consumen créditos. '
                  'Añade tu propia clave con --dart-define=MESHY_API_KEY=... para '
                  'generar piezas reales.',
              icon: Icons.science_outlined,
              tone: LuminaBannerTone.warning,
            ),

          const SizedBox(height: AppSpacing.lg),
          _StatusCard(generation: generation),
          const SizedBox(height: AppSpacing.lg),

          // --- Prompt enviado ---
          if (generation.prompt != null)
            LuminaSectionCard(
              title: 'Prompt enviado a Meshy',
              subtitle: generation.prompt!.wasTrimmed
                  ? 'Se recortó de ${generation.prompt!.originalLength} a '
                      '${generation.prompt!.length} caracteres (el límite de Meshy es 800).'
                  : '${generation.prompt!.length} caracteres.',
              leadingIcon: Icons.description_outlined,
              child: SelectableText(
                generation.prompt!.prompt,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

          // --- Tarea ---
          if (generation.task != null) ...[
            const SizedBox(height: AppSpacing.lg),
            LuminaSectionCard(
              title: 'Tarea en Meshy',
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
                      hint: 'Vuelve a enviar el diseño a Meshy',
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
              subtitle:
                  'Meshy conserva los archivos tres días. Descárgalo o compártelo para no perderlo.',
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
                  'Lumina compone un prompt con tu formulario y tus medidas reales.',
                ),
                _step(
                  context,
                  '2',
                  'Se crea una tarea en Meshy y se consulta su estado cada pocos segundos.',
                ),
                _step(
                  context,
                  '3',
                  'Cuando el estado es SUCCEEDED, Lumina descarga el archivo .glb.',
                ),
                _step(
                  context,
                  '4',
                  'Puedes verlo, descargarlo y compartirlo para imprimirlo.',
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
      GenerationPhase.preparing => 'Preparando el prompt...',
      GenerationPhase.creating => 'Enviando el diseño a Meshy...',
      GenerationPhase.polling => generation.task == null
          ? 'Consultando el estado...'
          : 'Meshy: ${generation.task!.status.label} '
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
                  'Meshy puede tardar varios minutos. No cierres la pantalla: '
                  'si la cierras, la tarea sigue en el servidor y podrás '
                  'consultarla con su identificador.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (generation.isTestMode) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Clave de prueba: ${Env.testModeApiKey.substring(0, 12)}… '
                  '(no válida para generar piezas reales)',
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
