// 颜色工具模块 —— 纯计算示例
function hexToRgb(hex) {
  var h = String(hex || "").replace("#", "");
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
  if (!/^[0-9a-fA-F]{6}$/.test(h)) return null;
  return { r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16), b: parseInt(h.slice(4, 6), 16) };
}
function rgbToHex(r, g, b) {
  return "#" + [r, g, b].map(function (v) { return ("0" + Math.max(0, Math.min(255, Math.round(v))).toString(16)).slice(-2); }).join("");
}
function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  var max = Math.max(r, g, b), min = Math.min(r, g, b);
  var h = 0, s = 0, l = (max + min) / 2;
  if (max !== min) {
    var d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    else if (max === g) h = ((b - r) / d + 2) / 6;
    else h = ((r - g) / d + 4) / 6;
  }
  return { h: Math.round(h * 360), s: Math.round(s * 100), l: Math.round(l * 100) };
}

registerTool({
  name: "js_color_convert",
  description: "颜色格式互转：HEX → RGB/HSL",
  parameters: {
    hex: { type: "string", description: "HEX 颜色，如 #4285F4" }
  },
  run: function (args) {
    var rgb = hexToRgb(String(args.hex || ""));
    if (!rgb) return "无效的 HEX 颜色";
    var hsl = rgbToHsl(rgb.r, rgb.g, rgb.b);
    return "HEX " + rgbToHex(rgb.r, rgb.g, rgb.b) + "\nRGB(" + rgb.r + ", " + rgb.g + ", " + rgb.b + ")\nHSL(" + hsl.h + "°, " + hsl.s + "%, " + hsl.l + "%)";
  }
});

registerTool({
  name: "js_color_lighten",
  description: "调亮/调暗颜色（percentage 正数调亮，负数调暗）",
  parameters: {
    hex: { type: "string", description: "HEX 颜色" },
    percentage: { type: "number", description: "调整百分比，如 20 或 -20" }
  },
  run: function (args) {
    var rgb = hexToRgb(String(args.hex || ""));
    if (!rgb) return "无效的 HEX 颜色";
    var pct = Number(args.percentage) || 0;
    var f = 1 + pct / 100;
    return rgbToHex(rgb.r * f, rgb.g * f, rgb.b * f);
  }
});
