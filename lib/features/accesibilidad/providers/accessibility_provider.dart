import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/accessibility_contract.dart';
import '../../../core/app_theme.dart';

/// Estado global de accesibilidad de Lumina.
///
/// Responsabilidades:
///  * Mantener los modos propios de Lumina: TalkBack, botones grandes y
///    pictogramas, además de dislexia y alto contraste.
///  * Persistir cada cambio en `SharedPreferences`.
///  * Exponer un [LuminaAccessibilityTheme] que se inyecta en [ThemeData] para
///    que los componentes adapten su geometría.
///  * Anunciar los cambios con `SemanticsService` cuando el modo TalkBack está
///    activo, de modo que el lector de pantalla confirme la acción.
///
/// Se eligió `provider` (ChangeNotifier) frente a `riverpod` porque el estado
/// de accesibilidad es un único objeto global de ciclo de vida largo, sin
/// dependencias asíncronas entre sí: `ChangeNotifier` + `context.watch`
/// resuelve el caso con menos ceremonia y es más fácil de leer en un proyecto
/// escolar. `riverpod` aportaría ventajas (testabilidad, autodispose) que aquí
/// no se aprovechan.
class AccessibilityProvider extends ChangeNotifier implements AccessibilityModes {
  AccessibilityProvider({SharedPreferences? preferences})
      : _preferences = preferences; // ignore: prefer_initializing_formals

  static const String _keyTalkBack = 'lumina.a11y.talkBack';
  static const String _keyBigButtons = 'lumina.a11y.bigButtons';
  static const String _keyPictograms = 'lumina.a11y.pictograms';
  static const String _keyDyslexia = 'lumina.a11y.dyslexiaFont';
  static const String _keyHighContrast = 'lumina.a11y.highContrast';
  static const String _keyReduceMotion = 'lumina.a11y.reduceMotion';

  SharedPreferences? _preferences;

  bool _talkBackEnabled = false;
  bool _bigButtonsEnabled = false;
  bool _pictogramsEnabled = false;
  bool _dyslexiaFontEnabled = false;
  bool _highContrastEnabled = false;
  bool _reduceMotionEnabled = false;

  // --- Lectura ---------------------------------------------------------------

  @override
  bool get talkBackEnabled => _talkBackEnabled;

  @override
  bool get bigButtonsEnabled => _bigButtonsEnabled;

  @override
  bool get pictogramsEnabled => _pictogramsEnabled;

  @override
  bool get dyslexiaFontEnabled => _dyslexiaFontEnabled;

  @override
  bool get highContrastEnabled => _highContrastEnabled;

  bool get reduceMotionEnabled => _reduceMotionEnabled;

  @override
  bool get needsLargeTouchTargets => _bigButtonsEnabled;

  /// Número de modos activos: la pantalla de inicio lo usa como resumen.
  int get activeModeCount => [
        _talkBackEnabled,
        _bigButtonsEnabled,
        _pictogramsEnabled,
        _dyslexiaFontEnabled,
        _highContrastEnabled,
        _reduceMotionEnabled,
      ].where((enabled) => enabled).length;

  // --- Escritura -------------------------------------------------------------

  @override
  void setTalkBack(bool value) => _update(() => _talkBackEnabled = value,
      _keyTalkBack, value, SemanticsLabels.talkBack);

  @override
  void setBigButtons(bool value) => _update(() => _bigButtonsEnabled = value,
      _keyBigButtons, value, SemanticsLabels.bigButtons);

  @override
  void setPictograms(bool value) => _update(() => _pictogramsEnabled = value,
      _keyPictograms, value, SemanticsLabels.pictograms);

  @override
  void setDyslexiaFont(bool value) => _update(() => _dyslexiaFontEnabled = value,
      _keyDyslexia, value, SemanticsLabels.dyslexia);

  @override
  void setHighContrast(bool value) => _update(() => _highContrastEnabled = value,
      _keyHighContrast, value, SemanticsLabels.highContrast);

  void setReduceMotion(bool value) => _update(() => _reduceMotionEnabled = value,
      _keyReduceMotion, value, 'Reducir movimiento');

  /// Desactiva todos los modos y borra las preferencias guardadas.
  void resetAll() {
    _talkBackEnabled = false;
    _bigButtonsEnabled = false;
    _pictogramsEnabled = false;
    _dyslexiaFontEnabled = false;
    _highContrastEnabled = false;
    _reduceMotionEnabled = false;
    final prefs = _preferences;
    if (prefs != null) {
      for (final key in [
        _keyTalkBack,
        _keyBigButtons,
        _keyPictograms,
        _keyDyslexia,
        _keyHighContrast,
        _keyReduceMotion,
      ]) {
        prefs.remove(key);
      }
    }
    notifyListeners();
    _announce('Ajustes de accesibilidad restablecidos');
  }

  /// Aplica un perfil preajustado de una sola vez.
  void applyPreset(AccessibilityPreset preset) {
    switch (preset) {
      case AccessibilityPreset.motriz:
        _bigButtonsEnabled = true;
        _talkBackEnabled = true;
        _pictogramsEnabled = true;
        _dyslexiaFontEnabled = false;
        _highContrastEnabled = true;
        _reduceMotionEnabled = true;
      case AccessibilityPreset.visual:
        _talkBackEnabled = true;
        _bigButtonsEnabled = true;
        _highContrastEnabled = true;
        _dyslexiaFontEnabled = false;
        _pictogramsEnabled = false;
        _reduceMotionEnabled = true;
      case AccessibilityPreset.cognitiva:
        _pictogramsEnabled = true;
        _dyslexiaFontEnabled = true;
        _reduceMotionEnabled = true;
        _talkBackEnabled = true;
        _bigButtonsEnabled = true;
        _highContrastEnabled = false;
      case AccessibilityPreset.ninguno:
        resetAll();
        return;
    }
    notifyListeners();
    _persistAll();
    _announce('Perfil ${preset.label} activado');
  }

  // --- Persistencia ----------------------------------------------------------

  /// Restaura las preferencias guardadas. Se llama una vez al arrancar.
  Future<void> restore() async {
    try {
      final prefs = _preferences ??= await SharedPreferences.getInstance();
      _talkBackEnabled = prefs.getBool(_keyTalkBack) ?? false;
      _bigButtonsEnabled = prefs.getBool(_keyBigButtons) ?? false;
      _pictogramsEnabled = prefs.getBool(_keyPictograms) ?? false;
      _dyslexiaFontEnabled = prefs.getBool(_keyDyslexia) ?? false;
      _highContrastEnabled = prefs.getBool(_keyHighContrast) ?? false;
      _reduceMotionEnabled = prefs.getBool(_keyReduceMotion) ?? false;
      notifyListeners();
    } catch (error) {
      // Un fallo de almacenamiento no debe impedir el arranque.
      debugPrint('AccessibilityProvider.restore falló: $error');
    }
  }

  void _update(
    VoidCallback mutate,
    String key,
    bool value,
    String label,
  ) {
    mutate();
    notifyListeners();
    _writePref(key, value);
    _announce('$label ${value ? 'activado' : 'desactivado'}');
  }

  /// Guarda una preferencia resolviendo `SharedPreferences` en diferido.
  ///
  /// No se asume que `restore()` haya terminado: si el usuario toca un
  /// interruptor antes de que el almacenamiento esté listo, el valor se
  /// escribe igualmente en cuanto esté disponible.
  Future<void> _writePref(String key, bool value) async {
    try {
      final prefs = _preferences ??= await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error) {
      debugPrint('No se pudo guardar "$key": $error');
    }
  }

  void _persistAll() {
    _writePref(_keyTalkBack, _talkBackEnabled);
    _writePref(_keyBigButtons, _bigButtonsEnabled);
    _writePref(_keyPictograms, _pictogramsEnabled);
    _writePref(_keyDyslexia, _dyslexiaFontEnabled);
    _writePref(_keyHighContrast, _highContrastEnabled);
    _writePref(_keyReduceMotion, _reduceMotionEnabled);
  }

  /// Anuncia el cambio al lector de pantalla cuando TalkBack está activo.
  void _announce(String message) {
    if (!_talkBackEnabled) return;
    // `announce` está marcado como deprecado en favor de `sendAnnouncement`,
    // que exige una `FlutterView`. `announce` sigue funcionando y evita
    // tener que resolver la vista desde aquí.
    // ignore: deprecated_member_use
    SemanticsService.announce(message, TextDirection.ltr).catchError(
      (Object error) => debugPrint('Anuncio falló: $error'),
    );
  }

  // --- Derivados para el tema ------------------------------------------------

  /// Modo dislexia: la app aumenta además la altura de línea y el espaciado
  /// entre letras, tal como pide el pliego.
  LuminaAccessibilityTheme get themeExtension => LuminaAccessibilityTheme(
        bigButtons: _bigButtonsEnabled,
        pictograms: _pictogramsEnabled,
        talkBack: _talkBackEnabled,
        reduceMotion: _reduceMotionEnabled,
        letterSpacing: _dyslexiaFontEnabled ? 1.2 : 0.15,
        lineHeight: _dyslexiaFontEnabled ? 1.7 : 0,
        fontFamilyOverride: _dyslexiaFontEnabled
            ? AppTheme.dyslexiaFontFamily
            : null,
        contrastOutline: _highContrastEnabled
            ? const Color(0xFFFFFFFF)
            : Colors.transparent,
      );

  /// Lee el [LuminaAccessibilityTheme] del contexto sin depender del provider.
  static LuminaAccessibilityTheme of(BuildContext context) =>
      Theme.of(context).extension<LuminaAccessibilityTheme>() ??
      LuminaAccessibilityTheme.neutral;
}

/// Perfiles de un solo toque, alineados con los tres públicos de Lumina.
enum AccessibilityPreset {
  motriz('Motriz', 'Botones grandes, pictogramas, alto contraste y TalkBack'),
  visual('Visual', 'TalkBack, alto contraste y botones grandes'),
  cognitiva(
    'Cognitiva / Sensibilidad',
    'Pictogramas, fuente Andika y sin animaciones',
  ),
  ninguno('Sin ajustes', 'Restablece todos los modos');

  const AccessibilityPreset(this.label, this.description);

  final String label;
  final String description;
}
