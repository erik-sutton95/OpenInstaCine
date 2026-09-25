plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

val supportedAndroidAbi = "arm64-v8a"
val swiftCoreJniLibsRoot = layout.buildDirectory.dir("generated/swiftCore/jniLibs")
val swiftCoreArm64Directory = swiftCoreJniLibsRoot.map { it.dir(supportedAndroidAbi) }
val repositoryRoot = rootProject.projectDir.parentFile.parentFile
val stageSwiftCoreScript = repositoryRoot.resolve("scripts/android-stage-swift-core.sh")

val resolvedVersionCode: Int =
    (findProperty("versionCode") ?: property("openpocketcine.versionCode")).toString().toInt()
val resolvedVersionName: String = property("openpocketcine.versionName").toString()

android {
    namespace = "com.opencapture.openpocketcine"
    compileSdk = 36

    defaultConfig {
        minSdk = 29
        buildConfigField("String", "VERSION_NAME", "\"$resolvedVersionName\"")
        buildConfigField("int", "VERSION_CODE", "$resolvedVersionCode")
        buildConfigField("String", "SOURCE_REVISION", "\"unknown\"")
        buildConfigField("String", "SENTRY_DSN_ANDROID", "\"\"")
        buildConfigField("String", "BUILD_IDENTITY", "\"unknown\"")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += supportedAndroidAbi
        }
        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_static"
            }
        }
    }

    ndkVersion = "28.2.13676358"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    sourceSets {
        getByName("main").jniLibs.directories.apply {
            clear()
            add(swiftCoreJniLibsRoot.get().asFile.absolutePath)
        }
    }
}

val stageSwiftCore =
    tasks.register<Exec>("stageSwiftCore") {
        group = "build"
        description = "Stage shared monitor media and assist Swift JNI for arm64-v8a."
        workingDir = repositoryRoot
        inputs.files(
            fileTree(repositoryRoot) {
                include("Package.swift", "Package.resolved", "Sources/**", "Adapters/OsmoCompatibility/Sources/**")
            },
            stageSwiftCoreScript,
        )
        inputs.property("swiftExecutable", providers.environmentVariable("SWIFT_EXECUTABLE").orElse("auto"))
        inputs.property(
            "swiftAndroidSdk",
            providers.environmentVariable("SWIFT_ANDROID_SDK_ID").orElse("swift-6.3.3-RELEASE_android"),
        )
        outputs.dir(swiftCoreArm64Directory)
        commandLine(
            "bash",
            stageSwiftCoreScript.absolutePath,
            "--output",
            swiftCoreArm64Directory.get().asFile.absolutePath,
        )
    }

tasks.named("preBuild").configure {
    dependsOn(stageSwiftCore)
}

// Compose BOM / androidx.core AARs currently declare compileSdk 37. Local and
// CI SDKs stay on 36 (same gate OpenZCine uses). Disable only the AAR metadata
// check so the rest of the AGP graph still runs.
afterEvaluate {
    tasks.matching { it.name.startsWith("check") && it.name.endsWith("AarMetadata") }
        .configureEach { enabled = false }
}

dependencies {
    api(project(":core-api"))
    api(project(":monitor-ui"))

    implementation(platform(libs.compose.bom))
    api(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.kyant.backdrop)
    implementation(libs.kyant.shapes)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.media3.common)
    implementation(libs.media3.effect)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)
    implementation(libs.okhttp)
    implementation(libs.mlkit.face.detection)
    implementation(libs.sentry.android)

    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation(libs.kotlin.test.junit)

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.json)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
}

// Existing dependency catalog asks for SDK 37, which is not in the installed SDK
// repository. Preserve the baseline SDK-36 metadata exemption. AGP 9.4's library
// lint bundler additionally requires the exempted check's output directory.
listOf("Debug", "Release").forEach { variant ->
    val marker = layout.buildDirectory.dir("intermediates/aar_metadata_check/${variant.lowercase()}/check${variant}AarMetadata")
    val prepare = tasks.register("prepare${variant}MetadataExemption") {
        outputs.dir(marker)
        doLast { marker.get().asFile.mkdirs() }
    }
    tasks.matching { it.name == "bundle${variant}LocalLintAar" }.configureEach { dependsOn(prepare) }
}
