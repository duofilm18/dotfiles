# Lighthouse 效能測試

## 測試 URL

- **Hugo 站（workers.dev）**：`https://landtw-v2.duofilm18.workers.dev/`
- **正式站（WordPress）**：`https://landtw.com`（目前仍是 WP，未來切換到 Hugo）

測效能改善時用 workers.dev URL，不要打 landtw.com（那是 WordPress）。

## 執行方式

### 1. WSL Puppeteer（推薦）

WSL 沒裝 Chrome，用 Puppeteer 自帶 Chromium 跑：

```bash
cd ~/landtw
npm install puppeteer lighthouse  # 只需裝一次
```

```js
// scripts/lighthouse.mjs
import puppeteer from 'puppeteer';
import lighthouse from 'lighthouse';

const url = process.argv[2] || 'https://landtw-v2.duofilm18.workers.dev/';
const browser = await puppeteer.launch({
  headless: 'new',
  args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
});
const { lhr } = await lighthouse(url, {
  port: new URL(browser.wsEndpoint()).port,
  output: 'json',
  onlyCategories: ['performance'],
});

console.log('Performance Score:', lhr.categories.performance.score * 100);
const keys = ['first-contentful-paint', 'largest-contentful-paint',
  'total-blocking-time', 'cumulative-layout-shift', 'speed-index'];
keys.forEach(k => {
  const a = lhr.audits[k];
  if (a) console.log(`${a.title}: ${a.displayValue}`);
});

await browser.close();
```

```bash
node scripts/lighthouse.mjs
node scripts/lighthouse.mjs "https://landtw-v2.duofilm18.workers.dev/代書收費標準/"
```

### 2. Chrome DevTools

1. 開啟 Chrome → F12 → Lighthouse 分頁
2. 選 Performance → Mobile → Analyze

### 3. PageSpeed Insights 網頁

https://pagespeed.web.dev/analysis?url=https://landtw-v2.duofilm18.workers.dev/

### 4. PSI API（有 quota 限制）

```bash
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=https://landtw-v2.duofilm18.workers.dev/&category=PERFORMANCE&strategy=MOBILE"
```

免費 quota 用完會回 429，需等隔天重置或申請提高額度。

## 重點指標

| 指標 | 目標 | 說明 |
|------|------|------|
| Performance Score | ≥ 90 | 綜合分數 |
| FCP | < 1.8s | First Contentful Paint |
| LCP | < 2.5s | Largest Contentful Paint |
| TBT | < 200ms | Total Blocking Time |
| CLS | < 0.1 | Cumulative Layout Shift |

## 字型相關審計項目

- **Font display** — `font-display: optional` 避免 FOIT
- **Total byte weight** — subset 後字型應 < 600KB
- **Network requests** — 字型請求應為 1 個（subset woff2）
