pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "OpenInstaCine"
include(":app", ":core-api", ":monitor", ":luna-adapter")

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
    }
}
