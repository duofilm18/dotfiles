#!/usr/bin/env python3
"""LED 即時調色盤 - 拖動顏色即時預覽到 RPi5B LED

啟動後開瀏覽器 http://localhost:8888
選色會即時透過 MQTT 送到 LED。

用法: python3 led-color-picker.py [mqtt_host] [mqtt_port]
"""

import json
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

MQTT_HOST = sys.argv[1] if len(sys.argv) > 1 else "192.168.88.10"
MQTT_PORT = sys.argv[2] if len(sys.argv) > 2 else "1883"

HTML_PAGE = """<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>LED 調色盤</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, sans-serif;
    background: #1a1a2e; color: #eee;
    display: flex; flex-direction: column; align-items: center;
    min-height: 100vh; padding: 20px;
  }
  h1 { margin-bottom: 20px; font-size: 1.5em; }

  .picker-area {
    display: flex; gap: 20px; flex-wrap: wrap; justify-content: center;
  }

  /* SV square */
  .sv-box {
    position: relative; width: 300px; height: 300px;
    border-radius: 8px; cursor: crosshair;
  }
  .sv-box .sat-overlay {
    position: absolute; inset: 0; border-radius: 8px;
    background: linear-gradient(to right, #fff, transparent);
  }
  .sv-box .val-overlay {
    position: absolute; inset: 0; border-radius: 8px;
    background: linear-gradient(to bottom, transparent, #000);
  }
  .sv-cursor {
    position: absolute; width: 16px; height: 16px;
    border: 2px solid #fff; border-radius: 50%;
    box-shadow: 0 0 4px rgba(0,0,0,0.5);
    transform: translate(-50%, -50%); pointer-events: none;
  }

  /* Hue bar */
  .hue-bar {
    width: 30px; height: 300px; border-radius: 8px; cursor: pointer;
    background: linear-gradient(to bottom,
      hsl(0,100%,50%), hsl(30,100%,50%), hsl(60,100%,50%),
      hsl(90,100%,50%), hsl(120,100%,50%), hsl(150,100%,50%),
      hsl(180,100%,50%), hsl(210,100%,50%), hsl(240,100%,50%),
      hsl(270,100%,50%), hsl(300,100%,50%), hsl(330,100%,50%),
      hsl(360,100%,50%));
    position: relative;
  }
  .hue-cursor {
    position: absolute; left: -4px; width: 38px; height: 6px;
    border: 2px solid #fff; border-radius: 3px;
    box-shadow: 0 0 4px rgba(0,0,0,0.5);
    transform: translateY(-50%); pointer-events: none;
  }

  /* Info panel */
  .info {
    margin-top: 24px; text-align: center;
  }
  .preview {
    width: 200px; height: 80px; border-radius: 12px;
    border: 3px solid #444; margin: 0 auto 16px;
  }
  .values {
    font-size: 1.8em; font-family: monospace; font-weight: bold;
    margin-bottom: 8px; user-select: all;
  }
  .values-small {
    font-size: 1em; color: #999; font-family: monospace;
    margin-bottom: 16px;
  }

  /* RGB sliders */
  .sliders { margin-top: 16px; width: 340px; }
  .slider-row {
    display: flex; align-items: center; gap: 10px; margin: 6px 0;
  }
  .slider-row label { width: 20px; font-weight: bold; font-size: 1.1em; }
  .slider-row input[type=range] { flex: 1; height: 8px; }
  .slider-row .val { width: 40px; text-align: right; font-family: monospace; }
  input.r { accent-color: #ff4444; }
  input.g { accent-color: #44ff44; }
  input.b { accent-color: #4444ff; }

  .status {
    margin-top: 12px; font-size: 0.85em; color: #666;
  }

  /* Preset buttons */
  .presets {
    margin-top: 20px; display: flex; gap: 8px; flex-wrap: wrap;
    justify-content: center;
  }
  .presets button {
    padding: 8px 14px; border: 2px solid #444; border-radius: 8px;
    background: transparent; color: #eee; cursor: pointer;
    font-size: 0.9em;
  }
  .presets button:hover { border-color: #888; }
</style>
</head>
<body>

<h1>LED 即時調色盤</h1>

<div class="picker-area">
  <div class="sv-box" id="svBox">
    <div class="sat-overlay"></div>
    <div class="val-overlay"></div>
    <div class="sv-cursor" id="svCursor"></div>
  </div>
  <div class="hue-bar" id="hueBar">
    <div class="hue-cursor" id="hueCursor"></div>
  </div>
</div>

<div class="info">
  <div class="preview" id="preview"></div>
  <div class="values" id="rgbText">R=255 G=0 B=0</div>
  <div class="values-small" id="hsvText">H=0 S=100 V=100</div>

  <div class="sliders">
    <div class="slider-row">
      <label style="color:#f66">R</label>
      <input type="range" class="r" id="sliderR" min="0" max="255" value="255">
      <span class="val" id="valR">255</span>
    </div>
    <div class="slider-row">
      <label style="color:#6f6">G</label>
      <input type="range" class="g" id="sliderG" min="0" max="255" value="0">
      <span class="val" id="valG">0</span>
    </div>
    <div class="slider-row">
      <label style="color:#66f">B</label>
      <input type="range" class="b" id="sliderB" min="0" max="255" value="0">
      <span class="val" id="valB">0</span>
    </div>
  </div>

  <div class="presets">
    <button onclick="setRGB(255,0,0)">紅</button>
    <button onclick="setRGB(255,64,0)">橘紅</button>
    <button onclick="setRGB(255,128,0)">橘</button>
    <button onclick="setRGB(255,200,0)">金黃</button>
    <button onclick="setRGB(255,255,0)">黃</button>
    <button onclick="setRGB(0,255,0)">綠</button>
    <button onclick="setRGB(0,255,255)">青</button>
    <button onclick="setRGB(0,0,255)">藍</button>
    <button onclick="setRGB(255,0,255)">紫</button>
    <button onclick="setRGB(255,255,255)">白</button>
    <button onclick="setRGB(0,0,0)">關</button>
  </div>

  <div class="status" id="status">拖動選色，即時預覽到 LED</div>
</div>

<script>
let H = 0, S = 1, V = 1;
let R = 255, G = 0, B = 0;
let sending = false;
let pendingColor = null;

const svBox = document.getElementById('svBox');
const svCursor = document.getElementById('svCursor');
const hueBar = document.getElementById('hueBar');
const hueCursor = document.getElementById('hueCursor');
const preview = document.getElementById('preview');
const rgbText = document.getElementById('rgbText');
const hsvText = document.getElementById('hsvText');
const sliderR = document.getElementById('sliderR');
const sliderG = document.getElementById('sliderG');
const sliderB = document.getElementById('sliderB');
const status = document.getElementById('status');

function hsvToRgb(h, s, v) {
  let r, g, b;
  const i = Math.floor(h * 6);
  const f = h * 6 - i;
  const p = v * (1 - s);
  const q = v * (1 - s * f);
  const t = v * (1 - s * (1 - f));
  switch (i % 6) {
    case 0: r=v; g=t; b=p; break;
    case 1: r=q; g=v; b=p; break;
    case 2: r=p; g=v; b=t; break;
    case 3: r=p; g=q; b=v; break;
    case 4: r=t; g=p; b=v; break;
    case 5: r=v; g=p; b=q; break;
  }
  return [Math.round(r*255), Math.round(g*255), Math.round(b*255)];
}

function rgbToHsv(r, g, b) {
  r/=255; g/=255; b/=255;
  const max=Math.max(r,g,b), min=Math.min(r,g,b), d=max-min;
  let h=0, s=max?d/max:0, v=max;
  if(d) {
    if(max===r) h=((g-b)/d+(g<b?6:0))/6;
    else if(max===g) h=((b-r)/d+2)/6;
    else h=((r-g)/d+4)/6;
  }
  return [h, s, v];
}

function updateFromHSV() {
  [R, G, B] = hsvToRgb(H, S, V);
  updateUI();
  sendToLED();
}

function updateFromRGB() {
  [H, S, V] = rgbToHsv(R, G, B);
  updateUI();
  sendToLED();
}

function updateUI() {
  preview.style.background = `rgb(${R},${G},${B})`;
  rgbText.textContent = `R=${R} G=${G} B=${B}`;
  hsvText.textContent = `H=${Math.round(H*360)} S=${Math.round(S*100)} V=${Math.round(V*100)}`;

  sliderR.value = R; document.getElementById('valR').textContent = R;
  sliderG.value = G; document.getElementById('valG').textContent = G;
  sliderB.value = B; document.getElementById('valB').textContent = B;

  // Update SV box hue background
  const [hr,hg,hb] = hsvToRgb(H, 1, 1);
  svBox.style.background = `rgb(${hr},${hg},${hb})`;

  // Update cursors
  svCursor.style.left = (S * 300) + 'px';
  svCursor.style.top = ((1 - V) * 300) + 'px';
  hueCursor.style.top = (H * 300) + 'px';
}

function sendToLED() {
  const color = {r: R, g: G, b: B, pattern: "solid", duration: 300};
  if (sending) { pendingColor = color; return; }
  sending = true;
  fetch('/led', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(color)
  }).then(r => r.json()).then(d => {
    status.textContent = d.ok ? `已送出 (${R},${G},${B})` : '送出失敗';
    sending = false;
    if (pendingColor) { const c = pendingColor; pendingColor = null; R=c.r; G=c.g; B=c.b; sendToLED(); }
  }).catch(e => {
    status.textContent = '連線錯誤';
    sending = false;
  });
}

function setRGB(r, g, b) {
  R=r; G=g; B=b;
  updateFromRGB();
}

// SV box drag
let svDragging = false;
function svMove(e) {
  const rect = svBox.getBoundingClientRect();
  const x = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
  const y = Math.max(0, Math.min(1, (e.clientY - rect.top) / rect.height));
  S = x; V = 1 - y;
  updateFromHSV();
}
svBox.addEventListener('mousedown', e => { svDragging=true; svMove(e); });
svBox.addEventListener('touchstart', e => { svDragging=true; svMove(e.touches[0]); e.preventDefault(); });
window.addEventListener('mousemove', e => { if(svDragging) svMove(e); });
window.addEventListener('touchmove', e => { if(svDragging) { svMove(e.touches[0]); e.preventDefault(); } }, {passive:false});
window.addEventListener('mouseup', () => svDragging=false);
window.addEventListener('touchend', () => svDragging=false);

// Hue bar drag
let hueDragging = false;
function hueMove(e) {
  const rect = hueBar.getBoundingClientRect();
  H = Math.max(0, Math.min(1, (e.clientY - rect.top) / rect.height));
  updateFromHSV();
}
hueBar.addEventListener('mousedown', e => { hueDragging=true; hueMove(e); });
hueBar.addEventListener('touchstart', e => { hueDragging=true; hueMove(e.touches[0]); e.preventDefault(); });
window.addEventListener('mousemove', e => { if(hueDragging) hueMove(e); });
window.addEventListener('touchmove', e => { if(hueDragging) { hueMove(e.touches[0]); e.preventDefault(); } }, {passive:false});
window.addEventListener('mouseup', () => hueDragging=false);
window.addEventListener('touchend', () => hueDragging=false);

// RGB sliders
sliderR.addEventListener('input', () => { R=+sliderR.value; updateFromRGB(); });
sliderG.addEventListener('input', () => { G=+sliderG.value; updateFromRGB(); });
sliderB.addEventListener('input', () => { B=+sliderB.value; updateFromRGB(); });

// Init
updateUI();
</script>
</body>
</html>
"""

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
        # 只顯示 POST 請求，不刷 GET log
        if "POST" in str(args):
            super().log_message(format, *args)


if __name__ == "__main__":
    port = 8888
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"LED 調色盤啟動: http://localhost:{port}")
    print(f"MQTT: {MQTT_HOST}:{MQTT_PORT}")
    print("Ctrl+C 結束")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n結束")
