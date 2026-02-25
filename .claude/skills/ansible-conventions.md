---
name: ansible-conventions
description: >
  Ansible playbook 撰寫規範。新增/修改 Ansible task、role、變數時必須遵守。
---

# Ansible 撰寫規範

## 核心原則

**所有環境變更必須透過 Ansible**，禁止 SSH 手動修改。

## 變數引用

- **用** `ansible_facts.user_dir` — 取得 HOME 目錄
- **不用** `ansible_env.HOME` — ansible-core 2.24 會移除 INJECT_FACTS_AS_VARS

```yaml
# ✅ 正確
dest: "{{ ansible_facts.user_dir }}/.vimrc"

# ❌ 禁止
dest: "{{ ansible_env.HOME }}/.vimrc"
```

## Python 套件安裝（pip）

**一律用 venv**，禁止 `--break-system-packages`。

### WSL

```yaml
- name: Install Python dev dependencies
  ansible.builtin.pip:
    requirements: "{{ dotfiles_local }}/requirements-dev.txt"
    virtualenv: "{{ dotfiles_local }}/.venv"
    virtualenv_command: python3 -m venv
```

apt 清單需包含 `python3-pip` + `python3-venv`。

### RPi

```yaml
- name: Install service requirements
  ansible.builtin.pip:
    requirements: "{{ service_dir }}/requirements.txt"
    virtualenv: "{{ service_dir }}/venv"
    virtualenv_command: python3 -m venv --system-site-packages
```

- **`--system-site-packages`** — 繼承 apt 裝的 paho-mqtt、gpiozero 等，不重複安裝
- apt 清單需包含 `python3-venv`

### systemd ExecStart

用 venv 的 python，不用系統 python：

```ini
# ✅ 正確
ExecStart={{ service_dir }}/venv/bin/python {{ service_dir }}/main.py

# ❌ 禁止
ExecStart=/usr/bin/python3 {{ service_dir }}/main.py
```

## 檔案權限

只對需要執行的副檔名加權限：

```yaml
# ✅ 正確
- name: Make scripts executable
  ansible.builtin.shell: chmod u+x {{ dotfiles_local }}/scripts/*.sh {{ dotfiles_local }}/scripts/*.py
  changed_when: false

# ❌ 禁止（會讓 .md、.json 等全部變可執行）
- name: Make scripts executable
  ansible.builtin.file:
    path: "{{ dotfiles_local }}/scripts"
    mode: "u+x"
    recurse: true
```

## 模組參數

| 模組 | 禁止 | 替代 |
|------|------|------|
| `get_url` | `creates`（已移除） | `force: false` |
| `git` | `creates`（已移除） | `update: false` |
| `pip` | `extra_args: --break-system-packages` | `virtualenv:` |

## Callback 設定

```ini
# ansible.cfg — 不用 community.general yaml callback（12.x 已移除）
stdout_callback = default
[callback_default]
result_format = yaml
```
