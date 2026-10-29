/// Contrato de los modos de accesibilidad que Lumina controla y aplica.
///
/// `accessibility_widget` gestiona las preferencias visuales/lectura
/// (dislexia, contraste, saturación, espaciados...). Lumina añade encima
/// los modos propios de la app: botones grandes y pictogramas.
///
/// Los lectores de pantalla del sistema **no aparecen aquí a propósito**: se
/// activan desde los ajustes del dispositivo, no desde la app. Lo que Lumina
/// garantiza es que sus widgets estén bien etiquetados con `Semantics`.
abstract interface class AccessibilityModes {
  bool get bigButtonsEnabled;
  bool get pictogramsEnabled;

  /// Modo dislexia (fuente Andika). Lo sirve `accessibility_widget`.
  bool get dyslexiaFontEnabled;

  /// Alto contraste. Lo sirve `accessibility_widget`.
  bool get highContrastEnabled;

  /// Cualquier ajuste que exija espaciados/áreas táctiles ampliadas.
  bool get needsLargeTouchTargets;

  void setBigButtons(bool value);
  void setPictograms(bool value);
  void setDyslexiaFont(bool value);
  void setHighContrast(bool value);
}

/// Dimensiones mínimas de área táctil exigidas por el modo "botones grandes".
abstract final class AccessibilityMetrics {
  /// WCAG 2.2 (2.5.5 Target Size Enhanced) recomienda 44x44 dp; Lumina sube a
  /// 64x64 dp cuando el modo de botones grandes está activo, tal como pide el
  /// pliego del proyecto.
  static const double minTapTarget = 64;

  /// Área táctil estándar cuando el modo no está activo.
  static const double defaultTapTarget = 48;

  static const double minButtonHeight = 64;
  static const double minIconSize = 32;
  static const double pictogramSize = 56;
}

/// Constantes de los modos aplicados con `Semantics`.
abstract final class SemanticsLabels {
  static const String bigButtons = 'Modo botones grandes';
  static const String pictograms = 'Modo pictogramas';
  static const String dyslexia = 'Modo dislexia';
  static const String highContrast = 'Alto contraste';
}
