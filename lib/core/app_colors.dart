import 'package:flutter/material.dart';

/// Paleta oficial de Lumina.
///
/// Azul `#2C5F8A` y morado `#6B4C9A` son los colores de marca; el resto son
/// neutros suaves para no generar fatiga visual ni sobrecarga sensorial.
/// Las variantes `hc*` se usan cuando el modo de alto contraste está activo.
abstract final class AppColors {
  // --- Marca ---
  static const Color blue = Color(0xFF2C5F8A);
  static const Color blueDark = Color(0xFF1D4363);
  static const Color blueLight = Color(0xFF5B8DB8);
  static const Color purple = Color(0xFF6B4C9A);
  static const Color purpleDark = Color(0xFF4A3469);
  static const Color purpleLight = Color(0xFF9C7FC9);

  // --- Neutros ---
  static const Color white = Color(0xFFFFFFFF);
  static const Color grey50 = Color(0xFFF7F8FA);
  static const Color grey100 = Color(0xFFEEF1F5);
  static const Color grey200 = Color(0xFFDCE1E8);
  static const Color grey300 = Color(0xFFC3CAD4);
  static const Color grey400 = Color(0xFF98A2B0);
  static const Color grey600 = Color(0xFF5A6371);
  static const Color grey800 = Color(0xFF2C323C);
  static const Color grey900 = Color(0xFF1A1E25);

  // --- Estados ---
  static const Color success = Color(0xFF2E7D5B);
  static const Color warning = Color(0xFFB26A00);
  static const Color error = Color(0xFFB3261E);

  // --- Alto contraste (WCAG AAA) ---
  static const Color hcYellow = Color(0xFFFFD600);
  static const Color hcBlack = Color(0xFF000000);
  static const Color hcWhite = Color(0xFFFFFFFF);
  static const Color hcBlue = Color(0xFF00306B);
  static const Color hcPurple = Color(0xFF3B1E6E);
}
