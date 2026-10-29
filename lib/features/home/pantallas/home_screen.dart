import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/pantallas/panel_accesibilidad_screen.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../../formulario/pantallas/formulario_screen.dart';
import '../../generacion3d/providers/generation_provider.dart';
import '../../orthosnap/pantallas/orthosnap_login_screen.dart';
import '../../progrip/pantallas/progrip_screen.dart';
import '../../visor3d/pantallas/visor_modelo_screen.dart';

/// Pantalla de inicio: punto de entrada único a todos los módulos.
///
/// Está pensada para que la primera decisión sea siempre la misma y esté
/// siempre en el mismo sitio: "¿qué necesito?". El estado de accesibilidad está
/// arriba, seguido de los accesos a los módulos profesionales y al historial.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final provider = context.watch<AccessibilityProvider>();
    final form = context.watch<FormularioProvider>();
    final generation = context.watch<GenerationProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lumina'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Modelos generados',
            onPressed: () => Navigator.of(context).push(HistoryScreen.route()),
          ),
          const AccessibilityAppBarAction(),
        ],
      ),
      floatingActionButton: const AccessibilityFab(heroTag: 'home.a11y'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          LuminaPageHeader(
            title: 'Impresión 3D para todos',
            subtitle:
                'Diseña objetos que encajen de verdad en tu mano, en tu casa o '
                'en tu consulta.',
            icon: Icons.lightbulb_outline,
            trailing: Icon(
              Icons.view_in_ar,
              size: a11y.bigButtons ? 40 : 32,
              color: theme.colorScheme.secondary,
            ),
          ),

          if (provider.activeModeCount == 0)
            LuminaSectionCard(
              title: 'Empieza ajustando la accesibilidad',
              subtitle:
                  'Lumina se adapta a ti: botones grandes, TalkBack, pictogramas, '
                  'fuente para dislexia y alto contraste.',
              leadingIcon: Icons.accessibility_new,
              child: AccessibleButton(
                label: 'Abrir el panel de accesibilidad',
                icon: Icons.accessibility_new,
                pictogram: Icons.accessibility_new,
                isPrimary: false,
                onPressed: () =>
                    Navigator.of(context).push(PanelAccesibilidadScreen.route()),
                hint: 'Activa o desactiva los modos de accesibilidad',
              ),
            )
          else
            LuminaInfoBanner(
              message:
                  '${provider.activeModeCount} modo(s) de accesibilidad activo(s): '
                  '${_activeModes(provider).join(', ')}.',
              icon: Icons.check_circle,
            ),

          const SizedBox(height: AppSpacing.xl),

          const _SectionTitle(
            title: 'Diseñar un objeto',
            subtitle: 'El formulario te guía con preguntas cortas.',
          ),
          _ModuleCard(
            title:
                form.canGenerate ? 'Continuar mi diseño' : 'Formulario inteligente',
            description: form.canGenerate
                ? 'Recomendación: ${form.recommendation!.title}'
                : 'Motriz, visual o cognitiva: responde unas preguntas y obtén '
                    'una recomendación.',
            icon: Icons.assignment,
            onOpen: () => Navigator.of(context).push(FormularioScreen.route()),
            highlight: true,
          ),

          const SizedBox(height: AppSpacing.xl),

          const _SectionTitle(
            title: 'Módulos profesionales',
            subtitle: 'Herramientas especializadas para oficios y clínica.',
          ),
          _ModuleCard(
            title: 'ProGrip',
            description:
                'Prótesis y adaptadores para trabajar: base, garfio y adaptador '
                'de herramienta.',
            icon: Icons.handyman,
            accent: theme.colorScheme.primary,
            onOpen: () => Navigator.of(context).push(ProGripScreen.route()),
          ),
          const SizedBox(height: AppSpacing.md),
          _ModuleCard(
            title: 'OrthoSnap',
            description:
                'Órtesis clínicas con estructura Voronoi. Acceso restringido a '
                'profesionales sanitarios.',
            icon: Icons.medical_services_outlined,
            accent: theme.colorScheme.secondary,
            badge: 'Acceso restringido',
            onOpen: () =>
                Navigator.of(context).push(OrthoSnapLoginScreen.route()),
          ),

          if (generation.history.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const _SectionTitle(
              title: 'Mis modelos',
              subtitle: 'Los últimos modelos generados en este dispositivo.',
            ),
            for (final model in generation.history.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.threed_rotation),
                    title: Text(model.title),
                    subtitle: Text(
                      model.isDownloaded
                          ? 'Guardado en el dispositivo'
                          : 'En la nube de Meshy',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      VisorModeloScreen.route(model),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            AccessibleButton(
              label: 'Ver todos los modelos',
              icon: Icons.history,
              pictogram: Icons.history,
              isPrimary: false,
              onPressed: () => Navigator.of(context).push(HistoryScreen.route()),
            ),
          ],

          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Lumina · proyecto escolar de impresión 3D accesible',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  List<String> _activeModes(AccessibilityProvider provider) {
    final modes = <String>[];
    if (provider.talkBackEnabled) modes.add('TalkBack');
    if (provider.bigButtonsEnabled) modes.add('botones grandes');
    if (provider.pictogramsEnabled) modes.add('pictogramas');
    if (provider.dyslexiaFontEnabled) modes.add('dislexia');
    if (provider.highContrastEnabled) modes.add('alto contraste');
    if (provider.reduceMotionEnabled) modes.add('reducir movimiento');
    return modes;
  }
}

/// Historial completo de modelos generados.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const HistoryScreen(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final generation = context.watch<GenerationProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Modelos generados')),
      body: generation.history.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: const [
                LuminaInfoBanner(
                  message:
                      'Todavía no has generado ningún modelo. Empieza por el '
                      'formulario inteligente.',
                  icon: Icons.inbox,
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: generation.history.length,
              itemBuilder: (context, index) {
                final model = generation.history[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: ListTile(
                    leading: const Icon(Icons.threed_rotation),
                    title: Text(model.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.isDownloaded
                              ? 'Guardado en el dispositivo'
                              : 'Solo en la nube (Meshy borra los archivos a los 3 días)',
                        ),
                        if (model.createdAt != null)
                          Text(
                            _formatDate(model.createdAt!),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Quitar del historial',
                      onPressed: () => generation.removeFromHistory(model.id),
                    ),
                    onTap: () => Navigator.of(context).push(
                      VisorModeloScreen.route(model),
                    ),
                  ),
                );
              },
            ),
    );
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onOpen,
    this.accent,
    this.badge,
    this.highlight = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onOpen;
  final Color? accent;
  final String? badge;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final color = accent ?? theme.colorScheme.primary;

    return Semantics(
      button: true,
      label: title,
      hint: description,
      excludeSemantics: true,
      child: Card(
        color: highlight ? theme.colorScheme.primaryContainer : null,
        child: InkWell(
          onTap: onOpen,
          borderRadius: AppRadius.cardRadius,
          child: Padding(
            padding: EdgeInsets.all(
              a11y.bigButtons ? AppSpacing.xl : AppSpacing.lg,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: a11y.pictograms
                      ? a11y.pictogramSize
                      : a11y.iconSize * 1.5,
                  color: color,
                ),
                SizedBox(width: a11y.controlGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child:
                                Text(title, style: theme.textTheme.titleMedium),
                          ),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                badge!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: color,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
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
