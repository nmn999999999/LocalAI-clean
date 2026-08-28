// LlamaBridge.mm — self-contained llama.cpp + mtmd (multimodal) binding for LocalAI.
// Drop-in replacement for the LLM.swift engine. Verified against Qwen2.5-VL-3B.

#include "LlamaBridge.h"

#include <vector>
#include <string>
#include <cstring>
#include <random>
#include <algorithm>
#include <mutex>
#include <deque>
#include <sstream>

#include "llama.h"
#include "ggml.h"
#include "common.h"
#include "chat.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include "nlohmann/json.hpp"

using json = nlohmann::json;

struct llama_bridge {
    struct llama_model *       model = nullptr;
    struct llama_context *     ctx   = nullptr;
    const struct llama_vocab * vocab = nullptr;
    struct mtmd_context *      mctx  = nullptr;          // null when text-only
    common_chat_templates_ptr  tmpls = nullptr;
    bool                       use_jinja = false;

    int    n_threads = 4;
    int    n_batch   = 512;
    int    n_ctx     = 4096;   // 上下文窗口（token 容量），用于 prompt 超长护栏
    int    max_tokens = 512;
    float  temp = 0.8f;
    int    top_k = 40;
    float  top_p = 0.9f;

    std::string last_error;
    bool stop = false;

    llama_batch batch = {};

    // 采样随机数生成器（跨 token 复用，避免每 token 重置种子导致采样可预测）
    std::mt19937 rng{std::random_device{}()};

    // llama.cpp 日志捕获（便于把失败原因带回 UI）
    std::mutex              log_mutex;
    std::deque<std::string> log_lines;
};

static void bridge_log_callback(ggml_log_level level, const char * text, void * user_data) {
    llama_bridge * b = static_cast<llama_bridge *>(user_data);
    if (!b || !text) return;
    std::lock_guard<std::mutex> lock(b->log_mutex);
    b->log_lines.push_back(std::string(text));
    while (b->log_lines.size() > 80) b->log_lines.pop_front();
}

static void set_error(llama_bridge * b, const std::string & msg) {
    if (b) b->last_error = msg;
}

// 错误信息附加最近一段 llama.cpp 日志，帮助定位失败原因
static std::string with_log(llama_bridge * b, const std::string & msg) {
    std::string full = msg;
    std::lock_guard<std::mutex> lock(b->log_mutex);
    if (!b->log_lines.empty()) {
        full += "\n--- llama 日志 ---\n";
        size_t start = b->log_lines.size() > 24 ? b->log_lines.size() - 24 : 0;
        for (size_t i = start; i < b->log_lines.size(); i++) {
            full += b->log_lines[i];
        }
    }
    return full;
}

// 拼接提示词模式：不使用模型内嵌 chat template(jinja)，直接按 "role: content" 拼接。
// 对缺少模板或模板解析异常的模型更通用，行为可控。
static std::string build_concat_prompt(const std::vector<common_chat_msg> & msgs) {
    std::ostringstream ss;
    for (const auto & m : msgs) {
        std::string role = m.role.empty() ? "user" : m.role;
        if (role == "tool") { role = "assistant"; } // 工具结果归为 assistant 上下文，使模型理解"这是补充信息"
        // 去掉内容里已有的重复前缀，避免 "user: user: xxx"
        std::string content = m.content;
        std::string prefix = role + ": ";
        if (content.rfind(prefix, 0) == 0) { content = content.substr(prefix.size()); }
        ss << role << ": " << content << "\n";
    }
    ss << "assistant:";
    return ss.str();
}

int llama_bridge_create(llama_bridge ** out_bridge) {
    *out_bridge = new llama_bridge();
    return 0;
}

void llama_bridge_free(llama_bridge * b) {
    if (!b) return;
    if (b->mctx)  mtmd_free(b->mctx);
    if (b->ctx)   {
        llama_batch_free(b->batch);
        llama_free(b->ctx);
    }
    if (b->model) llama_model_free(b->model);
    delete b;
}

bool llama_bridge_load_model(llama_bridge * b,
                             const char * model_path,
                             const char * mmproj_path,
                             int n_ctx,
                             int n_gpu_layers,
                             int n_threads) {
    if (!b) return false;
    b->n_threads = n_threads > 0 ? n_threads : 4;
    llama_log_set(bridge_log_callback, b);
    {
        std::lock_guard<std::mutex> lock(b->log_mutex);
        b->log_lines.clear();
    }

    struct llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = n_gpu_layers;
    b->model = llama_model_load_from_file(model_path, mparams);
    if (!b->model) {
        set_error(b, with_log(b, std::string("无法加载模型: ") + (model_path ? model_path : "")));
        return false;
    }

    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = n_ctx > 0 ? (uint32_t)n_ctx : 4096;
    b->n_ctx = (int)cparams.n_ctx;   // 记录真实窗口，供后续护栏使用
    cparams.n_threads = b->n_threads;
    cparams.n_threads_batch = b->n_threads;
    // Metal 后端上 Flash Attention 的稳定性问题：先关闭，换取可靠解码
    cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
    b->ctx = llama_init_from_model(b->model, cparams);
    if (!b->ctx) {
        set_error(b, with_log(b, "无法初始化上下文"));
        return false;
    }
    b->vocab = llama_model_get_vocab(b->model);
    // llama.cpp 新版 (>= b4xxx) 的 llama_batch_init 分配的是固定大小数组，
    // 必须在分配时预留足够的 token 槽位（最大为整个 context），否则
    // common_batch_add 会在第二个 token 处触发 "llama_batch size exceeded" 断言崩溃。
    b->batch = llama_batch_init((int32_t)cparams.n_ctx, 0, 1);

    // chat template（拼接模式不依赖它；无模板的模型也可用，只是不参与 prompt 构造）
    b->tmpls = common_chat_templates_init(b->model, "");

    // optional multimodal projector
    if (mmproj_path && strlen(mmproj_path) > 0) {
        struct mtmd_context_params mparams2 = mtmd_context_params_default();
        mparams2.n_threads = b->n_threads;
        // mmproj 视觉编码器放 CPU，避免与主模型争抢 iPhone 有限的 GPU/统一内存
        mparams2.use_gpu   = false;
        b->mctx = mtmd_init_from_file(mmproj_path, b->model, mparams2);
        if (!b->mctx) {
            set_error(b, std::string("无法加载 mmproj: ") + mmproj_path);
            return false;
        }
        if (!mtmd_helper_model_can_chat(b->ctx, b->mctx)) {
            set_error(b, "该 mmproj 不支持对话模式");
            return false;
        }
    }
    b->last_error.clear();
    return true;
}

const char * llama_bridge_last_error(llama_bridge * b) {
    return b ? b->last_error.c_str() : "null bridge";
}

void llama_bridge_stop(llama_bridge * b) {
    if (b) b->stop = true;
}

// ---- sampling (temperature + top-k + top-p) ----
static llama_token sample_token(llama_bridge * b, float * logits) {
    const int n_vocab = llama_vocab_n_tokens(b->vocab);
    std::vector<float> scores(n_vocab);
    for (int i = 0; i < n_vocab; i++) scores[i] = logits[i];

    if (b->temp > 0.0f) {
        for (int i = 0; i < n_vocab; i++) scores[i] /= b->temp;
    }

    int top_k = b->top_k > 0 ? b->top_k : n_vocab;
    std::vector<int> idx(n_vocab);
    for (int i = 0; i < n_vocab; i++) idx[i] = i;
    std::partial_sort(idx.begin(), idx.begin() + std::min(top_k, n_vocab), idx.end(),
        [&](int a, int c) { return scores[a] > scores[c]; });

    float max_l = scores[idx[0]];
    float sum = 0.0f;
    std::vector<float> probs(top_k);
    for (int i = 0; i < top_k; i++) {
        probs[i] = expf(scores[idx[i]] - max_l);
        sum += probs[i];
    }
    if (sum <= 0.0f) return (llama_token)idx[0];

    // top-p nucleus
    float cum = 0.0f;
    int chosen = 0;
    std::uniform_real_distribution<float> dist(0.0f, 1.0f);
    float r = dist(b->rng) * sum;
    for (int i = 0; i < top_k; i++) {
        cum += probs[i];
        if (cum >= r * b->top_p) { chosen = i; break; }
        chosen = i;
    }
    return (llama_token)idx[chosen];
}

// ---- text-only path (no mmproj): tokenize + decode + generate ----
// 返回 llama_decode 的返回码（0 = 成功）
static int eval_tokens(llama_bridge * b, const std::vector<llama_token> & toks, bool logits_last) {
    // 防御：batch 容量 = n_ctx，绝不允许超出，否则 common_batch_add 触发越界断言/abort。
    const size_t cap = (b->n_ctx > 0) ? (size_t)b->n_ctx : toks.size();
    const size_t n   = std::min(toks.size(), cap);
    common_batch_clear(b->batch);
    for (size_t i = 0; i < n; i++) {
        common_batch_add(b->batch, toks[i], (llama_pos)i, {0}, logits_last && (i + 1 == n));
    }
    return llama_decode(b->ctx, b->batch);
}

static int generate(llama_bridge * b, int n_past_start, void (*cb)(const char *, void *), void * ud) {
    int n_past = n_past_start;
    int max_tokens = b->max_tokens > 0 ? b->max_tokens : 512;
    std::vector<llama_token> gen;
    for (int i = 0; i < max_tokens; i++) {
        if (b->stop) break; // 用户点击停止
        float * logits = llama_get_logits(b->ctx);
        llama_token token = sample_token(b, logits);
        if (llama_vocab_is_eog(b->vocab, token)) break;
        std::string piece = common_token_to_piece(b->ctx, token);
        if (!piece.empty() && cb) {
            // common_token_to_piece 返回的已是合法 UTF-8，直接转发；
            // 非法字节由 Swift 端 String(cString:encoding:) 兜底处理，不在此破坏多字节字符
            cb(piece.c_str(), ud);
        }
        common_batch_clear(b->batch);
        common_batch_add(b->batch, token, n_past, {0}, true);
        int rc = llama_decode(b->ctx, b->batch);
        if (rc != 0) {
            set_error(b, with_log(b, "生成解码失败 (ret=" + std::to_string(rc) + ")"));
            return 1;
        }
        n_past++;
    }
    return 0;
}

// ---- main chat entry ----
int llama_bridge_chat(llama_bridge * b,
                      const char * messages_json,
                      const char * settings_json,
                      const char * image_paths_json,
                      void (* token_cb)(const char * piece, void * userdata),
                      void * userdata) {
    if (!b || !b->model || !b->ctx) {
        set_error(b, "模型尚未加载");
        return 1;
    }
    b->stop = false; // 新一轮生成，重置停止标志
    // 桥接为无状态：每轮都重新编码完整历史，因此必须清空 KV cache，
    // 否则多轮对话时位置不连续会触发 "inconsistent sequence positions" 解码失败。
    llama_memory_clear(llama_get_memory(b->ctx), true);
    if (!b->tmpls) {
        set_error(b, "chat template 未初始化");
        return 1;
    }

    // settings
    try {
        json s = json::parse(std::string(settings_json ? settings_json : "{}"));
        if (s.contains("temp"))      b->temp = s["temp"].get<float>();
        if (s.contains("top_k"))     b->top_k = s["top_k"].get<int>();
        if (s.contains("top_p"))     b->top_p = s["top_p"].get<float>();
        if (s.contains("max_tokens")) b->max_tokens = s["max_tokens"].get<int>();
    } catch (...) {}

    // messages
    std::vector<common_chat_msg> all;
    try {
        json m = json::parse(std::string(messages_json ? messages_json : "[]"));
        for (auto & e : m) {
            common_chat_msg cm;
            cm.role    = e.value("role", std::string("user"));
            cm.content = e.value("content", std::string(""));
            all.push_back(cm);
        }
    } catch (...) {
        set_error(b, "messages_json 解析失败");
        return 2;
    }
    if (all.empty()) {
        set_error(b, "messages 为空");
        return 2;
    }

    // images
    std::vector<std::string> img_paths;
    try {
        json p = json::parse(std::string(image_paths_json ? image_paths_json : "[]"));
        for (auto & e : p) img_paths.push_back(e.get<std::string>());
    } catch (...) {}

    // history 仅用于决定是否在 tokenize 时加 BOS；模板格式化使用完整消息列表 all
    std::vector<common_chat_msg> history(all.begin(), all.end() - 1);
    bool add_bos = history.empty();

    std::string marker;
    if (b->mctx) marker = mtmd_get_marker(b->mctx);

    // inject media markers into the new user message
    if (b->mctx && !img_paths.empty()) {
        std::string injected;
        for (size_t i = 0; i < img_paths.size(); i++) injected += marker + "\n";
        all.back().content = injected + all.back().content;
    }

    // 优先用模型自带的 chat template（效果最好）；无模板模型才回退到拼接模式
    // 注意：必须用 common_chat_templates_apply 格式化【完整】历史，
    // common_chat_format_single 只返回增量 diff（依赖 KV cache 保留历史），
    // 与本实现的每轮 KV 清理策略不兼容，会导致多轮上下文丢失。
    std::string formatted;
    if (b->tmpls) {
        common_chat_templates_inputs inputs;
        inputs.messages = all;
        inputs.add_generation_prompt = true;
        inputs.use_jinja = b->use_jinja;
        formatted = common_chat_templates_apply(b->tmpls.get(), inputs).prompt;
    } else {
        formatted = build_concat_prompt(all);
    }

    // ----- multimodal path -----
    if (b->mctx) {
        mtmd::bitmaps bitmaps;
        for (auto & p : img_paths) {
            auto res = mtmd_helper_bitmap_init_from_file(b->mctx, p.c_str(), false);
            if (res.bitmap) bitmaps.entries.emplace_back(res.bitmap);
        }
        auto bitmap_ptrs = bitmaps.c_ptr();

        mtmd_input_text text;
        text.text          = formatted.data();
        text.text_len      = formatted.size();
        text.add_special   = add_bos;
        text.parse_special = true;

        mtmd::input_chunks chunks(mtmd_input_chunks_init());
        int32_t res = mtmd_tokenize(b->mctx, chunks.ptr.get(), &text,
                                    bitmap_ptrs.data(), bitmap_ptrs.size());
        if (res != 0) {
            set_error(b, with_log(b, std::string("mtmd_tokenize 失败, res=") + std::to_string(res)));
            return 3;
        }

        int n_past = 0;
        size_t n_chunks = mtmd_input_chunks_size(chunks.ptr.get());
        mtmd::batch_ptr mbatch;
        for (size_t i = 0; i < n_chunks; i++) {
            auto chunk = mtmd_input_chunks_get(chunks.ptr.get(), i);
            auto ctype = mtmd_input_chunk_get_type(chunk);
            if (ctype == MTMD_INPUT_CHUNK_TYPE_TEXT) {
                llama_pos new_n_past = n_past;
                res = mtmd_helper_eval_chunk_single(b->mctx, b->ctx, chunk, n_past, 0,
                                                    b->n_batch, i == n_chunks - 1, &new_n_past);
                if (res != 0) { set_error(b, with_log(b, "文本块解码失败 (ret=" + std::to_string(res) + ")")); return 4; }
                n_past = new_n_past;
            } else {
                float * embd = nullptr;
                if (mbatch) embd = mtmd_batch_get_output_embd(mbatch.get(), chunk);
                if (!embd) {
                    mbatch.reset(mtmd_batch_init(b->mctx));
                    int r = mtmd_batch_add_chunk(mbatch.get(), chunk);
                    if (r != 0) { set_error(b, "batch add 失败"); return 4; }
                    for (size_t j = i + 1; j < n_chunks; j++) {
                        auto nx = mtmd_input_chunks_get(chunks.ptr.get(), j);
                        if (mtmd_input_chunk_get_type(nx) == MTMD_INPUT_CHUNK_TYPE_TEXT) break;
                        if (mtmd_batch_add_chunk(mbatch.get(), nx) != 0) break;
                    }
                    if (mtmd_batch_encode(mbatch.get()) != 0) { set_error(b, "batch encode 失败"); return 4; }
                    embd = mtmd_batch_get_output_embd(mbatch.get(), chunk);
                }
                if (!embd) { set_error(b, "无法获取图像 embedding"); return 4; }
                llama_pos new_n_past = n_past;
                res = mtmd_helper_decode_image_chunk(b->mctx, b->ctx, chunk, embd, n_past, 0,
                                                     b->n_batch, &new_n_past, nullptr, nullptr);
                if (res != 0) { set_error(b, "图像块解码失败"); return 4; }
                n_past = new_n_past;
            }
        }
        int gret = generate(b, n_past, token_cb, userdata);
        if (gret != 0) return 6;
        return 0;
    }

    // ----- text-only path -----
    std::vector<llama_token> toks = common_tokenize(b->ctx, formatted, add_bos, true);
    // 护栏：prompt 的 token 数不得超过上下文窗口，否则 common_batch_add 越界触发 abort。
    // 超出时丢弃最旧的 token、保留最近的上下文（本桥为无状态，每轮重编码完整历史）。
    if (b->n_ctx > 0 && (int)toks.size() > b->n_ctx) {
        toks.erase(toks.begin(), toks.end() - b->n_ctx);
    }
    int rc = eval_tokens(b, toks, true);
    if (rc != 0) {
        set_error(b, with_log(b, "prompt 解码失败 (ret=" + std::to_string(rc) + ")"));
        return 5;
    }
    int gret = generate(b, (int)toks.size(), token_cb, userdata);
    if (gret != 0) return 6;
    return 0;
}
