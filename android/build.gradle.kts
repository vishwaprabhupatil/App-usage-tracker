import com.android.build.gradle.LibraryExtension
import org.gradle.kotlin.dsl.configure

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    // Work around old plugins that don't set `namespace` (required by newer AGP).
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            if (project.name == "device_apps" && namespace == null) {
                namespace = "fr.g123k.deviceapps"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
