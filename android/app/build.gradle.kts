plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val repoRoot = rootProject.projectDir.parentFile
val generatedSharedResDir = layout.buildDirectory.dir("generated/res/sharedCards")

val prepareSharedCardDrawables by tasks.registering(Copy::class) {
    from(File(repoRoot, "resources/front")) {
        include("*.png")
        eachFile { name = name.lowercase() }
    }
    from(File(repoRoot, "resources/back")) {
        include("back.png")
        rename("back.png", "card_back.png")
    }
    into(generatedSharedResDir.map { it.dir("drawable") })
}

android {
    namespace = "window_german_drinking_game.com"
    compileSdk {
        version = release(36)
    }

    defaultConfig {
        applicationId = "window_german_drinking_game.com"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
    }

    sourceSets {
        getByName("main") {
            res.srcDir(generatedSharedResDir)
        }
    }
}

tasks.named("preBuild") {
    dependsOn(prepareSharedCardDrawables)
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.database)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
