# Lumina — notas para agentes

App Flutter de impresión 3D accesible. La documentación de producto (guía de
uso, tabla técnica, limitaciones) está en `README.md`; esto es lo que hace falta
saber para trabajar en el código sin romperlo.

## Comandos

```bash
flutter pub get
flutter analyze          # debe quedar en "No issues found!"
flutter test             # 35 pruebas, todas deben pasar
flutter build apk --debug
flutter build apk --release   # ~5 min; R8 tarda
```

`test/app_boot_test.dart` monta `LuminaRoot` entero (providers + panel +
formulario) y es el que detecta roturas de cableado; `test/widget_test.dart`
prueba unidades y pantallas sueltas.

Para probar en un móvil concreto, compila solo su arquitectura: el APK de debug
pasa de ~203 MiB a ~133 MiB y evita los fallos de instalación por falta de
espacio.

```bash
flutter run --target-platform android-arm64
```

Android necesita JDK 17 o superior, Android SDK 36 y NDK 28.2.13676358.
`android/gradle.properties` usa `-Xmx4G`: subirlo provoca que el runtime se
quede sin memoria al compilar MediaPipe junto con el WebView de `power3d`.

## Arquitectura

- **Estado:** `provider` con tres `ChangeNotifier` en `lib/app/app.dart`
  (`AccessibilityProvider`, `FormularioProvider`, `GenerationProvider`). No se
  usa Riverpod a propósito.
- **Aislamiento por feature:** cada módulo vive en `lib/features/<nombre>/` con
  `modelos/`, `pantallas/`, `providers/`, `servicios/`, `widgets/` según haga
  falta. Nada de un módulo importa pantallas de otro salvo por navegación.
- **Frontera con paquetes frágiles:** los paquetes con API inestable o
  específicos de plataforma se envuelven en un adaptador para que sus tipos no
  lleguen a la UI. Ejemplos: `hand_detector.dart` (envuelve
  `hand_landmarker`), `meshy_service.dart` (envuelve la API REST).
- **Accesibilidad:** `AccessibilityProvider` es la fuente de verdad. Se
  sincroniza en dos direcciones con `accessibility_widget` en
  `_AccessibilitySync` (`lib/app/app.dart`) y en el panel
  (`lib/features/accesibilidad/pantallas/panel_accesibilidad_screen.dart`). Si
  tocas uno, revisa el otro: el flag `_syncing` existe para evitar bucles.

## Generación 3D: local por defecto, Meshy opcional

**La vía por defecto no usa ninguna API.** `LocalGeneratorService`
(`lib/features/generacion3d/servicios/local_generator_service.dart`) construye
geometría paramétrica real con `MeshBuilder`
(`lib/shared/servicios/stl_builder.dart`) y la exporta a **STL binario** (para
el laminador) y a **GLB** (para el visor). Cuesta cero, funciona sin conexión y
produce un archivo imprimible de verdad.

Meshy solo se usa si hay una clave propia configurada (`Env.isMeshyTestMode` es
`false`). Esto no es una preferencia estética: **Meshy no tiene modo de prueba
gratuito** y responde `401` a cualquier clave que no sea de una cuenta real, así
que sin clave propia la app funcionaría siempre con error.

- La vía local mantiene las mismas fases (`creating` → `polling` →
  `succeeded`) que la remota para que la UI no tenga dos caminos.
- Las piezas locales se escriben en `lumina_piezas/` del directorio de
  documentos; las de Meshy en `lumina_models/`.
- `GeneratedModel.isLocal` distingue unas de otras.

## El Braille necesita una fuente propia

`braille_text` dibuja con `fontFamily: 'Braille'`, **pero el paquete no
empaqueta ninguna fuente con ese nombre**: sin declararla, el Braille se ve como
cuadros vacíos. `pubspec.yaml` registra `assets/fonts/BraillePoints.ttf`
(DejaVu Sans, que cubre los 256 caracteres de U+2800–U+28FF) con la familia
`Braille` justamente para eso. No la quites.

Además, `BrailleService.normalize` vacía el texto que no sabe representar: si
la normalización deja la cadena vacía, la vista previa **no** debe llamar a
`BrailleText` con ese texto vacío (era el fallo original: parecía que la
etiqueta "no funcionaba"). `braille_screen.dart` comprueba
`_hasPrintableLabel` antes de dibujar.

## Las piezas se construyen Z-arriba y el GLB sale Y-arriba

`MeshBuilder` construye con el eje **Z** como altura (`addTubeZ`, `addBox` con
`z0`/`z1`), pero glTF —y por tanto `power3d`— es **Y-arriba**. `toGlb()` hace la
conversión de ejes al escribir posiciones y normales. Si se quita, las piezas
altas y estrechas (el engrosador) llegan al visor tumbadas y de frente se ven
como un **círculo**. Hay una prueba de regresión: "el GLB sale Y-arriba".

## Las piezas deben ser un solo sólido

Las piezas paramétricas se montan por unión de volúmenes, y **cada volumen tiene
que solaparse con el que toca**: si dos volúmenes solo se tocan en una arista o
cara, el laminador ve dos sólidos sueltos. Por eso el garfio del engrosador
arranca en `outerRadius - 1.5` (dentro de la pared) y el apoyo de palma llega
hasta `-innerRadius` (atraviesa el tubo), en lugar de apoyarse en el exterior.

## La etiqueta Braille es una pieza aparte

La etiqueta **nunca se graba sobre otra pieza**. Se construye en dos sitios, y
los dos producen la misma placa suelta:

- `LocalGeneratorService.fromFormulario` la devuelve cuando la recomendación es
  `brailleLabelRecommendationId` (rama visual del formulario).
- `GenerationProvider.generateBrailleLabel` la construye a petición desde
  `braille_screen.dart`.

`FormularioProvider.brailleLabel` es solo el texto sugerido. No enganches la
etiqueta a la generación de una pieza de agarre: eso era el comportamiento
antiguo.

## El material de impresión no se elige

Se retiró el selector de material (PETG/PLA/TPU/ASA) del formulario y el campo
`material` de `GeneratedModel`. El usuario final no debe decidir el filamento:
el laminador lo hace por él. No lo reintroduzcas en el formulario ni en el
prompt.

## El lector de pantalla no es un interruptor de la app

No existe (ni debe existir) un `setTalkBack`: TalkBack y VoiceOver son lectores
del sistema y solo se activan desde los ajustes del móvil. Lo que Lumina
garantiza es que todos sus widgets tengan `Semantics` correctos. **No se le
dedica una tarjeta informativa en el panel**: se retiró a petición del usuario,
que no quiere ver TalkBack en la información de accesibilidad de la app. No
reintroduzcas ni la tarjeta ni un interruptor que no puede cumplir lo que
promete.

## El panel de accesibilidad está en español a propósito

`accessibility_widget` trae su panel con los textos fijos en inglés ("Text
Size", "Dyslexia Friendly Font"...). Lumina **no** usa su
`AccessibilityPanelContent`: dibuja los controles en
`panel_accesibilidad_screen.dart` y sigue usando solo el
`AccessibilityController` del paquete, que es donde vive la lógica y la
persistencia. Si añades un control nuevo, hazlo ahí, no con el widget del
paquete.

## La medición AR se retiró

`neom_ar`, `arkit_plugin` y `arcore_flutter_plugin` **ya no son dependencias**.
La medición AR no funcionaba de forma fiable y su fork de ARCore era la causa de
la mayor parte de la fragilidad del build. Quedan dos vías: detección de manos
(solo Android) y medida a mano. `MeasurementSource` ya no tiene el valor `ar`;
los datos antiguos se leen como `manual` por el `orElse` de
`Measurement.fromJson`.

## El único fork de `third_party/`

- `third_party/flutter_inappwebview_android` — `getDefaultProguardFile
  ('proguard-android.txt')` es rechazado por Gradle 9. Solo se cambia a
  `proguard-android-optimize.txt`. Se declara en `dependency_overrides`.

`analysis_options.yaml` excluye `third_party/**` del análisis; el fork tiene su
propio `analysis_options.yaml` relajado. No añadas lints ahí.

## Trampa de configuración nativa

| Ajuste | Dónde | Sin él |
| --- | --- | --- |
| `android.newDsl=false` | `android/gradle.properties` | El plugin de Flutter no aplica el DSL clásico |

## No pongas `ndk { abiFilters }` en `build.gradle.kts`

Hubo uno y se quitó. Hacía daño de dos formas:

1. **No limitaba nada.** El plugin Gradle de Flutter sobrescribe
   `ndk.abiFilters` con las ABI que se le piden compilar, así que el APK seguía
   incluyendo `x86_64`. Verificado en los artefactos:

   | Artefacto | Tamaño | ABI incluidas |
   | --- | --- | --- |
   | `app-debug.apk` | 202.8 MiB | arm64-v8a, armeabi-v7a, **x86_64** |
   | `app-release.apk` | 97.2 MiB | arm64-v8a, armeabi-v7a, **x86_64** |

2. **Rompe `--split-per-abi`.** Gradle aborta con:

   ```
   Conflicting configuration : 'armeabi-v7a,arm64-v8a' in ndk abiFilters
   cannot be present when splits abi filters are set
   ```

   Es decir, el bloque impedía justamente la orden que sirve para reducir el
   tamaño. No admite las dos configuraciones a la vez.

La forma correcta de elegir arquitecturas es la línea de comandos:

```bash
flutter build apk --release --split-per-abi    # un APK por ABI (arm64 ~42 MiB)
flutter run --target-platform android-arm64    # un solo APK (~133 MiB debug)
```

Un APK de debug de ~203 MiB es además la causa más común de
`adb: failed to install` (falta de espacio en el móvil). Ver los errores
probables del README.

## Al tocar el servicio de Meshy

`lib/features/generacion3d/servicios/meshy_service.dart` tiene dos invariantes
que no son evidentes y que **no se deben "arreglar"**:

1. **El `POST` nunca se reintenta.** Meshy no tiene clave de idempotencia: un
   segundo envío tras un timeout crea y cobra una segunda tarea. Solo se
   reintenta el `GET` de sondeo.
2. **Si se agota el tiempo de espera, la tarea sigue viva.** Se devuelve el
   último estado conocido con `MeshyErrorKind.timeout`, no un fallo, para que
   el usuario pueda volver a consultarla con su `task_id`.

El prompt se compone por capas en `prompt_builder_service.dart` y se recorta a
800 caracteres (límite de Meshy) avisando con `PromptBuildResult.wasTrimmed`.

## El `.env` se versiona a propósito

`pubspec.yaml` declara `.env` como asset porque `flutter_dotenv` lo lee del
bundle en el dispositivo. Si el fichero no existe, `flutter build` falla con
`No file or variants found for asset: .env`. Por eso `.env` está **fuera** de
`.gitignore`. La clave real va siempre por `--dart-define=MESHY_API_KEY=...`,
que tiene prioridad (ver `lib/core/env.dart`). No metas una clave real en el
`.env` del repositorio.

## Meshy no tiene modo de prueba

El valor `msy_dummy_api_key_for_test_mode_12345678` del `.env` **no es una
clave válida**: Meshy responde `401 Invalid API key` a cualquier clave que no
sea de una cuenta real. Se usa solo como centinela para detectar "no hay clave
configurada", y en ese caso la app genera en el dispositivo (ver arriba). No
inventes un "modo de prueba" de Meshy que devuelva modelos: no existe.

## Marcadores `[VERIFICAR]`

El proyecto no tiene ninguno pendiente en el código. Lo que **sí** requiere
hardware real y no se puede comprobar con `flutter test`:

- La detección de manos (`hand_landmarker` + `CameraController`): necesita un
  dispositivo Android con cámara.
- La carga del `.glb` en `power3d`: necesita el WebView de un dispositivo o
  emulador; en `flutter test` no se puede montar.
- El trazo del Braille en pantalla: la fuente ya está declarada y los tests
  cubren la conversión, pero el render final conviene verlo en el móvil.

## Verificado en este entorno (no lo repitas a ciegas)

`flutter analyze` (`No issues found!`), `flutter test` (35/35) y las cuatro
compilaciones de Android (`--debug`, `--release`, `--release --split-per-abi`,
`--debug --target-platform android-arm64`) están **ejecutadas**, no estimadas.
Requiere JDK 17 o superior: AGP 9 no arranca con JDK 11 y en Debian 13 solo hay
`openjdk-21-jdk-headless` en apt, así que compilando con Java 21 a bytecode 17
(`sourceCompatibility`/`jvmTarget` siguen en `VERSION_17`).

El primer `flutter build apk` en una máquina limpia tarda mucho más de lo que
sugiere el README: Gradle descarga el wrapper 9.3.1, AGP, CMake 3.22.1 y el
NDK 28.2.13676358. En este entorno fueron ~4 min el primer debug y ~2 min el
release ya en caliente. No es que el build se haya colgado.

Lo que **no** se puede verificar aquí: iOS (necesita macOS y Xcode) y todo lo
que dependa de cámara, WebView o vibración reales. No lo marques como probado.
