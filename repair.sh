#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x /usr/local/sbin/whatsapp-remote ]]; then exec /usr/local/sbin/whatsapp-remote repair; fi
exec "$SCRIPT_DIR/install.sh" --repair --auto
