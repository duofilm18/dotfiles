#!/usr/bin/env bats
# deploy_integrity.bats - 部署成品完整性靜態檢查
#
# 每個 @test 是一個「抗體」— 純靜態 grep / [ -f ]，< 1 秒。
# 新增 Ansible 管理的服務時，加一組對應的 DI-* 測試。

DOTFILES="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# ── WSL ime-mqtt-publisher 完整性 ──

@test "DI-1: ime-mqtt-publisher.sh 腳本存在" {
    [ -f "$DOTFILES/scripts/ime-mqtt-publisher.sh" ]
}

@test "DI-2: ime-mqtt-publisher.service.j2 template 存在" {
    [ -f "$DOTFILES/ansible/roles/wsl/templates/ime-mqtt-publisher.service.j2" ]
}

@test "DI-3: wsl role 有 deploy service task" {
    grep -q 'ime-mqtt-publisher.service' \
        "$DOTFILES/ansible/roles/wsl/tasks/main.yml"
}

@test "DI-4: wsl role 有 restart handler 對應 ime-mqtt-publisher" {
    grep -q 'Restart ime-mqtt-publisher' \
        "$DOTFILES/ansible/roles/wsl/handlers/main.yml"
}

# ── Pre-commit hook 由 Ansible 管理 ──

@test "DI-5: pre-commit hook 有跑 deploy_integrity" {
    grep -q 'deploy_integrity' \
        "$DOTFILES/ansible/roles/wsl/tasks/main.yml"
}

# ── Deploy marker（playbook post_tasks 寫入）──

@test "DI-6: wsl.yml 有 deploy marker post_task" {
    grep -q 'wsl-last-deploy' "$DOTFILES/ansible/wsl.yml"
}

@test "DI-7: rpi5b.yml 有 deploy marker post_task" {
    grep -q 'rpi5b-last-deploy' "$DOTFILES/ansible/rpi5b.yml"
}

# ── RPi5B mqtt-led role 存在 ──

@test "DI-8: rpi_mqtt_services role 存在" {
    [ -d "$DOTFILES/ansible/roles/rpi_mqtt_services" ]
}

# ── 每個 .service.j2 都有對應 restart handler ──

@test "DI-9: 每個 .service.j2 都有對應 restart handler" {
    local missing=""
    while IFS= read -r tmpl; do
        # 從 template 路徑取出 role 名稱
        local role_dir
        role_dir="$(dirname "$(dirname "$tmpl")")"
        local handler_file="$role_dir/handlers/main.yml"

        # 從 .service.j2 檔名取出 service 名稱
        local svc_name
        svc_name="$(basename "$tmpl" .service.j2)"

        if [ ! -f "$handler_file" ]; then
            missing="$missing\n  $tmpl → 缺 handlers/main.yml"
            continue
        fi

        # handler 檔案裡要有 restart/reload 該 service 的定義
        if ! grep -qi "restart.*$svc_name\|reload.*$svc_name\|$svc_name.*restart\|$svc_name.*reload" "$handler_file"; then
            missing="$missing\n  $tmpl → handlers 缺 restart/reload $svc_name"
        fi
    done < <(find "$DOTFILES/ansible/roles" -name '*.service.j2' -type f)

    if [ -n "$missing" ]; then
        echo -e "缺少 handler:$missing"
        return 1
    fi
}
