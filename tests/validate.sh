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

grep -q 'PROJECT_VERSION="2.5.0"' lib/common.sh
grep -q 'new_install_menu' setup.sh
grep -q 'existing_install_menu' setup.sh
grep -q 'Reparar/atualizar preservando' setup.sh
grep -q 'Instalação manual/personalizada' setup.sh
grep -q 'collect_health_issues' lib/common.sh
grep -q 'SERVICE_BROWSER="whatsapp-browser.service"' lib/common.sh
grep -q 'recover_profile_dir' lib/common.sh
grep -q 'whatsapp_session_status' lib/common.sh
grep -q 'remote-debugging-address=127.0.0.1' lib/common.sh
grep -q 'whatsapp-status' manage.sh
grep -q 'show_health_summary compact' manage.sh
grep -q 'RISCO DE SEGURANÇA' lib/common.sh
grep -q 'Reinstalar tudo do zero' manage.sh
grep -q 'WHATSAPP_REMOTE_MENU_WRAPPER' lib/common.sh
grep -q 'WHATSAPP_REMOTE_MANAGER_WRAPPER' lib/common.sh
grep -q -- '--purge' uninstall.sh
grep -q '🩺 Painel de saúde e diagnóstico' README.md
grep -q 'Verificar se o WhatsApp está conectado' README.md

tmp_python="$(mktemp)"
awk '/<<'"'"'PYTHON'"'"'/{flag=1;next}/^PYTHON$/{if(flag){exit}}flag' lib/common.sh > "$tmp_python"
python3 -m py_compile "$tmp_python"
rm -f "$tmp_python" "${tmp_python}c" 2>/dev/null || true

echo "Validação estática concluída com sucesso."
