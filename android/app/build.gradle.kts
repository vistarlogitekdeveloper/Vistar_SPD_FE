import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vistarlogitek.spd_frontend"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vistarlogitek.spd_frontend"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    /* Release signing.

       This was the Flutter template default — `signingConfigs.getByName("debug")`
       — which signs the release APK with the generic `CN=Android Debug`
       certificate every SDK install shares. Two consequences, both of which
       cost a day: Play Protect distrusts sideloaded debug-signed apps on
       recent Android and blocks the install with nothing more than "App not
       installed"; and because the debug keystore is per-machine, an APK built
       on one laptop will not upgrade one built on another.

       The key now lives OUTSIDE this repository and its password in
       android/key.properties, which .gitignore covers. Neither is in git and
       neither should ever be: whoever holds them can publish an update that
       Android will install over this app without question.

       A missing key.properties falls back to debug signing rather than
       failing the build, so a fresh checkout still runs `flutter run
       --release` — it simply produces an APK that cannot be distributed. */
    val keyProps = Properties()
    val keyPropsFile = rootProject.file("key.properties")
    if (keyPropsFile.exists()) {
        keyPropsFile.inputStream().use { keyProps.load(it) }
    }

    signingConfigs {
        create("release") {
            if (keyPropsFile.exists()) {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyPropsFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
