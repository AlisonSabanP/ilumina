import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';
import '../../generacion3d/pantallas/generacion_screen.dart';
import '../../generacion3d/providers/generation_provider.dart';
import '../../medicion/pantallas/medicion_hub_screen.dart';
import '../modelos/progrip_modelos.dart';
import '../providers/progrip_provider.dart';

/// Módulo ProGrip: prótesis y adaptadores para oficios.
///
/// El usuario compone la pieza eligiendo **tres capas**. La pantalla está
/// dividida en esas tres capas más un resumen, para que la decisión sea siempre
/// visible y reversible.
class ProGripScreen extends StatefulWidget {
  const ProGripScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const ProGripScreen(),
      );

  @override
  State<ProGripScreen> createState() => _ProGripScreenState();
}

class _ProGripScreenState extends State<ProGripScreen> {
  bool _generating = false;

  Future<void> _generate() async {
    final progrip = context.read<ProGripProvider>();
    final generation = context.read<GenerationProvider>();

    setState(() => _generating = true);
    // Se lanza la generación antes de navegar: la pantalla de generación lee
    // el estado del provider, no la configuración ProGrip.
    await generation.generateFromProGrip(progrip.config);
    if (!mounted) return;
    await Navigator.of(context).push(GeneracionScreen.route());
    if (!mounted) return;
    setState(() => _generating = false);
    if (generation.hasModel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modelo ProGrip generado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progrip = context.watch<ProGripProvider>();
    final a11y = AccessibilityProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ProGrip'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reiniciar la configuración',
            onPressed: progrip.reset,
          ),
          const AccessibilityAppBarAction(),
        ],
      ),
      floatingActionButton: const AccessibilityFab(heroTag: 'progrip.a11y'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          LuminaPageHeader(
            title: 'ProGrip',
            subtitle:
                'Protésis y adaptadores para trabajar: tres capas que se combinan en una sola pieza impresa.',
            icon: Icons.handyman,
            trailing: Icon(
              Icons.handyman,
              size: a11y.pictograms ? a11y.pictogramSize : 0,
              color: theme.colorScheme.primary,
            ),
          ),

          // --- Capa 1: base ---
          LuminaSectionCard(
            title: 'Capa 1 · Base de acople',
            subtitle: 'Cómo se sujeta la pieza a la mano o al brazo.',
            leadingIcon: Icons.settings_input_component,
            child: Column(
              children: [
                for (var i = 0; i < GripBase.values.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: PictogramOptionTile(
                      label: GripBase.values[i].label,
                      description: GripBase.values[i].description,
                      icon: GripBase.values[i].icon,
                      pictogram: GripBase.values[i].icon,
                      selected: progrip.base == GripBase.values[i],
                      onTap: () => progrip.setBase(GripBase.values[i]),
                      semanticKey: OrdinalSortKey(i.toDouble()),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Capa 2: garfio ---
          LuminaSectionCard(
            title: 'Capa 2 · Garfio funcional',
            subtitle: 'Sustituye al agarre de la mano.',
            leadingIcon: Icons.back_hand,
            child: Column(
              children: [
                for (var i = 0; i < GripHook.values.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: PictogramOptionTile(
                      label: GripHook.values[i].label,
                      description: GripHook.values[i].description,
                      icon: GripHook.values[i].icon,
                      pictogram: GripHook.values[i].icon,
                      selected: progrip.hook == GripHook.values[i],
                      onTap: () => progrip.setHook(GripHook.values[i]),
                      semanticKey: OrdinalSortKey(i.toDouble()),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Capa 3: adaptador ---
          LuminaSectionCard(
            title: 'Capa 3 · Adaptador de herramienta',
            subtitle: 'La pieza que encaja en la herramienta concreta.',
            leadingIcon: Icons.construction,
            child: Column(
              children: [
                for (var i = 0; i < ToolAdapter.values.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: PictogramOptionTile(
                      label: ToolAdapter.values[i].label,
                      description:
                          'Mango de referencia: '
                          '${ToolAdapter.values[i].defaultHandleDiameterMm} mm de diámetro.',
                      icon: ToolAdapter.values[i].icon,
                      pictogram: ToolAdapter.values[i].icon,
                      selected: progrip.adapter == ToolAdapter.values[i],
                      onTap: () {
                        progrip.setAdapter(ToolAdapter.values[i]);
                        progrip.seedHandleDiameter();
                      },
                      semanticKey: OrdinalSortKey(i.toDouble()),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Medidas y material ---
          LuminaSectionCard(
            title: 'Medidas y material',
            subtitle: 'Las medidas de la mano mejoran el ajuste.',
            leadingIcon: Icons.straighten,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (progrip.measurements.isEmpty)
                  Text(
                    'Sin medidas propias: se usarán proporciones estándar de '
                    'mano adulta.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  for (final measurement in progrip.measurements)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.straighten),
                      title: Text(measurement.label),
                      subtitle: Text(measurement.source.label),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            measurement.display,
                            style: theme.textTheme.titleMedium,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Eliminar ${measurement.label}',
                            onPressed: () =>
                                progrip.removeMeasurement(measurement.id),
                          ),
                        ],
                      ),
                    ),
                if (progrip.missingMeasurements.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  LuminaInfoBanner(
                    message:
                        'Medidas recomendadas: ${progrip.missingMeasurements.join(', ')}.',
                    icon: Icons.info_outline,
                    tone: LuminaBannerTone.warning,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AccessibleButton(
                  label: 'Medir ahora',
                  icon: Icons.straighten,
                  pictogram: Icons.straighten,
                  isPrimary: false,
                  onPressed: () =>
                      Navigator.of(context).push(MedicionHubScreen.route()),
                  hint: 'Abre la medición de mano o la medida a mano',
                ),
                SizedBox(height: a11y.controlGap),
                Text('Material', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final material in ProGripProvider.materials)
                      ChoiceChip(
                        label: Text(material),
                        selected: progrip.material == material,
                        onSelected: (_) => progrip.setMaterial(material),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Notas ---
          LuminaSectionCard(
            title: 'Requisitos adicionales',
            subtitle: 'Detalles de ajuste o de uso que quieras añadir.',
            leadingIcon: Icons.notes,
            child: TextField(
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: 'Por ejemplo: añade una correa de velcro ajustable',
                prefixIcon: Icon(Icons.edit_note),
              ),
              onChanged: progrip.setNotes,
            ),
          ),

          // --- Avisos de compatibilidad ---
          if (progrip.compatibilityWarnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            LuminaSectionCard(
              title: 'Sugerencias de ajuste',
              leadingIcon: Icons.lightbulb_outline,
              child: Column(
                children: [
                  for (final warning in progrip.compatibilityWarnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: LuminaInfoBanner(
                        message: warning,
                        icon: Icons.warning_amber,
                        tone: LuminaBannerTone.warning,
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // --- Resumen ---
          LuminaSectionCard(
            title: 'Resumen de la pieza',
            subtitle: progrip.config.summary,
            leadingIcon: Icons.summarize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progrip.config.title,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Material: ${progrip.material}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                AccessibleButton(
                  label: 'Generar pieza ProGrip',
                  icon: Icons.auto_awesome,
                  pictogram: Icons.auto_awesome,
                  busy: _generating,
                  onPressed: _generating ? null : _generate,
                  hint: 'Envía las tres capas a Meshy AI',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
