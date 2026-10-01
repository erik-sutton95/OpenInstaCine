pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "OpenInstaCine"
include(":app", ":core-api", ":monitor", ":monitor-ui", ":luna-adapter")
// Candidate (OpenCineCore CORE-02): common camera contracts from a sibling checkout of
// OpenCineCore, pinned by SHA in opencine-pins.txt. Named because OpenCineUI's build is also
// called Android. Replace with the Maven coordinate once published.
includeBuild("../../../OpenCineCore/Android") {
    name = "opencinecore"
    dependencySubstitution {
        substitute(module("com.opencapture.opencine:core")).using(project(":core"))
    }
}
