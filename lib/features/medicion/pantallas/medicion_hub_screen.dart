import 'package:flutter/material.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../modelos/measurement_models.dart';
import '../modelos/measurement_target.dart';
import '../servicios/hand_detector.dart';
import 'hand_measurement_screen.dart';
import 'manual_measurement_screen.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';

/// Central de medición: elige cómo medir y revisa lo medido.
///
/// Reúne las tres vías del pliego en un solo punto de entrada y muestra el
/// estado de cada una según la plataforma, para que el usuario no llegue nunca
/// a una pantalla que no puede funcionar en su dispositivo.
///
/// [target] decide dónde se guardan las medidas: en el formulario inteligente o
/// en la ficha clínica de OrthoSnap. Se propaga a las tres pantallas de
/// medición.
class MedicionHubScreen extends StatelessWidget {
  const MedicionHubScreen({
    super.key,
    this.target = MeasurementTarget.formulario,
  });

  final MeasurementTarget target;

  static Route<void> route({
    MeasurementTarget target = MeasurementTarget.formulario,
  }) =>
      MaterialPageRoute<void>(
        builder: (_) => MedicionHubScreen(target: target),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final measurements = MeasurementStore.read(context, target);

    final handSupported = HandDetector.isSupported;

    return Scaffold(
      appBar: AppBar(title: const Text('Medir')),
      floatingActionButton: const AccessibilityFab(heroTag: 'medicion.a11y'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          LuminaPageHeader(
            title: 'Tomar medidas',
            subtitle: target == MeasurementTarget.clinico
                ? 'Mide al paciente. Las medidas se guardan en su ficha clínica.'
                : 'Las medidas hacen que el modelo encaje de verdad. Puedes combinar las tres vías.',
            icon: Icons.straighten,
          ),

          // --- Mano ---
          _MethodCard(
            title: 'Mano con 21 puntos',
            description:
                'Calcula el ancho de palma, la envergadura y la apertura de agarre.',
            icon: Icons.back_hand,
            available: handSupported,
            unavailableReason: HandDetector.unsupportedReason,
            onOpen: () => Navigator.of(context).push(
              HandMeasurementScreen.route(target: target),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // --- Manual ---
          _MethodCard(
            title: 'Medida a mano',
            description:
                'Escribe una medida tomada con una regla. Siempre disponible.',
            icon: Icons.edit,
            available: true,
            onOpen: () => Navigator.of(context).push(
              ManualMeasurementScreen.route(
                target: target,
                suggestedLabels: target == MeasurementTarget.clinico
                    ? const [
                        'Perímetro de muñeca',
                        'Ancho de palma',
                        'Largo del antebrazo',
                        'Perímetro del tobillo',
                        'Largo del pie',
                      ]
                    : const [
                        'Largo del objeto',
                        'Ancho del objeto',
                        'Alto del objeto',
                        'Diámetro del mango',
                        'Perímetro de muñeca',
                        'Ancho de palma',
                      ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // --- Medidas actuales ---
          LuminaSectionCard(
            title: target == MeasurementTarget.clinico
                ? 'Medidas del paciente'
                : 'Medidas guardadas',
            subtitle: measurements.isEmpty
                ? 'Todavía no hay ninguna medida.'
                : '${measurements.length} medida(s) registradas.',
            leadingIcon: Icons.list_alt,
            trailing: measurements.isEmpty
                ? null
                : TextButton.icon(
                    onPressed: () =>
                        MeasurementStore.clear(context, target),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Borrar todas'),
                  ),
            child: measurements.isEmpty
                ? Text(
                    'Cuando midas algo aparecerá aquí.',
                    style: theme.textTheme.bodySmall,
                  )
                : Column(
                    children: [
                      for (final measurement in measurements)
                        _MeasurementTile(
                          measurement: measurement,
                          onRemove: () => MeasurementStore.remove(
                            context,
                            target,
                            measurement.id,
                          ),
                        ),
                    ],
                  ),
          ),

          if (target == MeasurementTarget.formulario &&
              a11y.bigButtons) ...[
            const SizedBox(height: AppSpacing.md),
            const LuminaInfoBanner(
              message:
                  'Modo botones grandes activo: los controles de medición se han ampliado.',
              icon: Icons.touch_app,
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

}

/// Tarjeta de un método de medición, con estado de disponibilidad.
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.available,
    required this.onOpen,
    this.unavailableReason,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool available;
  final VoidCallback onOpen;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);

    return Semantics(
      button: available,
      enabled: available,
      label: title,
      hint: available ? description : unavailableReason,
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          onTap: available ? onOpen : null,
          borderRadius: AppRadius.cardRadius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: a11y.pictograms ? a11y.pictogramSize : a11y.iconSize,
                  color: available
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                SizedBox(width: a11y.controlGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        available ? description : (unavailableReason ?? ''),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: available
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                        ),
                      ),
                      if (!available) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Icon(
                              Icons.block,
                              size: 16,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'No disponible en este dispositivo',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (available)
                  Icon(
                    Icons.chevron_right,
                    size: a11y.iconSize,
                    color: theme.colorScheme.outline,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de una medida guardada, con su origen y acción de borrado.
class _MeasurementTile extends StatelessWidget {
  const _MeasurementTile({required this.measurement, required this.onRemove});

  final Measurement measurement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final icon = switch (measurement.source) {
      MeasurementSource.hand => Icons.back_hand,
      MeasurementSource.manual => Icons.edit,
    };

    return Semantics(
      label:
          '${measurement.label}: ${measurement.display}. Origen: ${measurement.source.label}.',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, semanticLabel: measurement.source.label),
        title: Text(measurement.label),
        subtitle: Text(
          measurement.note ?? measurement.source.description,
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(measurement.display, style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar ${measurement.label}',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
