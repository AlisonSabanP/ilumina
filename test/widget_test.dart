import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/app_theme.dart';
import 'package:lumina/features/accesibilidad/providers/accessibility_provider.dart';
import 'package:lumina/features/formulario/modelos/formulario_modelos.dart';
import 'package:lumina/features/formulario/modelos/formulario_provider.dart';
import 'package:lumina/features/medicion/modelos/measurement_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pruebas de humo de Lumina.
///
/// Cubren lo que puede romperse sin dispositivo físico: el tema, la
/// persistencia de accesibilidad, el árbol de decisión del formulario y el
/// cálculo de medidas. La medición AR, la detección de manos y Meshy necesitan
/// hardware o red, así que se validan a mano (ver README).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AccessibilityProvider', () {
    test('arranca con todos los modos apagados', () {
      final provider = AccessibilityProvider();
      expect(provider.talkBackEnabled, isFalse);
      expect(provider.bigButtonsEnabled, isFalse);
      expect(provider.activeModeCount, 0);
      expect(provider.themeExtension.fontFamilyOverride, isNull);
    });

    test('el modo dislexia activa Andika, altura de línea y espaciado', () {
      final provider = AccessibilityProvider()..setDyslexiaFont(true);
      expect(provider.themeExtension.fontFamilyOverride, 'Andika');
      expect(provider.themeExtension.lineHeight, greaterThan(1));
      expect(provider.themeExtension.letterSpacing, greaterThan(0.5));
    });

    test('el modo botones grandes eleva el área táctil a 64 dp', () {
      final provider = AccessibilityProvider()..setBigButtons(true);
      expect(provider.themeExtension.minTapTarget, 64);
      expect(provider.themeExtension.minButtonHeight, 64);
    });

    test('los perfiles activan varios modos a la vez', () {
      final provider = AccessibilityProvider()
        ..applyPreset(AccessibilityPreset.cognitiva);
      expect(provider.pictogramsEnabled, isTrue);
      expect(provider.dyslexiaFontEnabled, isTrue);
      expect(provider.reduceMotionEnabled, isTrue);
    });

    test('persiste y restaura los modos', () async {
      final first = AccessibilityProvider()..setHighContrast(true);
      await Future<void>.delayed(Duration.zero);

      final second = AccessibilityProvider();
      await second.restore();
      expect(second.highContrastEnabled, isTrue);
      expect(first.highContrastEnabled, isTrue);
    });
  });

  group('AppTheme', () {
    testWidgets('expone LuminaAccessibilityTheme en el ThemeData',
        (tester) async {
      late LuminaAccessibilityTheme extension;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(
            accessibility: LuminaAccessibilityTheme.neutral,
          ),
          home: Builder(
            builder: (context) {
              extension =
                  Theme.of(context).extension<LuminaAccessibilityTheme>()!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(extension.bigButtons, isFalse);
      expect(extension.minTapTarget, 48);
    });

    testWidgets('el alto contraste cambia el esquema de color',
        (tester) async {
      final normal = AppTheme.light(
        accessibility: LuminaAccessibilityTheme.neutral,
      );
      final contrast = AppTheme.light(
        accessibility: LuminaAccessibilityTheme.neutral,
        highContrast: true,
      );
      expect(
        contrast.colorScheme.onSurface,
        isNot(normal.colorScheme.onSurface),
      );
    });
  });

  group('FormularioProvider', () {
    test('la rama motriz lleva a una recomendación terminal', () {
      final form = FormularioProvider()
        ..selectProfile(NeedProfile.motriz)
        ..answer('m_tool')
        ..answer('m_tool_screwdriver');

      expect(form.finished, isTrue);
      expect(form.canGenerate, isTrue);
      expect(form.recommendation!.id, 'progrip_destornillador');
      expect(form.promptFragments, isNotEmpty);
    });

    test('volver atrás conserva las respuestas dadas', () {
      final form = FormularioProvider()
        ..selectProfile(NeedProfile.motriz)
        ..answer('m_tool');
      final answered = form.answerLabel('m_need');
      form.goBack();
      expect(form.currentQuestionId, 'm_need');
      expect(form.answerLabel('m_need'), answered);
    });

    test('las medidas se sustituyen si comparten etiqueta', () {
      final form = FormularioProvider()
        ..upsertMeasurement(_measurement('Diámetro', 4))
        ..upsertMeasurement(_measurement('Diámetro', 5));
      expect(form.measurements, hasLength(1));
      expect(form.measurements.single.valueCm, 5);
    });
  });

  group('HandMetrics', () {
    test('sin calibración devuelve unidades relativas', () {
      final metrics = HandMetrics.fromLandmarks(
        _openHand(),
        frameWidth: 720,
        frameHeight: 1280,
      );
      expect(metrics.isCalibrated, isFalse);
      expect(metrics.unitLabel, 'u.r.');
      expect(metrics.confidence, 1);
    });

    test('con calibración devuelve centímetros coherentes', () {
      final metrics = HandMetrics.fromLandmarks(
        _openHand(),
        frameWidth: 720,
        frameHeight: 1280,
        referencePalmWidthCm: 8.5,
      );
      expect(metrics.isCalibrated, isTrue);
      expect(metrics.unitLabel, 'cm');
      // La palma se ha calibrado a 8,5 cm exactos.
      expect(metrics.palmWidth, closeTo(8.5, 0.001));
      expect(metrics.handSpan, greaterThan(metrics.palmWidth));
    });

    test('exige 21 landmarks', () {
      expect(
        () => HandMetrics.fromLandmarks(
          const <HandPoint>[HandPoint(0, 0, 0)],
          frameWidth: 720,
          frameHeight: 1280,
        ),
        throwsArgumentError,
      );
    });
  });
}

Measurement _measurement(String label, double valueCm) => Measurement(
      id: 'test_$label$valueCm',
      label: label,
      valueCm: valueCm,
      kind: MeasurementKind.manualDiameter,
      source: MeasurementSource.manual,
      timestamp: DateTime(2026, 1, 1),
    );

/// Mano abierta sintética: los 21 puntos repartidos de forma realista.
List<HandPoint> _openHand() => const <HandPoint>[
      HandPoint(0.50, 0.80, 0.00), // 0 muñeca
      HandPoint(0.44, 0.76, -0.01),
      HandPoint(0.39, 0.70, -0.02),
      HandPoint(0.35, 0.64, -0.03),
      HandPoint(0.31, 0.58, -0.04), // 4 punta del pulgar
      HandPoint(0.47, 0.60, -0.01),
      HandPoint(0.45, 0.50, -0.01),
      HandPoint(0.44, 0.44, -0.01),
      HandPoint(0.43, 0.38, -0.01), // 8 punta del índice
      HandPoint(0.52, 0.59, -0.01),
      HandPoint(0.52, 0.48, -0.01),
      HandPoint(0.52, 0.41, -0.01),
      HandPoint(0.52, 0.34, -0.01), // 12 punta del corazón
      HandPoint(0.57, 0.60, -0.01),
      HandPoint(0.58, 0.50, -0.01),
      HandPoint(0.59, 0.44, -0.01),
      HandPoint(0.60, 0.39, -0.01), // 16 punta del anular
      HandPoint(0.62, 0.62, -0.01),
      HandPoint(0.64, 0.54, -0.01),
      HandPoint(0.66, 0.49, -0.01),
      HandPoint(0.68, 0.45, -0.01), // 20 punta del meñique
    ];
