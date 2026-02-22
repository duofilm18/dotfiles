#!/bin/bash
# install-lighthouse.sh - 安裝 Lighthouse CLI 及其依賴（Chromium）
# 用法: ~/dotfiles/scripts/install-lighthouse.sh
# 安裝後可在任何專案使用 /lighthouse skill

set -e

echo "=========================================="
echo "  安裝 Lighthouse + Chromium"
echo "=========================================="

# 1. 安裝 Chromium 所需的系統函式庫
echo ""
echo "📦 安裝 Chromium 系統依賴..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    libnspr4 \
    libnss3 \
    libatk1.0-0t64 \
    libatk-bridge2.0-0t64 \
    libcups2t64 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2t64 \
    libxshmfence1 \
    libx11-xcb1 \
    libxcb-dri3-0 \
    2>/dev/null || true

# 2. 用 Puppeteer 下載 Chromium
echo ""
echo "🌐 下載 Chromium（via Puppeteer）..."
CHROME_PATH=$(npx puppeteer browsers install chrome 2>&1 | grep -oP '/.+/chrome$' || true)

if [ -z "$CHROME_PATH" ]; then
    # 嘗試找已安裝的
    CHROME_PATH=$(find "$HOME/.cache/puppeteer" -name "chrome" -type f 2>/dev/null | head -1)
fi

if [ -z "$CHROME_PATH" ]; then
    echo "❌ Chromium 安裝失敗"
    exit 1
fi

echo "  Chromium 路徑: $CHROME_PATH"

# 3. 驗證 Chromium 可以啟動
echo ""
echo "🧪 驗證 Chromium..."
if $CHROME_PATH --headless --no-sandbox --disable-gpu --dump-dom about:blank 2>/dev/null | grep -q "html"; then
    echo "  ✅ Chromium 正常運作"
else
    echo "  ⚠️  Chromium 啟動失敗，可能缺少系統函式庫"
    echo "  嘗試: $CHROME_PATH --headless --no-sandbox --disable-gpu --dump-dom about:blank"
    echo "  看錯誤訊息找出缺少的 .so 檔"
fi

# 4. 安裝 Lighthouse CLI
echo ""
echo "🔦 安裝 Lighthouse CLI..."
npm list -g lighthouse &>/dev/null || npm install -g lighthouse
LIGHTHOUSE_VERSION=$(npx lighthouse --version 2>/dev/null)
echo "  Lighthouse 版本: $LIGHTHOUSE_VERSION"

# 5. 寫入環境變數供 skill 使用
echo ""
echo "📝 設定 CHROME_PATH 環境變數..."
BASHRC="$HOME/.bashrc"
if ! grep -q "CHROME_PATH" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# Lighthouse Chromium path (installed by install-lighthouse.sh)" >> "$BASHRC"
    echo "export CHROME_PATH=\"$CHROME_PATH\"" >> "$BASHRC"
    echo "  已寫入 ~/.bashrc"
else
    # 更新現有的 CHROME_PATH
    sed -i "s|export CHROME_PATH=.*|export CHROME_PATH=\"$CHROME_PATH\"|" "$BASHRC"
    echo "  已更新 ~/.bashrc"
fi

echo ""
echo "=========================================="
echo "  ✅ Lighthouse 安裝完成！"
echo "=========================================="
echo ""
echo "使用方式："
echo "  1. source ~/.bashrc"
echo "  2. 在專案目錄執行 /lighthouse"
echo ""
echo "手動跑："
echo "  CHROME_PATH=\"$CHROME_PATH\" npx lighthouse <URL> \\"
echo "    --chrome-flags=\"--headless --no-sandbox --disable-gpu\" \\"
echo "    --only-categories=performance"
echo ""
