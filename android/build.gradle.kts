group = "com.trustsy.verify.flutter"
version = "0.2.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Where com.trustsy:trustsy-verify comes from. Added to EVERY project, the app
// included: the app resolves this plugin's dependency with its own
// repositories, so without this each app would have to repeat it.
// - `trustsyVerifyAndroidRepository` (android/gradle.properties, or
//   ORG_GRADLE_PROJECT_trustsyVerifyAndroidRepository): the Maven repository
//   that sdk/android's `publishReleasePublicationToTrustsyRepository` writes,
//   hosted (https://…) or on disk (a path, relative to the app's android/).
// - otherwise mavenLocal (`publishToMavenLocal` on this machine).
// Both serve the com.trustsy group only, so neither can stand in for any
// other dependency of the app.
val trustsyVerifyRepository = (
    rootProject.findProperty("trustsyVerifyAndroidRepository")
        ?: findProperty("trustsyVerifyAndroidRepository")
    )?.toString()?.trim()?.takeIf { it.isNotEmpty() }
    ?.let { if ("://" in it) uri(it) else rootProject.file(it).toURI() }

rootProject.allprojects {
    repositories {
        if (trustsyVerifyRepository != null) {
            maven {
                name = "trustsyVerify"
                url = trustsyVerifyRepository
                content { includeGroup("com.trustsy") }
            }
        } else {
            mavenLocal { content { includeGroup("com.trustsy") } }
        }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.trustsy.verify.flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Exports Compose UI and androidx.activity as API: the plugin instantiates
    // its TrustsyVerifyView without compiling any Compose itself.
    implementation("com.trustsy:trustsy-verify:0.2.0")
}
