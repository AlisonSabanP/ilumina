import 'package:flutter/material.dart';

/// Escala de espaciado, radios y duraciones de Lumina.
///
/// Se centralizan aquí para que todos los componentes compartan el mismo
/// ritmo visual (requisito de diseño: "radios, elevación y espaciados
/// consistentes en todos los componentes").
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  /// Separación extra aplicada cuando el modo "botones grandes" está activo.
  static const double bigModeBoost = 8;
}

/// Radios de esquina.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius fieldRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(md));
}

/// Elevaciones consistentes (Material 3 las interpreta como `surfaceTint`).
abstract final class AppElevation {
  static const double none = 0;
  static const double low = 1;
  static const double medium = 3;
  static const double high = 6;
}

/// Duraciones de animación (se reducen a cero en modo "reducir movimiento").
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);

  /// Devuelve [duration] o [Duration.zero] si el usuario pidió menos animación.
  static Duration respect(bool reduceMotion, Duration duration) =>
      reduceMotion ? Duration.zero : duration;
}
