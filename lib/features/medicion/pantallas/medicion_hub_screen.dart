import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../modelos/measurement_models.dart';
import '../servicios/hand_detector.dart';
import 'ar_measurement_screen.dart';
import 'hand_measurement_screen.dart';
import 'manual_measurement_screen.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';

/// Central de medición: elige cómo medir y revisa lo medido.
///
/// Reúne las tres vías del pliego en un solo punto de entrada y muestra el
/// estado de cada una según la plataforma, para que el usuario no llegue nunca
/// a una pantalla que no puede funcionar en su dispositivo.
class MedicionHubScreen extends StatelessWidget {
  const MedicionHubScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const MedicionHubScreen(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final form = context.watch<FormularioProvider>();

    final arSupported = _arSupported();
    final handSupported = HandDetector.isSupported;

    return Scaffold(
      appBar: AppBar(title: const Text('Medir')),
      floatingActionButton: const AccessibilityFab(heroTag: 'medicion.a11y'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const LuminaPageHeader(
            title: 'Tomar medidas',
            subtitle:
                'Las medidas hacen que el modelo encaje de verdad. Puedes usar las tres vías y combinarlas.',
            icon: Icons.straighten,
          ),

          // --- AR ---
          _MethodCard(
            title: 'Objetos con AR',
            description:
                'Apunta con la cámara y toca los dos extremos del objeto. Precisión milimétrica con ARKit y ARCore.',
            icon: Icons.view_in_ar,
            available: arSupported,
            unavailableReason:
                'La medición AR necesita un móvil Android o iPhone con ARCore o ARKit.',
            badge: 'Recomendado',
            onOpen: () =>
                Navigator.of(context).push(ArMeasurementScreen.route()),
          ),
          const SizedBox(height: AppSpacing.md),

          // --- Mano ---
          _MethodCard(
            title: 'Mano con 21 puntos',
            description:
                'Detecta los puntos de la mano y calcula el ancho de palma, la envergadura y la apertura de agarre.',
            icon: Icons.back_hand,
            available: handSupported,
            unavailableReason: HandDetector.unsupportedReason,
            onOpen: () =>
                Navigator.of(context).push(HandMeasurementScreen.route()),
          ),
          const SizedBox(height: AppSpacing.md),

          // --- Manual ---
          _MethodCard(
            title: 'Medida a mano',
            description:
                'Escribe una medida tomada con una regla. Es la opción más fiable y siempre está disponible.',
            icon: Icons.edit,
            available: true,
            onOpen: () => Navigator.of(context).push(
              ManualMeasurementScreen.route(
                suggestedLabels: const [
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
            title: 'Medidas guardadas',
            subtitle: form.measurements.isEmpty
                ? 'Todavía no hay ninguna medida.'
                : '${form.measurements.length} medida(s) en el formulario.',
            leadingIcon: Icons.list_alt,
            trailing: form.measurements.isEmpty
                ? null
                : TextButton.icon(
                    onPressed: form.clearMeasurements,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Borrar todas'),
                  ),
            child: form.measurements.isEmpty
                ? Text(
                    'Cuando midas algo aparecerá aquí y se añadirá al prompt del modelo.',
                    style: theme.textTheme.bodySmall,
                  )
                : Column(
                    children: [
                      for (final measurement in form.measurements)
                        _MeasurementTile(
                          measurement: measurement,
                          onRemove: () =>
                              form.removeMeasurement(measurement.id),
                        ),
                    ],
                  ),
          ),

          if (a11y.bigButtons) ...[
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

  bool _arSupported() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
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
    this.badge,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool available;
  final VoidCallback onOpen;
  final String? unavailableReason;
  final String? badge;

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
                          if (badge != null && available)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                badge!,
                                style: theme.textTheme.labelSmall,
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
      MeasurementSource.ar => Icons.view_in_ar,
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
