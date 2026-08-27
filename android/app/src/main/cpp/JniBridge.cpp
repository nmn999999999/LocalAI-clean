// JniBridge.cpp — 把 llama_bridge 的 C API 暴露为 JNI，供 Kotlin 调用。
#include <jni.h>
#include <string>
#include "LlamaBridge.h"

namespace {

// 回调上下文：把 C 字符串 token 转发到 Java 的 TokenCallback.onToken(String)
struct JniCallbackCtx {
    JNIEnv *   env;
    jobject    callback;   // global ref
    jmethodID  onToken;
};

void jni_token_cb(const char * piece, void * userdata) {
    auto * ctx = static_cast<JniCallbackCtx *>(userdata);
    if (!ctx || !ctx->env || !ctx->callback) return;
    jstring js = ctx->env->NewStringUTF(piece ? piece : "");
    if (js) {
        ctx->env->CallVoidMethod(ctx->callback, ctx->onToken, js);
        ctx->env->DeleteLocalRef(js);
    }
}

std::string jstring_to_string(JNIEnv * env, jstring js) {
    if (!js) return "";
    const char * chars = env->GetStringUTFChars(js, nullptr);
    std::string out = chars ? chars : "";
    if (chars) env->ReleaseStringUTFChars(js, chars);
    return out;
}

} // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_localai_app_llm_LlamaEngine_nativeCreate(JNIEnv *, jobject) {
    llama_bridge * b = nullptr;
    if (llama_bridge_create(&b) != 0) return 0;
    return reinterpret_cast<jlong>(b);
}

JNIEXPORT jboolean JNICALL
Java_com_localai_app_llm_LlamaEngine_nativeLoadModel(
        JNIEnv * env, jobject,
        jlong handle, jstring modelPath, jstring mmprojPath,
        jint nCtx, jint nGpuLayers, jint nThreads) {
    auto * b = reinterpret_cast<llama_bridge *>(handle);
    if (!b) return JNI_FALSE;
    std::string mp = jstring_to_string(env, modelPath);
    std::string mm = jstring_to_string(env, mmprojPath);
    bool ok = llama_bridge_load_model(b, mp.c_str(), mm.c_str(), nCtx, nGpuLayers, nThreads);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_localai_app_llm_LlamaEngine_nativeChat(
        JNIEnv * env, jobject,
        jlong handle, jstring messagesJson, jstring settingsJson,
        jstring imagePathsJson, jobject callback) {
    auto * b = reinterpret_cast<llama_bridge *>(handle);
    if (!b) return 1;

    std::string mj = jstring_to_string(env, messagesJson);
    std::string sj = jstring_to_string(env, settingsJson);
    std::string ij = jstring_to_string(env, imagePathsJson);

    jobject cbRef = callback ? env->NewGlobalRef(callback) : nullptr;
    if (!cbRef) return 1;
    jclass cls = env->GetObjectClass(cbRef);
    jmethodID onToken = env->GetMethodID(cls, "onToken", "(Ljava/lang/String;)V");
    env->DeleteLocalRef(cls);

    JniCallbackCtx ctx{ env, cbRef, onToken };
    int rc = llama_bridge_chat(b, mj.c_str(), sj.c_str(), ij.c_str(), jni_token_cb, &ctx);
    env->DeleteGlobalRef(cbRef);
    return rc;
}

JNIEXPORT void JNICALL
Java_com_localai_app_llm_LlamaEngine_nativeStop(JNIEnv *, jobject, jlong handle) {
    llama_bridge_stop(reinterpret_cast<llama_bridge *>(handle));
}

JNIEXPORT jstring JNICALL
Java_com_localai_app_llm_LlamaEngine_nativeLastError(JNIEnv * env, jobject, jlong handle) {
    const char * err = llama_bridge_last_error(reinterpret_cast<llama_bridge *>(handle));
    return env->NewStringUTF(err ? err : "");
}

JNIEXPORT void JNICALL
Java_com_localai_app_llm_LlamaEngine_nativeFree(JNIEnv *, jobject, jlong handle) {
    llama_bridge_free(reinterpret_cast<llama_bridge *>(handle));
}

} // extern "C"
