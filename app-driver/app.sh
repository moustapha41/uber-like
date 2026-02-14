#!/bin/bash

# Fonction pour créer un dossier et un fichier vide
create_file() {
    local path="$1"
    local file="$2"
    mkdir -p "$path"
    if [[ "$file" != *.png && "$file" != *.jpg && "$file" != *.svg ]]; then
        touch "$path/$file"
    fi
}

# ---- ANDROID ----
create_file "android/app/src/debug" "AndroidManifest.xml"
create_file "android/app/src/main/java/io/flutter/plugins" "GeneratedPluginRegistrant.java"
create_file "android/app/src/main/kotlin/com/example/motoride" "MainActivity.kt"
create_file "android/app/src/main/kotlin/com/flutter_template/app" "MainActivity.kt"
create_file "android/app/src/main/res/drawable" "launch_background.xml"
create_file "android/app/src/main/res/drawable-v21" "launch_background.xml"
create_file "android/app/src/main/res/values" "styles.xml"
create_file "android/app/src/main/res/values-night" "styles.xml"
create_file "android/app/src/main" "AndroidManifest.xml"
create_file "android/app/src/profile" "AndroidManifest.xml"
create_file "android/app" "build.gradle.kts"
create_file "android/app" "proguard-rules.pro"
create_file "android/gradle/wrapper" "gradle-wrapper.properties"
create_file "android" ".gitignore"
create_file "android" "build.gradle.kts"
create_file "android" "gradle.properties"
create_file "android" "local.properties"
create_file "android" "settings.gradle.kts"

# ---- ASSETS ----
mkdir -p assets/images

# ---- IOS ----
create_file "ios/Flutter/ephemeral" "flutter_lldb_helper.py"
create_file "ios/Flutter/ephemeral" "flutter_lldbinit"
create_file "ios/Flutter" "AppFrameworkInfo.plist"
create_file "ios/Flutter" "Debug.xcconfig"
create_file "ios/Flutter" "flutter_export_environment.sh"
create_file "ios/Flutter" "Release.xcconfig"
create_file "ios/Runner/Base.lproj" "LaunchScreen.storyboard"
create_file "ios/Runner/Base.lproj" "Main.storyboard"
create_file "ios/Runner" "AppDelegate.swift"
create_file "ios/Runner" "GeneratedPluginRegistrant.h"
create_file "ios/Runner" "GeneratedPluginRegistrant.m"
create_file "ios/Runner" "Info.plist"
create_file "ios/Runner" "Runner-Bridging-Header.h"
create_file "ios/Runner.xcodeproj/project.pbxproj" ""
create_file "ios/Runner.xcodeproj/xcshareddata/IDEWorkspaceChecks.plist" ""
create_file "ios/Runner.xcodeproj/xcshareddata/WorkspaceSettings.xcsettings" ""
create_file "ios/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist" ""
create_file "ios/Runner.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings" ""
create_file "ios/RunnerTests" "RunnerTests.swift"
create_file "ios" ".gitignore"
create_file "ios" "Podfile"

# ---- LIB ----
create_file "lib/core" "app_export.dart"
create_file "lib/presentation/authentication_screen/widgets" "input_field_widget.dart"
create_file "lib/presentation/authentication_screen/widgets" "social_login_button_widget.dart"
create_file "lib/presentation/authentication_screen" "authentication_screen.dart"
create_file "lib/presentation/home_screen/widgets" "promotional_banner_widget.dart"
create_file "lib/presentation/home_screen/widgets" "recent_destination_chip_widget.dart"
create_file "lib/presentation/home_screen/widgets" "service_card_widget.dart"
create_file "lib/presentation/home_screen" "home_screen_initial_page.dart"
create_file "lib/presentation/home_screen" "home_screen.dart"
create_file "lib/presentation/splash_screen" "splash_screen.dart"
create_file "lib/routes" "app_routes.dart"
create_file "lib/theme" "app_theme.dart"
create_file "lib/widgets" "custom_bottom_bar.dart"
create_file "lib/widgets" "custom_error_widget.dart"
create_file "lib/widgets" "custom_icon_widget.dart"
create_file "lib/widgets" "custom_image_widget.dart"
create_file "lib" "main.dart"

# ---- WEB ----
create_file "web/icons" "Icon-192.png"      # Ignoré si tu veux pas créer d'image
create_file "web/icons" "Icon-512.png"      # Ignoré
create_file "web/icons" "Icon-maskable-192.png" # Ignoré
create_file "web/icons" "Icon-maskable-512.png" # Ignoré
create_file "web" "favicon.png"            # Ignoré
create_file "web" "flutter_plugins.js"
create_file "web" "index.html"
create_file "web" "manifest.json"

# ---- ROOT FILES ----
create_file "." ".gitignore"
create_file "." "analysis_options.yaml"
create_file "." "env.json"
create_file "." "pubspec.yaml"

echo "Structure de projet créée (images ignorées) ✅"
