#!/usr/bin/env python3
"""LED 調色盤 + 暫存色板

從 rpi5b/mqtt-led/led-effects.json 讀取預設色，
調好的顏色可存到暫存色板（/tmp/led-palette.json），
Claude 可直接讀取後更新 led-effects.json。

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
PALETTE_PATH = Path("/tmp/led-palette.json")

# 載入 led-effects.json
EFFECTS_PATH = Path(__file__).parent.parent / "rpi5b" / "mqtt-led" / "led-effects.json"
with open(EFFECTS_PATH) as f:
    EFFECTS = json.load(f)


def build_buttons():
    buttons = []
    for domain, states in EFFECTS.items():
        if domain.startswith("_"):
            continue
        for state, effect in states.items():
            r, g, b = effect.get("r", 0), effect.get("g", 0), effect.get("b", 0)
            pattern = effect.get("pattern", "solid")
            luma = r * 0.299 + g * 0.587 + b * 0.114
            fg = "#000" if luma > 128 else "#fff"
            border = "#555" if r + g + b < 30 else f"rgb({r},{g},{b})"
            buttons.append(
                f'<button class="preset-btn" '
                f'style="background:rgb({r},{g},{b});color:{fg};border-color:{border}" '
                f'onclick="loadPreset(\'{domain}\',\'{state}\',{r},{g},{b})">'
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
<title>LED 調色盤</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, sans-serif;
    background: #1a1a2e; color: #eee;
    display: flex; flex-direction: column; align-items: center;
    min-height: 100vh; padding: 20px;
  }
  h1 { margin-bottom: 8px; font-size: 1.5em; }
  .subtitle { color: #888; margin-bottom: 20px; font-size: 0.9em; }
  .main { display: flex; gap: 32px; flex-wrap: wrap; justify-content: center; }

  .picker-col { display: flex; flex-direction: column; align-items: center; }
  .picker-area { display: flex; gap: 12px; }
  .sv-box {
    position: relative; width: 260px; height: 260px;
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
  .hue-bar {
    width: 24px; height: 260px; border-radius: 8px; cursor: pointer;
    background: linear-gradient(to bottom,
      hsl(0,100%,50%), hsl(60,100%,50%), hsl(120,100%,50%),
      hsl(180,100%,50%), hsl(240,100%,50%), hsl(300,100%,50%),
      hsl(360,100%,50%));
    position: relative;
  }
  .hue-cursor {
    position: absolute; left: -4px; width: 32px; height: 6px;
    border: 2px solid #fff; border-radius: 3px;
    box-shadow: 0 0 4px rgba(0,0,0,0.5);
    transform: translateY(-50%); pointer-events: none;
  }

  .info { margin-top: 16px; text-align: center; width: 100%; }
  .preview {
    width: 100%; height: 60px; border-radius: 10px;
    border: 3px solid #444; margin-bottom: 12px;
  }
  .values { font-size: 1.6em; font-family: monospace; font-weight: bold; user-select: all; }
  .values-small { font-size: 0.9em; color: #999; font-family: monospace; margin-top: 4px; }
  .json-hint {
    margin-top: 8px; font-size: 0.8em; color: #666; font-family: monospace;
    background: #111; padding: 6px 10px; border-radius: 6px; user-select: all;
  }

  .sliders { margin-top: 14px; width: 100%; }
  .slider-row { display: flex; align-items: center; gap: 8px; margin: 4px 0; }
  .slider-row label { width: 16px; font-weight: bold; font-size: 1em; }
  .slider-row input[type=range] { flex: 1; height: 6px; }
  .slider-row .val { width: 36px; text-align: right; font-family: monospace; font-size: 0.9em; }
  input.r { accent-color: #ff4444; }
  input.g { accent-color: #44ff44; }
  input.b { accent-color: #4444ff; }
  input.v { accent-color: #ffffff; }

  /* 儲存按鈕 */
  .save-row {
    margin-top: 12px; display: flex; gap: 8px; width: 100%;
  }
  .save-row input {
    flex: 1; padding: 6px 10px; border-radius: 6px; border: 1px solid #555;
    background: #111; color: #eee; font-family: monospace; font-size: 0.9em;
  }
  .save-row button {
    padding: 6px 16px; border-radius: 6px; border: 2px solid #4caf50;
    background: transparent; color: #4caf50; cursor: pointer; font-weight: bold;
  }
  .save-row button:hover { background: #4caf50; color: #000; }

  /* 右側 */
  .right-col { display: flex; flex-direction: column; gap: 16px; max-width: 340px; }
  .presets-title { font-size: 1em; color: #aaa; margin-bottom: 4px; }
  .presets-grid {
    display: grid; grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .preset-btn {
    padding: 10px 8px; border: 2px solid; border-radius: 10px;
    cursor: pointer; display: flex; flex-direction: column;
    align-items: center; gap: 2px; transition: transform 0.1s;
  }
  .preset-btn:hover { transform: scale(1.05); }
  .preset-btn:active { transform: scale(0.95); }
  .preset-btn .domain { font-size: 0.65em; opacity: 0.7; text-transform: uppercase; }
  .preset-btn .state-name { font-size: 1.1em; font-weight: bold; }
  .preset-btn .pattern { font-size: 0.75em; opacity: 0.7; }
  .preset-btn .rgb { font-size: 0.65em; opacity: 0.5; font-family: monospace; }

  /* 暫存色板 */
  .palette-section { width: 100%; }
  .palette-title { font-size: 1em; color: #aaa; margin-bottom: 8px; }
  .palette-list { display: flex; flex-direction: column; gap: 6px; }
  .palette-item {
    display: flex; align-items: center; gap: 8px;
    background: #16213e; border-radius: 8px; padding: 6px 10px;
  }
  .palette-swatch {
    width: 32px; height: 32px; border-radius: 6px; border: 2px solid #444;
    cursor: pointer; flex-shrink: 0;
  }
  .palette-swatch:hover { transform: scale(1.1); }
  .palette-label { flex: 1; font-family: monospace; font-size: 0.85em; }
  .palette-rgb { color: #888; font-family: monospace; font-size: 0.8em; }
  .palette-del {
    background: none; border: none; color: #f44; cursor: pointer;
    font-size: 1.2em; padding: 0 4px;
  }
  .palette-del:hover { color: #f88; }
  .palette-empty { color: #555; font-size: 0.85em; font-style: italic; }
  .palette-actions { margin-top: 8px; display: flex; gap: 8px; }
  .palette-actions button {
    padding: 6px 14px; border-radius: 6px; border: 1px solid #555;
    background: #111; color: #ccc; cursor: pointer; font-size: 0.85em;
  }
  .palette-actions button:hover { background: #333; }
  .copy-ok { color: #4caf50 !important; border-color: #4caf50 !important; }

  .status {
    margin-top: 16px; padding: 8px 20px; width: 100%; max-width: 720px;
    background: #16213e; border-radius: 8px; text-align: center;
    font-family: monospace; font-size: 0.85em;
  }
  .status.ok { border-left: 4px solid #4caf50; }
  .status.err { border-left: 4px solid #f44336; }
</style>
</head>
<body>

<h1>LED 調色盤</h1>
<p class="subtitle">MQTT: MQTT_HOST_PLACEHOLDER:MQTT_PORT_PLACEHOLDER</p>

<div class="main">
  <div class="picker-col">
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
      <div class="json-hint" id="jsonHint">"r": 255, "g": 0, "b": 0</div>
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
        <div class="slider-row">
          <label style="color:#fff">V</label>
          <input type="range" class="v" id="sliderV" min="0" max="100" value="100">
          <span class="val" id="valV">100</span>
        </div>
      </div>
      <div class="save-row">
        <input type="text" id="saveLabel" placeholder="標籤 (如 claude/idle)">
        <button onclick="saveToPalette()">存入色板</button>
      </div>
    </div>
  </div>

  <div class="right-col">
    <div>
      <div class="presets-title">led-effects.json (current)</div>
      <div class="presets-grid">
        BUTTONS_PLACEHOLDER
      </div>
    </div>

    <div class="palette-section">
      <div class="palette-title">暫存色板</div>
      <div class="palette-list" id="paletteList">
        <div class="palette-empty">尚無儲存的顏色</div>
      </div>
      <div class="palette-actions">
        <button onclick="copyPalette()">複製 JSON</button>
        <button onclick="clearPalette()">清空</button>
      </div>
    </div>
  </div>
</div>

<div class="status" id="status">調好顏色 → 存入色板 → 跟 Claude 說「更新 led-effects.json」</div>

<script>
let H=0, S=1, V=1, R=255, G=0, B=0;
let sending=false, pendingColor=null, currentLabel='';
let palette = [];

const svBox=document.getElementById('svBox'), svCursor=document.getElementById('svCursor');
const hueBar=document.getElementById('hueBar'), hueCursor=document.getElementById('hueCursor');
const preview=document.getElementById('preview'), rgbText=document.getElementById('rgbText');
const hsvText=document.getElementById('hsvText'), jsonHint=document.getElementById('jsonHint');
const sliderR=document.getElementById('sliderR'), sliderG=document.getElementById('sliderG');
const sliderB=document.getElementById('sliderB'), sliderV=document.getElementById('sliderV');
const status=document.getElementById('status');

function hsvToRgb(h,s,v){let r,g,b;const i=Math.floor(h*6),f=h*6-i,p=v*(1-s),q=v*(1-s*f),t=v*(1-s*(1-f));switch(i%6){case 0:r=v;g=t;b=p;break;case 1:r=q;g=v;b=p;break;case 2:r=p;g=v;b=t;break;case 3:r=p;g=q;b=v;break;case 4:r=t;g=p;b=v;break;case 5:r=v;g=p;b=q;break;}return[Math.round(r*255),Math.round(g*255),Math.round(b*255)];}
function rgbToHsv(r,g,b){r/=255;g/=255;b/=255;const max=Math.max(r,g,b),min=Math.min(r,g,b),d=max-min;let h=0,s=max?d/max:0,v=max;if(d){if(max===r)h=((g-b)/d+(g<b?6:0))/6;else if(max===g)h=((b-r)/d+2)/6;else h=((r-g)/d+4)/6;}return[h,s,v];}

function updateFromHSV(){[R,G,B]=hsvToRgb(H,S,V);updateUI();sendToLED();}
function updateFromRGB(){[H,S,V]=rgbToHsv(R,G,B);updateUI();sendToLED();}

function updateUI(){
  preview.style.background=`rgb(${R},${G},${B})`;
  rgbText.textContent=`R=${R} G=${G} B=${B}`;
  hsvText.textContent=`H=${Math.round(H*360)} S=${Math.round(S*100)} V=${Math.round(V*100)}`;
  jsonHint.textContent=`"r": ${R}, "g": ${G}, "b": ${B}`;
  sliderR.value=R;document.getElementById('valR').textContent=R;
  sliderG.value=G;document.getElementById('valG').textContent=G;
  sliderB.value=B;document.getElementById('valB').textContent=B;
  sliderV.value=Math.round(V*100);document.getElementById('valV').textContent=Math.round(V*100);
  const[hr,hg,hb]=hsvToRgb(H,1,1);
  svBox.style.background=`rgb(${hr},${hg},${hb})`;
  svCursor.style.left=(S*260)+'px';svCursor.style.top=((1-V)*260)+'px';
  hueCursor.style.top=(H*260)+'px';
}

function sendToLED(){
  const payload={domain:"raw",state:"",project:"",r:R,g:G,b:B,pattern:"solid",duration:0};
  if(sending){pendingColor=payload;return;}
  sending=true;
  fetch('/led',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)})
  .then(r=>r.json()).then(d=>{
    status.textContent=d.ok?`LED: (${R},${G},${B})${currentLabel?' - '+currentLabel:''}`:'送出失敗';
    status.className='status ok';sending=false;
    if(pendingColor){const c=pendingColor;pendingColor=null;R=c.r;G=c.g;B=c.b;sendToLED();}
  }).catch(()=>{status.textContent='連線錯誤';status.className='status err';sending=false;});
}

function loadPreset(domain,state,r,g,b){
  R=r;G=g;B=b;currentLabel=domain+'/'+state;
  document.getElementById('saveLabel').value=currentLabel;
  updateFromRGB();
}

// ── 暫存色板 ──
function saveToPalette(){
  const label=document.getElementById('saveLabel').value.trim()||`色${palette.length+1}`;
  palette.push({label,r:R,g:G,b:B});
  document.getElementById('saveLabel').value='';
  renderPalette();
  // 存到 server
  fetch('/palette',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify(palette)})
  .then(r=>r.json()).then(d=>{
    status.textContent=d.ok?`已存: ${label} (${R},${G},${B})`:'存檔失敗';
    status.className='status ok';
  });
}

function deletePaletteItem(idx){
  palette.splice(idx,1);
  renderPalette();
  fetch('/palette',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(palette)});
}

function loadPaletteItem(idx){
  const c=palette[idx];
  R=c.r;G=c.g;B=c.b;currentLabel=c.label;
  document.getElementById('saveLabel').value=c.label;
  updateFromRGB();
}

function renderPalette(){
  const el=document.getElementById('paletteList');
  if(!palette.length){el.innerHTML='<div class="palette-empty">尚無儲存的顏色</div>';return;}
  el.innerHTML=palette.map((c,i)=>{
    const luma=c.r*0.299+c.g*0.587+c.b*0.114;
    return`<div class="palette-item">
      <div class="palette-swatch" style="background:rgb(${c.r},${c.g},${c.b})" onclick="loadPaletteItem(${i})"></div>
      <span class="palette-label">${c.label}</span>
      <span class="palette-rgb">(${c.r},${c.g},${c.b})</span>
      <button class="palette-del" onclick="deletePaletteItem(${i})">x</button>
    </div>`;
  }).join('');
}

function copyPalette(){
  const obj={};
  palette.forEach(c=>{
    const parts=c.label.split('/');
    if(parts.length===2){
      if(!obj[parts[0]])obj[parts[0]]={};
      obj[parts[0]][parts[1]]={r:c.r,g:c.g,b:c.b};
    }else{
      if(!obj['custom'])obj['custom']={};
      obj['custom'][c.label]={r:c.r,g:c.g,b:c.b};
    }
  });
  const text=JSON.stringify(obj,null,2);
  navigator.clipboard.writeText(text).then(()=>{
    const btn=document.querySelector('.palette-actions button');
    btn.classList.add('copy-ok');btn.textContent='已複製!';
    setTimeout(()=>{btn.classList.remove('copy-ok');btn.textContent='複製 JSON';},1500);
  });
}

function clearPalette(){
  if(!confirm('確定清空暫存色板?'))return;
  palette=[];renderPalette();
  fetch('/palette',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify([])});
}

// SV drag
let svDrag=false;
function svMove(e){const rect=svBox.getBoundingClientRect();S=Math.max(0,Math.min(1,(e.clientX-rect.left)/rect.width));V=1-Math.max(0,Math.min(1,(e.clientY-rect.top)/rect.height));currentLabel='';updateFromHSV();}
svBox.addEventListener('mousedown',e=>{svDrag=true;svMove(e);});
svBox.addEventListener('touchstart',e=>{svDrag=true;svMove(e.touches[0]);e.preventDefault();});
window.addEventListener('mousemove',e=>{if(svDrag)svMove(e);});
window.addEventListener('touchmove',e=>{if(svDrag){svMove(e.touches[0]);e.preventDefault();}},{passive:false});
window.addEventListener('mouseup',()=>svDrag=false);
window.addEventListener('touchend',()=>svDrag=false);

// Hue drag
let hueDrag=false;
function hueMove(e){const rect=hueBar.getBoundingClientRect();H=Math.max(0,Math.min(1,(e.clientY-rect.top)/rect.height));currentLabel='';updateFromHSV();}
hueBar.addEventListener('mousedown',e=>{hueDrag=true;hueMove(e);});
hueBar.addEventListener('touchstart',e=>{hueDrag=true;hueMove(e.touches[0]);e.preventDefault();});
window.addEventListener('mousemove',e=>{if(hueDrag)hueMove(e);});
window.addEventListener('touchmove',e=>{if(hueDrag){hueMove(e.touches[0]);e.preventDefault();}},{passive:false});
window.addEventListener('mouseup',()=>hueDrag=false);
window.addEventListener('touchend',()=>hueDrag=false);

// RGB sliders
sliderR.addEventListener('input',()=>{R=+sliderR.value;currentLabel='';updateFromRGB();});
sliderG.addEventListener('input',()=>{G=+sliderG.value;currentLabel='';updateFromRGB();});
sliderB.addEventListener('input',()=>{B=+sliderB.value;currentLabel='';updateFromRGB();});
sliderV.addEventListener('input',()=>{V=+sliderV.value/100;currentLabel='';updateFromHSV();});

// 載入已存的色板
fetch('/palette').then(r=>r.json()).then(d=>{palette=d;renderPalette();}).catch(()=>{});

updateUI();
</script>
</body>
</html>
""".replace("BUTTONS_PLACEHOLDER", build_buttons()) \
   .replace("MQTT_HOST_PLACEHOLDER", MQTT_HOST) \
   .replace("MQTT_PORT_PLACEHOLDER", MQTT_PORT)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/palette":
            data = json.loads(PALETTE_PATH.read_text()) if PALETTE_PATH.exists() else []
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode())

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        if self.path == "/palette":
            try:
                data = json.loads(body)
                PALETTE_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False))
                self._json_ok()
            except Exception as e:
                self._json_err(str(e))

        elif self.path == "/led":
            try:
                data = json.loads(body)
                subprocess.run(
                    ["mosquitto_pub", "-h", MQTT_HOST, "-p", MQTT_PORT,
                     "-t", "claude/led", "-m", json.dumps(data)],
                    timeout=3, capture_output=True,
                )
                self._json_ok()
            except Exception as e:
                self._json_err(str(e))
        else:
            self.send_response(404)
            self.end_headers()

    def _json_ok(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def _json_err(self, msg):
        self.send_response(500)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"ok": False, "error": msg}).encode())

    def log_message(self, format, *args):
        if "POST" in str(args):
            super().log_message(format, *args)


if __name__ == "__main__":
    port = 8888
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"LED 調色盤: http://localhost:{port}")
    print(f"MQTT: {MQTT_HOST}:{MQTT_PORT}")
    print(f"暫存色板: {PALETTE_PATH}")
    print(f"狀態來源: {EFFECTS_PATH}")
    domains = {d: len(s) for d, s in EFFECTS.items() if not d.startswith("_")}
    print(f"載入: {domains}")
    print("Ctrl+C 結束")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n結束")
