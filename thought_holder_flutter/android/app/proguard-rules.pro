# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Play Core - Flutter references these for dynamic delivery but we don't use them.
# R8 fails without these dontwarn rules when Play Core library is absent.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.**

# SQLite / sqflite - uses reflection
-keep class com.tekartik.sqflite.** { *; }
-keep class org.sqlite.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Hive - uses reflection for type adapters
-keep class com.hivedb.** { *; }
-keepclassmembers class * extends com.hivedb.hive.HiveObject { *; }

# Google Sign-In
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.android.gms.**

# Google APIs / googleapis
-keep class com.google.api.** { *; }
-dontwarn com.google.api.**

# Keep all model classes (prevent R8 from stripping Map-based data)
-keepclassmembers class * {
    public <init>(android.content.Context);
}

# Dart/Flutter plugin reflection
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Prevent stripping of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# URL launcher
-keep class androidx.browser.** { *; }

# Speech to Text
-keep class com.csdcorp.speech_to_text.** { *; }

# BLE / universal_ble
-keep class com.example.universal_ble.** { *; }
-keep class android.bluetooth.** { *; }

# Suppress warnings for missing classes that are optional
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
