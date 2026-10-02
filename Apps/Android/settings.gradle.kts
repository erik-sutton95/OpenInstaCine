pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "OpenInstaCine"
include(":app", ":monitor")

// Candidate: the OpenCine platform build from a sibling checkout (~/Work/OpenCine next to this
// repository), pinned by SHA in opencine-pins.txt: shared Compose UI, common camera contracts,
// media policy, the Vulkan renderer, the Insta360 shell contract and the Kotlin Luna adapter.
// Named because its directory is also called Android. Replace with Maven coordinates once
// published.
includeBuild("../../../OpenCine/Android") {
    name = "opencine"
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:core")).using(project(":core"))
        substitute(module("com.opencapture.opencine:media")).using(project(":media"))
        substitute(module("com.opencapture.opencine:vulkan")).using(project(":vulkan"))
        substitute(module("com.opencapture.opencine:monitor-ui")).using(project(":monitor-ui"))
        substitute(module("com.opencapture.opencine:insta360-shell")).using(project(":insta360-shell"))
        substitute(module("com.opencapture.opencine:insta360-luna")).using(project(":insta360-luna"))
    }
}
