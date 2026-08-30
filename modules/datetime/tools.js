// 时间日期工具模块 —— 纯计算示例

function pad(n) { return n < 10 ? "0" + n : "" + n; }

function formatDate(d, fmt) {
  var map = {
    YYYY: d.getFullYear(),
    MM: pad(d.getMonth() + 1),
    DD: pad(d.getDate()),
    HH: pad(d.getHours()),
    mm: pad(d.getMinutes()),
    ss: pad(d.getSeconds())
  };
  var out = fmt || "YYYY-MM-DD HH:mm:ss";
  for (var k in map) { out = out.split(k).join(map[k]); }
  return out;
}

registerTool({
  name: "js_now",
  description: "当前日期时间（格式化）",
  parameters: {
    format: { type: "string", description: "格式，支持 YYYY/MM/DD/HH/mm/ss，默认 YYYY-MM-DD HH:mm:ss" }
  },
  run: function (args) {
    return formatDate(new Date(), String(args.format || ""));
  }
});

registerTool({
  name: "js_unix_ts",
  description: "当前 Unix 时间戳（秒）",
  parameters: {},
  run: function () {
    return String(Math.floor(Date.now() / 1000));
  }
});

registerTool({
  name: "js_date_format",
  description: "把日期字符串（YYYY-MM-DD 或 ISO）格式化为指定格式",
  parameters: {
    date: { type: "string", description: "日期字符串" },
    format: { type: "string", description: "目标格式，如 YYYY年MM月DD日" }
  },
  run: function (args) {
    var d = new Date(String(args.date || ""));
    if (isNaN(d.getTime())) return "无法解析日期: " + args.date;
    return formatDate(d, String(args.format || ""));
  }
});

registerTool({
  name: "js_days_between",
  description: "两个日期相差的天数",
  parameters: {
    from: { type: "string", description: "起始日期 YYYY-MM-DD" },
    to: { type: "string", description: "结束日期 YYYY-MM-DD" }
  },
  run: function (args) {
    var a = new Date(String(args.from || ""));
    var b = new Date(String(args.to || ""));
    if (isNaN(a.getTime()) || isNaN(b.getTime())) return "日期格式无效";
    var days = Math.round((b - a) / 86400000);
    return String(days) + " 天";
  }
});
