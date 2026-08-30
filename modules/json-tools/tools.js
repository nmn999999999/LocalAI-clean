// JSON 工具模块 —— 纯计算示例
registerTool({
  name: "js_json_format",
  description: "格式化 JSON 文本（缩进 2 空格）",
  parameters: {
    json: { type: "string", description: "JSON 文本" }
  },
  run: function (args) {
    try {
      return JSON.stringify(JSON.parse(String(args.json || "")), null, 2);
    } catch (e) {
      return "JSON 解析失败: " + e;
    }
  }
});

registerTool({
  name: "js_json_minify",
  description: "压缩 JSON 文本为单行",
  parameters: {
    json: { type: "string", description: "JSON 文本" }
  },
  run: function (args) {
    try {
      return JSON.stringify(JSON.parse(String(args.json || "")));
    } catch (e) {
      return "JSON 解析失败: " + e;
    }
  }
});

registerTool({
  name: "js_json_get",
  description: "按点路径取值，如 a.b[0].c",
  parameters: {
    json: { type: "string", description: "JSON 文本" },
    path: { type: "string", description: "点路径，支持 [下标]" }
  },
  run: function (args) {
    try {
      var obj = JSON.parse(String(args.json || ""));
      var path = String(args.path || "");
      var parts = path.replace(/\[(\d+)\]/g, ".$1").split(".").filter(function (p) { return p.length > 0; });
      var cur = obj;
      for (var i = 0; i < parts.length; i++) {
        if (cur === null || cur === undefined) return "路径不存在";
        cur = cur[parts[i]];
      }
      if (cur === undefined) return "路径不存在";
      return typeof cur === "object" ? JSON.stringify(cur, null, 2) : String(cur);
    } catch (e) {
      return "JSON 解析失败: " + e;
    }
  }
});
