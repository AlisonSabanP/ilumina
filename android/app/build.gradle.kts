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

        // MediaPipe (hand_landmarker) y el motor de Flutter traen bibliotecas
        // nativas muy grandes (el APK de debug pasa de 200 MiB).
        //
        // OJO: este filtro NO limita las ABI del APK final. El plugin Gradle de
        // Flutter sobrescribe `ndk.abiFilters` con la lista de ABI que se le
        // pide compilar, así que aquí siguen entrando `x86_64` y `armeabi-v7a`
        // aunque no estén declaradas. Para reducir el tamaño de verdad hay que
        // usar `--target-platform android-arm64` o `--split-per-abi` en la
        // línea de comandos. Se deja declarado porque documenta la intención y
        // sí afecta a los AAR de dependencias.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
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
