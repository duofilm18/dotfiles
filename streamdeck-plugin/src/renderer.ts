import { STATE_DISPLAY, DATE_DISPLAY, type StateDisplay } from "./types";

function rgbStr(c: [number, number, number]): string {
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

function escapeXml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** 狀態按鍵 SVG：上方專案名、中間狀態標籤 */
export function renderStatusSvg(project: string, display: StateDisplay): string {
  const bg = rgbStr(display.bg);
  const fg = rgbStr(display.fg);
  const title = escapeXml(project.slice(0, 10));
  const label = escapeXml(display.label);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144">\
<rect width="144" height="144" fill="${bg}"/>\
<text x="72" y="36" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="22" fill="${fg}">${title}</text>\
<text x="72" y="77" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="26" font-weight="bold" fill="${fg}">${label}</text>\
</svg>`;
}

/** 日期按鍵 SVG：YYYY 上半、MMDD 下半 */
export function renderDateSvg(): string {
  const now = new Date();
  const yyyy = now.getFullYear().toString();
  const mmdd =
    (now.getMonth() + 1).toString().padStart(2, "0") +
    now.getDate().toString().padStart(2, "0");
  const bg = rgbStr(DATE_DISPLAY.bg);
  const fg = rgbStr(DATE_DISPLAY.fg);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144">\
<rect width="144" height="144" fill="${bg}"/>\
<text x="72" y="48" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="32" font-weight="bold" fill="${fg}">${yyyy}</text>\
<text x="72" y="96" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="32" font-weight="bold" fill="${fg}">${mmdd}</text>\
</svg>`;
}

/** 系統狀態按鍵 SVG：RPi5B 標題 / 溫度（色溫） / RAM% */
export function renderSysStatsSvg(temp: number, ram: number): string {
  // 溫度色碼：<50 綠、50-64 黃、≥65 紅
  let tempColor: string;
  if (temp >= 65) tempColor = "rgb(255,60,60)";
  else if (temp >= 50) tempColor = "rgb(255,220,0)";
  else tempColor = "rgb(0,210,80)";

  return `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144">\
<rect width="144" height="144" fill="rgb(30,30,30)"/>\
<text x="72" y="28" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="16" fill="rgb(160,160,160)">RPi5B</text>\
<text x="72" y="72" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="36" font-weight="bold" fill="${tempColor}">${temp}\u00B0C</text>\
<text x="72" y="116" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="20" fill="rgb(255,255,255)">RAM ${ram}%</text>\
</svg>`;
}

/** Windows PC 狀態按鍵 SVG：標題 / 溫度（色溫） / 頻率 / RAM% */
export function renderWinStatsSvg(temp: number, freq: number, ram: number): string {
  // 桌機溫度色碼：<65 綠、65-79 黃、≥80 紅
  let tempColor: string;
  if (temp >= 80) tempColor = "rgb(255,60,60)";
  else if (temp >= 65) tempColor = "rgb(255,220,0)";
  else tempColor = "rgb(0,210,80)";

  const ghz = (freq / 1000).toFixed(1);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144">\
<rect width="144" height="144" fill="rgb(30,30,30)"/>\
<text x="72" y="24" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="16" fill="rgb(160,160,160)">Win PC</text>\
<text x="72" y="58" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="32" font-weight="bold" fill="${tempColor}">${temp}\u00B0C</text>\
<text x="72" y="92" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="18" fill="rgb(255,255,255)">${ghz} GHz</text>\
<text x="72" y="122" text-anchor="middle" dominant-baseline="middle" \
font-family="Arial,sans-serif" font-size="18" fill="rgb(255,255,255)">RAM ${ram}%</text>\
</svg>`;
}

/** 暗灰色空按鍵 SVG */
export function renderOffSvg(): string {
  return renderStatusSvg("", STATE_DISPLAY.off);
}

/** 把 SVG 字串轉成 data URI（供 setImage 使用） */
export function svgToDataUri(svg: string): string {
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}
