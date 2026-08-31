import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La clé de signature d'IDIAMA Agro. Elle vit hors du projet
// (C:/Users/bassi/cles/idiama-agro.jks) et ne doit JAMAIS être régénérée :
// sans elle, aucune mise à jour de l'application ne peut être installée
// par-dessus la précédente.
val proprietesCle = Properties()
val fichierCle = rootProject.file("key.properties")
if (fichierCle.exists()) {
    proprietesCle.load(FileInputStream(fichierCle))
}

android {
    namespace = "com.idiama.idiama_agro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.idiama.agro"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("livraison") {
            if (proprietesCle.getProperty("storeFile") != null) {
                keyAlias = proprietesCle.getProperty("keyAlias")
                keyPassword = proprietesCle.getProperty("keyPassword")
                storeFile = file(proprietesCle.getProperty("storeFile"))
                storePassword = proprietesCle.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (proprietesCle.getProperty("storeFile") != null) {
                signingConfigs.getByName("livraison")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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
