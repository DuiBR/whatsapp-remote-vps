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

for script in setup.sh install.sh manage.sh repair.sh status.sh uninstall.sh lib/common.sh; do
  bash -n "$script"
done

sha256sum -c MANIFEST.sha256

grep -q 'PROJECT_VERSION="2.3.0"' lib/common.sh
grep -q 'WHATSAPP_REMOTE_MENU_WRAPPER' lib/common.sh
grep -q 'reinstall_from_scratch' manage.sh
grep -q -- '--purge' uninstall.sh

echo "Validação estática concluída com sucesso."
