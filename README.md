# Lumina

Impresión 3D accesible para todos. Lumina ayuda a personas con discapacidad
motriz, visual o cognitiva (incluida la sensibilidad propia del autismo) y a
profesionales de la salud y la ortopedia a diseñar objetos impresos en 3D que
encajen de verdad: en su mano, en su casa o en su consulta.

La app mide con la cámara (21 puntos de la mano) o a mano. Sin clave de Meshy
muestra una **pieza de ejemplo** incluida en la app, para que el flujo completo
(visor 3D, descarga y compartir) se pueda probar sin coste. Con la clave propia
del usuario, la pieza la genera la IA de Meshy AI. Las **etiquetas Braille** se
construyen siempre en el propio dispositivo, con geometría real exportada a STL.
El modelo se puede ver en 3D, descargar y compartir.

## Estado de verificación

Todo lo que sigue se ha ejecutado en este repositorio, no es una estimación:

| Comprobación | Comando | Resultado |
| --- | --- | --- |
| Análisis estático | `flutter analyze` | `No issues found!` |
| Pruebas | `flutter test` | `35/35 All tests passed!` |
| APK de depuración | `flutter build apk --debug` | `✓ Built app-debug.apk (202.8MB)` |
| APK de release (R8 + shrink) | `flutter build apk --release` | `✓ Built app-release.apk (102.0MB)` |
| APK de release por ABI | `flutter build apk --release --split-per-abi` | `✓ arm64-v8a 43.7MB · armeabi-v7a 38.0MB · x86_64 48.0MB` |

Entorno usado: Flutter 3.47.9 stable, Dart 3.13.7, AGP 9.1.0, Gradle 9.3.1,
Kotlin 2.4.0, JDK 21 (compilando a Java 17), Android SDK 36, NDK 28.2.13676358.

La compilación de iOS **no** se ha podido verificar aquí: requiere macOS y
Xcode, que no existen en este entorno. Todo el código Dart es multiplataforma
y la configuración de iOS está escrita, pero `pod install` y el build con Xcode
quedan pendientes de ejecutarse en un Mac.

## Requisitos

- Flutter 3.44 o superior (probado con 3.47.9) con Dart 3.13.
- Android: JDK 17 o superior (AGP 9 lo exige), Android SDK 36,
  NDK 28.2.13676358, `minSdk 24`.
- iOS (medida a mano, generación, visor y Braille): macOS con Xcode,
  `platform :ios, '15.0'`.

## Puesta en marcha

```bash
flutter pub get
flutter run
```

No hace falta configurar nada: **la app arranca en modo demostración**. Sin
clave de Meshy se muestra una pieza de ejemplo empaquetada en la app y la
etiqueta Braille se construye en el propio dispositivo. No gasta créditos ni
necesita conexión.

El `.env` que incluye el repositorio solo contiene el valor centinela de Meshy
(ver más abajo); se versiona a propósito porque `flutter_dotenv` lo lee del
bundle y la compilación falla si el fichero no existe.

## Generación 3D: gratis por defecto, Meshy opcional

Hay tres vías:

1. **Modo demostración (por defecto, sin clave).** Se muestra el cubo de
   ejemplo incluido en `assets/models/demo_pieza.glb` con `Power3D.fromAsset`.
   Sirve para probar el visor, la descarga y el compartir sin gastar créditos.
2. **Etiqueta Braille (local, sin red).** `LocalGeneratorService` construye la
   placa con los puntos en relieve y la exporta a **STL binario** (para
   imprimir) y **GLB** (para el visor). Coste cero y funciona sin conexión.
3. **Generación con IA (opcional).** Solo si configuras tu clave de Meshy.

## La clave de Meshy (opcional)

La clave **nunca** está en el código. Se resuelve en este orden
(`lib/core/env.dart`):

1. `--dart-define=MESHY_API_KEY=...` — recomendado para CI y release.
2. El fichero `.env` — versionado, con un valor centinela.
3. El valor centinela `msy_dummy_api_key_for_test_mode_12345678`.

**Meshy no tiene modo de prueba gratuito.** Cualquier clave que no sea de una
cuenta real recibe un `401 Invalid API key`. Por eso Lumina usa el valor
centinela solo para saber que "no hay clave configurada" y, en ese caso, genera
en el dispositivo. Al configurar una clave real, la app llama a Meshy de verdad.

Comandos exactos:

```bash
# Sin configurar nada: generación en el dispositivo, gratis y sin conexión
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
  - `android.permission.CAMERA` — detección de manos.
  - `android.permission.INTERNET` — API de Meshy (solo si se configura clave)
    y descarga de modelos.
  - `android.hardware.camera` y `autofocus` con `required="false"`, para que
    la app se instale también en dispositivos sin cámara.
- `android/app/build.gradle.kts` — `minSdk = 24` (lo exige MediaPipe), filtro
  de ABI `arm64-v8a` + `armeabi-v7a` y R8 activado en release con las reglas
  de `android/app/proguard-rules.pro`.
- `android/gradle.properties` — `android.newDsl=false` (el plugin de Flutter
  aún aplica el DSL clásico).

### iOS

Ya está escrito, pero **no verificado** (hace falta macOS):

- `ios/Runner/Info.plist`
  - `NSCameraUsageDescription` — obligatoria; Apple rechaza la app sin ella.
  - `NSPhotoLibraryAddUsageDescription` / `NSPhotoLibraryUsageDescription` —
    para guardar el modelo o una captura.
  - Orientación fijada a retrato, igual que en Android.
- `ios/Podfile` — `platform :ios, '15.0'` y `PERMISSION_CAMERA=1` para el
  plugin `camera`.

```bash
cd ios && pod install && cd ..
flutter build ios --release --dart-define=MESHY_API_KEY=msy_tu_clave_real
open ios/Runner.xcworkspace    # para archivar y subir a App Store Connect
```

`hand_landmarker` es **solo Android**: en iOS la pantalla de manos muestra el
motivo y ofrece la medida a mano.

## Guía de uso

### Activar los modos de accesibilidad

El panel se abre desde el botón flotante de accesibilidad (el icono de persona)
presente en **todas** las pantallas, o desde la barra superior. Los cambios se
aplican al instante y se guardan en el dispositivo.

| Modo | Qué hace |
| --- | --- |
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

Los controles "Invertir colores" y "Guía de lectura" del paquete se han
retirado del panel: el paquete los guardaba pero no los aplicaba al árbol de
widgets, así que el interruptor no cambiaba nada. Un control que no cumple lo
que promete es peor que no tenerlo.

El lector de pantalla del sistema (TalkBack en Android, VoiceOver en iOS) no es
un modo de la app: se activa en los ajustes del teléfono. Lumina no le dedica un
interruptor, pero etiqueta todos sus controles con `Semantics` y un orden de
lectura lógico para que funcionen bien cuando el lector esté activo.

### El formulario inteligente

1. Elige tu necesidad: **Motriz**, **Visual** o **Cognitiva/Sensibilidad**.
2. Responde las preguntas. El árbol se ramifica: cada respuesta abre la
   siguiente pregunta y, al final, una recomendación concreta de objeto.
3. En la revisión puedes crear, **si quieres**, una **etiqueta en Braille**. No
   se añade a la pieza: es una pieza aparte, para pegar o colgar del objeto que
   identifica.

### La etiqueta en Braille (pieza aparte, opcional)

La etiqueta **no se graba sobre la pieza principal y no se genera sola**: se crea
únicamente cuando la pides. Hay dos caminos y ambos construyen la misma placa:

- **Elegir el perfil Visual** y la opción "Etiquetas en braille". Entonces
  "Generar modelo 3D" produce directamente la placa.
- **Desde la revisión de cualquier otro perfil**, con el botón "Crear etiqueta
  en Braille", que abre su pantalla propia.

El flujo es: escribes el texto (se propone el título de la recomendación, pero
es solo una sugerencia editable), ajustas el tamaño de la vista previa y
deslizas el dedo por encima para "leerla" con vibración. El botón **Crear la
etiqueta para imprimir** genera la placa con los puntos en relieve (1,6 mm de
diámetro y 0,8 mm de altura, con la separación estándar de 2,5 mm) y la abre en
el visor, lista para descargar.

Este es el caso de uso del perfil **Visual**: quien no ve el objeto no necesita
una pieza grande, necesita la etiqueta. Por eso es su propio objeto imprimible.

### Tomar medidas

Desde el formulario, "Añadir medida" abre el centro de medición con dos vías:

- **Mano con 21 puntos** (solo Android): pon la mano abierta frente a la
  cámara. Se dibujan los 21 puntos y se calculan distancias entre puntos clave.
  La primera vez hay que **calibrar** con un objeto de tamaño conocido: sin
  calibrar, las distancias son relativas (× unidad), no centímetros. La app lo
  indica en pantalla.
- **Medida a mano**: se escribe el valor en centímetros. Es la vía para
  dispositivos sin cámara o cuando se prefiere una regla.

> La medición de objetos por realidad aumentada se retiró: no funcionaba de
> forma fiable en dispositivos reales. Ver "Notas de mantenimiento".

### Generar, ver y exportar

1. Con el formulario completo, pulsa **Generar modelo 3D**. La pieza se
   construye en el dispositivo a partir de tus respuestas y medidas; verás la
   ficha con las cotas finales y las notas de fabricación (por ejemplo, si
   algún dato faltaba y se usó un valor estándar).
2. Si configuraste una clave de Meshy, en su lugar verás el prompt exacto que
   se envió (recortado a 800 caracteres si hacía falta) y el estado de la tarea
   con su progreso.
3. Al terminar, **Ver el modelo en 3D** abre el visor: rotar automáticamente,
   detener la rotación, centrar la cámara y bloquear el paneo (para no
   "perder" la pieza). El zoom está limitado entre 0,4× y 4×. El visor abre en
   vista de tres cuartos, no de frente: de frente las piezas altas y estrechas
   se ven de canto y parecen un círculo. "Centrar" devuelve a esa misma vista.
4. **Descargar STL** guarda el archivo listo para laminar; **Compartir STL** lo
   envía por cualquier app instalada (correo, mensajería, Drive). El STL se abre
   directamente en Cura, PrusaSlicer o Bambu Studio. El visor usa una copia
   interna en GLB y funciona sin conexión.

### Adaptadores de agarre para herramientas

La rama motriz del formulario cubre siete herramientas (martillo,
destornillador, sierra, cuchillo, tijeras, pincel y rastrillo). Cada una aporta
su recomendación y sus frases de diseño al prompt, y las medidas de la mano se
incorporan al modelo. No hay un módulo aparte: son un resultado más del
formulario.

## Documentación técnica

| Paquete / API | Versión resuelta | Para qué se usa | Con qué fin |
| --- | --- | --- | --- |
| Flutter | 3.47.9 (stable) | Framework | UI multiplataforma, null safety, Material 3 |
| Dart | 3.13.7 | Lenguaje | `sdk: ^3.13.0` en `pubspec.yaml` |
| `provider` | 6.1.5 | Gestión de estado | **Elegido frente a Riverpod** por ser el que usa el material didáctico de Flutter, no necesitar generación de código y bastar para este grafo de estado. Tres `ChangeNotifier` en la raíz |
| `nested` | 1.0.0 | Tipos | Aporta `SingleChildWidget`, el tipo de la lista de `MultiProvider`; `provider` no lo reexporta |
| `shared_preferences` | 2.5.6 | Persistencia | Guarda los modos de accesibilidad y el historial de modelos |
| `flutter_dotenv` | 6.0.1 | Configuración | Lee `MESHY_API_KEY` del `.env`, sin escribir la clave en el código |
| `http` | 1.6.0 | Red | Cliente REST de Meshy AI |
| `path_provider` | 2.1.6 | Sistema de ficheros | Carpeta de documentos para las piezas generadas y los `.glb` descargados |
| `share_plus` | 12.0.2 | Compartir | Envía el `.stl` o el texto en Braille a otras apps |
| `accessibility_widget` | 0.0.2 | Accesibilidad WCAG | Aporta el `AccessibilityController` y el `AccessibilityWidget` que envuelve la app: saturación, escala de texto, espaciados y fuente para dislexia. **Su panel no se usa**: trae los textos en inglés y Lumina dibuja el suyo en español con el mismo controlador. Sus controles de inversión de color y guía de lectura se descartaron porque no se aplican al árbol de widgets |
| `braille_text` | 0.0.1 | Accesibilidad visual | `BrailleConverter` traduce texto a Braille Unicode y `BrailleText` lo dibuja con vibración por carácter. Requiere declarar una fuente con glifos Braille (ver mantenimiento) |
| `camera` | 0.12.2 | Cámara | `CameraController` en `ImageFormatGroup.yuv420` para alimentar a MediaPipe |
| `hand_landmarker` | 3.1.0 | Visión por computadora | 21 landmarks 3D de la mano vía MediaPipe. **Solo Android** |
| `power3d` | 2.3.1 | Visor 3D | Visor Babylon.js sobre WebView. `Power3D.fromFile` carga las piezas generadas en el dispositivo, `Power3D.fromNetwork` los modelos de Meshy y `Power3D.fromAsset` cualquier `.glb` empaquetado; `Power3DController` da rotación, zoom, centrado y bloqueo de paneo |
| — (código propio) | — | Generación 3D local | `MeshBuilder` (`lib/shared/servicios/stl_builder.dart`) construye mallas paramétricas y las serializa a **STL binario** y **GLB**. Sin dependencias externas y sin coste |
| Meshy AI REST (opcional) | v2 | Generación 3D con IA | `POST /openapi/v2/text-to-3d` → `task_id` → `GET /openapi/v2/text-to-3d/{task_id}` hasta `SUCCEEDED` → descarga de `model_urls.glb` |

### Costes de Meshy

- **No existe modo de prueba.** El valor
  `msy_dummy_api_key_for_test_mode_12345678` que trae el `.env` versionado no
  es válido: sirve solo de centinela. Mientras esté ahí, Lumina muestra la
  pieza de ejemplo y no gasta nada.
- **El modo demostración y la etiqueta Braille son gratuitos**: no llaman a
  ningún servicio, así que un centro escolar o un usuario particular pueden usar
  Lumina entera sin coste recurrente.
- Con una clave real, cada tarea `preview` de text-to-3D consume créditos del
  plan. Hay plan gratuito con créditos mensuales limitados y planes de pago.
- **Nunca se reintenta un `POST`** tras un error de red: Meshy no tiene clave
  de idempotencia y un segundo envío crearía (y cobraría) una segunda tarea.
  Solo se reintenta el `GET` de sondeo.

### Limitaciones de plataforma

| Función | Android | iOS |
| --- | --- | --- |
| Medición de manos (21 puntos) | Sí | **No** — `hand_landmarker` solo tiene implementación Android. La pantalla lo explica y ofrece la medida a mano |
| Medida a mano | Sí | Sí |
| Generación local (gratuita) | Sí | Sí |
| Generación con Meshy (opcional) | Sí | Sí |
| Visor 3D y exportación | Sí | Sí |
| Braille | Sí | Sí |
| Modos de accesibilidad | Sí | Sí |

La app se instala también en dispositivos sin cámara: la característica está
declarada como opcional y la medida a mano sigue disponible.

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
    medicion/                      Manos y medida manual + modelos
    generacion3d/                  Generador local, cliente de Meshy y pantalla de progreso
    visor3d/                       Visor Power3D y descarga del STL
    home/                          Pantalla de inicio
  shared/
    servicios/stl_builder.dart     Mallas paramétricas y exportación a STL/GLB
    servicios/braille_service.dart Normalización de texto para Braille
    widgets/lumina_widgets.dart    Widgets accesibles reutilizables
test/widget_test.dart              32 pruebas: accesibilidad, tema, formulario,
                                   Braille, métricas y geometría (STL y GLB)
test/app_boot_test.dart            3 pruebas de integración: arranque real de
                                   la app, panel de accesibilidad y recorrido
                                   completo del formulario hasta la recomendación
assets/fonts/Andika-*.ttf          Tipografía para dislexia (SIL OFL)
assets/fonts/BraillePoints.ttf     Glifos Braille (DejaVu Sans, libre)
assets/images/, assets/models/     Assets declarados (vacíos, con .gitkeep)
.env                               Solo el valor centinela de Meshy (ver arriba)
android/                           Permisos, minSdk 24, R8 y reglas ProGuard
ios/                               Info.plist con los permisos de cámara
third_party/flutter_inappwebview_android/   Fork local (ver más abajo)
```

## Notas de mantenimiento

### Por qué se retiró la medición AR

La medición de objetos por realidad aumentada (`neom_ar` + `arkit_plugin` +
`arcore_flutter_plugin`) **se eliminó**. Los motivos:

1. No funcionaba de forma fiable en dispositivos reales: el paquete expone
   rutas internas no documentadas y su hit test por coordenadas no daba
   resultados estables.
2. `arcore_flutter_plugin` de pub.dev no compila con Gradle 9 y obligaba a
   mantener un fork propio de ARCore + Sceneform, que era la mayor fuente de
   fragilidad del build.

Lo que queda cubre la necesidad real: la detección de manos (21 landmarks, muy
precisa para lo que Lumina mide) y la medida a mano con regla. Eliminar AR
quitó también el fork de ARCore, las reglas de R8 para Sceneform y dos banderas
de Gradle.

Si algún día se quiere recuperar, el camino más sólido es
`google_mlkit_object_detection` con un objeto de referencia de tamaño conocido,
que es multiplataforma y no depende de ARCore.

### El único fork local de `third_party/`

- `third_party/flutter_inappwebview_android` — su configuración de release usa
  `getDefaultProguardFile('proguard-android.txt')`, que Gradle 9 rechaza porque
  desactiva R8. El fork solo cambia esa línea por
  `proguard-android-optimize.txt`.

Se declara en `dependency_overrides` de `pubspec.yaml`. Si el paquete publica
una versión compatible, basta con borrar el `override` y la carpeta.

### La fuente Braille es obligatoria

`braille_text` dibuja el Braille pidiendo `fontFamily: 'Braille'`, **pero no
empaqueta ninguna fuente con ese nombre**. Sin declararla, el Braille se dibuja
como cuadros vacíos: eso era exactamente lo que hacía parecer que "el Braille no
funcionaba". `pubspec.yaml` registra `assets/fonts/BraillePoints.ttf` (DejaVu
Sans, licencia libre, cubre los 256 caracteres de U+2800–U+28FF) con esa
familia. Si algún día se cambia la fuente, hay que comprobar que sigue teniendo
el bloque Braille completo.

### Rotar la clave de Meshy

1. Genera una nueva en <https://www.meshy.ai/developers/keys>.
2. Actualiza el `--dart-define=MESHY_API_KEY=...` de tu CI o de tu comando
   local. El `.env` versionado no se toca: solo lleva el valor centinela.
3. La clave anterior se puede revocar desde el mismo panel. No hay que tocar
   ningún fichero del repositorio.

### Demo 100 % gratuita

Ya es el comportamiento por defecto: sin clave de Meshy, Lumina genera la pieza
en el dispositivo y no llama a ningún servicio.

Si prefieres mostrar una pieza tuya en lugar de una generada:

1. Copia tu `.glb` a `assets/models/` (el directorio ya está declarado como
   asset en `pubspec.yaml`).
2. Ábrelo con `Power3D.fromAsset('assets/models/tu_pieza.glb', ...)`, que es la
   tercera vía del visor además de `fromFile` y `fromNetwork`.

Para entregar el archivo al usuario, `ModelDownloadService` copia el asset a
disco con `rootBundle.load` y lo comparte con `share_plus`.

### Antes de publicar en las tiendas

- Sustituir la firma de debug de `android/app/build.gradle.kts` por una clave
  de release propia (hay un `TODO` en el fichero).
- Revisar que `applicationId` (`com.lumina.lumina`) es el definitivo.
- Comprobar que el `.env` del commit sigue llevando **solo** el valor centinela
  y que la clave real va por `--dart-define` en el pipeline.
- Verificar en un dispositivo Android real que la app instala y ofrece la
  medida manual.
- En iOS: ejecutar `pod install` y el build en un Mac, y rellenar la ficha de
  privacidad (la cámara y la galería se declaran en `Info.plist`).
- Repasar las reglas de `proguard-rules.pro` si se añaden dependencias nuevas
  que usen reflexión o JNI.

## Errores probables

1. **`getDefaultProguardFile('proguard-android.txt')` rechazado por Gradle 9** —
   ya resuelto con el fork de `flutter_inappwebview_android`. Si se quita el
   `dependency_overrides`, vuelve el fallo.
2. **La detección de manos no detecta nada** — suele ser formato de cámara.
   Lumina pide `ImageFormatGroup.yuv420` y descarta los fotogramas que no
   traigan los tres planos (Y, U, V). Comprueba en un dispositivo real: los
   emuladores rara vez tienen una cámara utilizable para MediaPipe.
3. **`hand_landmarker` no funciona en iOS** — es esperado: solo hay
   implementación Android. La app lo detecta en tiempo de ejecución y ofrece la
   medida a mano.
4. **El visor 3D sale en blanco** — `power3d` monta un WebView. En un
   dispositivo con WebView antiguo o sin WebView del sistema, Babylon.js no
   arranca. Actualiza Android System WebView.
5. **El Braille se ve como cuadros vacíos** — falta la fuente con glifos
   Braille. Comprueba que `assets/fonts/BraillePoints.ttf` existe y que la
   familia `Braille` sigue declarada en `pubspec.yaml` (ver mantenimiento).
   También ocurre si el texto normalizado queda vacío: en ese caso la pantalla
   avisa en lugar de dibujar una etiqueta en blanco.
6. **Error 401 de Meshy** — la clave no es válida. Es lo esperado con el valor
   centinela: la app genera en el dispositivo en ese caso.
7. **Error 402 de Meshy** — la cuenta no tiene plan o se agotaron los créditos.
   El mensaje de la app lo explica.
8. **`adb: failed to install ... app-debug.apk` al hacer `flutter run`** — el
   APK de debug pesa ~203 MiB porque lleva tres arquitecturas (`arm64-v8a`,
   `armeabi-v7a` y `x86_64`). Causas habituales, en orden de probabilidad:

   - **Almacenamiento insuficiente.** `INSTALL_FAILED_INSUFFICIENT_STORAGE`.
     El instalador necesita copiar el APK y luego extraerlo: con 203 MiB hacen
     falta ~500 MiB libres. Libera espacio o compila solo tu arquitectura:
     `flutter run --target-platform android-arm64` (el APK baja a ~133 MiB).
   - **Permiso de instalación por USB.** En Huawei/Honor y en Xiaomi/MIUI es
     obligatorio activarlo, o el sistema rechaza cualquier `adb install`.
     Ajustes -> Sistema -> Opciones de desarrollador -> *Instalar aplicaciones
     vía USB* (en MIUI además *Depuración USB (Ajustes de seguridad)*).
     También ayuda `adb install -r -d` y desinstalar antes:
     `adb uninstall com.lumina.lumina`.
   - **Firma distinta.** Si ya había una copia instalada firmada con otra clave
     (por ejemplo, la de release), falla con `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
     Desinstala la anterior.

   El motivo exacto sale truncado en la consola de PowerShell. Para verlo
   entero, ejecuta el `adb` a mano:

   ```powershell
   adb install -r "build\app\outputs\flutter-apk\app-debug.apk"
   ```

   Si el mensaje sigue siendo escueto, estas órdenes dan el motivo real:

   ```powershell
   adb shell getprop ro.product.cpu.abi   # arquitectura: debe ser arm64-v8a
   adb shell df -h /data                  # espacio libre: hacen falta ~500 MiB
   adb install -r --no-streaming "build\app\outputs\flutter-apk\app-debug.apk"
   ```

   `--no-streaming` empuja el fichero y luego lo instala, en lugar de
   transmitirlo; en algunos dispositivos y cables USB el modo *streamed* se
   corta. Y para leer el rechazo del gestor de paquetes:

   ```powershell
   adb logcat -d | Select-String -Pattern "PackageManager.*(INSTALL|Failure)"
   ```

   En Huawei/Honor, además, *Instalar aplicaciones vía USB* exige tener sesión
   de cuenta Huawei e internet en el móvil; sin eso la opción no se queda
   activada aunque la marques.

9. **El primer `flutter build apk` tarda mucho** — Gradle descarga el NDK
   (~2 GB) y compila MediaPipe. Es normal la primera vez.
10. **`flutter build apk` se queda sin memoria** — MediaPipe es pesado.
    `android/gradle.properties` está ajustado a `-Xmx4G`; en una máquina con
    menos de 8 GB puede haber que bajarlo más.
11. **`No file or variants found for asset: .env`** — falta el fichero `.env`.
    Se versiona precisamente para que no pase; si lo has borrado, recupéralo
    con `git checkout -- .env`.
12. **`Could not close incremental caches in ... caches-jvm` en Windows** —
    el pub-cache está en una unidad distinta a la del proyecto (`D:\` y `C:\`).
    Kotlin guarda las rutas de sus cachés relativas a la raíz del proyecto, y
    entre discos distintos no existe ruta relativa. Ya está mitigado con
    `kotlin.incremental=false` en `android/gradle.properties`; ver la sección
    "Windows: el pub-cache en otra unidad" más abajo.

## Windows: el pub-cache en otra unidad

Si al compilar en Windows aparece este error, es que el pub-cache y el proyecto
están en discos distintos:

```
java.lang.IllegalArgumentException: this and base files have different roots:
D:\.pub-cache\hosted\pub.dev\google_maps_flutter_android-2.21.0\...\Messages.kt
and C:\Users\...\ilumina\android
```

El proyecto ya lo mitiga con `kotlin.incremental=false`, así que compila tal
cual. Si además quieres recuperar la compilación incremental (builds más
rápidos), mueve el pub-cache a la misma unidad que el proyecto:

```powershell
# PowerShell: mover el pub-cache a la unidad C
$env:PUB_CACHE = "C:\pub-cache"
setx PUB_CACHE "C:\pub-cache"          # para que sea permanente
flutter clean
flutter pub get
```

Para dejarlo fijo en el proyecto sin depender de variables de entorno, añade a
`android/gradle.properties` la ruta explícita, o declara `PUB_CACHE` en el
entorno antes de abrir el IDE. Tras moverlo hay que volver a ejecutar
`flutter pub get` para que las dependencias se descarguen en la nueva ubicación.

Si prefieres conservar el pub-cache donde está, deja `kotlin.incremental=false`:
el APK es idéntico, solo cambia el tiempo de compilación.

## Dependencias que debo instalar

Todas se resuelven con `flutter pub get`, incluidos los dos forks locales
(están en el repositorio). Para compilar Android hacen falta además, fuera de
Dart: **JDK 17+**, **Android SDK 36** y **NDK 28.2.13676358**. Para iOS: macOS,
Xcode y CocoaPods.

## Configuración nativa pendiente

- **iOS**: `pod install` y el build en Xcode, en un Mac. No verificable aquí.
- **Android**: la firma de release (hay un `TODO` con la configuración de
  debug). Todo lo demás ya está aplicado y probado.
- **Clave de Meshy para producción**: el `.env` versionado solo trae el valor
  centinela; hay que pasar la real con `--dart-define` al compilar.

## Paquetes que pueden no estar disponibles y su alternativa

| Paquete | Riesgo | Alternativa |
| --- | --- | --- |
| `flutter_inappwebview_android` | Su config de release rompe con Gradle 9 | Fork local ya incluido. Alternativa de más calado: sustituir `power3d` por `model_viewer_plus` o `flutter_cube` |
| `hand_landmarker` | Solo Android, mantenimiento irregular | `google_mlkit_pose_detection` (multiplataforma) o `mediapipe_flutter`; el adaptador `hand_detector.dart` ya aísla el paquete |
| `power3d` | Monta un WebView (Babylon.js); en WebViews antiguos no arranca | `model_viewer_plus` o `flutter_cube`; el visor está aislado en `visor_modelo_screen.dart` |
| `accessibility_widget` | 0.0.2, versión inicial | El panel propio de Lumina cubre botones grandes, pictogramas y dislexia sin él; solo se perderían la saturación y el escalado fino de espaciados |
| `braille_text` | 0.0.1 | `BrailleConverter` es una tabla Unicode: se puede reimplementar en ~50 líneas si el paquete desaparece |
| Meshy AI | API de pago | El generador local ya cubre el caso de uso sin coste; para IA hay que sustituir `meshy_service.dart` por otro servicio text-to-3D |

## Fragmentos marcados `[VERIFICAR]`

No queda ningún `[VERIFICAR]` en el código: las dos marcas que había eran de la
medición AR, que se retiró. Lo que **sí** necesita hardware real y no se puede
comprobar con `flutter test` (el entorno de este repositorio no tiene cámara ni
WebView):

1. **Detección de manos** (`hand_landmarker` + `CameraController`): requiere un
   Android con cámara. Lo que sí está cubierto por pruebas es el cálculo de
   distancias y la calibración (`HandMetrics`), que es código propio.
2. **Carga del `.glb` en `power3d`**: requiere el WebView de un dispositivo o
   emulador. Las pruebas validan que los bytes GLB y STL generados tienen
   cabecera y estructura correctas, que es la parte que Lumina controla.
3. **Trazo del Braille en pantalla**: la fuente ya está declarada y las pruebas
   cubren la conversión a Braille Unicode; el render final conviene verlo en un
   móvil.
