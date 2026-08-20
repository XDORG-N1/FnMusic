pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 使用可达镜像：google() → dl.google.com/dl/android/maven2，
        // mavenCentral() → repo1.maven.org/maven2，gradlePluginPortal() → plugins.gradle.org/m2。
        maven { url = uri("https://dl.google.com/dl/android/maven2") }
        maven { url = uri("https://repo1.maven.org/maven2") }
        maven { url = uri("https://plugins.gradle.org/m2") }
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        maven { url = uri("https://dl.google.com/dl/android/maven2") }
        maven { url = uri("https://repo1.maven.org/maven2") }
        maven { url = uri("https://plugins.gradle.org/m2") }
        // Flutter 引擎构件仓库（PREFER_SETTINGS 模式下需显式声明）
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // 本机 Gradle 发行版为 9.2.0（缓存），AGP 9.0.0 与其兼容；
    // AGP 9.1.0 需要 Gradle >= 9.3.1（服务端不可达）。
    id("com.android.application") version "9.0.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
