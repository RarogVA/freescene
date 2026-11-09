import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "local.freescene.freescene"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "local.freescene.freescene"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "device"
    productFlavors {
        create("mobile") { dimension = "device" }
        create("tv") {
            dimension = "device"
            applicationIdSuffix = ".tv"
        }
    }
    sourceSets.getByName("main").jniLibs.srcDir("../../build/android-engine/jniLibs")
    sourceSets.getByName("main").jniLibs.srcDir("../../build/android-audio/jniLibs")
    sourceSets.getByName("main").java.srcDir("../../build/android-audio/java")
    buildFeatures { buildConfig = true }
    testOptions { unitTests.isIncludeAndroidResources = true }
    val signingFile = rootProject.file("key.properties")
    val releaseKeys = Properties()
    if (signingFile.isFile) {
        signingFile.inputStream().use { releaseKeys.load(it) }
        signingConfigs.create("distribution") {
            storeFile = file(releaseKeys.getProperty("storeFile"))
            storePassword = releaseKeys.getProperty("storePassword")
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            // No silent production signing with a debug certificate.
            signingConfig = if (providers.gradleProperty("localPreview").orNull == "true") signingConfigs.getByName("debug")
                else if (signingFile.isFile) signingConfigs.getByName("distribution")
                else null
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles("proguard-rules.pro")
        }
    }
}

dependencies {
    compileOnly("org.checkerframework:checker-qual:3.43.0")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("androidx.webkit:webkit:1.17.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// AGP 9 host tests package resources; Flutter's asset-copy task must finish first.
tasks.configureEach {
    val variant = Regex("package(.+)UnitTestForUnitTest").matchEntire(name)?.groupValues?.get(1)
    if (variant != null) dependsOn("copyFlutterAssets$variant")
}
