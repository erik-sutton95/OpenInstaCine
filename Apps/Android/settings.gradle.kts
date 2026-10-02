pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "OpenInstaCine"
include(":app", ":monitor")

// Shared Compose UI from the sibling OpenCineUI checkout (candidate wiring
// until OpenCineUI publishes a release): ~/Work/OpenCineUI next to this repo.
includeBuild("../../../OpenCineUI/Android") {
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:monitor-ui")).using(project(":monitor-ui"))
    }
}
// Candidate (OpenCineCore CORE-02): common camera contracts from a sibling checkout of
// OpenCineCore, pinned by SHA in opencine-pins.txt. Named because OpenCineUI's build is also
// called Android. Replace with the Maven coordinate once published.
includeBuild("../../../OpenCineCore/Android") {
    name = "opencinecore"
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:core")).using(project(":core"))
        substitute(module("com.opencapture.opencine:media")).using(project(":media"))
        substitute(module("com.opencapture.opencine:vulkan")).using(project(":vulkan"))
    }
}
// Candidate (CORE-API): the Insta360 shell contract and the Kotlin Luna adapter from a sibling
// checkout of OpenCineInsta360, pinned by SHA in opencine-pins.txt. It includes ../OpenCineCore
// under the same name, so both resolve one Core build. Replace with Maven coordinates once published.
includeBuild("../../../OpenCineInsta360/Android") {
    name = "opencineinsta360"
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:insta360-shell")).using(project(":insta360-shell"))
        substitute(module("com.opencapture.opencine:insta360-luna")).using(project(":insta360-luna"))
    }
}
