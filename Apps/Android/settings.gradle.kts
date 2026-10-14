// OpenCine's Gradle plugins (the reporting adapter's DSN), from the same sibling checkout.
pluginManagement { includeBuild("../../../OpenCine/Android/build-logic"); repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "OpenInstaCine"
include(":app", ":monitor")

// Candidate: the OpenCine platform build from a sibling checkout (~/Work/OpenCine next to this
// repository), pinned by SHA in opencine-pins.txt: shared Compose UI, common camera contracts,
// media policy, the Vulkan renderer, the Insta360 shell contract, the Kotlin Luna adapter and
// the shared cameras and pairing flow (appkit).
// Named because its directory is also called Android. Replace with Maven coordinates once
// published.
includeBuild("../../../OpenCine/Android") {
    name = "opencine"
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:core")).using(project(":core"))
        substitute(module("com.opencapture.opencine:media")).using(project(":media"))
        substitute(module("com.opencapture.opencine:camera-vocabulary")).using(project(":camera-vocabulary"))
        substitute(module("com.opencapture.opencine:native-runtime")).using(project(":native-runtime"))
        substitute(module("com.opencapture.opencine:platform")).using(project(":platform"))
        substitute(module("com.opencapture.opencine:decoder")).using(project(":decoder"))
        substitute(module("com.opencapture.opencine:dji")).using(project(":dji"))
        substitute(module("com.opencapture.opencine:vulkan")).using(project(":vulkan"))
        substitute(module("com.opencapture.opencine:monitor-ui")).using(project(":monitor-ui"))
        substitute(module("com.opencapture.opencine:insta360-shell")).using(project(":insta360-shell"))
        substitute(module("com.opencapture.opencine:insta360-luna")).using(project(":insta360-luna"))
        substitute(module("com.opencapture.opencine:appkit")).using(project(":appkit"))
        substitute(module("com.opencapture.opencine:appkit-sentry")).using(project(":appkit-sentry"))
        substitute(module("com.opencapture.opencine:camera-controls")).using(project(":camera-controls"))
        substitute(module("com.opencapture.opencine:app-ui-testing")).using(project(":app-ui-testing"))
    }
}
