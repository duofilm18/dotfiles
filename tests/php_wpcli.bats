#!/usr/bin/env bats
# php_wpcli.bats - WSL dev-env health check: PHP 8.4 CLI + official WP-CLI.
# Provisioned by ansible/roles/wsl (tags: php, wp-cli). Re-runnable; run after
# `ansible-playbook wsl.yml --tags php,wp-cli`.

@test "php is on PATH" {
  run command -v php
  [ "$status" -eq 0 ]
}

@test "php default major.minor is 8.4" {
  run php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'
  [ "$status" -eq 0 ]
  [ "$output" = "8.4" ]
}

@test "wp (WP-CLI) is on PATH" {
  run command -v wp
  [ "$status" -eq 0 ]
}

@test "wp --version reports WP-CLI" {
  run wp --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"WP-CLI"* ]]
}
