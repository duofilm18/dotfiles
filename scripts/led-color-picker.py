#!/usr/bin/env python3
"""LED 狀態測試盤 - 點擊狀態即時預覽到 RPi5B LED

從 rpi5b/mqtt-led/led-effects.json 讀取所有定義的狀態，
點擊按鈕送語意 payload {domain, state, project} 到 MQTT。

啟動後開瀏覽器 http://localhost:8888

用法: python3 led-color-picker.py [mqtt_host] [mqtt_port]
"""

import json
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

MQTT_HOST = sys.argv[1] if len(sys.argv) > 1 else "192.168.88.10"
MQTT_PORT = sys.argv[2] if len(sys.argv) > 2 else "1883"

# 載入 led-effects.json
EFFECTS_PATH = Path(__file__).parent.parent / "rpi5b" / "mqtt-led" / "led-effects.json"
with open(EFFECTS_PATH) as f:
    EFFECTS = json.load(f)

# 生成按鈕 HTML
def build_buttons():
    buttons = []
    for domain, states in EFFECTS.items():
        if domain.startswith("_"):
            continue
        for state, effect in states.items():
            r = effect.get("r", 0)
            g = effect.get("g", 0)
            b = effect.get("b", 0)
            pattern = effect.get("pattern", "solid")
            # 文字色：深色背景用白字，淺色背景用黑字
            luma = r * 0.299 + g * 0.587 + b * 0.114
            fg = "#000" if luma > 128 else "#fff"
            # 特殊：全黑背景加邊框
            border = "#555" if r + g + b < 30 else f"rgb({r},{g},{b})"
            buttons.append(
                f'<button class="state-btn" '
                f'style="background:rgb({r},{g},{b});color:{fg};border-color:{border}" '
                f'onclick="send(\'{domain}\',\'{state}\')">'
                f'<span class="domain">{domain}</span>'
                f'<span class="state-name">{state}</span>'
                f'<span class="pattern">{pattern}</span>'
                f'<span class="rgb">({r},{g},{b})</span>'
                f'</button>'
            )
    return "\n    ".join(buttons)

HTML_PAGE = """<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>LED 狀態測試盤</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, sans-serif;
    background: #1a1a2e; color: #eee;
    display: flex; flex-direction: column; align-items: center;
    min-height: 100vh; padding: 20px;
  }
  h1 { margin-bottom: 8px; font-size: 1.5em; }
  .subtitle { color: #888; margin-bottom: 24px; font-size: 0.9em; }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: 12px; width: 100%; max-width: 720px;
  }
  .state-btn {
    padding: 16px 12px; border: 3px solid; border-radius: 12px;
    cursor: pointer; display: flex; flex-direction: column;
    align-items: center; gap: 4px; transition: transform 0.1s;
  }
  .state-btn:hover { transform: scale(1.05); }
  .state-btn:active { transform: scale(0.95); }
  .state-btn .domain { font-size: 0.7em; opacity: 0.7; text-transform: uppercase; }
  .state-btn .state-name { font-size: 1.3em; font-weight: bold; }
  .state-btn .pattern { font-size: 0.8em; opacity: 0.8; }
  .state-btn .rgb { font-size: 0.7em; opacity: 0.5; font-family: monospace; }
  .status {
    margin-top: 20px; padding: 12px 24px;
    background: #16213e; border-radius: 8px;
    font-family: monospace; font-size: 0.9em;
    min-height: 44px; display: flex; align-items: center;
  }
  .status.ok { border-left: 4px solid #4caf50; }
  .status.err { border-left: 4px solid #f44336; }
</style>
</head>
<body>
<h1>LED 狀態測試盤</h1>
<p class="subtitle">MQTT: MQTT_HOST_PLACEHOLDER:MQTT_PORT_PLACEHOLDER</p>
<div class="grid">
    BUTTONS_PLACEHOLDER
</div>
<div class="status" id="status">點擊按鈕測試 LED 狀態</div>
<script>
function send(domain, state) {
  const status = document.getElementById('status');
  status.textContent = `送出 ${domain}/${state}...`;
  status.className = 'status';
  fetch('/led', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({domain, state, project: 'test'})
  }).then(r => r.json()).then(d => {
    if (d.ok) {
      status.textContent = `${domain}/${state} — 已送出`;
      status.className = 'status ok';
    } else {
      status.textContent = `送出失敗: ${d.error || '未知'}`;
      status.className = 'status err';
    }
  }).catch(e => {
    status.textContent = '連線錯誤: ' + e;
    status.className = 'status err';
  });
}
</script>
</body>
</html>
""".replace("BUTTONS_PLACEHOLDER", build_buttons()) \
   .replace("MQTT_HOST_PLACEHOLDER", MQTT_HOST) \
   .replace("MQTT_PORT_PLACEHOLDER", MQTT_PORT)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(HTML_PAGE.encode())

    def do_POST(self):
        if self.path == "/led":
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length))
            try:
                subprocess.run(
                    ["mosquitto_pub", "-h", MQTT_HOST, "-p", MQTT_PORT,
                     "-t", "claude/led", "-m", json.dumps(data)],
                    timeout=3, capture_output=True,
                )
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"ok": True}).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"ok": False, "error": str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        if "POST" in str(args):
            super().log_message(format, *args)


if __name__ == "__main__":
    port = 8888
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"LED 狀態測試盤: http://localhost:{port}")
    print(f"MQTT: {MQTT_HOST}:{MQTT_PORT}")
    print(f"狀態來源: {EFFECTS_PATH}")
    domains = {d: len(s) for d, s in EFFECTS.items() if not d.startswith("_")}
    print(f"載入: {domains}")
    print("Ctrl+C 結束")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n結束")
