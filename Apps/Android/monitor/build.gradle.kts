import java.util.Properties

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
    (findProperty("versionCode") ?: property("openinstacine.versionCode")).toString().toInt()
val resolvedVersionName: String = property("openinstacine.versionName").toString()

android {
    namespace = "com.opencapture.openinstacine.monitor"
    compileSdk = 36

    defaultConfig {
        minSdk = 29
        consumerProguardFiles("proguard-rules.pro")
        buildConfigField("String", "VERSION_NAME", "\"$resolvedVersionName\"")
        buildConfigField("int", "VERSION_CODE", "$resolvedVersionCode")
        buildConfigField("String", "SOURCE_REVISION", "\"unknown\"")
        buildConfigField("String", "SENTRY_DSN_ANDROID", "\"\"")
        buildConfigField("String", "BUILD_IDENTITY", "\"unknown\"")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += supportedAndroidAbi
        }
    }

    ndkVersion = "28.2.13676358"

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

// Ported from OpenPocketCine app/build.gradle.kts. The monitor code reads this module's
// BuildConfig, so the release wiring lives here, not in :app. Contract: docs/sentry-deployment.md
val sourceRevisionField =
    providers.exec {
        workingDir = repositoryRoot
        commandLine("git", "rev-parse", "--short=12", "HEAD")
        isIgnoreExitValue = true
    }.standardOutput.asText
        .zip(
            providers.exec {
                workingDir = repositoryRoot
                commandLine("git", "status", "--porcelain")
                isIgnoreExitValue = true
            }.standardOutput.asText,
        ) { rev, status ->
            val envRev =
                System.getenv("OPENPOCKETCINE_SOURCE_REVISION")
                    ?: System.getenv("GITHUB_SHA")?.take(12)
            val cleaned =
                (envRev ?: rev.trim())
                    .filter { it.isLetterOrDigit() || it == '.' || it == '-' || it == '_' }
                    .ifEmpty { "unknown" }
            val dirty =
                status.isNotBlank() || System.getenv("OPENPOCKETCINE_SOURCE_DIRTY") == "1"
            val value = if (dirty) "$cleaned+" else cleaned
            com.android.build.api.variant.BuildConfigField("String", "\"$value\"", "git source revision")
        }

// Non-empty SENTRY_DSN_ANDROID wins; otherwise the ignored repo-root .local/reliability.properties.
val sentryDsnAndroidField =
    providers.environmentVariable("SENTRY_DSN_ANDROID")
        .orElse("")
        .zip(
            providers.of(LocalReliabilityDsnValueSource::class.java) {
                parameters.propertiesFile.set(
                    repositoryRoot.resolve(".local/reliability.properties"),
                )
            },
        ) { env, file ->
            val raw = env.trim().ifEmpty { file.trim() }
            val escaped = raw.replace("\\", "\\\\").replace("\"", "\\\"")
            com.android.build.api.variant.BuildConfigField(
                "String",
                "\"$escaped\"",
                "optional Sentry Android DSN",
            )
        }

// Windows CPython installs put `python` on PATH and no `python3`. `PYTHON` overrides both.
val pythonExecutable: Provider<String> =
    providers.environmentVariable("PYTHON").orElse(
        providers.systemProperty("os.name").map { osName ->
            if (osName.startsWith("Windows", ignoreCase = true)) "python" else "python3"
        }
    )

androidComponents {
    onVariants { variant ->
        variant.buildConfigFields?.put("SOURCE_REVISION", sourceRevisionField)
        variant.buildConfigFields?.put("SENTRY_DSN_ANDROID", sentryDsnAndroidField)
        val identity = providers.exec {
            workingDir = repositoryRoot
            commandLine(
                pythonExecutable.get(), repositoryRoot.resolve("tools/build-identity.py").absolutePath,
                "--platform", "android", "--configuration",
                "${variant.name}-$resolvedVersionName-$resolvedVersionCode-${gradle.gradleVersion}",
            )
        }.standardOutput.asText.map { value ->
            com.android.build.api.variant.BuildConfigField(
                "String", "\"${value.trim()}\"", "content identity of build inputs",
            )
        }
        variant.buildConfigFields?.put("BUILD_IDENTITY", identity)
    }
}

val stageSwiftCore =
    tasks.register<Exec>("stageSwiftCore") {
        group = "build"
        description = "Stage shared monitor media and assist Swift JNI for arm64-v8a."
        workingDir = repositoryRoot
        inputs.files(
            fileTree(repositoryRoot) {
                include("Package.swift", "Package.resolved", "Sources/**")
            },
            // OpenCineMedia, OpenCineMotion, OpenCineRelay (and OpenCineCore, which they depend on): the root
            // Package.swift takes them from the sibling OpenCine checkout.
            fileTree(repositoryRoot.resolve("../OpenCine")) {
                include(
                    "Package.swift",
                    "Sources/OpenCineMedia/**",
                    "Sources/OpenCineMotion/**",
                    "Sources/OpenCineRelay/**",
                    "Sources/MonitorPresentation/**",
                    "Sources/OpenCineCameraVocabulary/**",
                    "Sources/OpenCineCore/**",
                    "Sources/OpenCineJNISupport/**",
                    "Sources/OpenCineJNI/**",
                    "scripts/android-stage-swift-core.sh",
                )
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
    // Insta360 shell contract (CameraBackend, controls, media, values); brings OpenCineCore core.
    api(libs.opencine.insta360.shell)
    // The Luna session's layout projection and host-derived timecode (SHELL-01).
    implementation(libs.opencine.insta360.luna)
    // Cameras and pairing pages, the connection model and the saved-camera store (SHELL-02).
    implementation(libs.opencine.appkit)
    // Capture sheets, live chrome and gimbal views over the camera vocabulary (camera-controls).
    implementation("com.opencapture.opencine:camera-controls:0.1.0-SNAPSHOT")
    api(libs.opencine.monitor.ui)
    implementation("com.opencapture.opencine:media:0.1.0-SNAPSHOT")
    implementation("com.opencapture.opencine:camera-vocabulary:0.1.0-SNAPSHOT")
    implementation("com.opencapture.opencine:native-runtime:0.1.0-SNAPSHOT")
    implementation("com.opencapture.opencine:platform:0.1.0-SNAPSHOT")
    // Live-view MediaCodec decoder (HevcDecoder), shared with OpenPocketCine.
    implementation("com.opencapture.opencine:decoder:0.1.0-SNAPSHOT")
    // libopc_vulkan.so and its JNI facade (feed.OpcVulkan), built by OpenCineCore's `:vulkan` module.
    implementation("com.opencapture.opencine:vulkan:0.1.0-SNAPSHOT")

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
    androidTestImplementation(testFixtures("com.opencapture.opencine:core:0.1.0-SNAPSHOT"))

    testImplementation(libs.kotlin.test.junit)
    // Original cross-source calibration fixtures select DJI explicitly in tests only.
    testImplementation("com.opencapture.opencine:dji:0.1.0-SNAPSHOT")
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
    tasks.matching { it.name == "bundle${variant}LocalLintAar" || it.name == "bundle${variant}Aar" }
        .configureEach { dependsOn(prepare) }
}

abstract class LocalReliabilityDsnValueSource :
    ValueSource<String, LocalReliabilityDsnValueSource.Params> {
    interface Params : ValueSourceParameters {
        @get:org.gradle.api.tasks.Optional
        @get:InputFile
        @get:PathSensitive(PathSensitivity.NONE)
        val propertiesFile: RegularFileProperty
    }

    override fun obtain(): String {
        val file = parameters.propertiesFile.orNull?.asFile ?: return ""
        if (!file.isFile) return ""
        val props = Properties()
        file.inputStream().use { props.load(it) }
        return props.getProperty("SENTRY_DSN_ANDROID")?.trim().orEmpty()
    }
}
