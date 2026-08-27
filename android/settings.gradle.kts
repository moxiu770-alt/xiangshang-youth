pluginManagement {
    repositories {
        google()
        // repo.maven.apache.org occasionally rate-limits shared GitHub-hosted
        // runner IPs. repo1 is Maven Central's official alternate endpoint;
        // keep the Gradle shorthand as a fallback for local environments.
        maven(url = "https://repo1.maven.org/maven2/") {
            name = "MavenCentralOfficialAlternate"
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        maven(url = "https://repo1.maven.org/maven2/") {
            name = "MavenCentralOfficialAlternate"
        }
        mavenCentral()
    }
}
rootProject.name = "XiangshangYouth"
include(":app")
