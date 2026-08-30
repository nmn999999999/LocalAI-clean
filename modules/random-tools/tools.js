// 随机工具模块 —— 纯计算示例
registerTool({
  name: "js_password",
  description: "生成随机强密码（可含大小写/数字/符号）",
  parameters: {
    length: { type: "number", description: "长度，默认 16" },
    symbols: { type: "boolean", description: "是否包含符号，默认 true" }
  },
  run: function (args) {
    var len = Math.max(8, Math.min(64, Number(args.length) || 16));
    var useSymbols = args.symbols !== false;
    var sets = ["abcdefghijkmnopqrstuvwxyz", "ABCDEFGHJKLMNPQRSTUVWXYZ", "23456789"];
    if (useSymbols) sets.push("!@#$%^&*()_+-=[]{};:,.<>?");
    var all = sets.join("");
    var out = "";
    // 保证每类至少一个
    for (var i = 0; i < sets.length; i++) out += sets[i][Math.floor(Math.random() * sets[i].length)];
    for (var i = out.length; i < len; i++) out += all[Math.floor(Math.random() * all.length)];
    return out;
  }
});

registerTool({
  name: "js_dice",
  description: "掷骰子（标准 D6，可掷多个）",
  parameters: {
    count: { type: "number", description: "骰子个数，默认 2" }
  },
  run: function (args) {
    var n = Math.max(1, Math.min(20, Number(args.count) || 2));
    var rolls = [];
    var sum = 0;
    for (var i = 0; i < n; i++) { var v = 1 + Math.floor(Math.random() * 6); rolls.push(v); sum += v; }
    return rolls.join(" + ") + " = " + sum + "（平均 " + (sum / n).toFixed(1) + "）";
  }
});

registerTool({
  name: "js_pick",
  description: "从列表中随机抽取一个（逗号或换行分隔）",
  parameters: {
    items: { type: "string", description: "用逗号/换行分隔的选项" }
  },
  run: function (args) {
    var items = String(args.items || "").split(/[,，\\n]/).map(function (s) { return s.trim(); }).filter(function (s) { return s.length > 0; });
    if (items.length === 0) return "没有可抽取的选项";
    return items[Math.floor(Math.random() * items.length)];
  }
});
