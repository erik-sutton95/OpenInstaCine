plugins { alias(libs.plugins.android.application); alias(libs.plugins.kotlin.compose) }

// One product version for iOS and Android (docs/RELEASE.md). Play CI stamps -PversionCode;
// openpocketcine.versionCode in gradle.properties is the sideload floor. :monitor reads the same.
val resolvedVersionCode: Int =
    (findProperty("versionCode") ?: property("openpocketcine.versionCode")).toString().toInt()
val resolvedVersionName: String = property("openpocketcine.versionName").toString()

android {
 namespace = "com.opencapture.openinstacine"
 compileSdk = 36
 defaultConfig { applicationId = "com.opencapture.openinstacine"; minSdk = 29; targetSdk = 36; versionCode = resolvedVersionCode; versionName = resolvedVersionName; ndk { abiFilters += "arm64-v8a" } }

 // Play and sideload builds sign with the keystore named in the environment
 // (docs/android-play-ci.md, docs/RELEASE.md). Unset keeps debug and an unsigned release possible.
 val uploadKeystorePath = System.getenv("ANDROID_KEYSTORE_FILE").orEmpty()
 if (uploadKeystorePath.isNotEmpty()) {
  val uploadKeystore = file(uploadKeystorePath)
  require(uploadKeystore.isFile) { "ANDROID_KEYSTORE_FILE is set but not a file: $uploadKeystorePath" }
  signingConfigs {
   create("release") {
    storeFile = uploadKeystore
    storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
     ?: error("ANDROID_KEYSTORE_PASSWORD is required when ANDROID_KEYSTORE_FILE is set")
    keyAlias = System.getenv("ANDROID_KEY_ALIAS")
     ?: error("ANDROID_KEY_ALIAS is required when ANDROID_KEYSTORE_FILE is set")
    keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
     ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
     ?: error("ANDROID_KEY_PASSWORD is required when ANDROID_KEYSTORE_FILE is set")
   }
  }
 }

 buildTypes {
  // A distinct id and the "OpenInstaCine Dev" label (src/debug) install beside a Play or sideload build.
  debug { applicationIdSuffix = ".debug"; versionNameSuffix = "-debug" }
  release {
   // Minify stays off like OpenPocketCine: no mapping.txt, so Sentry needs only the native symbols.
   isMinifyEnabled = false
   if (uploadKeystorePath.isNotEmpty()) signingConfig = signingConfigs.getByName("release")
  }
 }
 buildFeatures { compose = true; buildConfig = true }
 sourceSets.getByName("main").assets.srcDir(rootProject.projectDir.resolve("../../Resources/CameraLUTs"))
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
}
afterEvaluate { tasks.matching { it.name.startsWith("check") && it.name.endsWith("AarMetadata") }.configureEach { enabled = false } }
dependencies { implementation(project(":monitor")); implementation(libs.opencine.insta360.luna); implementation("com.opencapture.opencine:camera-vocabulary:0.1.0-SNAPSHOT"); implementation(libs.kotlinx.coroutines.android) }
