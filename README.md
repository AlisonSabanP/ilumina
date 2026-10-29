# Lumina

Impresión 3D accesible para todos. Lumina ayuda a personas con discapacidad
motriz, visual o cognitiva (incluida la sensibilidad propia del autismo) y a
profesionales de la salud y la ortopedia a diseñar objetos impresos en 3D que
encajen de verdad: en su mano, en su casa o en su consulta.

La app mide con la cámara (AR o 21 puntos de la mano), construye un prompt
enriquecido con esas medidas y genera el modelo 3D con Meshy AI. El modelo se
puede ver en 3D, descargar y compartir.

## Estado de verificación

Todo lo que sigue se ha ejecutado en este repositorio, no es una estimación:

| Comprobación | Comando | Resultado |
| --- | --- | --- |
| Análisis estático | `flutter analyze` | `No issues found!` |
| Pruebas | `flutter test` | `13/13 All tests passed!` |
| APK de depuración | `flutter build apk --debug` | `✓ Built app-debug.apk` |
| APK de release (R8 + shrink) | `flutter build apk --release` | `✓ Built app-release.apk (127.5MB)` |

Entorno usado: Flutter 3.47.8 stable, Dart 3.13.7, AGP 9.1.0, Gradle 9.3.1,
Kotlin 2.4.0, JDK 17, Android SDK 36, NDK 28.2.13676358.

La compilación de iOS **no** se ha podido verificar aquí: requiere macOS y
Xcode, que no existen en este entorno. Todo el código Dart es multiplataforma
y la configuración de iOS está escrita, pero `pod install` y el build con Xcode
quedan pendientes de ejecutarse en un Mac.

## Requisitos

- Flutter 3.44 o superior (probado con 3.47.8) con Dart 3.13.
- Android: JDK 17, Android SDK 36, NDK 28.2.13676358, `minSdk 24`.
- iOS (solo para AR y visor): macOS con Xcode, `platform :ios, '15.0'`.

## Puesta en marcha

```bash
flutter pub get
flutter run
```

No hace falta configurar nada para probarla: el repositorio incluye un `.env`
con la clave **pública de prueba** de Meshy. Se versiona a propósito, porque
`flutter_dotenv` lo lee del bundle y la compilación falla si no existe. Nunca
contiene una clave real (ver más abajo).

## La clave de Meshy

La clave **nunca** está en el código. Se resuelve en este orden
(`lib/core/env.dart`):

1. `--dart-define=MESHY_API_KEY=...` — recomendado para CI y release.
2. El fichero `.env` — versionado, con la clave de prueba.
3. La clave de prueba pública de Meshy
   `msy_dummy_api_key_for_test_mode_12345678`, que no consume créditos pero
   **no genera el modelo del prompt**: Meshy devuelve un resultado de
   demostración. La app lo detecta y lo avisa en pantalla.

Comandos exactos:

```bash
# Sin configurar nada: usa la clave de prueba del .env versionado
flutter run

# Con tu clave real, sin tocar el .env
flutter run --dart-define=MESHY_API_KEY=msy_tu_clave_real

# APK de release con la clave inyectada en tiempo de compilación
flutter build apk --release --dart-define=MESHY_API_KEY=msy_tu_clave_real
```

En Windows PowerShell el `--dart-define` necesita comillas dobles:
`--dart-define="MESHY_API_KEY=msy_tu_clave_real"`.

La clave se obtiene en <https://www.meshy.ai/developers/keys>.

## Permisos y configuración nativa

### Android

Ya está hecho en el repositorio. Resumen de lo que hay y por qué:

- `android/app/src/main/AndroidManifest.xml`
  - `android.permission.CAMERA` — AR y detección de manos.
  - `android.permission.INTERNET` — API de Meshy y descarga del `.glb`.
  - `android.hardware.camera.ar` con `required="false"` y `tools:replace`:
    ARCore es **opcional**, así Lumina se instala también en móviles sin AR
    (donde la medición AR se desactiva y queda la entrada manual). El
    `tools:replace` es obligatorio porque `arcore_flutter_plugin` declara esa
    característica como requerida en su propio manifiesto.
  - `com.google.ar.core = "optional"` — Google Play ofrece instalar ARCore sin
    bloquear la instalación.
- `android/app/build.gradle.kts` — `minSdk = 24` (lo exigen ARCore y
  MediaPipe), filtro de ABI `arm64-v8a` + `armeabi-v7a` y R8 activado en
  release con las reglas de `android/app/proguard-rules.pro`.
- `android/gradle.properties` — `android.newDsl=false` (el plugin de Flutter
  aún aplica el DSL clásico), `android.uniquePackageNames=false` (Sceneform
  1.17 publica dos artefactos con el mismo `package` en su manifiesto).
- `android/settings.gradle.kts` y `android/build.gradle.kts` — añaden el Maven
  de Google, que es el único sitio donde están publicados los artefactos de
  Sceneform.

### iOS

Ya está escrito, pero **no verificado** (hace falta macOS):

- `ios/Runner/Info.plist`
  - `NSCameraUsageDescription` — obligatoria; Apple rechaza la app sin ella.
  - `NSPhotoLibraryAddUsageDescription` / `NSPhotoLibraryUsageDescription` —
    para guardar el modelo o una captura.
  - Orientación fijada a retrato, igual que en Android.
- `ios/Podfile` — `platform :ios, '15.0'` y `PERMISSION_CAMERA=1` para
  `permission_handler`.

```bash
cd ios && pod install && cd ..
flutter build ios --release --dart-define=MESHY_API_KEY=msy_tu_clave_real
open ios/Runner.xcworkspace    # para archivar y subir a App Store Connect
```

`hand_landmarker` es **solo Android**: en iOS la pantalla de manos muestra el
motivo y ofrece la medición AR o la manual.

## Guía de uso

### Activar los modos de accesibilidad

El panel se abre desde el botón flotante de accesibilidad (el icono de persona)
presente en **todas** las pantallas, o desde la barra superior. Los cambios se
aplican al instante y se guardan en el dispositivo.

| Modo | Qué hace |
| --- | --- |
| TalkBack / VoiceOver | Cada control anuncia su etiqueta y su pista, y los cambios de estado se anuncian en voz alta. |
| Botones grandes | Área táctil mínima de 64×64 dp y más separación entre controles. |
| Pictogramas | Un icono grande junto a cada etiqueta, para quien lee con dificultad. |
| Modo dislexia | Tipografía Andika, más altura de línea (1,7) y más espaciado entre letras (1,2). |
| Alto contraste | Esquema de máximo contraste, independiente del modo claro/oscuro. |
| Reducir movimiento | Desactiva animaciones decorativas. |

También hay tres perfiles de un solo toque: **Motriz**, **Visual** y
**Cognitiva**, y un botón de **restablecer**.

Los modos de dislexia y alto contraste están sincronizados en dos direcciones
con el paquete `accessibility_widget`, así que activarlos en cualquiera de los
dos paneles afecta a toda la app.

### El formulario inteligente

1. Elige tu necesidad: **Motriz**, **Visual** o **Cognitiva/Sensibilidad**.
2. Responde las preguntas. El árbol se ramifica: cada respuesta abre la
   siguiente pregunta y, al final, una recomendación concreta de objeto.
3. Opcionalmente, **Genera una etiqueta en Braille**: escribe el texto, ajusta
   el tamaño y desliza el dedo por encima para "leerla" con vibración antes de
   imprimirla. Se puede copiar o compartir.

### Tomar medidas

Desde el formulario, "Añadir medida" abre el centro de medición con tres vías:

- **Objetos con AR**: mueve el móvil despacio para que detecte superficies y
  toca los dos extremos del objeto. La distancia aparece en cm y se puede
  etiquetar ("diámetro del mango"). Si el hit test falla, la app avisa y no
  inventa una medida.
- **Mano con 21 puntos** (solo Android): pon la mano abierta frente a la
  cámara. Se dibujan los 21 puntos y se calculan distancias entre puntos clave.
  La primera vez hay que **calibrar** con un objeto de tamaño conocido: sin
  calibrar, las distancias son relativas (× unidad), no centímetros. La app lo
  indica en pantalla.
- **Medida a mano**: se escribe el valor en centímetros. Es la salida de
  emergencia para dispositivos sin AR o sin cámara.

### Generar, ver y exportar

1. Con el formulario completo y al menos una medida, pulsa **Generar modelo
   3D**. Verás el prompt exacto que se envió a Meshy (recortado a 800
   caracteres si hacía falta) y el estado de la tarea con su progreso.
2. Si algo falla, el botón **Reintentar** vuelve a lanzar la generación.
3. Al terminar, **Ver el modelo en 3D** abre el visor: rotar automáticamente,
   detener la rotación, centrar la cámara y bloquear el paneo (para no
   "perder" la pieza). El zoom está limitado entre 0,4× y 4×.
4. **Descargar** guarda el `.glb` en el dispositivo; **Compartir** lo envía por
   cualquier app instalada. Una vez descargado, el visor lo carga del
   dispositivo y funciona sin conexión.

### ProGrip

Prótesis y adaptadores para el trabajo, en tres capas: base de acople, garfio
funcional (dos dedos, tres dedos, gancho curvo, pinza de presión…) y adaptador
de herramienta (martillo, destornillador, sierra, taladro, cuchillo, tijeras,
pincel, rastrillo). Cada elección cambia el prompt, y las medidas de la mano se
incorporan al diseño.

### OrthoSnap

Órtesis clínicas con acceso restringido. El login está **mockeado** (no hay
backend): cualquier usuario y contraseña no vacíos entran, y se indica en
pantalla. El formulario clínico (zona de lesión, tipo de férula, diagnóstico,
lado afectado) más las medidas generan una petición a Meshy que pide
explícitamente estructura Voronoi, material transpirable y alta precisión.

## Documentación técnica

| Paquete / API | Versión | Para qué se usa | Con qué fin |
| --- | --- | --- | --- |
| Flutter | 3.47.8 (stable) | Framework | UI multiplataforma, null safety, Material 3 |
| Dart | 3.13.7 | Lenguaje | `sdk: ^3.13.0` en `pubspec.yaml` |
| `provider` | 6.1.2 | Gestión de estado | **Elegido frente a Riverpod** por ser el que usa el material didáctico de Flutter, no necesitar generación de código y bastar para este grafo de estado. Cinco `ChangeNotifier` en la raíz |
| `nested` | 1.0.0 | Tipos | Aporta `SingleChildWidget`, el tipo de la lista de `MultiProvider`; `provider` no lo reexporta |
| `shared_preferences` | 2.3.0 | Persistencia | Guarda los modos de accesibilidad y el historial de modelos |
| `flutter_dotenv` | 6.0.0 | Configuración | Lee `MESHY_API_KEY` del `.env`, sin escribir la clave en el código |
| `http` | 1.2.2 | Red | Cliente REST de Meshy AI |
| `path_provider` | 2.1.5 | Sistema de ficheros | Carpeta de documentos para los `.glb` descargados |
| `share_plus` | 12.0.0 | Compartir | Envía el `.glb` o el texto en Braille a otras apps |
| `accessibility_widget` | 0.0.2 | Accesibilidad WCAG | Panel de contraste, saturación, guía de lectura, escala de texto y fuente para dislexia; su `AccessibilityWidget` envuelve la app |
| `braille_text` | 0.0.1 | Accesibilidad visual | `BrailleConverter` traduce texto a Braille Unicode y `BrailleText` lo dibuja con vibración por carácter |
| `camera` | 0.12.1 | Cámara | `CameraController` con NV21 para alimentar a MediaPipe |
| `hand_landmarker` | 3.1.0 | Visión por computadora | 21 landmarks 3D de la mano vía MediaPipe. **Solo Android** |
| `neom_ar` | 1.0.0 | AR | `ArService`/`ArMeasureController` unifican ARKit y ARCore tras una sola interfaz y dan la máquina de estados de medición (dos puntos → distancia) |
| `arkit_plugin` | 1.5.0 | AR iOS | `ARKitSceneView` con detección de planos (la parte que `neom_ar` deja al consumidor) |
| `arcore_flutter_plugin` | 0.1.0 (fork local) | AR Android | `ArCoreView` con render de planos y hit test |
| `sint` | 1.6.2 | Inyección de dependencias | `neom_ar` registra su controlador con Sint; Lumina lo declara porque lo usa directamente |
| `power3d` | 2.3.0 | Visor 3D | `Power3D.fromNetwork` carga el `.glb` en un visor Babylon.js sobre WebView; `Power3DController` da rotación, zoom, centrado y bloqueo de paneo |
| Meshy AI REST | v2 | Generación 3D | `POST /openapi/v2/text-to-3d` → `task_id` → `GET /openapi/v2/text-to-3d/{task_id}` hasta `SUCCEEDED` → descarga de `model_urls.glb` |

### Costes de Meshy

- La clave `msy_dummy_api_key_for_test_mode_12345678` es la de **modo de
  prueba**: no consume créditos y permite probar todo el flujo, pero Meshy
  **no genera el modelo del prompt** (devuelve un resultado de demostración).
  Es la que trae el `.env` versionado.
- Con una clave real, cada tarea `preview` de text-to-3D consume créditos del
  plan. Hay plan gratuito con créditos mensuales limitados y planes de pago.
- Lumina consulta `GET /openapi/v1/balance` y avisa antes de gastar.
- **Nunca se reintenta un `POST`** tras un error de red: Meshy no tiene clave
  de idempotencia y un segundo envío crearía (y cobraría) una segunda tarea.
  Solo se reintenta el `GET` de sondeo.

### Limitaciones de plataforma

| Función | Android | iOS |
| --- | --- | --- |
| Medición AR de objetos | Sí (ARCore, requiere dispositivo compatible) | Sí (ARKit) |
| Medición de manos (21 puntos) | Sí | **No** — `hand_landmarker` solo tiene implementación Android. La pantalla lo explica y ofrece AR o medida manual |
| Medida manual | Sí | Sí |
| Generación con Meshy | Sí | Sí |
| Visor 3D y exportación | Sí | Sí |
| Braille | Sí | Sí |
| Modos de accesibilidad | Sí | Sí |

En Android, si el dispositivo no soporta ARCore, la app **se instala igual**
(la característica AR está declarada como opcional) y la medición AR queda
desactivada.

## Estructura del proyecto

```
lib/
  main.dart                        Arranque: enlaces, .env, orientación
  app/app.dart                     Providers y MaterialApp
  core/
    app_theme.dart                 ColorScheme, tipografía, ThemeExtension
    app_colors.dart                Paleta (azul #2C5F8A, morado #6B4C9A)
    app_spacing.dart               Radios, elevación y espaciados
    accessibility_contract.dart    Contrato de los modos de accesibilidad
    env.dart                       Resolución de MESHY_API_KEY
  features/
    accesibilidad/                 Panel, provider y FAB de accesibilidad
    formulario/                    Árbol de preguntas, provider y pantalla Braille
    medicion/                      AR, manos y medida manual + modelos
    generacion3d/                  Cliente de Meshy, prompt y pantalla de progreso
    visor3d/                       Visor Power3D y descarga del .glb
    progrip/                       Base + garfio + adaptador de herramienta
    orthosnap/                     Login mockeado y formulario clínico
    home/                          Pantalla de inicio
  shared/widgets/lumina_widgets.dart   Widgets accesibles reutilizables
test/widget_test.dart              13 pruebas de accesibilidad, tema, formulario y métricas
assets/fonts/Andika-*.ttf          Tipografía para dislexia (SIL OFL)
.env                               Solo la clave pública de prueba de Meshy (ver arriba)
android/  ios/  third_party/
third_party/arcore_flutter_plugin/          Fork local (ver más abajo)
third_party/flutter_inappwebview_android/   Fork local (ver más abajo)
```

## Notas de mantenimiento

### Los dos forks locales de `third_party/`

Dos paquetes de pub.dev no compilan con Gradle 9 / AGP 9 y se han vendorizado.
En ambos casos el código es el original y **solo cambia la configuración de
compilación**:

- `third_party/arcore_flutter_plugin` — el original llama a `jcenter()`
  (repositorio retirado), trae un `buildscript` con AGP 3.5.3 y depende de
  Sceneform 1.13, que ya no está publicado. El fork usa el plugin de Android
  moderno, Sceneform 1.17.1 y excluye `com.android.support` (que provocaba
  "Duplicate class" contra androidx). Único cambio de código: `MotionEvent?` →
  `MotionEvent` en `ArCoreView.kt`, por un cambio de firma de Sceneform 1.17.
- `third_party/flutter_inappwebview_android` — su configuración de release usa
  `getDefaultProguardFile('proguard-android.txt')`, que Gradle 9 rechaza porque
  desactiva R8. El fork solo cambia esa línea por
  `proguard-android-optimize.txt`.

Se declaran en `dependency_overrides` de `pubspec.yaml`. Si algún día los
paquetes publican una versión compatible, basta con borrar el `override` y la
carpeta.

### Rotar la clave de Meshy

1. Genera una nueva en <https://www.meshy.ai/developers/keys>.
2. Actualiza el `--dart-define=MESHY_API_KEY=...` de tu CI o de tu comando
   local. El `.env` versionado no se toca: solo lleva la clave de prueba.
3. La clave anterior se puede revocar desde el mismo panel. No hay que tocar
   ningún fichero del repositorio.

### Demo 100 % gratuita con modelos locales

Para una presentación sin gastar créditos ni depender de la red:

1. Copia tus `.glb` a `assets/models/`.
2. En `pubspec.yaml`, el directorio ya está declarado como asset.
3. En `lib/features/visor3d/pantallas/visor_modelo_screen.dart`, sustituye
   `Power3D.fromNetwork(url: _modelUrl, ...)` por
   `Power3D.fromAsset(assetPath: 'assets/models/tu_pieza.glb', ...)`.
4. El resto del visor (controlador, botones, descarga, compartir) no cambia.

### Antes de publicar en las tiendas

- Sustituir la firma de debug de `android/app/build.gradle.kts` por una clave
  de release propia (hay un `TODO` en el fichero).
- Revisar que `applicationId` (`com.lumina.lumina`) es el definitivo.
- Comprobar que el `.env` del commit sigue llevando **solo** la clave de prueba
  y que la clave real va por `--dart-define` en el pipeline.
- Verificar en un dispositivo Android real sin ARCore que la app instala y
  ofrece la medida manual.
- En iOS: ejecutar `pod install` y el build en un Mac, y rellenar la ficha de
  privacidad (la cámara y la galería se declaran en `Info.plist`).
- Repasar las reglas de `proguard-rules.pro` si se añaden dependencias nuevas
  que usen reflexión o JNI.

## Errores probables

1. **`jcenter()` en Gradle** — ya resuelto con el fork de `arcore_flutter_plugin`.
   Si se quita el `dependency_overrides`, vuelve el fallo.
2. **`Duplicate class android.support.v4...`** — ya resuelto excluyendo
   `com.android.support` de `sceneform-ux`. Vuelve si se quita la exclusión.
3. **`Namespace 'com.google.ar.sceneform' is used in multiple modules`** —
   resuelto con `android.uniquePackageNames=false`. Sin esa bandera AGP 9
   aborta la fusión de manifiestos.
4. **`Missing class com.google.ar.sceneform.animation.*` en R8** — resuelto con
   `-dontwarn` en `proguard-rules.pro`. Son clases opcionales de Sceneform que
   Lumina nunca ejecuta.
5. **La detección de manos no detecta nada** — suele ser formato de cámara.
   Lumina pide NV21 y descarta los fotogramas que no traigan tres planos.
   Comprueba en un dispositivo real: los emuladores rara vez tienen una cámara
   utilizable para MediaPipe.
6. **`hand_landmarker` falla en iOS** — es esperado: solo hay implementación
   Android. La app lo detecta en tiempo de ejecución y ofrece alternativas.
7. **El visor 3D sale en blanco** — `power3d` monta un WebView. En un
   dispositivo con WebView antiguo o sin WebView del sistema, Babylon.js no
   arranca. Actualiza Android System WebView.
8. **Error 402 de Meshy** — la cuenta no tiene plan o se agotaron los créditos.
   El mensaje de la app lo explica.
9. **El primer `flutter build apk` tarda mucho** — Gradle descarga el NDK
   (~2 GB) y compila MediaPipe y Filament (Sceneform). Es normal la primera vez.
10. **`flutter build apk` se queda sin memoria** — MediaPipe y Filament son
    pesados. `android/gradle.properties` está ajustado a `-Xmx4G`; en una
    máquina con menos de 8 GB puede haber que bajarlo más.
11. **`No file or variants found for asset: .env`** — falta el fichero `.env`.
    Se versiona precisamente para que no pase; si lo has borrado, recupéralo
    con `git checkout -- .env`.

## Dependencias que debo instalar

Todas se resuelven con `flutter pub get`, incluidos los dos forks locales
(están en el repositorio). Para compilar Android hacen falta además, fuera de
Dart: **JDK 17**, **Android SDK 36** y **NDK 28.2.13676358**. Para iOS: macOS,
Xcode y CocoaPods.

## Configuración nativa pendiente

- **iOS**: `pod install` y el build en Xcode, en un Mac. No verificable aquí.
- **Android**: la firma de release (hay un `TODO` con la configuración de
  debug). Todo lo demás ya está aplicado y probado.
- **Login de OrthoSnap**: mockeado a propósito, sin backend real.
- **Clave de Meshy para producción**: el `.env` versionado solo trae la clave
  de prueba; hay que pasar la real con `--dart-define` al compilar.

## Paquetes que pueden no estar disponibles y su alternativa

| Paquete | Riesgo | Alternativa |
| --- | --- | --- |
| `arcore_flutter_plugin` | Abandonado; su versión de pub.dev no compila | Fork local ya incluido en `third_party/`. Si desaparece el código fuente, `google_mlkit_object_detection` + `camera` permiten medir con referencia de escala conocida |
| `flutter_inappwebview_android` | Su config de release rompe con Gradle 9 | Fork local ya incluido. Alternativa de más calado: sustituir `power3d` por `model_viewer_plus` o `flutter_cube` |
| `neom_ar` | 1.0.0, muy joven; expone rutas internas (`ui/controllers/ar_measure_controller.dart`) | El código de medición AR de Lumina está aislado en `ar_measurement_screen.dart` y usa la interfaz `ArService`; se puede reemplazar por llamadas directas a `arcore_flutter_plugin` y `arkit_plugin` sin tocar el resto |
| `hand_landmarker` | Solo Android, mantenimiento irregular | `google_mlkit_pose_detection` (multiplataforma) o `mediapipe_flutter`; el adaptador `hand_detector.dart` ya aísla el paquete |
| `accessibility_widget` | 0.0.2, versión inicial | El panel propio de Lumina cubre TalkBack, botones grandes, pictogramas y dislexia sin él; solo se perderían los filtros de color y la guía de lectura |
| `braille_text` | 0.0.1 | `BrailleConverter` es una tabla Unicode: se puede reimplementar en ~50 líneas si el paquete desaparece |
| Meshy AI | API de pago | `Power3D.fromAsset` con `.glb` locales (ver "Demo 100 % gratuita"), o cualquier otro servicio text-to-3D sustituyendo `meshy_service.dart` |

## Fragmentos marcados `[VERIFICAR]`

Dos puntos de `lib/features/medicion/pantallas/ar_measurement_screen.dart`:

1. La ruta del import `package:neom_ar/ui/controllers/ar_measure_controller.dart`
   es una ruta interna del paquete. Compila con la versión 1.0.0 fijada, pero
   un cambio de estructura interna la rompería.
2. `neom_ar` documenta que `ArMeasureController.onTap` recibe coordenadas
   normalizadas (0-1), pero no documenta el camino de hit test por coordenadas.
   Lumina usa ese camino porque es el que se comporta igual en ARKit y ARCore,
   y ofrece la medida manual como respaldo si el hit test no devuelve nada.

Ninguno de los dos se ha podido probar en un dispositivo real con cámara en
este entorno, así que se dejan marcados en lugar de darlos por buenos.
