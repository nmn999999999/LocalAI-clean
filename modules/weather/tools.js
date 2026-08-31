// 天气查询模块 —— 演示 nativeFetch 网络桥（需 network 权限）
registerTool({
  name: "js_weather",
  description: "查询指定城市的实时天气（温度/体感/湿度/天气描述）",
  parameters: {
    city: { type: "string", description: "城市名，如 北京 / London" }
  },
  run: async function (args) {
    var city = String(args.city || "").trim() || String(storeGet('default_city') || "").trim();
    if (!city) return "请提供城市名";
    var url = "https://wttr.in/" + encodeURIComponent(city) + "?format=j1";
    var body = await nativeFetch(url);
    var data = JSON.parse(body);
    var cur = data.current_condition && data.current_condition[0];
    if (!cur) return "未获取到 " + city + " 的天气数据";
    var desc = (cur.weatherDesc && cur.weatherDesc[0] && cur.weatherDesc[0].value) || "未知";
    return [
      city + " 当前天气：",
      "温度: " + cur.temp_C + "°C（体感 " + cur.feelslike_C + "°C）",
      "天气: " + desc,
      "湿度: " + cur.humidity + "%",
      "风速: " + cur.windspeedKmph + " km/h"
    ].join("\n");
  }
});
