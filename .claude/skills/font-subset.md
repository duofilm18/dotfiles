---
name: font-subset
description: >
  Noto Sans TC 字型 subset 流程。當需要重新產生 subset woff2、
  新增內容含罕見字、或修改字型 CSS 設定時使用。
---

# Font Subset — Noto Sans TC

## 目的

將完整 Noto Sans TC 變體字型（~12MB TTF）裁切為僅包含網站實際使用文字的 subset woff2，大幅降低字型檔大小與 HTTP 請求數。

## 前置條件

```bash
pip install fonttools brotli
```

## 使用方式

```bash
cd ~/landtw

# 1. 確認原始字型存在（只需下載一次）
mkdir -p fonts-src
curl -L -o fonts-src/NotoSansTC-VF.ttf \
  "https://github.com/google/fonts/raw/main/ofl/notosanstc/NotoSansTC%5Bwght%5D.ttf"

# 2. 執行 subset
python3 scripts/subset-font.py

# 3. 驗證
hugo server  # 檢查字型顯示正常
```

## 腳本流程（`scripts/subset-font.py`）

1. 確認 `fonts-src/NotoSansTC-VF.ttf` 存在
2. 執行 `hugo --minify` 產生 `public/`
3. 掃描所有 `public/**/*.html`，strip HTML tags，收集 unique 字元
4. 加入保底字元（ASCII 0x20–0x7E + 常用中文標點）
5. 用 `pyftsubset` 切出 `static/fonts/noto-sans-tc-subset.woff2`
6. 印出 before/after 大小

## 何時需要重跑

- 新增內容含有之前未出現的中文字（例如新文章使用罕見字）
- 更換字型來源
- 修改字型 CSS 設定

## 注意事項

- `fonts-src/` 已加入 `.gitignore`，原始 TTF 不進 repo
- subset 產出 `static/fonts/noto-sans-tc-subset.woff2` **需要 commit**
- `assets/css/fonts.css` 只有 1 條 `@font-face`，指向 subset 檔案
- `font-display: optional` 避免 FOIT（Flash of Invisible Text）
