import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/app_spacing.dart';
import '../../features/accesibilidad/providers/accessibility_provider.dart';

/// Botón principal de Lumina.
///
/// Adapta automáticamente su altura y su área táctil al modo "botones
/// grandes" (mínimo 64x64 dp) y dibuja un pictograma grande cuando el modo
/// pictogramas está activo.
///
/// El `Semantics` envolvente describe la acción completa para TalkBack, e
/// incluye `hint` con el resultado esperado, algo que WCAG recomienda y que el
/// lector de pantalla anuncia después de la etiqueta.
class AccessibleButton extends StatelessWidget {
  const AccessibleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.pictogram,
    this.hint,
    this.isPrimary = true,
    this.expand = true,
    this.busy = false,
    this.semanticKey,
  });

  /// Etiqueta visible y base de la etiqueta semántica.
  final String label;

  final VoidCallback? onPressed;

  /// Icono pequeño dentro del botón (siempre visible).
  final IconData? icon;

  /// Pictograma grande que solo aparece en modo pictogramas.
  final IconData? pictogram;

  /// Texto adicional que el lector de pantalla lee como `hint`.
  final String? hint;

  final bool isPrimary;

  /// Ocupa todo el ancho disponible.
  final bool expand;

  /// Muestra un indicador de progreso y deshabilita el botón.
  final bool busy;

  /// Permite fijar el orden de foco lógico con `OrdinalSortKey`.
  final OrdinalSortKey? semanticKey;

  @override
  Widget build(BuildContext context) {
    final a11y = AccessibilityProvider.of(context);
    final theme = Theme.of(context);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: SizedBox.square(
              dimension: a11y.iconSize * 0.75,
              child: const CircularProgressIndicator(strokeWidth: 2.5),
            ),
          )
        else if (a11y.pictograms && pictogram != null) ...[
          Icon(
            pictogram,
            size: a11y.pictogramSize,
            semanticLabel: '',
          ),
          const SizedBox(width: AppSpacing.md),
        ] else if (icon != null) ...[
          Icon(icon, size: a11y.iconSize, semanticLabel: ''),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: a11y.bigButtons
                  ? (theme.textTheme.labelLarge?.fontSize ?? 14) + 4
                  : null,
            ),
          ),
        ),
      ],
    );

    final effectiveOnPressed = busy ? null : onPressed;

    return Semantics(
      button: true,
      enabled: effectiveOnPressed != null,
      sortKey: semanticKey,
      label: label,
      hint: hint,
      // Se excluye el subárbol para no duplicar la etiqueta con el texto hijo.
      excludeSemantics: true,
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: isPrimary
            ? FilledButton(
                onPressed: effectiveOnPressed,
                child: content,
              )
            : OutlinedButton(
                onPressed: effectiveOnPressed,
                child: content,
              ),
      ),
    );
  }
}

/// Tarjeta de sección reutilizable con título, subtítulo y contenido.
class LuminaSectionCard extends StatelessWidget {
  const LuminaSectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.leadingIcon,
    this.trailing,
    this.padding,
    this.semanticLabel,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  /// Etiqueta semántica del grupo; si es nula se compone con el título.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);

    return Semantics(
      container: true,
      label: semanticLabel ?? title,
      child: Card(
        child: Padding(
          padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    if (leadingIcon != null) ...[
                      Icon(
                        leadingIcon,
                        size: a11y.iconSize,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Text(title!, style: theme.textTheme.titleMedium),
                    ),
                    ?trailing,
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                SizedBox(height: a11y.controlGap),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Opción seleccionable con pictograma grande opcional.
///
/// Se usa en el formulario y en los módulos ProGrip/OrthoSnap. En modo
/// pictogramas la altura crece para dar cabida al icono de 56 dp.
class PictogramOptionTile extends StatelessWidget {
  const PictogramOptionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.description,
    this.pictogram,
    this.semanticKey,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? description;
  final IconData? pictogram;
  final OrdinalSortKey? semanticKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final showPictogram = a11y.pictograms && pictogram != null;

    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return Semantics(
      button: true,
      selected: selected,
      sortKey: semanticKey,
      label: label,
      hint: description,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardRadius,
          child: Container(
            constraints: BoxConstraints(
              minHeight: a11y.minTapTarget,
            ),
            padding: EdgeInsets.all(
              a11y.bigButtons ? AppSpacing.lg : AppSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.cardRadius,
              border: Border.all(
                color: borderColor,
                width: selected ? 3 : (a11y.contrastOutline == Colors.transparent ? 1 : 2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  showPictogram ? pictogram : icon,
                  size: showPictogram ? a11y.pictogramSize : a11y.iconSize,
                  color: theme.colorScheme.primary,
                ),
                SizedBox(width: a11y.controlGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (description != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    size: a11y.iconSize,
                    color: theme.colorScheme.primary,
                    semanticLabel: 'Seleccionado',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vista de carga reutilizable y accesible.
class LuminaLoadingView extends StatelessWidget {
  const LuminaLoadingView({super.key, this.message, this.progress});

  final String? message;

  /// Progreso 0.0-1.0; si es nulo se muestra un indicador indeterminado.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: message ?? 'Cargando',
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (progress == null)
              const CircularProgressIndicator()
            else
              CircularProgressIndicator(value: progress),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${(progress! * 100).round()} %',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Vista de error reutilizable, con acción de reintento.
class LuminaErrorView extends StatelessWidget {
  const LuminaErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Reintentar',
    this.title = 'Algo no salió bien',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
              semanticLabel: 'Error',
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AccessibleButton(
                label: retryLabel,
                icon: Icons.refresh,
                pictogram: Icons.refresh,
                onPressed: onRetry,
                expand: false,
                hint: 'Vuelve a intentar la última operación',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Caja informativa (aviso, nota o advertencia) con icono y color semántico.
class LuminaInfoBanner extends StatelessWidget {
  const LuminaInfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.tone = LuminaBannerTone.info,
  });

  final String message;
  final IconData icon;
  final LuminaBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);

    final (Color background, Color foreground) = switch (tone) {
      LuminaBannerTone.info => (
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
        ),
      LuminaBannerTone.warning => (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        ),
      LuminaBannerTone.error => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        ),
    };

    return Semantics(
      container: true,
      liveRegion: tone != LuminaBannerTone.info,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: a11y.iconSize, color: foreground),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum LuminaBannerTone { info, warning, error }
