package com.localai.app.llm

/** llama.cpp + mtmd 推理引擎的 JNI 封装（对应 iOS 的 LlamaBridge）。 */
class LlamaEngine : AutoCloseable {

    fun interface TokenCallback {
        fun onToken(piece: String)
    }

    private var handle: Long = 0

    fun create() {
        if (handle != 0L) return
        handle = nativeCreate()
    }

    fun isCreated() = handle != 0L

    fun loadModel(
        modelPath: String,
        mmprojPath: String?,
        nCtx: Int,
        nGpuLayers: Int,
        nThreads: Int,
        loadMode: Int = 1,  // 1 = LLAMA_LOAD_MODE_MMAP, 0 = LLAMA_LOAD_MODE_NONE
    ): Boolean = nativeLoadModel(handle, modelPath, mmprojPath ?: "", nCtx, nGpuLayers, nThreads, loadMode)

    /** 返回 0 成功；非 0 用 lastError() 查看详情。callback 在调用线程同步回调。 */
    fun chat(
        messagesJson: String,
        settingsJson: String,
        imagePathsJson: String,
        callback: TokenCallback,
    ): Int = nativeChat(handle, messagesJson, settingsJson, imagePathsJson, callback)

    fun stop() {
        if (handle != 0L) nativeStop(handle)
    }

    fun lastError(): String =
        if (handle != 0L) nativeLastError(handle) else "engine not created"

    override fun close() {
        if (handle != 0L) {
            nativeFree(handle)
            handle = 0
        }
    }

    private external fun nativeCreate(): Long
    private external fun nativeLoadModel(
        h: Long, modelPath: String, mmprojPath: String,
        nCtx: Int, nGpuLayers: Int, nThreads: Int, loadMode: Int,
    ): Boolean
    private external fun nativeChat(
        h: Long, messagesJson: String, settingsJson: String,
        imagePathsJson: String, callback: TokenCallback,
    ): Int
    private external fun nativeStop(h: Long)
    private external fun nativeLastError(h: Long): String
    private external fun nativeFree(h: Long)

    companion object {
        init {
            System.loadLibrary("localai")
        }
    }
}
