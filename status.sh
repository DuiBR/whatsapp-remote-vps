#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x /usr/local/sbin/whatsapp-remote ]]; then exec /usr/local/sbin/whatsapp-remote status; fi
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
require_root
show_status
