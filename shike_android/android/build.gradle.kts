import com.android.build.api.variant.LibraryAndroidComponentsExtension

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Compile all Android plugins against our installed, pinned SDK. Older plugin
// defaults otherwise start slow automatic downloads of additional platforms.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<LibraryAndroidComponentsExtension> {
            finalizeDsl {
                it.compileSdk = 36
                it.buildToolsVersion = "36.0.0"
            }
        }
    }
}
