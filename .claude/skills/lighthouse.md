# Lighthouse 效能測試

## 環境限制

- **WSL 沒有裝 Chrome**，`npx lighthouse` 會失敗（`Unable to connect to Chrome`）
- **PageSpeed Insights API** 免費額度容易用完（429 RATE_LIMIT_EXCEEDED）
- 用戶本機（Windows）可直接跑 Lighthouse

## 執行方式

### 1. 本機 CLI（推薦）

```bash
npx lighthouse https://landtw.com \
  --output=json --output-path=lighthouse.json \
  --chrome-flags="--headless --no-sandbox" \
  --only-categories=performance
```

### 2. Chrome DevTools

1. 開啟 Chrome → F12 → Lighthouse 分頁
2. 選 Performance → Mobile → Analyze

### 3. PageSpeed Insights 網頁

https://pagespeed.web.dev/analysis?url=https://landtw.com

### 4. PSI API（有 quota 限制）

```bash
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=https://landtw.com&category=PERFORMANCE&strategy=MOBILE"
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
