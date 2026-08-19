# Suppress missing class warnings for unused ML Kit language packages
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.**
-dontwarn com.google_mlkit_text_recognition.**

-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }

-ignorewarnings

# Google Play Services / AdMob
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
