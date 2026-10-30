import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/app_theme.dart';
import 'package:lumina/shared/servicios/braille_service.dart';
import 'package:lumina/features/accesibilidad/providers/accessibility_provider.dart';
import 'package:lumina/features/formulario/modelos/formulario_modelos.dart';
import 'package:lumina/features/formulario/modelos/formulario_provider.dart';
import 'package:lumina/features/formulario/pantallas/braille_screen.dart';
import 'package:lumina/features/generacion3d/providers/generation_provider.dart';
import 'package:lumina/features/visor3d/pantallas/visor_modelo_screen.dart';
import 'package:lumina/features/visor3d/servicios/model_download_service.dart';
import 'package:provider/provider.dart';
import 'package:braille_text/braille_text.dart';
import 'package:lumina/features/generacion3d/servicios/local_generator_service.dart';
import 'package:lumina/features/generacion3d/servicios/prompt_builder_service.dart';
import 'package:lumina/features/medicion/modelos/measurement_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Pruebas de humo de Lumina.
///
/// Cubren lo que puede romperse sin dispositivo físico: el tema, la
/// persistencia de accesibilidad, el árbol de decisión del formulario y el
/// cálculo de medidas. La detección de manos y Meshy necesitan hardware o red,
/// así que se validan a mano (ver README).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _mockPathProvider();
  });

  group('BrailleScreen', () {
    testWidgets('la etiqueta se puede crear y abre el visor', (tester) async {
      // Es el flujo que se reportó como roto: al elegir el perfil visual, la
      // pantalla de Braille debe dejar crear la pieza imprimible.
      final form = FormularioProvider()
        ..selectProfile(NeedProfile.visual)
        ..answer('v_braille')
        ..setBrailleText('Leche');
      final generation = GenerationProvider();
      final a11y = AccessibilityProvider();

      // Pantalla alta: la pantalla de Braille es una lista larga y así se
      // evita depender del desplazamiento para llegar al botón.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<FormularioProvider>.value(value: form),
            ChangeNotifierProvider<GenerationProvider>.value(value: generation),
            ChangeNotifierProvider<AccessibilityProvider>.value(value: a11y),
          ],
          child: MaterialApp(
            theme: AppTheme.light(accessibility: a11y.themeExtension),
            home: const BrailleScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La vista previa del Braille se dibuja con el texto ya normalizado.
      expect(find.byType(BrailleText), findsOneWidget);

      final createButton = find.text('Crear la etiqueta para imprimir');
      expect(createButton, findsOneWidget);
      // `runAsync` es necesario porque la generación local escribe ficheros de
      // verdad y el resto del test corre con temporizadores simulados.
      await tester.runAsync(() async {
        await tester.tap(createButton);
        for (var i = 0; i < 100; i++) {
          if (generation.phase == GenerationPhase.succeeded) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      // El visor monta un WebView que nunca queda "quieto", así que no se usa
      // `pumpAndSettle`: basta con dejar pasar unos fotogramas.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Se generó una pieza local real y el visor la muestra.
      expect(generation.phase, GenerationPhase.succeeded);
      expect(generation.model!.isLocal, isTrue);
      expect(File(generation.model!.stlPath!).existsSync(), isTrue);
      expect(find.byType(VisorModeloScreen), findsOneWidget);
      generation.dispose();
    });
  });

  group('AccessibilityProvider', () {
    test('arranca con todos los modos apagados', () {
      final provider = AccessibilityProvider();
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
      expect(form.recommendation!.id, 'grip_destornillador');
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
    test('sin calibrar estima centímetros con el ancho de palma medio', () {
      final metrics = HandMetrics.fromLandmarks(
        _openHand(),
        frameWidth: 720,
        frameHeight: 1280,
      );
      // Los valores salen en centímetros, pero marcados como estimación, para
      // que nunca aparezcan medidas de un orden de magnitud absurdo.
      expect(metrics.isCalibrated, isTrue);
      expect(metrics.isEstimated, isTrue);
      expect(metrics.unitLabel, 'cm');
      expect(metrics.confidence, 1);
      // Con el ancho de palma medio, la palma mide exactamente ese valor.
      expect(
        metrics.palmWidth,
        closeTo(HandMetrics.defaultReferencePalmWidthCm, 0.001),
      );
      // Y la mano completa, un valor humano plausible.
      expect(metrics.handSpan, greaterThan(10));
      expect(metrics.handSpan, lessThan(30));
    });

    test('con calibración devuelve centímetros coherentes', () {
      final metrics = HandMetrics.fromLandmarks(
        _openHand(),
        frameWidth: 720,
        frameHeight: 1280,
        referencePalmWidthCm: 8.5,
      );
      expect(metrics.isCalibrated, isTrue);
      expect(metrics.isEstimated, isFalse);
      expect(metrics.unitLabel, 'cm');
      // La palma se ha calibrado a 8,5 cm exactos.
      expect(metrics.palmWidth, closeTo(8.5, 0.001));
      expect(metrics.handSpan, greaterThan(metrics.palmWidth));
    });

    test('con calibración la medida no depende de la resolución del fotograma',
        () {
      // Propiedad clave del arreglo: al calibrar con el ancho de palma, la
      // medida en centímetros es invariante a la resolución del fotograma. Si
      // se pasan las dimensiones equivocadas (el `previewSize` en lugar del
      // tamaño real de la imagen), la relación de aspecto cambia y el valor
      // sale desviado; con el fotograma correcto, no.
      final small = HandMetrics.fromLandmarks(
        _openHand(),
        frameWidth: 640,
        frameHeight: 480,
        referencePalmWidthCm: 8.5,
      );
      final large = HandMetrics.fromLandmarks(
        _openHand(),
        frameWidth: 1280,
        frameHeight: 960,
        referencePalmWidthCm: 8.5,
      );
      expect(small.palmWidth, closeTo(8.5, 0.001));
      expect(large.palmWidth, closeTo(8.5, 0.001));
      // Misma proporción de fotograma => mismo resultado en centímetros.
      expect(small.handSpan, closeTo(large.handSpan, 0.001));
    });

    test('una proporción de fotograma equivocada desvía la medida', () {
      // Esto es lo que ocurría al usar `previewSize`: la proporción no era la
      // del fotograma analizado y las distancias salían mal.
      final correct = HandMetrics.fromLandmarks(
        _openHand(),
        frameWidth: 640,
        frameHeight: 480,
        referencePalmWidthCm: 8.5,
      );
      final distorted = HandMetrics.fromLandmarks(
        _openHand(),
        frameWidth: 720,
        frameHeight: 1280,
        referencePalmWidthCm: 8.5,
      );
      expect(
        (distorted.handSpan - correct.handSpan).abs(),
        greaterThan(1),
      );
    });

    test('rechaza un tamaño de fotograma no positivo', () {
      expect(
        () => HandMetrics.fromLandmarks(
          _openHand(),
          frameWidth: 0,
          frameHeight: 1280,
        ),
        throwsArgumentError,
      );
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

  group('LocalGeneratorService', () {
    // La generación local es la vía gratuita: construye geometría real y la
    // exporta a STL. Estas pruebas comprueban el contenido binario, no solo
    // que el método devuelva algo.
    test('la placa Braille produce un STL binario válido', () {
      final mesh = const LocalGeneratorService().braillePlate('lumina');
      expect(mesh.triangleCount, greaterThan(100));
      expect(mesh.stl.length, 84 + mesh.triangleCount * 50);

      // Cabecera del formato: contador de triángulos en little endian.
      final view = ByteData.sublistView(mesh.stl);
      expect(view.getUint32(80, Endian.little), mesh.triangleCount);
    });

    test('el STL usa el texto normalizado y crece con la etiqueta', () {
      const service = LocalGeneratorService();
      final short = service.braillePlate('pan');
      final long = service.braillePlate('pan integral de centeno');
      // Más texto ocupa más celdas y, por tanto, más puntos en relieve.
      expect(long.triangleCount, greaterThan(short.triangleCount));

      // La normalización quita tildes: "café" y "cafe" deben dar lo mismo.
      expect(
        service.braillePlate('café').triangleCount,
        service.braillePlate('cafe').triangleCount,
      );
    });

    test('el GLB generado es un contenedor glTF 2.0 bien formado', () {
      final mesh = const LocalGeneratorService().braillePlate('lumina');
      final view = ByteData.sublistView(mesh.glb);

      expect(view.getUint32(0, Endian.little), 0x46546C67); // "glTF"
      expect(view.getUint32(4, Endian.little), 2);
      expect(view.getUint32(8, Endian.little), mesh.glb.length);

      final jsonLength = view.getUint32(12, Endian.little);
      expect(view.getUint32(16, Endian.little), 0x4E4F534A); // "JSON"
      final jsonText = utf8.decode(mesh.glb.sublist(20, 20 + jsonLength));
      expect(jsonText, contains('"version":"2.0"'));

      final binHeader = 20 + jsonLength;
      expect(view.getUint32(binHeader + 4, Endian.little), 0x004E4942);
    });

    test('el GLB sale Y-arriba: una pieza alta no se tumba', () {
      // Regresión: las piezas se construyen Z-arriba y glTF es Y-arriba. Sin la
      // conversión de ejes, el engrosador (alto y estrecho) llegaba al visor
      // tumbado, y de frente se veía como un círculo.
      final mesh = const LocalGeneratorService().gripSleeve(
        measurements: <Measurement>[_measurement('Diámetro del objeto', 4.0)],
      );
      final view = ByteData.sublistView(mesh.glb);
      final jsonLength = view.getUint32(12, Endian.little);
      final json = jsonDecode(
        utf8.decode(mesh.glb.sublist(20, 20 + jsonLength)),
      ) as Map<String, dynamic>;
      final accessors = json['accessors'] as List<dynamic>;
      final min = (accessors[0] as Map<String, dynamic>)['min'] as List<dynamic>;
      final max = (accessors[0] as Map<String, dynamic>)['max'] as List<dynamic>;
      final widthX = (max[0] as num) - (min[0] as num);
      final heightY = (max[1] as num) - (min[1] as num);
      final depthZ = (max[2] as num) - (min[2] as num);

      // La altura es el largo del manguito (70 mm) y supera el diámetro (~31 mm).
      expect(heightY, greaterThan(widthX));
      expect(heightY, greaterThan(depthZ));
    });

    test('el engrosador respeta el diámetro medido más la holgura', () {
      final mesh = const LocalGeneratorService().gripSleeve(
        measurements: <Measurement>[_measurement('Diámetro del objeto', 4.0)],
      );
      // 4 cm de objeto + 0,4 mm de holgura a cada lado del agujero.
      expect(mesh.dimensionsMm['diámetro del agujero'], closeTo(40.8, 0.01));
      expect(mesh.kind, LocalPieceKind.gripSleeve);
    });

    test('sin medidas avisa de que ha usado valores estándar', () {
      final mesh = const LocalGeneratorService().gripSleeve(
        measurements: const <Measurement>[],
      );
      expect(
        mesh.notes.any((n) => n.contains('No se tomó el diámetro')),
        isTrue,
      );
    });
  });

  group('GenerationProvider', () {
    test('sin clave propia arranca en modo demostración, sin red', () {
      final provider = GenerationProvider();
      expect(provider.isDemoMode, isTrue);
      expect(provider.isMeshyMode, isFalse);
      expect(provider.hasModel, isFalse);
    });

    test('la demostración muestra la pieza de ejemplo empaquetada', () async {
      // Sin clave de Meshy no se llama a la API: se enseña el cubo incluido en
      // la app para poder probar el flujo completo.
      final provider = GenerationProvider();
      final form = FormularioProvider()
        ..selectProfile(NeedProfile.motriz)
        ..answer('m_tool')
        ..answer('m_tool_screwdriver');

      await provider.generateFromFormulario(form);

      expect(provider.phase, GenerationPhase.succeeded);
      expect(provider.hasModel, isTrue);
      expect(provider.model!.isDemo, isTrue);
      expect(provider.model!.isLocalAsset, isTrue);
      expect(provider.model!.assetPath, GenerationProvider.demoAssetPath);
      expect(provider.history, hasLength(1));
      provider.dispose();
    });

    test('el perfil visual genera una etiqueta Braille imprimible', () async {
      // Es el caso que el usuario reportó: al elegir el perfil visual, la app
      // debe dejar crear la etiqueta. Se recorre la rama real del formulario.
      final form = FormularioProvider()..selectProfile(NeedProfile.visual);
      form.answer('v_braille');
      expect(form.recommendation?.id, 'braille_label');
      expect(form.brailleLabel, isNotEmpty);

      final provider = GenerationProvider();
      await provider.generateBrailleLabel(form.brailleLabel);

      expect(provider.phase, GenerationPhase.succeeded);
      expect(provider.model!.isLocal, isTrue);
      // El STL se escribe en disco y tiene contenido real.
      final stl = File(provider.model!.stlPath!);
      expect(stl.existsSync(), isTrue);
      expect(stl.lengthSync(), greaterThan(1000));
      provider.dispose();
    });

    test('la etiqueta Braille se crea solo si se pide', () async {
      final provider = GenerationProvider();
      await provider.generateBrailleLabel('medicinas');

      expect(provider.phase, GenerationPhase.succeeded);
      expect(provider.model!.title, 'Etiqueta Braille');
      expect(provider.model!.pieceSummary, contains('medicinas'));
      provider.dispose();
    });

    test('la etiqueta Braille no se graba en la pieza principal', () {
      // La etiqueta es una pieza aparte: no debe aparecer en el prompt de la
      // pieza de agarre ni colarse en su geometría.
      final form = FormularioProvider()
        ..selectProfile(NeedProfile.motriz)
        ..answer('m_tool')
        ..answer('m_tool_screwdriver');
      final built = const PromptBuilderService().fromFormulario(form);
      expect(built.prompt.toLowerCase(), isNot(contains('braille')));
    });
  });

  group('Pieza de demostración (cubo)', () {
    testWidgets('el visor abre la pieza de ejemplo empaquetada', (tester) async {
      // Sin clave de Meshy la app muestra el cubo incluido en la app. Este test
      // comprueba que el visor lo carga con `Power3D.fromAsset` y que no se
      // queda en el estado de error.
      final generation = GenerationProvider();
      final a11y = AccessibilityProvider();
      addTearDown(generation.dispose);

      final form = FormularioProvider()
        ..selectProfile(NeedProfile.motriz)
        ..answer('m_tool')
        ..answer('m_tool_screwdriver');

      await tester.runAsync(() async {
        await generation.generateFromFormulario(form);
      });
      expect(generation.model!.isDemo, isTrue);
      expect(generation.model!.assetPath, GenerationProvider.demoAssetPath);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GenerationProvider>.value(value: generation),
            ChangeNotifierProvider<AccessibilityProvider>.value(value: a11y),
          ],
          child: MaterialApp(
            theme: AppTheme.light(accessibility: a11y.themeExtension),
            home: VisorModeloScreen(model: generation.model!),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(VisorModeloScreen), findsOneWidget);
      // La pieza de ejemplo no se puede "descargar" del dispositivo: el botón
      // sigue existiendo y exporta el asset.
      expect(find.text('Descargar STL'), findsOneWidget);
    });

    test('el asset del cubo se empaqueta y se puede exportar a disco', () async {
      // `exportAsset` es lo que hace el botón de descarga en modo demo: copia el
      // `.glb` de la app al almacenamiento del dispositivo.
      final service = ModelDownloadService();
      final path = await service.exportAsset(
        assetPath: GenerationProvider.demoAssetPath,
        id: 'demo_test',
        title: 'Pieza de ejemplo',
      );
      final file = File(path);
      expect(file.existsSync(), isTrue);
      // El cubo real pesa más de un kilobyte: comprueba que no se copió vacío.
      expect(file.lengthSync(), greaterThan(1000));
      // Y sigue siendo un contenedor glTF válido.
      final bytes = file.readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'glTF');
    });
  });

  group('BrailleService', () {
    test('quita tildes y mayúsculas que el conversor perdería', () {
      // `BrailleConverter` convierte a espacio todo lo que no esté en su tabla:
      // sin normalizar, "Muñeca" saldría como "mu eca".
      expect(BrailleService.normalize('Muñeca izquierda'), 'muneca izquierda');
      expect(BrailleService.normalize('Diámetro'), 'diametro');
      expect(BrailleService.normalize('Férula nº 3'), 'ferula n 3');
    });

    test('genera Braille Unicode sin huecos', () {
      final braille = BrailleService.toBraille('Muñeca');
      expect(braille, isNotEmpty);
      // Ningún carácter debe quedar como espacio en medio de la palabra.
      expect(braille.trim(), braille);
      expect(braille.contains(' '), isFalse);
    });

    test('recorta etiquetas largas por palabra completa', () {
      final label = BrailleService.prepareLabel(
        'Adaptador ergonomico para destornillador de precision',
      );
      expect(label.length, lessThanOrEqualTo(BrailleService.maxLabelLength));
      // No debe cortar una palabra por la mitad.
      expect(label.endsWith('de'), isFalse);
    });

    test('la etiqueta sugerida sale del título de la recomendación', () {
      expect(
        BrailleService.labelFromTitle('Adaptador para sierra'),
        'adaptador para sierra',
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

/// Simula `path_provider` para las pruebas.
///
/// Las piezas locales se escriben en el directorio de documentos de la app, y
/// ese plugin no tiene implementación en el entorno de pruebas: sin este doble,
/// cualquier test que genere una pieza fallaría con `MissingPluginException` en
/// lugar de comprobar la geometría. Se apunta a una carpeta temporal real, así
/// que los archivos se escriben de verdad y se pueden leer.
void _mockPathProvider() {
  final directory = Directory.systemTemp.createTempSync('lumina_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
        case 'getApplicationSupportDirectory':
          return directory.path;
        default:
          return null;
      }
    },
  );
}

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
