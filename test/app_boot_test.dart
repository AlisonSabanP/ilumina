import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/app/app.dart';
import 'package:lumina/core/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Arranque real de la aplicación.
///
/// Las demás pruebas montan pantallas sueltas con providers a mano. Esta monta
/// `LuminaRoot` entero —`MultiProvider`, `AccessibilityWidget` del paquete
/// WCAG, tema, `HomeScreen`— para detectar errores de cableado que solo
/// aparecen al construir el árbol completo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('la app arranca y muestra la pantalla de inicio', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LuminaRoot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Lumina'), findsWidgets);
    expect(find.byType(Scaffold), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el panel de accesibilidad se abre y aplica un modo', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LuminaRoot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // La pantalla de inicio ofrece el panel con un botón explícito.
    await tester.tap(find.text('Abrir el panel de accesibilidad'));
    await tester.pumpAndSettle();

    expect(find.text('Accesibilidad'), findsWidgets);
    expect(find.text('Modos de Lumina'), findsOneWidget);

    // Activar "Botones grandes" desde el panel debe cambiar el tema de la app.
    // El interruptor conmuta el modo; la etiqueta es solo texto.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    final extension = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .extension<LuminaAccessibilityTheme>();
    expect(extension?.bigButtons, isTrue);
    expect(extension?.minTapTarget, 64);
  });

  testWidgets('el formulario recorre la rama motriz hasta la recomendación',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LuminaRoot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Formulario inteligente').first);
    await tester.pumpAndSettle();

    // Perfil -> herramienta -> destornillador.
    await tester.tap(find.text('Motriz').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adaptador para una herramienta').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destornillador').first);
    await tester.pumpAndSettle();

    expect(find.text('Tu recomendación'), findsOneWidget);
    expect(find.text('Generar modelo 3D'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
