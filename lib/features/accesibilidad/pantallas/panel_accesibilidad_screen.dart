import 'package:accessibility_widget/accessibility_widget.dart' as wcag;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../core/app_theme.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../providers/accessibility_provider.dart';

/// Panel de accesibilidad conmutable en caliente.
///
/// Combina dos capas:
///  1. Los modos propios de Lumina (TalkBack, botones grandes, pictogramas,
///     reducir movimiento), gestionados por [AccessibilityProvider].
///  2. Los controles WCAG que aporta `accessibility_widget` (dislexia,
///     contraste, saturación, guía de lectura, escala de texto...), servidos
///     por [wcag.AccessibilityPanelContent].
///
/// Ambas capas se sincronizan en dos direcciones para que el tema de toda la
/// app (no solo el panel) refleje los cambios al instante.
class PanelAccesibilidadScreen extends StatefulWidget {
  const PanelAccesibilidadScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const PanelAccesibilidadScreen(),
      );

  @override
  State<PanelAccesibilidadScreen> createState() =>
      _PanelAccesibilidadScreenState();
}

class _PanelAccesibilidadScreenState extends State<PanelAccesibilidadScreen> {
  late final wcag.AccessibilityController _wcag;

  /// Evita que la sincronización en dos direcciones entre en bucle.
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _wcag = wcag.AccessibilityController();
    _wcag.restore();
    _wcag.addListener(_onWcagChanged);
    // Arranca con los valores que ya tiene Lumina.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushProviderToWcag());
  }

  @override
  void dispose() {
    _wcag.removeListener(_onWcagChanged);
    _wcag.dispose();
    super.dispose();
  }

  AccessibilityProvider get _provider =>
      context.read<AccessibilityProvider>();

  /// `accessibility_widget` -> Lumina (por ejemplo, al tocar "Dislexia" en el
  /// panel WCAG, Lumina debe activar Andika en toda la app).
  void _onWcagChanged() {
    if (_syncing || !mounted) {
      setState(() {});
      return;
    }
    _syncing = true;
    final settings = _wcag.settings;
    final provider = _provider;
    if (settings.dyslexiaFont != provider.dyslexiaFontEnabled) {
      provider.setDyslexiaFont(settings.dyslexiaFont);
    }
    if (settings.highContrast != provider.highContrastEnabled) {
      provider.setHighContrast(settings.highContrast);
    }
    _syncing = false;
    setState(() {});
  }

  /// Lumina -> `accessibility_widget`.
  void _pushProviderToWcag() {
    if (!mounted) return;
    _syncing = true;
    final provider = _provider;
    final settings = _wcag.settings;
    _wcag.update(
      settings.copyWith(
        dyslexiaFont: provider.dyslexiaFontEnabled,
        highContrast: provider.highContrastEnabled,
      ),
    );
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccessibilityProvider>();

    // Reconstruye el tema del panel combinando ambas fuentes de verdad, de modo
    // que el cambio se ve antes incluso de salir del panel.
    final wcagSettings = _wcag.settings;
    final baseExtension = provider.themeExtension;
    final effectiveExtension = baseExtension.copyWith(
      dyslexiaFont: provider.dyslexiaFontEnabled || wcagSettings.dyslexiaFont,
      highContrast: provider.highContrastEnabled || wcagSettings.highContrast,
      letterSpacing: wcagSettings.letterSpacing != 0
          ? wcagSettings.letterSpacing
          : baseExtension.letterSpacing,
      lineHeight: wcagSettings.lineSpacing != 1.0
          ? wcagSettings.lineSpacing
          : baseExtension.lineHeight,
    );
    final highContrast =
        provider.highContrastEnabled || wcagSettings.highContrast;

    final ambient = Theme.of(context);
    final isDark = wcagSettings.darkMode ?? ambient.brightness == Brightness.dark;
    final panelTheme = isDark
        ? AppTheme.dark(
            accessibility: effectiveExtension,
            highContrast: highContrast,
          )
        : AppTheme.light(
            accessibility: effectiveExtension,
            highContrast: highContrast,
          );

    return wcag.AccessibilityScope(
      controller: _wcag,
      child: Theme(
        data: panelTheme,
        child: Builder(
          builder: (panelContext) => Scaffold(
            appBar: AppBar(
              title: const Text('Accesibilidad'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cerrar el panel de accesibilidad',
                onPressed: () => Navigator.of(panelContext).maybePop(),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                LuminaInfoBanner(
                  message: provider.activeModeCount == 0
                      ? 'Ningún modo activo. Activa los que necesites: los cambios se aplican al instante y se guardan en el dispositivo.'
                      : '${provider.activeModeCount} modo(s) activo(s). Los cambios se aplican al instante y se guardan en el dispositivo.',
                  icon: Icons.accessibility_new,
                ),
                const SizedBox(height: AppSpacing.lg),

                LuminaSectionCard(
                  title: 'Perfiles rápidos',
                  subtitle:
                      'Configura varios modos de una sola vez según tu necesidad.',
                  leadingIcon: Icons.bolt,
                  child: Column(
                    children: [
                      for (final preset in AccessibilityPreset.values)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.sm,
                          ),
                          child: AccessibleButton(
                            label: preset.label,
                            hint: preset.description,
                            icon: Icons.play_arrow,
                            pictogram: _presetPictogram(preset),
                            isPrimary: false,
                            onPressed: () =>
                                provider.applyPreset(preset),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                LuminaSectionCard(
                  title: 'Modos de Lumina',
                  subtitle: 'Se aplican en todas las pantallas.',
                  leadingIcon: Icons.tune,
                  child: Column(
                    children: [
                      _ModeSwitch(
                        title: 'Modo TalkBack / VoiceOver',
                        description:
                            'Etiquetas y anuncios para el lector de pantalla, con orden de foco lógico.',
                        value: provider.talkBackEnabled,
                        onChanged: provider.setTalkBack,
                        icon: Icons.record_voice_over,
                      ),
                      _ModeSwitch(
                        title: 'Botones grandes',
                        description:
                            'Área táctil mínima de 64x64 dp y más separación entre controles.',
                        value: provider.bigButtonsEnabled,
                        onChanged: provider.setBigButtons,
                        icon: Icons.touch_app,
                      ),
                      _ModeSwitch(
                        title: 'Modo pictogramas',
                        description:
                            'Iconos grandes junto a cada etiqueta para reconocer acciones de un vistazo.',
                        value: provider.pictogramsEnabled,
                        onChanged: provider.setPictograms,
                        icon: Icons.emoji_emotions_outlined,
                      ),
                      _ModeSwitch(
                        title: 'Reducir movimiento',
                        description: 'Desactiva animaciones y auto-rotación.',
                        value: provider.reduceMotionEnabled,
                        onChanged: provider.setReduceMotion,
                        icon: Icons.motion_photos_off,
                      ),
                      Divider(color: panelTheme.dividerTheme.color),
                      _ModeSwitch(
                        title: 'Modo dislexia (fuente Andika)',
                        description:
                            'Fuente Andika, mayor altura de línea y espaciado entre letras.',
                        value: provider.dyslexiaFontEnabled,
                        onChanged: provider.setDyslexiaFont,
                        icon: Icons.text_fields,
                      ),
                      _ModeSwitch(
                        title: 'Alto contraste',
                        description:
                            'Colores reforzados (amarillo sobre negro o negro sobre blanco).',
                        value: provider.highContrastEnabled,
                        onChanged: provider.setHighContrast,
                        icon: Icons.contrast,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                LuminaSectionCard(
                  title: 'Más ajustes de lectura y color',
                  subtitle:
                      'Controles WCAG: escala de texto, saturación, guía de lectura, cursor grande...',
                  leadingIcon: Icons.visibility,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                  child: const wcag.AccessibilityPanelContent(),
                ),
                const SizedBox(height: AppSpacing.lg),

                AccessibleButton(
                  label: 'Restablecer todos los ajustes',
                  icon: Icons.restart_alt,
                  pictogram: Icons.restart_alt,
                  isPrimary: false,
                  hint: 'Desactiva todos los modos de accesibilidad',
                  onPressed: () {
                    _syncing = true;
                    _wcag.reset();
                    _syncing = false;
                    provider.resetAll();
                    setState(() {});
                  },
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _presetPictogram(AccessibilityPreset preset) => switch (preset) {
        AccessibilityPreset.motriz => Icons.pan_tool_alt,
        AccessibilityPreset.visual => Icons.visibility,
        AccessibilityPreset.cognitiva => Icons.psychology_alt,
        AccessibilityPreset.ninguno => Icons.restart_alt,
      };
}

/// Interruptor con etiqueta, descripción y pictograma opcional.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.icon,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);

    return Semantics(
      toggled: value,
      label: title,
      hint: description,
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: a11y.bigButtons ? AppSpacing.md : AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: a11y.iconSize, color: theme.colorScheme.primary),
            SizedBox(width: a11y.controlGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
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
            SizedBox(width: a11y.controlGap),
            // `MergeSemantics` con el switch dentro evita que TalkBack anuncie
            // el texto dos veces: una por la fila y otra por el propio switch.
            ExcludeSemantics(
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
