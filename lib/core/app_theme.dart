import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// [ThemeExtension] con las decisiones de accesibilidad que necesitan los
/// componentes para adaptar su geometría (no solo su color).
///
/// Se inyecta en [ThemeData.extensions] y se lee con
/// `Theme.of(context).extension<LuminaAccessibilityTheme>()!`.
@immutable
class LuminaAccessibilityTheme extends ThemeExtension<LuminaAccessibilityTheme> {
  const LuminaAccessibilityTheme({
    required this.bigButtons,
    required this.pictograms,
    required this.reduceMotion,
    required this.letterSpacing,
    required this.lineHeight,
    required this.fontFamilyOverride,
    required this.contrastOutline,
  });

  /// Área táctil mínima y altura de botones ampliadas.
  final bool bigButtons;

  /// Se dibujan pictogramas grandes junto a cada etiqueta.
  final bool pictograms;

  /// Sin animaciones.
  final bool reduceMotion;

  /// Espaciado entre letras (lo aplica también `accessibility_widget`).
  final double letterSpacing;

  /// Altura de línea (lo aplica también `accessibility_widget`).
  final double lineHeight;

  /// `Andika` cuando el modo dislexia está activo; `null` para la fuente base.
  final String? fontFamilyOverride;

  /// Color de contorno reforzado en modo alto contraste.
  final Color contrastOutline;

  /// Valores neutros (todos los modos apagados).
  static const LuminaAccessibilityTheme neutral = LuminaAccessibilityTheme(
    bigButtons: false,
    pictograms: false,
    reduceMotion: false,
    letterSpacing: 0,
    lineHeight: 0,
    fontFamilyOverride: null,
    contrastOutline: Colors.transparent,
  );

  /// Área táctil efectiva según el modo activo.
  double get minTapTarget => bigButtons
      ? AccessibilityMetricsValues.minTapTarget
      : AccessibilityMetricsValues.defaultTapTarget;

  double get minButtonHeight => bigButtons
      ? AccessibilityMetricsValues.minButtonHeight
      : AccessibilityMetricsValues.defaultButtonHeight;

  double get iconSize => bigButtons
      ? AccessibilityMetricsValues.minIconSize
      : AccessibilityMetricsValues.defaultIconSize;

  double get pictogramSize => AccessibilityMetricsValues.pictogramSize;

  /// Espaciado vertical extra entre controles cuando el modo grande está activo.
  double get controlGap => bigButtons
      ? AppSpacing.md + AppSpacing.bigModeBoost
      : AppSpacing.md;

  Duration resolve(Duration duration) =>
      reduceMotion ? Duration.zero : duration;

  @override
  LuminaAccessibilityTheme copyWith({
    bool? bigButtons,
    bool? pictograms,
    bool? reduceMotion,
    double? letterSpacing,
    double? lineHeight,
    String? fontFamilyOverride,
    Color? contrastOutline,
    bool? dyslexiaFont,
    bool? highContrast,
    bool clearFontFamily = false,
  }) {
    return LuminaAccessibilityTheme(
      bigButtons: bigButtons ?? this.bigButtons,
      pictograms: pictograms ?? this.pictograms,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamilyOverride: clearFontFamily
          ? null
          : (dyslexiaFont == true
              ? AppTheme.dyslexiaFontFamily
              : (fontFamilyOverride ?? this.fontFamilyOverride)),
      contrastOutline: contrastOutline ?? this.contrastOutline,
    );
  }

  @override
  LuminaAccessibilityTheme lerp(
    covariant ThemeExtension<LuminaAccessibilityTheme>? other,
    double t,
  ) {
    if (other is! LuminaAccessibilityTheme) return this;
    return LuminaAccessibilityTheme(
      bigButtons: t < 0.5 ? bigButtons : other.bigButtons,
      pictograms: t < 0.5 ? pictograms : other.pictograms,
      reduceMotion: t < 0.5 ? reduceMotion : other.reduceMotion,
      letterSpacing: lerpDouble(letterSpacing, other.letterSpacing, t),
      lineHeight: lerpDouble(lineHeight, other.lineHeight, t),
      fontFamilyOverride:
          t < 0.5 ? fontFamilyOverride : other.fontFamilyOverride,
      contrastOutline: Color.lerp(contrastOutline, other.contrastOutline, t)!,
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// Duplicado de las métricas como constantes locales para que el
/// [ThemeExtension] no dependa de `accessibility_contract.dart`.
abstract final class AccessibilityMetricsValues {
  static const double minTapTarget = 64;
  static const double defaultTapTarget = 48;
  static const double minButtonHeight = 64;
  static const double defaultButtonHeight = 52;
  static const double minIconSize = 32;
  static const double defaultIconSize = 24;
  static const double pictogramSize = 56;
}

/// Constructor del [ThemeData] de Lumina.
abstract final class AppTheme {
  /// Familia tipográfica base (Inter se resuelve como fuente del sistema si no
  /// está empaquetada; Andika se usa cuando el modo dislexia está activo).
  static const String baseFontFamily = 'Inter';

  /// Nombre de la familia Andika empaquetada en este proyecto.
  static const String dyslexiaFontFamily = 'Andika';

  static ThemeData light({
    required LuminaAccessibilityTheme accessibility,
    bool highContrast = false,
  }) {
    final colorScheme = highContrast
        ? _highContrastLightScheme()
        : _brandLightScheme();
    return _build(
      colorScheme: colorScheme,
      accessibility: accessibility,
      highContrast: highContrast,
    );
  }

  static ThemeData dark({
    required LuminaAccessibilityTheme accessibility,
    bool highContrast = false,
  }) {
    final colorScheme = highContrast
        ? _highContrastDarkScheme()
        : _brandDarkScheme();
    return _build(
      colorScheme: colorScheme,
      accessibility: accessibility,
      highContrast: highContrast,
    );
  }

  // --- Esquemas de color -----------------------------------------------------

  static ColorScheme _brandLightScheme() => ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.blue,
        onPrimary: AppColors.white,
        primaryContainer: AppColors.grey100,
        onPrimaryContainer: AppColors.blueDark,
        secondary: AppColors.purple,
        onSecondary: AppColors.white,
        secondaryContainer: AppColors.grey100,
        onSecondaryContainer: AppColors.purpleDark,
        surface: AppColors.white,
        onSurface: AppColors.grey900,
        surfaceContainerLowest: AppColors.white,
        surfaceContainerLow: AppColors.grey50,
        surfaceContainer: AppColors.grey100,
        outline: AppColors.grey300,
        outlineVariant: AppColors.grey200,
        error: AppColors.error,
      );

  static ColorScheme _brandDarkScheme() => ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppColors.blueLight,
        onPrimary: AppColors.grey900,
        secondary: AppColors.purpleLight,
        onSecondary: AppColors.grey900,
        surface: AppColors.grey900,
        onSurface: AppColors.grey50,
        outline: AppColors.grey600,
      );

  /// Alto contraste claro: texto negro sobre blanco y acentos azul muy oscuro.
  static ColorScheme _highContrastLightScheme() =>
      const ColorScheme.light().copyWith(
        primary: AppColors.hcBlue,
        onPrimary: AppColors.hcWhite,
        secondary: AppColors.hcPurple,
        onSecondary: AppColors.hcWhite,
        surface: AppColors.hcWhite,
        onSurface: AppColors.hcBlack,
        surfaceContainerLowest: AppColors.hcWhite,
        surfaceContainerLow: AppColors.hcWhite,
        surfaceContainer: AppColors.hcWhite,
        outline: AppColors.hcBlack,
        outlineVariant: AppColors.hcBlack,
        error: AppColors.error,
        onError: AppColors.hcWhite,
      );

  /// Alto contraste oscuro: amarillo sobre negro (máxima legibilidad).
  static ColorScheme _highContrastDarkScheme() =>
      const ColorScheme.dark().copyWith(
        primary: AppColors.hcYellow,
        onPrimary: AppColors.hcBlack,
        secondary: AppColors.hcYellow,
        onSecondary: AppColors.hcBlack,
        surface: AppColors.hcBlack,
        onSurface: AppColors.hcWhite,
        surfaceContainerLowest: AppColors.hcBlack,
        surfaceContainerLow: AppColors.hcBlack,
        surfaceContainer: AppColors.hcBlack,
        outline: AppColors.hcWhite,
        outlineVariant: AppColors.hcWhite,
        error: AppColors.hcYellow,
        onError: AppColors.hcBlack,
      );

  // --- Construcción ----------------------------------------------------------

  static ThemeData _build({
    required ColorScheme colorScheme,
    required LuminaAccessibilityTheme accessibility,
    required bool highContrast,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: accessibility.fontFamilyOverride ?? baseFontFamily,
    );

    final textTheme = _textTheme(base.textTheme, accessibility, colorScheme);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,
      visualDensity: accessibility.bigButtons
          ? VisualDensity.comfortable
          : VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[accessibility],
      splashFactory: accessibility.reduceMotion
          ? NoSplash.splashFactory
          : base.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: AppElevation.none,
        scrolledUnderElevation: AppElevation.low,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: AppElevation.low,
        color: colorScheme.surfaceContainerLowest,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: BorderSide(
            color: highContrast ? colorScheme.outline : colorScheme.outlineVariant,
            width: highContrast ? 2 : 1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(
            accessibility.minTapTarget,
            accessibility.minButtonHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(
            accessibility.minTapTarget,
            accessibility.minButtonHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          side: BorderSide(
            color: colorScheme.outline,
            width: highContrast ? 2 : 1,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(accessibility.minTapTarget, accessibility.minTapTarget),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: Size.square(accessibility.minTapTarget),
          iconSize: accessibility.iconSize,
        ),
      ),
      iconTheme: IconThemeData(
        size: accessibility.iconSize,
        color: colorScheme.onSurface,
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: accessibility.bigButtons
            ? AppSpacing.lg
            : AppSpacing.sm,
        iconColor: colorScheme.primary,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: accessibility.bigButtons ? AppSpacing.xl : AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(
            color: highContrast ? colorScheme.outline : colorScheme.outlineVariant,
            width: highContrast ? 2 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        labelStyle: textTheme.bodyLarge,
        helperStyle: textTheme.bodySmall,
      ),
      chipTheme: ChipThemeData(
        labelStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: highContrast ? 2 : 1,
        space: AppSpacing.xl,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: textTheme.bodyLarge?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.buttonRadius,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearMinHeight: accessibility.bigButtons ? 12 : 6,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(colorScheme.onPrimary),
        trackColor: WidgetStatePropertyAll<Color>(colorScheme.primary),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
        ),
        side: BorderSide(color: colorScheme.outline, width: highContrast ? 2 : 1),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.outline;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: accessibility.bigButtons ? 96 : 72,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        indicatorColor: colorScheme.primaryContainer,
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: AppRadius.fieldRadius,
        ),
      ),
    );
  }

  static TextTheme _textTheme(
    TextTheme base,
    LuminaAccessibilityTheme accessibility,
    ColorScheme colorScheme,
  ) {
    // En modo dislexia se aumenta la altura de línea y el espaciado entre
    // letras. `accessibility_widget` vuelve a aplicar sus propios valores
    // encima, pero aquí garantizamos una base coherente en toda la app.
    final double letterSpacing = accessibility.letterSpacing != 0
        ? accessibility.letterSpacing
        : 0.15;
    final double? height = accessibility.lineHeight != 0
        ? accessibility.lineHeight
        : null;

    TextStyle? tune(TextStyle? style) => style?.copyWith(
          letterSpacing: letterSpacing,
          height: height,
          color: colorScheme.onSurface,
        );

    return base.copyWith(
      displayLarge: tune(base.displayLarge),
      displayMedium: tune(base.displayMedium),
      displaySmall: tune(base.displaySmall),
      headlineLarge: tune(base.headlineLarge),
      headlineMedium: tune(base.headlineMedium),
      headlineSmall: tune(base.headlineSmall),
      titleLarge: tune(base.titleLarge),
      titleMedium: tune(base.titleMedium),
      titleSmall: tune(base.titleSmall),
      bodyLarge: tune(base.bodyLarge),
      bodyMedium: tune(base.bodyMedium),
      bodySmall: tune(base.bodySmall),
      labelLarge: tune(base.labelLarge),
      labelMedium: tune(base.labelMedium),
      labelSmall: tune(base.labelSmall),
    );
  }
}
