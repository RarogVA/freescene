# Media3 loads the optional renderer by name. Keep JNI method/class names as well.
-keep class androidx.media3.decoder.ffmpeg.** { *; }

# Older WebViews call this bounded progress endpoint by its JavaScript name.
-keepclassmembers class local.freescene.freescene.WebPlaybackProgress {
    @android.webkit.JavascriptInterface public void postMessage(java.lang.String);
}
