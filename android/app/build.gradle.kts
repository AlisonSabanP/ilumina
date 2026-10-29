plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lumina.lumina"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lumina.lumina"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // `hand_landmarker` (MediaPipe) exige 24. Se fija explícitamente para
        // no depender del valor por defecto del SDK.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Aquí NO hay bloque `ndk { abiFilters }`, a propósito.
        //
        // Tenía uno, y era un error por dos motivos:
        //  1. No servía de nada: el plugin Gradle de Flutter sobrescribe
        //     `ndk.abiFilters` con la lista de ABI que se le pide compilar, así
        //     que el APK incluía `x86_64` igualmente.
        //  2. Rompía `--split-per-abi`: Gradle aborta con "Conflicting
        //     configuration ... in ndk abiFilters cannot be present when splits
        //     abi filters are set" porque no admite las dos cosas a la vez.
        //
        // La forma correcta de limitar las arquitecturas es la línea de
        // comandos: `--target-platform android-arm64` (un solo APK) o
        // `--split-per-abi` (un APK por arquitectura). No lo repongas.
    }

    buildTypes {
        release {
            // TODO: sustituir por tu propia configuración de firma antes de
            // publicar. Firmar con la clave de debug permite que
            // `flutter run --release` funcione en local.
            signingConfig = signingConfigs.getByName("debug")

            // R8 elimina y ofusca el código no usado. Las reglas de
            // `proguard-rules.pro` cubren MediaPipe y los puentes nativos/JS
            // de los plugins, que no son visibles al análisis estático de R8.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
