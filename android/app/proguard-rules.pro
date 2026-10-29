# Lumina — reglas de R8/ProGuard para el APK/AAB de release.
#
# Todo lo que hay aquí responde a un aviso real de la compilación de release;
# no son reglas "por si acaso".

# --- Sceneform (dependencia de `arcore_flutter_plugin`) -----------------------
# Sceneform 1.17.1 referencia clases opcionales que no publica en Maven:
# `animation.*` (solo existe en la variante "filament-android" completa),
# `assets.Loader` y `assets.ModelData` (módulo `sceneform:assets` no incluido) y
# `com.google.devtools.build.android.desugar.runtime.ThrowableExtension` (solo
# presente si se compila con desugaring de API < 24). R8 las trata como
# "missing classes" y aborta; el código que las usa nunca se ejecuta en el
# camino de medición de Lumina (`ArSceneView` + `AnchorNode`), así que basta con
# silenciar el aviso.
-dontwarn com.google.ar.sceneform.**
-dontwarn com.google.ar.core.**

# Mantener el motor de render y las factorías por reflexión de Sceneform.
-keep class com.google.ar.sceneform.** { *; }
-keep class com.google.ar.core.** { *; }

# --- Puentes nativos de los plugins de Flutter --------------------------------
# Los plugins se registran por reflexión desde `GeneratedPluginRegistrant`, así
# que R8 no debe eliminarlos ni renombrarlos.
-keep class io.flutter.plugins.** { *; }
-keep class com.difrancescogianmarco.arcore_flutter_plugin.** { *; }

# MediaPipe (`hand_landmarker`) carga sus tareas por JNI: los nombres de clase
# que aparecen en las firmas nativas no se pueden ofuscar.
-keep class com.google.mediapipe.** { *; }
-keep class dev.fluttermediapipe.** { *; }

# --- WebView de `power3d` (flutter_inappwebview) ------------------------------
# El puente JavaScript <-> Dart se resuelve por nombre de método.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }
