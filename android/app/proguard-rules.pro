# Lumina — reglas de R8/ProGuard para el APK/AAB de release.
#
# Todo lo que hay aquí responde a un aviso real de la compilación de release;
# no son reglas "por si acaso".

# --- Puentes nativos de los plugins de Flutter --------------------------------
# Los plugins se registran por reflexión desde `GeneratedPluginRegistrant`, así
# que R8 no debe eliminarlos ni renombrarlos.
-keep class io.flutter.plugins.** { *; }

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
