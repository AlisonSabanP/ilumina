import 'package:accessibility_widget/accessibility_widget.dart' as wcag;
import 'package:flutter/material.dart';
import 'package:nested/nested.dart' show SingleChildWidget;
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../features/accesibilidad/providers/accessibility_provider.dart';
import '../features/formulario/modelos/formulario_provider.dart';
import '../features/generacion3d/providers/generation_provider.dart';
import '../features/home/pantallas/home_screen.dart';
import '../features/orthosnap/providers/auth_provider.dart';
import '../features/progrip/providers/progrip_provider.dart';

/// Raíz de la aplicación.
///
/// Responsabilidades:
///  * Construir el [MaterialApp] con el tema que refleja los modos de
///    accesibilidad activos.
///  * Envolver el árbol con el [wcag.AccessibilityWidget] del paquete
///    `accessibility_widget`, que aporta escala de texto, filtros de color,
///    guía de lectura, cursor grande y el `AccessibilityScope` que su panel
///    necesita.
///  * Sincronizar los dos sistemas de accesibilidad: el [AccessibilityProvider]
///    de Lumina es la fuente de verdad y empuja a `accessibility_widget` los
///    valores que ambos comparten (dislexia y alto contraste), de modo que el
///    paquete los aplique también a sus propios widgets.
class LuminaApp extends StatefulWidget {
  const LuminaApp({super.key, required this.home});

  final Widget home;

  @override
  State<LuminaApp> createState() => _LuminaAppState();
}

class _LuminaAppState extends State<LuminaApp> {
  @override
  Widget build(BuildContext context) {
    final a11y = context.watch<AccessibilityProvider>();

    final extension = a11y.themeExtension;

    // El brillo efectivo depende del modo oscuro del sistema y del ajuste de
    // alto contraste, que fuerza un esquema de máximo contraste.
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    final theme = isDark
        ? AppTheme.dark(
            accessibility: extension,
            highContrast: a11y.highContrastEnabled,
          )
        : AppTheme.light(
            accessibility: extension,
            highContrast: a11y.highContrastEnabled,
          );

    // `accessibility_widget` necesita su propio wrapper: aporta los filtros de
    // color y la guía de lectura que Lumina no reimplementa.
    return wcag.AccessibilityWidget(
      child: _AccessibilitySync(
        child: MaterialApp(
          title: 'Lumina',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: AppTheme.dark(
            accessibility: extension,
            highContrast: a11y.highContrastEnabled,
          ),
          themeMode: ThemeMode.system,
          home: widget.home,
          builder: (context, child) {
            // Se aplica el escalado de texto respetando el que ya pida el
            // sistema: se toma el mayor de los dos para no reducir nunca el
            // tamaño que el usuario haya elegido en los ajustes del móvil.
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(
                  _effectiveTextScale(media.textScaler),
                ),
                // El orden de foco se mantiene lógico; se declara de forma
                // explícita porque TalkBack lo usa para navegar.
                boldText: media.boldText,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }

  double _effectiveTextScale(TextScaler scaler) {
    final systemScale = scaler.scale(1);
    // El paquete WCAG aplica su propio textScale; aquí solo se garantiza que
    // el sistema no reduzca el texto por debajo de 1.
    return systemScale < 1 ? 1 : systemScale;
  }
}

/// Sincroniza el [AccessibilityProvider] de Lumina con el controlador de
/// `accessibility_widget`.
///
/// Sin esta pieza, activar "dislexia" en Lumina no cambiaría el resto de
/// widgets del paquete, y activarlo en el panel del paquete no cambiaría el
/// tema de Lumina.
class _AccessibilitySync extends StatefulWidget {
  const _AccessibilitySync({required this.child});

  final Widget child;

  @override
  State<_AccessibilitySync> createState() => _AccessibilitySyncState();
}

class _AccessibilitySyncState extends State<_AccessibilitySync> {
  AccessibilityProvider? _lumina;
  wcag.AccessibilityController? _wcag;
  bool _syncing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lumina = context.read<AccessibilityProvider>();
    if (identical(lumina, _lumina)) return;

    _lumina?.removeListener(_pushLuminaToWcag);
    _lumina = lumina;
    _lumina!.addListener(_pushLuminaToWcag);

    // El controlador del paquete se obtiene del `AccessibilityScope` que crea
    // `AccessibilityWidget`. Puede no existir todavía en el primer frame.
    final scope = wcag.AccessibilityScope.maybeOf(context);
    final controller = scope?.controller;
    if (controller != null && !identical(controller, _wcag)) {
      _wcag?.removeListener(_pullWcagToLumina);
      _wcag = controller;
      _wcag!.addListener(_pullWcagToLumina);
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushLuminaToWcag());
    }
  }

  @override
  void dispose() {
    _lumina?.removeListener(_pushLuminaToWcag);
    _wcag?.removeListener(_pullWcagToLumina);
    super.dispose();
  }

  /// Lumina -> paquete WCAG.
  void _pushLuminaToWcag() {
    final lumina = _lumina;
    final wcagController = _wcag;
    if (lumina == null || wcagController == null || _syncing) return;
    _syncing = true;
    final settings = wcagController.settings;
    if (settings.dyslexiaFont != lumina.dyslexiaFontEnabled ||
        settings.highContrast != lumina.highContrastEnabled) {
      wcagController.update(
        settings.copyWith(
          dyslexiaFont: lumina.dyslexiaFontEnabled,
          highContrast: lumina.highContrastEnabled,
        ),
      );
    }
    _syncing = false;
  }

  /// Paquete WCAG -> Lumina.
  void _pullWcagToLumina() {
    final lumina = _lumina;
    final wcagController = _wcag;
    if (lumina == null || wcagController == null || _syncing) return;
    _syncing = true;
    final settings = wcagController.settings;
    if (settings.dyslexiaFont != lumina.dyslexiaFontEnabled) {
      lumina.setDyslexiaFont(settings.dyslexiaFont);
    }
    if (settings.highContrast != lumina.highContrastEnabled) {
      lumina.setHighContrast(settings.highContrast);
    }
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Raíz del árbol de providers y de la aplicación.
///
/// Se registran todos en la raíz porque varios módulos comparten estado: el
/// formulario alimenta la generación, la generación alimenta el visor, y
/// ProGrip y OrthoSnap escriben en el mismo estado de generación.
class LuminaRoot extends StatelessWidget {
  const LuminaRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AccessibilityProvider>(
          create: (_) => AccessibilityProvider()..restore(),
        ),
        ChangeNotifierProvider<FormularioProvider>(
          create: (_) => FormularioProvider(),
        ),
        ChangeNotifierProvider<ProGripProvider>(
          create: (_) => ProGripProvider(),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
        ),
        ChangeNotifierProvider<GenerationProvider>(
          create: (_) => GenerationProvider()..restoreHistory(),
        ),
      ],
      child: const LuminaApp(home: HomeScreen()),
    );
  }
}
