// 货币汇率模块 —— 演示 nativeFetch（open.er-api.com 免费、无需 key）
registerTool({
  name: "js_convert",
  description: "货币换算：amount 单位 from 货币 → to 货币（如 100 USD → CNY）",
  parameters: {
    amount: { type: "number", description: "金额" },
    from: { type: "string", description: "源货币代码，如 USD" },
    to: { type: "string", description: "目标货币代码，如 CNY" }
  },
  run: async function (args) {
    var amount = Number(args.amount);
    var from = String(args.from || "USD").toUpperCase();
    var to = String(args.to || "CNY").toUpperCase();
    if (!amount || amount <= 0) return "请输入有效金额";
    var body = await nativeFetch("https://open.er-api.com/v6/latest/" + encodeURIComponent(from));
    var data = JSON.parse(body);
    if (!data || data.result !== "success" || !data.rates) {
      return "汇率获取失败（请检查网络或货币代码，如 USD/CNY/EUR/JPY）";
    }
    var rate = data.rates[to];
    if (rate === undefined) return "不支持的货币代码: " + to;
    var result = amount * rate;
    return amount + " " + from + " = " + result.toFixed(2) + " " + to + "（1 " + from + " = " + rate + " " + to + "）";
  }
});
