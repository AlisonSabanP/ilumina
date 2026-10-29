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
///  1. Los modos propios de Lumina (botones grandes, pictogramas, dislexia,
///     alto contraste, reducir movimiento), gestionados por
///     [AccessibilityProvider].
///  2. Los controles WCAG que aporta `accessibility_widget` (escala de texto,
///     negrita, espaciados, saturación...), servidos por su controlador.
///
/// Se han retirado los controles "Invertir colores" y "Guía de lectura": el
/// paquete los guardaba pero no los aplicaba al árbol de widgets, así que el
/// interruptor no cambiaba nada. Se prefirió quitarlos antes que dejar un
/// control que no hace lo que promete.
///
/// **Los controles se dibujan aquí, en español, en lugar de usar el
/// `AccessibilityPanelContent` del paquete**: ese widget trae los textos fijos
/// en inglés ("Text Size", "Dyslexia Friendly Font"...), y un panel de
/// accesibilidad en inglés es inservible para el público de Lumina. Se sigue
/// usando el controlador del paquete, que es donde vive la lógica y la
/// persistencia; solo se sustituye la capa de presentación.
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

  AccessibilityProvider get _provider => context.read<AccessibilityProvider>();

  /// `accessibility_widget` -> Lumina (por ejemplo, al activar "dislexia" en un
  /// control, Lumina debe activar Andika en toda la app).
  void _onWcagChanged() {
    if (!mounted) return;
    if (_syncing) {
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
    if (settings.stopAnimations != provider.reduceMotionEnabled) {
      provider.setReduceMotion(settings.stopAnimations);
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
        stopAnimations: provider.reduceMotionEnabled,
      ),
    );
    _syncing = false;
  }

  /// Aplica un cambio al controlador del paquete y, si toca un modo de Lumina,
  /// lo propaga al provider para que el tema de toda la app se reconstruya.
  void _updateWcag(
    wcag.AccessibilitySettings Function(wcag.AccessibilitySettings) mutate, {
    bool dyslexia = false,
    bool highContrast = false,
    bool reduceMotion = false,
  }) {
    _syncing = true;
    _wcag.update(mutate(_wcag.settings));
    _syncing = false;

    if (dyslexia) {
      _provider.setDyslexiaFont(_wcag.settings.dyslexiaFont);
    }
    if (highContrast) {
      _provider.setHighContrast(_wcag.settings.highContrast);
    }
    if (reduceMotion) {
      _provider.setReduceMotion(_wcag.settings.stopAnimations);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccessibilityProvider>();
    final settings = _wcag.settings;

    // Reconstruye el tema del panel combinando ambas fuentes de verdad, de modo
    // que el cambio se ve antes incluso de salir del panel.
    final baseExtension = provider.themeExtension;
    final effectiveExtension = baseExtension.copyWith(
      dyslexiaFont: provider.dyslexiaFontEnabled || settings.dyslexiaFont,
      highContrast: provider.highContrastEnabled || settings.highContrast,
      letterSpacing: settings.letterSpacing != 0
          ? settings.letterSpacing
          : baseExtension.letterSpacing,
      lineHeight: settings.lineSpacing != 1.0
          ? settings.lineSpacing
          : baseExtension.lineHeight,
    );
    final highContrast = provider.highContrastEnabled || settings.highContrast;

    final ambient = Theme.of(context);
    final isDark = settings.darkMode ?? ambient.brightness == Brightness.dark;
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
                            onPressed: () {
                              provider.applyPreset(preset);
                              _pushProviderToWcag();
                              setState(() {});
                            },
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
                      Divider(color: panelTheme.dividerTheme.color),
                      _ModeSwitch(
                        title: 'Modo dislexia (fuente Andika)',
                        description:
                            'Fuente Andika, mayor altura de línea y espaciado entre letras.',
                        value: provider.dyslexiaFontEnabled,
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(dyslexiaFont: value),
                          dyslexia: true,
                        ),
                        icon: Icons.text_fields,
                      ),
                      _ModeSwitch(
                        title: 'Alto contraste',
                        description:
                            'Colores reforzados (amarillo sobre negro o negro sobre blanco).',
                        value: provider.highContrastEnabled,
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(highContrast: value),
                          highContrast: true,
                        ),
                        icon: Icons.contrast,
                      ),
                      _ModeSwitch(
                        title: 'Reducir movimiento',
                        description: 'Desactiva animaciones y auto-rotación.',
                        value: provider.reduceMotionEnabled,
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(stopAnimations: value),
                          reduceMotion: true,
                        ),
                        icon: Icons.motion_photos_off,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // --- Texto y lectura ---
                LuminaSectionCard(
                  title: 'Texto y lectura',
                  subtitle: 'Ajustes de tipografía: tamaño, negrita y espaciados.',
                  leadingIcon: Icons.text_fields,
                  child: Column(
                    children: [
                      _SliderTile(
                        title: 'Tamaño del texto',
                        description: 'Escala todo el texto de la aplicación.',
                        value: settings.textScale,
                        min: 1.0,
                        max: 2.0,
                        divisions: 10,
                        valueLabel: '${(settings.textScale * 100).round()} %',
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(textScale: value),
                        ),
                      ),
                      _ModeSwitch(
                        title: 'Texto en negrita',
                        description: 'Aumenta el grosor para leer mejor.',
                        value: settings.boldText,
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(boldText: value),
                        ),
                        icon: Icons.format_bold,
                      ),
                      _SliderTile(
                        title: 'Espacio entre líneas',
                        description: 'Separa más las líneas de texto.',
                        value: settings.lineSpacing,
                        min: 1.0,
                        max: 2.5,
                        divisions: 15,
                        valueLabel: settings.lineSpacing.toStringAsFixed(1),
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(lineSpacing: value),
                        ),
                      ),
                      _SliderTile(
                        title: 'Espacio entre letras',
                        description: 'Separa más las letras.',
                        value: settings.letterSpacing,
                        min: 0.0,
                        max: 4.0,
                        divisions: 16,
                        valueLabel: settings.letterSpacing.toStringAsFixed(1),
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(letterSpacing: value),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // --- Color y contraste ---
                LuminaSectionCard(
                  title: 'Color y contraste',
                  subtitle: 'Ajusta los colores de toda la aplicación.',
                  leadingIcon: Icons.palette_outlined,
                  child: Column(
                    children: [
                      _SliderTile(
                        title: 'Saturación del color',
                        description:
                            'A 0 el contenido se ve en escala de grises.',
                        value: settings.saturation,
                        min: 0.0,
                        max: 1.0,
                        divisions: 10,
                        valueLabel: '${(settings.saturation * 100).round()} %',
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(saturation: value),
                        ),
                      ),
                      _ThemeModeTile(
                        value: settings.darkMode,
                        onChanged: (value) => _updateWcag(
                          (s) => value == null
                              ? s.copyWith(clearDarkMode: true)
                              : s.copyWith(darkMode: value),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // --- Contenido y resaltado ---
                LuminaSectionCard(
                  title: 'Contenido y resaltado',
                  subtitle:
                      'Útil para baja visión y para reducir distracciones.',
                  leadingIcon: Icons.visibility_outlined,
                  child: Column(
                    children: [
                      _ModeSwitch(
                        title: 'Ocultar imágenes',
                        description:
                            'Sustituye las imágenes por un texto descriptivo.',
                        value: settings.hideImages,
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(hideImages: value),
                        ),
                        icon: Icons.image_not_supported_outlined,
                      ),
                      _ModeSwitch(
                        title: 'Resaltar enlaces',
                        description:
                            'Subraya y colorea los enlaces para localizarlos mejor.',
                        value: settings.highlightLinks,
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(highlightLinks: value),
                        ),
                        icon: Icons.link,
                      ),
                      _ModeSwitch(
                        title: 'Resaltar tarjetas y listas',
                        description:
                            'Dibuja el contorno de todo lo que se puede tocar.',
                        value: settings.highlightTiles,
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(highlightTiles: value),
                        ),
                        icon: Icons.crop_free,
                      ),
                      _ModeSwitch(
                        title: 'Resaltar títulos',
                        description:
                            'Marca visualmente los títulos de cada sección.',
                        value: settings.highlightHeadings,
                        onChanged: (value) => _updateWcag(
                          (s) => s.copyWith(highlightHeadings: value),
                        ),
                        icon: Icons.title,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // --- Respuesta táctil ---
                LuminaSectionCard(
                  title: 'Respuesta táctil',
                  subtitle: 'Ayuda a confirmar que un toque se ha registrado.',
                  leadingIcon: Icons.vibration,
                  child: _ModeSwitch(
                    title: 'Vibración al tocar',
                    description:
                        'Una vibración corta cada vez que se pulsa un control.',
                    value: settings.hapticFeedback,
                    onChanged: (value) => _updateWcag(
                      (s) => s.copyWith(hapticFeedback: value),
                    ),
                    icon: Icons.vibration,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

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
        padding: EdgeInsets.symmetric(
          vertical: a11y.bigButtons ? AppSpacing.md : AppSpacing.sm,
        ),
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
            // Se excluye el switch del árbol semántico para que el lector
            // anuncie una sola vez el título y su estado, en lugar de leer
            // además el propio control.
            ExcludeSemantics(
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ajuste numérico con etiqueta, descripción y valor visible.
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              Text(valueLabel, style: theme.textTheme.titleMedium),
            ],
          ),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Semantics(
            slider: true,
            label: title,
            hint: description,
            value: valueLabel,
            child: ExcludeSemantics(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selector de tema claro, oscuro o el del sistema.
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({required this.value, required this.onChanged});

  /// `null` = seguir el sistema.
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tema de la aplicación', style: theme.textTheme.titleMedium),
          Text(
            'Claro, oscuro o el que tenga configurado el teléfono.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: 'Tema de la aplicación',
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'system',
                  label: Text('Sistema'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment<String>(
                  value: 'light',
                  label: Text('Claro'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment<String>(
                  value: 'dark',
                  label: Text('Oscuro'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: <String>{
                value == null
                    ? 'system'
                    : value!
                        ? 'dark'
                        : 'light',
              },
              onSelectionChanged: (selection) {
                final chosen = selection.first;
                onChanged(chosen == 'system' ? null : chosen == 'dark');
              },
            ),
          ),
        ],
      ),
    );
  }
}
