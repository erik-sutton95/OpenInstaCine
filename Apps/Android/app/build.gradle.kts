plugins { alias(libs.plugins.android.application); alias(libs.plugins.kotlin.compose) }

// One product version for iOS and Android (docs/RELEASE.md). Play CI stamps -PversionCode;
// openinstacine.versionCode in gradle.properties is the sideload floor. :monitor reads the same.
val resolvedVersionCode: Int =
    (findProperty("versionCode") ?: property("openinstacine.versionCode")).toString().toInt()
val resolvedVersionName: String = property("openinstacine.versionName").toString()

android {
 namespace = "com.opencapture.openinstacine"
 compileSdk = 36
 defaultConfig { testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"; applicationId = "com.opencapture.openinstacine"; minSdk = 29; targetSdk = 36; versionCode = resolvedVersionCode; versionName = resolvedVersionName; manifestPlaceholders["sentryProguardUuid"] = System.getenv("SENTRY_PROGUARD_UUID").orEmpty(); ndk { abiFilters += "arm64-v8a" } }

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
   isMinifyEnabled = true
   isShrinkResources = true
   proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
   if (uploadKeystorePath.isNotEmpty()) signingConfig = signingConfigs.getByName("release")
  }
 }
 buildFeatures { compose = true; buildConfig = true }
 sourceSets.getByName("main").assets.srcDir(rootProject.projectDir.resolve("../../Resources/CameraLUTs"))
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
}
afterEvaluate { tasks.matching { it.name.startsWith("check") && it.name.endsWith("AarMetadata") }.configureEach { enabled = false } }

// ML Kit instantiates its ComponentRegistrar classes reflectively; a shrunk bundle without their
// constructors crashes face detection (OPENINSTACINE-ANDROID-1). Every bundleRelease checks the dex.
val releaseBundle = layout.buildDirectory.file("outputs/bundle/release/app-release.aab")
val verifyReleaseComponentRegistrars = tasks.register<Exec>("verifyReleaseComponentRegistrars") {
 group = "verification"
 description = "Fail when R8 strips a ComponentRegistrar constructor from the release bundle."
 dependsOn("bundleRelease")
 inputs.file(releaseBundle)
 environment("ANDROID_HOME", androidComponents.sdkComponents.sdkDirectory.get().asFile.absolutePath)
 commandLine("bash", rootProject.projectDir.resolve("../../../OpenCine/scripts/android-verify-component-registrars.sh").absolutePath, releaseBundle.get().asFile.absolutePath)
}
tasks.matching { it.name == "bundleRelease" }.configureEach { finalizedBy(verifyReleaseComponentRegistrars) }
dependencies { androidTestImplementation("com.opencapture.opencine:app-ui-testing:0.1.0-SNAPSHOT"); implementation(project(":monitor")); implementation(libs.opencine.insta360.luna); implementation("com.opencapture.opencine:camera-vocabulary:0.1.0-SNAPSHOT"); implementation(libs.kotlinx.coroutines.android) }
