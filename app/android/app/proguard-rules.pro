# ===== Attributes needed by reflection / generics (Gson, plugins) =====
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*,Exceptions,SourceFile,LineNumberTable

# ===== Flutter engine and embedding =====
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
# Flutter's optional Play Store deferred-components classes (not used here).
-dontwarn com.google.android.play.core.**

# ===== This app's own native code =====
-keep class com.zdmgold.katharscan.** { *; }

# ===== flutter_local_notifications (reads/writes its saved schedule with Gson) =====
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ===== ML Kit text recognition (Latin, Chinese, Japanese, Korean) =====
-dontwarn com.google.mlkit.**
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }

# ===== Google Mobile Ads and consent (UMP) =====
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-keep class com.google.android.ump.** { *; }
-dontwarn com.google.android.ump.**

# ===== Google Play Billing (in_app_purchase) =====
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# ===== Image cropper (UCrop) and its OkHttp use =====
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**
-dontwarn okhttp3.**
-dontwarn okio.**

# ===== Native (JNI) classes: never rename or strip =====
-keepclasseswithmembernames class * { native <methods>; }

# ===== Plugin glue code (tiny; keeping it removes reflection/JNI risk) =====
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class com.incrediblezayed.file_saver.** { *; }
-keep class com.shirsh.flutter_doc_scanner.** { *; }
-keep class net.jonhanson.flutter_native_splash.** { *; }
-keep class net.wolverinebeach.flutter_timezone.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class vn.hunghd.flutter.plugins.imagecropper.** { *; }
-keep class dev.britannio.in_app_review.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class jp.espresso3389.pdf_render.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class net.nfet.flutter.printing.** { *; }
-keep class com.tekartik.sqflite.** { *; }
# Dart-to-Java bridge (jni / jnigen): Java classes are looked up by name.
-keep class com.github.dart_lang.** { *; }
-dontwarn com.github.dart_lang.**
