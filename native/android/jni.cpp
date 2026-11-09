#include <jni.h>
#include <cstdint>
#include <cstring>
#include <string>
#include "../engine.h"

static std::string utf8(JNIEnv* env, jstring value) {
    jclass type = env->FindClass("java/lang/String");
    jmethodID getBytes = env->GetMethodID(type, "getBytes", "(Ljava/lang/String;)[B");
    jstring charset = env->NewStringUTF("UTF-8");
    auto bytes = static_cast<jbyteArray>(env->CallObjectMethod(value, getBytes, charset));
    std::string result;
    if (bytes) {
        result.resize(env->GetArrayLength(bytes));
        env->GetByteArrayRegion(bytes, 0, result.size(), reinterpret_cast<jbyte*>(result.data()));
        env->DeleteLocalRef(bytes);
    }
    env->DeleteLocalRef(charset); env->DeleteLocalRef(type);
    return result;
}

// Calls are serialized on the Android torrent executor, never the UI thread.
extern "C" JNIEXPORT jlong JNICALL
Java_local_freescene_freescene_TorrentNative_create(JNIEnv* env, jobject, jstring config) {
    const auto text = utf8(env, config);
    if (env->ExceptionCheck()) return 0;
    auto* engine = fs_engine_create(text.c_str());
    return static_cast<jlong>(reinterpret_cast<intptr_t>(engine));
}
extern "C" JNIEXPORT jstring JNICALL
Java_local_freescene_freescene_TorrentNative_command(JNIEnv* env, jobject, jlong handle, jstring request) {
    const auto text = utf8(env, request);
    if (env->ExceptionCheck()) return nullptr;
    char* reply = fs_engine_command(reinterpret_cast<void*>(static_cast<intptr_t>(handle)), text.c_str());
    // JSON emits UTF-8, whereas NewStringUTF expects modified UTF-8. Decode with
    // the Java String UTF-8 constructor so emoji/non-BMP release names survive.
    jbyteArray bytes = env->NewByteArray(static_cast<jsize>(strlen(reply)));
    env->SetByteArrayRegion(bytes, 0, env->GetArrayLength(bytes), reinterpret_cast<const jbyte*>(reply));
    fs_engine_free(reply);
    jclass stringClass = env->FindClass("java/lang/String");
    jmethodID constructor = env->GetMethodID(stringClass, "<init>", "([BLjava/lang/String;)V");
    jstring charset = env->NewStringUTF("UTF-8");
    auto result = static_cast<jstring>(env->NewObject(stringClass, constructor, bytes, charset));
    env->DeleteLocalRef(bytes); env->DeleteLocalRef(charset); env->DeleteLocalRef(stringClass);
    return result;
}
extern "C" JNIEXPORT void JNICALL
Java_local_freescene_freescene_TorrentNative_destroy(JNIEnv*, jobject, jlong handle) {
    fs_engine_destroy(reinterpret_cast<void*>(static_cast<intptr_t>(handle)));
}
