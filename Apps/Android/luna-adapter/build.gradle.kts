plugins { alias(libs.plugins.android.library) }
android {
 namespace = "com.opencapture.openinstacine.luna"; compileSdk = 36
 defaultConfig { minSdk = 29 }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
}
afterEvaluate { tasks.matching { it.name.startsWith("check") && it.name.endsWith("AarMetadata") }.configureEach { enabled = false } }
dependencies { implementation(project(":core-api")); implementation(libs.kotlinx.coroutines.android); testImplementation(libs.kotlin.test.junit) }

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
