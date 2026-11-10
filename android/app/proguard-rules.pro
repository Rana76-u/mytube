# DL2.2 — R8/ProGuard keep rules for the extraction engine.
#
# The release build runs R8 (minification/shrinking is active for release),
# so these rules keep the youtubedl-android engine's reflection entry points
# and stop R8 from failing on transitive classes that are not present on
# Android.
#
# youtubedl-android drives yt-dlp as a bundled Python subprocess and reaches
# its Java/Kotlin classes reflectively; R8 must not rename or remove them.

-keep class com.yausername.youtubedl_android_ytdlp.** { *; }
-keep class com.yausername.parser.** { *; }
-dontwarn com.yausername.**

# Transitive deps of the extraction engine that reference classes absent from
# Android. These are only touched reflectively/optionally (Apache Commons
# Compress 7zip -> org.tukaani.xz; Jackson DOM serializer ->
# org.w3c.dom.bootstrap), so tell R8 not to treat their absence as an error.
# See build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn org.tukaani.xz.**
-dontwarn org.w3c.dom.bootstrap.**

# FFmpeg / aria2c native wrapper entry points loaded from the engine.
-keep class * implements java.io.Serializable { *; }
