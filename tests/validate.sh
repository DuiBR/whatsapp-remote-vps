#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required=(
  setup.sh install.sh manage.sh repair.sh status.sh uninstall.sh lib/common.sh
  README.md CHANGELOG.md VERSION MANIFEST.sha256
)

for file in "${required[@]}"; do
  [[ -s "$file" ]] || { echo "Arquivo obrigatório ausente: $file" >&2; exit 1; }
done

for script in setup.sh install.sh manage.sh repair.sh status.sh uninstall.sh lib/common.sh tests/validate.sh; do
  bash -n "$script"
done

sha256sum -c MANIFEST.sha256

grep -q 'PROJECT_VERSION="2.4.0"' lib/common.sh
grep -q 'new_install_menu' setup.sh
grep -q 'existing_install_menu' setup.sh
grep -q 'Reparar/atualizar preservando' setup.sh
grep -q 'Instalação manual/personalizada' setup.sh
grep -q 'collect_health_issues' lib/common.sh
grep -q 'show_health_summary compact' manage.sh
grep -q 'RISCO DE SEGURANÇA' lib/common.sh
grep -q 'Reinstalar tudo do zero' manage.sh
grep -q 'WHATSAPP_REMOTE_MENU_WRAPPER' lib/common.sh
grep -q 'WHATSAPP_REMOTE_MANAGER_WRAPPER' lib/common.sh
grep -q -- '--purge' uninstall.sh
grep -q '🩺 Painel de saúde e diagnóstico' README.md

echo "Validação estática concluída com sucesso."
