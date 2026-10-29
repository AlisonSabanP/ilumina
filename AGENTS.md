# Lumina — notas para agentes

App Flutter de impresión 3D accesible. La documentación de producto (guía de
uso, tabla técnica, limitaciones) está en `README.md`; esto es lo que hace falta
saber para trabajar en el código sin romperlo.

## Comandos

```bash
flutter pub get
flutter analyze          # debe quedar en "No issues found!"
flutter test             # 20 pruebas, todas deben pasar
flutter build apk --debug
flutter build apk --release   # ~5 min; R8 tarda
```

Android necesita JDK 17, Android SDK 36 y NDK 28.2.13676358.
`android/gradle.properties` usa `-Xmx4G`: subirlo provoca que el runtime se
quede sin memoria al compilar Filament (Sceneform) y MediaPipe a la vez.

## Arquitectura

- **Estado:** `provider` con cinco `ChangeNotifier` en `lib/app/app.dart`
  (`AccessibilityProvider`, `FormularioProvider`, `ProGripProvider`,
  `AuthProvider`, `GenerationProvider`). No se usa Riverpod a propósito.
- **Aislamiento por feature:** cada módulo vive en `lib/features/<nombre>/` con
  `modelos/`, `pantallas/`, `providers/`, `servicios/`, `widgets/` según haga
  falta. Nada de un módulo importa pantallas de otro salvo por navegación.
- **Frontera con paquetes frágiles:** los paquetes con API inestable o
  específicos de plataforma se envuelven en un adaptador para que sus tipos no
  lleguen a la UI. Ejemplos: `hand_detector.dart` (envuelve
  `hand_landmarker`), `meshy_service.dart` (envuelve la API REST),
  `ar_measurement_screen.dart` (usa la interfaz `ArService` de `neom_ar`, no
  las clases de ARCore/ARKit directamente).
- **Accesibilidad:** `AccessibilityProvider` es la fuente de verdad. Se
  sincroniza en dos direcciones con `accessibility_widget` en
  `_AccessibilitySync` (`lib/app/app.dart`) y en el panel
  (`lib/features/accesibilidad/pantallas/panel_accesibilidad_screen.dart`). Si
  tocas uno, revisa el otro: el flag `_syncing` existe para evitar bucles.

## Los dos forks de `third_party/`

No son opcionales. Sin ellos no compila. Se declaran en
`dependency_overrides` de `pubspec.yaml`.

- `third_party/arcore_flutter_plugin` — el original de pub.dev llama a
  `jcenter()`, trae AGP 3.5.3 en su `buildscript` y depende de Sceneform 1.13
  (retirado). El fork moderniza el Gradle, sube a Sceneform 1.17.1 y excluye
  `com.android.support` de `sceneform-ux` (provocaba "Duplicate class").
  **Único cambio de código Kotlin:** `MotionEvent?` → `MotionEvent` en
  `ArCoreView.kt`, por la nueva firma de `setOnTouchListener` en Sceneform 1.17.
- `third_party/flutter_inappwebview_android` — `getDefaultProguardFile
  ('proguard-android.txt')` es rechazado por Gradle 9. Solo se cambia a
  `proguard-android-optimize.txt`.

`analysis_options.yaml` excluye `third_party/**` del análisis; cada fork tiene
su propio `analysis_options.yaml` relajado. No añadas lints ahí.

## Trampas de configuración nativa

Estas cuatro banderas/reglas son la diferencia entre que compile y que no.
Están puestas y comentadas en el repositorio; si alguien las quita, vuelve el
error:

| Ajuste | Dónde | Sin él |
| --- | --- | --- |
| `android.newDsl=false` | `android/gradle.properties` | El plugin de Flutter no aplica |
| `android.uniquePackageNames=false` | `android/gradle.properties` | Sceneform publica dos artefactos con el mismo `package` y AGP 9 aborta la fusión de manifiestos |
| Exclusión de `com.android.support` en `sceneform-ux` | `third_party/arcore_flutter_plugin/android/build.gradle` | `Duplicate class android.support.v4...` |
| `-dontwarn com.google.ar.sceneform.**` | `android/app/proguard-rules.pro` | R8 falla por clases opcionales de Sceneform que nunca se ejecutan |

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
configurada". En ese caso `GenerationProvider._runDemo` no llama a la API y
carga `assets/models/demo_pieza.glb` con `Power3D.fromAsset`. No inventes un
"modo de prueba" de Meshy que devuelva modelos: no existe.

`assets/models/*.glb` está excluido por `.gitignore`, salvo `demo_pieza.glb`,
que se versiona porque el modo de demostración lo necesita.

## Marcadores `[VERIFICAR]`

Hay dos en `ar_measurement_screen.dart`: la ruta de import interna de `neom_ar`
y el camino de hit test por coordenadas. Ninguno se ha probado en un
dispositivo real con cámara. No los des por buenos sin probarlos en hardware.
