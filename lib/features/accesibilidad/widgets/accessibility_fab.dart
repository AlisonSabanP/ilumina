import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../pantallas/panel_accesibilidad_screen.dart';
import '../providers/accessibility_provider.dart';

/// Botón flotante que abre el panel de accesibilidad desde cualquier pantalla.
///
/// El pliego exige que el panel sea accesible "desde cualquier pantalla", por
/// lo que este FAB se añade al `Scaffold` de cada pantalla principal. Su
/// etiqueta semántica indica cuántos modos hay activos, para que un usuario de
/// TalkBack sepa de un vistazo en qué estado está la app.
class AccessibilityFab extends StatelessWidget {
  const AccessibilityFab({super.key, this.heroTag = 'lumina.a11y.fab'});

  /// Etiquetas `Hero` distintas evitan el conflicto de dos FABs visibles
  /// durante una transición de ruta.
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccessibilityProvider>();
    final a11y = AccessibilityProvider.of(context);
    final active = provider.activeModeCount;

    return Semantics(
      button: true,
      label: 'Abrir el panel de accesibilidad',
      hint: active == 0
          ? 'Ningún modo activo'
          : '$active modo${active == 1 ? '' : 's'} activo${active == 1 ? '' : 's'}',
      child: FloatingActionButton(
        heroTag: heroTag,
        tooltip: 'Accesibilidad',
        onPressed: () =>
            Navigator.of(context).push(PanelAccesibilidadScreen.route()),
        child: Badge(
          isLabelVisible: active > 0,
          label: Text('$active'),
          child: Icon(
            Icons.accessibility_new,
            size: a11y.iconSize,
          ),
        ),
      ),
    );
  }
}

/// Acción de `AppBar` que abre el mismo panel.
///
/// Útil en pantallas con mucho contenido a pie de página, donde un FAB podría
/// tapar el último control.
class AccessibilityAppBarAction extends StatelessWidget {
  const AccessibilityAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccessibilityProvider>();
    return IconButton(
      icon: Badge(
        isLabelVisible: provider.activeModeCount > 0,
        label: Text('${provider.activeModeCount}'),
        child: const Icon(Icons.accessibility_new),
      ),
      tooltip: 'Accesibilidad',
      onPressed: () =>
          Navigator.of(context).push(PanelAccesibilidadScreen.route()),
    );
  }
}

/// Cabecera de pantalla con título, subtítulo y acción de accesibilidad.
class LuminaPageHeader extends StatelessWidget {
  const LuminaPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);

    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: a11y.bigButtons ? 40 : 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
