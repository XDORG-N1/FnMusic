plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fnmusic.app"
    // Flutter 3.47 插件生态（connectivity_plus/dynamic_color 等）要求 compileSdk 36；
    // minSdk/targetSdk 仍为 35（Android 15+）。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // 开启 core library desugaring（参考项目同款配置）
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.fnmusic.app"
        // 仅支持 Android 15+（API 35）
        minSdk = 35
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: 配置正式签名（当前用 debug 签名便于调试构建）
            signingConfig = signingConfigs.getByName("debug")
            // 与参考项目一致：关闭 R8/资源压缩（体积主要由原生库构成）
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Shizuku（灵动岛焦点通知白名单绕过）
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}
