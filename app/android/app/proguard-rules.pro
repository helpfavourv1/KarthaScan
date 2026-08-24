# --- FLUTTER CORE PROTECTIONS (REQUIRED) ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# --- ML KIT & TEXT RECOGNITION (MERGED) ---
# Suppress missing class warnings for unused ML Kit language packages
-dontwarn com.google.mlkit.**
-dontwarn com.google_mlkit_text_recognition.**

-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }

-ignorewarnings

# --- GOOGLE PLAY SERVICES / ADMOB ---
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# --- IMAGE CROPPER (UCROP) ---
-keep class com.yalantis.ucrop.** { *; }
