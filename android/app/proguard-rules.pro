# Flutter release enables R8 minify by default. Keep SAF + file_picker so
# Obsidian vault tree pick / persistable URI grants keep working.

-keep class com.jvoltci.saf.** { *; }
-keepclassmembers class com.jvoltci.saf.** { *; }

-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keepclassmembers class com.mr.flutter.plugin.filepicker.** { *; }

# Document providers / URI helpers used via reflection in some OEM builds.
-keep class androidx.documentfile.provider.** { *; }
