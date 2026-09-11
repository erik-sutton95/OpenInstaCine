plugins { alias(libs.plugins.android.application); alias(libs.plugins.kotlin.compose) }
android {
 namespace = "com.opencapture.openinstacine"
 compileSdk = 36
 defaultConfig { applicationId = "com.opencapture.openinstacine"; minSdk = 29; targetSdk = 36; versionCode = 1; versionName = "0.1.0"; ndk { abiFilters += "arm64-v8a" } }
 buildFeatures { compose = true; buildConfig = true }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
}
afterEvaluate { tasks.matching { it.name.startsWith("check") && it.name.endsWith("AarMetadata") }.configureEach { enabled = false } }
dependencies { implementation(project(":monitor")); implementation(project(":luna-adapter")); implementation(project(":core-api")); implementation(libs.kotlinx.coroutines.android) }
