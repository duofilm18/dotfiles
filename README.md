# Dotfiles

個人開發環境配置檔案，用於快速設置 WSL + Docker 開發環境。

## 目錄結構

```
dotfiles/
├── docker/
│   ├── docker-compose.yml
│   ├── guardrails/
│   │   └── Dockerfile
│   └── python-dev/
│       └── Dockerfile
├── scripts/
│   └── safe-check.sh
├── shared/
├── windows/
└── wsl/
```

## 使用方式

### Docker 服務

```bash
cd ~/dotfiles/docker

# 啟動 Python 開發環境
docker compose --profile dev up -d

# 啟動 Guardrails AI
docker compose --profile ai up -d

# 進入 Python 開發容器
docker exec -it python-dev bash
```

### 安全審查工具

> 在執行危險指令前，先用 Ollama 審查

```bash
~/dotfiles/scripts/safe-check.sh "rm -rf /tmp/test"
```

需要先在 **Windows** 上啟動 Ollama。

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
