# DL2.2 — R8/ProGuard keep rules for the extraction engine.
#
# Minification is currently OFF in the release build type (the DL2 acceptance
# gate is `flutter build apk --debug`, which never runs R8). These rules are
# wired through `proguardFiles` so that enabling `isMinifyEnabled = true` later
# does not strip the youtubedl-android engine's reflection entry points.
#
# youtubedl-android drives yt-dlp as a bundled Python subprocess and reaches
# its Java/Kotlin classes reflectively; R8 must not rename or remove them.

-keep class com.yausername.youtubedl_android_ytdlp.** { *; }
-keep class com.yausername.parser.** { *; }
-dontwarn com.yausername.**

# FFmpeg / aria2c native wrapper entry points loaded from the engine.
-keep class * implements java.io.Serializable { *; }
