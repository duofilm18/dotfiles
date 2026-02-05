# Dotfiles

個人開發環境配置檔案，用於快速設置 WSL 開發環境。

## 目錄結構

```
dotfiles/
├── .claude/
│   └── skills/
│       └── add-hook.md
├── scripts/
│   ├── install-docker.sh
│   ├── install.sh
│   ├── qwen-advisor.sh
│   ├── safe-check.sh
│   ├── setup-claude-hooks.sh
│   └── update-readme.sh
├── shared/
│   ├── .tmux.conf
│   └── .vimrc
├── wsl/
│   ├── .bash_aliases
│   └── claude-hooks.json.example
├── CLAUDE.md
└── README.md
```

## 使用方式

### 快速安裝

```bash
git clone https://github.com/duofilm18/dotfiles.git ~/dotfiles
~/dotfiles/scripts/install.sh
```

### 安全審查工具

> 在執行危險指令前，先用 Ollama 審查

```bash
~/dotfiles/scripts/safe-check.sh "rm -rf /tmp/test"
```

需要先在 **Windows** 上啟動 Ollama。

### Claude Code Hooks（手機通知）

讓 Claude Code 在需要你注意時發送通知到手機。

```bash
# 1. 複製模板並修改設定
cp ~/dotfiles/wsl/claude-hooks.json.example ~/dotfiles/wsl/claude-hooks.json
vim ~/dotfiles/wsl/claude-hooks.json  # 修改 IP

# 2. 執行設定腳本
~/dotfiles/scripts/setup-claude-hooks.sh

# 3. 重啟 Claude Code
```

需要先在 rpi5b 上啟動 Apprise 服務。

---

## 慘案教訓

> 這些是用血淚換來的經驗，請務必遵守！

> **1. 重要資料要 git push**
>
> 本地的 git 歷史在重灌時會一起消失。只有 push 到 GitHub 的才是真正的備份。

```bash
git add .
git commit -m "update"
git push  # 這步不能忘！
```

> **2. 危險指令用 safe-check 審查**
>
> 在執行 `rm`、`prune`、`clean` 相關指令前，先審查。

**特別危險的指令：**
- `rm -rf` - 刪除檔案/目錄
- `docker system prune -a` - 清除所有 Docker 資源
- `git reset --hard` - 丟棄所有未提交的更改
- `chmod -R 777` - 危險的權限設定

> **3. Ollama 裝 Windows，不要裝 WSL**
>
> WSL 的 Ollama 會佔用大量記憶體，Windows 版本可以更好地利用 GPU。
> WSL 透過 `localhost:11434` 直接存取 Windows 的 Ollama。

---

## License

MIT
