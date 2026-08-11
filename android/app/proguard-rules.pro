# ProGuard rules for Radio Mix App
# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Dart and Flutter
-keep class dart.** { *; }

# Keep Audio Service
-keep class com.ryanheise.audioservice.** { *; }

# Keep Riverpod
-keep class * extends StateNotifier { *; }
-keep class * extends Notifier { *; }

# Keep models
-keep class com.example.radio_mix.models.** { *; }

# Prevent obfuscation of methods used by reflection
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# HTTP and networking
-keep class com.squareup.okhttp.** { *; }
-keep class com.squareup.okhttp3.** { *; }
-dontwarn com.squareup.okhttp.**
-dontwarn com.squareup.okhttp3.**

# XML parsing
-keep class org.xmlpull.v1.** { *; }
-dontwarn org.xmlpull.v1.**

# Audio session
-keep class com.ryanheise.audio_session.** { *; }

# Just Audio
-keep class com.ryanheise.just_audio.** { *; }

# General
-dontwarn android.**
-dontwarn java.**
-dontwarn javax.**
-dontwarn sun.**
-dontwarn com.google.**
