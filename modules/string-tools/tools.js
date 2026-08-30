// 字符串工具包 —— 示例 JS 插件模块
// 纯计算沙箱：无网络/无文件访问；registerTool 注册后自动加入 Agent 工具目录。

registerTool({
  name: "js_reverse",
  description: "反转字符串（支持 Unicode）",
  parameters: {
    text: { type: "string", description: "要反转的文本" }
  },
  run: function (args) {
    var text = String(args.text || "");
    var chars = Array.from(text);
    return chars.reverse().join("");
  }
});

registerTool({
  name: "js_rot13",
  description: "ROT13 字母移位加密（A-Z/a-z 移位 13 位）",
  parameters: {
    text: { type: "string", description: "要加密的文本" }
  },
  run: function (args) {
    var text = String(args.text || "");
    return text.replace(/[a-zA-Z]/g, function (c) {
      var base = c <= "Z" ? 65 : 97;
      return String.fromCharCode((c.charCodeAt(0) - base + 13) % 26 + base);
    });
  }
});

registerTool({
  name: "js_word_count",
  description: "统计文本词频，返回出现最多的前 N 个词",
  parameters: {
    text: { type: "string", description: "要分析的文本" },
    top: { type: "number", description: "返回前几个词（默认 5）" }
  },
  run: function (args) {
    var text = String(args.text || "");
    var top = Math.max(1, Math.min(20, Number(args.top) || 5));
    var words = text.toLowerCase().match(/[a-z0-9\u4e00-\u9fa5]+/g) || [];
    var freq = {};
    for (var i = 0; i < words.length; i++) {
      freq[words[i]] = (freq[words[i]] || 0) + 1;
    }
    var sorted = Object.keys(freq).sort(function (a, b) { return freq[b] - freq[a]; }).slice(0, top);
    return sorted.map(function (w) { return w + ": " + freq[w]; }).join("\n");
  }
});

registerTool({
  name: "js_palindrome",
  description: "判断文本是否回文（忽略大小写与空白标点）",
  parameters: {
    text: { type: "string", description: "要检测的文本" }
  },
  run: function (args) {
    var text = String(args.text || "").toLowerCase().replace(/[^a-z0-9\u4e00-\u9fa5]/g, "");
    var rev = Array.from(text).reverse().join("");
    return "「" + String(args.text || "") + "」" + (text === rev && text.length > 0 ? "是回文" : "不是回文");
  }
});
